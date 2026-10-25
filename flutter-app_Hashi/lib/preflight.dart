import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'theme.dart';
import 'central.dart';
import 'kit.dart';
import 'languages.dart';
import 'models.dart';
import 'repo.dart';
import 'push_notifications.dart';

/// Phase 1, pre-flight. The booking, seat and preferences come from the passenger's account on the central backend
/// and are cached on the phone, so the screen also works with no signal. The airline's push notification is still simulated.
class PreflightScreen extends StatefulWidget {
  final Profile profile;
  final PassengerRepo repo;
  const PreflightScreen({super.key, required this.profile, required this.repo});

  @override
  State<PreflightScreen> createState() => _PreflightScreenState();
}

class _PreflightScreenState extends State<PreflightScreen> {
  bool notified = false;
  final Map<String, String> kit = {}; // model code -> state
  bool downloading = false;
  bool busy = false;
  bool checkingKit = true;
  String? error;
  ModelStore? aircraftModelStore;
  final Map<String, double> aircraftProgress = {};
  bool downloadingAircraftModels = false;
  String? aircraftModelError;
  late final TextEditingController central = TextEditingController(
    text: widget.profile.central,
  );
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Keep the demo notification action visible even when the passenger is
    // already signed in, so the booking-to-preferences flow can be shown.
    notified = false;
    _refreshKit();
    _openAircraftModelStore();
  }

  Profile get p => widget.profile;
  PassengerRepo get repo => widget.repo;

  void adopt() => applyAccountToProfile(p, repo.preferences, repo.trip);

  Future<void> signIn() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      p.central = central.text.trim();
      repo.client.baseUrl = p.central;
      await repo.signIn(email.text.trim(), password.text);
      adopt();
      await p.save();
      unawaited(
        PushNotifications.instance.register(repo.client, repo.deviceId),
      );
      notified = true;
    } on CentralException catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> savePreferences() async {
    final sent = await repo.edit(preferencesFromProfile(p, repo.preferences));
    await p.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          sent
              ? 'Saved to your account'
              : 'Saved on this phone, will sync when there is a signal',
        ),
      ),
    );
    setState(() {});
  }

  Future<void> downloadKit() async {
    if (mounted)
      setState(() {
        downloading = true;
        error = null;
      });
    for (final l in Kit.needed(p.lang)) {
      if (!mounted) return;
      setState(() => kit[l.bcpCode] = 'downloading');
      try {
        final ok = await Kit.has(l) || await Kit.download(l);
        if (mounted) setState(() => kit[l.bcpCode] = ok ? 'ready' : 'failed');
      } catch (_) {
        if (mounted) setState(() => kit[l.bcpCode] = 'failed');
      }
    }
    if (mounted) setState(() => downloading = false);
  }

  Future<void> _refreshKit() async {
    if (mounted) setState(() => checkingKit = true);
    final states = await Kit.status(p.lang);
    if (!mounted) return;
    setState(() {
      kit
        ..clear()
        ..addAll(
          states.map(
            (code, installed) =>
                MapEntry(code, installed ? 'ready' : 'not downloaded'),
          ),
        );
      checkingKit = false;
    });
  }

  Future<void> _openAircraftModelStore() async {
    try {
      final store = await ModelStore.open();
      if (mounted) setState(() => aircraftModelStore = store);
    } catch (_) {
      // The edge model cache is unavailable on platforms without local files.
    }
  }

  Future<void> downloadAircraftModels() async {
    final store = aircraftModelStore;
    final credentials = repo.cabinCredentials;
    if (store == null || credentials == null) {
      setState(
        () => aircraftModelError = credentials == null
            ? 'Join the aircraft cabin network first. The local model server is available after boarding.'
            : 'The local model cache is not available on this device.',
      );
      return;
    }
    setState(() {
      downloadingAircraftModels = true;
      aircraftModelError = null;
    });
    try {
      for (final model in speechModels) {
        if (store.installed(model)) continue;
        await store.downloadFromEdge(
          model,
          baseUrl: p.server,
          deviceToken: credentials.deviceToken,
          onProgress: (value) {
            if (mounted) setState(() => aircraftProgress[model.id] = value);
          },
        );
      }
    } catch (e) {
      aircraftModelError = 'Aircraft model download failed: $e';
    }
    if (mounted) setState(() => downloadingAircraftModels = false);
  }

  Widget aircraftModelCard() {
    final store = aircraftModelStore;
    return PaperCard(
      spine: ai,
      color: const Color(0xFFF1F5FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Download from the aircraft',
            style: TextStyle(
              fontFamily: serifFont,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              color: aiDeep,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'If you missed the pre-flight download, the aircraft Wi-Fi can provide the speech models locally. No internet is required.',
            style: TextStyle(fontSize: 15, color: sumiSoft, height: 1.3),
          ),
          const SizedBox(height: 8),
          for (final model in speechModels)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory_rounded, color: ai),
              title: Text(model.title),
              subtitle: Text(
                store?.installed(model) == true
                    ? 'Ready on this phone'
                    : aircraftProgress.containsKey(model.id)
                    ? '${(aircraftProgress[model.id]! * 100).round()}% downloaded'
                    : '${(model.totalBytes / 1000000).round()} MB · aircraft cache',
              ),
            ),
          if (aircraftModelError != null)
            Text(
              aircraftModelError!,
              style: const TextStyle(color: bad, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: downloadingAircraftModels
                ? null
                : downloadAircraftModels,
            icon: const Icon(Icons.wifi_rounded),
            label: Text(
              downloadingAircraftModels
                  ? 'Downloading from aircraft...'
                  : 'Download missing speech models',
            ),
          ),
        ],
      ),
    );
  }

  String label(String code) =>
      {
        TranslateLanguage.japanese.bcpCode: '日本語 Japanese',
        TranslateLanguage.english.bcpCode: 'English',
      }[code] ??
      langByCode(p.lang).name;

  Widget accountCard() => PaperCard(
    spine: kin,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Sign in to get your booking',
          style: TextStyle(
            fontFamily: serifFont,
            fontWeight: FontWeight.w800,
            fontSize: 20,
            color: aiDeep,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Your seat comes from your booking. You never type it.',
          style: TextStyle(fontSize: 15, color: sumiSoft),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: central,
          decoration: const InputDecoration(
            labelText: 'Booking server address',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: email,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(labelText: 'Email'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: password,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Password'),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: bad, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    error!,
                    style: const TextStyle(
                      color: bad,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: busy ? null : signIn,
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Sign in'),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => setState(() {
                email.text = 'demo.passenger@example.com';
                password.text = 'demo-pass-123';
              }),
              child: const Text('Fill demo account'),
            ),
          ],
        ),
      ],
    ),
  );

  Widget bookingCard() {
    final t = repo.trip;
    return PaperCard(
      spine: ai,
      child: Row(
        children: [
          const Icon(Icons.flight_takeoff_rounded, color: ai, size: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t == null
                      ? 'No upcoming booking found'
                      : '${t.flightNumber} · ${t.from} → ${t.to}',
                  style: const TextStyle(
                    fontFamily: serifFont,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: aiDeep,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  t == null
                      ? 'Check that your booking is confirmed.'
                      : 'Seat ${t.seat} · from your booking',
                  style: const TextStyle(fontSize: 16, color: sumiSoft),
                ),
              ],
            ),
          ),
          if (notified)
            const Icon(Icons.check_circle_rounded, color: good, size: 28),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = langByCode(p.lang);
    return WashiPage(
      title: 'Before you fly',
      kanji: '出発前',
      children: [
        if (!repo.signedIn) accountCard() else bookingCard(),
        const SizedBox(height: 12),
        if (!notified)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: shuBright),
            onPressed: () => setState(() => notified = true),
            icon: const Icon(Icons.notifications_active_rounded),
            label: const Text('Show the notification the passenger would get'),
          ),
        if (notified) ...[
          PaperCard(
            color: kinSoft,
            child: const Row(
              children: [
                Icon(Icons.notifications_rounded, color: aiDeep),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tell the crew how to help you. Set your language and needs, and get your language kit for the flight.',
                    style: TextStyle(fontSize: 16, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('一', 'Your language'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final x in languages)
                ChoiceChip(
                  label: Text(x.name),
                  selected: p.lang == x.code,
                  onSelected: (_) {
                    setState(() => p.lang = x.code);
                    _refreshKit();
                  },
                ),
            ],
          ),
          const SectionTitle('二', 'What helps you'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  title: const Text(
                    'Bigger text and pictures',
                    style: TextStyle(fontSize: 17),
                  ),
                  value: p.senior,
                  onChanged: (v) => setState(() {
                    p.senior = v;
                    seniorMode.value = v;
                  }),
                ),
                for (final n in const {
                  'veg': 'Vegetarian',
                  'hearing': 'I hear less well',
                  'mobility': 'I need help walking',
                }.entries)
                  CheckboxListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    title: Text(n.value, style: const TextStyle(fontSize: 17)),
                    value: p.needs.contains(n.key),
                    onChanged: (v) => setState(
                      () => v == true
                          ? p.needs.add(n.key)
                          : p.needs.remove(n.key),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: savePreferences,
            child: const Text('Save my preferences'),
          ),
          if (repo.hasPendingEdit)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Waiting for a signal: your changes are kept on this phone and will be sent later.',
                style: TextStyle(color: warn, fontWeight: FontWeight.w600),
              ),
            ),
          SectionTitle('三', 'Language kit for ${l.name}'),
          if (checkingKit)
            const ListTile(
              contentPadding: EdgeInsets.zero,
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: ai),
              ),
              title: Text('Checking this phone for downloaded models...'),
            )
          else if (kit.values.every((state) => state == 'ready'))
            const PaperCard(
              spine: good,
              color: Color(0xFFE8F6EF),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: good),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'All required translation models are ready for offline use.',
                      style: TextStyle(
                        color: good,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            const PaperCard(
              spine: warn,
              color: Color(0xFFFFF5E1),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber_rounded, color: warn),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offline translation is not ready yet. Download the required language models before boarding. This may use hundreds of MB on Wi-Fi.',
                      style: TextStyle(
                        color: sumi,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const Text(
            'These translation models are not bundled in the app. Download them once on Wi-Fi; they stay on this phone and work without a connection.',
            style: TextStyle(fontSize: 16, color: sumiSoft, height: 1.35),
          ),
          if (l.ml == null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${l.name} has no on-device model: signs will be translated to English.',
                style: const TextStyle(
                  color: warn,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 10),
          PaperCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final m in Kit.needed(p.lang))
                  ListTile(
                    leading: switch (kit[m.bcpCode]) {
                      'ready' => const Icon(
                        Icons.check_circle_rounded,
                        color: good,
                      ),
                      'downloading' => const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          color: ai,
                        ),
                      ),
                      'failed' => const Icon(Icons.error_rounded, color: bad),
                      _ => const Icon(
                        Icons.download_for_offline_outlined,
                        color: ai,
                      ),
                    },
                    title: Text(
                      label(m.bcpCode),
                      style: const TextStyle(fontSize: 17),
                    ),
                    subtitle: Text(kit[m.bcpCode] ?? 'not downloaded'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: downloading || checkingKit ? null : downloadKit,
            icon: const Icon(Icons.download_rounded),
            label: Text(
              downloading
                  ? 'Downloading models...'
                  : 'Download required models',
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('四', 'Aircraft model cache'),
          aircraftModelCard(),
        ],
      ],
    );
  }
}
