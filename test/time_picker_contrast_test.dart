import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:oasx/modules/args/index.dart';

double contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a >= b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final type in ['date_time', 'time', 'time_delta']) {
      testWidgets('$type stays readable before, during and after hover ($brightness)', (
        tester,
      ) async {
        final colors = ColorScheme.fromSeed(
          seedColor: const Color(0xFF8EADB9),
          brightness: brightness,
          surface: brightness == Brightness.dark
              ? const Color(0xFF1F2B34)
              : const Color(0xFFE8EEF1),
        );
        final theme = ThemeData(
          colorScheme: colors,
          brightness: brightness,
          primaryColor: Colors.black,
        );
        final value = switch (type) {
          'date_time' => '2026-11-16 09:00:00',
          'time' => '09:00:00',
          _ => '00 09:00:00',
        };
        final picker = switch (type) {
          'date_time' => DateTimePicker(value: value, onChange: (_) {}),
          'time' => TimePicker(value: value, onChange: (_) {}),
          _ => TimeDeltaPicker(value: value, onChange: (_) {}),
        };
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Center(
                child: DefaultTextStyle(
                  style: const TextStyle(color: Colors.black),
                  child: picker,
                ),
              ),
            ),
          ),
        );
        final text = find.text(value);
        Color textColor() => tester.widget<Text>(text).style!.color!;

        expect(textColor(), colors.onSurface);
        expect(contrast(textColor(), colors.surface), greaterThanOrEqualTo(4.5));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        addTearDown(mouse.removePointer);
        await mouse.moveTo(tester.getCenter(text));
        await tester.pumpAndSettle();
        expect(textColor(), colors.primary);
        expect(contrast(textColor(), colors.surface), greaterThanOrEqualTo(4.5));

        await mouse.moveTo(Offset.zero);
        await tester.pumpAndSettle();
        expect(textColor(), colors.onSurface);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('custom picker styles keep their color and typography', (
    tester,
  ) async {
    const value = '2026-11-16 09:00:00';
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Center(
            child: DateTimePicker(
              value: value,
              onChange: (_) {},
              notHoverStyle: const TextStyle(color: Colors.white, fontSize: 12),
              hoverStyle: const TextStyle(color: Colors.amber, fontSize: 14),
            ),
          ),
        ),
      ),
    );
    final text = find.text(value);
    expect(tester.widget<Text>(text).style!.fontSize, 12);
    expect(tester.widget<Text>(text).style!.color, Colors.white);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await mouse.moveTo(tester.getCenter(text));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(text).style!.fontSize, 14);
    expect(tester.widget<Text>(text).style!.color, Colors.amber);
  });
}
