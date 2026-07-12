import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
}

class _FakeSupabaseHubGateway implements SupabaseHubGateway {
  _FakeSupabaseHubGateway({List<Map<String, dynamic>> hubs = const []})
    : _hubs = hubs;

  final List<Map<String, dynamic>> _hubs;
  final Map<String, String> _memberships = {};

  @override
  Future<List<Map<String, dynamic>>> getHubDirectory() async => _hubs;

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
