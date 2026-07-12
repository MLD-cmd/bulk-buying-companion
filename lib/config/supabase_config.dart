class SupabaseConfig {
  const SupabaseConfig({required this.url, required this.anonKey});

  final String url;
  final String anonKey;

  factory SupabaseConfig.fromEnvironment(Map<String, String> environment) {
    final url = environment['SUPABASE_URL']?.trim() ?? '';
    final anonKey = environment['SUPABASE_ANON_KEY']?.trim() ?? '';
    if (url.isEmpty || anonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_ANON_KEY must be set in the local .env file.',
      );
    }
    return SupabaseConfig(url: url, anonKey: anonKey);
  }
}
