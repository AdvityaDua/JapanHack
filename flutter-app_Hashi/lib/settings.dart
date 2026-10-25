import 'package:flutter/material.dart';

import 'kit.dart';
import 'languages.dart';
import 'repo.dart';
import 'session.dart';
import 'theme.dart';

/// What the crew and the app should know about the passenger. Changes are saved on the phone at once and sent to the account
/// when there is a signal; the cabin app picks them up the next time it opens.
const needOptions = <String, (String, IconData)>{
  'veg': ('I eat vegetarian food', Icons.eco_rounded),
  'diabetic': ('I have diabetes', Icons.bloodtype_rounded),
  'hearing': ('I do not hear well', Icons.hearing_disabled_rounded),
  'vision': ('I do not see well', Icons.visibility_off_rounded),
  'mobility': ('I need help walking', Icons.accessible_rounded),
  'quiet': ('I prefer a quiet seat', Icons.volume_off_rounded),
};

class SettingsScreen extends StatefulWidget {
  final Profile profile;
  final PassengerRepo repo;
  /// When the passenger is in the cabin, profile changes are sent to the crew straight away.
  final CabinSession? session;
  const SettingsScreen({super.key, required this.profile, required this.repo, this.session});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Profile get p => widget.profile;
  PassengerRepo get repo => widget.repo;
  String? message;
  bool saving = false;

  /// Saves the profile on the phone, applies the look at once, and sends it to the account if it can.
  Future<void> save() async {
    seniorMode.value = p.senior;
    calmMotion.value = p.calm;
    setState(() => saving = true);
    await p.save();
    widget.session?.link.updateProfile();
    var sent = false;
    if (repo.signedIn) sent = await repo.edit(preferencesFromProfile(p, repo.preferences));
    if (!mounted) return;
    setState(() {
      saving = false;
      message = !repo.signedIn ? 'Saved on this phone. Sign in under "Before you fly" to keep it in your account.' : (sent ? 'Saved to your account.' : 'Saved on this phone. It will be sent when there is a signal.');
    });
  }

  Future<void> syncNow() async {
    setState(() => saving = true);
    final ok = await repo.refresh();
    if (ok) {
      applyAccountToProfile(p, repo.preferences, repo.trip);
      seniorMode.value = p.senior;
      await p.save();
    }
    if (!mounted) return;
    setState(() {
      saving = false;
      message = ok ? 'Up to date with your account.' : 'No connection to the booking server. Your changes stay on this phone.';
    });
  }

  Future<void> signOut() async {
    await repo.signOut();
    if (!mounted) return;
    setState(() => message = 'Signed out. Your settings stay on this phone.');
  }

  @override
  Widget build(BuildContext context) {
    final others = p.needs.where((n) => !needOptions.containsKey(n)).toList();
    return WashiPage(
      title: 'My settings',
      kanji: '設定',
      children: [
        const SectionTitle('一', 'My language'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final x in languages) ChoiceChip(label: Text(x.name), selected: p.lang == x.code, onSelected: (_) { setState(() => p.lang = x.code); save(); }),
        ]),
        const SectionTitle('二', 'Make it easier to use'),
        PaperCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              title: const Text('Bigger text and buttons', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              subtitle: const Text('Easier to read and tap'),
              value: p.senior,
              onChanged: (v) { setState(() => p.senior = v); save(); },
            ),
            const Divider(height: 1),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              title: const Text('Calm screen', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              subtitle: const Text('No moving petals or flipping cards'),
              value: p.calm,
              onChanged: (v) { setState(() => p.calm = v); save(); },
            ),
          ]),
        ),
        const SectionTitle('三', 'What helps me'),
        PaperCard(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(children: [
            for (final e in needOptions.entries)
              CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                secondary: Icon(e.value.$2, color: ai),
                title: Text(e.value.$1, style: const TextStyle(fontSize: 17)),
                value: p.needs.contains(e.key),
                onChanged: (v) { setState(() => v == true ? p.needs.add(e.key) : p.needs.remove(e.key)); save(); },
              ),
            for (final o in others) ListTile(leading: const Icon(Icons.label_outline_rounded), title: Text(o)),
          ]),
        ),
        const SectionTitle('四', 'My account'),
        PaperCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(repo.signedIn ? Icons.verified_user_rounded : Icons.person_off_rounded, color: repo.signedIn ? good : warn),
              const SizedBox(width: 10),
              Expanded(child: Text(repo.signedIn ? 'Signed in. Your preferences are kept in your account.' : 'Not signed in. Your settings stay on this phone only.', style: const TextStyle(fontSize: 16))),
            ]),
            if (repo.hasPendingEdit) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Waiting for a signal to send your latest changes.', style: TextStyle(color: warn, fontWeight: FontWeight.w600))),
            if (p.seat.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Seat ${p.seat} (from your booking)', style: const TextStyle(fontSize: 16, color: sumiSoft))),
            const SizedBox(height: 12),
            Row(children: [
              if (repo.signedIn) Expanded(child: OutlinedButton.icon(onPressed: saving ? null : syncNow, icon: const Icon(Icons.sync_rounded), label: const Text('Sync now'))),
              if (repo.signedIn) const SizedBox(width: 10),
              if (repo.signedIn) Expanded(child: TextButton(onPressed: signOut, child: const Text('Sign out'))),
            ]),
          ]),
        ),
        if (message != null) Padding(padding: const EdgeInsets.only(top: 14), child: StatusBanner(icon: Icons.check_circle_rounded, color: good, title: 'Done', detail: message!, busy: saving)),
        const SizedBox(height: 10),
        const Text('Your name is never sent to the cabin. The crew only see your seat, language and what helps you.', style: TextStyle(fontSize: 14, color: sumiSoft, height: 1.35)),
      ],
    );
  }
}
