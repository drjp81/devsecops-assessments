
param(
  [int]$Companies = 2,
  [int]$TeamsPerCompany = 2,
  [int]$AssessmentsPerTeam = 4,
  [switch]$Reset
)


$DBUser = "appuser"
$DBPassword = ConvertTo-SecureString -String "apppass" -AsPlainText -Force
$creds = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $DBUser, $DBPassword
$database = "assessments"
try {
  $sqlConnect = Open-MySqlConnection -ConnectionName MyDBCon -Server 192.168.1.188 -Database $database -Port 3306 -Credential $creds -WarningAction SilentlyContinue 
}
catch {
  Write-Host "Failed to connect to database $database" -ForegroundColor Red
  exit 1
}



function Invoke-MySQL {
  param([Parameter(Mandatory = $true)][string]$Sql)
  #$tmp = New-TemporaryFile
  #$Sql | Out-File -FilePath $tmp -Encoding UTF8
  try {
    $data = Invoke-SqlQuery -query $Sql -ErrorAction Stop -ConnectionName MyDBCon -WarningAction SilentlyContinue
    return $data

  }
  catch {
    Write-Host "Error executing SQL: $Sql" -ForegroundColor Red

  }
}

Write-Host "Seeding database via docker compose exec db (MariaDB)..." -ForegroundColor Cyan

# Optional: reset (DANGER: destructive)
if ($Reset) {
  Write-Host "Resetting tables..." -ForegroundColor Yellow
  $resetSql = @'
SET FOREIGN_KEY_CHECKS=0;
TRUNCATE TABLE raw_data;
TRUNCATE TABLE metrics;
TRUNCATE TABLE scores;
TRUNCATE TABLE controls_evidence;
TRUNCATE TABLE assessments;
TRUNCATE TABLE teams;
TRUNCATE TABLE companies;
TRUNCATE TABLE practices;
TRUNCATE TABLE maturity_models;
SET FOREIGN_KEY_CHECKS=1;
'@
  Invoke-MySQL -Sql $resetSql
}

# 1) Ensure maturity models and some practices exist (idempotent)
$seedModels = @'
INSERT IGNORE INTO maturity_models(name) VALUES
('SAMM'),('SSDF'),('SLSA'),('Auditability');

-- SAMM practices
INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name
FROM maturity_models m
JOIN (SELECT 'GOV.1' AS code, 'Governance Policy' AS name
      UNION ALL SELECT 'TST.1','Testing Strategy'
      UNION ALL SELECT 'OPS.1','Operations & Incident Mgmt') x
ON m.name='SAMM'
LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code
WHERE p.id IS NULL;

-- SSDF practices
INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name
FROM maturity_models m
JOIN (SELECT 'PS.3' AS code, 'Secure Software Build' AS name
      UNION ALL SELECT 'RV.1','Review Security Requirements' AS name) x
ON m.name='SSDF'
LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code
WHERE p.id IS NULL;

-- SLSA practices
INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name
FROM maturity_models m
JOIN (SELECT 'BUILD.L2' AS code, 'Build Integrity L2' AS name
      UNION ALL SELECT 'PROV.L2','Provenance L2' AS name) x
ON m.name='SLSA'
LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code
WHERE p.id IS NULL;

-- Auditability practices
INSERT INTO practices(model_id, code, name)
SELECT m.id, x.code, x.name
FROM maturity_models m
JOIN (SELECT 'EVID.1' AS code, 'Evidence Availability' AS name
      UNION ALL SELECT 'TRACE.1','Change Traceability' AS name) x
ON m.name='Auditability'
LEFT JOIN practices p ON p.model_id=m.id AND p.code=x.code
WHERE p.id IS NULL;
'@
Invoke-MySQL -Sql $seedModels

# 2) Create companies, teams, assessments with GUID tokens; then metrics/scores/controls/raw
$allTokens = @()

for ($ci = 1; $ci -le $Companies; $ci++) {
  # Create company
  $companyserial = $ci.ToString("D4")
  $cName = "Organisation-$companyserial"
  $cAddr = "123 Boulevard Demo, Suite $ci"
  $cContact = "Jules.Smith$ci@company.com"

  $sqlCompany = @"
INSERT INTO companies(name, address, contact_person, created_at)
VALUES ('$cName', '$cAddr', '$cContact', NOW());
"@
  Invoke-MySQL -Sql $sqlCompany

  # Fetch company id
  $sqlGetCid = "SELECT id FROM companies WHERE name='$cName';"
  $cid = (Invoke-MySQL -Sql $sqlGetCid).id
  if (-not $cid) { throw "Failed to obtain company id for $cName" }

  for ($ti = 1; $ti -le $TeamsPerCompany; $ti++) {
    $tName = "Product Team-$ti-$companyserial"
    $tNick = "t$ti"
    $tPurpose = "Deliver Service $ti"
    $tDesc = "Demo team $ti for company $cName"

    $sqlTeam = @"
INSERT INTO teams(company_id, name, nickname, purpose, description)
VALUES ($cid, '$tName', '$tNick', '$tPurpose', '$tDesc');
"@
    Invoke-MySQL -Sql $sqlTeam

    # Fetch team id
    $sqlGetTid = "SELECT id FROM teams WHERE company_id=$cid AND name='$tName';"
    $tid = (Invoke-MySQL -Sql $sqlGetTid).id
    if (-not $tid) { throw "Failed to obtain team id for $tName" }

    for ($ai = 1; $ai -le $AssessmentsPerTeam; $ai++) {
      $aName = "Assessment-$ai-$tName"
      $aDate = (Get-Date).AddDays(-1 * (Get-Random -Minimum 0 -Maximum 60)).ToString('yyyy-MM-dd')
      $token = [Guid]::NewGuid().ToString()

      $sqlAssessment = @"
INSERT INTO assessments(team_id, name, assessment_date, guid_token, notes)
VALUES ($tid, '$aName', '$aDate', '$token', 'Seed data for demo');
"@
      Invoke-MySQL -Sql $sqlAssessment

      # Fetch assessment id
      $sqlGetAid = "SELECT id FROM assessments WHERE team_id=$tid AND guid_token='$token';"
      $aid = (Invoke-MySQL -Sql $sqlGetAid).id
      if (-not $aid) { throw "Failed to obtain assessment id for $aName" }

      # Metrics (DORA-like)
      $deploys = [Math]::Round((Get-Random -Minimum 5 -Maximum 50), 0)
      $leadP50 = [Math]::Round((Get-Random -Minimum 5 -Maximum 112), 0)
      $cfr = [Math]::Round((Get-Random -Minimum 1 -Maximum 20), 0)
      $mttrH = [Math]::Round((Get-Random -Minimum 1 -Maximum 24), 0)
      $eacr = [Math]::Round((Get-Random -Minimum 1 -Maximum 44), 0)

      $sqlMetrics = @"
INSERT INTO metrics(assessment_id, metric_name, metric_value, unit, collected_at) VALUES
($aid,'Deployment Frequency per Week',$deploys,'deploys/week',NOW()),
($aid,'Lead Time for Changes',$leadP50,'hours',NOW()),
($aid,'Change Failure Rate',$cfr,'%',NOW()),
($aid,'Mean Time to Recovery',$mttrH,'hours',NOW()),
($aid,'Eac per Iac Rate',$eacr,'%',NOW())
"@
      Invoke-MySQL -Sql $sqlMetrics

      # Scores using subselect to find practice ids
      $sqlScores = @"
INSERT INTO scores(assessment_id, practice_id, level, evidence_uri, notes)
SELECT $aid, p.id, FLOOR(RAND() * 4)+1, 'https://example.com/evidence/samm-gov1', 'demo'
FROM practices p JOIN maturity_models m ON p.model_id=m.id
WHERE m.name='SAMM' AND p.code='GOV.1';

INSERT INTO scores(assessment_id, practice_id, level, evidence_uri, notes)
SELECT $aid, p.id, FLOOR(RAND() * 4)+1, 'https://example.com/evidence/ssdf-ps3', 'demo'
FROM practices p JOIN maturity_models m ON p.model_id=m.id
WHERE m.name='SSDF' AND p.code='PS.3';

INSERT INTO scores(assessment_id, practice_id, level, evidence_uri, notes)
SELECT $aid, p.id, FLOOR(RAND() * 4)+1, 'https://example.com/evidence/slsa-build', 'demo'
FROM practices p JOIN maturity_models m ON p.model_id=m.id
WHERE m.name='SLSA' AND p.code='BUILD.L2';

INSERT INTO scores(assessment_id, practice_id, level, evidence_uri, notes)
SELECT $aid, p.id, FLOOR(RAND() * 4)+1, 'https://example.com/evidence/audit-evid1', 'demo'
FROM practices p JOIN maturity_models m ON p.model_id=m.id
WHERE m.name='Auditability' AND p.code='EVID.1';
"@
      Invoke-MySQL -Sql $sqlScores

      # Controls evidence
      $sqlControls = @"
INSERT INTO controls_evidence(assessment_id, domain, control, standard, level, evidence_uri, collected_at) VALUES
($aid,'SSDF','PS.3','SSDF',NULL,'https://example.com/run/123',NOW()),
($aid,'SLSA','PROV.L2','SLSA',NULL,'https://example.com/attest/abc',NOW());
"@
      Invoke-MySQL -Sql $sqlControls

      # Raw data (store as JSON text)
      $raw = @{
        source            = "github"
        repo              = "org/service-$ti"
        prs_merged_last30 = (Get-Random -Minimum 10 -Maximum 200)
        last_build        = (Get-Date).ToString("o")
      } | ConvertTo-Json -Depth 4

      $rawEsc = $raw.Replace("\", "\\").Replace("'", "''")
      $sqlRaw = @"
INSERT INTO raw_data(assessment_id, source, payload, collected_at)
VALUES ($aid, 'github', '$rawEsc', NOW());
"@
      Invoke-MySQL -Sql $sqlRaw

      $allTokens += [pscustomobject]@{ Company = $cName; Team = $tName; Assessment = $aName; Token = $token; AssessmentId = $aid }
    }
  }
}

Write-Host "`n== Created assessments & tokens ==" -ForegroundColor Green
$allTokens | Format-Table -AutoSize

Write-Host "`nIngestion example (PowerShell):" -ForegroundColor Cyan
if ($allTokens.Count -gt 0) {
  $t = $allTokens[0].Token
  @"
$guid = '$t'
$uri  = "http://localhost:8000/api/ingest/$guid/raw"
$body = @{ event = "build"; status = "success"; ts = (Get-Date).ToString("o") } | ConvertTo-Json
Invoke-RestMethod -Method Post -Uri $uri -ContentType "application/json" -Body $body -Headers @{"X-Source"="github"}
"@ | Write-Host
}
Close-SqlConnection -connectionname MyDBCon -erroraction SilentlyContinue