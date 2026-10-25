import 'package:flutter/material.dart';

import 'content.dart';
import 'languages.dart';
import 'protocol.dart';
import 'session.dart';
import 'theme.dart';

/// A written conversation with the crew. The passenger types in their own language; the crew read Japanese, and the
/// passenger first sees the Japanese translated back, to check it says what they meant, before anything is sent.
class TalkScreen extends StatefulWidget {
  final CabinSession session;
  const TalkScreen({super.key, required this.session});

  @override
  State<TalkScreen> createState() => _TalkScreenState();
}

class _TalkScreenState extends State<TalkScreen> {
  final text = TextEditingController();
  String? notice;

  CabinSession get s => widget.session;
  String get lang => s.profile.lang;
  String t(String k) => Content.instance.t(lang, k);

  void send() {
    final v = text.text.trim();
    if (v.isEmpty) return;
    if (!s.link.say(v)) {
      setState(() => notice = 'Not connected to the crew yet. Try again when the line is back.');
      return;
    }
    text.clear();
    setState(() => notice = null);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s.store,
      builder: (context, _) {
        final pending = s.store.pendingMessage;
        final error = s.store.lastError;
        return WashiPage(
          title: 'Talk to the crew',
          kanji: '会話',
          bottom: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: text,
                    minLines: 1,
                    maxLines: 3,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => send(),
                    decoration: InputDecoration(hintText: 'Type here in ${langByCode(lang).name}', contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filled(style: IconButton.styleFrom(minimumSize: const Size(56, 56), backgroundColor: ai), tooltip: 'Check my message', onPressed: send, icon: const Icon(Icons.send_rounded, color: Colors.white)),
              ]),
            ),
          ),
          children: [
            const Text('Write in your own language. The crew read it in Japanese. You will see it translated back first, so you can check it.', style: TextStyle(fontSize: 16, color: sumiSoft, height: 1.35)),
            if (notice != null) Padding(padding: const EdgeInsets.only(top: 10), child: StatusBanner(icon: Icons.wifi_off_rounded, color: warn, title: 'Not sent', detail: notice!)),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: StatusBanner(
                  icon: Icons.hourglass_top_rounded,
                  color: warn,
                  title: error == 'model_not_ready' ? 'The translator is still starting' : 'Something went wrong',
                  detail: error == 'model_not_ready' ? 'Please try again in a minute, or use the picture cards.' : error,
                ),
              ),
            if (pending != null) Padding(padding: const EdgeInsets.only(top: 14), child: _Check(message: pending, session: s)),
            const SizedBox(height: 14),
            for (final m in s.store.thread.where((m) => m.status != 'pending' && m.status != 'cancelled').toList().reversed) Padding(padding: const EdgeInsets.only(bottom: 10), child: _Bubble(message: m, session: s)),
            if (s.store.thread.isEmpty && pending == null) const Padding(padding: EdgeInsets.only(top: 20), child: Text('No messages yet.', style: TextStyle(color: sumiSoft))),
          ],
        );
      },
    );
  }
}

/// The check step: what the crew will read, and the same thing translated back.
class _Check extends StatelessWidget {
  final Message message;
  final CabinSession session;
  const _Check({required this.message, required this.session});

  @override
  Widget build(BuildContext context) {
    final lang = session.profile.lang;
    return PaperCard(
      spine: message.warn ? warn : kin,
      color: kinSoft.withValues(alpha: 0.5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Please check before sending', style: TextStyle(fontFamily: serifFont, fontSize: 18, fontWeight: FontWeight.w800, color: aiDeep)),
        const SizedBox(height: 10),
        const Text('You wrote', style: TextStyle(fontSize: 13, color: sumiSoft, fontWeight: FontWeight.w700)),
        Text(message.original, style: const TextStyle(fontSize: 18)),
        const SizedBox(height: 10),
        const Text('The crew will read (Japanese)', style: TextStyle(fontSize: 13, color: sumiSoft, fontWeight: FontWeight.w700)),
        Text(message.ja ?? '', style: const TextStyle(fontFamily: serifFont, fontSize: 22, fontWeight: FontWeight.w800, color: aiDeep)),
        const SizedBox(height: 10),
        const Text('Translated back to you', style: TextStyle(fontSize: 13, color: sumiSoft, fontWeight: FontWeight.w700)),
        Text(message.back ?? '', style: const TextStyle(fontSize: 18)),
        if (message.warn)
          const Padding(
            padding: EdgeInsets.only(top: 10),
            child: Row(children: [Icon(Icons.warning_amber_rounded, color: warn), SizedBox(width: 8), Expanded(child: Text('This may not say what you meant. Try shorter, simpler words.', style: TextStyle(color: warn, fontWeight: FontWeight.w700)))]),
          ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: good), onPressed: () => session.link.confirmSay(message.id), icon: const Icon(Icons.send_rounded), label: Text(Content.instance.t(lang, 'yes')))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton(onPressed: () => session.link.cancelSay(message.id), child: Text(Content.instance.t(lang, 'cancel')))),
        ]),
      ]),
    );
  }
}

class _Bubble extends StatelessWidget {
  final Message message;
  final CabinSession session;
  const _Bubble({required this.message, required this.session});

  @override
  Widget build(BuildContext context) {
    final lang = session.profile.lang;
    final m = message;
    if (!m.fromCrew) {
      return Align(
        alignment: Alignment.centerRight,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          child: PaperCard(color: ai, padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(m.original, style: const TextStyle(color: Colors.white, fontSize: 17)),
            if (m.ja != null) Text(m.ja!, style: const TextStyle(color: Color(0xFFD5DBF0), fontSize: 15, fontFamily: serifFont)),
          ])),
        ),
      );
    }
    final mine = m.translated ?? m.original;
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.88),
        child: PaperCard(
          spine: m.lane == 'vetted' ? good : warn,
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Crew · 乗務員', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: shu, letterSpacing: 1)),
            const SizedBox(height: 4),
            Text(mine, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.3)),
            if (m.translated != null) Text(m.original, style: const TextStyle(fontSize: 14, color: sumiSoft, fontFamily: serifFont)),
            const SizedBox(height: 4),
            Text(m.lane == 'vetted' ? 'Approved wording' : 'Machine translation: it may not be exact', style: TextStyle(fontSize: 12.5, color: m.lane == 'vetted' ? good : warn, fontWeight: FontWeight.w600)),
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(onPressed: () => speakText(mine, langByCode(lang).tts), icon: const Icon(Icons.volume_up_rounded), label: Text(Content.instance.t(lang, 'play')))),
          ]),
        ),
      ),
    );
  }
}
