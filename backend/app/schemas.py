"""Pydantic models shared by the routes."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

Kind = Literal["credit_given", "payment_received", "cash_sale", "expense"]


class Proposal(BaseModel):
    party_name: str | None = None
    party_id: int | None = None  # set when the name matched an existing customer
    kind: Kind
    amount_minor: int = Field(gt=0)
    note: str = ""
    doubt: list[str] = []
    date: str | None = None  # YYYY-MM-DD read from a ledger page; used only for ledger_photo saves


class ProposalsOut(BaseModel):
    heard: str
    proposals: list[Proposal]
    currency: str


class TextIn(BaseModel):
    text: str = Field(min_length=1, max_length=2000)


class ConfirmIn(BaseModel):
    proposals: list[Proposal] = Field(min_length=1, max_length=20)
    heard: str = ""
    source: Literal["voice", "ledger_photo", "manual"] = "voice"


class ShopIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    currency: str = Field(default="INR", min_length=3, max_length=3)


class BookIn(BaseModel):
    shop_name: str = Field(default="My Shop", min_length=1, max_length=80)
    currency: str = Field(default="INR", min_length=3, max_length=3)


class AskIn(BaseModel):
    text: str = Field(min_length=1, max_length=500)


class EntryEdit(BaseModel):
    kind: Kind | None = None
    amount_minor: int | None = Field(default=None, gt=0)
    party_id: int | None = None
    note: str | None = Field(default=None, max_length=200)


class VoidIn(BaseModel):
    reason: str = Field(default="", max_length=200)


class PartyEdit(BaseModel):
    name: str | None = Field(default=None, max_length=80)
    phone: str | None = Field(default=None, max_length=30)
    language: str | None = Field(default=None, max_length=40)


class ReminderIn(BaseModel):
    party_id: int
    language: str = Field(default="English", min_length=2, max_length=40)
