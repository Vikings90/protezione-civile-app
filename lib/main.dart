import 'dart:convert';
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'config/supabase_config.dart';
import 'services/supabase_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.instance.initialize();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: IoSonoV(),
  ));
}

class IoSonoV extends StatefulWidget {
  const IoSonoV({super.key});
  @override
  State<IoSonoV> createState() => _IoSonoVState();
}

class _IoSonoVState extends State<IoSonoV> {
  bool _inRegistrazioneAssociazione = false;
  bool _isAuthenticated = false;
  bool _inRegistrazioneVolontario = false;
  bool _isMasterUser = false;
  bool _isVolontarioUser = false;
  bool _mostraLogin = false;
  bool _mostraSchermataRecuperoPassword = false;
  String? _sessionOrgId;
  String _sessionPermessi = 'pieno_accesso';

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _recuperoEmailController = TextEditingController();
  final TextEditingController _recuperoMasterController = TextEditingController();

  final List<Map<String, dynamic>> organizzazioni = [];
  List<Map<String, dynamic>> volontari = [];

  final SupabaseService _db = SupabaseService.instance;
  bool _caricamentoIniziale = true;
  bool _haOrgCloud = false;
  bool _operazioneInCorso = false;

  late List<Map<String, dynamic>> mezzo = [];
  late List<Map<String, dynamic>> magazzino = [];
  Map<String, Map<String, String>> _permessiSezione = {};

  List<Map<String, dynamic>> interventi = [];
  List<Map<String, String>> segnalazioni = [];
  List<Map<String, dynamic>> pecFiles = [];
  List<Map<String, dynamic>> registrazioniPresenze = [];

  List<int> selezionatiInterventi = [];
  List<int> listaSegnalazioniSelezionate = [];

  final Color pcBlue = const Color(0xFF003399);
  final Color pcYellow = const Color(0xFFFFD700);
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passController.dispose();
    _recuperoEmailController.dispose();
    _recuperoMasterController.dispose();
    super.dispose();
  }

  bool get _usaCloud => _db.isReady;

  bool get _haOrganizzazioni => _usaCloud ? _haOrgCloud : organizzazioni.isNotEmpty;

  bool _haPermessoSezione(String sezione) {
    if (_isMasterUser) return true;
    if (_sessionPermessi == 'pieno_accesso') return true;
    
    // Per volontari con permessi granulari
    final userId = _db.client.auth.currentUser?.id;
    if (userId != null && _permessiSezione.containsKey(userId)) {
      final permessi = _permessiSezione[userId];
      if (permessi != null && permessi.containsKey(sezione)) {
        return permessi[sezione] == 'pieno_accesso';
      }
    }
    
    return false;
  }

  Future<void> _bootstrap() async {
    if (_usaCloud) {
      try {
        _haOrgCloud = await _db.esisteAlmenoUnOrganizzazione();
        final session = _db.client.auth.currentSession;
        if (session != null) {
          await _apriSessioneCloud();
        }
      } catch (e) {
        debugPrint('Bootstrap Supabase: $e');
      }
    }
    if (mounted) setState(() => _caricamentoIniziale = false);
  }

  Future<void> _apriSessioneCloud() async {
    final userId = _db.client.auth.currentUser?.id;
    if (userId == null) return;

    final profilo = await _db.client.from('profili').select('org_id, ruolo, email, permessi').eq('id', userId).maybeSingle();
    if (profilo == null) return;

    final orgId = profilo['org_id'] as String;
    final org = await _db.caricaOrganizzazione(orgId);
    final listaVolontari = await _db.caricaVolontari(orgId);
    final listaMezzi = await _db.caricaMezzi(orgId);
    final listaMagazzino = await _db.caricaMagazzino(orgId);
    final listaPresenze = await _db.caricaPresenze(orgId);
    final listaInterventi = await _db.caricaInterventi(orgId);

    organizzazioni
      ..clear()
      ..add(org);
    volontari = listaVolontari.map((v) {
      v['orgNome'] = org['nome'];
      return v;
    }).toList();
    mezzo = listaMezzi.map((m) {
      m['orgId'] = orgId;
      return m;
    }).toList();
    magazzino = listaMagazzino.map((m) {
      m['orgId'] = orgId;
      return m;
    }).toList();
    registrazioniPresenze = listaPresenze.map((p) {
      p['orgId'] = orgId;
      return p;
    }).toList();
    interventi = listaInterventi.map((i) {
      i['orgId'] = orgId;
      return i;
    }).toList();

    // Carica permessi granulari per tutti i volontari
    _permessiSezione.clear();
    for (var vol in volontari) {
      if (vol['id'] != null) {
        final permessi = await _db.caricaPermessiSezione(vol['id']);
        _permessiSezione[vol['id']] = permessi;
      }
    }

    setState(() {
      _isAuthenticated = true;
      _isMasterUser = profilo['ruolo'] == 'master';
      _isVolontarioUser = profilo['ruolo'] == 'volontario';
      _sessionOrgId = orgId;
      _sessionPermessi = profilo['permessi'] as String? ?? 'pieno_accesso';
      _haOrgCloud = true;
    });
  }

  Future<void> _esegui(Future<void> Function() azione, {String? messaggioOk}) async {
    setState(() => _operazioneInCorso = true);
    try {
      await azione();
      if (messaggioOk != null) _snack(messaggioOk, color: Colors.green);
    } catch (e) {
      _snack(_messaggioErrore(e));
    } finally {
      if (mounted) setState(() => _operazioneInCorso = false);
    }
  }

  String _messaggioErrore(Object e) {
    final testo = e.toString();
    if (testo.contains('Invalid login credentials')) return 'Credenziali errate!';
    if (testo.contains('User already registered')) return 'Email già registrata. Prova ad accedere con il login.';
    if (testo.contains('over_email_send_rate_limit') || testo.contains('429')) {
      return 'Troppe richieste ravvicinate. Attendi 10-20 secondi e riprova (o disattiva "Confirm email" in Supabase).';
    }
    if (testo.contains('Email not confirmed')) {
      return 'Conferma l\'email in Supabase Auth oppure disattiva "Confirm email" per i test.';
    }
    if (testo.contains('email provider is disabled')) {
      return 'In Supabase attiva Authentication → Providers → Email.';
    }
    return testo.replaceFirst('Exception: ', '');
  }

  String _normEmail(String email) => email.trim().toLowerCase();

  Map<String, dynamic>? _orgById(String? id) {
    if (id == null) return null;
    for (final org in organizzazioni) {
      if (org['id'] == id) return org;
    }
    return null;
  }

  Map<String, dynamic>? get _orgSessione => _orgById(_sessionOrgId);

  List<Map<String, dynamic>> get _volontariOrganizzazione {
    if (_sessionOrgId == null) return volontari;
    return volontari.where((v) => v['orgId'] == _sessionOrgId).toList();
  }

  Map<String, dynamic>? _trovaInvitoPendente(String email) {
    final norm = _normEmail(email);
    for (final org in organizzazioni) {
      for (final inv in List<Map<String, dynamic>>.from(org['inviti'] as List)) {
        if (_normEmail(inv['email'] as String) == norm && inv['stato'] == 'in_attesa') {
          return {'org': org, 'invito': inv};
        }
      }
    }
    return null;
  }

  Future<void> _logout() async {
    if (_usaCloud) {
      try {
        await _db.logout();
      } catch (_) {}
    }
    setState(() {
      _isAuthenticated = false;
      _isMasterUser = false;
      _isVolontarioUser = false;
      _sessionOrgId = null;
      _sessionPermessi = 'pieno_accesso';
      if (_usaCloud) {
        organizzazioni.clear();
        volontari = [];
      }
    });
  }

  void _snack(String msg, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color ?? Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_caricamentoIniziale) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_inRegistrazioneVolontario) return _buildRegistrazioneVolontario();
    if (_inRegistrazioneAssociazione) return _buildRegistrazioneAssociazione();
    if (_mostraSchermataRecuperoPassword) return _buildRecuperoPassword();
    if (_mostraLogin) return _buildLogin();
    if (!_isAuthenticated) return _buildSchermataScelta();
    return _buildDashboard();
  }

  Widget _buildSchermataScelta() {
    return Scaffold(
      backgroundColor: pcBlue,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () => setState(() => _mostraLogin = true),
              child: Image.asset('assets/images/io sono v.png', width: 150, height: 150),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: pcYellow, foregroundColor: pcBlue, fixedSize: const Size(280, 50)),
              onPressed: () => setState(() => _inRegistrazioneAssociazione = true),
              child: const Text("CREA ASSOCIAZIONE"),
            ),
            const SizedBox(height: 20),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.white54, side: const BorderSide(color: Colors.white54)),
              onPressed: () => setState(() => _inRegistrazioneVolontario = true),
              child: const Text("ACCESSO VOLONTARIO"),
            ),
            const Padding(
              padding: EdgeInsets.only(top: 16, left: 32, right: 32),
              child: Text(
                "Clicca sul logo per accedere. Dopo la creazione dell'associazione, il master potrà invitare i volontari. Solo chi è invitato potrà registrarsi.",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogin() {
    return Scaffold(
      backgroundColor: pcBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("ACCESSO",
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Email"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passController,
                obscureText: true,
                decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Password"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _operazioneInCorso
                    ? null
                    : () async {
                        final email = _normEmail(_emailController.text);
                        final pass = _passController.text;

                        if (email.isEmpty || pass.isEmpty) {
                          _snack("Compila tutti i campi.");
                          return;
                        }

                        await _tentaLogin();
                      },
                child: const Text("ACCEDI"),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => setState(() => _mostraSchermataRecuperoPassword = true),
                child: const Text("Password dimenticata?", style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => setState(() => _mostraLogin = false),
                child: const Text("Indietro", style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecuperoPassword() {
    return Scaffold(
      backgroundColor: pcBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("RECUPERO PASSWORD",
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _recuperoEmailController,
                decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Email"),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _recuperoMasterController,
                obscureText: true,
                decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Codice Master"),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _operazioneInCorso
                    ? null
                    : () async {
                        final email = _normEmail(_recuperoEmailController.text);
                        final master = _recuperoMasterController.text;

                        if (email.isEmpty || master.isEmpty) {
                          _snack("Compila tutti i campi.");
                          return;
                        }

                        await _recuperaPassword(email, master);
                      },
                child: const Text("RECUPERA"),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => setState(() => _mostraSchermataRecuperoPassword = false),
                child: const Text("Indietro", style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _recuperaPassword(String email, String masterCode) async {
    // Implementazione del recupero password con codice master
    if (_usaCloud) {
      await _esegui(() async {
        final profilo = await _db.client.from('profili').select('*').eq('email', email).maybeSingle();
        if (profilo == null) {
          _snack("Email non trovata.");
          return;
        }

        final org = await _db.caricaOrganizzazione(profilo['org_id']);
        if (org['master_code'] != masterCode) {
          _snack("Codice master errato.");
          return;
        }

        // Qui potresti implementare l'invio della password via email o mostrarla
        _snack("Password recuperata: ${org['password']}", color: Colors.green);
        setState(() => _mostraSchermataRecuperoPassword = false);
      });
      return;
    }

    // Per locale
    for (final org in organizzazioni) {
      if (_normEmail(org['email'] as String) == email && org['masterCode'] == masterCode) {
        _snack("Password recuperata: ${org['password']}", color: Colors.green);
        setState(() => _mostraSchermataRecuperoPassword = false);
        return;
      }
    }

    _snack("Email o codice master errato.");
  }

  Widget _buildRegistrazioneAssociazione() {
    final TextEditingController nomeController = TextEditingController();
    final TextEditingController viaController = TextEditingController();
    final TextEditingController indirizzoController = TextEditingController();
    final TextEditingController emailRegController = TextEditingController();
    final TextEditingController passRegController = TextEditingController();
    final TextEditingController masterController = TextEditingController();

    return Scaffold(
      backgroundColor: pcBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("REGISTRAZIONE ASSOCIAZIONE",
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(controller: nomeController, decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Nome Associazione")),
              const SizedBox(height: 10),
              TextField(controller: viaController, decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Via/Piazza")),
              const SizedBox(height: 10),
              TextField(controller: indirizzoController, decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Civico / Città")),
              const SizedBox(height: 10),
              TextField(controller: emailRegController, decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Email")),
              const SizedBox(height: 10),
              TextField(controller: passRegController, obscureText: true, decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Password")),
              const SizedBox(height: 10),
              TextField(controller: masterController, obscureText: true, decoration: const InputDecoration(filled: true, fillColor: Colors.white, labelText: "Codice Master Recupero")),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _operazioneInCorso
                    ? null
                    : () async {
                        final nome = nomeController.text.trim();
                        final email = _normEmail(emailRegController.text);
                        final pass = passRegController.text;
                        final master = masterController.text.trim();

                        final minPass = _usaCloud ? 6 : 4;
                        if (nome.isEmpty || email.isEmpty || pass.length < minPass || master.length < 4) {
                          _snack("Compila tutti i campi. Password: minimo $minPass caratteri (Supabase richiede 6).");
                          return;
                        }

                        if (_usaCloud) {
                          await _esegui(() async {
                            await _db.registraAssociazione(
                              nome: nome,
                              via: viaController.text.trim(),
                              indirizzo: indirizzoController.text.trim(),
                              email: email,
                              password: pass,
                              masterCode: master,
                            );
                            _haOrgCloud = true;
                            await _apriSessioneCloud();
                            setState(() => _inRegistrazioneAssociazione = false);
                          }, messaggioOk: "Associazione creata su Supabase. Usa INVITI per i volontari.");
                          return;
                        }

                        if (organizzazioni.any((o) => _normEmail(o['email'] as String) == email)) {
                          _snack("Email già usata da un'altra associazione.");
                          return;
                        }

                        final orgId = 'org_${DateTime.now().millisecondsSinceEpoch}';
                        organizzazioni.add({
                          'id': orgId,
                          'nome': nome,
                          'via': viaController.text.trim(),
                          'indirizzo': indirizzoController.text.trim(),
                          'email': email,
                          'password': pass,
                          'masterCode': master,
                          'inviti': <Map<String, dynamic>>[],
                          'accountVolontari': <Map<String, dynamic>>[],
                        });

                        setState(() {
                          _inRegistrazioneAssociazione = false;
                          _isAuthenticated = true;
                          _isMasterUser = true;
                          _isVolontarioUser = false;
                          _sessionOrgId = orgId;
                        });
                        _snack("Associazione creata. Usa la cartella INVITI per aggiungere volontari.", color: Colors.green);
                      },
                child: const Text("COMPLETA REGISTRAZIONE"),
              ),
              TextButton(
                onPressed: () => setState(() => _inRegistrazioneAssociazione = false),
                child: const Text("Annulla", style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _tentaLogin() async {
    final email = _normEmail(_emailController.text);
    final pass = _passController.text;

    if (_usaCloud) {
      await _esegui(() async {
        final sessione = await _db.login(email: email, password: pass);
        organizzazioni
          ..clear()
          ..add(await _db.caricaOrganizzazione(sessione.orgId));
        volontari = (await _db.caricaVolontari(sessione.orgId))
            .map((v) => v..['orgNome'] = sessione.orgNome)
            .toList();
        setState(() {
          _isAuthenticated = true;
          _isMasterUser = sessione.isMaster;
          _isVolontarioUser = !sessione.isMaster;
          _sessionOrgId = sessione.orgId;
          _haOrgCloud = true;
        });
      });
      return;
    }

    for (final org in organizzazioni) {
      if (_normEmail(org['email'] as String) == email && org['password'] == pass) {
        setState(() {
          _isAuthenticated = true;
          _isMasterUser = true;
          _isVolontarioUser = false;
          _sessionOrgId = org['id'] as String;
          _sessionPermessi = 'pieno_accesso';
        });
        return;
      }
    }

    for (final org in organizzazioni) {
      for (final account in List<Map<String, dynamic>>.from(org['accountVolontari'] as List)) {
        if (_normEmail(account['email'] as String) == email && account['password'] == pass) {
          final volontario = volontari.firstWhere(
            (v) => v['email'] == email && v['orgId'] == org['id'],
            orElse: () => {'permessi': 'pieno_accesso'},
          );
          setState(() {
            _isAuthenticated = true;
            _isMasterUser = false;
            _isVolontarioUser = true;
            _sessionOrgId = org['id'] as String;
            _sessionPermessi = volontario['permessi'] as String? ?? 'pieno_accesso';
          });
          return;
        }
      }
    }

    _snack("Credenziali errate!");
  }

  void _mostraRecuperoPassword() {
    final emailController = TextEditingController();
    final masterController = TextEditingController();
    var ruoloRecupero = 'master'; // master | volontario

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialog) => AlertDialog(
          title: const Text("Recupero password"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _usaCloud
                      ? "Più associazioni usano la stessa app: inserisci i dati della TUA sede.\n\n"
                          "• Master: email + codice master della sede\n"
                          "• Volontario: solo la tua email (devi essere già registrato)"
                      : "Master: email + codice master.\nVolontario: email usata in registrazione.",
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'master', label: Text('Master')),
                    ButtonSegment(value: 'volontario', label: Text('Volontario')),
                  ],
                  selected: {ruoloRecupero},
                  onSelectionChanged: (s) => setDialog(() => ruoloRecupero = s.first),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: "Email",
                    border: OutlineInputBorder(),
                  ),
                ),
                if (ruoloRecupero == 'master') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: masterController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: "Codice master della sede",
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("ANNULLA")),
            ElevatedButton(
              onPressed: () async {
                final email = _normEmail(emailController.text);
                final master = masterController.text.trim();

                if (!email.contains('@')) {
                  _snack("Inserisci un'email valida.");
                  return;
                }
                if (ruoloRecupero == 'master' && master.isEmpty) {
                  _snack("Inserisci il codice master della tua associazione.");
                  return;
                }

                if (_usaCloud) {
                  await _esegui(() async {
                    if (ruoloRecupero == 'master') {
                      await _db.recuperoPasswordMaster(email: email, masterCode: master);
                    } else {
                      await _db.recuperoPasswordVolontario(email: email);
                    }
                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (!context.mounted) return;
                    _alertRecuperoInviato(context, email);
                  }, messaggioOk: null);
                  return;
                }

                // Modalità locale (senza Supabase)
                if (ruoloRecupero == 'master') {
                  Map<String, dynamic>? org;
                  for (final o in organizzazioni) {
                    if (_normEmail(o['email'] as String) == email && o['masterCode'] == master) {
                      org = o;
                      break;
                    }
                  }
                  if (org != null) {
                    Navigator.pop(dialogCtx);
                    _alertPasswordLocale(context, org);
                  } else {
                    _snack("Email o codice master non corretti per nessuna associazione salvata in questo dispositivo.");
                  }
                } else {
                  for (final org in organizzazioni) {
                    for (final account in List<Map<String, dynamic>>.from(org['accountVolontari'] as List)) {
                      if (_normEmail(account['email'] as String) == email) {
                        Navigator.pop(dialogCtx);
                        _alertPasswordLocale(context, {
                          'nome': org['nome'],
                          'email': email,
                          'password': account['password'],
                        }, titolo: 'Volontario');
                        return;
                      }
                    }
                  }
                  _snack("Volontario non trovato su questo dispositivo.");
                }
              },
              child: Text(_usaCloud ? "INVIA LINK RESET" : "VERIFICA"),
            ),
          ],
        ),
      ),
    );
  }

  void _alertRecuperoInviato(BuildContext ctx, String email) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: const Text("Richiesta inviata"),
        content: Text(
          "Se l'email $email è corretta e in Supabase hai configurato l'invio mail (SMTP), "
          "riceverai un link per impostare una nuova password.\n\n"
          "Per i test senza email: in Supabase → Authentication → Users puoi reimpostare la password manualmente.",
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
      ),
    );
  }

  void _alertPasswordLocale(BuildContext ctx, Map<String, dynamic> dati, {String titolo = 'Master'}) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        title: Text("Credenziali $titolo"),
        content: Text(
          "Associazione: ${dati['nome']}\nEmail: ${dati['email']}\nPassword: ${dati['password']}",
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text("OK"))],
      ),
    );
  }

  Widget _buildLoginScreen() {
    return Scaffold(
      backgroundColor: pcBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.shield_rounded, size: 100, color: pcYellow),
              const SizedBox(height: 20),
              const Text("IO SONO V", style: TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 2)),
              const Text("Gestione Operativa Protezione Civile", style: TextStyle(color: Colors.white70, fontSize: 14)),
              if (_usaCloud)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text("Connesso a Supabase", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text("Modalità locale (configura Supabase)", style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                ),
              const SizedBox(height: 40),
              TextField(
                controller: _emailController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Email o Username",
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.person, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _passController,
                style: const TextStyle(color: Colors.white),
                obscureText: true,
                decoration: InputDecoration(
                  hintText: "Password",
                  hintStyle: const TextStyle(color: Colors.white54),
                  prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.1),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 25),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: pcYellow, foregroundColor: pcBlue, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                  onPressed: _operazioneInCorso ? null : _tentaLogin,
                  child: const Text("ACCEDI", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              TextButton(
                onPressed: _mostraRecuperoPassword,
                child: const Text("Password dimenticata?", style: TextStyle(color: Colors.white70)),
              ),
              TextButton(
                onPressed: () => setState(() => _inRegistrazioneVolontario = true),
                child: const Text(
                  "Sei un nuovo volontario? Registrati",
                  style: TextStyle(color: Colors.white, decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _mostraDialogInvito(BuildContext context) {
    if (!_isMasterUser || _orgSessione == null) {
      _snack("Solo il master può invitare volontari.");
      return;
    }

    final org = _orgSessione!;
    final nomeVController = TextEditingController();
    final cognomeVController = TextEditingController();
    final emailVController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text("Invita Volontario"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "L'invito resta in attesa finché il volontario non completa la registrazione. Nessuna email viene inviata.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(controller: nomeVController, decoration: const InputDecoration(labelText: "Nome")),
            TextField(controller: cognomeVController, decoration: const InputDecoration(labelText: "Cognome")),
            TextField(controller: emailVController, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: "Email")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text("Annulla")),
          ElevatedButton(
            onPressed: () async {
              final nome = nomeVController.text.trim();
              final cognome = cognomeVController.text.trim();
              final email = _normEmail(emailVController.text);

              if (nome.isEmpty || cognome.isEmpty || !email.contains('@')) {
                _snack("Inserisci nome, cognome e email valida.");
                return;
              }

              final inviti = List<Map<String, dynamic>>.from(org['inviti'] as List);
              final giaPresente = inviti.any((i) => _normEmail(i['email'] as String) == email);
              if (giaPresente) {
                _snack("Questo volontario è già stato invitato.");
                return;
              }

              if (_usaCloud) {
                await _esegui(() async {
                  await _db.creaInvito(orgId: org['id'] as String, nome: nome, cognome: cognome, email: email);
                  final aggiornata = await _db.caricaOrganizzazione(org['id'] as String);
                  org['inviti'] = aggiornata['inviti'];
                  setState(() {});
                  if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                }, messaggioOk: "Invito registrato per $nome $cognome");
                return;
              }

              inviti.add({
                'id': 'inv_${DateTime.now().millisecondsSinceEpoch}',
                'nome': nome,
                'cognome': cognome,
                'email': email,
                'stato': 'in_attesa',
                'dataInvito': DateTime.now().toIso8601String(),
              });
              org['inviti'] = inviti;

              setState(() {});
              Navigator.pop(dialogCtx);
              _snack("Invito registrato per $nome $cognome", color: Colors.green);
            },
            child: const Text("Aggiungi invito"),
          ),
        ],
      ),
    );
  }

  Widget _paginaCartellaInviti() {
    final org = _orgSessione;
    if (org == null || !_isMasterUser) {
      return const Scaffold(body: Center(child: Text("Accesso riservato al master")));
    }

    final inviti = List<Map<String, dynamic>>.from(org['inviti'] as List);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Cartella Inviti"),
        backgroundColor: pcBlue,
        foregroundColor: Colors.white,
      ),
      body: inviti.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Nessun volontario invitato.\nUsa + per aggiungere un invito.\nIl volontario potrà registrarsi solo se compare qui in stato \"In attesa\".",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: inviti.length,
              itemBuilder: (context, i) {
                final inv = inviti[i];
                final registrato = inv['stato'] == 'registrato';
                return Card(
                  child: ListTile(
                    leading: Icon(
                      registrato ? Icons.check_circle : Icons.hourglass_top,
                      color: registrato ? Colors.green : Colors.orange,
                    ),
                    title: Text("${inv['nome']} ${inv['cognome']}"),
                    subtitle: Text("${inv['email']}\nStato: ${registrato ? 'Registrato' : 'In attesa'}"),
                    isThreeLine: true,
                    trailing: registrato
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                            onPressed: () async {
                              final invitoId = inv['id'] as String;
                              if (_usaCloud) {
                                await _esegui(() async {
                                  await _db.eliminaInvito(invitoId);
                                  final aggiornata = await _db.caricaOrganizzazione(org['id'] as String);
                                  org['inviti'] = aggiornata['inviti'];
                                  setState(() {});
                                }, messaggioOk: "Invito rimosso");
                              } else {
                                setState(() {
                                  inviti.removeAt(i);
                                  org['inviti'] = inviti;
                                });
                              }
                            },
                          ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _mostraDialogInvito(context),
        backgroundColor: pcBlue,
        child: const Icon(Icons.person_add),
      ),
    );
  }

  Widget _buildDashboard() {
    final orgNome = _orgSessione?['nome'] ?? '';
    final ruolo = _isMasterUser ? 'Master' : 'Volontario';

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("IO SONO V", style: TextStyle(fontWeight: FontWeight.bold, color: pcYellow, letterSpacing: 1.2)),
        backgroundColor: pcBlue,
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout)
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text("DASHBOARD — $orgNome", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
            Text("Accesso: $ruolo", style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const Divider(),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 15,
                mainAxisSpacing: 15,
                children: [
                  if (_isMasterUser)
                    _card("INVITI", Icons.folder_shared_rounded, Colors.indigo[700]!, () => _vaiA(_paginaCartellaInviti())),
                  _card("VOLONTARI", Icons.people_alt_rounded, Colors.blue[700]!, () => _vaiA(_paginaVolontari())),
                  _card("MEZZI E ATTREZZATURE", Icons.local_shipping_rounded, Colors.orange[800]!, () => _vaiA(_paginaMezzi())),
                  _card("MAGAZZINO", Icons.inventory, Colors.amber[600]!, () => _vaiA(_paginaMagazzino())),
                  _card("SALA RADIO", Icons.settings_input_antenna, Colors.green[700]!, () => _vaiA(_paginaSalaRadio())),
                  if (_isMasterUser)
                    _card("ARCHIVIO", Icons.inventory_2_rounded, Colors.blueGrey[700]!, () => _vaiA(_paginaArchivioInterventi())),
                  _card("SEGNALAZIONI", Icons.report_problem_rounded, Colors.purple[700]!, () => _vaiA(_paginaSegnalazioni())),
                  _card("PIANO EMERGENZA COMUNALE", Icons.picture_as_pdf, Colors.red[700]!, () => _vaiA(_paginaPEC())),
                  _card("PRESENZA", Icons.how_to_reg, Colors.teal[700]!, () => _vaiA(_paginaPresenza())),
                  if (_isMasterUser)
                    _card("GESTIONE PRESENZE", Icons.assignment, Colors.amber[700]!, () => _vaiA(_paginaGestionePresenze())),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              height: 65,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[700], foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                onPressed: _sessionPermessi == 'pieno_accesso' ? _dialogNuovoIntervento : null,
                icon: const Icon(Icons.warning_amber_rounded, size: 28),
                label: const Text("NUOVO INTERVENTO", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: _isMasterUser
          ? FloatingActionButton(
              onPressed: () => _vaiA(_paginaCartellaInviti()),
              backgroundColor: pcBlue,
              child: const Icon(Icons.folder_shared),
            )
          : null,
    );
  }

  Widget _card(String t, IconData i, Color c, VoidCallback f) => InkWell(
        onTap: f,
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)]),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(i, size: 40, color: c),
            const SizedBox(height: 10),
            Text(t, style: TextStyle(color: c, fontWeight: FontWeight.bold))
          ]),
        ),
      );

  void _vaiA(Widget pagina) => Navigator.push(context, MaterialPageRoute(builder: (c) => pagina));

  Widget _paginaSegnalazioni() {
    return StatefulBuilder(builder: (context, setStateSegnalazioni) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Segnalazioni", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.purple[700],
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: segnalazioni.isEmpty
            ? const Center(child: Text("Nessuna segnalazione presente", style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: segnalazioni.length,
                itemBuilder: (c, i) => ListTile(
                  leading: Icon(Icons.assignment_rounded, color: Colors.purple[700]),
                  title: Text(segnalazioni[i]['oggetto'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(segnalazioni[i]['descrizione'] ?? ""),
                ),
              ),
        floatingActionButton: _sessionPermessi == 'pieno_accesso' ? FloatingActionButton(
          backgroundColor: Colors.purple[700],
          child: const Icon(Icons.add, color: Colors.white),
          onPressed: () => _dialogNuovaSegnalazione(() => setStateSegnalazioni(() {})),
        ) : null,
      );
    });
  }

  void _dialogNuovaSegnalazione(VoidCallback onSave) {
    String oggetto = "";
    String descrizione = "";
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Nuova Segnalazione"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(onChanged: (v) => oggetto = v, decoration: const InputDecoration(labelText: "Oggetto")),
            const SizedBox(height: 10),
            TextField(onChanged: (v) => descrizione = v, maxLines: 3, decoration: const InputDecoration(labelText: "Descrizione")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[700], foregroundColor: Colors.white),
            onPressed: () {
              if (oggetto.isNotEmpty || descrizione.isNotEmpty) {
                setState(() => segnalazioni.add({"oggetto": oggetto, "descrizione": descrizione}));
                onSave();
              }
              Navigator.pop(c);
            },
            child: const Text("INVIA"),
          )
        ],
      ),
    );
  }

  Widget _paginaVolontari() {
    String query = "";
    return StatefulBuilder(builder: (context, setStateVol) {
      var filtrati = _volontariOrganizzazione.where((v) => v['nome'].toLowerCase().contains(query.toLowerCase())).toList();
      return Scaffold(
        appBar: AppBar(
          title: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: "Cerca Volontario...", hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
            onChanged: (v) => setStateVol(() => query = v),
          ),
          backgroundColor: pcBlue,
        ),
        body: ListView.builder(
          itemCount: filtrati.length,
          itemBuilder: (c, i) => ListTile(
            leading: Icon(filtrati[i]['patenteC'] ? Icons.badge : Icons.person, color: pcBlue),
            title: Text(filtrati[i]['nome']),
            subtitle: Text("Stato: ${filtrati[i]['stato']} ${filtrati[i]['patenteC'] ? '(Pat. C)' : ''}"),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isMasterUser)
                  IconButton(icon: const Icon(Icons.security, color: Colors.purple), onPressed: () => _dialogPermessiVolontario(filtrati[i], () => setStateVol(() {}))),
                if (_sessionPermessi == 'pieno_accesso')
                  IconButton(icon: const Icon(Icons.edit, color: Colors.grey), onPressed: () => _dialogNuovoVolontario(() => setStateVol(() {}), editItem: filtrati[i])),
                if (_sessionPermessi == 'pieno_accesso')
                  IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                    final item = filtrati[i];
                    if (_usaCloud && item['id'] != null) {
                      await _esegui(() async {
                        await _db.eliminaVolontare(item['id'] as String);
                        setState(() => volontari.remove(item));
                        setStateVol(() {});
                      });
                    } else {
                      setState(() => volontari.remove(item));
                      setStateVol(() {});
                    }
                  }),
                PopupMenuButton<String>(
                  onSelected: (String s) async {
                    setState(() => filtrati[i]['stato'] = s);
                    if (_usaCloud && filtrati[i]['id'] != null) {
                      await _db.salvaVolontare(filtrati[i]);
                    }
                    setStateVol(() {});
                  },
                  itemBuilder: (c) => ["Disponibile", "Sala Radio", "In Intervento", "Non Disponibile"].map((st) => PopupMenuItem(value: st, child: Text(st))).toList(),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: _sessionPermessi == 'pieno_accesso' ? FloatingActionButton(
          backgroundColor: pcBlue,
          child: const Icon(Icons.person_add, color: Colors.white),
          onPressed: () => _dialogNuovoVolontario(() => setStateVol(() {})),
        ) : null,
      );
    });
  }

  void _dialogNuovoVolontario(VoidCallback onSave, {Map<String, dynamic>? editItem}) {
    String n = editItem?['nome'] ?? "";
    bool pC = editItem?['patenteC'] ?? false;
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text(editItem == null ? "Nuovo Volontario" : "Modifica Volontario"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: TextEditingController(text: n)..selection = TextSelection.collapsed(offset: n.length),
                onChanged: (v) => n = v,
                decoration: const InputDecoration(labelText: "Nome e Cognome"),
              ),
              CheckboxListTile(title: const Text("Patente C"), value: pC, onChanged: (v) => setD(() => pC = v!)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                if (editItem == null) {
                  final nuovo = {
                    "nome": n,
                    "ruolo": "Volontario",
                    "patenteC": pC,
                    "stato": "Non Disponibile",
                    "inServizio": true,
                    "orgId": _sessionOrgId,
                    "orgNome": _orgSessione?['nome'] ?? '',
                    "permessi": "pieno_accesso",
                  };
                  if (_usaCloud) {
                    await _db.salvaVolontare(nuovo);
                  }
                  setState(() => volontari.add(nuovo));
                } else {
                  setState(() {
                    editItem['nome'] = n;
                    editItem['patenteC'] = pC;
                  });
                  if (_usaCloud && editItem['id'] != null) {
                    await _db.salvaVolontare(editItem);
                  }
                }
                onSave();
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text("SALVA"),
            )
          ],
        ),
      ),
    );
  }

  void _dialogPermessiVolontario(Map<String, dynamic> volontario, VoidCallback onSave) {
    String permessiGlobale = volontario['permessi'] ?? 'pieno_accesso';
    Map<String, String> permessiSezione = {};
    
    if (_usaCloud && volontario['id'] != null) {
      permessiSezione = Map.from(_permessiSezione[volontario['id']] ?? {});
    }
    
    final sezioni = [
      'volontari',
      'mezzi',
      'magazzino',
      'sala_radio',
      'archivio',
      'segnalazioni'
    ];
    
    final sezioniNomi = {
      'volontari': 'Volontari',
      'mezzi': 'Mezzi e Attrezzature',
      'magazzino': 'Magazzino',
      'sala_radio': 'Sala Radio',
      'archivio': 'Archivio',
      'segnalazioni': 'Segnalazioni'
    };
    
    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: Text("Permessi: ${volontario['nome']}"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text("Scegli il livello di accesso globale:"),
                const SizedBox(height: 8),
                RadioListTile<String>(
                  title: const Text("Pieno Accesso Globale"),
                  subtitle: const Text("Può modificare tutte le sezioni"),
                  value: 'pieno_accesso',
                  groupValue: permessiGlobale,
                  onChanged: (v) => setD(() => permessiGlobale = v!),
                ),
                RadioListTile<String>(
                  title: const Text("Permessi Granulari"),
                  subtitle: const Text("Configura permessi per ogni sezione"),
                  value: 'granulare',
                  groupValue: permessiGlobale,
                  onChanged: (v) => setD(() => permessiGlobale = v!),
                ),
                RadioListTile<String>(
                  title: const Text("Solo Lettura Globale"),
                  subtitle: const Text("Può solo visualizzare tutte le sezioni"),
                  value: 'solo_lettura',
                  groupValue: permessiGlobale,
                  onChanged: (v) => setD(() => permessiGlobale = v!),
                ),
                if (permessiGlobale == 'granulare') ...[
                  const Divider(),
                  const SizedBox(height: 8),
                  const Text("Configura permessi per sezione:"),
                  const SizedBox(height: 8),
                  ...sezioni.map((sezione) {
                    final permesso = permessiSezione[sezione] ?? 'solo_lettura';
                    return Column(
                      children: [
                        ListTile(
                          title: Text(sezioniNomi[sezione] ?? sezione),
                          trailing: DropdownButton<String>(
                            value: permesso,
                            items: [
                              const DropdownMenuItem(value: 'solo_lettura', child: Text('Solo Lettura')),
                              const DropdownMenuItem(value: 'pieno_accesso', child: Text('Pieno Accesso')),
                            ],
                            onChanged: (v) {
                              if (v != null) {
                                setD(() => permessiSezione[sezione] = v);
                              }
                            },
                          ),
                        ),
                        const Divider(),
                      ],
                    );
                  }).toList(),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
            ElevatedButton(
              onPressed: () async {
                volontario['permessi'] = permessiGlobale;
                if (_usaCloud && volontario['id'] != null) {
                  await _esegui(() async {
                    await _db.aggiornaPermessiVolontario(volontario['id'] as String, permessiGlobale);
                    
                    if (permessiGlobale == 'granulare') {
                      // Salva permessi granulari
                      for (var sezione in sezioni) {
                        await _db.salvaPermessoSezione(
                          volontario['id'],
                          sezione,
                          permessiSezione[sezione] ?? 'solo_lettura'
                        );
                      }
                    } else {
                      // Elimina permessi granulari se non sono granulari
                      await _db.eliminaPermessiSezione(volontario['id']);
                    }
                    
                    // Ricarica permessi
                    final nuoviPermessi = await _db.caricaPermessiSezione(volontario['id']);
                    setState(() => _permessiSezione[volontario['id']] = nuoviPermessi);
                  }, messaggioOk: "Permessi aggiornati");
                }
                onSave();
                if (c.mounted) Navigator.pop(c);
              },
              child: const Text("SALVA"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _paginaMezzi() {
    String query = "";
    return StatefulBuilder(builder: (context, setStateMez) {
      var filtrati = mezzo.where((m) => m['nome'].toLowerCase().contains(query.toLowerCase()) || m['targa'].toLowerCase().contains(query.toLowerCase())).toList();
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.orange[800],
          title: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: "Cerca Mezzo o Attrezzatura...", hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
            onChanged: (v) => setStateMez(() => query = v),
          ),
        ),
        body: ListView.builder(
          itemCount: filtrati.length,
          itemBuilder: (c, i) {
            Color iconColor = (filtrati[i]['guasto'] || filtrati[i]['stato'] == "Manutenzione")
                ? Colors.red
                : (filtrati[i]['stato'] == "In Intervento" ? Colors.blue : Colors.green);
            return ListTile(
              leading: Icon(Icons.fire_truck, color: iconColor),
              title: Text("${filtrati[i]['nome']} (${filtrati[i]['targa']})"),
              subtitle: Text("Stato: ${filtrati[i]['stato']}\nAss: ${filtrati[i]['scadenzaAss']}"),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_haPermessoSezione('mezzi'))
                    IconButton(icon: const Icon(Icons.edit, color: Colors.grey), onPressed: () => _dialogNuovoMezzo(() => setStateMez(() {}), editMezzo: filtrati[i])),
                  if (_haPermessoSezione('mezzi'))
                    IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                      if (_usaCloud && filtrati[i]['id'] != null) {
                        try {
                          await _db.eliminaMezzo(filtrati[i]['id']);
                          setState(() => mezzo.remove(filtrati[i]));
                          setStateMez(() {});
                        } catch (e) {
                          _snack("Errore eliminazione mezzo: $e");
                        }
                      } else {
                        setState(() => mezzo.remove(filtrati[i]));
                        setStateMez(() {});
                      }
                    }),
                  PopupMenuButton<String>(
                    onSelected: (String s) async {
                      if (s == "Manutenzione") {
                        _dialogGestioneMezzo(filtrati[i], () => setStateMez(() {}));
                      } else {
                        if (_usaCloud && filtrati[i]['id'] != null) {
                          try {
                            await _db.aggiornaStatoMezzo(filtrati[i]['id'], s);
                            setState(() {
                              filtrati[i]['stato'] = s;
                              if (s == "Disponibile") filtrati[i]['guasto'] = false;
                            });
                          } catch (e) {
                            _snack("Errore aggiornamento stato: $e");
                          }
                        } else {
                          setState(() {
                            filtrati[i]['stato'] = s;
                            if (s == "Disponibile") filtrati[i]['guasto'] = false;
                          });
                        }
                        setStateMez(() {});
                      }
                    },
                    itemBuilder: (c) => ["Disponibile", "In Intervento", "Manutenzione"].map((st) => PopupMenuItem(value: st, child: Text(st))).toList(),
                  ),
                ],
              ),
            );
          },
        ),
        floatingActionButton: _haPermessoSezione('mezzi') ? FloatingActionButton(backgroundColor: Colors.orange[800], child: const Icon(Icons.add_road), onPressed: () => _dialogNuovoMezzo(() => setStateMez(() {}))) : null,
      );
    });
  }

  void _dialogNuovoMezzo(VoidCallback onSave, {Map<String, dynamic>? editMezzo}) {
    String n = editMezzo?['nome'] ?? "", t = editMezzo?['targa'] ?? "", s = editMezzo?['scadenzaAss'] ?? "", b = editMezzo?['scadenzaRevisione'] ?? "";
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(editMezzo == null ? "Nuovo Mezzo/Attrezzatura" : "Modifica Mezzo/Attrezzatura"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: TextEditingController(text: n), onChanged: (v) => n = v, decoration: const InputDecoration(labelText: "Nome Mezzo/Attrezzatura")),
              TextField(controller: TextEditingController(text: t), onChanged: (v) => t = v, decoration: const InputDecoration(labelText: "Targa")),
              TextField(controller: TextEditingController(text: s), onChanged: (v) => s = v, decoration: const InputDecoration(labelText: "Scadenza Assicurazione")),
              TextField(controller: TextEditingController(text: b), onChanged: (v) => b = v, decoration: const InputDecoration(labelText: "Scadenza Revisione")),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (_usaCloud && _sessionOrgId != null) {
                try {
                  if (editMezzo == null) {
                    final nuovoMezzo = {"nome": n, "targa": t, "stato": "Disponibile", "scadenzaAss": s, "scadenzaRevisione": b, "guasto": false, "notaGuasto": "", "orgId": _sessionOrgId};
                    await _db.salvaMezzo(nuovoMezzo, _sessionOrgId!);
                    mezzo.add(nuovoMezzo);
                  } else {
                    editMezzo['nome'] = n;
                    editMezzo['targa'] = t;
                    editMezzo['scadenzaAss'] = s;
                    editMezzo['scadenzaRevisione'] = b;
                    await _db.salvaMezzo(editMezzo, _sessionOrgId!);
                  }
                  setState(() {});
                  onSave();
                  Navigator.pop(c);
                } catch (e) {
                  _snack("Errore salvataggio mezzo: $e");
                }
              } else {
                setState(() {
                  if (editMezzo == null) {
                    mezzo.add({"nome": n, "targa": t, "stato": "Disponibile", "scadenzaAss": s, "scadenzaRevisione": b, "guasto": false, "notaGuasto": ""});
                  } else {
                    editMezzo['nome'] = n;
                    editMezzo['targa'] = t;
                    editMezzo['scadenzaAss'] = s;
                    editMezzo['scadenzaRevisione'] = b;
                  }
                });
                onSave();
                Navigator.pop(c);
              }
            },
            child: const Text("SALVA"),
          )
        ],
      ),
    );
  }

  void _dialogGestioneMezzo(Map<String, dynamic> m, VoidCallback onSave) {
    String n = m['notaGuasto'];
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("Manutenzione: ${m['nome']}"),
        content: TextField(controller: TextEditingController(text: n), onChanged: (v) => n = v, decoration: const InputDecoration(labelText: "Problema")),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                m['guasto'] = false;
                m['stato'] = "Disponibile";
              });
              onSave();
              Navigator.pop(c);
            },
            child: const Text("RIPRISTINA"),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                m['guasto'] = true;
                m['notaGuasto'] = n;
                m['stato'] = "Manutenzione";
              });
              onSave();
              Navigator.pop(c);
            },
            child: const Text("SALVA"),
          ),
        ],
      ),
    );
  }

  Widget _paginaMagazzino() {
    String query = "";
    List<int> selezionati = [];
    return StatefulBuilder(builder: (context, setStateMag) {
      var filtrati = magazzino.where((m) => m['descrizione'].toLowerCase().contains(query.toLowerCase())).toList();
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.amber[600],
          title: TextField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(hintText: "Cerca articolo...", hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
            onChanged: (v) => setStateMag(() => query = v),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.description, color: Colors.white),
              onPressed: () {
                final articoliSelezionati = filtrati.where((art) => selezionati.contains(filtrati.indexOf(art))).toList();
                _generaFoglioPrelievo(articoliSelezionati);
              },
            ),
            IconButton(
              icon: const Icon(Icons.download, color: Colors.white),
              onPressed: () {
                final articoliSelezionati = filtrati.where((art) => selezionati.contains(filtrati.indexOf(art))).toList();
                _esportaMagazzinoExcel(articoliSelezionati);
              },
            ),
          ],
        ),
        body: Column(
          children: [
            if (selezionati.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Text("${selezionati.length} articoli selezionati", style: const TextStyle(color: Colors.brown, fontWeight: FontWeight.bold)),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: filtrati.length,
                itemBuilder: (c, i) {
                  return ListTile(
                    leading: Checkbox(
                      value: selezionati.contains(i),
                      onChanged: (v) {
                        setStateMag(() {
                          if (v == true) {
                            selezionati.add(i);
                          } else {
                            selezionati.remove(i);
                          }
                        });
                      },
                    ),
                    title: Text(filtrati[i]['descrizione']),
                    subtitle: Text("Quantità: ${filtrati[i]['quantita']}\nCategoria: ${filtrati[i]['categoria'] ?? 'N/A'}"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_haPermessoSezione('magazzino'))
                          IconButton(icon: const Icon(Icons.edit, color: Colors.grey), onPressed: () => _dialogNuovoArticolo(() => setStateMag(() {}), editArticolo: filtrati[i])),
                        if (_haPermessoSezione('magazzino'))
                          IconButton(icon: const Icon(Icons.delete, color: Colors.redAccent), onPressed: () async {
                            if (_usaCloud && filtrati[i]['id'] != null) {
                              try {
                                await _db.eliminaArticoloMagazzino(filtrati[i]['id']);
                                setState(() => magazzino.remove(filtrati[i]));
                                setStateMag(() {});
                              } catch (e) {
                                _snack("Errore eliminazione articolo: $e");
                              }
                            } else {
                              setState(() => magazzino.remove(filtrati[i]));
                              setStateMag(() {});
                            }
                          }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        floatingActionButton: _haPermessoSezione('magazzino') ? FloatingActionButton(backgroundColor: Colors.amber[600], child: const Icon(Icons.add), onPressed: () => _dialogNuovoArticolo(() => setStateMag(() {}))) : null,
      );
    });
  }

  void _dialogNuovoArticolo(VoidCallback onSave, {Map<String, dynamic>? editArticolo}) {
    String d = editArticolo?['descrizione'] ?? "", q = editArticolo?['quantita']?.toString() ?? "0";
    String categoria = editArticolo?['categoria'] ?? "elettricità";
    final categorie = ["elettricità", "idraulica", "attrezzature", "ferramenta", "aib"];
    
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(editArticolo == null ? "Nuovo Articolo" : "Modifica Articolo"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: TextEditingController(text: d), onChanged: (v) => d = v, decoration: const InputDecoration(labelText: "Descrizione")),
              TextField(controller: TextEditingController(text: q), onChanged: (v) => q = v, decoration: const InputDecoration(labelText: "Quantità"), keyboardType: TextInputType.number),
              DropdownButtonFormField<String>(
                value: categoria,
                decoration: const InputDecoration(labelText: "Categoria"),
                items: categorie.map((String cat) {
                  return DropdownMenuItem<String>(
                    value: cat,
                    child: Text(cat),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    categoria = newValue;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () async {
              if (_usaCloud && _sessionOrgId != null) {
                try {
                  if (editArticolo == null) {
                    final nuovoArticolo = {"descrizione": d, "quantita": int.tryParse(q) ?? 0, "categoria": categoria, "orgId": _sessionOrgId};
                    await _db.salvaArticoloMagazzino(nuovoArticolo, _sessionOrgId!);
                    magazzino.add(nuovoArticolo);
                  } else {
                    editArticolo['descrizione'] = d;
                    editArticolo['quantita'] = int.tryParse(q) ?? 0;
                    editArticolo['categoria'] = categoria;
                    await _db.salvaArticoloMagazzino(editArticolo, _sessionOrgId!);
                  }
                  setState(() {});
                  onSave();
                  Navigator.pop(c);
                } catch (e) {
                  _snack("Errore salvataggio articolo: $e");
                }
              } else {
                setState(() {
                  if (editArticolo == null) {
                    magazzino.add({"descrizione": d, "quantita": int.tryParse(q) ?? 0, "categoria": categoria});
                  } else {
                    editArticolo['descrizione'] = d;
                    editArticolo['quantita'] = int.tryParse(q) ?? 0;
                    editArticolo['categoria'] = categoria;
                  }
                });
                onSave();
                Navigator.pop(c);
              }
            },
            child: const Text("SALVA"),
          )
        ],
      ),
    );
  }

  void _esportaMagazzinoExcel(List<Map<String, dynamic>> articoli) {
    if (articoli.isEmpty) {
      _snack("Nessun articolo selezionato per l'esportazione");
      return;
    }
    
    String csv = "Descrizione;Quantità;Categoria\n";
    for (var art in articoli) {
      csv += "${art['descrizione']};${art['quantita']};${art['categoria'] ?? 'N/A'}\n";
    }
    
    // Crea un file temporaneo
    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    // Crea un link per il download
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "magazzino_export.csv")
      ..click();
    
    // Pulisce
    html.Url.revokeObjectUrl(url);
  }

  void _generaFoglioPrelievo(List<Map<String, dynamic>> articoli) {
    if (articoli.isEmpty) {
      _snack("Nessun articolo selezionato per il foglio di prelievo");
      return;
    }

    final now = DateTime.now();
    final data = "${now.day}/${now.month}/${now.year}";
    final ora = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    // Genera contenuto RTF compatibile con Word usando stringhe raw per struttura e concatenazione per dati
    String rtf = r"""{\rtf1\ansi\ansicpg1252\deff0\deflang1040{\fonttbl{\f0\fswiss\fcharset0 Arial;}}
{\colortbl;\red0\green0\blue0;}
\viewkind4\uc1\pard\qc\f0\fs24\b\fs28 PROTEZIONE CIVILE COMUNALE DI MENTANA\par
\pard\qc\b0\fs24\par
\pard\qc\b FOGLIO DI PRELIEVO MATERIALE\par
\pard\qc\b0\par
\pard\ql Data: """ + data + r"""\par
\pard\ql Ora: """ + ora + r"""\par
\pard\ql\par
\b\ul Elenco Materiale Prelievo:\b0\ul0\par
\par
""";

    int index = 1;
    for (var art in articoli) {
      final descrizione = art['descrizione'] ?? 'N/A';
      final quantita = art['quantita']?.toString() ?? '0';
      final categoria = art['categoria'] ?? 'N/A';
      
      rtf += r"""""" + index.toString() + r""". """ + descrizione + r"""\par
   Quantità: """ + quantita + r"""\par
   Categoria: """ + categoria + r"""\par
\par
""";
      index++;
    }

    rtf += r"""\pard\ql\par
\pard\ql\par
\pard\ql\b Note:\b0\par
\pard\ql\ul\par
\par
\par
\par
\pard\ql\b0\ul0\par
\pard\ql\par
\pard\ql\b Firma Responsabile:\b0\par
\pard\ql\par
\pard\ql\b Firma Operatore:\b0\par
\pard\ql\par
}""";

    final bytes = utf8.encode(rtf);
    final blob = html.Blob([bytes], 'application/rtf;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "foglio_prelievo_${now.day}${now.month}${now.year}.rtf")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  void _cancellaIntervento(Map<String, dynamic> intervento) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancella Intervento"),
        content: const Text("Sei sicuro di voler cancellare questo intervento?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            onPressed: () {
              setState(() => interventi.remove(intervento));
              Navigator.pop(c);
              _snack("Intervento cancellato", color: Colors.green);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CANCELLA"),
          ),
        ],
      ),
    );
  }

  void _cancellaInterventiSelezionati() {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancella Interventi Selezionati"),
        content: Text("Sei sicuro di voler cancellare ${selezionatiInterventi.length} interventi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            onPressed: () {
              var interventiArchiviati = interventi.where((i) => i['stato'] == "archiviato").toList();
              selezionatiInterventi.sort((a, b) => b.compareTo(a));
              for (var idx in selezionatiInterventi) {
                interventi.remove(interventiArchiviati[idx]);
              }
              selezionatiInterventi.clear();
              setState(() {});
              Navigator.pop(c);
              _snack("Interventi cancellati", color: Colors.green);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CANCELLA"),
          ),
        ],
      ),
    );
  }

  Widget _paginaPEC() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Piano Emergenza Comunale"),
        backgroundColor: Colors.red[700],
      ),
      body: pecFiles.isEmpty
          ? const Center(child: Text("Nessun file caricato", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: pecFiles.length,
              itemBuilder: (context, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                  title: Text(pecFiles[i]['nome']),
                  subtitle: Text("Caricato: ${pecFiles[i]['data']}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.download, color: Colors.blue),
                        onPressed: () => _downloadPECFile(pecFiles[i]),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        onPressed: () => _cancellaPECFile(i),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.red[700],
        child: const Icon(Icons.upload_file),
        onPressed: _caricaPECFile,
      ),
    );
  }

  Future<void> _caricaPECFile() async {
    final input = html.FileUploadInputElement()..accept = 'application/pdf';
    input.click();
    
    input.onChange.listen((e) async {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        final reader = html.FileReader();
        
        reader.onLoad.listen((e) {
          final result = reader.result as String;
          setState(() {
            pecFiles.add({
              'nome': file.name,
              'data': DateTime.now().toString().substring(0, 16),
              'contenuto': result,
              'dimensione': '${(file.size / 1024).toStringAsFixed(2)} KB',
            });
          });
          _snack("File caricato con successo", color: Colors.green);
        });
        
        reader.readAsDataUrl(file);
      }
    });
  }

  void _downloadPECFile(Map<String, dynamic> file) {
    final contenuto = file['contenuto'] as String;
    final bytes = base64Decode(contenuto.split(',').last);
    final blob = html.Blob([bytes], 'application/pdf');
    final url = html.Url.createObjectUrlFromBlob(blob);
    
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", file['nome'])
      ..click();
    
    html.Url.revokeObjectUrl(url);
  }

  void _cancellaPECFile(int index) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancella File"),
        content: const Text("Sei sicuro di voler cancellare questo file?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            onPressed: () {
              setState(() => pecFiles.removeAt(index));
              Navigator.pop(c);
              _snack("File cancellato", color: Colors.green);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CANCELLA"),
          ),
        ],
      ),
    );
  }

  Widget _paginaPresenza() {
    // Trova il volontario corrente usando l'email
    final userEmail = _db.client.auth.currentUser?.email;
    final volontarioCorrente = volontari.firstWhere(
      (v) => v['email'] == userEmail,
      orElse: () => <String, dynamic>{},
    );

    if (volontarioCorrente.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Presenza"), backgroundColor: Colors.teal[700]),
        body: const Center(child: Text("Volontario non trovato", style: TextStyle(color: Colors.grey))),
      );
    }

    final isInServizio = volontarioCorrente['stato'] == "Disponibile";

    return Scaffold(
      appBar: AppBar(title: const Text("Registra Presenza"), backgroundColor: Colors.teal[700]),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isInServizio ? Icons.check_circle : Icons.access_time,
              size: 100,
              color: isInServizio ? Colors.green : Colors.orange,
            ),
            const SizedBox(height: 20),
            Text(
              isInServizio ? "In Servizio" : "Fuori Servizio",
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              "Stato attuale: ${volontarioCorrente['stato']}",
              style: const TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 40),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 180,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () => _registraEntrata(volontarioCorrente),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      "ENTRATA",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                SizedBox(
                  width: 180,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: () => _registraUscita(volontarioCorrente),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      "USCITA",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _registraEntrata(Map<String, dynamic> volontario) async {
    if (volontario['stato'] == "Disponibile") {
      _snack("Sei già in servizio", color: Colors.orange);
      return;
    }

    final now = DateTime.now();
    final timestamp = "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    final nuovaRegistrazione = {
      'volontario_email': volontario['email'],
      'volontario_nome': volontario['nome'],
      'giorno': "${now.day}/${now.month}/${now.year}",
      'entrata': timestamp,
      'uscita': null,
    };

    if (_usaCloud && _sessionOrgId != null) {
      try {
        await _db.salvaRegistrazionePresenza(nuovaRegistrazione, _sessionOrgId!);
        // Aggiorna lo stato del volontario nel database
        volontario['stato'] = "Disponibile";
        await _db.salvaVolontare(volontario);
      } catch (e) {
        _snack("Errore salvataggio presenza: $e");
        return;
      }
    }

    setState(() {
      volontario['stato'] = "Disponibile";
      registrazioniPresenze.add(nuovaRegistrazione);
    });
    _snack("Entrata registrata con successo", color: Colors.green);
  }

  Future<void> _registraUscita(Map<String, dynamic> volontario) async {
    if (volontario['stato'] != "Disponibile") {
      _snack("Non sei in servizio", color: Colors.orange);
      return;
    }

    final now = DateTime.now();
    final timestamp = "${now.day}/${now.month}/${now.year} ${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Conferma Uscita"),
        content: const Text("Sei sicuro di voler registrare l'uscita dal servizio?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            onPressed: () async {
              // Trova e aggiorna l'ultima registrazione di entrata
              final ultimaRegistrazione = registrazioniPresenze.lastWhere(
                (r) => r['volontario_email'] == volontario['email'] && r['uscita'] == null,
                orElse: () => <String, dynamic>{},
              );
              
              if (ultimaRegistrazione.isNotEmpty) {
                ultimaRegistrazione['uscita'] = timestamp;
                
                if (_usaCloud && ultimaRegistrazione['id'] != null) {
                  try {
                    await _db.salvaRegistrazionePresenza(ultimaRegistrazione, _sessionOrgId!);
                    // Aggiorna lo stato del volontario nel database
                    volontario['stato'] = "Non Disponibile";
                    await _db.salvaVolontare(volontario);
                  } catch (e) {
                    _snack("Errore aggiornamento presenza: $e");
                    return;
                  }
                }
              }

              setState(() {
                volontario['stato'] = "Non Disponibile";
              });
              Navigator.pop(c);
              _snack("Uscita registrata con successo", color: Colors.green);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CONFERMA"),
          ),
        ],
      ),
    );
  }

  Widget _paginaGestionePresenze() {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Gestione Presenze"),
        backgroundColor: Colors.amber[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.download, color: Colors.white),
            onPressed: () => _esportaPresenzeExcel(),
          ),
        ],
      ),
      body: registrazioniPresenze.isEmpty
          ? const Center(child: Text("Nessuna registrazione di presenza", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: registrazioniPresenze.length,
              itemBuilder: (context, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  leading: const Icon(Icons.person, color: Colors.amber),
                  title: Text(registrazioniPresenze[i]['volontario_nome']),
                  subtitle: Text(
                    "Giorno: ${registrazioniPresenze[i]['giorno']}\nEntrata: ${registrazioniPresenze[i]['entrata']}\nUscita: ${registrazioniPresenze[i]['uscita'] ?? 'In corso'}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent),
                    onPressed: () => _cancellaRegistrazionePresenza(i),
                  ),
                ),
              ),
            ),
    );
  }

  void _esportaPresenzeExcel() {
    if (registrazioniPresenze.isEmpty) {
      _snack("Nessuna registrazione da esportare");
      return;
    }

    String csv = "Volontario;Giorno;Entrata;Uscita\n";
    for (var reg in registrazioniPresenze) {
      csv += "${reg['volontario_nome']};${reg['giorno']};${reg['entrata']};${reg['uscita'] ?? 'In corso'}\n";
    }

    final bytes = utf8.encode(csv);
    final blob = html.Blob([bytes], 'text/csv;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "presenze_export.csv")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  void _cancellaRegistrazionePresenza(int index) async {
    final registrazione = registrazioniPresenze[index];
    
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Cancella Registrazione"),
        content: const Text("Sei sicuro di voler cancellare questa registrazione?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            onPressed: () async {
              if (_usaCloud && registrazione['id'] != null) {
                try {
                  await _db.eliminaRegistrazionePresenza(registrazione['id']);
                } catch (e) {
                  _snack("Errore eliminazione presenza: $e");
                  return;
                }
              }
              
              setState(() => registrazioniPresenze.removeAt(index));
              Navigator.pop(c);
              _snack("Registrazione cancellata", color: Colors.green);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("CANCELLA"),
          ),
        ],
      ),
    );
  }

  Widget _paginaSalaRadio() {
    var interventiInCorso = interventi.where((i) => i['stato'] == "sala_radio").toList();
    return Scaffold(
      appBar: AppBar(title: const Text("Sala Radio"), backgroundColor: Colors.green[700]),
      body: interventiInCorso.isEmpty
          ? const Center(child: Text("Nessun intervento in corso", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              itemCount: interventiInCorso.length,
              itemBuilder: (context, i) => Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text(interventiInCorso[i]['titolo']),
                  subtitle: Text("Inizio: ${interventiInCorso[i]['inizio']}\nMezzi: ${interventiInCorso[i]['mezzi'].join(", ")}\nVolontari: ${interventiInCorso[i]['volontari_impegnati'].join(", ")}"),
                  leading: const Icon(Icons.radio, color: Colors.green),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _dialogDettaglioIntervento(interventiInCorso[i], () => setState(() {})),
                  ),
                ),
              ),
            ),
    );
  }

  void _dialogNuovoIntervento() {
    Map<String, dynamic> nuovo = {"titolo": "", "descrizione": "", "segnalato_da": "", "inizio": "", "fine": null, "foto": null, "mezzi": [], "volontari_impegnati": [], "stato": "sala_radio"};
    String loc = "", tipo = "Incendio", descrizione = "", segnalatoDa = "";
    List<String> mezziSel = [];
    List<String> volSel = [];
    var mezziDisp = mezzo.where((m) => !m['guasto'] && m['stato'] == "Disponibile").toList();
    var volDisp = volontari.where((v) => v['stato'] == "Disponibile").toList();

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setD) => AlertDialog(
          title: const Text("Nuovo Intervento"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  value: tipo,
                  isExpanded: true,
                  items: ["Incendio", "Allagamento", "Soccorso", "Altro"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                  onChanged: (v) => setD(() => tipo = v!),
                ),
                const Text("Mezzi:"),
                Wrap(children: mezziDisp.map((m) => FilterChip(label: Text(m['nome']), selected: mezziSel.contains(m['nome']), onSelected: (s) => setD(() => s ? mezziSel.add(m['nome']) : mezziSel.remove(m['nome'])))).toList()),
                const Text("Volontari:"),
                Wrap(children: volDisp.map((v) => FilterChip(label: Text(v['nome']), selected: volSel.contains(v['nome']), onSelected: (s) => setD(() => s ? volSel.add(v['nome']) : volSel.remove(v['nome'])))).toList()),
                TextField(onChanged: (v) => loc = v, decoration: const InputDecoration(labelText: "Località")),
                TextField(onChanged: (v) => descrizione = v, maxLines: 3, decoration: const InputDecoration(labelText: "Descrizione")),
                TextField(onChanged: (v) => segnalatoDa = v, decoration: const InputDecoration(labelText: "Segnalato da")),
                TextButton.icon(onPressed: () => _scattaFoto(nuovo, setD), icon: const Icon(Icons.camera_alt), label: const Text("FOTO")),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () async {
                setState(() {
                  nuovo['titolo'] = "[$tipo] $loc";
                  nuovo['descrizione'] = descrizione;
                  nuovo['segnalato_da'] = segnalatoDa;
                  nuovo['inizio'] = "${DateTime.now().hour}:${DateTime.now().minute}";
                  nuovo['mezzi'] = mezziSel;
                  nuovo['volontari_impegnati'] = volSel;
                  nuovo['stato'] = "sala_radio";
                  for (var m in mezziSel) mezzo.firstWhere((e) => e['nome'] == m)['stato'] = "In Intervento";
                  for (var v in volSel) volontari.firstWhere((e) => e['nome'] == v)['stato'] = "In Intervento";
                  interventi.insert(0, nuovo);
                });
                
                if (_usaCloud && _sessionOrgId != null) {
                  try {
                    await _db.salvaIntervento(nuovo, _sessionOrgId!);
                  } catch (e) {
                    _snack("Errore salvataggio intervento: $e");
                    return;
                  }
                }
                
                Navigator.pop(c);
              },
              child: const Text("AVVIA"),
            )
          ],
        ),
      ),
    );
  }

  Widget _paginaArchivioInterventi() {
    var interventiArchiviati = interventi.where((i) => i['stato'] == "archiviato").toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text("Archivio Generale"),
        backgroundColor: Colors.blueGrey[700],
        actions: [
          IconButton(icon: const Icon(Icons.description, color: Colors.white), onPressed: () => _generaRapportinoIntervento()),
          IconButton(icon: const Icon(Icons.share, color: Colors.white), onPressed: _esportaSelezionati),
          if (selezionatiInterventi.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete, color: Colors.white), onPressed: () => _cancellaInterventiSelezionati()),
        ],
      ),
      body: (interventiArchiviati.isEmpty && segnalazioni.isEmpty)
          ? const Center(child: Text("Archivio vuoto", style: TextStyle(color: Colors.grey)))
          : CustomScrollView(
              slivers: [
                if (interventiArchiviati.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(12.0),
                      child: Text("INTERVENTI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueGrey)),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ListTile(
                        title: Text(interventiArchiviati[i]['titolo']),
                        subtitle: Text("Inizio: ${interventiArchiviati[i]['inizio']}\nFine: ${interventiArchiviati[i]['fine']}"),
                        leading: Checkbox(
                          value: selezionatiInterventi.contains(i),
                          onChanged: (v) => setState(() => v! ? selezionatiInterventi.add(i) : selezionatiInterventi.remove(i)),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _cancellaIntervento(interventiArchiviati[i]),
                        ),
                        onTap: () => _dialogDettaglioIntervento(interventiArchiviati[i], () => setState(() {})),
                      ),
                      childCount: interventiArchiviati.length,
                    ),
                  ),
                ],
                if (segnalazioni.isNotEmpty) ...[
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.only(left: 12.0, right: 12.0, top: 24.0, bottom: 12.0),
                      child: Text("SEGNALAZIONI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.purple)),
                    ),
                  ),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => ListTile(
                        title: Text(segnalazioni[i]['oggetto'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(segnalazioni[i]['descrizione'] ?? ""),
                        leading: Checkbox(
                          value: listaSegnalazioniSelezionate.contains(i),
                          activeColor: Colors.purple,
                          onChanged: (v) => setState(() => v! ? listaSegnalazioniSelezionate.add(i) : listaSegnalazioniSelezionate.remove(i)),
                        ),
                      ),
                      childCount: segnalazioni.length,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  void _generaRapportinoIntervento() {
    var interventiArchiviati = interventi.where((i) => i['stato'] == "archiviato").toList();
    if (interventiArchiviati.isEmpty) {
      _snack("Nessun intervento archiviato per il rapportino");
      return;
    }

    final now = DateTime.now();
    final data = "${now.day}/${now.month}/${now.year}";
    final ora = "${now.hour}:${now.minute.toString().padLeft(2, '0')}";

    // Costruisci la stringa RTF usando stringhe raw per la struttura e interpolazione per i dati
    String rtf = r"""{\rtf1\ansi\ansicpg1252\deff0\deflang1040{\fonttbl{\f0\fswiss\fcharset0 Arial;}}
{\colortbl;\red0\green0\blue0;}
\viewkind4\uc1\pard\qc\f0\fs24\b\fs28 PROTEZIONE CIVILE COMUNALE\par
\pard\qc\b0\fs24\par
\pard\qc\b RAPPORTINO INTERVENTO\par
\pard\qc\b0\par
\pard\ql Data: """ + data + r"""\par
\pard\ql Ora: """ + ora + r"""\par
\pard\ql\par
\b\ul Elenco Interventi:\b0\ul0\par
\par
""";

    int index = 1;
    for (var inter in interventiArchiviati) {
      final mezziList = inter['mezzi'] is List ? (inter['mezzi'] as List).join(", ") : 'Nessuno';
      final volList = inter['volontari_impegnati'] is List ? (inter['volontari_impegnati'] as List).join(", ") : 'Nessuno';
      final titolo = inter['titolo'] ?? 'Senza titolo';
      final descrizione = inter['descrizione'] ?? 'N/A';
      final segnalatoDa = inter['segnalato_da'] ?? 'N/A';
      final inizio = inter['inizio'] ?? 'N/A';
      final fine = inter['fine'] ?? 'In corso';
      
      rtf += r"""""" + index.toString() + r""". """ + titolo + r"""\par
   Descrizione: """ + descrizione + r"""\par
   Segnalato da: """ + segnalatoDa + r"""\par
   Inizio: """ + inizio + r"""\par
   Fine: """ + fine + r"""\par
   Mezzi: """ + mezziList + r"""\par
   Volontari: """ + volList + r"""\par
\par
""";
      index++;
    }

    rtf += r"""\pard\ql\par
\pard\ql\b Note:\b0\par
\pard\ql\ul\par
\par
\par
\par
\pard\ql\b0\ul0\par
\pard\ql\par
\pard\ql\b Firma Responsabile:\b0\par
\pard\ql\par
\pard\ql\b Firma Operatore:\b0\par
\pard\ql\par
}""";

    final bytes = utf8.encode(rtf);
    final blob = html.Blob([bytes], 'application/rtf;charset=utf-8;');
    final url = html.Url.createObjectUrlFromBlob(blob);

    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "rapportino_intervento_${now.day}${now.month}${now.year}.rtf")
      ..click();

    html.Url.revokeObjectUrl(url);
  }

  void _dialogDettaglioIntervento(Map<String, dynamic> inter, VoidCallback refresh) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(inter['titolo']),
        content: Text("Mezzi: ${inter['mezzi'].join(", ")}\nInizio: ${inter['inizio']}\nFine: ${inter['fine'] ?? 'Operativo'}"),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(c);
              _dialogModificaRapportino(inter, refresh);
            },
            child: const Text("MODIFICA"),
          ),
          if (inter['fine'] == null)
            ElevatedButton(
              onPressed: () {
                setState(() {
                  inter['fine'] = "${DateTime.now().hour}:${DateTime.now().minute}";
                  inter['stato'] = "archiviato";
                  for (var m in inter['mezzi']) mezzo.firstWhere((e) => e['nome'] == m)['stato'] = "Disponibile";
                  for (var v in inter['volontari_impegnati']) volontari.firstWhere((e) => e['nome'] == v)['stato'] = "Disponibile";
                });
                refresh();
                Navigator.pop(c);
              },
              child: const Text("CHIUDI"),
            ),
        ],
      ),
    );
  }

  void _dialogModificaRapportino(Map<String, dynamic> inter, VoidCallback refresh) {
    String nuovoTitolo = inter['titolo'];
    String vImpiegati = inter['volontari_impegnati'].isEmpty
        ? "Nessun volontario assegnato"
        : inter['volontari_impegnati'].join(", ");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Modifica Rapportino"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: TextEditingController(text: nuovoTitolo),
              onChanged: (v) => nuovoTitolo = v,
              decoration: const InputDecoration(labelText: "Dettaglio Intervento"),
            ),
            const SizedBox(height: 20),
            const Text(
              "Volontari Impiegati:",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey),
            ),
            const SizedBox(height: 5),
            Text(vImpiegati, style: const TextStyle(fontSize: 14, color: Colors.black87)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("ANNULLA")),
          ElevatedButton(
            onPressed: () {
              setState(() => inter['titolo'] = nuovoTitolo);
              refresh();
              Navigator.pop(c);
            },
            child: const Text("SALVA"),
          ),
        ],
      ),
    );
  }

  Future<void> _esportaSelezionati() async {
    if (selezionatiInterventi.isEmpty && listaSegnalazioniSelezionate.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Seleziona almeno un elemento da esportare!"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String reportContenuto = "=== REPORT GENERALE PROTEZIONE CIVILE ===\n";
    reportContenuto += "Generato il: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}\n\n";

    if (selezionatiInterventi.isNotEmpty) {
      reportContenuto += ">> INTERVENTI SELEZIONATI <<\n";
      for (var idx in selezionatiInterventi) {
        var intv = interventi[idx];
        reportContenuto += "----------------------------------------\n";
        reportContenuto += "INTERVENTO: ${intv['titolo']}\n";
        reportContenuto += "Orario Inizio: ${intv['inizio']}\n";
        reportContenuto += "Orario Fine: ${intv['fine'] ?? 'Ancora Operativo'}\n";
        reportContenuto += "Mezzi: ${intv['mezzi'].isEmpty ? 'Nessuno' : intv['mezzi'].join(', ')}\n";
        reportContenuto += "Volontari: ${intv['volontari_impegnati'].isEmpty ? 'Nessuno' : intv['volontari_impegnati'].join(', ')}\n";
      }
      reportContenuto += "----------------------------------------\n\n";
    }

    if (listaSegnalazioniSelezionate.isNotEmpty) {
      reportContenuto += ">> SEGNALAZIONI SELEZIONATE <<\n";
      for (var idx in listaSegnalazioniSelezionate) {
        var segn = segnalazioni[idx];
        reportContenuto += "----------------------------------------\n";
        reportContenuto += "OGGETTO: ${segn['oggetto']}\n";
        reportContenuto += "DESCRIZIONE: ${segn['descrizione']}\n";
      }
      reportContenuto += "----------------------------------------\n\n";
    }

    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        reportContenuto,
        subject: 'Report Protezione Civile',
        sharePositionOrigin: box != null ? box.localToGlobal(Offset.zero) & box.size : null,
      );
      setState(() {
        selezionatiInterventi.clear();
        listaSegnalazioniSelezionate.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Errore durante l'invio: $e"), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _scattaFoto(Map<String, dynamic> item, StateSetter setD) async {
    final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
    if (photo != null) setD(() => item['foto'] = photo.path);
  }

  Widget _buildRegistrazioneVolontario() {
    final emailRegController = TextEditingController();
    final nomeRegController = TextEditingController();
    final cognomeRegController = TextEditingController();
    final passRegController = TextEditingController();
    final pass2RegController = TextEditingController();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Registrazione Volontario"),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              "Registrazione solo su invito",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              "Inserisci la stessa email usata dal master nell'invito. Nessuna email viene inviata dall'app: l'invito è già nella cartella dell'organizzazione.",
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            TextField(controller: nomeRegController, decoration: const InputDecoration(labelText: "Nome")),
            const SizedBox(height: 10),
            TextField(controller: cognomeRegController, decoration: const InputDecoration(labelText: "Cognome")),
            const SizedBox(height: 10),
            TextField(
              controller: emailRegController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: "Email (come nell'invito)"),
            ),
            const SizedBox(height: 10),
            TextField(controller: passRegController, obscureText: true, decoration: const InputDecoration(labelText: "Password")),
            const SizedBox(height: 10),
            TextField(controller: pass2RegController, obscureText: true, decoration: const InputDecoration(labelText: "Conferma password")),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _operazioneInCorso
                  ? null
                  : () async {
                      final nome = nomeRegController.text.trim();
                      final cognome = cognomeRegController.text.trim();
                      final email = _normEmail(emailRegController.text);
                      final pass = passRegController.text;
                      final pass2 = pass2RegController.text;

                      if (nome.isEmpty || cognome.isEmpty || !email.contains('@')) {
                        _snack("Compila nome, cognome e email valida.");
                        return;
                      }
                      final minPass = _usaCloud ? 6 : 4;
                      if (pass.length < minPass) {
                        _snack("Password minimo $minPass caratteri.");
                        return;
                      }
                      if (pass != pass2) {
                        _snack("Le password non coincidono.");
                        return;
                      }

                      if (_usaCloud) {
                        await _esegui(() async {
                          final trovato = await _db.trovaInvitoPendente(email);
                          if (trovato == null) {
                            throw Exception('Non risulti invitato. Chiedi al master di aggiungerti nella cartella inviti.');
                          }
                          final org = trovato['org'] as Map<String, dynamic>;
                          final invito = trovato['invito'] as Map<String, dynamic>;
                          final sessione = await _db.registraVolontario(
                            nome: nome,
                            cognome: cognome,
                            email: email,
                            password: pass,
                            invitoId: invito['id'] as String,
                            orgId: org['id'] as String,
                            orgNome: org['nome'] as String,
                          );
                          organizzazioni
                            ..clear()
                            ..add(await _db.caricaOrganizzazione(sessione.orgId));
                          volontari = await _db.caricaVolontari(sessione.orgId);
                          setState(() {
                            _inRegistrazioneVolontario = false;
                            _isAuthenticated = true;
                            _isMasterUser = false;
                            _isVolontarioUser = true;
                            _sessionOrgId = sessione.orgId;
                            _haOrgCloud = true;
                          });
                        }, messaggioOk: "Registrazione completata su Supabase.");
                        return;
                      }

                      final trovato = _trovaInvitoPendente(email);
                      if (trovato == null) {
                        _snack("Non risulti invitato. Chiedi al master di aggiungerti nella cartella inviti.");
                        return;
                      }

                      final org = trovato['org'] as Map<String, dynamic>;
                      final invito = trovato['invito'] as Map<String, dynamic>;

                      final accounts = List<Map<String, dynamic>>.from(org['accountVolontari'] as List);
                      if (accounts.any((a) => _normEmail(a['email'] as String) == email)) {
                        _snack("Email già registrata. Effettua il login.");
                        return;
                      }

                      invito['stato'] = 'registrato';
                      invito['dataRegistrazione'] = DateTime.now().toIso8601String();

                      final nomeCompleto = '$nome $cognome';
                      accounts.add({
                        'email': email,
                        'password': pass,
                        'nome': nome,
                        'cognome': cognome,
                      });
                      org['accountVolontari'] = accounts;

                      volontari.add({
                        'nome': nomeCompleto,
                        'ruolo': 'Volontario',
                        'patenteC': false,
                        'stato': 'Disponibile',
                        'inServizio': true,
                        'orgId': org['id'],
                        'orgNome': org['nome'],
                        'email': email,
                        'permessi': 'pieno_accesso',
                      });

                      setState(() {
                        _inRegistrazioneVolontario = false;
                        _isAuthenticated = true;
                        _isMasterUser = false;
                        _isVolontarioUser = true;
                        _sessionOrgId = org['id'] as String;
                      });

                      _snack("Registrazione completata. Sei nella casa: ${org['nome']}", color: Colors.green);
                    },
              child: const Text("Completa Registrazione"),
            ),
            TextButton(
              onPressed: () => setState(() => _inRegistrazioneVolontario = false),
              child: const Text("Torna al Login"),
            ),
          ],
        ),
      ),
    );
  }
}