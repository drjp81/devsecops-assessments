from sqlalchemy import Column, Integer, String, Text, Date, DateTime, ForeignKey, Float
from sqlalchemy.orm import relationship
from datetime import datetime
from database import Base

class Company(Base):
    __tablename__ = "companies"
    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(200), nullable=False, unique=True)
    address = Column(Text, nullable=True)
    contact_person = Column(String(200), nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    teams = relationship("Team", back_populates="company", cascade="all, delete-orphan")

class Team(Base):
    __tablename__ = "teams"
    id = Column(Integer, primary_key=True, autoincrement=True)
    company_id = Column(Integer, ForeignKey("companies.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(200), nullable=False)
    nickname = Column(String(100), nullable=True)
    purpose = Column(String(300), nullable=True)
    description = Column(Text, nullable=True)

    company = relationship("Company", back_populates="teams")
    assessments = relationship("Assessment", back_populates="team", cascade="all, delete-orphan")

class Assessment(Base):
    __tablename__ = "assessments"
    id = Column(Integer, primary_key=True, autoincrement=True)
    team_id = Column(Integer, ForeignKey("teams.id", ondelete="CASCADE"), nullable=False)
    name = Column(String(200), nullable=False)
    assessment_date = Column(Date, nullable=True)
    guid_token = Column(String(36), nullable=False, unique=True)  # UUID4 string
    notes = Column(Text, nullable=True)

    team = relationship("Team", back_populates="assessments")
    raw = relationship("RawData", back_populates="assessment", cascade="all, delete-orphan")
    metrics = relationship("Metric", back_populates="assessment", cascade="all, delete-orphan")
    scores = relationship("Score", back_populates="assessment", cascade="all, delete-orphan")
    controls = relationship("ControlEvidence", back_populates="assessment", cascade="all, delete-orphan")

class RawData(Base):
    __tablename__ = "raw_data"
    id = Column(Integer, primary_key=True, autoincrement=True)
    assessment_id = Column(Integer, ForeignKey("assessments.id", ondelete="CASCADE"), nullable=False)
    source = Column(String(100), nullable=True)  # e.g., github, azuredevops, sonarqube
    payload = Column(Text, nullable=False)       # raw JSON string
    collected_at = Column(DateTime, default=datetime.utcnow)

    assessment = relationship("Assessment", back_populates="raw")

class Metric(Base):
    __tablename__ = "metrics"
    id = Column(Integer, primary_key=True, autoincrement=True)
    assessment_id = Column(Integer, ForeignKey("assessments.id", ondelete="CASCADE"), nullable=False)
    metric_name = Column(String(200), nullable=False)
    metric_value = Column(Float, nullable=False)
    unit = Column(String(50), nullable=True)
    collected_at = Column(DateTime, default=datetime.utcnow)

    assessment = relationship("Assessment", back_populates="metrics")

class MaturityModel(Base):
    __tablename__ = "maturity_models"
    id = Column(Integer, primary_key=True, autoincrement=True)
    name = Column(String(100), unique=True, nullable=False)  # SAMM, BSIMM, SSDF, SLSA, Auditability
    practices = relationship("Practice", back_populates="model", cascade="all, delete-orphan")

class Practice(Base):
    __tablename__ = "practices"
    id = Column(Integer, primary_key=True, autoincrement=True)
    model_id = Column(Integer, ForeignKey("maturity_models.id", ondelete="CASCADE"), nullable=False)
    code = Column(String(50), nullable=False)   # e.g., TST.1, GOV.2
    name = Column(String(200), nullable=False)
    description = Column(Text, nullable=True)

    model = relationship("MaturityModel", back_populates="practices")
    scores = relationship("Score", back_populates="practice")

class Score(Base):
    __tablename__ = "scores"
    id = Column(Integer, primary_key=True, autoincrement=True)
    assessment_id = Column(Integer, ForeignKey("assessments.id", ondelete="CASCADE"), nullable=False)
    practice_id = Column(Integer, ForeignKey("practices.id", ondelete="CASCADE"), nullable=False)
    level = Column(Integer, nullable=False)  # 0..3
    evidence_uri = Column(String(500), nullable=True)
    notes = Column(Text, nullable=True)

    assessment = relationship("Assessment", back_populates="scores")
    practice = relationship("Practice", back_populates="scores")

class ControlEvidence(Base):
    __tablename__ = "controls_evidence"
    id = Column(Integer, primary_key=True, autoincrement=True)
    assessment_id = Column(Integer, ForeignKey("assessments.id", ondelete="CASCADE"), nullable=False)
    domain = Column(String(100), nullable=True)      # optional grouping
    control = Column(String(200), nullable=False)    # e.g., SSDF-PS.3, CIS-2.3
    standard = Column(String(100), nullable=True)    # e.g., SSDF, CIS, SLSA
    level = Column(String(50), nullable=True)        # e.g., L1/L2/L3 or safeguard number
    evidence_uri = Column(String(500), nullable=True)
    collected_at = Column(DateTime, default=datetime.utcnow)

    assessment = relationship("Assessment", back_populates="controls")
