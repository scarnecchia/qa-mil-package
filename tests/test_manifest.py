"""Tests for input manifest and run manifest models (NUM-30, NUM-38)."""

from __future__ import annotations

from pathlib import Path

import pytest
import yaml

from qa_mil.manifest import (
    InputManifest,
    RunManifest,
    SemanticProfile,
    TableEntry,
    load_input_manifest,
    resolve_table_path,
    validate_etl_consistency,
    validate_required_tables,
    validate_table_paths,
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _minimal_manifest_data(
    tables: dict[str, dict] | None = None,
    etl: int = 12,
    conversion: dict | None = None,
    manifest_version: str = "1.0",
    profile_name: str = "qa-mil-parquet-v1",
) -> dict:
    data: dict = {
        "manifest_version": manifest_version,
        "etl_number": etl,
        "scdm_version": "8.2.0",
        "semantic_profile": {
            "name": profile_name,
            "sas_date": "date32",
            "sas_datetime": "timestamp_us",
            "character_padding": "trimmed",
            "numeric_missing": "null",
            "special_missing": "null",
        },
        "tables": tables or {},
    }
    if conversion is not None:
        data["conversion"] = conversion
    return data


def _write_manifest(tmp_path: Path, data: dict) -> Path:
    p = tmp_path / "manifest.yaml"
    p.write_text(yaml.dump(data))
    return p


def _touch_parquet(tmp_path: Path, name: str = "mil.parquet") -> str:
    """Create a dummy parquet-like file for path-existence tests."""
    p = tmp_path / name
    p.write_text("dummy")
    return str(p)


# ---------------------------------------------------------------------------
# SemanticProfile
# ---------------------------------------------------------------------------


class TestSemanticProfile:
    def test_valid_profile(self) -> None:
        sp = SemanticProfile(
            name="qa-mil-parquet-v1",
            sas_date="date32",
            sas_datetime="timestamp_us",
            character_padding="trimmed",
            numeric_missing="null",
            special_missing="null",
        )
        assert sp.name == "qa-mil-parquet-v1"

    def test_unsupported_profile_name(self) -> None:
        with pytest.raises(ValueError, match="Unsupported semantic profile"):
            SemanticProfile(
                name="unknown-profile",
                sas_date="date32",
                sas_datetime="timestamp_us",
                character_padding="trimmed",
                numeric_missing="null",
                special_missing="null",
            )

    def test_unsupported_padding(self) -> None:
        with pytest.raises(ValueError, match="character_padding"):
            SemanticProfile(
                name="qa-mil-parquet-v1",
                sas_date="date32",
                sas_datetime="timestamp_us",
                character_padding="chopped",
                numeric_missing="null",
                special_missing="null",
            )


# ---------------------------------------------------------------------------
# InputManifest loading and validation
# ---------------------------------------------------------------------------


class TestInputManifestLoading:
    def test_valid_manifest_loads(self, tmp_path: Path) -> None:
        pq = _touch_parquet(tmp_path, "mil.parquet")
        data = _minimal_manifest_data(tables={"mil": {"path": pq, "row_count": 100}})
        p = _write_manifest(tmp_path, data)
        manifest, parent = load_input_manifest(p)
        assert manifest.etl_number == 12
        assert manifest.scdm_version == "8.2.0"
        assert "mil" in manifest.tables

    def test_missing_manifest_version(self, tmp_path: Path) -> None:
        data = _minimal_manifest_data()
        del data["manifest_version"]
        p = _write_manifest(tmp_path, data)
        with pytest.raises(ValueError, match="manifest_version"):
            load_input_manifest(p)

    def test_unsupported_manifest_version(self, tmp_path: Path) -> None:
        data = _minimal_manifest_data(manifest_version="2.0")
        p = _write_manifest(tmp_path, data)
        with pytest.raises(ValueError, match="Unsupported manifest_version"):
            load_input_manifest(p)

    def test_missing_semantic_profile(self, tmp_path: Path) -> None:
        data = _minimal_manifest_data()
        del data["semantic_profile"]
        p = _write_manifest(tmp_path, data)
        with pytest.raises(ValueError, match="semantic_profile"):
            load_input_manifest(p)

    def test_empty_tables(self, tmp_path: Path) -> None:
        data = _minimal_manifest_data(tables={})
        p = _write_manifest(tmp_path, data)
        with pytest.raises(ValueError, match="at least one table"):
            load_input_manifest(p)

    def test_manifest_not_found(self) -> None:
        with pytest.raises(FileNotFoundError, match="Input manifest not found"):
            load_input_manifest("/nonexistent/manifest.yaml")


# ---------------------------------------------------------------------------
# Conversion metadata
# ---------------------------------------------------------------------------


class TestConversionMeta:
    def test_conversion_absent_does_not_fail(self, tmp_path: Path) -> None:
        pq = _touch_parquet(tmp_path, "mil.parquet")
        data = _minimal_manifest_data(tables={"mil": {"path": pq}})
        p = _write_manifest(tmp_path, data)
        manifest, _ = load_input_manifest(p)
        assert manifest.conversion is None

    def test_conversion_present_parsed(self, tmp_path: Path) -> None:
        pq = _touch_parquet(tmp_path, "mil.parquet")
        data = _minimal_manifest_data(
            tables={"mil": {"path": pq}},
            conversion={
                "tool": "scdm-convert",
                "version": "1.4.0",
                "completed_at": "2026-07-01T14:22:00Z",
            },
        )
        p = _write_manifest(tmp_path, data)
        manifest, _ = load_input_manifest(p)
        assert manifest.conversion is not None
        assert manifest.conversion.tool == "scdm-convert"
        assert manifest.conversion.version == "1.4.0"


# ---------------------------------------------------------------------------
# Path resolution
# ---------------------------------------------------------------------------


class TestPathResolution:
    def test_absolute_path_used_unchanged(self, tmp_path: Path) -> None:
        pq = _touch_parquet(tmp_path, "mil.parquet")
        entry = TableEntry(path=pq)
        resolved = resolve_table_path("mil", entry, tmp_path / "elsewhere")
        assert str(resolved) == str(Path(pq).resolve()) or resolved == Path(pq)

    def test_relative_path_resolved_from_manifest_parent(self, tmp_path: Path) -> None:
        # Create a subdirectory for the manifest, put the parquet next to it
        manifest_dir = tmp_path / "manifests"
        manifest_dir.mkdir()
        pq = manifest_dir / "mil.parquet"
        pq.write_text("dummy")

        entry = TableEntry(path="mil.parquet")  # relative
        resolved = resolve_table_path("mil", entry, manifest_dir)
        assert resolved == pq.resolve()

    def test_missing_table_path_names_table_and_path(self, tmp_path: Path) -> None:
        entry = TableEntry(path=str(tmp_path / "nonexistent.parquet"))
        with pytest.raises(FileNotFoundError, match="Table 'mil'"):
            validate_table_paths(
                InputManifest(
                    manifest_version="1.0",
                    etl_number=12,
                    scdm_version="8.2.0",
                    semantic_profile=SemanticProfile(
                        name="qa-mil-parquet-v1",
                        sas_date="date32",
                        sas_datetime="timestamp_us",
                        character_padding="trimmed",
                        numeric_missing="null",
                        special_missing="null",
                    ),
                    tables={"mil": entry},
                ),
                tmp_path,
                check_exists=True,
            )


# ---------------------------------------------------------------------------
# ETL consistency
# ---------------------------------------------------------------------------


class TestETLConsistency:
    def test_matching_etl(self) -> None:
        validate_etl_consistency(12, 12)  # should not raise

    def test_etl_mismatch_names_both_values(self) -> None:
        with pytest.raises(ValueError, match="config=12.*manifest=13"):
            validate_etl_consistency(12, 13)


# ---------------------------------------------------------------------------
# Required table validation
# ---------------------------------------------------------------------------


class TestRequiredTables:
    def test_all_required_present(self, tmp_path: Path) -> None:
        pq = _touch_parquet(tmp_path, "mil.parquet")
        manifest, parent = load_input_manifest(
            _write_manifest(
                tmp_path,
                _minimal_manifest_data(tables={"mil": {"path": pq}}),
            )
        )
        validate_required_tables(manifest, {"mil": ["check_371"]})

    def test_missing_required_table_names_table_and_checks(self, tmp_path: Path) -> None:
        pq = _touch_parquet(tmp_path, "mil.parquet")
        manifest, _ = load_input_manifest(
            _write_manifest(
                tmp_path,
                _minimal_manifest_data(tables={"mil": {"path": pq}}),
            )
        )
        with pytest.raises(ValueError, match="Required table 'enr'.*check_200"):
            validate_required_tables(manifest, {"enr": ["check_200"]})


# ---------------------------------------------------------------------------
# Run manifest
# ---------------------------------------------------------------------------


class TestRunManifest:
    def _minimal_run_manifest(self) -> RunManifest:
        return RunManifest(
            package_version="0.1.0",
            request={
                "project_id": "soc",
                "workplan_type": "qmr",
                "workplan_id": "wp001",
                "dpid": "nsdp",
                "version_id": "v01",
            },
            request_id="soc_qmr_wp001_nsdp_v01",
            config={"etl_number": 12, "backend": {"name": "duckdb"}},
            input_manifest="/data/manifest.yaml",
            manifest_version="1.0",
            etl_number=12,
            scdm_version="8.2.0",
            semantic_profile={"name": "qa-mil-parquet-v1"},
            check_selection={"disabled": []},
        )

    def test_round_trip_without_conversion(self) -> None:
        rm = self._minimal_run_manifest()
        yaml_str = rm.to_yaml()
        rm2 = RunManifest.from_yaml(yaml_str)
        assert rm2.request_id == rm.request_id
        assert rm2.etl_number == rm.etl_number
        assert rm2.conversion is None

    def test_conversion_preserved_in_serialization(self) -> None:
        rm = self._minimal_run_manifest()
        rm.conversion = {
            "tool": "scdm-convert",
            "version": "1.4.0",
            "completed_at": "2026-07-01T14:22:00Z",
        }
        yaml_str = rm.to_yaml()
        rm2 = RunManifest.from_yaml(yaml_str)
        assert rm2.conversion is not None
        assert rm2.conversion["tool"] == "scdm-convert"

    def test_request_id_recorded(self) -> None:
        rm = self._minimal_run_manifest()
        assert rm.request_id == "soc_qmr_wp001_nsdp_v01"
