import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android declares camera support for physical-device scan testing', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();

    expect(
      manifest,
      contains('android.permission.CAMERA'),
      reason: 'Physical devices must be able to grant camera access.',
    );
    expect(
      manifest,
      contains('android.hardware.camera'),
      reason: 'Play/device installs should know camera hardware is supported.',
    );
  });
}
