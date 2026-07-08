"""dplocal output writer — patient-level flag detail."""

from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


def write_dplocal_flags(tables: list[pa.Table], output_dir: Path) -> Path:
    """Write consolidated dplocal flags to parquet.

    Preserves all check-result columns (including patient/detail keys like
    MPatID, CPatID, EncounterID) so flagged records can be identified.

    Args:
        tables: List of Arrow tables from check results (may have different schemas).
        output_dir: Output directory root.

    Returns path to the written parquet file.
    """
    dplocal_dir = output_dir / "dplocal"
    dplocal_dir.mkdir(parents=True, exist_ok=True)

    if not tables:
        # Write empty schema
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
        out_path = dplocal_dir / "flags.parquet"
        pq.write_table(empty, out_path)
        return out_path

    # Align schemas: collect all columns across all tables, fill missing with null
    all_fields: dict[str, pa.DataType] = {}
    for tbl in tables:
        for field in tbl.schema:
            # Prefer the first type seen for each column
            if field.name not in all_fields:
                all_fields[field.name] = field.type

    unified_schema = pa.schema(
        [pa.field(name, dtype) for name, dtype in sorted(all_fields.items())]
    )

    aligned: list[pa.Table] = []
    for tbl in tables:
        columns = {}
        for field in unified_schema:
            if field.name in tbl.column_names:
                columns[field.name] = tbl[field.name]
            else:
                columns[field.name] = pa.nulls(len(tbl), type=field.type)
        aligned.append(pa.table(columns, schema=unified_schema))

    combined = pa.concat_tables(aligned)
    out_path = dplocal_dir / "flags.parquet"
    pq.write_table(combined, out_path)
    return out_path
