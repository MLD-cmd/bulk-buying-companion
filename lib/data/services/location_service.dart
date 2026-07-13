import 'package:geolocator/geolocator.dart';

class Coordinates {
  const Coordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

/// Raised when the device location cannot be read. The message is user-facing;
/// every failure here is recoverable by typing the coordinates by hand.
class LocationFailure implements Exception {
  const LocationFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the device's current position. Behind an interface so the ViewModel
/// can be tested without a GPS radio or platform channels.
abstract class LocationService {
  Future<Coordinates> getCurrentPosition();
}

class GeolocatorLocationService implements LocationService {
  const GeolocatorLocationService();

  @override
  Future<Coordinates> getCurrentPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        'Location is turned off. Turn it on, or enter the coordinates below.',
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        'Location permission is blocked in settings. '
        'Enter the coordinates below instead.',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        'Location permission denied. Enter the coordinates below instead.',
      );
    }

    final position = await Geolocator.getCurrentPosition();
    return Coordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }
}
