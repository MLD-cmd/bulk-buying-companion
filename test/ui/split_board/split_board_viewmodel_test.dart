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
      hubName: 'Colon Street Hub',
    );

    expect(viewModel.isLoading, isTrue);
    expect(viewModel.hubName, 'Colon Street Hub');
    await Future<void>.value();

    expect(viewModel.isLoading, isFalse);
    expect(viewModel.deals, hasLength(2));
    expect(viewModel.deals.first.title, 'Rice Sack');
  });

  test('exposes an empty list for a hub with no deals', () async {
    final viewModel = SplitBoardViewModel(
      dealRepository: _FakeDealRepository(const {}),
      hubId: 'empty',
      hubName: 'Empty Hub',
    );
    await Future<void>.value();

    expect(viewModel.deals, isEmpty);
    expect(viewModel.hasError, isFalse);
  });

  test('refresh re-fetches the hub deals', () async {
    final repository = _FakeDealRepository({
      'colon': const [Deal(id: 'a', hubId: 'colon', title: 'Rice Sack')],
    });
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();
    expect(repository.getDealsCalls, 1);

    await viewModel.refresh();

    expect(repository.getDealsCalls, 2);
  });

  test('flags an error when loading fails, then recovers on refresh', () async {
    final repository = _FakeDealRepository(
      {'colon': const [Deal(id: 'a', hubId: 'colon', title: 'Rice Sack')]},
      failFirstCall: true,
    );
    final viewModel = SplitBoardViewModel(
      dealRepository: repository,
      hubId: 'colon',
      hubName: 'Colon Street Hub',
    );
    await Future<void>.value();

    expect(viewModel.hasError, isTrue);
    expect(viewModel.deals, isEmpty);

    await viewModel.refresh();

    expect(viewModel.hasError, isFalse);
    expect(viewModel.deals, hasLength(1));
  });
}

class _FakeDealRepository implements DealRepository {
  _FakeDealRepository(this._dealsByHub, {this.failFirstCall = false});

  final Map<String, List<Deal>> _dealsByHub;
  final bool failFirstCall;
  int getDealsCalls = 0;

  @override
  Future<List<Deal>> getDeals(String hubId) async {
    getDealsCalls++;
    if (failFirstCall && getDealsCalls == 1) {
      throw Exception('network error');
    }
    return _dealsByHub[hubId] ?? const [];
  }
}
