import 'package:flutter/material.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import 'theme.dart';
import 'central.dart';
import 'kit.dart';
import 'languages.dart';
import 'repo.dart';

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
  String? error;
  late final TextEditingController central = TextEditingController(text: widget.profile.central);
  final email = TextEditingController();
  final password = TextEditingController();

  Profile get p => widget.profile;
  PassengerRepo get repo => widget.repo;

  void adopt() => applyAccountToProfile(p, repo.preferences, repo.trip);

  Future<void> signIn() async {
    setState(() { busy = true; error = null; });
    try {
      p.central = central.text.trim();
      repo.client.baseUrl = p.central;
      await repo.signIn(email.text.trim(), password.text);
      adopt();
      await p.save();
    } on CentralException catch (e) {
      error = e.message;
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> savePreferences() async {
    final sent = await repo.edit(preferencesFromProfile(p, repo.preferences));
    await p.save();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent ? 'Saved to your account' : 'Saved on this phone, will sync when there is a signal')));
    setState(() {});
  }

  Future<void> downloadKit() async {
    setState(() => downloading = true);
    for (final l in Kit.needed(p.lang)) {
      setState(() => kit[l.bcpCode] = 'downloading');
      try {
        final ok = await Kit.has(l) || await Kit.download(l);
        setState(() => kit[l.bcpCode] = ok ? 'ready' : 'failed');
      } catch (_) {
        setState(() => kit[l.bcpCode] = 'failed');
      }
    }
    setState(() => downloading = false);
  }

  String label(String code) => {
        TranslateLanguage.japanese.bcpCode: '日本語 Japanese',
        TranslateLanguage.english.bcpCode: 'English',
      }[code] ??
      langByCode(p.lang).name;

  Widget accountCard() => PaperCard(
        spine: kin,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Sign in to get your booking', style: TextStyle(fontFamily: serifFont, fontWeight: FontWeight.w800, fontSize: 20, color: aiDeep)),
          const SizedBox(height: 4),
          const Text('Your seat comes from your booking. You never type it.', style: TextStyle(fontSize: 15, color: sumiSoft)),
          const SizedBox(height: 12),
          TextField(controller: central, decoration: const InputDecoration(labelText: 'Booking server address')),
          const SizedBox(height: 10),
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
          const SizedBox(height: 10),
          TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password')),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Row(children: [const Icon(Icons.error_outline_rounded, color: bad, size: 20), const SizedBox(width: 6), Expanded(child: Text(error!, style: const TextStyle(color: bad, fontWeight: FontWeight.w600)))])),
          const SizedBox(height: 12),
          Row(children: [
            FilledButton(onPressed: busy ? null : signIn, child: busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Sign in')),
            const SizedBox(width: 8),
            TextButton(onPressed: () => setState(() { email.text = 'demo.passenger@example.com'; password.text = 'demo-pass-123'; }), child: const Text('Fill demo account')),
          ]),
        ]),
      );

  Widget bookingCard() {
    final t = repo.trip;
    return PaperCard(
      spine: ai,
      child: Row(children: [
        const Icon(Icons.flight_takeoff_rounded, color: ai, size: 32),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t == null ? 'No upcoming booking found' : '${t.flightNumber} · ${t.from} → ${t.to}', style: const TextStyle(fontFamily: serifFont, fontSize: 20, fontWeight: FontWeight.w800, color: aiDeep)),
            const SizedBox(height: 2),
            Text(t == null ? 'Check that your booking is confirmed.' : 'Seat ${t.seat} · from your booking', style: const TextStyle(fontSize: 16, color: sumiSoft)),
          ]),
        ),
        if (notified) const Icon(Icons.check_circle_rounded, color: good, size: 28),
      ]),
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
            child: const Row(children: [
              Icon(Icons.notifications_rounded, color: aiDeep),
              SizedBox(width: 12),
              Expanded(child: Text('Tell the crew how to help you. Set your language and needs, and get your language kit for the flight.', style: TextStyle(fontSize: 16, height: 1.35))),
            ]),
          ),
          const SectionTitle('一', 'Your language'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in languages) ChoiceChip(label: Text(x.name), selected: p.lang == x.code, onSelected: (_) => setState(() => p.lang = x.code)),
          ]),
          const SectionTitle('二', 'What helps you'),
          PaperCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Column(children: [
              SwitchListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 10), title: const Text('Bigger text and pictures', style: TextStyle(fontSize: 17)), value: p.senior, onChanged: (v) => setState(() { p.senior = v; seniorMode.value = v; })),
              for (final n in const {'veg': 'Vegetarian', 'hearing': 'I hear less well', 'mobility': 'I need help walking'}.entries)
                CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  title: Text(n.value, style: const TextStyle(fontSize: 17)),
                  value: p.needs.contains(n.key),
                  onChanged: (v) => setState(() => v == true ? p.needs.add(n.key) : p.needs.remove(n.key)),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: savePreferences, child: const Text('Save my preferences')),
          if (repo.hasPendingEdit) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Waiting for a signal: your changes are kept on this phone and will be sent later.', style: TextStyle(color: warn, fontWeight: FontWeight.w600))),
          SectionTitle('三', 'Language kit for ${l.name}'),
          const Text('Small translation models stay on your phone so the camera translator works with no signal. Download them now, on Wi-Fi.', style: TextStyle(fontSize: 16, color: sumiSoft, height: 1.35)),
          if (l.ml == null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('${l.name} has no on-device model: signs will be translated to English.', style: const TextStyle(color: warn, fontWeight: FontWeight.w600))),
          const SizedBox(height: 10),
          PaperCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [
              for (final m in Kit.needed(p.lang))
                ListTile(
                  leading: switch (kit[m.bcpCode]) {
                    'ready' => const Icon(Icons.check_circle_rounded, color: good),
                    'downloading' => const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: ai)),
                    'failed' => const Icon(Icons.error_rounded, color: bad),
                    _ => const Icon(Icons.download_for_offline_outlined, color: ai),
                  },
                  title: Text(label(m.bcpCode), style: const TextStyle(fontSize: 17)),
                  subtitle: Text(kit[m.bcpCode] ?? 'not downloaded'),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: downloading ? null : downloadKit, icon: const Icon(Icons.download_rounded), label: const Text('Download language kit')),
        ],
      ],
    );
  }
}
