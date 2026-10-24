def test_legacy_r2_environment_aliases_are_supported(monkeypatch):
    from app.core.config import Settings

    monkeypatch.setenv("R2_ACCESS_ID", "access-id")
    monkeypatch.setenv("R2_ACCESS_KEY", "secret-key")
    monkeypatch.setenv("R2_URL", "https://account.r2.cloudflarestorage.com")
    settings = Settings(_env_file=None)
    assert settings.r2_access_key_id == "access-id"
    assert settings.r2_secret_access_key == "secret-key"
    assert settings.r2_endpoint_url == "https://account.r2.cloudflarestorage.com"
