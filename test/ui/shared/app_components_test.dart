import 'package:bulk_buying_companion/ui/shared/app_banner.dart';
import 'package:bulk_buying_companion/ui/shared/app_form_section.dart';
import 'package:bulk_buying_companion/ui/shared/app_icon_container.dart';
import 'package:bulk_buying_companion/ui/shared/app_message_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('AppBanner announces a live error message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppBanner.error(message: 'Could not load deals.')),
      ),
    );

    expect(find.text('Could not load deals.'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(AppBanner)).flagsCollection.isLiveRegion,
      isTrue,
    );
  });

  testWidgets('AppBanner exposes a responsive retry action', (tester) async {
    var retries = 0;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: AppBanner.error(
              message: 'Couldn’t refresh deals. Showing saved deals.',
              actionLabel: 'Try again',
              onAction: () => retries++,
            ),
          ),
        ),
      ),
    );

    final retryButton = find.widgetWithText(TextButton, 'Try again');
    expect(retryButton, findsOneWidget);
    expect(tester.getSemantics(retryButton).label, contains('Try again'));
    expect(tester.getSize(retryButton).shortestSide, greaterThanOrEqualTo(44));

    await tester.tap(retryButton);

    expect(retries, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppBanner stacks its action below 360dp at normal text', (
    tester,
  ) async {
    await _pumpGeometryBanner(tester, width: 359, textScale: 1);

    final messageBottom = tester
        .getBottomLeft(find.text(_geometryBannerMessage))
        .dy;
    final actionTop = tester.getTopLeft(find.byType(TextButton)).dy;

    expect(actionTop, greaterThanOrEqualTo(messageBottom + 4));
  });

  testWidgets('AppBanner stacks its action above 1.3 text scale when wide', (
    tester,
  ) async {
    await _pumpGeometryBanner(tester, width: 500, textScale: 1.31);

    final messageBottom = tester
        .getBottomLeft(find.text(_geometryBannerMessage))
        .dy;
    final actionTop = tester.getTopLeft(find.byType(TextButton)).dy;

    expect(actionTop, greaterThanOrEqualTo(messageBottom + 4));
  });

  testWidgets('AppBanner keeps its action inline at the width boundary', (
    tester,
  ) async {
    await _pumpGeometryBanner(tester, width: 360, textScale: 1);

    final messageTop = tester.getTopLeft(find.text(_geometryBannerMessage)).dy;
    final actionTop = tester.getTopLeft(find.byType(TextButton)).dy;

    expect(actionTop, moreOrLessEquals(messageTop));
  });

  test('AppBanner rejects incomplete or impossible action states', () {
    void action() {}

    expect(
      () => AppBanner(
        message: 'Saved deals are available.',
        tone: AppBannerTone.notice,
        icon: Icons.info_outline,
        actionLabel: 'Retry',
      ),
      throwsAssertionError,
    );
    expect(
      () => AppBanner.error(
        message: 'Could not refresh deals.',
        onAction: action,
      ),
      throwsAssertionError,
    );
    expect(
      () => AppBanner.notice(
        message: 'Saved deals are available.',
        actionBusy: true,
      ),
      throwsAssertionError,
    );
    expect(
      () => AppBanner.success(
        message: 'Deals refreshed.',
        actionLabel: 'Refresh',
      ),
      throwsAssertionError,
    );
    expect(
      () => AppBanner.error(
        message: 'Could not refresh deals.',
        actionLabel: 'Retry',
        onAction: action,
        actionBusy: true,
      ),
      returnsNormally,
    );
  });

  testWidgets('AppBanner disables a busy action and shows progress', (
    tester,
  ) async {
    var retries = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppBanner.error(
            message: 'Couldn’t refresh deals.',
            actionLabel: 'Try again',
            onAction: () => retries++,
            actionBusy: true,
          ),
        ),
      ),
    );

    final action = tester.widget<TextButton>(find.byType(TextButton));
    final progress = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byType(CircularProgressIndicator),
            matching: find.byType(SizedBox),
          )
          .first,
    );

    expect(action.onPressed, isNull);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester.getSemantics(find.byType(TextButton)).label,
      contains('Try again in progress'),
    );
    expect(progress.width, 18);
    expect(progress.height, 18);
    await tester.tap(find.byType(TextButton));
    expect(retries, 0);
  });

  testWidgets('AppBanner stays accessible across the viewport matrix', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in _responsiveViewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: AppBanner.error(
                message: 'Couldn’t refresh deals. Showing saved deals.',
                actionLabel: 'Retry',
                onAction: _emptyAction,
              ),
            ),
          ),
        ),
      );

      final banner = find.byType(AppBanner);
      final liveError = find.descendant(
        of: banner,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.liveRegion == true,
        ),
      );
      final retry = find.widgetWithText(TextButton, 'Retry');
      expect(liveError, findsOneWidget, reason: 'error is not live at $size');
      expect(
        tester.getSemantics(liveError).flagsCollection.isLiveRegion,
        isTrue,
        reason: 'error is not live at $size',
      );
      expect(
        tester.getSemantics(retry).label,
        contains('Retry'),
        reason: 'retry is not labelled at $size',
      );
      expect(
        tester.getSize(retry).shortestSide,
        greaterThanOrEqualTo(44),
        reason: 'retry touch target is too small at $size',
      );
      expect(tester.takeException(), isNull, reason: 'overflow at $size');
    }
  });

  testWidgets('AppMessageState exposes an optional retry action', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMessageState(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't load deals",
            message: 'Check your connection and try again.',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text("Couldn't load deals"), findsOneWidget);
    expect(find.text('Check your connection and try again.'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    expect(retries, 1);
  });

  testWidgets('AppMessageState keeps a disabled semantic retry while busy', (
    tester,
  ) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppMessageState(
            icon: Icons.cloud_off_outlined,
            title: "Couldn't load deals",
            message: 'Check your connection and try again.',
            onRetry: () => retries++,
            retryBusy: true,
          ),
        ),
      ),
    );

    final retryButton = tester.widget<OutlinedButton>(
      find.byType(OutlinedButton),
    );
    expect(retryButton.onPressed, isNull);
    expect(find.text('Trying again…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('Trying again'), findsOneWidget);

    await tester.tap(find.byType(OutlinedButton));
    expect(retries, 0);
  });

  testWidgets('AppFormSection and AppIconContainer keep content focused', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppFormSection(
            title: 'Product',
            description: 'Tell members what the group is buying.',
            icon: Icons.inventory_2_outlined,
            children: [Text('Product name field')],
          ),
        ),
      ),
    );

    expect(find.text('Product'), findsOneWidget);
    expect(find.text('Tell members what the group is buying.'), findsOneWidget);
    expect(find.byType(AppIconContainer), findsOneWidget);
    expect(find.text('Product name field'), findsOneWidget);
  });
}

const _geometryBannerMessage = 'Saved deals are available.';

Future<void> _pumpGeometryBanner(
  WidgetTester tester, {
  required double width,
  required double textScale,
}) async {
  tester.view.physicalSize = Size(width, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: AppBanner.error(
            message: _geometryBannerMessage,
            actionLabel: 'Retry',
            onAction: _emptyAction,
          ),
        ),
      ),
    ),
  );
}

void _emptyAction() {}

const _responsiveViewports = <Size>[
  Size(320, 568),
  Size(412, 915),
  Size(915, 412),
  Size(1200, 900),
];
