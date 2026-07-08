"""Shared pytest fixtures and utilities for qa-mil tests."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.parquet as pq
import pytest
import yaml


def write_parquet(path: Path, data: dict[str, list]) -> None:
    """Write a small parquet file from column-oriented dict data."""
    table = pa.table(data)
    pq.write_table(table, path)


def make_mil_data(
    rows: list[dict[str, Any]] | None = None,
) -> dict[str, list]:
    """Generate MIL table data.

    Default fixture has rows that will trigger various 371-375 checks.
    """
    if rows is None:
        rows = [
            # Birth_Type=1, 1 CPatID linked — consistent (no flag)
            {
                "MPatID": "M001",
                "CPatID": "C001",
                "ADate": "2020-01-15",
                "EncounterID": "E001",
                "Birth_Type": 1,
            },
            # Birth_Type=2, 1 CPatID linked — inconsistent (flag 372)
            {
                "MPatID": "M002",
                "CPatID": "C002",
                "ADate": "2020-03-20",
                "EncounterID": "E002",
                "Birth_Type": 2,
            },
            # Birth_Type=3, 1 CPatID linked — inconsistent (flag 373)
            {
                "MPatID": "M003",
                "CPatID": "C003",
                "ADate": "2020-06-10",
                "EncounterID": "E003",
                "Birth_Type": 3,
            },
        ]
    # Convert list of dicts to column-oriented dict
    if rows:
        return {key: [row[key] for row in rows] for key in rows[0]}
    return {"MPatID": [], "CPatID": [], "ADate": [], "EncounterID": [], "Birth_Type": []}


def make_enr_data() -> dict[str, list]:
    """Generate ENR (enrollment) table data matching the default MIL fixture."""
    return {
        "MPatID": ["M001", "M002", "M003"],
        "EnrStart": ["2020-01-01", "2020-01-01", "2020-01-01"],
        "EnrEnd": ["2020-12-31", "2020-12-31", "2020-12-31"],
    }


def make_full_fixture(tmp_path: Path) -> dict[str, Path]:
    """Create both MIL and ENR parquet files, manifest, and config."""
    mil_path = tmp_path / "mil.parquet"
    write_parquet(mil_path, make_mil_data())
    enr_path = tmp_path / "enr.parquet"
    write_parquet(enr_path, make_enr_data())
    manifest_path = make_manifest_yaml(tmp_path, {"mil": mil_path, "enr": enr_path})
    config_path = make_config_yaml(tmp_path, manifest_path)
    return {"mil": mil_path, "enr": enr_path, "manifest": manifest_path, "config": config_path}


def make_config_yaml(
    tmp_path: Path,
    manifest_path: Path,
    etl: int = 12,
    disabled: list[str] | None = None,
) -> Path:
    """Write a config YAML file for tests."""
    cfg_data = {
        "etl_number": etl,
        "backend": {"name": "duckdb"},
        "input_manifest": str(manifest_path),
        "output_dir": str(tmp_path / "output"),
        "request": {
            "project_id": "soc",
            "workplan_type": "qmr",
            "workplan_id": "wp001",
            "dpid": "nsdp",
            "version_id": "v01",
        },
        "checks": {"disabled": disabled or []},
    }
    p = tmp_path / "config.yaml"
    p.write_text(yaml.dump(cfg_data))
    return p


def make_manifest_yaml(
    tmp_path: Path,
    tables: dict[str, Path],
    etl: int = 12,
) -> Path:
    """Write an input manifest YAML file for tests."""
    manifest_data = {
        "manifest_version": "1.0",
        "etl_number": etl,
        "scdm_version": "8.2.0",
        "semantic_profile": {
            "name": "qa-mil-parquet-v1",
            "sas_date": "date32",
            "sas_datetime": "timestamp_us",
            "character_padding": "trimmed",
            "numeric_missing": "null",
            "special_missing": "null",
        },
        "tables": {name: {"path": str(path)} for name, path in tables.items()},
    }
    p = tmp_path / "manifest.yaml"
    p.write_text(yaml.dump(manifest_data))
    return p


@pytest.fixture
def mil_fixture(tmp_path: Path) -> Path:
    """Create a MIL parquet fixture file."""
    p = tmp_path / "mil.parquet"
    write_parquet(p, make_mil_data())
    return p


@pytest.fixture
def full_setup(tmp_path: Path) -> dict[str, Path]:
    """Create a full config + manifest + parquet fixture set."""
    mil_path = tmp_path / "mil.parquet"
    write_parquet(mil_path, make_mil_data())
    enr_path = tmp_path / "enr.parquet"
    write_parquet(
        enr_path,
        {
            "MPatID": ["M001", "M002", "M003"],
            "EnrStart": ["2020-01-01", "2020-01-01", "2020-01-01"],
            "EnrEnd": ["2020-12-31", "2020-12-31", "2020-12-31"],
        },
    )
    manifest_path = make_manifest_yaml(tmp_path, {"mil": mil_path, "enr": enr_path})
    config_path = make_config_yaml(tmp_path, manifest_path)
    return {
        "config": config_path,
        "manifest": manifest_path,
        "mil": mil_path,
        "enr": enr_path,
        "output_dir": tmp_path / "output",
    }
