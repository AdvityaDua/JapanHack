# HASHI passenger app: local backend demo

The offline speech, translation, OCR, cards, and TTS layers remain on-device.
The backend integration transports pairing, requests, statuses, messages, and
announcements. Passenger cancellations, acknowledgements, check-in answers,
profile changes, and conversation actions also use the backend HTTP/event
protocol; the connected app does not send those actions as legacy socket
commands.

Start the communication backend first:

```bash
cd communication_backend
uv run --with fastapi --with uvicorn --with paho-mqtt --with websockets \
  uvicorn app.main:app --host 0.0.0.0 --port 8001
```

For an Android phone connected with ADB, forward both backend ports:

```bash
adb reverse tcp:8001 tcp:8001
adb reverse tcp:8100 tcp:8100
```

The mobile app can then use `127.0.0.1` because Android maps that address
through the reverse tunnel to the development computer.

Run the passenger app on the Android device:

```bash
cd flutter-app_Hashi
flutter run \
  --dart-define=CABIN_BACKEND_URL=http://127.0.0.1:8001 \
  --dart-define=CENTRAL_BACKEND_URL=http://127.0.0.1:8100
```

The app defaults now also point to these localhost ports, so the
`--dart-define` values are optional for the ADB demo.

The passenger must have a confirmed seat in the account flow. Once the app
finds the cabin backend, it pairs the passenger device automatically. A card
or help request is posted to the backend, appears in the crew queue, and crew
status changes are delivered back over the authenticated WebSocket.
