import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

class SessioneUtente {
  final String orgId;
  final String orgNome;
  final bool isMaster;
  final String email;
  final String permessi;

  const SessioneUtente({
    required this.orgId,
    required this.orgNome,
    required this.isMaster,
    required this.email,
    this.permessi = 'pieno_accesso',
  });
}

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  bool _inizializzato = false;

  bool get isReady => _inizializzato && SupabaseConfig.isConfigured;

  SupabaseClient get client => Supabase.instance.client;

  Future<void> initialize() async {
    if (!SupabaseConfig.isConfigured) return;
    if (_inizializzato) return;

    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
    _inizializzato = true;
  }

  String normEmail(String email) => email.trim().toLowerCase();

  Future<bool> esisteAlmenoUnOrganizzazione() async {
    final res = await client.from('organizzazioni').select('id').limit(1);
    return (res as List).isNotEmpty;
  }

  bool _isRateLimit(AuthException e) =>
      e.code == 'over_email_send_rate_limit' ||
      e.statusCode == '429' ||
      e.message.contains('429') ||
      e.message.contains('3 seconds');

  Never _rilanciaAuth(AuthException e) {
    if (_isRateLimit(e)) {
      throw Exception(
        'Troppe prove ravvicinate. Aspetta 1 minuto, poi usa ACCEDI con la stessa email '
        '(l\'account potrebbe essere già stato creato).',
      );
    }
    if (e.message.toLowerCase().contains('already registered') || e.code == 'user_already_exists') {
      throw Exception('Email già registrata: usa ACCEDI invece di registrarti di nuovo.');
    }
    throw Exception(e.message);
  }

  /// Crea account Auth o effettua login se esiste già (evita nuovi signUp inutili).
  Future<String> _authSignUpOrSignIn({required String email, required String password}) async {
    final mail = normEmail(email);

    try {
      final signUp = await client.auth.signUp(email: mail, password: password);
      if (signUp.user != null && signUp.session != null) {
        return signUp.user!.id;
      }
      // Confirm email attivo: nessuna sessione → prova login
      if (signUp.user != null) {
        final signIn = await client.auth.signInWithPassword(email: mail, password: password);
        if (signIn.user != null) return signIn.user!.id;
        throw Exception(
          'Account creato ma non puoi entrare. In Supabase disattiva "Confirm email" '
          '(Authentication → Providers → Email).',
        );
      }
    } on AuthException catch (e) {
      if (_isRateLimit(e)) {
        _rilanciaAuth(e);
      }
      // Utente già presente: login senza nuovo signUp (non consuma invio email)
      try {
        final signIn = await client.auth.signInWithPassword(email: mail, password: password);
        if (signIn.user != null) return signIn.user!.id;
      } on AuthException catch (loginErr) {
        _rilanciaAuth(loginErr);
      }
      _rilanciaAuth(e);
    }

    throw Exception('Registrazione non riuscita. Riprova tra qualche minuto.');
  }

  Future<void> registraAssociazione({
    required String nome,
    required String via,
    required String indirizzo,
    required String email,
    required String password,
    required String masterCode,
  }) async {
    final mail = normEmail(email);
    final userId = await _authSignUpOrSignIn(email: mail, password: password);

    final orgEsistente = await client.from('organizzazioni').select('id').eq('owner_id', userId).maybeSingle();
    if (orgEsistente != null) {
      // Master già registrato in precedenza
      return;
    }

    final orgRow = await client.from('organizzazioni').insert({
      'owner_id': userId,
      'nome': nome,
      'via': via,
      'indirizzo': indirizzo,
      'email': mail,
      'master_code': masterCode,
    }).select().single();

    final profiloEsistente = await client.from('profili').select('id').eq('id', userId).maybeSingle();
    if (profiloEsistente == null) {
      await client.from('profili').insert({
        'id': userId,
        'org_id': orgRow['id'],
        'ruolo': 'master',
        'nome': 'Master',
        'cognome': nome,
        'email': mail,
      });
    }
  }

  Future<SessioneUtente> login({required String email, required String password}) async {
    final mail = normEmail(email);
    await client.auth.signInWithPassword(email: mail, password: password);
    final userId = client.auth.currentUser?.id;
    if (userId == null) throw Exception('Login fallito');

    final profilo = await client.from('profili').select('org_id, ruolo, email, permessi').eq('id', userId).maybeSingle();
    if (profilo == null) throw Exception('Profilo non trovato');

    final org = await client.from('organizzazioni').select('id, nome').eq('id', profilo['org_id']).single();

    return SessioneUtente(
      orgId: org['id'] as String,
      orgNome: org['nome'] as String,
      isMaster: profilo['ruolo'] == 'master',
      email: profilo['email'] as String,
      permessi: profilo['permessi'] as String? ?? 'pieno_accesso',
    );
  }

  Future<void> logout() async {
    await client.auth.signOut();
  }

  Future<Map<String, dynamic>> caricaOrganizzazione(String orgId) async {
    final org = await client.from('organizzazioni').select().eq('id', orgId).single();
    final inviti = await client
        .from('inviti')
        .select()
        .eq('org_id', orgId)
        .order('data_invito', ascending: false);

    return {
      'id': org['id'],
      'nome': org['nome'],
      'via': org['via'] ?? '',
      'indirizzo': org['indirizzo'] ?? '',
      'email': org['email'],
      'masterCode': org['master_code'],
      'password': '',
      'inviti': (inviti as List)
          .map((e) => _mapInvito(Map<String, dynamic>.from(e as Map)))
          .toList(),
      'accountVolontari': <Map<String, dynamic>>[],
    };
  }

  Map<String, dynamic> _mapInvito(Map<String, dynamic> row) => {
        'id': row['id'],
        'nome': row['nome'],
        'cognome': row['cognome'],
        'email': row['email'],
        'stato': row['stato'],
        'dataInvito': row['data_invito'],
        'dataRegistrazione': row['data_registrazione'],
      };

  Future<void> creaInvito({
    required String orgId,
    required String nome,
    required String cognome,
    required String email,
  }) async {
    await client.from('inviti').insert({
      'org_id': orgId,
      'nome': nome,
      'cognome': cognome,
      'email': normEmail(email),
      'stato': 'in_attesa',
    });
  }

  Future<void> eliminaInvito(String invitoId) async {
    await client.from('inviti').delete().eq('id', invitoId);
  }

  Future<Map<String, dynamic>?> trovaInvitoPendente(String email) async {
    final mail = normEmail(email);
    final row = await client
        .from('inviti')
        .select('*, organizzazioni(*)')
        .eq('email', mail)
        .eq('stato', 'in_attesa')
        .maybeSingle();

    if (row == null) return null;

    final orgRaw = row['organizzazioni'] as Map<String, dynamic>;
    final org = {
      'id': orgRaw['id'],
      'nome': orgRaw['nome'],
      'via': orgRaw['via'] ?? '',
      'indirizzo': orgRaw['indirizzo'] ?? '',
      'email': orgRaw['email'],
      'masterCode': orgRaw['master_code'],
      'password': '',
      'inviti': <Map<String, dynamic>>[],
      'accountVolontari': <Map<String, dynamic>>[],
    };

    return {
      'org': org,
      'invito': _mapInvito(row),
    };
  }

  Future<SessioneUtente> registraVolontario({
    required String nome,
    required String cognome,
    required String email,
    required String password,
    required String invitoId,
    required String orgId,
    required String orgNome,
  }) async {
    final mail = normEmail(email);
    final userId = await _authSignUpOrSignIn(email: mail, password: password);

    final profiloEsistente = await client.from('profili').select('id').eq('id', userId).maybeSingle();
    if (profiloEsistente != null) {
      throw Exception('Email già registrata. Usa ACCEDI.');
    }

    await client.from('profili').insert({
      'id': userId,
      'org_id': orgId,
      'ruolo': 'volontario',
      'nome': nome,
      'cognome': cognome,
      'email': mail,
    });

    await client.from('inviti').update({
      'stato': 'registrato',
      'data_registrazione': DateTime.now().toIso8601String(),
      'user_id': userId,
    }).eq('id', invitoId);

    await client.from('volontari').insert({
      'org_id': orgId,
      'nome': '$nome $cognome',
      'ruolo': 'Volontario',
      'patente_c': false,
      'stato': 'Disponibile',
      'in_servizio': true,
      'email': mail,
    });

    return SessioneUtente(
      orgId: orgId,
      orgNome: orgNome,
      isMaster: false,
      email: mail,
    );
  }

  Future<List<Map<String, dynamic>>> caricaVolontari(String orgId) async {
    final rows = await client.from('volontari').select().eq('org_id', orgId).order('nome');
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return {
        'id': m['id'],
        'nome': m['nome'],
        'ruolo': m['ruolo'] ?? 'Volontario',
        'patenteC': m['patente_c'] == true,
        'stato': m['stato'] ?? 'Disponibile',
        'inServizio': m['in_servizio'] != false,
        'orgId': m['org_id'],
        'orgNome': '',
        'email': m['email'],
        'permessi': m['permessi'] ?? 'pieno_accesso',
      };
    }).toList();
  }

  Future<void> salvaVolontare(Map<String, dynamic> v) async {
    final payload = {
      'org_id': v['orgId'],
      'nome': v['nome'],
      'ruolo': v['ruolo'] ?? 'Volontario',
      'patente_c': v['patenteC'] == true,
      'stato': v['stato'] ?? 'Disponibile',
      'in_servizio': v['inServizio'] != false,
      'email': v['email'],
      'permessi': v['permessi'] ?? 'pieno_accesso',
    };

    if (v['id'] != null) {
      await client.from('volontari').update(payload).eq('id', v['id']);
    } else {
      final row = await client.from('volontari').insert(payload).select().single();
      v['id'] = row['id'];
    }
  }

  Future<void> aggiornaPermessiVolontario(String volontarioId, String permessi) async {
    await client.from('volontari').update({'permessi': permessi}).eq('id', volontarioId);
  }

  Future<void> aggiornaPermessiProfilo(String profiloId, String permessi) async {
    await client.from('profili').update({'permessi': permessi}).eq('id', profiloId);
  }

  Future<void> eliminaVolontare(String id) async {
    await client.from('volontari').delete().eq('id', id);
  }

  /// Con più associazioni: email + codice master identificano la sede corretta.
  Future<Map<String, dynamic>?> organizzazioneDaEmailEMasterCode({
    required String email,
    required String masterCode,
  }) async {
    final mail = normEmail(email);
    final row = await client
        .from('organizzazioni')
        .select()
        .eq('email', mail)
        .eq('master_code', masterCode.trim())
        .maybeSingle();
    if (row == null) return null;
    return {
      'id': row['id'],
      'nome': row['nome'],
      'email': row['email'],
      'masterCode': row['master_code'],
    };
  }

  /// Invia link di reimpostazione password (richiede SMTP configurato in Supabase).
  Future<void> inviaLinkResetPassword(String email) async {
    final mail = normEmail(email);
    await client.auth.resetPasswordForEmail(mail);
  }

  Future<bool> emailVolontarioRegistrata(String email) async {
    final mail = normEmail(email);
    final row = await client.from('profili').select('id').eq('email', mail).eq('ruolo', 'volontario').maybeSingle();
    return row != null;
  }

  Future<void> recuperoPasswordMaster({
    required String email,
    required String masterCode,
  }) async {
    final org = await organizzazioneDaEmailEMasterCode(email: email, masterCode: masterCode);
    if (org == null) {
      throw Exception('Email o codice master non corrispondono. Controlla i dati della tua associazione.');
    }
    await inviaLinkResetPassword(org['email'] as String);
  }

  Future<void> recuperoPasswordVolontario({required String email}) async {
    final mail = normEmail(email);
    final ok = await emailVolontarioRegistrata(mail);
    if (!ok) {
      throw Exception('Email non trovata tra i volontari registrati. Chiedi al master di invitarti.');
    }
    await inviaLinkResetPassword(mail);
  }

  Future<List<Map<String, dynamic>>> caricaMezzi(String orgId) async {
    final rows = await client.from('mezzi').select().eq('org_id', orgId).order('nome');
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return {
        'id': m['id'],
        'nome': m['nome'],
        'targa': m['targa'],
        'stato': m['stato'] ?? 'Disponibile',
        'scadenzaAss': m['scadenza_ass'] ?? '',
        'scadenzaBollo': m['scadenza_bollo'] ?? '',
        'guasto': m['guasto'] == true,
        'notaGuasto': m['nota_guasto'] ?? '',
        'orgId': m['org_id'],
      };
    }).toList();
  }

  Future<void> salvaMezzo(Map<String, dynamic> m, String orgId) async {
    final payload = {
      'org_id': orgId,
      'nome': m['nome'],
      'targa': m['targa'],
      'stato': m['stato'] ?? 'Disponibile',
      'scadenza_ass': m['scadenzaAss'] ?? '',
      'scadenza_bollo': m['scadenzaBollo'] ?? '',
      'guasto': m['guasto'] == true,
      'nota_guasto': m['notaGuasto'] ?? '',
    };

    if (m['id'] != null) {
      await client.from('mezzi').update(payload).eq('id', m['id']);
    } else {
      final row = await client.from('mezzi').insert(payload).select().single();
      m['id'] = row['id'];
    }
  }

  Future<void> aggiornaStatoMezzo(String mezzoId, String stato) async {
    await client.from('mezzi').update({'stato': stato}).eq('id', mezzoId);
  }

  Future<void> eliminaMezzo(String id) async {
    await client.from('mezzi').delete().eq('id', id);
  }

  Future<List<Map<String, dynamic>>> caricaMagazzino(String orgId) async {
    final rows = await client.from('magazzino').select().eq('org_id', orgId).order('descrizione');
    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      return {
        'id': m['id'],
        'descrizione': m['descrizione'],
        'quantita': m['quantita'] ?? 0,
        'orgId': m['org_id'],
      };
    }).toList();
  }

  Future<void> salvaArticoloMagazzino(Map<String, dynamic> articolo, String orgId) async {
    final payload = {
      'org_id': orgId,
      'descrizione': articolo['descrizione'],
      'quantita': articolo['quantita'] ?? 0,
    };

    if (articolo['id'] != null) {
      await client.from('magazzino').update(payload).eq('id', articolo['id']);
    } else {
      final row = await client.from('magazzino').insert(payload).select().single();
      articolo['id'] = row['id'];
    }
  }

  Future<void> eliminaArticoloMagazzino(String id) async {
    await client.from('magazzino').delete().eq('id', id);
  }
}
