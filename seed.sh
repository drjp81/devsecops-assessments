#!/usr/bin/env bash
set -euo pipefail

COMPANIES="${1:-2}"
TEAMS="${2:-2}"
ASSESS="${3:-2}"
RESET="${RESET:-}"

invoke_mysql() {
  local sql="$1"
  docker compose exec -T db sh -lc 'mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$MYSQL_DATABASE" --default-character-set=utf8mb4' <<SQL
${sql}
SQL
}

if [[ -n "${RESET}" ]]; then
  invoke_mysql "SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE raw_data; TRUNCATE TABLE metrics; TRUNCATE TABLE scores; TRUNCATE TABLE controls_evidence;
TRUNCATE TABLE assessments; TRUNCATE TABLE teams; TRUNCATE TABLE companies;
TRUNCATE TABLE practices; TRUNCATE TABLE maturity_models;
SET FOREIGN_KEY_CHECKS=1;"
fi

# Models & practices
invoke_mysql "INSERT IGNORE INTO maturity_models(name) VALUES ('SAMM'),('SSDF'),('SLSA'),('Auditability');"
invoke_mysql "INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name FROM maturity_models m
JOIN (SELECT 'GOV.1' code, 'Governance Policy' name UNION ALL SELECT 'TST.1','Testing Strategy' UNION ALL SELECT 'OPS.1','Operations & Incident Mgmt') x
ON m.name='SAMM' LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code WHERE p.id IS NULL;"
invoke_mysql "INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name FROM maturity_models m
JOIN (SELECT 'PS.3' code, 'Secure Software Build' UNION ALL SELECT 'RV.1','Review Security Requirements') x
ON m.name='SSDF' LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code WHERE p.id IS NULL;"
invoke_mysql "INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name FROM maturity_models m
JOIN (SELECT 'BUILD.L2' code, 'Build Integrity L2' UNION ALL SELECT 'PROV.L2','Provenance L2') x
ON m.name='SLSA' LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code WHERE p.id IS NULL;"
invoke_mysql "INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name FROM maturity_models m
JOIN (SELECT 'EVID.1' code, 'Evidence Availability' UNION ALL SELECT 'TRACE.1','Change Traceability') x
ON m.name='Auditability' LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code WHERE p.id IS NULL;"

for ((ci=1; ci<=COMPANIES; ci++)); do
  SUFFIX=$(cat /proc/sys/kernel/random/uuid | tr -d '-' | cut -c1-6)
  CNAME="Acme-${SUFFIX}"
  invoke_mysql "INSERT INTO companies(name, address, contact_person, created_at) VALUES
  ('$CNAME','123 Demo Blvd Suite ${ci}','Contact-${ci}',NOW());"
  CID=$(docker compose exec -T db sh -lc "mysql -N -B -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\" -e \"SELECT id FROM companies WHERE name='${CNAME}'\"")

  for ((ti=1; ti<=TEAMS; ti++)); do
    TNAME="Team-${ti}-${SUFFIX}"
    invoke_mysql "INSERT INTO teams(company_id,name,nickname,purpose,description) VALUES
    (${CID},'${TNAME}','t${ti}','Deliver Service ${ti}','Demo team ${ti} for ${CNAME}');"
    TID=$(docker compose exec -T db sh -lc "mysql -N -B -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\" -e \"SELECT id FROM teams WHERE company_id=${CID} AND name='${TNAME}'\"")

    for ((ai=1; ai<=ASSESS; ai++)); do
      TOKEN=$(cat /proc/sys/kernel/random/uuid)
      ANAME="Assessment-${ai}-${TNAME}"
      ADATE=$(date -I -d "$((RANDOM%60)) days ago")
      invoke_mysql "INSERT INTO assessments(team_id,name,assessment_date,guid_token,notes) VALUES
      (${TID},'${ANAME}','${ADATE}','${TOKEN}','Seed data');"
      AID=$(docker compose exec -T db sh -lc "mysql -N -B -u\"\$MYSQL_USER\" -p\"\$MYSQL_PASSWORD\" \"\$MYSQL_DATABASE\" -e \"SELECT id FROM assessments WHERE team_id=${TID} AND guid_token='${TOKEN}'\"")

      DEP=$(( (RANDOM%45)+5 )); LEAD=$(( (RANDOM%48)+1 )); CFR=$(( (RANDOM%20)+1 )); MTTR=$(( (RANDOM%24)+1 ));
      invoke_mysql "INSERT INTO metrics(assessment_id,metric_name,metric_value,unit,collected_at) VALUES
      (${AID},'deployment_frequency_week',${DEP},'deploys/week',NOW()),
      (${AID},'lead_time_p50_hours',${LEAD},'hours',NOW()),
      (${AID},'cfr_percent',${CFR},'%',NOW()),
      (${AID},'mttr_hours',${MTTR},'hours',NOW());"

      invoke_mysql "INSERT INTO scores(assessment_id,practice_id,level,evidence_uri,notes)
      SELECT ${AID}, p.id, 2, 'https://example.com/evidence/samm-gov1','demo'
      FROM practices p JOIN maturity_models m ON p.model_id=m.id WHERE m.name='SAMM' AND p.code='GOV.1';"
      invoke_mysql "INSERT INTO scores(assessment_id,practice_id,level,evidence_uri,notes)
      SELECT ${AID}, p.id, 1, 'https://example.com/evidence/ssdf-ps3','demo'
      FROM practices p JOIN maturity_models m ON p.model_id=m.id WHERE m.name='SSDF' AND p.code='PS.3';"
      invoke_mysql "INSERT INTO scores(assessment_id,practice_id,level,evidence_uri,notes)
      SELECT ${AID}, p.id, 2, 'https://example.com/evidence/slsa-build','demo'
      FROM practices p JOIN maturity_models m ON p.model_id=m.id WHERE m.name='SLSA' AND p.code='BUILD.L2';"
      invoke_mysql "INSERT INTO scores(assessment_id,practice_id,level,evidence_uri,notes)
      SELECT ${AID}, p.id, 1, 'https://example.com/evidence/audit-evid1','demo'
      FROM practices p JOIN maturity_models m ON p.model_id=m.id WHERE m.name='Auditability' AND p.code='EVID.1';"

      invoke_mysql "INSERT INTO controls_evidence(assessment_id,domain,control,standard,level,evidence_uri,collected_at) VALUES
      (${AID},'SSDF','PS.3','SSDF',NULL,'https://example.com/run/123',NOW()),
      (${AID},'SLSA','PROV.L2','SLSA',NULL,'https://example.com/attest/abc',NOW());"

      RAW=$(jq -n --arg repo "org/service-${ti}" --arg now "$(date --iso-8601=seconds)" --argjson prs $((RANDOM%200+10)) \
            '{source:"github",repo:$repo,prs_merged_last30:$prs,last_build:$now}')
      invoke_mysql "INSERT INTO raw_data(assessment_id,source,payload,collected_at) VALUES
      (${AID},'github','${RAW//\'/''}',NOW());"

      echo "Assessment token: ${TOKEN}"
    done
  done
done

echo "Seed complete."
