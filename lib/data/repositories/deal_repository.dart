import '../../models/deal.dart';

/// Split Board deal-feed contract. Backed by [MockDealRepository] until the
/// real backend (Supabase) is wired; the ViewModel never depends on the
/// concrete implementation.
abstract class DealRepository {
  Future<List<Deal>> getDeals(String hubId);
}

/// In-memory stand-in. Deals are stubbed per hub so the Split Board renders
/// with placeholder cards. Detail fields (price, slots, pickup, status) are
/// filled in by the deal-card work on top of the [Deal] model.
class MockDealRepository implements DealRepository {
  MockDealRepository()
      : _dealsByHub = const {
          'colon': [
            Deal(
              id: 'colon-rice',
              hubId: 'colon',
              title: '25kg Rice Sack — Split 5 ways',
            ),
            Deal(
              id: 'colon-water',
              hubId: 'colon',
              title: 'Bottled Water Case (24pk)',
            ),
            Deal(
              id: 'colon-detergent',
              hubId: 'colon',
              title: 'Laundry Detergent 6L',
            ),
          ],
          'magallanes': [
            Deal(
              id: 'magallanes-eggs',
              hubId: 'magallanes',
              title: 'Egg Tray (30s) — Split 3 ways',
            ),
            Deal(
              id: 'magallanes-coffee',
              hubId: 'magallanes',
              title: '3-in-1 Coffee Bulk Pack',
            ),
          ],
        };

  final Map<String, List<Deal>> _dealsByHub;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    return _dealsByHub[hubId] ?? const [];
  }
}
