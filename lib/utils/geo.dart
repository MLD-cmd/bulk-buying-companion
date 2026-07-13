import 'dart:math' as math;

const double _earthRadiusMeters = 6371000;

/// Great-circle distance between two coordinates, in meters.
///
/// Accurate enough for campus-scale distances (hundreds of meters), which is
/// all the hub features need — no map SDK or network call involved.
double haversineMeters({
  required double startLatitude,
  required double startLongitude,
  required double endLatitude,
  required double endLongitude,
}) {
  final dLat = _toRadians(endLatitude - startLatitude);
  final dLon = _toRadians(endLongitude - startLongitude);
  final lat1 = _toRadians(startLatitude);
  final lat2 = _toRadians(endLatitude);

  final a =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.sin(dLon / 2) * math.sin(dLon / 2) * math.cos(lat1) * math.cos(lat2);

  return 2 * _earthRadiusMeters * math.asin(math.min(1, math.sqrt(a)));
}

double _toRadians(double degrees) => degrees * math.pi / 180;
