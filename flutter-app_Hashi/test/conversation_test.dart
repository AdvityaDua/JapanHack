
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/conversation.dart';
import 'package:hashi_mobile/engines.dart';

import 'helpers.dart';

const gap = Duration(milliseconds: 60);

({ConversationController c, FakeSpeech s, FakeTranslator t, List<String> spoken}) make({Map<String, String>? table, FakeSpeech? speech, FakeTranslator? translator, bool aloud = true}) {
  final s = speech ?? FakeSpeech();
  final t = translator ?? FakeTranslator(table ?? {'mujhe paani chahiye': 'お水をください', 'お水です': 'यह पानी है', 'mujhe': '私に', 'mujhe paani': '私に水'});
  final spoken = <String>[];
  final c = ConversationController(speech: s, translator: t, myLang: 'hi', speak: (text, lang) async => spoken.add('$lang:$text'), partialDelay: const Duration(milliseconds: 10), speakAloud: aloud);
  addTearDown(c.dispose);
  return (c: c, s: s, t: t, spoken: spoken);
}

void main() {
  group('speaking and translating', () {
    test('while talking, the words and a running translation appear; on the end the turn is saved and read aloud in Japanese', () async {
      final m = make();
      await m.c.startListening(Side.me);
      expect(m.c.listening, Side.me);
      expect(m.s.asked.single, 'hi_IN');

      m.s.say('mujhe paani');
      await Future<void>.delayed(gap);
      expect(m.c.heard, 'mujhe paani');
      expect(m.c.heardTranslation, '私に水');

      m.s.say('mujhe paani chahiye', isFinal: true);
      await Future<void>.delayed(gap);
      expect(m.c.listening, isNull);
      expect(m.c.history.single.original, 'mujhe paani chahiye');
      expect(m.c.history.single.translated, 'お水をください');
      expect(m.c.history.single.fromLang, 'hi');
      expect(m.c.history.single.toLang, 'ja');
      expect(m.spoken, ['ja:お水をください']);
      expect(m.c.heard, isEmpty);
      expect(m.c.heardTranslation, isNull);
    });

    test('when the other person speaks Japanese it is translated into the passenger\'s language and read aloud in it', () async {
      final m = make();
      await m.c.startListening(Side.them);
      expect(m.s.asked.single, 'ja_JP');
      m.s.say('お水です', isFinal: true);
      await Future<void>.delayed(gap);
      expect(m.c.history.single.toLang, 'hi');
      expect(m.c.history.single.translated, 'यह पानी है');
      expect(m.spoken, ['hi:यह पानी है']);
    });

    test('an old translation never overwrites a newer one', () async {
      final m = make(translator: FakeTranslator({'mujhe': '私に', 'mujhe paani': '私に水'}, delays: {'mujhe': const Duration(milliseconds: 200)}));
      await m.c.startListening(Side.me);
      m.s.say('mujhe');
      await Future<void>.delayed(const Duration(milliseconds: 30)); // translation of the first is now slow and running
      m.s.say('mujhe paani');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(m.c.heardTranslation, '私に水');
    });

    test('the time to translate is recorded for each turn', () async {
      final m = make(translator: FakeTranslator({'x': 'y'}, pairs: {'hi>ja'}, delays: {'x': const Duration(milliseconds: 40)}));
      await m.c.typed(Side.me, 'x');
      expect(m.c.history.single.translateTime!.inMilliseconds, greaterThanOrEqualTo(35));
    });

    test('typing takes the same path as speaking', () async {
      final m = make();
      await m.c.typed(Side.me, '  mujhe paani chahiye  ');
      expect(m.c.history.single.original, 'mujhe paani chahiye');
      expect(m.spoken, ['ja:お水をください']);
    });

    test('empty or blank input makes no turn', () async {
      final m = make();
      await m.c.typed(Side.me, '   ');
      await m.c.startListening(Side.me);
      m.s.say('   ', isFinal: true);
      await Future<void>.delayed(gap);
      expect(m.c.history, isEmpty);
    });

    test('reading aloud can be switched off', () async {
      final m = make(aloud: false);
      await m.c.typed(Side.me, 'mujhe paani chahiye');
      expect(m.c.history.length, 1);
      expect(m.spoken, isEmpty);
    });

    test('any turn can be read aloud again', () async {
      final m = make();
      await m.c.typed(Side.me, 'mujhe paani chahiye');
      m.spoken.clear();
      await m.c.replay(m.c.history.single);
      expect(m.spoken, ['ja:お水をください']);
    });

    test('if the recogniser gives up waiting without a final result, what was heard is used', () async {
      final m = make();
      await m.c.startListening(Side.me);
      m.s.say('mujhe paani chahiye');
      await Future<void>.delayed(gap);
      await m.s.hangUp();
      await Future<void>.delayed(gap);
      expect(m.c.history.single.original, 'mujhe paani chahiye');
    });
  });

  group('when something is missing', () {
    test('a language the translator does not know says which model is missing and never listens', () async {
      final m = make(translator: FakeTranslator({}, pairs: {}));
      await m.c.startListening(Side.me);
      expect(m.c.problem, 'no_model:hi>ja');
      expect(m.c.listening, isNull);
      expect(m.s.asked, isEmpty);
      expect(explainProblem(m.c.problem!, 'hi'), contains('language kit'));
    });

    test('a language the phone cannot listen to offline is explained, with the way out', () async {
      final m = make(speech: FakeSpeech({'ja_JP'}));
      await m.c.startListening(Side.me);
      expect(m.c.problem, 'no_speech:hi');
      expect(m.c.listening, isNull);
      final text = explainProblem(m.c.problem!, 'hi');
      expect(text, contains('offline speech pack'));
      expect(text, contains('type instead'));
    });

    test('a failed translation at the end is reported and nothing wrong is saved', () async {
      final m = make();
      m.t.broken = true;
      await m.c.startListening(Side.me);
      m.s.say('mujhe paani chahiye', isFinal: true);
      await Future<void>.delayed(gap);
      expect(m.c.problem, startsWith('no_model'));
      expect(m.c.history, isEmpty);
      expect(m.spoken, isEmpty);
    });

    test('"no match" and timeouts from the microphone are not alarming', () async {
      final m = make();
      await m.c.startListening(Side.me);
      m.s.fail('error_no_match');
      await Future<void>.delayed(gap);
      expect(m.c.problem, isNull);
    });

    test('a real microphone error is reported and stops listening', () async {
      final m = make();
      await m.c.startListening(Side.me);
      m.s.fail('error_audio_error');
      await Future<void>.delayed(gap);
      expect(m.c.problem, 'speech_error:error_audio_error');
      expect(m.c.listening, isNull);
      expect(explainProblem(m.c.problem!, 'hi'), contains('microphone'));
    });

    test('a problem can be dismissed', () async {
      final m = make(speech: FakeSpeech({}));
      await m.c.startListening(Side.me);
      expect(m.c.problem, isNotNull);
      m.c.clearProblem();
      expect(m.c.problem, isNull);
    });
  });

  group('stopping and switching', () {
    test('stopping ends listening, and late words do not create a turn', () async {
      final m = make();
      await m.c.startListening(Side.me);
      final out = m.s.out!;
      await m.c.stopListening();
      expect(m.c.listening, isNull);
      expect(m.s.stops, 1);
      out.add(const SpeechEvent('too late', isFinal: true));
      await Future<void>.delayed(gap);
      expect(m.c.history, isEmpty);
    });

    test('starting the other side stops the first and listens in the other language', () async {
      final m = make();
      await m.c.startListening(Side.me);
      await m.c.startListening(Side.them);
      expect(m.c.listening, Side.them);
      expect(m.s.asked, ['hi_IN', 'ja_JP']);
      expect(m.s.stops, 1);
    });

    test('words that arrive for the first side after switching are ignored', () async {
      final m = make();
      await m.c.startListening(Side.me);
      final first = m.s.out!;
      await m.c.startListening(Side.them);
      first.add(const SpeechEvent('mujhe paani chahiye', isFinal: true));
      await Future<void>.delayed(gap);
      expect(m.c.history, isEmpty);
    });
  });

  test('which side uses which language', () {
    final m = make();
    expect(m.c.langOf(Side.me), 'hi');
    expect(m.c.langOf(Side.them), 'ja');
    expect(m.c.otherLang(Side.me), 'ja');
    expect(m.c.otherLang(Side.them), 'hi');
  });

  test('the composite translator uses the first engine that knows the pair and falls through when one cannot answer', () async {
    final a = FakeTranslator({'x': 'from A'}, pairs: {'hi>ja'})..broken = true;
    final b = FakeTranslator({'x': 'from B'}, pairs: {'hi>ja', 'pa>ja'});
    final both = CompositeTranslator([a, b]);
    expect(both.supports('pa', 'ja'), true);
    expect(both.supports('km', 'ja'), false);
    expect(await both.translate('x', 'hi', 'ja'), 'from B');
    expect(a.calls.length, 1);
  });

  test('recogniser locales', () {
    expect(speechLocale('ja'), 'ja_JP');
    expect(speechLocale('hi'), 'hi_IN');
    expect(speechLocale('pa'), 'pa_IN');
    expect(speechLocale('en'), 'en_IN');
  });
}
