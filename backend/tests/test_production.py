"""Books isolation, audit trail, statements, reports, export, backup, ask, reminder."""

import json
from datetime import date

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def env(tmp_path, monkeypatch):
    monkeypatch.setenv("SAYLEDGER_DATA", str(tmp_path / "data"))
    import importlib

    import app.main as main
    importlib.reload(main)
    return main


def new_book(main, name="Demo Shop", currency="INR"):
    c = TestClient(main.app)
    r = c.post("/books", json={"shop_name": name, "currency": currency})
    c.headers["Authorization"] = f"Bearer {r.json()['token']}"
    return c


def add(c, name, kind, minor, note=""):
    r = c.post("/entries/confirm", json={"proposals": [
        {"party_name": name, "kind": kind, "amount_minor": minor, "note": note}], "source": "manual"})
    assert r.status_code == 200, r.text
    return r.json()["saved"][0]


def test_requires_token(env):
    c = TestClient(env.app)
    assert c.get("/parties").status_code == 401
    c.headers["Authorization"] = "Bearer nope"
    assert c.get("/parties").status_code == 401


def test_books_are_isolated(env):
    a, b = new_book(env, "A"), new_book(env, "B", "USD")
    add(a, "Ramesh", "credit_given", 45000)
    assert b.get("/parties").json()["parties"] == []
    assert b.get("/shop").json()["currency"] == "USD"


def test_void_keeps_entry_but_leaves_totals(env):
    c = new_book(env)
    e = add(c, "Ramesh", "credit_given", 45000)
    add(c, "Ramesh", "credit_given", 1000)
    assert c.post(f"/entries/{e['id']}/void", json={"reason": "typo"}).status_code == 200
    assert c.get("/parties").json()["parties"][0]["balance_minor"] == 1000
    assert len(c.get("/entries").json()["entries"]) == 1
    assert len(c.get("/entries?include_voided=true").json()["entries"]) == 2
    assert c.post(f"/entries/{e['id']}/void", json={}).status_code == 404
    assert c.patch(f"/entries/{e['id']}", json={"amount_minor": 5}).status_code == 400


def test_edit_is_audited(env):
    c = new_book(env)
    e = add(c, "Sita", "credit_given", 20000)
    r = c.patch(f"/entries/{e['id']}", json={"amount_minor": 25000, "note": "fixed"})
    assert r.json()["amount_minor"] == 25000
    events = c.get(f"/audit?entry_id={e['id']}").json()["events"]
    assert [ev["action"] for ev in events] == ["edit", "create"]
    assert events[0]["before"]["amount_minor"] == 20000 and events[0]["after"]["amount_minor"] == 25000


def test_party_edit_and_validation(env):
    c = new_book(env)
    e = add(c, "Maria", "credit_given", 100)
    pid = e["party_id"]
    assert c.patch(f"/parties/{pid}", json={"phone": "+1 415-555-0100", "language": "Spanish"}).json()["language"] == "Spanish"
    assert c.patch(f"/parties/{pid}", json={"phone": "call me"}).status_code == 400


def test_statement_running_balance_and_opening(env):
    main = env
    c = new_book(main)
    e = add(c, "Ramesh", "credit_given", 45000)
    pid = e["party_id"]
    # Backdate entries straight in the ledger to build a 2-day history.
    lg = main.books.open(c.headers["Authorization"][7:])[1]
    lg.add_entry("credit_given", 10000, pid, created_at="2026-10-01T06:00:00+00:00")
    lg.add_entry("payment_received", 4000, pid, created_at="2026-10-02T06:00:00+00:00")
    st = c.get(f"/parties/{pid}/statement?start=2026-10-02").json()
    assert st["opening_balance_minor"] == 10000
    assert [l["balance_after_minor"] for l in st["lines"]] == [6000, 51000]
    assert st["closing_balance_minor"] == 51000 == c.get(f"/parties/{pid}").json()["balance_minor"]


def test_report_and_csv(env):
    c = new_book(env)
    add(c, "Ramesh", "credit_given", 45000)
    add(c, "Sita", "payment_received", 5000)
    c.post("/entries/confirm", json={"proposals": [{"kind": "cash_sale", "amount_minor": 9900}]})
    c.post("/entries/confirm", json={"proposals": [{"kind": "expense", "amount_minor": 2500}]})
    today = date.today().isoformat()
    r = c.get(f"/report?start={today}&end={today}").json()
    assert (r["cash_in_minor"], r["cash_out_minor"], r["net_cash_minor"]) == (14900, 2500, 12400)
    assert (r["outstanding_total_minor"], r["advance_total_minor"]) == (45000, 5000)
    assert [p["name"] for p in r["parties"]] == ["Ramesh", "Sita"]
    csv = c.get("/export.csv").text
    assert "Ramesh" in csv and "450.00" in csv and csv.count("\n") == 5


def test_backup_restore_roundtrip(env, tmp_path):
    c = new_book(env)
    add(c, "Ramesh", "credit_given", 45000)
    blob = c.get("/backup").content
    add(c, "Sita", "credit_given", 100)
    r = c.post("/restore", files={"file": ("b.sayledger", blob, "application/octet-stream")})
    assert r.json()["entries"] == 1
    assert [p["name"] for p in c.get("/parties").json()["parties"]] == ["Ramesh"]
    bad = c.post("/restore", files={"file": ("x.sayledger", b"not a db", "application/octet-stream")})
    assert bad.status_code == 400


def test_delete_book(env):
    c = new_book(env)
    assert c.delete("/books/me").json() == {"deleted": True}
    assert c.get("/shop").status_code == 401


def fake_ask(monkeypatch, intent, params):
    from app import meta_client
    monkeypatch.setattr(meta_client, "ask_text", lambda *a, **k: json.dumps({"intent": intent, "params": params}))


def test_ask_numbers_come_from_book(env, monkeypatch):
    c = new_book(env)
    add(c, "Ramesh", "credit_given", 45000)
    add(c, "Sita", "credit_given", 12050)
    fake_ask(monkeypatch, "outstanding_total", {})
    r = c.post("/ask", json={"text": "kitna udhaar baaki hai?"}).json()
    assert r["numbers"]["Outstanding"] == 57050 and "₹570.50" in r["answer"]
    fake_ask(monkeypatch, "party_balance", {"party": "ramesh"})
    assert "Ramesh owes you ₹450" in c.post("/ask", json={"text": "x"}).json()["answer"]
    fake_ask(monkeypatch, "party_balance", {"party": "Nobody"})
    assert "couldn't find" in c.post("/ask", json={"text": "x"}).json()["answer"]
    fake_ask(monkeypatch, "none", {})
    assert "only answer questions about your book" in c.post("/ask", json={"text": "weather?"}).json()["answer"]


def test_reminder_amount_always_exact(env, monkeypatch):
    from app import meta_client
    c = new_book(env, currency="USD")
    pid = add(c, "Maria", "credit_given", 1250)["party_id"]
    monkeypatch.setattr(meta_client, "ask_text", lambda *a, **k: "Hola Maria, your balance is {AMOUNT}. Gracias!")
    r = c.post("/reminder-draft", json={"party_id": pid, "language": "Spanish"}).json()
    assert r["text"] == "Hola Maria, your balance is $12.50. Gracias!" and r["ai_written"]
    # Model invents a number -> safe template with the exact amount.
    monkeypatch.setattr(meta_client, "ask_text", lambda *a, **k: "Pay {AMOUNT} within 7 days.")
    r = c.post("/reminder-draft", json={"party_id": pid}).json()
    assert "$12.50" in r["text"] and "7" not in r["text"] and not r["ai_written"]
    pid2 = add(c, "Jake", "payment_received", 100)["party_id"]
    assert c.post("/reminder-draft", json={"party_id": pid2}).status_code == 400


def test_ledger_photo_rows_validated(env, monkeypatch):
    from app import meta_client
    c = new_book(env)
    reply = {"rows": [
        {"party_name": "Ramesh", "kind": "credit_given", "amount": 450, "note": "rice", "confidence": 0.9},
        {"party_name": "Sita", "kind": "credit_given", "amount": 120, "confidence": 0.4},
        {"party_name": "??", "kind": "credit_given", "amount": None, "confidence": 0.2},
    ], "unreadable": 1}
    monkeypatch.setattr(meta_client, "ask_image", lambda *a, **k: json.dumps(reply))
    r = c.post("/ledger-photo", files={"image": ("p.png", b"\x89PNG fake", "image/png")}).json()
    assert [row["amount_minor"] for row in r["rows"]] == [45000, 12000]
    assert "amount" in r["rows"][1]["doubt"]
    assert r["unreadable"] == 2
    assert c.get("/parties").json()["parties"] == []  # nothing saved
    assert c.post("/ledger-photo", files={"image": ("p.gif", b"x", "image/gif")}).status_code == 400


def test_ai_rate_limit(env, monkeypatch):
    from app import meta_client
    monkeypatch.setattr(meta_client, "ask_text", lambda *a, **k: '{"entries": []}')
    monkeypatch.setattr(env, "AI_LIMIT", 3)
    c = new_book(env)
    codes = [c.post("/text", json={"text": "x"}).status_code for _ in range(4)]
    assert codes == [200, 200, 200, 429]


def test_ledger_photo_saves_with_page_date(env):
    c = new_book(env)
    r = c.post("/entries/confirm", json={"source": "ledger_photo", "proposals": [
        {"party_name": "Iqbal", "kind": "credit_given", "amount_minor": 18000, "date": "2026-10-02"},
        {"party_name": "Iqbal", "kind": "credit_given", "amount_minor": 100, "date": "2999-01-01"}]}).json()
    assert r["saved"][0]["created_at"].startswith("2026-10-02")
    assert not r["saved"][1]["created_at"].startswith("2999")


def test_collections_ageing_fifo(env):
    from datetime import date as _d
    c = new_book(env)
    lg = env.books.open(c.headers["Authorization"][7:])[1]
    r = lg.add_party("Ramesh")["id"]
    lg.add_entry("credit_given", 10000, r, created_at="2026-07-01T06:00:00+00:00")  # old
    lg.add_entry("credit_given", 5000, r, created_at="2026-10-20T06:00:00+00:00")   # recent
    lg.add_entry("payment_received", 4000, r, created_at="2026-10-25T06:00:00+00:00")  # clears oldest first
    out = lg.collections(_d(2026, 11, 3))
    rm = out["customers"][0]
    assert rm["balance_minor"] == 11000
    assert rm["buckets"] == {"0_30": 5000, "31_60": 0, "61_90": 0, "90_plus": 6000}
    assert rm["oldest_unpaid_days"] == 125 and rm["days_since_payment"] == 9 and rm["remind"] is False
    assert out["buckets"]["90_plus"] == 6000 and out["outstanding_total_minor"] == 11000
    assert c.get("/collections").status_code == 200


def test_stock_count_filters_and_dedupes(env, monkeypatch):
    import io

    from PIL import Image

    from app import meta_client
    raw = ("<0f>1<|box;x1=10;y1=10;x2=50;y2=90;w=200;h=100;c=0.95|><|mask;x=0;y=0;data=1,1,~a|>,"
           "2<|box;x1=12;y1=11;x2=51;y2=90;w=200;h=100;c=0.90|><|mask;x=0;y=0;data=1,1,~a|>,"   # duplicate
           "3<|box;x1=100;y1=10;x2=140;y2=90;w=200;h=100;c=0.80|><|mask;x=0;y=0;data=1,1,~a|>,"
           "4<|box;x1=150;y1=10;x2=190;y2=90;w=200;h=100;c=0.20|><|mask;x=0;y=0;data=1,1,~a|>")  # low conf
    monkeypatch.setattr(meta_client, "segment", lambda *a, **k: raw)
    buf = io.BytesIO()
    Image.new("RGB", (200, 100), "white").save(buf, "PNG")
    c = new_book(env)
    r = c.post("/stock-count", files={"image": ("s.png", buf.getvalue(), "image/png")}, data={"item": "Water Bottle"}).json()
    assert r["count"] == 2 and r["item"] == "water bottle" and r["overlay_jpeg"]
    bad = c.post("/stock-count", files={"image": ("s.png", buf.getvalue(), "image/png")}, data={"item": "count all; drop table"})
    assert bad.status_code == 400
