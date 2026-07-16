import 'package:bulk_buying_companion/ui/shared/app_theme.dart';
import 'package:bulk_buying_companion/ui/shared/task_help_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('task help presents its title and ordered steps', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showTaskHelpSheet(
                context,
                title: 'Find your hub',
                steps: const [
                  TaskHelpStep(
                    icon: Icons.search_outlined,
                    title: 'Search nearby',
                    body: 'Search by hub, building, or area.',
                  ),
                  TaskHelpStep(
                    icon: Icons.domain_outlined,
                    title: 'Review the hub',
                    body: 'Check the hub type before joining.',
                  ),
                  TaskHelpStep(
                    icon: Icons.group_add_outlined,
                    title: 'Join or switch',
                    body: 'Choose the hub that fits your group.',
                  ),
                ],
              ),
              child: const Text('Show help'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show help'));
    await tester.pumpAndSettle();

    expect(find.text('Find your hub'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Search nearby'), findsOneWidget);
    expect(find.text('Review the hub'), findsOneWidget);
    expect(find.text('Join or switch'), findsOneWidget);
    expect(find.byIcon(Icons.search_outlined), findsOneWidget);
    expect(
      tester.getSemantics(find.text('Find your hub')).flagsCollection.isHeader,
      isTrue,
    );
    expect(
      tester.getSemantics(find.text('1')).label,
      startsWith('Step 1\nSearch nearby'),
    );
    expect(
      tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle,
      isTrue,
    );

    final closeButton = find.widgetWithText(FilledButton, 'Close');
    final closeSemantics = tester.getSemantics(closeButton);
    expect(closeButton, findsOneWidget);
    expect(closeSemantics.label, 'Close');
    expect(
      closeSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
  });

  testWidgets('task help scrolls at 320dp with 200 percent text', (
    tester,
  ) async {
    final theme = AppTheme.light();
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showTaskHelpSheet(
                context,
                title: 'Complete this task',
                steps: _longSteps,
              ),
              child: const Text('Show help'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show help'));
    await tester.pumpAndSettle();

    final closeButton = find.widgetWithText(FilledButton, 'Close');
    final closeLabelStyle = theme.filledButtonTheme.style!.textStyle!.resolve(
      const <WidgetState>{},
    )!;
    final scaledCloseLineHeight =
        closeLabelStyle.fontSize! * closeLabelStyle.height! * 2;
    expect(closeButton, findsOneWidget);
    expect(tester.getSize(closeButton).height, greaterThanOrEqualTo(48));
    expect(
      tester.getSize(find.text('Close')).height,
      greaterThanOrEqualTo(scaledCloseLineHeight),
    );
    expect(find.byType(ListView), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Finish the final task and confirm the result.'),
      200,
      scrollable: find.byType(Scrollable).last,
    );

    expect(
      find.text('Finish the final task and confirm the result.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('task help remains operable across the viewport matrix', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final size in _responsiveViewports) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: Builder(
                builder: (context) => FilledButton(
                  onPressed: () => showTaskHelpSheet(
                    context,
                    title: 'Complete this task',
                    steps: _longSteps,
                  ),
                  child: const Text('Show help'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show help'));
      await tester.pumpAndSettle();

      final close = find.widgetWithText(FilledButton, 'Close');
      expect(close, findsOneWidget, reason: 'missing Close at $size');
      expect(
        tester.getSize(close).height,
        greaterThanOrEqualTo(48),
        reason: 'Close is too small at $size',
      );
      expect(
        tester.getSemantics(close).label,
        'Close',
        reason: 'Close is not labelled at $size',
      );
      expect(tester.takeException(), isNull, reason: 'overflow at $size');

      await tester.tap(close);
      await tester.pumpAndSettle();
    }
  });

  testWidgets('closing task help preserves the underlying screen state', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var count = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: Column(
              children: [
                Text('Count: $count'),
                TextField(controller: controller),
                FilledButton(
                  onPressed: () => setState(() => count++),
                  child: const Text('Update state'),
                ),
                FilledButton(
                  onPressed: () => showTaskHelpSheet(
                    context,
                    title: 'Keep working',
                    steps: const [
                      TaskHelpStep(
                        icon: Icons.edit_outlined,
                        title: 'Continue editing',
                        body: 'Your work stays on this screen.',
                      ),
                    ],
                  ),
                  child: const Text('Show help'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Saved draft');
    await tester.tap(find.text('Update state'));
    await tester.tap(find.text('Show help'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Close'));
    await tester.pumpAndSettle();

    expect(find.text('Keep working'), findsNothing);
    expect(find.text('Count: 1'), findsOneWidget);
    expect(controller.text, 'Saved draft');
  });
}

const _longSteps = [
  TaskHelpStep(
    icon: Icons.looks_one_outlined,
    title: 'Start with the first task',
    body: 'Read the available information before making a choice.',
  ),
  TaskHelpStep(
    icon: Icons.looks_two_outlined,
    title: 'Continue to the second task',
    body: 'Review the details and keep the current work in place.',
  ),
  TaskHelpStep(
    icon: Icons.looks_3_outlined,
    title: 'Check the third task',
    body: 'Make sure each choice matches what the group needs.',
  ),
  TaskHelpStep(
    icon: Icons.looks_4_outlined,
    title: 'Review the fourth task',
    body: 'Look over the saved values before moving forward.',
  ),
  TaskHelpStep(
    icon: Icons.looks_5_outlined,
    title: 'Complete the fifth task',
    body: 'Finish the final task and confirm the result.',
  ),
];

const _responsiveViewports = <Size>[
  Size(320, 568),
  Size(412, 915),
  Size(915, 412),
  Size(1200, 900),
];
