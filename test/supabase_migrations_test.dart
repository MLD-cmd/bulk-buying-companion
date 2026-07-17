import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migrations =
      Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.sql'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  String migration(String name) {
    final file = migrations.singleWhere((file) => file.path.endsWith(name));
    return file.readAsStringSync();
  }

  String allMigrations() =>
      migrations.map((file) => file.readAsStringSync()).join('\n');

  group('Supabase migrations', () {
    test('define deals before later migrations depend on it', () {
      final core = migration('20260713000000_create_core_hub_tables.sql');
      final all = allMigrations();

      expect(core, contains('create table if not exists public.deals'));
      expect(
        all.indexOf('create table if not exists public.deals'),
        lessThan(
          all.indexOf('create table if not exists public.deal_reservations'),
        ),
      );
      expect(core, contains('create or replace view public.deal_feed'));
    });

    test('scope deals and deal views to the signed-in student hub', () {
      final all = allMigrations();

      expect(all, contains('create policy "deals select in own hub"'));
      expect(all, contains('create policy "deals insert in own hub"'));
      expect(all, contains('revoke delete on public.deals from authenticated'));
      expect(all, isNot(contains('create policy "deals delete')));

      final finalDealFeed = migration('20260716000000_add_deal_lifecycle.sql');
      expect(finalDealFeed, contains('create view public.deal_feed as'));
      expect(finalDealFeed, contains('where exists ('));
      expect(finalDealFeed, contains('m.hub_id = d.hub_id'));
      expect(finalDealFeed, contains('m.user_id = (select auth.uid())'));
      expect(
        finalDealFeed,
        contains('create view public.deal_participants as'),
      );
    });

    test('deal participant names fall back when display names are missing', () {
      final all = allMigrations();

      expect(all, contains("split_part(p.email, '@', 1)"));
      expect(all, contains('as student_name'));
      expect(all, contains('as host_name'));
    });

    test('existing auth users with missing profiles are backfilled', () {
      final all = allMigrations();

      expect(all, contains('from auth.users u'));
      expect(all, contains('insert into public.profiles'));
      expect(all, contains('where not exists'));
    });

    test('deal and user reports are stored behind own-row RLS', () {
      final all = allMigrations();

      expect(all, contains('create table if not exists public.reports'));
      expect(
        all,
        contains('alter table public.reports enable row level security'),
      );
      expect(all, contains('reports insert own row'));
      expect(all, contains('reports select own rows'));
      expect(all, contains('reporter_id = (select auth.uid())'));
      expect(all, contains('reports_reporter_id_idx'));
      expect(all, contains('reports_deal_id_idx'));
      expect(all, contains('reports_reported_user_id_idx'));
      expect(
        all,
        contains(
          'alter publication supabase_realtime add table public.reports',
        ),
      );
    });

    test('publishes realtime source tables used by live screens', () {
      final all = allMigrations();

      for (final table in [
        'public.deals',
        'public.deal_reservations',
        'public.hubs',
        'public.hub_memberships',
        'public.reports',
      ]) {
        expect(
          all,
          contains('alter publication supabase_realtime add table $table'),
        );
      }
    });

    test('rejects sub-centavo deal prices in schema source', () {
      final all = allMigrations();

      expect(all, contains('deals_total_price_check'));
      expect(all, contains('check (total_price >= 0.01)'));
      expect(all, isNot(contains('check (total_price > 0)')));
    });
  });
}
