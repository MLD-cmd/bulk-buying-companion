import '../../models/deal.dart';

/// Split Board deal-feed contract. Backed by [MockDealRepository] until the
/// real backend (Supabase) is wired; the ViewModel never depends on the
/// concrete implementation.
abstract class DealRepository {
  Future<List<Deal>> getDeals(String hubId);
}

/// In-memory stand-in. Deals are stubbed per hub so the Split Board renders
/// with placeholder cards until the backend feed is wired.
class MockDealRepository implements DealRepository {
  MockDealRepository()
    : _dealsByHub = {
        'colon': [
          Deal(
            id: 'colon-rice',
            hubId: 'colon',
            title: '25kg Rice Sack — Split 5 ways',
            priceLabel: 'P180/share',
            category: DealCategory.grocery,
            availableSlots: 3,
            totalSlots: 5,
            pickupLocation: 'USJR Main Gate',
            status: DealStatus.open,
            closesAt: DateTime(2026, 7, 16),
          ),
          Deal(
            id: 'colon-water',
            hubId: 'colon',
            title: 'Bottled Water Case (24pk)',
            priceLabel: 'P95/share',
            category: DealCategory.drinks,
            availableSlots: 2,
            totalSlots: 4,
            pickupLocation: 'Colon Street Hub',
            status: DealStatus.fillingFast,
            closesAt: DateTime(2026, 7, 14),
          ),
          Deal(
            id: 'colon-detergent',
            hubId: 'colon',
            title: 'Laundry Detergent 6L',
            priceLabel: 'P120/share',
            category: DealCategory.household,
            availableSlots: 0,
            totalSlots: 3,
            pickupLocation: 'Barangay Hall Lobby',
            status: DealStatus.full,
            closesAt: DateTime(2026, 7, 18),
          ),
        ],
        'magallanes': [
          Deal(
            id: 'magallanes-eggs',
            hubId: 'magallanes',
            title: 'Egg Tray (30s) — Split 3 ways',
            priceLabel: 'P85/share',
            category: DealCategory.grocery,
            availableSlots: 1,
            totalSlots: 3,
            pickupLocation: 'Magallanes Residence Gate',
            status: DealStatus.fillingFast,
            closesAt: DateTime(2026, 7, 15),
          ),
          Deal(
            id: 'magallanes-coffee',
            hubId: 'magallanes',
            title: '3-in-1 Coffee Bulk Pack',
            priceLabel: 'P150/share',
            category: DealCategory.pantry,
            availableSlots: 4,
            totalSlots: 6,
            pickupLocation: 'Tower A Lobby',
            status: DealStatus.open,
            closesAt: DateTime(2026, 7, 19),
          ),
        ],
      };

  final Map<String, List<Deal>> _dealsByHub;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    return _dealsByHub[hubId] ?? const [];
  }
}
