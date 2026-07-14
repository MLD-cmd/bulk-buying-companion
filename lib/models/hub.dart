enum HubType { dormitory, areaHub }

class Hub {
  const Hub({
    required this.id,
    required this.name,
    required this.type,
    required this.memberCount,
    required this.distanceLabel,
    this.latitude,
    this.longitude,
    this.distanceMeters,
  });

  final String id;
  final String name;
  final HubType type;
  final int memberCount;
  final String distanceLabel;

  /// Null for the hubs seeded before hub registration existed. Real distances
  /// can only be computed for hubs that carry coordinates.
  final double? latitude;
  final double? longitude;

  /// Straight-line distance from the student's current position. Null until the
  /// device location has been read, and for any hub without coordinates —
  /// [distanceLabel] still holds the seeded text in that case.
  final double? distanceMeters;

  bool get hasCoordinates => latitude != null && longitude != null;

  Hub copyWith({
    String? distanceLabel,
    double? distanceMeters,
    int? memberCount,
  }) {
    return Hub(
      id: id,
      name: name,
      type: type,
      memberCount: memberCount ?? this.memberCount,
      distanceLabel: distanceLabel ?? this.distanceLabel,
      latitude: latitude,
      longitude: longitude,
      distanceMeters: distanceMeters ?? this.distanceMeters,
    );
  }
}

/// A hub the student is about to register, before the backend assigns it an id.
class HubDraft {
  const HubDraft({
    required this.name,
    required this.type,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final HubType type;
  final double latitude;
  final double longitude;
}

/// Hub ids are readable slugs ("Magallanes Residence" -> "magallanes-residence")
/// rather than uuids, matching the hand-seeded hubs already in the table.
///
/// This doubles as the duplicate-name key: two names that slugify identically
/// ("Colon Street Hub" and "colon street  hub!") are treated as the same hub,
/// which also guarantees the generated id cannot collide with an existing one.
String hubSlug(String name) {
  return name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
}
