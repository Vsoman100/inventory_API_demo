# app/models.py
from pydantic import BaseModel, Field
from typing import Optional

class OrderIn(BaseModel):
    status: str = Field(default="draft", pattern="^(draft|paid|fulfilled|cancelled)$")
    date: Optional[str] = None  # ISO YYYY-MM-DD

class OrderOut(BaseModel):
    id: int
    status: str
    date: Optional[str]
    shipped_at: Optional[str]
    created_at: str
    updated_at: str

class OrderItemIn(BaseModel):
    order_id: int
    product_id: int
    qty: int = Field(gt=0)
    unit_price_cents: int = Field(ge=0)
    shipping_note: Optional[str] = None
    proof_sent: Optional[str] = None

class ShipmentIn(BaseModel):
    order_id: int
    box_id: int
    carrier: Optional[str] = None
    tracking_no: Optional[str] = None
    shipped_at: Optional[str] = None  # ISO timestamp; None = pending

class ShipPatch(BaseModel):
    tracking_no: Optional[str] = None
    shipped_at: Optional[str] = None  # if omitted, we’ll default to NOW()

class Pagination(BaseModel):
    limit: int = Field(default=50, ge=1, le=500)
    offset: int = Field(default=0, ge=0)
