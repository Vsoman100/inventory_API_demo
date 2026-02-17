# Inventory Orders API (Demo)

This repository contains a demo/test version of a backend service for managing orders, shipments, and inventory. It demonstrates a production-style architecture using FastAPI and PostgreSQL, including connection pooling, relational data modeling, and support for analytical workloads.

This project includes representative structure and core implementation patterns but excludes proprietary business logic, production configurations, and sensitive data.

---

## Tech Stack

- Python
- FastAPI
- PostgreSQL
- psycopg (v3) with connection pooling
- Pydantic
- python-dotenv

---

## Features

- REST API for:
  - Creating and retrieving orders
  - Managing order items
  - Recording and updating shipments
- PostgreSQL schema with:
  - Normalized relational design
  - Foreign key constraints
  - Indexes for common query patterns
  - Triggers for updated_at
- Seed data for local development
- Database health and debug endpoints
- Configurable connection pooling
- Analytical materialized view for reporting patterns

---

## Project Structure

app/
  app.py                FastAPI application and endpoints  
  db.py                 Database connection pool and query helpers  
  models.py             Pydantic request/response models  
  db/
    db_creation.sql     Schema and indexes  
    db_seeding.sql      Sample seed data  

---

## Getting Started

### 1. Requirements

- Python 3.9+
- PostgreSQL running locally

Install dependencies:

pip install -r requirements.txt

---

### 2. Environment Configuration

Create a `.env` file (see `.env.example`):

DATABASE_URL=postgresql://postgres:postgres@localhost:5432/inventory_demo  
APP_POOL_MIN=1  
APP_POOL_MAX=10  

Create the database:

CREATE DATABASE inventory_demo;

---

### 3. Initialize Schema

psql -d inventory_demo -f app/db/db_creation.sql  
psql -d inventory_demo -f app/db/db_seeding.sql  

---

### 4. Run the API

uvicorn app.app:app --reload

API docs will be available at:

http://localhost:8000/docs

---

## Example Endpoints

GET /health/db  
GET /debug/seed-summary  
POST /orders  
GET /orders/{order_id}  
PATCH /shipments/{shipment_id}

---

## Design Notes

Connection Pooling  
Uses psycopg_pool to efficiently manage database connections.

Separation of Concerns  
- API layer (app.py)  
- Database utilities (db.py)  
- Data models (models.py)  
- Schema and seed SQL  

Data Modeling  
- Normalized relational schema  
- Indexed query paths  
- Triggers for audit fields  

Analytics Support  
Includes a materialized view (weekly_order_tracking_mv) to demonstrate patterns for reporting and downstream analytics.

---

## Purpose

This repository is intended as a portfolio example demonstrating:

- Backend API design
- Relational data modeling
- Production-style project structure
- Database performance considerations
- End-to-end service setup

---

## Future Improvements

- Docker containerization
- Background jobs for materialized view refresh
- Authentication/authorization
- Schema migrations (Alembic)

---

## Author

Vishal Soman  
LinkedIn: https://www.linkedin.com/in/vishal-soman/
