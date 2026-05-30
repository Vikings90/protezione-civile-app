/// Inserisci qui URL e chiave anon del tuo progetto Supabase
/// (Dashboard → Project Settings → API).
///
/// In alternativa avvia l'app con:
/// flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJ...
class SupabaseConfig {
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://nzxuhgyfootqnvjurpaw.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im56eHVoZ3lmb290cW52anVycGF3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk2MzY3NTQsImV4cCI6MjA5NTIxMjc1NH0.bbrALCKHq2p-ZXsZ4dD_bHgx0s2Ldt-6D2U217SVwgw',
  );

  static bool get isConfigured =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      !url.contains('TUO_PROJECT_ID') &&
      anonKey != 'LA_TUA_CHIAVE_ANON';
}
