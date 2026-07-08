"""Input manifest and run manifest models for qa-mil."""

from __future__ import annotations

from pathlib import Path
from typing import Any

import yaml
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

SUPPORTED_MANIFEST_VERSIONS = {"1.0"}

SUPPORTED_SEMANTIC_PROFILES = {
    "qa-mil-parquet-v1",
}


# ---------------------------------------------------------------------------
# Input manifest models
# ---------------------------------------------------------------------------


class SemanticProfile(BaseModel):
    """Semantic profile declaring upstream conversion semantics."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(..., description="Profile identifier, e.g. 'qa-mil-parquet-v1'.")
    sas_date: str = Field(..., description="SAS date representation, e.g. 'date32'.")
    sas_datetime: str = Field(..., description="SAS datetime representation, e.g. 'timestamp_us'.")
    character_padding: str = Field(
        ..., description="Character padding/trimming policy: 'trimmed' or 'padded'."
    )
    numeric_missing: str = Field(
        ..., description="Numeric missing value representation, e.g. 'null'."
    )
    special_missing: str = Field(
        ..., description="Special missing value representation, e.g. 'null'."
    )

    @field_validator("name")
    @classmethod
    def validate_name(cls, v: str) -> str:
        if v not in SUPPORTED_SEMANTIC_PROFILES:
            raise ValueError(
                f"Unsupported semantic profile name {v!r}; "
                f"supported: {sorted(SUPPORTED_SEMANTIC_PROFILES)}"
            )
        return v

    @field_validator("character_padding")
    @classmethod
    def validate_padding(cls, v: str) -> str:
        allowed = {"trimmed", "padded"}
        if v not in allowed:
            raise ValueError(f"character_padding must be one of {sorted(allowed)}, got {v!r}")
        return v


class Checksum(BaseModel):
    """Optional per-table checksum."""

    model_config = ConfigDict(extra="forbid")

    algorithm: str = Field(..., description="Checksum algorithm, e.g. 'sha256'.")
    value: str = Field(..., description="Checksum value.")


class TableEntry(BaseModel):
    """A single table entry in the input manifest."""

    model_config = ConfigDict(extra="forbid")

    path: str = Field(..., description="Path to the parquet file (absolute or relative).")
    row_count: int | None = Field(default=None, description="Optional row count.")
    checksum: Checksum | None = Field(default=None, description="Optional checksum.")
    provenance: dict[str, Any] | None = Field(
        default=None, description="Optional provenance metadata."
    )


class ConversionMeta(BaseModel):
    """Optional upstream conversion provenance."""

    model_config = ConfigDict(extra="forbid")

    tool: str = Field(..., description="Conversion tool name.")
    version: str = Field(..., description="Conversion tool version.")
    completed_at: str | None = Field(default=None, description="ISO timestamp.")


class InputManifest(BaseModel):
    """Input manifest listing produced parquet tables and conversion semantics."""

    model_config = ConfigDict(extra="forbid")

    manifest_version: str = Field(..., description="Manifest schema version.")
    etl_number: int = Field(..., description="ETL number for this run.")
    scdm_version: str = Field(..., description="SCDM version string.")
    semantic_profile: SemanticProfile
    tables: dict[str, TableEntry] = Field(..., description="Mapping of table name to table entry.")
    conversion: ConversionMeta | None = Field(
        default=None, description="Optional conversion metadata."
    )

    @field_validator("manifest_version")
    @classmethod
    def validate_manifest_version(cls, v: str) -> str:
        if v not in SUPPORTED_MANIFEST_VERSIONS:
            raise ValueError(
                f"Unsupported manifest_version {v!r}; "
                f"supported: {sorted(SUPPORTED_MANIFEST_VERSIONS)}"
            )
        return v

    @model_validator(mode="after")
    def validate_tables_nonempty(self) -> InputManifest:
        if not self.tables:
            raise ValueError("manifest must list at least one table")
        return self


# ---------------------------------------------------------------------------
# Manifest loading and path resolution
# ---------------------------------------------------------------------------


def load_input_manifest(path: str | Path) -> tuple[InputManifest, Path]:
    """Load an InputManifest from a YAML file.

    Returns the manifest and the resolved manifest file parent directory
    (for relative-path resolution).

    Raises FileNotFoundError if the file does not exist.
    Raises ValueError if the content is invalid.
    """
    p = Path(path).resolve()
    if not p.exists():
        raise FileNotFoundError(f"Input manifest not found: {p}")
    with p.open() as f:
        data = yaml.safe_load(f)
    if data is None:
        raise ValueError(f"Input manifest is empty: {p}")
    manifest = InputManifest.model_validate(data)
    return manifest, p.parent


def resolve_table_path(table_name: str, entry: TableEntry, manifest_parent: Path) -> Path:
    """Resolve a table entry's path.

    Absolute paths are used unchanged.
    Relative paths are resolved relative to the manifest parent directory.
    """
    raw = Path(entry.path)
    if raw.is_absolute():
        return raw
    return (manifest_parent / raw).resolve()


def validate_table_paths(
    manifest: InputManifest, manifest_parent: Path, check_exists: bool = True
) -> dict[str, Path]:
    """Validate and resolve all table paths in the manifest.

    Returns a mapping of table name to resolved Path.

    If check_exists is True, raises FileNotFoundError naming the table and path
    for any missing file.
    """
    resolved: dict[str, Path] = {}
    for name, entry in manifest.tables.items():
        p = resolve_table_path(name, entry, manifest_parent)
        resolved[name] = p
        if check_exists and not p.exists():
            raise FileNotFoundError(f"Table '{name}' path does not exist: {p}")
    return resolved


def validate_etl_consistency(config_etl: int, manifest_etl: int) -> None:
    """Validate that config and manifest ETL numbers match.

    Raises ValueError with both values if they differ.
    """
    if config_etl != manifest_etl:
        raise ValueError(f"ETL number mismatch: config={config_etl}, manifest={manifest_etl}")


def validate_required_tables(
    manifest: InputManifest,
    required_tables: dict[str, list[str]],
) -> None:
    """Validate that all required tables are present in the manifest.

    Args:
        manifest: The input manifest.
        required_tables: Mapping of table name → list of dependent check IDs.

    Raises ValueError naming the missing table and dependent check(s).
    """
    missing: list[str] = []
    for table_name, check_ids in required_tables.items():
        if table_name not in manifest.tables:
            missing.append(
                f"Required table '{table_name}' "
                f"(needed by checks: {', '.join(check_ids)}) "
                f"is absent from the manifest"
            )
    if missing:
        raise ValueError("Missing required table(s):\n" + "\n".join(missing))


# ---------------------------------------------------------------------------
# Run manifest
# ---------------------------------------------------------------------------


class CheckOutcome(BaseModel):
    """Placeholder for per-check outcome (populated by runner in NUM-32)."""

    model_config = ConfigDict(extra="forbid")

    check_id: str
    level: int
    status: str = Field(
        default="pending",
        description="pending | completed | disabled | skipped | aborted",
    )
    flag_count: int = 0


class RunManifest(BaseModel):
    """Run manifest recording provenance and outcomes for a qa-mil run."""

    model_config = ConfigDict(extra="allow")

    package_version: str = Field(..., description="qa-mil package version.")
    request: dict[str, str] = Field(..., description="Request identity tokens.")
    request_id: str = Field(..., description="Derived lowercase request ID.")
    config: dict[str, Any] = Field(..., description="Resolved configuration.")
    input_manifest: str = Field(..., description="Path to the input manifest.")
    manifest_version: str = Field(..., description="Input manifest version.")
    etl_number: int = Field(..., description="ETL number.")
    scdm_version: str = Field(..., description="SCDM version.")
    semantic_profile: dict[str, str] = Field(..., description="Semantic profile.")
    conversion: dict[str, Any] | None = Field(
        default=None, description="Optional conversion metadata."
    )
    check_selection: dict[str, Any] = Field(..., description="Enabled/disabled checks.")
    check_outcomes: list[CheckOutcome] = Field(
        default_factory=list,
        description="Per-check outcomes (populated by runner).",
    )
    flag_counts: dict[str, int] = Field(
        default_factory=dict,
        description="Flag counts by output scope.",
    )

    def to_yaml(self) -> str:
        """Serialize to YAML string."""
        return yaml.dump(
            self.model_dump(mode="json"),
            default_flow_style=False,
            sort_keys=True,
        )

    @classmethod
    def from_yaml(cls, yaml_str: str) -> RunManifest:
        """Deserialize from YAML string."""
        data = yaml.safe_load(yaml_str)
        return cls.model_validate(data)
