import 'package:flutter/material.dart';

import 'decks.dart';
import 'theme.dart';

/// The big picture tiles used for every deck: a coloured card, a round white icon, and the words below in the passenger's
/// own language. Large, high contrast and easy to hit, for older travellers.
class TileStyle {
  final Color tint;
  final Color edge;
  const TileStyle(this.tint, this.edge);
}

const _slate = TileStyle(Color(0xFFE9ECF5), Color(0xFFB4BCD6));
const _blue = TileStyle(Color(0xFFE4EBFF), Color(0xFF3B6FE0));
const _orange = TileStyle(Color(0xFFFFEFD2), Color(0xFFE69A1F));
const _green = TileStyle(Color(0xFFDDF3E8), Color(0xFF2FA06B));
const _lavender = TileStyle(Color(0xFFEEE9FB), Color(0xFF8E7CC3));
const _teal = TileStyle(Color(0xFFDDF1F5), Color(0xFF3AA0B5));
const _red = TileStyle(Color(0xFFFDE5E2), Color(0xFFD03C26));
const _pink = TileStyle(Color(0xFFFBE6EC), Color(0xFFD9647F));

/// Colour by meaning, so a group is recognised by colour as well as by its words and icon.
TileStyle tileStyleFor(Deck deck, String group) => switch ((deck, group)) {
      (Deck.flight, 'urgent') => _red,
      (Deck.flight, 'drink') => _blue,
      (Deck.flight, 'food') => _orange,
      (Deck.flight, 'comfort') => _slate,
      (Deck.flight, 'assist') => _green,
      (Deck.flight, 'seat') => _lavender,
      (Deck.flight, 'info') => _teal,
      (Deck.before, 'help') => _green,
      (Deck.before, 'seat') => _lavender,
      (Deck.before, 'meal') => _orange,
      (Deck.before, 'health') => _pink,
      (Deck.before, 'ask') => _blue,
      (Deck.staff, 'arrive') => _blue,
      (Deck.staff, 'go') => _teal,
      (Deck.staff, 'need') => _green,
      (Deck.staff, 'health') => _pink,
      (Deck.staff, 'lost') => _orange,
      (Deck.staff, 'polite') => _slate,
      _ => _slate,
    };

class CardTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final TileStyle style;
  final VoidCallback onTap;
  /// Shown above the label for urgent requests: words, not just colour.
  final String? badge;
  const CardTile({super.key, required this.icon, required this.label, required this.style, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.of(context).textScaler.scale(1);
    return Pressable(
      onTap: onTap,
      label: label,
      child: Container(
        constraints: BoxConstraints(minHeight: tileHeight * scale.clamp(1.0, 1.4)),
        padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
        decoration: BoxDecoration(
          color: style.tint,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: style.edge, width: 1.8),
          boxShadow: [BoxShadow(color: style.edge.withValues(alpha: 0.25), blurRadius: 0, offset: const Offset(0, 3))],
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 62,
            height: 62,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(icon, size: 34, color: aiDeep),
          ),
          const SizedBox(height: 10),
          if (badge != null) Padding(padding: const EdgeInsets.only(bottom: 3), child: Text(badge!, style: const TextStyle(color: shu, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: 0.8))),
          Text(label, textAlign: TextAlign.center, maxLines: 4, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: aiDeep, height: 1.25)),
        ]),
      ),
    );
  }
}

const tileHeight = 150.0;

/// Tiles two to a row. Laid out with Rows (not a scrolling grid) so it sits inside any page.
class TileGrid extends StatelessWidget {
  final List<Widget> tiles;
  const TileGrid({super.key, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 12),
        // IntrinsicHeight makes the two tiles in a row the same height, whichever has the longer words
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tiles[i]),
            const SizedBox(width: 12),
            Expanded(child: i + 1 < tiles.length ? tiles[i + 1] : const SizedBox()),
          ]),
        ),
      ));
    }
    return Column(children: rows);
  }
}
