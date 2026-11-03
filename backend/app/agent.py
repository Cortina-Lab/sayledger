"""Prompts + strict validation around Muse Spark.

The model only PROPOSES entries. Python converts amounts to minor units,
rejects anything invalid and matches names; nothing here writes to the ledger.
"""

from __future__ import annotations

import difflib
import json
import re
from decimal import Decimal, InvalidOperation

from . import meta_client
from .schemas import Proposal

KINDS = ("credit_given", "payment_received", "cash_sale", "expense")

# ISO 4217 currencies without a minor unit; everything else uses 2 decimals.
ZERO_DECIMAL = {"JPY", "KRW", "VND", "CLP", "ISK", "UGX", "XAF", "XOF", "PYG", "RWF"}

EXTRACT_PROMPT = """You turn a shopkeeper's note into ledger entries.
Shop currency: {currency}. Known customers: {names}.
Allowed kinds:
- credit_given: the customer took goods/money on credit (udhaar) and now owes more
- payment_received: the customer paid back money they owed
- cash_sale: a sale paid immediately, no customer needed
- expense: the shop spent money
The note may be in English, Hindi, Hinglish or another language. One note may contain several entries.
Return JSON only, no other text:
{{"entries":[{{"party_name": <string or null>, "kind": <one allowed kind>, "amount": <number in {currency}>, "note": <short item description or "">, "doubt": [<field names you are unsure about>]}}]}}
Write party_name and note in English using Latin letters (transliterate names, e.g. "रमेश" -> "Ramesh"; translate item notes to English). If a known customer is meant, use the known spelling. If the note has no ledger entry, return {{"entries":[]}}.
Never guess an amount: if it is unclear, still return the entry with your best reading and put "amount" in doubt.

Note: {text}"""


class AgentError(ValueError):
    """The model's reply could not be turned into valid proposals."""


def _json_object(reply: str) -> dict:
    """Parse the first JSON object in the reply (models sometimes add ``` fences)."""
    start, end = reply.find("{"), reply.rfind("}")
    if start < 0 or end <= start:
        raise AgentError("No JSON in model reply")
    try:
        data = json.loads(reply[start : end + 1])
    except json.JSONDecodeError as e:
        raise AgentError("Model reply was not valid JSON") from e
    if not isinstance(data, dict):
        raise AgentError("Model reply was not a JSON object")
    return data


def to_minor(amount, currency: str) -> int:
    """Major units -> integer minor units. Rejects zero, negatives and junk."""
    if isinstance(amount, bool):
        raise AgentError("Bad amount")
    if isinstance(amount, str):
        amount = re.sub(r"[^\d.]", "", amount)
    try:
        value = Decimal(str(amount))
    except InvalidOperation as e:
        raise AgentError("Bad amount") from e
    exp = 0 if currency.upper() in ZERO_DECIMAL else 2
    minor = int((value * (10**exp)).to_integral_value())
    if minor <= 0:
        raise AgentError("Amount must be positive")
    return minor


def match_party(name: str | None, known: dict[str, int]) -> tuple[str | None, int | None]:
    """Case-insensitive exact match, then a close fuzzy match. Returns (name, id)."""
    if not name or not name.strip():
        return None, None
    name = " ".join(name.split())
    lower = {k.lower(): k for k in known}
    if name.lower() in lower:
        real = lower[name.lower()]
        return real, known[real]
    close = difflib.get_close_matches(name.lower(), list(lower), n=1, cutoff=0.8)
    if close:
        real = lower[close[0]]
        return real, known[real]
    return name, None


def proposals_from_reply(reply: str, currency: str, known: dict[str, int]) -> list[Proposal]:
    data = _json_object(reply)
    entries = data.get("entries")
    if not isinstance(entries, list):
        raise AgentError("Model reply has no entries list")
    out: list[Proposal] = []
    for e in entries[:20]:
        if not isinstance(e, dict) or e.get("kind") not in KINDS:
            continue
        doubt = [d for d in e.get("doubt") or [] if isinstance(d, str)]
        try:
            amount_minor = to_minor(e.get("amount"), currency)
        except AgentError:
            continue  # no usable amount: drop rather than invent one
        name, pid = match_party(e.get("party_name") if isinstance(e.get("party_name"), str) else None, known)
        if e["kind"] in ("credit_given", "payment_received") and not name:
            doubt.append("party_name")
        if name and pid is None and "party_name" not in doubt:
            doubt.append("new_customer")
        out.append(Proposal(
            party_name=name,
            party_id=pid,
            kind=e["kind"],
            amount_minor=amount_minor,
            note=str(e.get("note") or "")[:200],
            doubt=sorted(set(doubt)),
        ))
    return out


def extract(text: str, currency: str, known: dict[str, int]) -> list[Proposal]:
    prompt = EXTRACT_PROMPT.format(
        currency=currency,
        names=", ".join(known) or "(none yet)",
        text=text.strip(),
    )
    reply = meta_client.ask_text(prompt)
    return proposals_from_reply(reply, currency, known)


# ───────────────────────────── money text (display only) ─────────────────

_SYMBOLS = {"INR": "₹", "USD": "$", "EUR": "€", "GBP": "£", "JPY": "¥", "NGN": "₦"}


def _group(digits: str, indian: bool) -> str:
    if len(digits) <= 3:
        return digits
    head, tail = digits[:-3], digits[-3:]
    size = 2 if indian else 3
    parts = []
    while len(head) > size:
        parts.insert(0, head[-size:])
        head = head[:-size]
    if head:
        parts.insert(0, head)
    return ",".join(parts) + "," + tail


def fmt_money(minor: int, currency: str) -> str:
    cur = currency.upper()
    exp = 0 if cur in ZERO_DECIMAL else 2
    neg, minor = minor < 0, abs(minor)
    major, frac = divmod(minor, 10**exp) if exp else (minor, 0)
    text = _group(str(major), cur == "INR") + (f".{frac:02d}" if exp and frac else "")
    sym = _SYMBOLS.get(cur, cur + " ")
    return ("-" if neg else "") + sym + text


# ──────────────────────────────────── Ask ─────────────────────────────────

INTENTS = ("outstanding_total", "party_balance", "day_summary", "period_summary", "top_debtors", "party_history")

ASK_PROMPT = """You map a shopkeeper's question about their own account book to ONE intent. You never answer it yourself.
Today is {today}. Known customers: {names}.
Intents and params:
- outstanding_total: {{}}  (how much do customers owe in total)
- party_balance: {{"party": <customer name>}}
- day_summary: {{"date": "YYYY-MM-DD"}}  (sales/credit/payments/expenses on one day)
- period_summary: {{"from": "YYYY-MM-DD", "to": "YYYY-MM-DD"}}  (same, for a range like this week / last month)
- top_debtors: {{"n": <int 1-20>}}  (who owes the most)
- party_history: {{"party": <customer name>, "from": "YYYY-MM-DD" or null, "to": "YYYY-MM-DD" or null}}
If the question is not about this shop's book (e.g. weather, advice, general knowledge), use "none".
The question may be in any language. Return JSON only: {{"intent": <name or "none">, "params": {{...}}}}

Question: {question}"""


def _parse_day(value, fallback=None):
    from datetime import date as _date
    if not value:
        return fallback
    try:
        return _date.fromisoformat(str(value)[:10])
    except ValueError:
        raise AgentError("Bad date in model reply")


def classify_question(question: str, today, names: list[str]) -> tuple[str, dict]:
    reply = meta_client.ask_text(ASK_PROMPT.format(today=today.isoformat(), names=", ".join(names) or "(none yet)",
                                                   question=question.strip()))
    data = _json_object(reply)
    intent = data.get("intent")
    params = data.get("params") if isinstance(data.get("params"), dict) else {}
    if intent not in INTENTS:
        return "none", {}
    return intent, params


def answer_question(question: str, ledger, today) -> dict:
    """Model picks the intent; every number comes from the ledger."""
    from datetime import timedelta
    cur = ledger.currency()
    known = {p["name"]: p["id"] for p in ledger.parties_with_balances()}
    intent, params = classify_question(question, today, list(known))
    m = lambda v: fmt_money(v, cur)  # noqa: E731

    def party():
        name, pid = match_party(params.get("party") if isinstance(params.get("party"), str) else None, known)
        if pid is None:
            raise _NoParty(name)
        return name, pid

    try:
        if intent == "outstanding_total":
            total, top = ledger.outstanding_total(), ledger.top_debtors(100)
            return _ans(intent, f"Customers owe you {m(total)} in total, across {len(top)} "
                                f"customer{'s' if len(top) != 1 else ''}.",
                        {"Outstanding": total, "Customers owing": len(top)}, cur)
        if intent == "party_balance":
            name, pid = party()
            bal = ledger.party_balance(pid)
            text = (f"{name} owes you {m(bal)}." if bal > 0 else
                    f"{name} has paid {m(-bal)} in advance." if bal < 0 else f"{name} is all settled.")
            return _ans(intent, text, {f"{name} balance": bal}, cur, party_id=pid)
        if intent in ("day_summary", "period_summary"):
            start = _parse_day(params.get("date") or params.get("from"), today)
            end = _parse_day(params.get("to"), start) if intent == "period_summary" else start
            if end < start:
                start, end = end, start
            if end > today:
                end = today
            r = ledger.report(start, end)
            label = start.strftime("%d %b %Y") if start == end else f"{start:%d %b} – {end:%d %b %Y}"
            text = (f"{label}: {r['entries']} entr{'y' if r['entries'] == 1 else 'ies'}. "
                    f"Credit given {m(r['credit_given_minor'])}, payments received {m(r['payment_received_minor'])}, "
                    f"cash sales {m(r['cash_sale_minor'])}, expenses {m(r['expense_minor'])}.")
            return _ans(intent, text, {
                "Credit given": r["credit_given_minor"], "Payments received": r["payment_received_minor"],
                "Cash sales": r["cash_sale_minor"], "Expenses": r["expense_minor"], "Entries": r["entries"],
            }, cur, period={"from": start.isoformat(), "to": end.isoformat()})
        if intent == "top_debtors":
            try:
                n = max(1, min(int(params.get("n") or 5), 20))
            except (TypeError, ValueError):
                n = 5
            top = ledger.top_debtors(n)
            if not top:
                return _ans(intent, "Nobody owes you anything right now.", {}, cur)
            text = "Who owes the most: " + "; ".join(f"{p['name']} {m(p['balance_minor'])}" for p in top) + "."
            return _ans(intent, text, {p["name"]: p["balance_minor"] for p in top}, cur)
        if intent == "party_history":
            name, pid = party()
            start = _parse_day(params.get("from"))
            end = _parse_day(params.get("to"))
            st = ledger.statement(pid, start, end)
            n = len(st["lines"])
            text = (f"{name}: {n} entr{'y' if n == 1 else 'ies'}"
                    + (f" from {start:%d %b}" if start else "") + (f" to {end:%d %b %Y}" if end else "")
                    + f". Credit {m(st['credit_given_minor'])}, paid {m(st['payment_received_minor'])}. "
                    + f"Balance now {m(ledger.party_balance(pid))}.")
            return _ans(intent, text, {"Credit given": st["credit_given_minor"],
                                       "Payments received": st["payment_received_minor"],
                                       "Balance now": ledger.party_balance(pid)}, cur, party_id=pid)
    except _NoParty as e:
        who = f"'{e.name}'" if e.name else "that customer"
        return _ans("unknown_party", f"I couldn't find {who} in your book.", {}, cur)
    return _ans("none", "I can only answer questions about your book — like who owes you, "
                        "today's total, or a customer's balance.", {}, cur)


class _NoParty(Exception):
    def __init__(self, name):
        self.name = name


def _ans(intent, answer, numbers, currency, **extra) -> dict:
    # Counts are plain ints; everything else in `numbers` is minor units.
    return {"intent": intent, "answer": answer, "numbers": numbers, "currency": currency, **extra}


# ──────────────────────────────── Ledger photo ────────────────────────────

LEDGER_PHOTO_PROMPT = """This is a photo of a page from a small shop's handwritten credit book. Read it row by row.
Shop currency: {currency}. Known customers: {names}.
For each row you can read, return: party_name, kind (credit_given = customer took goods/money on credit; payment_received = customer paid; cash_sale; expense), amount (number in {currency}), note (item, in English), date (YYYY-MM-DD if written, else null), confidence (0 to 1).
Rows or amounts you cannot read clearly must NOT be guessed: count them in "unreadable".
Write names in Latin letters (transliterate if needed).
Return JSON only: {{"rows":[{{"party_name":..., "kind":..., "amount":..., "note":..., "date":..., "confidence":...}}], "unreadable": <int>}}"""


def read_ledger_photo(image: bytes, mime: str, currency: str, known: dict[str, int]) -> dict:
    reply = meta_client.ask_image(
        LEDGER_PHOTO_PROMPT.format(currency=currency, names=", ".join(known) or "(none yet)"),
        image, mime, effort="medium", max_tokens=6000,
    )
    data = _json_object(reply)
    raw_rows = data.get("rows") if isinstance(data.get("rows"), list) else []
    try:
        unreadable = max(0, int(data.get("unreadable") or 0))
    except (TypeError, ValueError):
        unreadable = 0
    rows = []
    for r in raw_rows[:60]:
        if not isinstance(r, dict):
            continue
        props = proposals_from_reply(json.dumps({"entries": [r]}), currency, known)
        if not props:
            unreadable += 1  # model returned a row we can't trust
            continue
        p = props[0].model_dump()
        try:
            conf = float(r.get("confidence"))
        except (TypeError, ValueError):
            conf = 0.5
        p["confidence"] = max(0.0, min(conf, 1.0))
        if p["confidence"] < 0.6 and "amount" not in p["doubt"]:
            p["doubt"].append("amount")
        p["date"] = r.get("date") if isinstance(r.get("date"), str) else None
        rows.append(p)
    return {"rows": rows, "unreadable": unreadable, "currency": currency}


# ─────────────────────────────── Reminder draft ───────────────────────────

REMINDER_PROMPT = """Write a short, polite payment reminder that a small shop owner will send to a customer.
Language: {language}. Customer: {party}. Shop: {shop}.
Write the placeholder {{AMOUNT}} exactly once where the amount goes. Do not write any other numbers, dates, interest, threats or deadlines.
2–3 sentences, warm and respectful. Return only the message text."""


def reminder_text(party: str, shop: str, balance_minor: int, currency: str, language: str) -> tuple[str, bool]:
    """Returns (text, used_model). Falls back to a fixed English template if the
    model's draft misses the placeholder or adds numbers of its own."""
    amount = fmt_money(balance_minor, currency)
    fallback = (f"Hello {party}, this is a friendly reminder from {shop}. "
                f"Your account shows {amount} due. Please clear it when convenient. Thank you!")
    try:
        draft = meta_client.ask_text(REMINDER_PROMPT.format(language=language, party=party, shop=shop),
                                     max_tokens=1200).strip().strip('"')
    except meta_client.MetaAPIError:
        return fallback, False
    if draft.count("{AMOUNT}") != 1 or re.search(r"\d", draft.replace("{AMOUNT}", "")) or len(draft) > 600:
        return fallback, False
    return draft.replace("{AMOUNT}", amount), True
