import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('brand icon and splash assets are registered', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('assets/branding/app_icon.png'));
    expect(pubspec, contains('assets/branding/splash_logo.png'));
  });

  test('Android launch splash uses the brand splash drawable', () {
    final launchBackground = File(
      'android/app/src/main/res/drawable/launch_background.xml',
    ).readAsStringSync();
    final launchBackgroundV21 = File(
      'android/app/src/main/res/drawable-v21/launch_background.xml',
    ).readAsStringSync();

    expect(launchBackground, contains('@drawable/splash_logo'));
    expect(launchBackgroundV21, contains('@drawable/splash_logo'));
  });
}
