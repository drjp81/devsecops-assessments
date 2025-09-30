DevSecOps Assessments v2 (fixed imports) — FastAPI + MariaDB (Docker Compose)
=============================================================================

Hierarchy:
- Company -> Teams -> Assessments (assessments belong to a team)
- Separate RawData (ingested JSON) and Metrics, plus Scores & ControlEvidence
- Each Assessment has a GUID token used as an API access token for JSON ingestion

Quick start:
  unzip devsecops-assessments-v2-fixed.zip
  cd devsecops-assessments-v2-fixed
  docker compose up --build -d

App:     http://localhost:8000
Adminer: http://localhost:8080  (System: MySQL; Server: db; User: appuser; Pass: apppass; DB: assessments)

JSON Ingestion:
POST /api/ingest/{guid}/raw
Headers: X-Source: <optional>
Body:    application/json (stored as text in RawData.payload)
Response: {"status":"ok","assessment_id":..., "raw_id":...}

Note: If web starts before DB is ready, first request may fail. Re-try or add a healthcheck/wait-for-db for production.
