"""dplocal output writer — patient-level flag detail."""

from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq


def write_dplocal_flags(tables: list[pa.Table], output_dir: Path) -> Path:
    """Write consolidated dplocal flags to parquet.

    Args:
        tables: List of Arrow tables from check results.
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

    # Concatenate all tables
    combined = pa.concat_tables(tables)
    out_path = dplocal_dir / "flags.parquet"
    pq.write_table(combined, out_path)
    return out_path
