"""Tests for output writers (dplocal/msoc) — NUM-32."""

from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pytest

from qa_mil.outputs.dplocal import write_dplocal_flags
from qa_mil.outputs.msoc import check_identifier_columns, write_msoc_flags, write_msoc_table


def _make_flag_table(rows: list[dict] | None = None) -> pa.Table:
    """Create a flag-shaped Arrow table."""
    if rows is None:
        rows = [
            {
                "flagid": "MIL_3_00_00-0_371",
                "flag_descr": "test",
                "message": "msg",
                "flag_type": "Warn",
                "abort_yn": "N",
            },
        ]
    return pa.table(
        {
            "flagid": [r["flagid"] for r in rows],
            "flag_descr": [r["flag_descr"] for r in rows],
            "message": [r["message"] for r in rows],
            "flag_type": [r["flag_type"] for r in rows],
            "abort_yn": [r["abort_yn"] for r in rows],
        }
    )


class TestDplocalWriter:
    def test_writes_parquet(self, tmp_path: Path) -> None:
        tbl = _make_flag_table()
        path = write_dplocal_flags([tbl], tmp_path)
        assert path.exists()
        assert path.name == "flags.parquet"
        assert path.parent.name == "dplocal"

    def test_empty_tables_writes_empty_parquet(self, tmp_path: Path) -> None:
        path = write_dplocal_flags([], tmp_path)
        assert path.exists()
        assert path.name == "flags.parquet"

    def test_concatenates_multiple_tables(self, tmp_path: Path) -> None:
        t1 = _make_flag_table(
            [
                {
                    "flagid": "MIL_3_00_00-0_371",
                    "flag_descr": "a",
                    "message": "m1",
                    "flag_type": "Warn",
                    "abort_yn": "N",
                },
            ]
        )
        t2 = _make_flag_table(
            [
                {
                    "flagid": "MIL_3_00_00-0_372",
                    "flag_descr": "b",
                    "message": "m2",
                    "flag_type": "Warn",
                    "abort_yn": "N",
                },
            ]
        )
        path = write_dplocal_flags([t1, t2], tmp_path)
        import pyarrow.parquet as pq

        read_back = pq.read_table(path)
        assert len(read_back) == 2


class TestMsocIdentifierGuard:
    @pytest.mark.parametrize(
        "col_name",
        [
            "MPatID",
            "CPatID",
            "PatID",
            "EncounterID",
            "mpatid",
            "cpatid",
            "patid",
            "encounterid",
            "MPATID",
            "CPATID",
            "PATID",
            "ENCOUNTERID",
        ],
    )
    def test_rejects_identifier_column(self, col_name: str) -> None:
        schema = pa.schema([("flagid", pa.string()), (col_name, pa.string())])
        with pytest.raises(ValueError, match="forbidden columns"):
            check_identifier_columns(schema)

    def test_allows_clean_schema(self) -> None:
        schema = pa.schema(
            [
                ("flagid", pa.string()),
                ("flag_descr", pa.string()),
                ("count", pa.int64()),
            ]
        )
        check_identifier_columns(schema)  # should not raise

    def test_rejects_with_mixed_case(self) -> None:
        schema = pa.schema([("flagid", pa.string()), ("MpatId", pa.string())])
        with pytest.raises(ValueError, match="MpatId"):
            check_identifier_columns(schema)

    def test_writes_msoc_parquet(self, tmp_path: Path) -> None:
        tbl = pa.table(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "flag_descr": ["aggregate"],
                "count": [42],
            }
        )
        path = write_msoc_table(tbl, tmp_path, "test_agg")
        assert path.exists()
        assert path.name == "test_agg.parquet"

    def test_msoc_flags_writer_rejects_identifier(self, tmp_path: Path) -> None:
        tbl = pa.table(
            {
                "flagid": ["MIL_3_00_00-0_371"],
                "MPatID": ["P001"],
                "count": [1],
            }
        )
        with pytest.raises(ValueError, match="forbidden columns"):
            write_msoc_flags([tbl], tmp_path)

    def test_msoc_flags_writer_allows_clean(self, tmp_path: Path) -> None:
        tbl = _make_flag_table()
        path = write_msoc_flags([tbl], tmp_path)
        assert path.exists()
        assert path.parent.name == "msoc"
