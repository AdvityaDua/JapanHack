import 'dart:async';

import 'package:flutter/material.dart';

import 'cabin.dart';
import 'cards.dart';
import 'content.dart';
import 'decks.dart';
import 'discover.dart';
import 'hubs.dart';
import 'protocol.dart';
import 'repo.dart';
import 'session.dart';
import 'talk.dart';
import 'theme.dart';
import 'tiles.dart';
import 'backend/backend_config.dart';

/// The in-flight home: how the line to the crew is, the big help button, the requests in progress with the crew's
/// replies, and the doors to the cards and the conversation. Everything here is native; nothing opens in a browser.
class InFlightScreen extends StatefulWidget {
  final CabinSession session;

  /// Tests can pass the cards directly instead of loading the bundled file.
  final List<HashiCard>? cards;

  /// Used to board with the booking pass; without it the screen still works but cannot find the cabin by itself.
  final PassengerRepo? repo;

  /// Look for the cabin by itself while the line is down. Switched off in tests.
  final bool autoJoin;
  final Future<CabinConnection> Function(List<String> hosts)? connector;
  const InFlightScreen({
    super.key,
    required this.session,
    this.cards,
    this.repo,
    this.autoJoin = true,
    this.connector,
  });

  @override
  State<InFlightScreen> createState() => _InFlightScreenState();
}

class _InFlightScreenState extends State<InFlightScreen> {
  Map<String, HashiCard> byId = {};
  Timer? _searchTimer;
  bool _searching = false;
  bool _notFound = false;

  CabinSession get s => widget.session;
  String get lang => s.profile.lang;
  String t(String key) => Content.instance.t(lang, key);

  /// Looks for the cabin network and, when it is found, opens the live line. Tried again every few seconds until it works.
  Future<void> _search() async {
    if (!mounted ||
        _searching ||
        s.link.online ||
        s.store.link == LinkState.connecting)
      return;
    setState(() => _searching = true);
    final p = s.profile;
    final hosts = defaultCabinHosts(
      lastGood: p.server.isEmpty ? null : p.server,
      configured: cabinBackendOverride,
    );
    final repo = widget.repo;
    final result =
        await (widget.connector ??
            (h) => connectToCabin(
              hosts: h,
              getGrant: repo?.boardingGrant ?? () async => null,
              deviceId: repo?.deviceId ?? 'phone-unknown',
              bookedSeat: p.seat.isEmpty ? null : p.seat,
              useCommunicationBackend: true,
              displayName: 'Passenger ${p.seat}',
            ))(hosts);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _notFound = !result.connected;
    });
    if (result.connected) {
      p.server = result.baseUrl!;
      if (result.credentials != null && repo != null)
        await repo.saveCabinCredentials(result.credentials!);
      s.connect(
        result.baseUrl!,
        credentials: result.credentials,
      ); // open the line first; remembering the address can wait
      await p.save();
    }
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.autoJoin) {
      _search();
      _searchTimer = Timer.periodic(
        const Duration(seconds: 6),
        (_) => _search(),
      );
    }
    if (widget.cards != null) {
      byId = {for (final c in widget.cards!) c.id: c};
    } else {
      loadFlightCards().then((list) {
        if (mounted) setState(() => byId = {for (final c in list) c.id: c});
      });
    }
  }

  Future<void> askForHelp() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: const Icon(Icons.emergency_rounded, color: shu, size: 40),
        title: Text(t('helpSure'), textAlign: TextAlign.center),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('no'), style: const TextStyle(fontSize: 18)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: shuBright),
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('yes')),
          ),
        ],
      ),
    );
    if (yes == true) s.link.sendRequest('help', via: 'sos');
  }

  ({IconData icon, Color color, String title, String detail})
  banner() => switch (s.store.link) {
    LinkState.online => (
      icon: Icons.check_circle_rounded,
      color: good,
      title: 'Connected to the crew',
      detail: 'Seat ${s.profile.seat}. The crew can see your requests.',
    ),
    LinkState.connecting => (
      icon: Icons.sync_rounded,
      color: warn,
      title: 'Connecting…',
      detail: 'Looking for the cabin.',
    ),
    LinkState.offline => (
      icon: Icons.wifi_off_rounded,
      color: warn,
      title: 'Reconnecting…',
      detail:
          'Your requests are kept and will be sent as soon as the line is back.',
    ),
    LinkState.idle =>
      _searching
          ? (
              icon: Icons.wifi_find_rounded,
              color: warn,
              title: 'Looking for the cabin…',
              detail:
                  'Connect to the aircraft Wi-Fi. Speaking and translating still work with no connection.',
            )
          : (
              icon: Icons.link_off_rounded,
              color: warn,
              title: _notFound ? 'Cabin not found yet' : 'Not connected',
              detail:
                  'Connect to the aircraft Wi-Fi. This page keeps looking. Speaking and translating still work with no connection.',
            ),
  };

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: s.store,
      builder: (context, _) {
        final b = banner();
        final active = s.store.activeRequests;
        return WashiPage(
          title: 'In flight',
          kanji: '機内',
          children: [
            StatusBanner(
              icon: b.icon,
              color: b.color,
              title: b.title,
              detail: b.detail,
              busy: s.store.link == LinkState.connecting,
            ),
            const SizedBox(height: 14),
            Semantics(
              button: true,
              label: 'I need help. Call the crew.',
              child: SizedBox(
                height: 84,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: shuBright,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                    ),
                  ),
                  onPressed: askForHelp,
                  icon: const Icon(Icons.emergency_rounded, size: 34),
                  label: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        t('helpBig'),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Text('助けてください', style: TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SpeakBar(lang: lang),
            if (s.store.link != LinkState.online)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CabinScreen(
                        profile: s.profile,
                        repo: widget.repo!,
                        ensureSession: () => s,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.settings_ethernet_rounded),
                  label: const Text('Connection details'),
                ),
              ),
            SectionTitle('一', t('askWhat')),
            TileGrid(
              tiles: [
                for (final id in const [
                  'water',
                  'food',
                  'blanket',
                  'toilet',
                  'medicine',
                ])
                  if (byId[id] != null)
                    CardTile(
                      icon: byId[id]!.icon,
                      label: _label(id),
                      style: tileStyleFor(Deck.flight, byId[id]!.group),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FullCard(
                            card: byId[id]!,
                            profile: s.profile,
                            deck: Deck.flight,
                            session: s,
                          ),
                        ),
                      ),
                    ),
                CardTile(
                  icon: Icons.add_rounded,
                  label: 'More',
                  style: tileStyleFor(Deck.flight, 'comfort'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DeckScreen(
                        deck: Deck.flight,
                        profile: s.profile,
                        session: s,
                        cards: widget.cards,
                      ),
                    ),
                  ),
                ),
                CardTile(
                  icon: Icons.forum_rounded,
                  label: 'Type to the crew',
                  style: tileStyleFor(Deck.flight, 'info'),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TalkScreen(session: s)),
                  ),
                ),
              ],
            ),
            if (s.store.queued.isNotEmpty) ...[
              const SectionTitle('二', 'Waiting to be sent'),
              for (final q in s.store.queued)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: PaperCard(
                    spine: warn,
                    child: Row(
                      children: [
                        const Icon(Icons.schedule_send_rounded, color: warn),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _label(q.intent),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const Text(
                          'Waiting for the line',
                          style: TextStyle(
                            color: warn,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
            if (active.isNotEmpty) ...[
              SectionTitle(s.store.queued.isEmpty ? '二' : '三', 'My requests'),
              for (var i = 0; i < active.length; i++)
                Entrance(
                  key: ValueKey(active[i].id),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: RequestTile(
                      request: active[i],
                      session: s,
                      label: _label(active[i].intent),
                      icon:
                          byId[active[i].intent]?.icon ??
                          Icons.help_outline_rounded,
                    ),
                  ),
                ),
            ],
            if (active.isEmpty && s.store.queued.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 22),
                child: Text(
                  'No requests yet. Tap "What do you need?" and choose a picture, or press the red button if it is urgent.',
                  style: TextStyle(fontSize: 16, color: sumiSoft, height: 1.4),
                ),
              ),
          ],
        );
      },
    );
  }

  String _label(String intent) {
    final c = byId[intent];
    if (c == null) return intent;
    return c.labels[lang] ?? c.en;
  }
}

/// One request in progress: the three steps (sent, crew coming, crew replied), the crew's reply as a picture, words and sound,
/// and the "I understood" button that tells the crew the message arrived.
class RequestTile extends StatelessWidget {
  final CabinRequest request;
  final CabinSession session;
  final String label;
  final IconData icon;
  const RequestTile({
    super.key,
    required this.request,
    required this.session,
    required this.label,
    required this.icon,
  });

  String get lang => session.profile.lang;
  String t(String key) => Content.instance.t(lang, key);

  @override
  Widget build(BuildContext context) {
    final r = request;
    final reply = r.lastReply == null
        ? null
        : Content.instance.replies[r.lastReply!.replyId];
    final step = switch (r.status) {
      RequestStatus.fresh => 0,
      RequestStatus.seen => 1,
      _ => 2,
    };
    return PaperCard(
      spine: r.urgency >= 3 ? shu : ai,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: ai, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontFamily: serifFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: aiDeep,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Step(done: step >= 0, text: t('sent')),
              _Step(done: step >= 1, text: t('seen')),
              _Step(done: step >= 2, text: t('replied')),
            ],
          ),
          if (reply != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kinSoft.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(flightIcon(reply.icon), color: aiDeep, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          reply.say(lang),
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => playClip(
                        'reply_${reply.id}_$lang.mp3',
                        reply.say(lang),
                        lang,
                      ),
                      icon: const Icon(Icons.volume_up_rounded),
                      label: Text(t('play')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            if (r.needsUnderstood)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: good,
                    minimumSize: const Size.fromHeight(56),
                  ),
                  onPressed: () => session.link.understood(r.id),
                  icon: const Icon(Icons.verified_rounded),
                  label: Text(t('understood')),
                ),
              )
            else if (r.understoodAt != null)
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: good),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      t('understoodDone'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: good,
                      ),
                    ),
                  ),
                ],
              ),
          ],
          if (r.status == RequestStatus.fresh || r.status == RequestStatus.seen)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => session.link.cancelRequest(r.id),
                child: Text(t('cancel')),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final bool done;
  final String text;
  const _Step({required this.done, required this.text});

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Icon(
          done
              ? Icons.check_circle_rounded
              : Icons.radio_button_unchecked_rounded,
          color: done ? good : sumiSoft.withValues(alpha: 0.5),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: done ? FontWeight.w800 : FontWeight.w500,
            color: done ? sumi : sumiSoft,
            height: 1.2,
          ),
        ),
      ],
    ),
  );
}
