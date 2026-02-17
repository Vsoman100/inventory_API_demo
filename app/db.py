# app/db.py
import os
from contextlib import contextmanager
from psycopg_pool import ConnectionPool
from psycopg.rows import dict_row

DATABASE_URL = os.getenv("DATABASE_URL")
POOL_MIN = int(os.getenv("APP_POOL_MIN", "1"))
POOL_MAX = int(os.getenv("APP_POOL_MAX", "10"))

pool = ConnectionPool(
    conninfo=DATABASE_URL,
    min_size=POOL_MIN,
    max_size=POOL_MAX,
    kwargs={"autocommit": False}  # we’ll manage transactions
)

@contextmanager
def get_conn():
    with pool.connection() as conn:
        yield conn

def fetch_all(conn, sql, params=None):
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params or ())
        return cur.fetchall()

def fetch_one(conn, sql, params=None):
    with conn.cursor(row_factory=dict_row) as cur:
        cur.execute(sql, params or ())
        return cur.fetchone()

def execute(conn, sql, params=None):
    with conn.cursor() as cur:
        cur.execute(sql, params or ())
