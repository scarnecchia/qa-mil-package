"""Configuration models for qa-mil."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator


class RequestTokens(BaseModel):
    """SAS-compatible request identity tokens.

    Mirrors the SAS master-file derivation:
    ``%let ReqID = %lowcase(&ProjID._&WPType._&WPID._&DPID._&VerID);``
    """

    model_config = ConfigDict(extra="forbid")

    project_id: str = Field(..., description="Project identifier, e.g. 'soc'.")
    workplan_type: str = Field(..., description="Workplan type, e.g. 'qmr'.")
    workplan_id: str = Field(..., description="Workplan identifier, e.g. 'wp001'.")
    dpid: str = Field(..., description="Data-partner identifier, 3–6 alphanumeric chars.")
    version_id: str = Field(..., description="Version identifier, e.g. 'v01'.")

    @field_validator("dpid")
    @classmethod
    def validate_dpid(cls, v: str) -> str:
        v = v.lower()
        if not re.fullmatch(r"[a-z0-9]{3,6}", v):
            raise ValueError(f"dpid must be 3–6 alphanumeric characters, got {v!r}")
        return v

    @field_validator("workplan_id")
    @classmethod
    def validate_workplan_id(cls, v: str) -> str:
        v = v.lower()
        if not re.fullmatch(r"wp\d{3}", v):
            raise ValueError(
                f"workplan_id must follow convention 'wp###' (e.g. 'wp001'), got {v!r}"
            )
        return v

    @field_validator("version_id")
    @classmethod
    def validate_version_id(cls, v: str) -> str:
        v = v.lower()
        if not re.fullmatch(r"v\d{2}", v):
            raise ValueError(f"version_id must follow convention 'v##' (e.g. 'v01'), got {v!r}")
        return v

    @field_validator("project_id", "workplan_type")
    @classmethod
    def lowercase_tokens(cls, v: str) -> str:
        return v.lower()

    @property
    def request_id(self) -> str:
        """Derived request ID: lowercase underscore-joined tokens.

        Matches SAS: ``%lowcase(&ProjID._&WPType._&WPID._&DPID._&VerID)``
        """
        return "_".join(
            [
                self.project_id,
                self.workplan_type,
                self.workplan_id,
                self.dpid,
                self.version_id,
            ]
        )


class CheckSelection(BaseModel):
    """Check enable/disable selection."""

    model_config = ConfigDict(extra="forbid")

    disabled: list[str] = Field(default_factory=list, description="Check IDs to disable.")
    enabled: list[str] | None = Field(
        default=None,
        description="If non-empty, only run these check IDs (overrides disabled).",
    )


class BackendConfig(BaseModel):
    """Backend configuration."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(default="duckdb", description="Backend name: 'duckdb' or 'spark'.")
    options: dict[str, Any] = Field(
        default_factory=dict,
        description="Backend-specific options (e.g. memory_limit, threads).",
    )

    @field_validator("name")
    @classmethod
    def validate_backend(cls, v: str) -> str:
        allowed = {"duckdb", "spark"}
        if v.lower() not in allowed:
            raise ValueError(f"backend name must be one of {allowed}, got {v!r}")
        return v.lower()


class Config(BaseModel):
    """Top-level qa-mil configuration."""

    model_config = ConfigDict(extra="forbid")

    etl_number: int = Field(..., description="ETL number for this request.")
    backend: BackendConfig = Field(default_factory=BackendConfig)
    input_manifest: Path = Field(..., description="Path to the input manifest YAML.")
    output_dir: Path = Field(..., description="Directory for qa-mil output.")
    request: RequestTokens
    checks: CheckSelection = Field(default_factory=CheckSelection)

    @field_validator("etl_number")
    @classmethod
    def validate_etl(cls, v: int) -> int:
        if v < 1:
            raise ValueError(f"etl_number must be >= 1, got {v}")
        return v

    @property
    def request_id(self) -> str:
        """Convenience accessor for the derived request ID."""
        return self.request.request_id


def load_config(path: str | Path) -> Config:
    """Load a Config from a YAML file.

    Raises FileNotFoundError if the file does not exist.
    Raises ValueError (via pydantic) if the content is invalid.
    """
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Config file not found: {p}")
    with p.open() as f:
        data = yaml.safe_load(f)
    if data is None:
        raise ValueError(f"Config file is empty: {p}")
    return Config.model_validate(data)
