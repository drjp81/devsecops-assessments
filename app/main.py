from fastapi import FastAPI, Depends, Request, Form, HTTPException
from fastapi.responses import RedirectResponse, HTMLResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.orm import Session
from datetime import date
import uuid, json, os

from database import Base, engine, get_db
import models

from jinja2 import Environment, FileSystemLoader, select_autoescape

Base.metadata.create_all(bind=engine)

app = FastAPI(title="DevSecOps Assessments v2")

# Static & templates
app.mount("/static", StaticFiles(directory=os.path.join(os.path.dirname(__file__), "static")), name="static")
templates_env = Environment(
    loader=FileSystemLoader(os.path.join(os.path.dirname(__file__), "templates")),
    autoescape=select_autoescape(["html", "xml"])
)

def render(tpl_name: str, **ctx) -> HTMLResponse:
    tpl = templates_env.get_template(tpl_name)
    return HTMLResponse(tpl.render(**ctx))

@app.get("/", response_class=HTMLResponse)
def home():
    return RedirectResponse(url="/companies")

# -------------------- Companies --------------------
@app.get("/companies", response_class=HTMLResponse)
def companies_list(db: Session = Depends(get_db)):
    companies = db.query(models.Company).order_by(models.Company.name).all()
    return render("companies_list.html", companies=companies)

@app.post("/companies", response_class=HTMLResponse)
def companies_create(name: str = Form(...), address: str = Form(None), contact_person: str = Form(None), db: Session = Depends(get_db)):
    c = models.Company(name=name.strip(), address=(address or "").strip() or None, contact_person=(contact_person or "").strip() or None)
    db.add(c); db.commit()
    return RedirectResponse(url="/companies", status_code=303)

@app.get("/companies/{company_id}", response_class=HTMLResponse)
def company_detail(company_id: int, db: Session = Depends(get_db)):
    company = db.get(models.Company, company_id)
    if not company:
        return HTMLResponse("Company not found", status_code=404)
    teams = db.query(models.Team).filter_by(company_id=company_id).order_by(models.Team.name).all()
    return render("company_detail.html", company=company, teams=teams)

# -------------------- Teams --------------------
@app.post("/companies/{company_id}/teams", response_class=HTMLResponse)
def team_create(company_id: int,
                name: str = Form(...),
                nickname: str = Form(None),
                purpose: str = Form(None),
                description: str = Form(None),
                db: Session = Depends(get_db)):
    t = models.Team(company_id=company_id,
                    name=name.strip(),
                    nickname=(nickname or "").strip() or None,
                    purpose=(purpose or "").strip() or None,
                    description=description)
    db.add(t); db.commit()
    return RedirectResponse(url=f"/teams/{t.id}", status_code=303)

@app.get("/teams/{team_id}", response_class=HTMLResponse)
def team_detail(team_id: int, db: Session = Depends(get_db)):
    team = db.get(models.Team, team_id)
    if not team:
        return HTMLResponse("Team not found", status_code=404)
    assessments = (
        db.query(models.Assessment)
            .filter_by(team_id=team_id)
            .order_by(
            models.Assessment.assessment_date.is_(None),     # non-null first, nulls last
            models.Assessment.assessment_date.desc()
            )
            .all()
        )
    return render("team_detail.html", team=team, company=team.company, assessments=assessments)

# -------------------- Assessments --------------------
@app.post("/teams/{team_id}/assessments", response_class=HTMLResponse)
def assessment_create(team_id: int,
                      name: str = Form(...),
                      assessment_date: str = Form(None),
                      notes: str = Form(None),
                      db: Session = Depends(get_db)):
    d = None
    if assessment_date:
        try:
            d = date.fromisoformat(assessment_date)
        except:
            d = None
    token = str(uuid.uuid4())
    a = models.Assessment(team_id=team_id, name=name.strip(), assessment_date=d, guid_token=token, notes=notes)
    db.add(a); db.commit()
    return RedirectResponse(url=f"/assessments/{a.id}", status_code=303)

@app.get("/assessments/{assessment_id}", response_class=HTMLResponse)
def assessment_detail(assessment_id: int, db: Session = Depends(get_db)):
    a = db.get(models.Assessment, assessment_id)
    if not a:
        return HTMLResponse("Assessment not found", status_code=404)
    team = db.get(models.Team, a.team_id)
    company = team.company
    raw = db.query(models.RawData).filter_by(assessment_id=assessment_id).order_by(models.RawData.collected_at.desc()).limit(20).all()
    metrics = db.query(models.Metric).filter_by(assessment_id=assessment_id).order_by(models.Metric.collected_at.desc()).all()
    scores = db.query(models.Score).filter_by(assessment_id=assessment_id).all()
    controls = db.query(models.ControlEvidence).filter_by(assessment_id=assessment_id).order_by(models.ControlEvidence.collected_at.desc()).all()
    ingest_url = f"/api/ingest/{a.guid_token}/raw"
    return render("assessment_detail.html", assessment=a, team=team, company=company,
                  raw=raw, metrics=metrics, scores=scores, controls=controls, ingest_url=ingest_url)

# Web form endpoints (manual entry)
@app.post("/assessments/{assessment_id}/metrics", response_class=HTMLResponse)
def add_metric(assessment_id: int,
               metric_name: str = Form(...),
               metric_value: float = Form(...),
               unit: str = Form(None),
               db: Session = Depends(get_db)):
    m = models.Metric(assessment_id=assessment_id, metric_name=metric_name.strip(), metric_value=float(metric_value), unit=(unit or None))
    db.add(m); db.commit()
    return RedirectResponse(url=f"/assessments/{assessment_id}", status_code=303)

@app.post("/assessments/{assessment_id}/scores", response_class=HTMLResponse)
def add_score(assessment_id: int,
              model_name: str = Form(...),
              code: str = Form(...),
              practice_name: str = Form(None),
              level: int = Form(...),
              evidence_uri: str = Form(None),
              notes: str = Form(None),
              db: Session = Depends(get_db)):
    model = db.query(models.MaturityModel).filter_by(name=model_name.strip()).first()
    if not model:
        model = models.MaturityModel(name=model_name.strip()); db.add(model); db.flush()
    practice = db.query(models.Practice).filter_by(model_id=model.id, code=code.strip()).first()
    if not practice:
        practice = models.Practice(model_id=model.id, code=code.strip(), name=practice_name or code, description=None)
        db.add(practice); db.flush()
    s = models.Score(assessment_id=assessment_id, practice_id=practice.id, level=int(level), evidence_uri=(evidence_uri or None), notes=notes)
    db.add(s); db.commit()
    return RedirectResponse(url=f"/assessments/{assessment_id}", status_code=303)

@app.post("/assessments/{assessment_id}/controls", response_class=HTMLResponse)
def add_control(assessment_id: int,
                domain: str = Form(None),
                control: str = Form(...),
                standard: str = Form(None),
                level: str = Form(None),
                evidence_uri: str = Form(None),
                db: Session = Depends(get_db)):
    c = models.ControlEvidence(assessment_id=assessment_id, domain=(domain or None), control=control.strip(),
                               standard=(standard or None), level=(level or None), evidence_uri=(evidence_uri or None))
    db.add(c); db.commit()
    return RedirectResponse(url=f"/assessments/{assessment_id}", status_code=303)

@app.post("/assessments/{assessment_id}/raw", response_class=HTMLResponse)
def add_raw_manual(assessment_id: int, source: str = Form(None), payload_text: str = Form(...), db: Session = Depends(get_db)):
    try:
        _ = json.loads(payload_text)  # validate JSON
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON: {e}")
    r = models.RawData(assessment_id=assessment_id, source=(source or None), payload=payload_text)
    db.add(r); db.commit()
    return RedirectResponse(url=f"/assessments/{assessment_id}", status_code=303)

# -------------------- JSON Ingestion API --------------------
@app.post("/api/ingest/{guid_token}/raw")
async def ingest_raw(guid_token: str, request: Request, db: Session = Depends(get_db)):
    a = db.query(models.Assessment).filter_by(guid_token=guid_token).first()
    if not a:
        raise HTTPException(status_code=404, detail="Assessment token not found")
    try:
        body_bytes = await request.body()
        body = json.loads(body_bytes.decode("utf-8"))
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid JSON body: {e}")
    source = request.headers.get("X-Source", None)
    r = models.RawData(assessment_id=a.id, source=source, payload=json.dumps(body, ensure_ascii=False))
    db.add(r); db.commit()
    return {"status": "ok", "assessment_id": a.id, "raw_id": r.id}
