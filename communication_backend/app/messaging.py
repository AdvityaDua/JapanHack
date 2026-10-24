import json
import logging
import threading
import uuid
from collections.abc import Callable

try:
    import paho.mqtt.client as mqtt
except ImportError:  # pragma: no cover
    mqtt = None

from app.config import settings
from app.store import store

logger = logging.getLogger(__name__)


class MQTTBus:
    def __init__(self, on_command: Callable[[str, dict], None]) -> None:
        self.on_command = on_command
        self.client = None
        self.enabled = settings.mqtt_enabled and mqtt is not None
        self._stop = threading.Event()
        self._inflight: dict[int, int] = {}

    def start(self) -> None:
        if not self.enabled:
            logger.info("MQTT disabled; HTTP and WebSocket mode active")
            return
        client_id = f"aircraft-communication-edge-{settings.flight_id}-{uuid.uuid4().hex[:8]}"
        self.client = mqtt.Client(mqtt.CallbackAPIVersion.VERSION2, client_id=client_id)
        if settings.mqtt_username:
            self.client.username_pw_set(settings.mqtt_username, settings.mqtt_password)
        self.client.on_connect = self._on_connect
        self.client.on_message = self._on_message
        self.client.on_publish = self._on_publish
        self.client.connect(settings.mqtt_host, settings.mqtt_port, keepalive=30)
        self.client.loop_start()

    def stop(self) -> None:
        if self.client:
            self.client.loop_stop()
            self.client.disconnect()

    def _on_connect(self, client, userdata, flags, reason_code, properties=None):
        client.subscribe(f"flight/{settings.flight_id}/+/+/commands/#", qos=1)
        logger.info("Connected to MQTT broker: %s", reason_code)
        publish_pending(self)

    def _on_message(self, client, userdata, message):
        try:
            payload = json.loads(message.payload.decode())
            event_id = payload.get("event_id")
            if event_id and store.inbox_seen(event_id):
                return
            self.on_command(message.topic, payload)
            if event_id:
                store.mark_inbox(event_id, message.topic, "processed")
        except Exception as exc:  # keep broker loop alive
            logger.exception("MQTT command failed: %s", exc)
            if isinstance(payload if "payload" in locals() else None, dict) and payload.get("event_id"):
                store.mark_inbox(payload["event_id"], message.topic, "failed", str(exc))

    def _on_publish(self, client, userdata, mid, reason_code=None, properties=None):
        message_id = self._inflight.pop(mid, None)
        if message_id is not None:
            store.mark_published(message_id)

    def publish(self, topic: str, payload: dict, qos: int = 1, message_id: int | None = None) -> bool:
        if not self.client:
            return False
        info = self.client.publish(topic, json.dumps(payload), qos=qos)
        if message_id is not None and info.rc == mqtt.MQTT_ERR_SUCCESS:
            self._inflight[info.mid] = message_id
        return info.rc == mqtt.MQTT_ERR_SUCCESS


def publish_pending(bus: MQTTBus) -> None:
    if not bus.client:
        return
    for message in store.pending_outbox():
        bus.publish(message["topic"], json.loads(message["payload"]), message["qos"], message["id"])
