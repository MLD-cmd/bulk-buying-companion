import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseHubRepository', () {
    test('maps hub directory rows', () async {
      final repository = SupabaseHubRepository(
        gateway: _FakeSupabaseHubGateway(
          hubs: const [
            {
              'id': 'colon',
              'name': 'Colon Street Hub',
              'type': 'area_hub',
              'member_count': 31,
              'distance_label': '400 m',
            },
          ],
        ),
      );

      final hubs = await repository.getHubs();

      expect(hubs, hasLength(1));
      expect(hubs.first.id, 'colon');
      expect(hubs.first.type, HubType.areaHub);
      expect(hubs.first.memberCount, 31);
    });

    test('joined hub persists across repository instances', () async {
      final gateway = _FakeSupabaseHubGateway();
      final firstSession = SupabaseHubRepository(gateway: gateway);

      await firstSession.joinHub(userId: 'user-1', hubId: 'magallanes');
      final restartedSession = SupabaseHubRepository(gateway: gateway);

      expect(await restartedSession.getCurrentHubId('user-1'), 'magallanes');
    });

    test('leave removes the persisted membership', () async {
      final gateway = _FakeSupabaseHubGateway();
      final repository = SupabaseHubRepository(gateway: gateway);

      await repository.joinHub(userId: 'user-1', hubId: 'magallanes');
      await repository.leaveHub(userId: 'user-1');

      expect(await repository.getCurrentHubId('user-1'), isNull);
    });

    test('createHub writes a slugged row with coordinates', () async {
      final gateway = _FakeSupabaseHubGateway();
      final repository = SupabaseHubRepository(gateway: gateway);

      final hub = await repository.createHub(
        const HubDraft(
          name: '  Sanciangko Apartments ',
          type: HubType.dormitory,
          latitude: 10.2939,
          longitude: 123.8949,
        ),
      );

      expect(gateway.insertedHubs.single, {
        'id': 'sanciangko-apartments',
        'name': 'Sanciangko Apartments',
        'type': 'dormitory',
        'latitude': 10.2939,
        'longitude': 123.8949,
      });
      expect(hub.id, 'sanciangko-apartments');
      expect(hub.type, HubType.dormitory);
      expect(hub.latitude, 10.2939);
      // A hub nobody has joined yet starts empty.
      expect(hub.memberCount, 0);
    });

    test('a registered hub shows up in the directory', () async {
      final gateway = _FakeSupabaseHubGateway();
      final repository = SupabaseHubRepository(gateway: gateway);

      await repository.createHub(
        const HubDraft(
          name: 'Junquera Area Hub',
          type: HubType.areaHub,
          latitude: 10.2975,
          longitude: 123.8939,
        ),
      );

      final hubs = await repository.getHubs();
      expect(hubs.single.name, 'Junquera Area Hub');
      expect(hubs.single.type, HubType.areaHub);
    });

    test('reports a hub someone else registered first', () async {
      final gateway = _FakeSupabaseHubGateway()
        ..insertError = PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
        );
      final repository = SupabaseHubRepository(gateway: gateway);

      expect(
        () => repository.createHub(
          const HubDraft(
            name: 'Colon Street Hub',
            type: HubType.areaHub,
            latitude: 10.2967,
            longitude: 123.8988,
          ),
        ),
        throwsA(
          isA<HubFailure>().having(
            (error) => error.message,
            'message',
            'That hub is already registered.',
          ),
        ),
      );
    });

    test('reports an RLS rejection as a permission problem', () async {
      final gateway = _FakeSupabaseHubGateway()
        ..insertError = PostgrestException(
          message: 'new row violates row-level security policy',
          code: '42501',
        );
      final repository = SupabaseHubRepository(gateway: gateway);

      expect(
        () => repository.createHub(
          const HubDraft(
            name: 'Colon Street Hub',
            type: HubType.areaHub,
            latitude: 10.2967,
            longitude: 123.8988,
          ),
        ),
        throwsA(
          isA<HubFailure>().having(
            (error) => error.message,
            'message',
            'You do not have permission to register a hub.',
          ),
        ),
      );
    });
  });
}

class _FakeSupabaseHubGateway implements SupabaseHubGateway {
  _FakeSupabaseHubGateway({List<Map<String, dynamic>> hubs = const []})
    : _hubs = List.of(hubs);

  final List<Map<String, dynamic>> _hubs;
  final Map<String, String> _memberships = {};

  /// Rows handed to [insertHub], so tests can assert what was written.
  final List<Map<String, dynamic>> insertedHubs = [];

  /// When set, [insertHub] throws it instead of inserting.
  PostgrestException? insertError;

  @override
  Future<List<Map<String, dynamic>>> getHubDirectory() async => _hubs;

  @override
  Future<Map<String, dynamic>> insertHub(Map<String, dynamic> values) async {
    final error = insertError;
    if (error != null) throw error;
    insertedHubs.add(values);
    _hubs.add(values);
    return values;
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => _memberships[userId];

  @override
  Future<void> upsertMembership({
    required String userId,
    required String hubId,
  }) async {
    _memberships[userId] = hubId;
  }

  @override
  Future<void> deleteMembership(String userId) async {
    _memberships.remove(userId);
  }
}
