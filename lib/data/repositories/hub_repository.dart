import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/hub.dart';

/// Hub data + membership contract. Backed by [MockHubRepository] until
/// the real backend (Supabase) is wired; the ViewModel never depends on
/// the concrete implementation.
abstract class HubRepository {
  Future<List<Hub>> getHubs();

  Future<void> joinHub({required String userId, required String hubId});

  Future<void> leaveHub({required String userId});

  Future<String?> getCurrentHubId(String userId);
}

/// In-memory stand-in. Data is stubbed — the hub names below are
/// placeholders (real streets near USJR, invented establishment names),
/// not verified real boarding houses.
class MockHubRepository implements HubRepository {
  MockHubRepository()
      : _hubs = const [
          Hub(
            id: 'magallanes',
            name: 'Magallanes Residence',
            type: HubType.dormitory,
            memberCount: 24,
            distanceLabel: '150 m',
          ),
          Hub(
            id: 'burgos',
            name: 'P. Burgos Boarding House',
            type: HubType.dormitory,
            memberCount: 18,
            distanceLabel: '300 m',
          ),
          Hub(
            id: 'colon',
            name: 'Colon Street Hub',
            type: HubType.areaHub,
            memberCount: 31,
            distanceLabel: '400 m',
          ),
          Hub(
            id: 'sanciangko',
            name: 'Sanciangko Apartments',
            type: HubType.dormitory,
            memberCount: 12,
            distanceLabel: '600 m',
          ),
          Hub(
            id: 'junquera',
            name: 'Junquera Area Hub',
            type: HubType.areaHub,
            memberCount: 9,
            distanceLabel: '850 m',
          ),
        ];

  final List<Hub> _hubs;
  final Map<String, String> _membership = {};

  @override
  Future<List<Hub>> getHubs() async => _hubs;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {
    _membership[userId] = hubId;
  }

  @override
  Future<void> leaveHub({required String userId}) async {
    _membership.remove(userId);
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => _membership[userId];
}

abstract class SupabaseHubGateway {
  Future<List<Map<String, dynamic>>> getHubDirectory();

  Future<void> upsertMembership({
    required String userId,
    required String hubId,
  });

  Future<void> deleteMembership(String userId);

  Future<String?> getCurrentHubId(String userId);
}

class PostgrestSupabaseHubGateway implements SupabaseHubGateway {
  PostgrestSupabaseHubGateway(this._client);

  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> getHubDirectory() async {
    final rows = await _client.from('hub_directory').select().order('name');
    return List<Map<String, dynamic>>.from(rows);
  }

  @override
  Future<void> upsertMembership({
    required String userId,
    required String hubId,
  }) async {
    await _client.from('hub_memberships').upsert({
      'user_id': userId,
      'hub_id': hubId,
    }, onConflict: 'user_id');
  }

  @override
  Future<void> deleteMembership(String userId) async {
    await _client.from('hub_memberships').delete().eq('user_id', userId);
  }

  @override
  Future<String?> getCurrentHubId(String userId) async {
    final row = await _client
        .from('hub_memberships')
        .select('hub_id')
        .eq('user_id', userId)
        .maybeSingle();
    return row?['hub_id'] as String?;
  }
}

class SupabaseHubRepository implements HubRepository {
  SupabaseHubRepository({required SupabaseHubGateway gateway})
    : _gateway = gateway;

  final SupabaseHubGateway _gateway;

  @override
  Future<List<Hub>> getHubs() async {
    final rows = await _gateway.getHubDirectory();
    return rows.map(_mapHub).toList();
  }

  @override
  Future<void> joinHub({required String userId, required String hubId}) {
    return _gateway.upsertMembership(userId: userId, hubId: hubId);
  }

  @override
  Future<void> leaveHub({required String userId}) {
    return _gateway.deleteMembership(userId);
  }

  @override
  Future<String?> getCurrentHubId(String userId) {
    return _gateway.getCurrentHubId(userId);
  }

  Hub _mapHub(Map<String, dynamic> row) {
    return Hub(
      id: row['id'] as String,
      name: row['name'] as String,
      type: _mapHubType(row['type'] as String),
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      distanceLabel: row['distance_label'] as String? ?? '',
    );
  }

  HubType _mapHubType(String value) {
    return switch (value) {
      'area_hub' => HubType.areaHub,
      'dormitory' => HubType.dormitory,
      _ => throw StateError('Unknown hub type "$value".'),
    };
  }
}
