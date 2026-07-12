import 'package:bulk_buying_companion/config/supabase_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads Supabase values from environment entries', () {
    final config = SupabaseConfig.fromEnvironment({
      'SUPABASE_URL': 'https://project.supabase.co',
      'SUPABASE_ANON_KEY': 'anon-key',
    });

    expect(config.url, 'https://project.supabase.co');
    expect(config.anonKey, 'anon-key');
  });

  test('throws a readable error when configuration is missing', () {
    expect(
      () => SupabaseConfig.fromEnvironment(const {}),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('SUPABASE_URL and SUPABASE_ANON_KEY'),
        ),
      ),
    );
  });
}
