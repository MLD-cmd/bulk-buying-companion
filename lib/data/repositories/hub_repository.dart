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
