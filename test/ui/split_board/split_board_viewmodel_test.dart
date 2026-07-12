import 'package:bulk_buying_companion/data/repositories/deal_repository.dart';
import 'package:bulk_buying_companion/models/deal.dart';
import 'package:bulk_buying_companion/ui/split_board/split_board_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads the deals for its hub on construction', () async {
    final repository = _FakeDealRepository({
      'colon': const [
        Deal(id: 'a', hubId: 'colon', title: 'Rice Sack'),
        Deal(id: 'b', hubId: 'colon', title: 'Water Case'),
      ],
    });
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
    );

    expect(viewModel.isLoading, isTrue);
    await Future<void>.value();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.deals, hasLength(2));
    expect(viewModel.deals.first.title, 'Rice Sack');
  });

  test('exposes an empty list for a hub with no deals', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const {}),
      hubId: 'empty',
    );
    await Future<void>.value();

    expect(viewModel.deals, isEmpty);
  });

  test('refresh re-fetches the hub deals', () async {
    final repository = _FakeDealRepository({
      'colon': const [Deal(id: 'a', hubId: 'colon', title: 'Rice Sack')],
    });
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
    );
    await Future<void>.value();
    expect(repository.getDealsCalls, 1);

    await viewModel.refresh();

    expect(repository.getDealsCalls, 2);
  });
}

class _FakeDealRepository implements DealRepository {
  _FakeDealRepository(this._dealsByHub);

  final Map<String, List<Deal>> _dealsByHub;
  int getDealsCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    getDealsCalls++;
    return _dealsByHub[hubId] ?? const [];
  }
}
