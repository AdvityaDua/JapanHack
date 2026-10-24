import importlib


def test_demo_seed_populates_backend_store(tmp_path, monkeypatch):
    import app.config as config
    import app.store as store_module

    monkeypatch.setattr(config.settings, "database_path", str(tmp_path / "demo.db"))
    store_module.store.path = config.settings.database_path
    store_module.store.init()
    store_module.store.seed_session({
        "id": config.settings.flight_id,
        "flight_number": config.settings.flight_number,
        "aircraft_identifier": config.settings.aircraft_identifier,
        "status": "boarding",
        "started_at": "2026-01-01T00:00:00+00:00",
    })

    import app.demo_seed as demo_seed
    importlib.reload(demo_seed)
    assert demo_seed.seed_demo_data() == 7
    assert demo_seed.seed_demo_data() == 0

    rows = store_module.store.list_requests(config.settings.flight_id, None)
    assert len(rows) == 7
    assert {row["status"] for row in rows} == {"created", "in_progress", "fulfilled"}
    tamil = next(row for row in rows if row["seat_number"] == "24A")
    assert tamil["passenger_language"] == "Tamil"
