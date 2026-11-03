"""Fill a book with clearly-invented DEMO data (for the demo video / judges).

Usage (from backend/):
  .venv/bin/python -m scripts.seed_demo data/books/<book_id>.db [--currency INR|USD]

All names are invented. Entries are spread over the last ~100 days so ageing,
statements and reports have something real to show. Run on an empty book.
"""

from __future__ import annotations

import argparse
import random
from datetime import datetime, timedelta, timezone

from app.ledger import Ledger

INR = {
    "customers": ["Ramesh", "Sita", "Maria", "Iqbal", "Meena", "Ravi Tea Stall", "Anita"],
    "items": ["rice 5 kg", "sugar 2 kg", "oil 1 L", "atta 10 kg", "dal 2 kg", "tea 500 g", "milk", "soap", "biscuits"],
    "credit": (80, 1800),
    "sale": (20, 400),
    "expense": [("electricity bill", 1450), ("shop rent", 6000), ("delivery van fuel", 700), ("cleaning", 300)],
}
USD = {
    "customers": ["Maria", "Jake", "Priya", "Luis", "Grace", "Tom's Diner", "Aisha"],
    "items": ["milk 2 gal", "bread", "eggs dozen", "coffee", "rice 10 lb", "cereal", "detergent", "snacks"],
    "credit": (5, 90),
    "sale": (2, 40),
    "expense": [("electric bill", 140), ("rent", 1800), ("supplies", 75), ("van gas", 60)],
}


def at(days_ago: int, hour: int) -> str:
    now = datetime.now(timezone.utc)
    return (now - timedelta(days=days_ago)).replace(hour=hour, minute=random.randint(0, 59), second=0,
                                                    microsecond=0).isoformat()


def seed(path: str, currency: str) -> None:
    random.seed(7)
    lg = Ledger(path)
    if lg.entry_count():
        raise SystemExit("Book already has entries; seed an empty book.")
    shop = lg.get_shop()
    lg.set_shop(shop["name"] if shop else "Demo Shop", currency)
    d = INR if currency == "INR" else USD
    unit = 100
    ids = {name: lg.add_party(name)["id"] for name in d["customers"]}
    # Habits: some pay regularly, some fall behind (ageing buckets fill naturally).
    payers = {d["customers"][1], d["customers"][3], d["customers"][6]}
    for days_ago in range(100, -1, -1):
        for name, pid in ids.items():
            if random.random() < 0.10:
                amt = random.randint(*d["credit"]) * unit
                lg.add_entry("credit_given", amt, pid, random.choice(d["items"]),
                             random.choice(["voice", "voice", "manual"]), created_at=at(days_ago, random.randint(3, 13)))
            if name in payers and random.random() < 0.08 and lg.party_balance(pid) > 0:
                pay = min(lg.party_balance(pid), random.randint(*d["credit"]) * unit)
                lg.add_entry("payment_received", pay, pid, "", "voice", created_at=at(days_ago, random.randint(3, 13)))
        for _ in range(random.randint(1, 4)):
            lg.add_entry("cash_sale", random.randint(*d["sale"]) * unit, None, random.choice(d["items"]), "voice",
                         created_at=at(days_ago, random.randint(3, 14)))
        if days_ago % 30 == 3:
            for note, amt in d["expense"]:
                lg.add_entry("expense", amt * unit, None, note, "manual", created_at=at(days_ago, 5))
    # One old ledger-photo import and one corrected mistake, so the audit log has history.
    e = lg.add_entry("credit_given", d["credit"][1] * unit, ids[d["customers"][0]], "old book page", "ledger_photo",
                     created_at=at(96, 6))
    wrong = lg.add_entry("credit_given", 999 * unit, ids[d["customers"][2]], "typo", "voice", created_at=at(2, 6))
    lg.void_entry(wrong["id"], "Wrong amount, re-entered")
    lg.add_entry("credit_given", 99 * unit, ids[d["customers"][2]], "re-entered", "manual", created_at=at(2, 6))
    lg.edit_entry(e["id"], note="old book page (checked)")
    print(f"Seeded {lg.entry_count()} entries for {len(ids)} customers; outstanding {lg.outstanding_total() / 100:.2f} {currency}")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("book")
    ap.add_argument("--currency", default="INR")
    a = ap.parse_args()
    seed(a.book, a.currency.upper())
