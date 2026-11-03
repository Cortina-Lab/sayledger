"""Phase 1 check: balances are correct for a scripted set of entries."""

from datetime import date

import pytest

from app.ledger import Ledger, LedgerError

DAY1 = "2026-10-30T09:00:00+00:00"
DAY2 = "2026-10-31T10:00:00+00:00"


@pytest.fixture
def book(tmp_path):
    lg = Ledger(tmp_path / "test.db")
    lg.set_shop("Demo Shop", "inr")
    return lg


@pytest.fixture
def scripted(book):
    """Ramesh: 450 + 120 credit, paid 200 -> owes 370.
    Sita: 300 credit, paid 300 -> owes 0.
    Maria: paid 50 in advance -> -50 (shop owes her)."""
    ramesh = book.add_party("Ramesh")
    sita = book.add_party("Sita", language="hi")
    maria = book.add_party("Maria", language="es")
    book.add_entry("credit_given", 45000, ramesh["id"], "3 kg rice", "voice", created_at=DAY1)
    book.add_entry("credit_given", 30000, sita["id"], created_at=DAY1)
    book.add_entry("cash_sale", 9900, note="biscuits", created_at=DAY1)
    book.add_entry("expense", 2500, note="tea", created_at=DAY1)
    book.add_entry("payment_received", 20000, ramesh["id"], created_at=DAY2)
    book.add_entry("credit_given", 12000, ramesh["id"], "oil", created_at=DAY2)
    book.add_entry("payment_received", 30000, sita["id"], created_at=DAY2)
    book.add_entry("payment_received", 5000, maria["id"], created_at=DAY2)
    return book, ramesh, sita, maria


def test_shop_currency_normalised(book):
    assert book.get_shop()["currency"] == "INR"


def test_party_balances(scripted):
    book, ramesh, sita, maria = scripted
    assert book.party_balance(ramesh["id"]) == 37000
    assert book.party_balance(sita["id"]) == 0
    assert book.party_balance(maria["id"]) == -5000


def test_outstanding_counts_only_positive_balances(scripted):
    book, *_ = scripted
    assert book.outstanding_total() == 37000


def test_top_debtors(scripted):
    book, ramesh, *_ = scripted
    top = book.top_debtors(5)
    assert [p["name"] for p in top] == ["Ramesh"]
    assert top[0]["balance_minor"] == 37000


def test_day_summary(scripted):
    book, *_ = scripted
    d1 = book.day_summary(date(2026, 10, 30))
    assert (d1["credit_given_minor"], d1["payment_received_minor"]) == (75000, 0)
    assert (d1["cash_sale_minor"], d1["expense_minor"], d1["entries"]) == (9900, 2500, 4)
    d2 = book.day_summary(date(2026, 10, 31))
    assert (d2["credit_given_minor"], d2["payment_received_minor"], d2["entries"]) == (12000, 55000, 4)
    assert d2["outstanding_total_minor"] == 37000


def test_party_history_date_filter(scripted):
    book, ramesh, *_ = scripted
    assert len(book.entries_for_party(ramesh["id"])) == 3
    assert len(book.entries_for_party(ramesh["id"], start=date(2026, 10, 31))) == 2


def test_delete_entry_undoes_balance(scripted):
    book, ramesh, *_ = scripted
    oil = [e for e in book.entries_for_party(ramesh["id"]) if e["note"] == "oil"][0]
    assert book.delete_entry(oil["id"])
    assert book.party_balance(ramesh["id"]) == 25000
    assert not book.delete_entry(oil["id"])


def test_party_name_case_insensitive(book):
    book.add_party("Ramesh  Kumar")
    assert book.find_party("ramesh kumar")["name"] == "Ramesh Kumar"
    with pytest.raises(LedgerError):
        book.add_party("RAMESH KUMAR")


@pytest.mark.parametrize("amount", [0, -100, 12.5, True, "450"])
def test_rejects_bad_amounts(book, amount):
    p = book.add_party("Ramesh")
    with pytest.raises(LedgerError):
        book.add_entry("credit_given", amount, p["id"])


def test_credit_needs_a_customer(book):
    with pytest.raises(LedgerError):
        book.add_entry("credit_given", 100)
    with pytest.raises(LedgerError):
        book.add_entry("payment_received", 100, party_id=999)


def test_rejects_unknown_kind_and_source(book):
    with pytest.raises(LedgerError):
        book.add_entry("loan", 100)
    with pytest.raises(LedgerError):
        book.add_entry("cash_sale", 100, source="telepathy")


def test_bad_currency(book):
    with pytest.raises(LedgerError):
        book.set_shop("Demo Shop", "RUPEES")
