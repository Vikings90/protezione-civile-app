# Collegare IO SONO V a Supabase

## 1. Crea il progetto Supabase

1. Vai su [https://supabase.com](https://supabase.com) e crea un account.
2. **New project** → scegli nome e password database.
3. Attendi che il progetto sia pronto.

## 2. Crea le tabelle

1. Nel menu: **SQL Editor** → **New query**.
2. Copia tutto il contenuto di `supabase/schema.sql` e clicca **Run**.

## 3. Auth (importante per i test)

1. **Authentication** → **Providers** → **Email**.
2. **Enable Email provider** = ON (verde) — non basta da solo.
3. **Confirm email** = **OFF** / disattivato — fondamentale: se è ON, ogni registrazione invia mail e compare l’errore *rate limit* (429).
4. Clicca **Save**.
5. In produzione potrai riattivare la conferma email e configurare SMTP.

### Errore "over_email_send_rate_limit" (429)

- Hai premuto Registrati troppe volte: **aspetta 1 minuto**.
- L’account può **esistere già**: usa **ACCEDI** con la stessa email/password (non registrarti di nuovo).
- In **Authentication** → **Users** controlla se l’email c’è già; in test puoi eliminare l’utente e riprovare.
- Verifica che **Confirm email** sia **spenta** (vedi sopra).

## 4. Chiavi API nell'app

1. **Project Settings** → **API**.
2. Copia **Project URL** e **anon public** key.
3. Apri `lib/config/supabase_config.dart` e sostituisci:

```dart
defaultValue: 'https://TUO_PROJECT_ID.supabase.co',  // → il tuo URL
defaultValue: 'LA_TUA_CHIAVE_ANON',                   // → la tua anon key
```

Oppure avvia con:

```bash
flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbG...
```

## 5. Installa dipendenze e avvia

```bash
flutter pub get
flutter run
```

Se Supabase è configurato, l'app usa il cloud. Altrimenti resta in modalità locale (memoria).

## Flusso cloud

| Azione | Supabase |
|--------|----------|
| Crea associazione | `auth.signUp` + tabella `organizzazioni` + `profili` (master) |
| Login master/volontario | `auth.signInWithPassword` + lettura `profili` |
| Invita volontario | insert in `inviti` |
| Registrazione volontario | verifica invito → `signUp` → aggiorna invito → `profili` + `volontari` |
| Lista volontari | tabella `volontari` filtrata per `org_id` |

## Recupero password (più associazioni)

Ogni associazione ha **email master** e **codice master** propri (il codice deve essere **unico** tra tutte le sedi).

| Chi | Cosa inserisce | Cosa succede |
|-----|----------------|--------------|
| **Master** | Email della sede + codice master | Supabase invia link per nuova password (se SMTP attivo) |
| **Volontario** | Solo la sua email | Link reset solo se è già registrato |

Esegui anche `supabase/migration_codice_master_unico.sql` se il database esisteva già.

Senza SMTP configurato: il master può reimpostare password da **Authentication → Users** nel pannello Supabase.

## Risoluzione problemi

- **Invalid API key**: controlla URL e anon key in `supabase_config.dart`.
- **Row Level Security**: riesegui `schema.sql` se le query falliscono.
- **Email not confirmed**: disattiva conferma email in Auth (passo 3).
