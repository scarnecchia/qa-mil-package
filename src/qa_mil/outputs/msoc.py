"""msoc output writer — aggregate results with identifier guard."""

from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq

# Patient-level identifier columns that must never appear in msoc output.
_FORBIDDEN_COLUMNS = {"mpatid", "cpatid", "patid", "encounterid"}


def check_identifier_columns(schema: pa.Schema) -> None:
    """Raise ValueError if any patient-level identifier column is present.

    Check is case-insensitive.
    """
    column_names_lower = {name.lower() for name in schema.names}
    offending = column_names_lower & _FORBIDDEN_COLUMNS
    if offending:
        # Find original-casing column names for the error message
        original_names = [name for name in schema.names if name.lower() in offending]
        raise ValueError(
            f"msoc output must not contain patient-level identifier columns. "
            f"Found forbidden columns: {original_names}"
        )


def write_msoc_flags(tables: list[pa.Table], output_dir: Path) -> Path:
    """Write consolidated msoc flags to parquet.

    Rejects tables containing patient-level identifier columns.

    Args:
        tables: List of Arrow tables from check results.
        output_dir: Output directory root.

    Returns path to the written parquet file.
    """
    msoc_dir = output_dir / "msoc"
    msoc_dir.mkdir(parents=True, exist_ok=True)

    if not tables:
        schema = pa.schema(
            [
                ("flagid", pa.string()),
                ("flag_descr", pa.string()),
                ("message", pa.string()),
                ("flag_type", pa.string()),
                ("abort_yn", pa.string()),
            ]
        )
        empty = pa.table({col: pa.array([], type=schema.field(col).type) for col in schema.names})
        out_path = msoc_dir / "flags.parquet"
        pq.write_table(empty, out_path)
        return out_path

    # Guard: reject identifier columns
    for tbl in tables:
        check_identifier_columns(tbl.schema)

    combined = pa.concat_tables(tables)
    out_path = msoc_dir / "flags.parquet"
    pq.write_table(combined, out_path)
    return out_path


def write_msoc_table(table: pa.Table, output_dir: Path, name: str) -> Path:
    """Write a named msoc output table (for aggregate datasets).

    Rejects tables containing patient-level identifier columns.
    """
    check_identifier_columns(table.schema)
    msoc_dir = output_dir / "msoc"
    msoc_dir.mkdir(parents=True, exist_ok=True)
    out_path = msoc_dir / f"{name}.parquet"
    pq.write_table(table, out_path)
    return out_path
