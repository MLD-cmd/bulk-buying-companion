import 'package:bulk_buying_companion/data/repositories/hub_repository.dart';
import 'package:bulk_buying_companion/data/services/location_service.dart';
import 'package:bulk_buying_companion/models/hub.dart';
import 'package:bulk_buying_companion/ui/hub/create_hub_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sits at the same spot as [_existingHub], within the duplicate radius.
const _magallanes = Hub(
  id: 'magallanes',
  name: 'Magallanes Residence',
  type: HubType.dormitory,
  memberCount: 24,
  distanceLabel: '150 m',
  latitude: 10.2954,
  longitude: 123.8969,
);

/// A hub that predates coordinates — proximity checks must skip it, not crash.
const _legacyHub = Hub(
  id: 'legacy',
  name: 'Legacy Hub',
  type: HubType.areaHub,
  memberCount: 3,
  distanceLabel: '',
);

HubDraft _draft({
  String name = 'Sanciangko Apartments',
  double latitude = 10.4000,
  double longitude = 124.0000,
}) {
  return HubDraft(
    name: name,
    type: HubType.dormitory,
    latitude: latitude,
    longitude: longitude,
  );
}

Future<CreateHubViewModel> _viewModel({
  List<Hub> hubs = const [_magallanes],
  _FakeLocationService? locationService,
  _FakeHubRepository? hubRepository,
}) async {
  final viewModel = CreateHubViewModel(
    hubRepository: hubRepository ?? _FakeHubRepository(hubs: hubs),
    locationService: locationService ?? _FakeLocationService(),
  );
  // The constructor kicks off the directory load; let it settle.
  await Future<void>.delayed(Duration.zero);
  return viewModel;
}

void main() {
  group('validation', () {
    test('rejects an empty or too-short name', () async {
      final viewModel = await _viewModel();

      expect(viewModel.validateName(''), 'Enter the hub name.');
      expect(viewModel.validateName('  '), 'Enter the hub name.');
      expect(viewModel.validateName('Hi'), 'Hub name is too short.');
      expect(viewModel.validateName('!!!!'), 'Hub name needs at least one letter.');
      expect(viewModel.validateName('Colon Street Hub'), isNull);
    });

    test('rejects coordinates that are not numbers or out of range', () async {
      final viewModel = await _viewModel();

      expect(viewModel.validateLatitude(''), 'Enter a latitude.');
      expect(viewModel.validateLatitude('abc'), 'Latitude must be a number.');
      expect(
        viewModel.validateLatitude('91'),
        'Latitude must be between -90.0 and 90.0.',
      );
      expect(viewModel.validateLatitude('10.2954'), isNull);

      expect(
        viewModel.validateLongitude('181'),
        'Longitude must be between -180.0 and 180.0.',
      );
      expect(viewModel.validateLongitude('-123.8969'), isNull);
    });
  });

  group('duplicate detection', () {
    test('rejects a hub whose name already exists, ignoring case and spacing',
        () async {
      final viewModel = await _viewModel();

      final error = viewModel.duplicateErrorFor(
        _draft(name: '  magallanes   residence '),
      );

      expect(error, 'A hub named "Magallanes Residence" is already registered.');
    });

    test('rejects a differently-named hub sitting on top of an existing one',
        () async {
      final viewModel = await _viewModel();

      // ~11 m away from Magallanes Residence: same building, new name.
      final error = viewModel.duplicateErrorFor(
        _draft(name: 'Magallanes Dorm Annex', latitude: 10.2955, longitude: 123.8969),
      );

      expect(error, contains('"Magallanes Residence" is already registered about'));
      expect(error, contains('m from here'));
    });

    test('accepts a hub that is far enough away', () async {
      final viewModel = await _viewModel();

      // ~250 m north of Magallanes: a genuinely different place.
      final error = viewModel.duplicateErrorFor(
        _draft(name: 'Colon Street Hub', latitude: 10.2977, longitude: 123.8969),
      );

      expect(error, isNull);
    });

    test('skips hubs that have no coordinates instead of crashing', () async {
      final viewModel = await _viewModel(hubs: const [_legacyHub]);

      expect(viewModel.duplicateErrorFor(_draft()), isNull);
    });
  });

  group('useMyLocation', () {
    test('captures the device position', () async {
      final viewModel = await _viewModel(
        locationService: _FakeLocationService(
          position: const Coordinates(latitude: 10.31, longitude: 123.89),
        ),
      );

      await viewModel.useMyLocation();

      expect(viewModel.capturedLocation?.latitude, 10.31);
      expect(viewModel.capturedLocation?.longitude, 123.89);
      expect(viewModel.locationError, isNull);
      expect(viewModel.isLocating, isFalse);
    });

    test('surfaces a permission failure without blocking manual entry',
        () async {
      final viewModel = await _viewModel(
        locationService: _FakeLocationService(
          failure: const LocationFailure('Location permission denied.'),
        ),
      );

      await viewModel.useMyLocation();

      expect(viewModel.locationError, 'Location permission denied.');
      expect(viewModel.capturedLocation, isNull);
      expect(viewModel.isLocating, isFalse);
    });
  });

  group('submit', () {
    test('registers the hub and returns it', () async {
      final repository = _FakeHubRepository(hubs: const [_magallanes]);
      final viewModel = await _viewModel(hubRepository: repository);

      final hub = await viewModel.submit(_draft());

      expect(hub, isNotNull);
      expect(hub!.name, 'Sanciangko Apartments');
      expect(hub.id, 'sanciangko-apartments');
      expect(hub.memberCount, 0);
      expect(repository.created, hasLength(1));
      expect(viewModel.errorMessage, isNull);
    });

    test('refuses a duplicate without touching the repository', () async {
      final repository = _FakeHubRepository(hubs: const [_magallanes]);
      final viewModel = await _viewModel(hubRepository: repository);

      final hub = await viewModel.submit(_draft(name: 'Magallanes Residence'));

      expect(hub, isNull);
      expect(repository.created, isEmpty);
      expect(viewModel.errorMessage, contains('already registered'));
    });

    test('surfaces a backend failure', () async {
      final repository = _FakeHubRepository(
        hubs: const [_magallanes],
        failure: const HubFailure('That hub is already registered.'),
      );
      final viewModel = await _viewModel(hubRepository: repository);

      final hub = await viewModel.submit(_draft());

      expect(hub, isNull);
      expect(viewModel.errorMessage, 'That hub is already registered.');
      expect(viewModel.isSubmitting, isFalse);
    });

    test('still registers when the directory failed to load', () async {
      // A failed load only weakens duplicate detection; it must not block.
      final repository = _FakeHubRepository(hubs: const [], failLoad: true);
      final viewModel = await _viewModel(hubRepository: repository);

      final hub = await viewModel.submit(_draft());

      expect(hub, isNotNull);
      expect(viewModel.existingHubs, isEmpty);
    });
  });
}

class _FakeHubRepository implements HubRepository {
  _FakeHubRepository({
    required List<Hub> hubs,
    this.failure,
    this.failLoad = false,
  }) : _hubs = hubs;

  final List<Hub> _hubs;
  final HubFailure? failure;
  final bool failLoad;
  final List<HubDraft> created = [];

  @override
  Future<List<Hub>> getHubs() async {
    if (failLoad) throw StateError('hub table unavailable');
    return _hubs;
  }

  @override
  Future<Hub> createHub(HubDraft draft) async {
    final error = failure;
    if (error != null) throw error;
    created.add(draft);
    return Hub(
      id: hubSlug(draft.name),
      name: draft.name.trim(),
      type: draft.type,
      memberCount: 0,
      distanceLabel: '',
      latitude: draft.latitude,
      longitude: draft.longitude,
    );
  }

  @override
  Future<String?> getCurrentHubId(String userId) async => null;

  @override
  Future<void> joinHub({required String userId, required String hubId}) async {}

  @override
  Future<void> leaveHub({required String userId}) async {}
}

class _FakeLocationService implements LocationService {
  _FakeLocationService({this.position, this.failure});

  final Coordinates? position;
  final LocationFailure? failure;

  @override
  Future<Coordinates> getCurrentPosition() async {
    final error = failure;
    if (error != null) throw error;
    return position ??
        const Coordinates(latitude: 10.2954, longitude: 123.8969);
  }
}
