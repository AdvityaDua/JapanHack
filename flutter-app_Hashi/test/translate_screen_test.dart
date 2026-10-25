import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/conversation.dart';
import 'package:hashi_mobile/theme.dart';
import 'package:hashi_mobile/translate_screen.dart';

import 'helpers.dart';

void tall(WidgetTester t) {
  t.view.physicalSize = const Size(800, 3200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Future<void> settle(WidgetTester t) async {
  tall(t);
  for (var i = 0; i < 4; i++) {
    await t.pump(const Duration(milliseconds: 150));
  }
}

({
  ConversationController c,
  FakeSpeech s,
  FakeTranslator tr,
  List<String> spoken,
})
make({FakeSpeech? speech, FakeTranslator? translator}) {
  final s = speech ?? FakeSpeech();
  final tr =
      translator ??
      FakeTranslator({
        'mujhe paani': '私に水',
        'mujhe paani chahiye': 'お水をください',
        'お水です': 'यह पानी है',
      });
  final spoken = <String>[];
  final c = ConversationController(
    speech: s,
    translator: tr,
    myLang: 'hi',
    speak: (text, lang) async => spoken.add('$lang:$text'),
    partialDelay: const Duration(milliseconds: 10),
  );
  addTearDown(c.dispose);
  return (c: c, s: s, tr: tr, spoken: spoken);
}

Future<void> show(WidgetTester t, ConversationController c) async {
  tall(t);
  await t.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      home: TranslateScreen(lang: 'hi', controller: c),
    ),
  );
  await settle(t);
}

void main() {
  testWidgets(
    'two big microphone buttons, one for each person, and a plain explanation to start',
    (t) async {
      final m = make();
      await show(t, m.c);
      expect(find.text('I speak'), findsOneWidget);
      expect(find.text('They speak'), findsOneWidget);
      expect(
        find.text('हिन्दी'),
        findsOneWidget,
      ); // the passenger's language is named on their button
      expect(find.text('日本語'), findsOneWidget);
      for (final label in ['I speak', 'They speak']) {
        final size = t.getSize(
          find
              .ancestor(
                of: find.text(label),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        expect(size.height, greaterThanOrEqualTo(80), reason: label);
      }
      expect(find.textContaining('Tap "I speak"'), findsOneWidget);
    },
  );

  testWidgets(
    'tapping "I speak" listens in the passenger\'s language, and the words and Japanese appear while talking',
    (t) async {
      final m = make();
      await show(t, m.c);
      await t.tap(find.text('I speak'));
      await settle(t);
      expect(m.s.asked, ['hi_IN']);
      expect(find.text('Listening to you…'), findsOneWidget);
      expect(find.text('Tap to stop'), findsOneWidget);

      m.s.say('mujhe paani');
      await settle(t);
      expect(find.text('mujhe paani'), findsOneWidget);
      expect(find.text('私に水'), findsOneWidget);
    },
  );

  testWidgets(
    'when speech ends the turn moves to the history with its Japanese, its time, and it is read aloud',
    (t) async {
      final m = make();
      await show(t, m.c);
      await t.tap(find.text('I speak'));
      await settle(t);
      m.s.say('mujhe paani chahiye', isFinal: true);
      await settle(t);
      expect(find.text('お水をください'), findsOneWidget);
      expect(find.text('mujhe paani chahiye'), findsOneWidget);
      expect(
        find.textContaining(' s'),
        findsWidgets,
      ); // how long the translation took
      expect(m.spoken, ['ja:お水をください']);
      expect(find.text('Listening to you…'), findsNothing);
    },
  );

  testWidgets(
    '"They speak" listens in Japanese and shows the translation for the passenger',
    (t) async {
      final m = make();
      await show(t, m.c);
      await t.tap(find.text('They speak'));
      await settle(t);
      expect(m.s.asked, ['ja_JP']);
      m.s.say('お水です', isFinal: true);
      await settle(t);
      expect(find.text('यह पानी है'), findsOneWidget);
      expect(m.spoken, ['hi:यह पानी है']);
    },
  );

  testWidgets('tapping the same button again stops listening', (t) async {
    final m = make();
    await show(t, m.c);
    await t.tap(find.text('I speak'));
    await settle(t);
    await t.tap(find.text('Tap to stop'));
    await settle(t);
    expect(m.c.listening, isNull);
    expect(m.s.stops, 1);
  });

  testWidgets(
    'a language the phone cannot listen to offline gives a clear message and a how-to',
    (t) async {
      final m = make(speech: FakeSpeech({'ja_JP'}));
      await show(t, m.c);
      await t.tap(find.text('I speak'));
      await settle(t);
      expect(find.textContaining('offline speech model'), findsOneWidget);
      await t.tap(find.text('How to set up'));
      await settle(t);
      expect(find.textContaining('Sherpa/ONNX models'), findsOneWidget);
      await t.tap(find.text('OK'));
      await settle(t);
      await t.tap(find.text('Dismiss'));
      await settle(t);
      expect(find.textContaining('offline speech model'), findsNothing);
    },
  );

  testWidgets('a missing translation model says to download the language kit', (
    t,
  ) async {
    final m = make(translator: FakeTranslator({}, pairs: {}));
    await show(t, m.c);
    await t.tap(find.text('I speak'));
    await settle(t);
    expect(find.textContaining('language kit'), findsOneWidget);
  });

  testWidgets('typing works too, in either language', (t) async {
    final m = make();
    await show(t, m.c);
    await t.tap(find.text('Type instead'));
    await settle(t);
    await t.enterText(find.byType(TextField), 'mujhe paani chahiye');
    await t.tap(find.byTooltip('Translate what I typed'));
    await settle(t);
    expect(find.text('お水をください'), findsOneWidget);
    expect(m.spoken, ['ja:お水をください']);
    await t.enterText(find.byType(TextField), 'お水です');
    await t.tap(find.byTooltip('Translate Japanese I typed'));
    await settle(t);
    expect(find.text('यह पानी है'), findsOneWidget);
  });

  testWidgets(
    'reading aloud can be switched off, and any line can be replayed',
    (t) async {
      final m = make();
      await show(t, m.c);
      await t.tap(find.byTooltip('Reading aloud is on'));
      await settle(t);
      expect(m.c.speakAloud, false);
      await t.tap(find.text('I speak'));
      await settle(t);
      m.s.say('mujhe paani chahiye', isFinal: true);
      await settle(t);
      expect(m.spoken, isEmpty);
      await t.tap(find.byTooltip('Read aloud'));
      await settle(t);
      expect(m.spoken, ['ja:お水をください']);
    },
  );
}
