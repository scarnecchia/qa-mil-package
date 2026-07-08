"""Tests for configuration models (NUM-30)."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from qa_mil.config import CheckSelection, RequestTokens, load_config

# ---------------------------------------------------------------------------
# RequestTokens
# ---------------------------------------------------------------------------


class TestRequestTokens:
    def test_valid_tokens_and_derived_request_id(self) -> None:
        rt = RequestTokens(
            project_id="soc",
            workplan_type="qmr",
            workplan_id="wp001",
            dpid="nsdp",
            version_id="v01",
        )
        assert rt.request_id == "soc_qmr_wp001_nsdp_v01"

    def test_tokens_are_lowercased(self) -> None:
        rt = RequestTokens(
            project_id="SOC",
            workplan_type="QMR",
            workplan_id="WP001",
            dpid="NSDP",
            version_id="V01",
        )
        assert rt.request_id == "soc_qmr_wp001_nsdp_v01"

    def test_invalid_dpid_too_short(self) -> None:
        with pytest.raises(ValueError, match="dpid"):
            RequestTokens(
                project_id="soc",
                workplan_type="qmr",
                workplan_id="wp001",
                dpid="ab",
                version_id="v01",
            )

    def test_invalid_dpid_too_long(self) -> None:
        with pytest.raises(ValueError, match="dpid"):
            RequestTokens(
                project_id="soc",
                workplan_type="qmr",
                workplan_id="wp001",
                dpid="abcdefg",
                version_id="v01",
            )

    def test_invalid_dpid_non_alphanumeric(self) -> None:
        with pytest.raises(ValueError, match="dpid"):
            RequestTokens(
                project_id="soc",
                workplan_type="qmr",
                workplan_id="wp001",
                dpid="ns-dp",
                version_id="v01",
            )

    def test_invalid_workplan_id(self) -> None:
        with pytest.raises(ValueError, match="workplan_id"):
            RequestTokens(
                project_id="soc",
                workplan_type="qmr",
                workplan_id="w1",
                dpid="nsdp",
                version_id="v01",
            )

    def test_invalid_version_id(self) -> None:
        with pytest.raises(ValueError, match="version_id"):
            RequestTokens(
                project_id="soc",
                workplan_type="qmr",
                workplan_id="wp001",
                dpid="nsdp",
                version_id="version1",
            )


# ---------------------------------------------------------------------------
# Config loading
# ---------------------------------------------------------------------------


def _write_config(
    tmp_path: Path,
    etl: int = 12,
    dpid: str = "nsdp",
    workplan_id: str = "wp001",
    version_id: str = "v01",
) -> Path:
    cfg_data = {
        "etl_number": etl,
        "backend": {"name": "duckdb"},
        "input_manifest": str(tmp_path / "manifest.yaml"),
        "output_dir": str(tmp_path / "output"),
        "request": {
            "project_id": "soc",
            "workplan_type": "qmr",
            "workplan_id": workplan_id,
            "dpid": dpid,
            "version_id": version_id,
        },
        "checks": {"disabled": []},
    }
    p = tmp_path / "config.yaml"
    p.write_text(yaml.dump(cfg_data))
    return p


class TestConfigLoading:
    def test_valid_config_loads(self, tmp_path: Path) -> None:
        p = _write_config(tmp_path)
        cfg = load_config(p)
        assert cfg.etl_number == 12
        assert cfg.backend.name == "duckdb"
        assert cfg.request_id == "soc_qmr_wp001_nsdp_v01"

    def test_config_file_not_found(self) -> None:
        with pytest.raises(FileNotFoundError, match="Config file not found"):
            load_config("/nonexistent/config.yaml")

    def test_empty_config_file(self, tmp_path: Path) -> None:
        p = tmp_path / "empty.yaml"
        p.write_text("")
        with pytest.raises(ValueError, match="empty"):
            load_config(p)

    def test_check_selection_defaults(self) -> None:
        cs = CheckSelection()
        assert cs.disabled == []
        assert cs.enabled is None
