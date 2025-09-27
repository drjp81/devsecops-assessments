DevSecOps Assessments v2 — FastAPI + MariaDB (Docker Compose)
=============================================================

Hierarchy:
- Company -> Teams -> Assessments (assessments belong to a team)
- Assessments contain all collected data (RawData), Metrics, Scores (maturity), and ControlEvidence
- Each Assessment has a GUID token used as an API access token for JSON ingestion

Quick start:
  docker compose up --build -d
App:     http://localhost:8000
Adminer: http://localhost:8080  (System: MySQL; Server: db; User: appuser; Pass: apppass; DB: assessments)

Flow:
1) Create a Company (name, address, contact person)
2) Add Teams (name, nickname, purpose, description)
3) Create an Assessment on the Team (token auto-generated)
4) Assessment page:
   - Ingestion URL (/api/ingest/{GUID}/raw)
   - Paste raw JSON (manual)
   - Add Metrics (numeric)
   - Add Scores (SAMM/BSIMM/SSDF/SLSA/Auditability)
   - Add Control Evidence

JSON Ingestion:
POST /api/ingest/{guid}/raw
Headers: X-Source: <optional>
Body:    (application/json) — any JSON payload stored in RawData.payload (as text)
Response: {"status":"ok","assessment_id":..., "raw_id":...}

Security notes:
- Token-by-URL is an MVP; add TLS, Authorization header, and rotation for production.
