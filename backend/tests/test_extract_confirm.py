import json

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(tmp_path, monkeypatch):
    monkeypatch.setenv("SAYLEDGER_DATA", str(tmp_path / "data"))
    import importlib

    import app.main as main
    importlib.reload(main)
    c = TestClient(main.app)
    token = c.post("/books", json={"shop_name": "Demo Shop", "currency": "INR"}).json()["token"]
    c.headers["Authorization"] = f"Bearer {token}"
    return c, main


def fake_reply(monkeypatch, entries):
    from app import meta_client
    monkeypatch.setattr(meta_client, "ask_text", lambda *a, **k: "```json\n" + json.dumps({"entries": entries}) + "\n```")


def test_text_proposes_but_saves_nothing(client, monkeypatch):
    c, main = client
    fake_reply(monkeypatch, [
        {"party_name": "Ramesh", "kind": "credit_given", "amount": 450, "note": "3 kg rice", "doubt": []},
        {"party_name": "Sita", "kind": "payment_received", "amount": "200.50", "note": "", "doubt": []},
    ])
    r = c.post("/text", json={"text": "Ramesh 450 udhaar, Sita ne 200.50 diye"}).json()
    assert [p["amount_minor"] for p in r["proposals"]] == [45000, 20050]
    assert all("new_customer" in p["doubt"] for p in r["proposals"])
    assert c.get("/parties").json()["parties"] == []


def test_confirm_saves_creates_party_and_balance(client, monkeypatch):
    c, _ = client
    props = [
        {"party_name": "Ramesh", "kind": "credit_given", "amount_minor": 45000, "note": "rice"},
        {"party_name": "ramesh", "kind": "payment_received", "amount_minor": 10000},
    ]
    r = c.post("/entries/confirm", json={"proposals": props, "heard": "x"}).json()
    assert len(r["saved"]) == 2
    assert list(r["balances"].values()) == [35000]
    assert c.get("/summary").json()["outstanding_total_minor"] == 35000


def test_existing_party_fuzzy_matched(client, monkeypatch):
    c, _ = client
    c.post("/entries/confirm", json={"proposals": [{"party_name": "Ramesh", "kind": "credit_given", "amount_minor": 100}]})
    fake_reply(monkeypatch, [{"party_name": "Ramesh ", "kind": "credit_given", "amount": 50}, {"party_name": "Rames", "kind": "credit_given", "amount": 5}])
    props = c.post("/text", json={"text": "x"}).json()["proposals"]
    assert [p["party_id"] for p in props] == [1, 1]


def test_bad_model_amounts_dropped_not_invented(client, monkeypatch):
    c, _ = client
    fake_reply(monkeypatch, [
        {"party_name": "A", "kind": "credit_given", "amount": -5},
        {"party_name": "B", "kind": "credit_given", "amount": None},
        {"party_name": "C", "kind": "steal", "amount": 5},
        {"party_name": None, "kind": "cash_sale", "amount": 30},
    ])
    props = c.post("/text", json={"text": "x"}).json()["proposals"]
    assert [(p["kind"], p["amount_minor"]) for p in props] == [("cash_sale", 3000)]


def test_garbage_reply_is_friendly_422(client, monkeypatch):
    c, _ = client
    from app import meta_client
    monkeypatch.setattr(meta_client, "ask_text", lambda *a, **k: "sorry, no idea")
    r = c.post("/text", json={"text": "x"})
    assert r.status_code == 422 and "try again" in r.json()["detail"]


def test_confirm_credit_without_name_rejected_nothing_saved(client):
    c, _ = client
    props = [{"party_name": "Ok", "kind": "credit_given", "amount_minor": 100},
             {"party_name": None, "kind": "credit_given", "amount_minor": 100}]
    assert c.post("/entries/confirm", json={"proposals": props}).status_code == 400
    assert c.get("/parties").json()["parties"] == []


def test_currency_locked_once_book_has_entries(client):
    c, _ = client
    assert c.put("/shop", json={"name": "Harbor Market", "currency": "USD"}).json()["currency"] == "USD"
    c.post("/entries/confirm", json={"proposals": [{"party_name": "Maria", "kind": "credit_given", "amount_minor": 1250}]})
    assert c.put("/shop", json={"name": "Harbor Market", "currency": "INR"}).status_code == 400
    assert c.put("/shop", json={"name": "Harbor Mkt", "currency": "usd"}).status_code == 200
