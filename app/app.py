# app/app.py
import os
from fastapi import FastAPI, HTTPException, Depends, Query
from fastapi.responses import JSONResponse
from dotenv import load_dotenv

from .db import get_conn, fetch_all, fetch_one, execute, pool
from .models import OrderIn, OrderOut, OrderItemIn, ShipmentIn, ShipPatch, Pagination

load_dotenv()

app = FastAPI(title="Stencil Orders API", version="0.1.0")

@app.on_event("startup")
def startup():
    # touch the pool so it initializes eagerly
    with get_conn() as conn:
        pass

@app.on_event("shutdown")
def shutdown():
    pool.close()

# Health & Debug

@app.get("/health/db")
def health_db():
    try:
        with get_conn() as conn:
            row = fetch_one(conn, "SELECT 1 AS ok")
            return {"db_ok": row["ok"] == 1}
    except Exception as e:
        return JSONResponse(status_code=500, content={"db_ok": False, "error": str(e)})

@app.get("/debug/seed-summary")
def seed_summary():
    with get_conn() as conn:
        rows = fetch_all(conn, """
            SELECT 'products' key, COUNT(*)::int val FROM products UNION ALL
            SELECT 'boxes', COUNT(*)::int FROM boxes UNION ALL
            SELECT 'product_box', COUNT(*)::int FROM product_box UNION ALL
            SELECT 'inventory_items', COUNT(*)::int FROM inventory_items UNION ALL
            SELECT 'icr_rules', COUNT(*)::int FROM inventory_consumption_rules
        """)
        return {r["key"]: r["val"] for r in rows}

# Orders

@app.post("/orders", response_model=OrderOut, status_code=201)
def create_order(body: OrderIn):
    with get_conn() as conn:
        try:
            row = fetch_one(conn,
                "INSERT INTO orders(status, date) VALUES (%s, %s) RETURNING *",
                (body.status, body.date)
            )
            conn.commit()
            return row
        except Exception as e:
            conn.rollback()
            raise HTTPException(400, f"create_order failed: {e}")

@app.get("/orders/{order_id}", response_model=OrderOut)
def get_order(order_id: int):
    with get_conn() as conn:
        row = fetch_one(conn, "SELECT * FROM orders WHERE id=%s", (order_id,))
        if not row:
            raise HTTPException(404, "order not found")
        return row

@app.get("/orders")
def list_orders(limit: int = Query(50, ge=1, le=500), offset: int = Query(0, ge=0)):
    with get_conn() as conn:
        rows = fetch_all(conn,
            "SELECT * FROM orders ORDER BY created_at DESC LIMIT %s OFFSET %s",
            (limit, offset)
        )
        return rows

# Order Items

@app.post("/order_items", status_code=201)
def add_order_item(body: OrderItemIn):
    with get_conn() as conn:
        try:
            row = fetch_one(conn, """
                INSERT INTO order_items(order_id, product_id, qty, unit_price_cents, shipping_note, proof_sent)
                VALUES (%s,%s,%s,%s,%s,%s)
                RETURNING *
            """, (body.order_id, body.product_id, body.qty, body.unit_price_cents, body.shipping_note, body.proof_sent))
            conn.commit()
            return row
        except Exception as e:
            conn.rollback()
            raise HTTPException(400, f"add_order_item failed: {e}")

# Shipments (1:N per order)

@app.post("/shipments", status_code=201)
def create_shipment(body: ShipmentIn):
    with get_conn() as conn:
        try:
            row = fetch_one(conn, """
                INSERT INTO shipments(order_id, box_id, carrier, tracking_no, shipped_at)
                VALUES (%s,%s,%s,%s,%s)
                RETURNING *
            """, (body.order_id, body.box_id, body.carrier, body.tracking_no, body.shipped_at))
            conn.commit()
            return row
        except Exception as e:
            conn.rollback()
            raise HTTPException(400, f"create_shipment failed: {e}")

@app.patch("/shipments/{shipment_id}/ship")
def mark_shipment_shipped(shipment_id: int, body: ShipPatch):
    with get_conn() as conn:
        try:
            # default shipped_at to NOW() if not provided
            row = fetch_one(conn, """
                UPDATE shipments
                SET shipped_at = COALESCE(%s, NOW()),
                    tracking_no = COALESCE(%s, tracking_no)
                WHERE id = %s
                RETURNING *
            """, (body.shipped_at, body.tracking_no, shipment_id))
            if not row:
                raise HTTPException(404, "shipment not found")
            conn.commit()
            return row
        except HTTPException:
            raise
        except Exception as e:
            conn.rollback()
            raise HTTPException(400, f"mark_shipment_shipped failed: {e}")

# Reports (use your strict logic view/MV)

@app.get("/orders/shipped")
def list_shipped_orders(limit: int = Query(100, ge=1, le=500), offset: int = Query(0, ge=0)):
    with get_conn() as conn:
        # strict "all parcels shipped" is baked into the view in your schema
        rows = fetch_all(conn, "SELECT * FROM order_history_v ORDER BY created_at DESC LIMIT %s OFFSET %s", (limit, offset))
        return rows

@app.get("/reports/weekly")
def weekly_report():
    with get_conn() as conn:
        # if you kept the MV:
        rows = fetch_all(conn, "SELECT * FROM weekly_order_tracking_mv ORDER BY week_start DESC LIMIT 52")
        return rows

@app.post("/admin/refresh-weekly-mv")
def refresh_mv():
    # Optional admin endpoint if you want to refresh from the API
    with get_conn() as conn:
        try:
            execute(conn, "REFRESH MATERIALIZED VIEW weekly_order_tracking_mv")
            conn.commit()
            return {"ok": True}
        except Exception as e:
            conn.rollback()
            raise HTTPException(500, f"refresh failed: {e}")
