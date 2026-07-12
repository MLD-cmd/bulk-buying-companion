import 'package:bulk_buying_companion/utils/geo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('haversineMeters', () {
    test('is zero for the same point', () {
      expect(
        haversineMeters(
          startLatitude: 10.2954,
          startLongitude: 123.8969,
          endLatitude: 10.2954,
          endLongitude: 123.8969,
        ),
        0,
      );
    });

    test('one degree of latitude is about 111 km', () {
      expect(
        haversineMeters(
          startLatitude: 0,
          startLongitude: 0,
          endLatitude: 1,
          endLongitude: 0,
        ),
        closeTo(111195, 50),
      );
    });

    test('is symmetric', () {
      const a = (lat: 10.2954, lng: 123.8969);
      const b = (lat: 10.2967, lng: 123.8988);

      final forward = haversineMeters(
        startLatitude: a.lat,
        startLongitude: a.lng,
        endLatitude: b.lat,
        endLongitude: b.lng,
      );
      final backward = haversineMeters(
        startLatitude: b.lat,
        startLongitude: b.lng,
        endLatitude: a.lat,
        endLongitude: a.lng,
      );

      expect(forward, closeTo(backward, 0.001));
    });

    test('measures a short campus-scale hop', () {
      // ~0.0009 degrees of latitude is roughly 100 m.
      final meters = haversineMeters(
        startLatitude: 10.2954,
        startLongitude: 123.8969,
        endLatitude: 10.2963,
        endLongitude: 123.8969,
      );

      expect(meters, closeTo(100, 5));
    });
  });
}
