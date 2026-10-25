# HASHI 橋 · passenger app

*Don't translate. Understand.*

The Android app for passengers flying between India and Japan. It keeps working with no connection: the screens, the
picture cards and the translation models all live on the phone.

## What it does

The app follows the journey in three stages:

| Stage | What is inside |
| --- | --- |
| **Before flight** (出発前) | Booking and seat from the passenger's account, preferences, language kit download, airport cards (wheelchair, seat, meal, health, questions) |
| **In flight** (機内) | Finds the cabin network by itself, boards with the seat from the booking, live line to the crew: picture requests, the crew's replies as picture, words and sound, announcements, exit-row check, crew check-in, written conversation, big help button |
| **After flight** (到着後) | Read a sign with the camera, cards to show staff |

**Speak & translate** is in every stage: the passenger talks in their own language and the other person hears Japanese,
and the other way round, with the translation appearing while the person is still speaking.

Every deck uses large picture tiles in the passenger's own language, with a bigger-text mode and a calm-screen mode for
older travellers.

## Status

Working and tested on a phone: the three stages, the cards, the live cabin link with reconnect, settings and account
sync, on-device translation for 13 languages (Google ML Kit).

In progress: our own on-device speech models (see below) are written and measured, and are being wired into the Speak
screen. Punjabi, Malayalam, Khmer and Burmese translation needs the NLLB model, which is not in the app yet.

Not yet tested on real devices: other phones than the one used in development, real cabin noise, real passenger
accents. The speech numbers below come from synthetic voices and are a best case.

## Models and libraries

Speech (runs on the phone through [sherpa-onnx](https://github.com/k2-fsa/sherpa-onnx), downloaded once on Wi-Fi):

| Model | Used for | Size |
| --- | --- | --- |
| Meta Omnilingual ASR 300M CTC, int8 | Hindi, Punjabi, Tamil and the other Indian and Southeast Asian languages | 365 MB |
| OpenAI Whisper tiny, int8 | Japanese (the crew) and English | 103 MB |
| Silero VAD | finds where a sentence starts and ends | 0.6 MB |

Translation (on the phone): Google ML Kit on-device translation (about 30 MB per language, 13 languages).

Measured on a OnePlus Nord CE (Android 13, 7.5 GB RAM), character error rate on 34 synthetic clips, clean / with 10 dB
cabin-style noise (lower is better):

| Model | Hindi | Punjabi | Tamil | Japanese | English | Time for a 3 s clip |
| --- | --- | --- | --- | --- | --- | --- |
| Whisper tiny | 1.07 / 1.12 | 1.04 / 1.05 | 0.54 / 0.52 | 0.08 / 0.14 | 0.00 / 0.00 | 0.5 s |
| Whisper base | 1.06 / 1.11 | 1.02 / 1.11 | 0.47 / 0.50 | 0.18 / 0.18 | 0.00 / 0.00 | 1.0 s |
| Whisper small | 0.55 / 0.51 | 1.00 / 1.00 | 0.52 / 0.52 | 0.01 / 0.04 | 0.00 / 0.00 | 3.8 s |
| Omnilingual 300M | 0.01 / 0.31 | 0.27 / 0.42 | 0.05 / 0.12 | 0.17 / 0.16 | 0.00 / 0.10 | 1.0 s |

The phone's built-in offline recogniser had no packs for Japanese, Hindi or English and does not support Punjabi, which is
why the app carries its own models. Re-run the measurements with `scripts/make_asr_testset.py` and the benchmark in
`lib/asrbench.dart` (see below).

## Run it

```bash
flutter pub get
flutter test
flutter build apk --release
```

The cabin wording (requests, replies, announcements, interface words in 17 languages) and the recorded replies are bundled
from the project's intent data:

```bash
python scripts/export_cards.py      # from the main HASHI repository
node scripts/export_ui.mjs
```

Test builds (they print a report to `adb logcat -s flutter`):

```bash
flutter build apk --release --dart-define=SELFTEST=true   # translation and speech checks
flutter build apk --release --dart-define=SELFTEST=asr    # speech model benchmark
```

## Layout

```
lib/
  main.dart            home: the three stages
  hubs.dart            before / after flight screens
  inflight.dart        in-flight screen, requests and replies
  cabin_link.dart      live line to the cabin server (reconnect, queue)
  protocol.dart        what the cabin sends, kept in one store
  discover.dart        finds the cabin network, boards with the booking pass
  central.dart         booking, preferences, boarding pass (cloud backend)
  repo.dart            offline cache and preference sync
  decks.dart, cards.dart, tiles.dart   the card decks and the tile style
  translate_screen.dart, conversation.dart, engines.dart   speak and translate
  models.dart, asr_worker.dart, asr_engine.dart            on-device speech models
  theme.dart           colours, type and motion in one place
test/                  unit and widget tests
assets/                bundled wording, recordings
```
