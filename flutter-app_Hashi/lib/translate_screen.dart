import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'content.dart' show speakText;
import 'conversation.dart';
import 'asr_engine.dart';
import 'engines.dart';
import 'kit.dart';
import 'languages.dart';
import 'models.dart';
import 'protocol.dart';
import 'session.dart';
import 'theme.dart';

/// Speak and translate, open ended, on the phone. The passenger talks in their own language and the other person hears
/// Japanese; the other person talks in Japanese and the passenger reads and hears their own language. The translation
/// appears while the person is still speaking.
class TranslateScreen extends StatefulWidget {
  final String lang;

  /// Tests pass their own engines.
  final ConversationController? controller;
  final CabinSession? session;
  const TranslateScreen({
    super.key,
    required this.lang,
    this.controller,
    this.session,
  });

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  ConversationController? _controller;
  SherpaSpeechEngine? _speechEngine;
  bool speechModelsLoading = false;
  bool speechModelsReady = false;
  String? speechModelError;
  final text = TextEditingController();
  bool typing = false;
  bool? modelsReady;
  bool downloadingModels = false;
  String? modelError;
  String? remoteError;
  final List<_RemoteLine> remoteLines = [];
  final Set<String> seenRemoteMessages = {};
  late final bool ownsController;

  ConversationController get c => _controller!;

  @override
  void initState() {
    super.initState();
    ownsController = widget.controller == null;
    if (widget.controller != null) {
      _controller = widget.controller;
      speechModelsReady = true;
    } else {
      speechModelsLoading = true;
      unawaited(_initOfflineSpeech());
    }
    _checkModels();
    widget.session?.store.addListener(_onCabinChanged);
    _onCabinChanged();
  }

  Future<void> _initOfflineSpeech() async {
    try {
      final store = await ModelStore.open();
      final engine = SherpaSpeechEngine(store);
      _speechEngine = engine;
      final invalid = <String>[
        for (final model in speechModels) ...store.invalidFiles(model),
      ];
      if (invalid.isNotEmpty) {
        speechModelError =
            'Missing or invalid speech model files: ${invalid.join(', ')}';
      } else {
        // Loading is intentional: supports() only checks files, while
        // prepare() starts the Sherpa worker and constructs the recogniser in
        // its isolate. This is the real readiness check before enabling Speak.
        final passengerReady = await engine.prepare(speechLocale(widget.lang));
        final crewReady = await engine.prepare('ja_JP');
        speechModelsReady = passengerReady && crewReady;
        if (!speechModelsReady) {
          speechModelError =
              'Speech model files are present, but Sherpa could not load them into memory.';
        }
      }
      _controller = ConversationController(
        speech: engine,
        translator: CompositeTranslator([MlKitTranslator()]),
        myLang: widget.lang,
        speak: (t, lang) =>
            speakText(t, lang == 'ja' ? 'ja-JP' : langByCode(lang).tts),
        onTranslated: _sendTurnToCrew,
      );
    } catch (e) {
      speechModelError = 'Offline speech setup failed: $e';
      _controller = ConversationController(
        speech: _UnavailableSpeechEngine(),
        translator: CompositeTranslator([MlKitTranslator()]),
        myLang: widget.lang,
        speak: (t, lang) =>
            speakText(t, lang == 'ja' ? 'ja-JP' : langByCode(lang).tts),
        onTranslated: _sendTurnToCrew,
      );
    } finally {
      speechModelsLoading = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _sendTurnToCrew(Turn turn) async {
    final session = widget.session;
    if (session == null || turn.side != Side.me || turn.translated == null)
      return;
    final sent = await session.link.sendLiveTranslation(
      text: turn.original,
      translatedText: turn.translated!,
      sourceLanguage: turn.fromLang,
    );
    if (mounted && !sent) {
      setState(
        () => remoteError =
            'The live cabin line is unavailable. Your translation stayed on this phone.',
      );
    }
  }

  void _onCabinChanged() {
    final session = widget.session;
    if (session == null) return;
    for (final message in session.store.thread.where((item) => item.fromCrew)) {
      if (!seenRemoteMessages.add(message.id)) continue;
      final line = _RemoteLine(message: message);
      remoteLines.add(line);
      _translateRemoteLine(line);
    }
    if (mounted) setState(() {});
  }

  Future<void> _translateRemoteLine(_RemoteLine line) async {
    final message = line.message;
    final translated =
        message.translated ??
        await c.translator.translate(
          message.original,
          message.sourceLanguage,
          widget.lang,
        );
    if (!mounted) return;
    setState(() => line.translated = translated ?? message.original);
    if (translated != null && c.speakAloud) {
      unawaited(c.speak(translated, widget.lang));
    }
  }

  Future<void> _checkModels() async {
    if (widget.controller != null) {
      if (mounted) setState(() => modelsReady = true);
      return;
    }
    try {
      final ready = await Kit.ready(widget.lang);
      if (mounted) setState(() => modelsReady = ready);
    } catch (e) {
      if (mounted)
        setState(() {
          modelsReady = false;
          modelError = kIsWeb
              ? 'Offline ML Kit translation is not available in Chrome. Run the passenger app on Android or iOS, then download the language kit.'
              : 'Could not check the offline translation models: $e';
        });
    }
  }

  Future<void> _downloadModels() async {
    setState(() {
      downloadingModels = true;
      modelError = null;
    });
    try {
      for (final model in Kit.needed(widget.lang)) {
        if (!await Kit.has(model)) await Kit.download(model);
      }
      final ready = await Kit.ready(widget.lang);
      if (mounted)
        setState(() {
          modelsReady = ready;
          downloadingModels = false;
          modelError = ready
              ? null
              : 'Some required models could not be downloaded.';
        });
    } catch (e) {
      if (mounted)
        setState(() {
          downloadingModels = false;
          modelsReady = false;
          modelError = kIsWeb
              ? 'Model downloads require the Android or iOS app; Chrome cannot install ML Kit models.'
              : 'Download failed: $e';
        });
    }
  }

  @override
  void dispose() {
    if (ownsController) _controller?.dispose();
    _speechEngine?.dispose();
    widget.session?.store.removeListener(_onCabinChanged);
    text.dispose();
    super.dispose();
  }

  String get mine => langByCode(widget.lang).name;

  void toggle(Side side) {
    if (_controller == null) return;
    if (c.listening == side) {
      c.stopListening();
    } else {
      c.startListening(side);
    }
  }

  void sendTyped(Side side) {
    final v = text.text.trim();
    if (v.isEmpty) return;
    text.clear();
    c.typed(side, v);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) {
      return WashiPage(
        title: 'Speak & translate',
        kanji: '通訳',
        children: [
          PaperCard(
            spine: ai,
            child: Row(
              children: const [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Checking and loading offline speech models into memory…',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final live = c.listening != null || c.heard.isNotEmpty;
        return WashiPage(
          title: 'Speak & translate',
          kanji: '通訳',
          actions: [
            IconButton(
              tooltip: c.speakAloud
                  ? 'Reading aloud is on'
                  : 'Reading aloud is off',
              icon: Icon(
                c.speakAloud
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                color: ai,
              ),
              onPressed: () => setState(() => c.speakAloud = !c.speakAloud),
            ),
          ],
          bottom: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (typing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: text,
                              minLines: 1,
                              maxLines: 3,
                              style: const TextStyle(fontSize: 18),
                              decoration: const InputDecoration(
                                hintText: 'Type here',
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Translate what I typed',
                            style: IconButton.styleFrom(
                              backgroundColor: ai,
                              minimumSize: const Size(52, 52),
                            ),
                            onPressed: () => sendTyped(Side.me),
                            icon: const Icon(
                              Icons.translate_rounded,
                              color: Colors.white,
                            ),
                          ),
                          IconButton.filled(
                            tooltip: 'Translate Japanese I typed',
                            style: IconButton.styleFrom(
                              backgroundColor: shuBright,
                              minimumSize: const Size(52, 52),
                            ),
                            onPressed: () => sendTyped(Side.them),
                            icon: const Icon(
                              Icons.translate_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: _Mic(
                          label: 'I speak',
                          sub: mine,
                          color: ai,
                          active: c.listening == Side.me,
                          // Speech and translation have separate failure modes.
                          // Keep the microphone usable so the screen can show the
                          // real speech/model error instead of a dead button.
                          enabled: speechModelsReady && !speechModelsLoading,
                          onTap: () => toggle(Side.me),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _Mic(
                          label: 'They speak',
                          sub: '日本語',
                          color: shuBright,
                          active: c.listening == Side.them,
                          enabled: speechModelsReady && !speechModelsLoading,
                          onTap: () => toggle(Side.them),
                        ),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => typing = !typing),
                    icon: Icon(
                      typing
                          ? Icons.keyboard_hide_rounded
                          : Icons.keyboard_rounded,
                    ),
                    label: Text(typing ? 'Hide keyboard' : 'Type instead'),
                  ),
                ],
              ),
            ),
          ),
          children: [
            if (widget.session != null) _liveCabinBanner(),
            _speechAuditCard(),
            if (remoteLines.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final line in remoteLines.reversed) _remoteLine(line),
            ],
            if (modelsReady != true)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PaperCard(
                  spine: warn,
                  color: const Color(0xFFFFF5E1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.warning_amber_rounded, color: warn),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Download required language models before speaking offline.',
                              style: TextStyle(
                                color: sumi,
                                fontWeight: FontWeight.w800,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (modelError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            modelError!,
                            style: const TextStyle(color: bad),
                          ),
                        ),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: downloadingModels ? null : _downloadModels,
                        icon: downloadingModels
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download_rounded),
                        label: Text(
                          downloadingModels
                              ? 'Downloading models...'
                              : 'Download models',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (c.problem != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PaperCard(
                  spine: warn,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, color: warn),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              explainProblem(c.problem!, widget.lang),
                              style: const TextStyle(
                                fontSize: 16,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          if (c.problem!.startsWith('no_speech'))
                            TextButton(
                              onPressed: () => showDialog<void>(
                                context: context,
                                builder: (_) => const _SetupDialog(),
                              ),
                              child: const Text('How to set up'),
                            ),
                          TextButton(
                            onPressed: c.clearProblem,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (live)
              PaperCard(
                spine: c.listening == Side.them ? shuBright : ai,
                color: kinSoft.withValues(alpha: 0.4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _Pulse(on: c.listening != null),
                        const SizedBox(width: 10),
                        Text(
                          c.listening == null
                              ? 'Translating…'
                              : (c.listening == Side.me
                                    ? 'Listening to you…'
                                    : 'Listening to them…'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: aiDeep,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      c.heard.isEmpty ? '…' : c.heard,
                      style: const TextStyle(fontSize: 18, height: 1.3),
                    ),
                    if (c.heardTranslation != null) ...[
                      const Divider(height: 22),
                      Text(
                        c.heardTranslation!,
                        style: const TextStyle(
                          fontFamily: serifFont,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: aiDeep,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            if (!live && c.history.isEmpty && c.problem == null) const _Intro(),
            const SizedBox(height: 10),
            for (final t in c.history.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _TurnTile(turn: t, onReplay: () => c.replay(t)),
              ),
          ],
        );
      },
    );
  }

  Widget _speechAuditCard() {
    final ready = speechModelsReady && !speechModelsLoading;
    final title = speechModelsLoading
        ? 'Checking offline speech models…'
        : ready
        ? 'Offline speech models ready'
        : 'Offline speech models are not ready';
    final detail = speechModelsLoading
        ? 'Checking folder names, file sizes, and loading the selected recognisers into memory.'
        : ready
        ? 'Sherpa/ONNX is loaded in memory for ${langByCode(widget.lang).name} and 日本語. Speaking works without internet.'
        : (speechModelError ??
              'Download the speech models before using Speak.');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: PaperCard(
        spine: ready ? good : warn,
        color: ready ? good.withValues(alpha: .08) : const Color(0xFFFFF5E1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              ready ? Icons.memory_rounded : Icons.warning_amber_rounded,
              color: ready ? good : warn,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(color: sumiSoft, height: 1.3),
                  ),
                ],
              ),
            ),
            if (speechModelsLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (ready)
              const Icon(Icons.check_circle_rounded, color: good),
          ],
        ),
      ),
    );
  }

  Widget _liveCabinBanner() => PaperCard(
    spine: good,
    color: good.withValues(alpha: .08),
    child: Row(
      children: [
        const Icon(Icons.cell_tower_rounded, color: good, size: 28),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Live cabin translation',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: aiDeep,
                ),
              ),
              Text(
                'Your seat is linked to the crew tablet. Speak here and the translated text is delivered to your crew.',
                style: const TextStyle(color: sumiSoft, height: 1.35),
              ),
            ],
          ),
        ),
        Icon(
          widget.session!.link.online
              ? Icons.cloud_done_rounded
              : Icons.cloud_off_rounded,
          color: widget.session!.link.online ? good : warn,
        ),
      ],
    ),
  );

  Widget _remoteLine(_RemoteLine line) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: PaperCard(
      spine: shu,
      color: shu.withValues(alpha: .08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Crew · translated on your phone',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: shu,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            line.translated ?? 'Translating…',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: aiDeep,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            line.message.original,
            style: const TextStyle(fontSize: 13, color: sumiSoft),
          ),
          if (remoteError != null)
            Text(
              remoteError!,
              style: const TextStyle(fontSize: 12, color: warn),
            ),
        ],
      ),
    ),
  );
}

class _RemoteLine {
  _RemoteLine({required this.message});
  final Message message;
  String? translated;
}

class _Intro extends StatelessWidget {
  const _Intro();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 8),
    child: Text(
      'Tap "I speak" and talk in your own language. The Japanese appears while you speak and is read aloud for the other person.\n\nWhen they answer, tap "They speak" and hold the phone towards them. You see and hear it in your language.',
      style: TextStyle(fontSize: 17, color: sumiSoft, height: 1.45),
    ),
  );
}

class _Mic extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  const _Mic({
    required this.label,
    required this.sub,
    required this.color,
    required this.active,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: active ? 'Stop listening' : '$label, $sub',
    child: SizedBox(
      height: 84,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: active ? Colors.black87 : color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        onPressed: enabled ? onTap : null,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(active ? Icons.stop_rounded : Icons.mic_rounded, size: 30),
            Text(
              active ? 'Tap to stop' : label,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
            ),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Pulse extends StatefulWidget {
  final bool on;
  const _Pulse({required this.on});
  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController a = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.on) a.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _Pulse old) {
    super.didUpdateWidget(old);
    if (widget.on && !a.isAnimating) a.repeat(reverse: true);
    if (!widget.on) a.stop();
  }

  @override
  void dispose() {
    a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween(begin: 0.35, end: 1.0).animate(a),
    child: const Icon(Icons.mic_rounded, color: shuBright),
  );
}

class _TurnTile extends StatelessWidget {
  final Turn turn;
  final VoidCallback onReplay;
  const _TurnTile({required this.turn, required this.onReplay});

  @override
  Widget build(BuildContext context) {
    final me = turn.side == Side.me;
    return Align(
      alignment: me ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.9,
        ),
        child: PaperCard(
          spine: me ? ai : shuBright,
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                turn.translated ?? '',
                style: const TextStyle(
                  fontFamily: serifFont,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: aiDeep,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                turn.original,
                style: const TextStyle(fontSize: 15, color: sumiSoft),
              ),
              Row(
                children: [
                  if (turn.translateTime != null)
                    Text(
                      '${(turn.translateTime!.inMilliseconds / 1000).toStringAsFixed(1)} s',
                      style: const TextStyle(fontSize: 12, color: sumiSoft),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Read aloud',
                    onPressed: onReplay,
                    icon: const Icon(Icons.volume_up_rounded, color: ai),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupDialog extends StatelessWidget {
  const _SetupDialog();
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Listen with no connection'),
    content: const SingleChildScrollView(
      child: Text(
        'HASHI listens with its bundled Sherpa/ONNX models. To use a language offline:\n\n'
        '1. Connect to the aircraft Wi-Fi.\n'
        '2. Download the speech models from the model card on the In-flight screen.\n'
        '3. Wait for the audit to say “Offline speech models ready”.\n\n'
        'The model files are checked by name and size, then loaded into a worker before the microphone is enabled.',
        style: TextStyle(fontSize: 16, height: 1.4),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('OK'),
      ),
    ],
  );
}

/// Keeps the screen usable when the local model store itself cannot be opened,
/// while making the failure explicit instead of leaving a microphone button
/// that appears to work but cannot produce audio.
class _UnavailableSpeechEngine implements SpeechEngine {
  @override
  Future<bool> supports(String locale) async => false;

  @override
  Future<bool> prepare(String locale) async => false;

  @override
  Stream<SpeechEvent> listen(String locale) =>
      Stream.value(const SpeechEvent('', error: 'offline_speech_unavailable'));

  @override
  Future<void> stop() async {}
}
