import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/hub.dart';

/// Hub data + membership contract. Backed by [MockHubRepository] in tests and
/// [SupabaseHubRepository] in production; the ViewModel never depends on the
/// concrete implementation.
abstract class HubRepository {
  Future<List<Hub>> getHubs();

  Future<Hub> createHub(HubDraft draft);

  Future<void> joinHub({required String userId, required String hubId});

  Future<void> leaveHub({required String userId});

  Future<String?> getCurrentHubId(String userId);
}

class HubDirectorySnapshot {
  const HubDirectorySnapshot({required this.hubs, required this.joinedHubId});

  final List<Hub> hubs;
  final String? joinedHubId;
}

abstract class RealtimeHubRepository {
  Stream<HubDirectorySnapshot> watchHubDirectory(String userId);
}

/// Raised when a hub cannot be registered. The message is user-facing.
class HubFailure implements Exception {
  const HubFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// In-memory stand-in. Data is stubbed — the hub names below are placeholders
/// (real streets near USJR, invented establishment names), and the coordinates
/// are approximate points around the campus, not surveyed locations.
class MockHubRepository implements HubRepository {
  MockHubRepository()
    : _hubs = [
        const Hub(
          id: 'magallanes',
          name: 'Magallanes Residence',
          type: HubType.dormitory,
          memberCount: 24,
          distanceLabel: '150 m',
          latitude: 10.2954,
          longitude: 123.8969,
        ),
        const Hub(
          id: 'burgos',
          name: 'P. Burgos Boarding House',
          type: HubType.dormitory,
          memberCount: 18,
          distanceLabel: '300 m',
          latitude: 10.2963,
          longitude: 123.8951,
        ),
        const Hub(
          id: 'colon',
          name: 'Colon Street Hub',
          type: HubType.areaHub,
          memberCount: 31,
          distanceLabel: '400 m',
          latitude: 10.2967,
          longitude: 123.8988,
        ),
        const Hub(
          id: 'sanciangko',
          name: 'Sanciangko Apartments',
          type: HubType.dormitory,
          memberCount: 12,
          distanceLabel: '600 m',
          latitude: 10.2939,
          longitude: 123.8949,
        ),
        const Hub(
          id: 'junquera',
          name: 'Junquera Area Hub',
          type: HubType.areaHub,
          memberCount: 9,
          distanceLabel: '850 m',
          latitude: 10.2975,
          longitude: 123.8939,
        ),
      ];

  final List<Hub> _hubs;
  final Map<String, String> _membership = {};

  @override
  Future<List<Hub>> getHubs() async => List.unmodifiable(_hubs);

  @override
  Future<Hub> createHub(HubDraft draft) async {
    final hub = Hub(
      id: hubSlug(draft.name),
      name: draft.name.trim(),
      type: draft.type,
      memberCount: 0,
      distanceLabel: '',
      latitude: draft.latitude,
      longitude: draft.longitude,
    );
    _hubs.add(hub);
    return hub;
  }

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

  Future<Map<String, dynamic>> insertHub(Map<String, dynamic> values);

  Future<void> upsertMembership({
    required String userId,
    required String hubId,
  });

  Future<void> deleteMembership(String userId);

  Future<String?> getCurrentHubId(String userId);
}

abstract class HubInvalidationSource {
  Stream<void> watchHubDirectory();
}

class SupabaseHubInvalidationSource implements HubInvalidationSource {
  SupabaseHubInvalidationSource(this._client);

  final SupabaseClient _client;

  @override
  Stream<void> watchHubDirectory() {
    late final RealtimeChannel channel;
    final controller = StreamController<void>();

    void invalidate(PostgresChangePayload _) {
      if (!controller.isClosed) controller.add(null);
    }

    controller.onListen = () {
      channel = _client
          .channel('hubs:${DateTime.now().microsecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'hubs',
            callback: invalidate,
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'hub_memberships',
            callback: invalidate,
          )
          .subscribe((status, error) {
            if (controller.isClosed) return;
            if (status == RealtimeSubscribeStatus.channelError ||
                status == RealtimeSubscribeStatus.timedOut) {
              controller.addError(
                error ?? const RealtimeHubSubscriptionFailure(),
              );
            }
          });
    };

    controller.onCancel = () async {
      await channel.unsubscribe();
    };
    return controller.stream;
  }
}

class RealtimeHubSubscriptionFailure implements Exception {
  const RealtimeHubSubscriptionFailure();

  @override
  String toString() => 'Realtime hub subscription failed.';
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
  Future<Map<String, dynamic>> insertHub(Map<String, dynamic> values) async {
    final row = await _client.from('hubs').insert(values).select().single();
    return Map<String, dynamic>.from(row);
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

class SupabaseHubRepository implements HubRepository, RealtimeHubRepository {
  SupabaseHubRepository({
    required SupabaseHubGateway gateway,
    HubInvalidationSource? invalidationSource,
  }) : _gateway = gateway,
       _invalidationSource = invalidationSource;

  final SupabaseHubGateway _gateway;
  final HubInvalidationSource? _invalidationSource;

  @override
  Stream<HubDirectorySnapshot> watchHubDirectory(String userId) async* {
    yield await _snapshot(userId);

    final invalidationSource = _invalidationSource;
    if (invalidationSource == null) return;

    await for (final _ in invalidationSource.watchHubDirectory()) {
      yield await _snapshot(userId);
    }
  }

  @override
  Future<List<Hub>> getHubs() async {
    final rows = await _gateway.getHubDirectory();
    return rows.map(_mapHub).toList();
  }

  @override
  Future<Hub> createHub(HubDraft draft) async {
    try {
      final row = await _gateway.insertHub({
        'id': hubSlug(draft.name),
        'name': draft.name.trim(),
        'type': _hubTypeValue(draft.type),
        'latitude': draft.latitude,
        'longitude': draft.longitude,
      });
      // The insert returns the `hubs` row, which has no member_count column;
      // a hub nobody has joined yet has zero members by definition.
      return _mapHub({...row, 'member_count': 0});
    } on PostgrestException catch (error) {
      throw HubFailure(_messageFor(error));
    }
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

  Future<HubDirectorySnapshot> _snapshot(String userId) async {
    final results = await Future.wait([getHubs(), getCurrentHubId(userId)]);
    return HubDirectorySnapshot(
      hubs: results[0] as List<Hub>,
      joinedHubId: results[1] as String?,
    );
  }

  String _messageFor(PostgrestException error) {
    // 23505 = unique_violation: another student registered this hub first.
    if (error.code == '23505') {
      return 'That hub is already registered.';
    }
    // 42501 = insufficient_privilege, i.e. the insert policy rejected us.
    if (error.code == '42501') {
      return 'You do not have permission to register a hub.';
    }
    return 'Could not register the hub. Please try again.';
  }

  Hub _mapHub(Map<String, dynamic> row) {
    return Hub(
      id: row['id'] as String,
      name: row['name'] as String,
      type: _mapHubType(row['type'] as String),
      memberCount: (row['member_count'] as num?)?.toInt() ?? 0,
      distanceLabel: row['distance_label'] as String? ?? '',
      latitude: (row['latitude'] as num?)?.toDouble(),
      longitude: (row['longitude'] as num?)?.toDouble(),
    );
  }

  HubType _mapHubType(String value) {
    return switch (value) {
      'area_hub' => HubType.areaHub,
      'dormitory' => HubType.dormitory,
      _ => throw StateError('Unknown hub type "$value".'),
    };
  }

  String _hubTypeValue(HubType type) {
    return switch (type) {
      HubType.areaHub => 'area_hub',
      HubType.dormitory => 'dormitory',
    };
  }
}
