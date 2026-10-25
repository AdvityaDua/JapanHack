import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

/// The three card decks. A card shows Japanese large (for crew or staff), English below, and the passenger's own language
/// (on-device translation, or the bundled label for flight cards).

enum Deck { before, flight, staff }

class CardGroup {
  final String id;
  final String en;
  final String ja;
  final IconData icon;
  const CardGroup(this.id, this.en, this.ja, this.icon);
}

class HashiCard {
  final String id;
  final String group;
  final String ja;
  final String en;
  final IconData icon;
  /// 1 normal, 2 soon, 3 urgent (flight deck only).
  final int urgency;
  /// Ready-made labels by language code (flight deck). Other decks are translated on the phone.
  final Map<String, String> labels;
  const HashiCard({required this.id, required this.group, required this.ja, required this.en, required this.icon, this.urgency = 1, this.labels = const {}});
}

// ---- Before you fly: at the airport desk, security and the gate ----

const beforeGroups = <CardGroup>[
  CardGroup('help', 'Help at the airport', '空港での手助け', Icons.accessibility_new_rounded),
  CardGroup('seat', 'My seat', 'お席のご希望', Icons.event_seat_rounded),
  CardGroup('meal', 'My meal', 'お食事', Icons.restaurant_rounded),
  CardGroup('health', 'My health', '健康のこと', Icons.favorite_rounded),
  CardGroup('ask', 'Questions', 'おたずね', Icons.help_outline_rounded),
];

const beforeCards = <HashiCard>[
  HashiCard(id: 'b_wheelchair', group: 'help', ja: '空港で車いすをお願いします。', en: 'I need a wheelchair at the airport.', icon: Icons.accessible_rounded),
  HashiCard(id: 'b_escort', group: 'help', ja: '搭乗口まで案内をお願いします。', en: 'Please guide me to my gate.', icon: Icons.directions_walk_rounded),
  HashiCard(id: 'b_priority', group: 'help', ja: '優先搭乗をお願いします。', en: 'I would like priority boarding.', icon: Icons.airplane_ticket_rounded),
  HashiCard(id: 'b_walk_slow', group: 'help', ja: 'ゆっくりしか歩けません。', en: 'I can only walk slowly.', icon: Icons.elderly_rounded),
  HashiCard(id: 'b_bags', group: 'help', ja: '荷物を運ぶのを手伝ってください。', en: 'Please help me with my bags.', icon: Icons.luggage_rounded),
  HashiCard(id: 'b_security', group: 'help', ja: '手荷物検査で手伝ってください。', en: 'Please help me at the security check.', icon: Icons.security_rounded),
  HashiCard(id: 'b_forms', group: 'help', ja: '書類の記入を手伝ってください。', en: 'Please help me fill in the forms.', icon: Icons.edit_note_rounded),
  HashiCard(id: 'b_aisle', group: 'seat', ja: '通路側の席をお願いします。', en: 'I would like an aisle seat.', icon: Icons.airline_seat_recline_normal_rounded),
  HashiCard(id: 'b_near_toilet', group: 'seat', ja: 'お手洗いに近い席をお願いします。', en: 'I would like a seat near the toilet.', icon: Icons.wc_rounded),
  HashiCard(id: 'b_legroom', group: 'seat', ja: '足元が広い席をお願いします。', en: 'I would like a seat with more legroom.', icon: Icons.airline_seat_legroom_extra_rounded),
  HashiCard(id: 'b_family_seat', group: 'seat', ja: '家族の隣の席にしてください。', en: 'Please seat me next to my family.', icon: Icons.family_restroom_rounded),
  HashiCard(id: 'b_infant', group: 'seat', ja: '赤ちゃんと一緒に旅行します。', en: 'I am travelling with a baby.', icon: Icons.child_friendly_rounded),
  HashiCard(id: 'b_veg', group: 'meal', ja: 'ベジタリアンの機内食をお願いします。', en: 'I would like a vegetarian meal.', icon: Icons.eco_rounded),
  HashiCard(id: 'b_no_beef', group: 'meal', ja: '牛肉は食べられません。', en: 'I do not eat beef.', icon: Icons.no_food_rounded),
  HashiCard(id: 'b_no_pork', group: 'meal', ja: '豚肉は食べられません。', en: 'I do not eat pork.', icon: Icons.no_meals_rounded),
  HashiCard(id: 'b_allergy', group: 'meal', ja: '食べ物のアレルギーがあります。', en: 'I have a food allergy.', icon: Icons.warning_amber_rounded),
  HashiCard(id: 'b_diabetic', group: 'meal', ja: '糖尿病のため、食事に気をつけています。', en: 'I have diabetes and must be careful with food.', icon: Icons.bloodtype_rounded),
  HashiCard(id: 'b_soft', group: 'meal', ja: 'やわらかい食事をお願いします。', en: 'I would like soft food.', icon: Icons.soup_kitchen_rounded),
  HashiCard(id: 'b_medicine', group: 'health', ja: '毎日飲む薬を持っています。', en: 'I carry medicine that I take every day.', icon: Icons.medication_rounded),
  HashiCard(id: 'b_pacemaker', group: 'health', ja: 'ペースメーカーを使っています。', en: 'I have a pacemaker.', icon: Icons.monitor_heart_rounded),
  HashiCard(id: 'b_hearing_aid', group: 'health', ja: '補聴器を使っています。', en: 'I use a hearing aid.', icon: Icons.hearing_rounded),
  HashiCard(id: 'b_cane', group: 'health', ja: '杖を使っています。', en: 'I use a walking stick.', icon: Icons.assist_walker_rounded),
  HashiCard(id: 'b_poor_sight', group: 'health', ja: '目が見えにくいです。', en: 'I cannot see well.', icon: Icons.visibility_off_rounded),
  HashiCard(id: 'b_checkin', group: 'ask', ja: 'チェックインカウンターはどこですか。', en: 'Where is the check-in counter?', icon: Icons.how_to_reg_rounded),
  HashiCard(id: 'b_gate', group: 'ask', ja: '搭乗口はどこですか。', en: 'Where is my boarding gate?', icon: Icons.meeting_room_rounded),
  HashiCard(id: 'b_boarding_time', group: 'ask', ja: '搭乗は何時ですか。', en: 'What time is boarding?', icon: Icons.schedule_rounded),
  HashiCard(id: 'b_on_time', group: 'ask', ja: 'この便は定刻ですか。', en: 'Is this flight on time?', icon: Icons.flight_takeoff_rounded),
  HashiCard(id: 'b_connection', group: 'ask', ja: '乗り継ぎ便に間に合いますか。', en: 'Will I make my connecting flight?', icon: Icons.transfer_within_a_station_rounded),
  HashiCard(id: 'b_slow', group: 'ask', ja: 'ゆっくり話してください。', en: 'Please speak slowly.', icon: Icons.slow_motion_video_rounded),
  HashiCard(id: 'b_write', group: 'ask', ja: '書いていただけますか。', en: 'Please write it down.', icon: Icons.draw_rounded),
  HashiCard(id: 'b_no_japanese', group: 'ask', ja: '日本語が話せません。', en: 'I do not speak Japanese.', icon: Icons.translate_rounded),
];

// ---- After landing: show staff ----

const staffGroups = <CardGroup>[
  CardGroup('arrive', 'Arriving', '到着', Icons.flight_land_rounded),
  CardGroup('go', 'Getting around', '移動', Icons.train_rounded),
  CardGroup('need', 'What I need', 'お願い', Icons.volunteer_activism_rounded),
  CardGroup('health', 'Health', '体調', Icons.health_and_safety_rounded),
  CardGroup('lost', 'Lost something', '落とし物', Icons.search_rounded),
  CardGroup('polite', 'Polite words', 'ことば', Icons.chat_bubble_outline_rounded),
];

const staffCards = <HashiCard>[
  HashiCard(id: 's_immigration', group: 'arrive', ja: '入国審査はどこですか。', en: 'Where is the immigration counter?', icon: Icons.badge_rounded),
  HashiCard(id: 's_baggage', group: 'arrive', ja: '荷物の受け取りはどこですか。', en: 'Where do I collect my baggage?', icon: Icons.luggage_rounded),
  HashiCard(id: 's_transfer', group: 'arrive', ja: '乗り継ぎカウンターはどこですか。', en: 'Where is the transfer counter?', icon: Icons.transfer_within_a_station_rounded),
  HashiCard(id: 's_exit', group: 'arrive', ja: '出口はどこですか。', en: 'Where is the exit?', icon: Icons.exit_to_app_rounded),
  HashiCard(id: 's_info', group: 'arrive', ja: '案内所はどこですか。', en: 'Where is the information desk?', icon: Icons.info_outline_rounded),
  HashiCard(id: 's_toilet', group: 'arrive', ja: 'お手洗いはどこですか。', en: 'Where is the toilet?', icon: Icons.wc_rounded),
  HashiCard(id: 's_train_bus', group: 'go', ja: '電車やバスで市内へ行くにはどうすればいいですか。', en: 'How do I get to the city by train or bus?', icon: Icons.directions_transit_rounded),
  HashiCard(id: 's_taxi', group: 'go', ja: 'タクシー乗り場はどこですか。', en: 'Where is the taxi stand?', icon: Icons.local_taxi_rounded),
  HashiCard(id: 's_address', group: 'go', ja: 'この住所まで行きたいです。', en: 'I want to go to this address.', icon: Icons.place_rounded),
  HashiCard(id: 's_ticket', group: 'go', ja: '切符の買い方を教えてください。', en: 'Please show me how to buy a ticket.', icon: Icons.confirmation_number_rounded),
  HashiCard(id: 's_sim', group: 'go', ja: 'SIMカードやWi-Fiはどこで買えますか。', en: 'Where can I buy a SIM card or Wi-Fi?', icon: Icons.sim_card_rounded),
  HashiCard(id: 's_atm', group: 'go', ja: '両替所かATMはどこですか。', en: 'Where is the currency exchange or an ATM?', icon: Icons.currency_exchange_rounded),
  HashiCard(id: 's_wheelchair', group: 'need', ja: '車いすをお願いします。', en: 'I need a wheelchair.', icon: Icons.accessible_rounded),
  HashiCard(id: 's_sit', group: 'need', ja: '座って休みたいです。', en: 'I need to sit down and rest.', icon: Icons.chair_alt_rounded),
  HashiCard(id: 's_bags', group: 'need', ja: '荷物を運ぶのを手伝ってください。', en: 'Please help me carry my bags.', icon: Icons.luggage_rounded),
  HashiCard(id: 's_water', group: 'need', ja: 'お水をください。', en: 'I need water.', icon: Icons.water_drop_rounded),
  HashiCard(id: 's_read', group: 'need', ja: '目が見えにくいので、読んでいただけますか。', en: 'I cannot see well. Could you read this for me?', icon: Icons.visibility_off_rounded),
  HashiCard(id: 's_loud', group: 'need', ja: '耳が遠いので、大きな声でお願いします。', en: 'I am hard of hearing. Please speak louder.', icon: Icons.hearing_rounded),
  HashiCard(id: 's_family', group: 'need', ja: '家族に連絡したいです。電話を貸していただけますか。', en: 'I want to contact my family. May I use a phone?', icon: Icons.phone_in_talk_rounded),
  HashiCard(id: 's_interp', group: 'need', ja: 'ヒンディー語かパンジャブ語の通訳をお願いします。', en: 'I need a Hindi or Punjabi interpreter.', icon: Icons.record_voice_over_rounded),
  HashiCard(id: 's_doctor', group: 'health', ja: '医者を呼んでください。', en: 'Please call a doctor.', icon: Icons.medical_services_rounded),
  HashiCard(id: 's_unwell', group: 'health', ja: '気分が悪いです。', en: 'I feel unwell.', icon: Icons.sick_rounded),
  HashiCard(id: 's_medicine', group: 'health', ja: '薬を飲みたいので、お水をください。', en: 'I need to take my medicine. Water, please.', icon: Icons.medication_rounded),
  HashiCard(id: 's_pharmacy', group: 'health', ja: '薬局はどこですか。', en: 'Where is a pharmacy?', icon: Icons.local_pharmacy_rounded),
  HashiCard(id: 's_heart', group: 'health', ja: '心臓が悪いです。', en: 'I have a heart condition.', icon: Icons.monitor_heart_rounded),
  HashiCard(id: 's_diabetes', group: 'health', ja: '糖尿病があります。', en: 'I have diabetes.', icon: Icons.bloodtype_rounded),
  HashiCard(id: 's_lost_bag', group: 'lost', ja: '荷物をなくしました。', en: 'I lost my bag.', icon: Icons.work_off_rounded),
  HashiCard(id: 's_no_bag', group: 'lost', ja: '私の荷物が出てきません。', en: 'My bag has not come out.', icon: Icons.luggage_rounded),
  HashiCard(id: 's_passport', group: 'lost', ja: 'パスポートをなくしました。', en: 'I lost my passport.', icon: Icons.contact_page_rounded),
  HashiCard(id: 's_phone', group: 'lost', ja: '携帯電話をなくしました。', en: 'I lost my phone.', icon: Icons.phonelink_erase_rounded),
  HashiCard(id: 's_slow', group: 'polite', ja: 'ゆっくり話してください。', en: 'Please speak slowly.', icon: Icons.slow_motion_video_rounded),
  HashiCard(id: 's_write', group: 'polite', ja: '書いていただけますか。', en: 'Please write it down.', icon: Icons.draw_rounded),
  HashiCard(id: 's_no_japanese', group: 'polite', ja: '日本語が話せません。', en: 'I do not speak Japanese.', icon: Icons.translate_rounded),
  HashiCard(id: 's_yes', group: 'polite', ja: 'はい。', en: 'Yes.', icon: Icons.check_circle_outline_rounded),
  HashiCard(id: 's_no', group: 'polite', ja: 'いいえ。', en: 'No.', icon: Icons.highlight_off_rounded),
  HashiCard(id: 's_sorry', group: 'polite', ja: 'すみません。', en: 'Excuse me. / Sorry.', icon: Icons.waving_hand_rounded),
  HashiCard(id: 's_thanks', group: 'polite', ja: 'ありがとうございます。', en: 'Thank you.', icon: Icons.favorite_border_rounded),
];

// ---- On the flight: the vetted cabin requests (bundled file made by scripts/export_cards.py) ----

const flightGroups = <CardGroup>[
  CardGroup('urgent', 'Urgent help', '緊急', Icons.emergency_rounded),
  CardGroup('drink', 'Drinks', 'お飲み物', Icons.local_drink_rounded),
  CardGroup('food', 'Meals', 'お食事', Icons.restaurant_rounded),
  CardGroup('comfort', 'Comfort', '快適に', Icons.bedtime_rounded),
  CardGroup('assist', 'Assistance', 'お手伝い', Icons.volunteer_activism_rounded),
  CardGroup('seat', 'My seat', 'お席', Icons.event_seat_rounded),
  CardGroup('info', 'Information', 'ご案内', Icons.info_outline_rounded),
];

/// The vetted request names map to Material icons here (the web app uses Lucide names).
const _icons = <String, IconData>{
  'GlassWater': Icons.water_drop_rounded, 'Coffee': Icons.coffee_rounded, 'CupSoda': Icons.local_drink_rounded, 'Utensils': Icons.restaurant_rounded,
  'Salad': Icons.eco_rounded, 'ShieldAlert': Icons.shield_rounded, 'Clock': Icons.schedule_rounded, 'Timer': Icons.timer_rounded,
  'BedDouble': Icons.bed_rounded, 'BedSingle': Icons.single_bed_rounded, 'Snowflake': Icons.ac_unit_rounded, 'Sun': Icons.wb_sunny_rounded,
  'Lightbulb': Icons.lightbulb_rounded, 'LightbulbOff': Icons.lightbulb_outline_rounded, 'Toilet': Icons.wc_rounded, 'Pill': Icons.medication_rounded,
  'Headphones': Icons.headphones_rounded, 'MonitorPlay': Icons.live_tv_rounded, 'BatteryCharging': Icons.battery_charging_full_rounded,
  'Armchair': Icons.event_seat_rounded, 'ArrowLeftRight': Icons.swap_horiz_rounded, 'UsersRound': Icons.groups_rounded, 'Luggage': Icons.luggage_rounded,
  'Link2': Icons.link_rounded, 'FileText': Icons.description_rounded, 'PlaneLanding': Icons.flight_land_rounded, 'Route': Icons.route_rounded,
  'Languages': Icons.translate_rounded, 'EarOff': Icons.hearing_disabled_rounded, 'Accessibility': Icons.accessible_rounded, 'Baby': Icons.child_friendly_rounded,
  'Search': Icons.search_rounded, 'Undo2': Icons.undo_rounded, 'Smile': Icons.sentiment_satisfied_alt_rounded, 'TriangleAlert': Icons.warning_amber_rounded,
  'HeartPulse': Icons.monitor_heart_rounded, 'Wind': Icons.air_rounded, 'Orbit': Icons.sync_rounded, 'Bandage': Icons.healing_rounded,
  'Flame': Icons.local_fire_department_rounded, 'HandHelping': Icons.pan_tool_rounded,
  // crew replies and announcements
  'Check': Icons.check_circle_rounded, 'CircleSlash': Icons.block_rounded, 'ClipboardCheck': Icons.fact_check_rounded, 'DoorOpen': Icons.door_front_door_rounded,
  'Footprints': Icons.directions_walk_rounded, 'GalleryHorizontal': Icons.view_carousel_rounded, 'HandPlatter': Icons.room_service_rounded,
  'Hourglass': Icons.hourglass_top_rounded, 'ImagePlay': Icons.slideshow_rounded, 'Megaphone': Icons.campaign_rounded, 'ScanSearch': Icons.search_rounded,
  'ShieldCheck': Icons.verified_user_rounded, 'Siren': Icons.notification_important_rounded, 'SmartphoneNfc': Icons.phone_android_rounded,
  'Waves': Icons.waves_rounded, 'X': Icons.close_rounded,
};

IconData flightIcon(String lucideName) => _icons[lucideName] ?? Icons.help_outline_rounded;

List<HashiCard> parseFlightCards(String json) {
  final list = (jsonDecode(json)['cards'] as List).cast<Map<String, dynamic>>();
  return [
    for (final c in list)
      HashiCard(
        id: c['id'] as String,
        group: c['cat'] as String,
        ja: (c['labels'] as Map)['ja'] as String,
        en: (c['labels'] as Map)['en'] as String,
        icon: flightIcon(c['icon'] as String),
        urgency: c['urgency'] as int,
        labels: {for (final e in (c['labels'] as Map).entries) e.key as String: e.value as String},
      ),
  ];
}

Future<List<HashiCard>> loadFlightCards([AssetBundle? bundle]) async => parseFlightCards(await (bundle ?? rootBundle).loadString('assets/cards/flight.json'));

List<CardGroup> groupsFor(Deck d) => switch (d) { Deck.before => beforeGroups, Deck.flight => flightGroups, Deck.staff => staffGroups };

Future<List<HashiCard>> cardsFor(Deck d, [AssetBundle? bundle]) async => switch (d) { Deck.before => beforeCards, Deck.flight => await loadFlightCards(bundle), Deck.staff => staffCards };
