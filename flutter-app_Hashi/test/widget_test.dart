import 'dart:io';

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/decks.dart';
import 'package:hashi_mobile/languages.dart';
import 'package:hashi_mobile/theme.dart';

final _japanese = RegExp(r'[぀-ヿ一-鿿]');

void main() {
  test('17 passenger languages', () => expect(languages.length, 17));

  group('decks', () {
    for (final deck in [(Deck.before, beforeCards, beforeGroups), (Deck.staff, staffCards, staffGroups)]) {
      test('${deck.$1.name}: every card has Japanese, English, a group that exists, and an icon', () {
        final groupIds = deck.$3.map((g) => g.id).toSet();
        for (final c in deck.$2) {
          expect(_japanese.hasMatch(c.ja), true, reason: '${c.id} has no Japanese');
          expect(c.en.trim().isNotEmpty, true, reason: c.id);
          expect(groupIds.contains(c.group), true, reason: '${c.id} has unknown group ${c.group}');
          expect(c.ja.endsWith('。') || c.ja.endsWith('い。') || c.ja.length < 8, true, reason: '${c.id} should end like a sentence');
        }
        expect(deck.$2.map((c) => c.id).toSet().length, deck.$2.length, reason: 'card ids must be unique');
        for (final g in deck.$3) {
          expect(deck.$2.any((c) => c.group == g.id), true, reason: 'group ${g.id} is empty');
        }
      });
    }

    test('the before-you-fly deck covers help, seat, meal and health for older travellers', () {
      final ids = beforeCards.map((c) => c.id).toSet();
      for (final must in ['b_wheelchair', 'b_walk_slow', 'b_aisle', 'b_near_toilet', 'b_veg', 'b_diabetic', 'b_medicine', 'b_pacemaker', 'b_hearing_aid', 'b_cane', 'b_poor_sight', 'b_forms']) {
        expect(ids, contains(must));
      }
    });

    test('the show-staff deck covers senior needs: rest, reading, hearing, medicine, family, interpreter', () {
      final ids = staffCards.map((c) => c.id).toSet();
      for (final must in ['s_wheelchair', 's_sit', 's_read', 's_loud', 's_medicine', 's_family', 's_interp', 's_slow', 's_doctor', 's_heart', 's_diabetes']) {
        expect(ids, contains(must));
      }
    });

    test('the flight deck is the 42 vetted requests, each with all 18 languages and a known group', () {
      final cards = parseFlightCards(File('assets/cards/flight.json').readAsStringSync());
      expect(cards.length, 42);
      final groupIds = flightGroups.map((g) => g.id).toSet();
      for (final c in cards) {
        expect(groupIds.contains(c.group), true, reason: '${c.id}: ${c.group}');
        expect(c.labels.length, greaterThanOrEqualTo(18), reason: c.id);
        for (final lang in [...languages.map((l) => l.code), 'ja']) {
          expect((c.labels[lang] ?? '').trim().isNotEmpty, true, reason: '${c.id} missing $lang');
        }
      }
      expect(cards.where((c) => c.urgency >= 3).length, 7, reason: 'urgent cards');
      expect(cards.every((c) => c.icon.codePoint != 0), true);
    });

    test('the bundled flight file matches the intents file it was exported from', () {
      final cards = parseFlightCards(File('assets/cards/flight.json').readAsStringSync());
      final yaml = File('../data/intents/intents.yaml').readAsStringSync();
      for (final c in cards) {
        expect(yaml.contains('id: ${c.id}'), true, reason: '${c.id} is not in intents.yaml');
      }
    });
  });

  group('look', () {
    test('text colours are readable on the paper (WCAG AA, 4.5:1)', () {
      for (final pair in {'sumi': sumi, 'sumiSoft': sumiSoft, 'ai': ai, 'aiDeep': aiDeep, 'shu': shu, 'matcha': matcha, 'warn': warn}.entries) {
        expect(contrastRatio(pair.value, washi), greaterThanOrEqualTo(4.5), reason: '${pair.key} on washi');
        expect(contrastRatio(pair.value, const Color.fromARGB(255, 255, 255, 255)), greaterThanOrEqualTo(4.5), reason: '${pair.key} on white');
      }
      expect(contrastRatio(const Color(0xFFFFFFFF), ai), greaterThanOrEqualTo(4.5), reason: 'white on indigo buttons');
      expect(contrastRatio(const Color(0xFFFFFFFF), shuBright), greaterThanOrEqualTo(4.5), reason: 'white on the red send button');
      expect(contrastRatio(aiDeep, kin), greaterThanOrEqualTo(4.5), reason: 'dark text on the gold play button');
    });
  });
}
