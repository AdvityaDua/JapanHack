# Hushit Crew Tablet

Tablet-first cabin-crew dashboard based on the reference UI in `docs/CREW_TABLET_UI_SPEC.md`.

## Run the demo

Start the aircraft communication backend first:

```bash
cd ../communication_backend
../.venv/bin/python -m uvicorn app.main:app --host 0.0.0.0 --port 8001
```

Then run this Flutter app in Chrome:

```bash
cd crew_flutter
flutter pub get
flutter run -d chrome --web-port 5001
```

The dashboard starts with local demo data so the UI can be reviewed without a backend. Tap **Connect backend**, use `http://127.0.0.1:8001`, and enter the configured crew pairing code. The app then loads `/api/v1/crew/requests`, sends status updates through the backend, and listens for WebSocket events.

Use the laptop LAN IP from the tablet; `127.0.0.1` refers to the tablet itself. Cleartext HTTP is enabled for this local prototype and must be replaced with HTTPS before production deployment.
