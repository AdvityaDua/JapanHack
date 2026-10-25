import json
import sqlite3
from pathlib import Path
from threading import Lock

from app.config import settings


class Store:
    def __init__(self, path: str) -> None:
        Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.path = path
        self.lock = Lock()

    def connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(self.path, check_same_thread=False)
        conn.row_factory = sqlite3.Row
        conn.execute("PRAGMA journal_mode=WAL")
        conn.execute("PRAGMA foreign_keys=ON")
        return conn

    def init(self) -> None:
        with self.lock, self.connect() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS flight_sessions (
                    id TEXT PRIMARY KEY, flight_number TEXT NOT NULL,
                    aircraft_identifier TEXT NOT NULL, status TEXT NOT NULL,
                    started_at TEXT NOT NULL, ended_at TEXT
                );
                CREATE TABLE IF NOT EXISTS devices (
                    id TEXT PRIMARY KEY, flight_id TEXT NOT NULL,
                    device_type TEXT NOT NULL, display_name TEXT,
                    seat_number TEXT, seat_token TEXT, token_hash TEXT NOT NULL,
                    status TEXT NOT NULL, last_seen_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS communication_requests (
                    id TEXT PRIMARY KEY, flight_id TEXT NOT NULL,
                    passenger_device_id TEXT NOT NULL, seat_token TEXT NOT NULL,
                    seat_number TEXT,
                    passenger_language TEXT NOT NULL DEFAULT 'English',
                    category TEXT NOT NULL, message TEXT, urgency TEXT NOT NULL,
                    status TEXT NOT NULL, assigned_crew_device_id TEXT,
                    created_at TEXT NOT NULL, updated_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS flight_seats (
                    flight_id TEXT NOT NULL,
                    seat_number TEXT NOT NULL,
                    row_number INTEGER NOT NULL,
                    seat_column TEXT NOT NULL,
                    seat_order INTEGER NOT NULL,
                    cabin_class TEXT NOT NULL,
                    seat_type TEXT NOT NULL,
                    occupancy_status TEXT NOT NULL DEFAULT 'available',
                    PRIMARY KEY (flight_id, seat_number)
                );
                CREATE TABLE IF NOT EXISTS request_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE NOT NULL,
                    request_id TEXT NOT NULL, flight_id TEXT NOT NULL,
                    event_type TEXT NOT NULL, actor_device_id TEXT,
                    payload TEXT NOT NULL, occurred_at TEXT NOT NULL,
                    sequence INTEGER NOT NULL
                );
                CREATE TABLE IF NOT EXISTS inbox_messages (
                    event_id TEXT PRIMARY KEY, topic TEXT NOT NULL,
                    status TEXT NOT NULL, processed_at TEXT, error_message TEXT
                );
                CREATE TABLE IF NOT EXISTS outbox_messages (
                    id INTEGER PRIMARY KEY AUTOINCREMENT, event_id TEXT UNIQUE NOT NULL,
                    topic TEXT NOT NULL, payload TEXT NOT NULL, qos INTEGER NOT NULL,
                    published_at TEXT, attempt_count INTEGER NOT NULL DEFAULT 0,
                    last_error TEXT, created_at TEXT NOT NULL
                );
                CREATE TABLE IF NOT EXISTS idempotency_keys (
                    scope TEXT NOT NULL, idempotency_key TEXT NOT NULL,
                    response_json TEXT NOT NULL, created_at TEXT NOT NULL,
                    PRIMARY KEY(scope, idempotency_key)
                );
                """
            )
            columns = {row[1] for row in conn.execute("PRAGMA table_info(communication_requests)")}
            if "seat_number" not in columns:
                conn.execute("ALTER TABLE communication_requests ADD COLUMN seat_number TEXT")
            if "passenger_language" not in columns:
                conn.execute("ALTER TABLE communication_requests ADD COLUMN passenger_language TEXT NOT NULL DEFAULT 'English'")

    def seed_session(self, session: dict) -> None:
        with self.lock, self.connect() as conn:
            conn.execute("INSERT OR IGNORE INTO flight_sessions VALUES (?, ?, ?, ?, ?, NULL)", (session["id"], session["flight_number"], session["aircraft_identifier"], session["status"], session["started_at"]))

    def get_session(self, flight_id: str) -> sqlite3.Row | None:
        with self.connect() as conn:
            return conn.execute("SELECT * FROM flight_sessions WHERE id = ?", (flight_id,)).fetchone()

    def save_device(self, data: dict) -> None:
        with self.lock, self.connect() as conn:
            conn.execute("INSERT INTO devices VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)", tuple(data.values()))

    def get_device(self, device_id: str) -> sqlite3.Row | None:
        with self.connect() as conn:
            return conn.execute("SELECT * FROM devices WHERE id = ?", (device_id,)).fetchone()

    def save_idempotent(self, scope: str, key: str, response: dict, created_at: str) -> bool:
        with self.lock, self.connect() as conn:
            try:
                conn.execute("INSERT INTO idempotency_keys VALUES (?, ?, ?, ?)", (scope, key, json.dumps(response), created_at))
                return True
            except sqlite3.IntegrityError:
                return False

    def get_idempotent(self, scope: str, key: str) -> dict | None:
        with self.connect() as conn:
            row = conn.execute("SELECT response_json FROM idempotency_keys WHERE scope = ? AND idempotency_key = ?", (scope, key)).fetchone()
            return json.loads(row["response_json"]) if row else None

    def create_request(self, request: dict, event: dict, topic: str, created_at: str) -> None:
        with self.lock, self.connect() as conn:
            conn.execute("INSERT INTO communication_requests (id, flight_id, passenger_device_id, seat_token, seat_number, passenger_language, category, message, urgency, status, assigned_crew_device_id, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", tuple(request[field] for field in ("id", "flight_id", "passenger_device_id", "seat_token", "seat_number", "passenger_language", "category", "message", "urgency", "status", "assigned_crew_device_id", "created_at", "updated_at")))
            self._append_event(conn, event, topic, created_at)

    def get_request(self, request_id: str) -> sqlite3.Row | None:
        with self.connect() as conn:
            return conn.execute("SELECT * FROM communication_requests WHERE id = ?", (request_id,)).fetchone()

    def list_requests(self, flight_id: str, statuses: list[str] | None = None) -> list[sqlite3.Row]:
        with self.connect() as conn:
            if statuses:
                marks = ",".join("?" for _ in statuses)
                return conn.execute(f"SELECT * FROM communication_requests WHERE flight_id = ? AND status IN ({marks}) ORDER BY created_at ASC", [flight_id, *statuses]).fetchall()
            return conn.execute("SELECT * FROM communication_requests WHERE flight_id = ? ORDER BY created_at ASC", (flight_id,)).fetchall()

    def save_seat(self, seat: dict) -> None:
        with self.lock, self.connect() as conn:
            conn.execute(
                """INSERT OR IGNORE INTO flight_seats
                (flight_id, seat_number, row_number, seat_column, seat_order,
                 cabin_class, seat_type, occupancy_status)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                tuple(seat[field] for field in (
                    "flight_id", "seat_number", "row_number", "seat_column",
                    "seat_order", "cabin_class", "seat_type", "occupancy_status",
                )),
            )

    def list_seats(self, flight_id: str) -> list[sqlite3.Row]:
        with self.connect() as conn:
            return conn.execute(
                """SELECT s.*, r.id AS request_id, r.category AS request_category,
                    r.status AS request_status, r.urgency AS request_urgency
                FROM flight_seats s
                LEFT JOIN communication_requests r ON r.id = (
                    SELECT r2.id FROM communication_requests r2
                    WHERE r2.flight_id = s.flight_id
                      AND r2.seat_number = s.seat_number
                      AND r2.status NOT IN ('cancelled', 'expired')
                    ORDER BY r2.updated_at DESC LIMIT 1
                )
                WHERE s.flight_id = ?
                ORDER BY s.row_number ASC, s.seat_order ASC""",
                (flight_id,),
            ).fetchall()

    def transition_request(self, request_id: str, status: str, crew_id: str | None, event: dict, topic: str, updated_at: str) -> sqlite3.Row:
        with self.lock, self.connect() as conn:
            conn.execute("UPDATE communication_requests SET status = ?, assigned_crew_device_id = COALESCE(?, assigned_crew_device_id), updated_at = ? WHERE id = ?", (status, crew_id, updated_at, request_id))
            self._append_event(conn, event, topic, updated_at)
            return conn.execute("SELECT * FROM communication_requests WHERE id = ?", (request_id,)).fetchone()

    def append_event(self, event: dict, topic: str, occurred_at: str) -> None:
        with self.lock, self.connect() as conn:
            self._append_event(conn, event, topic, occurred_at)

    def replay_events(self, flight_id: str, after_sequence: int, limit: int = 200) -> list[sqlite3.Row]:
        with self.connect() as conn:
            return conn.execute("SELECT * FROM request_events WHERE flight_id = ? AND sequence > ? ORDER BY sequence ASC LIMIT ?", (flight_id, after_sequence, limit)).fetchall()

    def pending_outbox(self, limit: int = 50) -> list[sqlite3.Row]:
        with self.connect() as conn:
            return conn.execute("SELECT * FROM outbox_messages WHERE published_at IS NULL ORDER BY id ASC LIMIT ?", (limit,)).fetchall()

    def mark_published(self, message_id: int) -> None:
        with self.lock, self.connect() as conn:
            conn.execute("UPDATE outbox_messages SET published_at = datetime('now') WHERE id = ?", (message_id,))

    def mark_inbox(self, event_id: str, topic: str, status: str, error: str | None = None) -> None:
        with self.lock, self.connect() as conn:
            conn.execute("INSERT OR REPLACE INTO inbox_messages VALUES (?, ?, ?, datetime('now'), ?)", (event_id, topic, status, error))

    def inbox_seen(self, event_id: str) -> bool:
        with self.connect() as conn:
            return conn.execute("SELECT 1 FROM inbox_messages WHERE event_id = ? AND status = 'processed'", (event_id,)).fetchone() is not None

    def _append_event(self, conn: sqlite3.Connection, event: dict, topic: str, created_at: str) -> None:
        sequence = conn.execute("SELECT COALESCE(MAX(sequence), 0) + 1 FROM request_events WHERE flight_id = ?", (event["flight_id"],)).fetchone()[0]
        event["sequence"] = sequence
        conn.execute("INSERT INTO request_events (event_id, request_id, flight_id, event_type, actor_device_id, payload, occurred_at, sequence) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", (event["event_id"], event["aggregate_id"], event["flight_id"], event["event_type"], event.get("device_id"), json.dumps(event["payload"]), event["occurred_at"], sequence))
        conn.execute("INSERT INTO outbox_messages (event_id, topic, payload, qos, created_at) VALUES (?, ?, ?, ?, ?)", (event["event_id"], topic, json.dumps(event), 1, created_at))


store = Store(settings.database_path)
