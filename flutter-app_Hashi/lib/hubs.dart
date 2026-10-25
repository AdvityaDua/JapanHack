import 'package:flutter/material.dart';

import 'cards.dart';
import 'decks.dart';
import 'kit.dart';
import 'preflight.dart';
import 'repo.dart';
import 'session.dart';
import 'settings.dart';
import 'sign.dart';
import 'theme.dart';
import 'tiles.dart';
import 'translate_screen.dart';

/// The big "Speak and translate" button. It is the first thing in every stage of the journey.
class SpeakBar extends StatelessWidget {
  final String lang;
  final CabinSession? session;
  const SpeakBar({super.key, required this.lang, this.session});

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'Speak and translate',
    child: SizedBox(
      height: 84,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: aiDeep,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
        ),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TranslateScreen(lang: lang, session: session),
          ),
        ),
        icon: const Icon(Icons.mic_rounded, size: 34, color: kin),
        label: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Speak & translate',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            Text('話す · 通訳', style: TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

/// A tile for a group of cards; it opens the deck already filtered to that group.
CardTile groupTile(
  BuildContext context,
  Deck deck,
  CardGroup g,
  Profile p, {
  CabinSession? session,
}) => CardTile(
  icon: g.icon,
  label: '${g.en}\n${g.ja}',
  style: tileStyleFor(deck, g.id),
  onTap: () => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => DeckScreen(
        deck: deck,
        profile: p,
        initialGroup: g.id,
        session: session,
      ),
    ),
  ),
);

/// Before the flight: speak, my booking and settings, and cards for the desk, security and the gate.
class BeforeHub extends StatelessWidget {
  final Profile profile;
  final PassengerRepo repo;
  const BeforeHub({super.key, required this.profile, required this.repo});

  @override
  Widget build(BuildContext context) => WashiPage(
    title: 'Before flight',
    kanji: '出発前',
    children: [
      SpeakBar(lang: profile.lang),
      const SizedBox(height: 16),
      TileGrid(
        tiles: [
          CardTile(
            icon: Icons.event_available_rounded,
            label: 'My booking\nand language kit',
            style: tileStyleFor(Deck.flight, 'info'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PreflightScreen(profile: profile, repo: repo),
              ),
            ),
          ),
          CardTile(
            icon: Icons.tune_rounded,
            label: 'My settings',
            style: tileStyleFor(Deck.flight, 'seat'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(profile: profile, repo: repo),
              ),
            ),
          ),
        ],
      ),
      const SectionTitle('一', 'Show at the airport'),
      TileGrid(
        tiles: [
          for (final g in beforeGroups)
            groupTile(context, Deck.before, g, profile),
        ],
      ),
    ],
  );
}

/// After landing: speak, read a sign with the camera, and cards for staff.
class AfterHub extends StatelessWidget {
  final Profile profile;
  const AfterHub({super.key, required this.profile});

  @override
  Widget build(BuildContext context) => WashiPage(
    title: 'After flight',
    kanji: '到着後',
    children: [
      SpeakBar(lang: profile.lang),
      const SizedBox(height: 16),
      TileGrid(
        tiles: [
          CardTile(
            icon: Icons.photo_camera_rounded,
            label: 'Read a sign\n標識を翻訳',
            style: tileStyleFor(Deck.staff, 'go'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => SignScreen(profile: profile)),
            ),
          ),
          CardTile(
            icon: Icons.record_voice_over_rounded,
            label: 'All cards for staff',
            style: tileStyleFor(Deck.staff, 'need'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DeckScreen(deck: Deck.staff, profile: profile),
              ),
            ),
          ),
        ],
      ),
      const SectionTitle('一', 'Show to staff'),
      TileGrid(
        tiles: [
          for (final g in staffGroups)
            groupTile(context, Deck.staff, g, profile),
        ],
      ),
    ],
  );
}
