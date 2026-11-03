from fastapi.testclient import TestClient


def test_health(tmp_path, monkeypatch):
    monkeypatch.setenv("SAYLEDGER_DATA", str(tmp_path / "data"))
    from app.main import app

    assert TestClient(app).get("/health").json() == {"ok": True}
