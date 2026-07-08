"""Tests for the DuckDB/Ibis engine layer (NUM-31)."""

from __future__ import annotations

from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from qa_mil.engine import EngineSession
from qa_mil.engine.base import create_session
from qa_mil.engine.duckdb import DuckDbSession

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------


def _write_parquet(path: Path, data: dict[str, list]) -> None:
    """Write a small parquet file from column-oriented dict data."""
    table = pa.table(data)
    pq.write_table(table, path)


@pytest.fixture
def mil_parquet(tmp_path: Path) -> Path:
    p = tmp_path / "mil.parquet"
    _write_parquet(
        p,
        {
            "MPatID": ["P001", "P002", "P003", "P004"],
            "Birth_Type": [1, 2, 3, 2],
            "Birth_Date": ["2020-01-15", "2020-03-20", "2020-06-10", "2020-09-05"],
            "AgeGroup": ["0-1", "0-1", "0-1", "0-1"],
        },
    )
    return p


@pytest.fixture
def enr_parquet(tmp_path: Path) -> Path:
    p = tmp_path / "enr.parquet"
    _write_parquet(
        p,
        {
            "MPatID": ["P001", "P002", "P003", "P004"],
            "EnrStart": ["2020-01-01", "2020-01-01", "2020-01-01", "2020-01-01"],
            "EnrEnd": ["2020-12-31", "2020-12-31", "2020-12-31", "2020-12-31"],
        },
    )
    return p


@pytest.fixture
def table_paths(mil_parquet: Path, enr_parquet: Path) -> dict[str, Path]:
    return {"mil": mil_parquet, "enr": enr_parquet}


# ---------------------------------------------------------------------------
# Registration and protocol
# ---------------------------------------------------------------------------


class TestTableRegistration:
    def test_session_is_engine_session_protocol(self, table_paths: dict[str, Path]) -> None:
        session = DuckDbSession(table_paths)
        assert isinstance(session, EngineSession)
        session.close()

    def test_backend_name(self, table_paths: dict[str, Path]) -> None:
        session = DuckDbSession(table_paths)
        assert session.backend_name == "duckdb"
        session.close()

    def test_registers_manifest_tables(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            assert tbl is not None
            assert "MPatID" in tbl.columns

    def test_registers_stable_file_row_number(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            assert "file_row_number" in tbl.columns
            result = session.execute(
                tbl.select("MPatID", "file_row_number").order_by("file_row_number")
            )
            assert result["MPatID"].tolist() == ["P001", "P002", "P003", "P004"]
            assert result["file_row_number"].tolist() == [0, 1, 2, 3]

    def test_tables_exposed_by_manifest_key(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            all_tables = session.tables()
            assert set(all_tables.keys()) == {"mil", "enr"}
            assert "MPatID" in all_tables["mil"].columns
            assert "EnrStart" in all_tables["enr"].columns

    def test_unknown_table_raises(self, table_paths: dict[str, Path]) -> None:
        with (
            DuckDbSession(table_paths) as session,
            pytest.raises(KeyError, match="nonexistent"),
        ):
            session.table("nonexistent")

    def test_table_keys_are_case_insensitive(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("MIL")
            assert tbl is not None


# ---------------------------------------------------------------------------
# Expression execution
# ---------------------------------------------------------------------------


class TestExpressionExecution:
    def test_row_count(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            result = session.execute(tbl.count())
            assert int(result) == 4

    def test_projection(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            result = session.execute(tbl.select("MPatID", "Birth_Type"))
            assert "MPatID" in result.columns
            assert "Birth_Type" in result.columns
            assert len(result) == 4

    def test_filter(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            result = session.execute(tbl.filter(tbl["Birth_Type"] == 2))
            assert len(result) == 2

    def test_group_by_aggregation(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            result = session.execute(tbl.group_by("Birth_Type").aggregate(count=tbl.count()))
            result = result.sort_values("Birth_Type").reset_index(drop=True)
            assert set(result["Birth_Type"].tolist()) == {1, 2, 3}
            assert result[result["Birth_Type"] == 2]["count"].iloc[0] == 2


# ---------------------------------------------------------------------------
# Path semantics
# ---------------------------------------------------------------------------


class TestPathSemantics:
    def test_absolute_paths(self, table_paths: dict[str, Path]) -> None:
        # table_paths uses absolute paths by default from tmp_path
        with DuckDbSession(table_paths) as session:
            tbl = session.table("mil")
            assert session.execute(tbl.count()) == 4

    def test_manifest_relative_paths(
        self, tmp_path: Path, mil_parquet: Path, enr_parquet: Path
    ) -> None:
        # Simulate manifest-relative resolution: use paths relative to a "manifest_parent"
        manifest_parent = tmp_path / "manifests"
        manifest_parent.mkdir()
        # Copy parquet files into manifest_parent
        mil_dest = manifest_parent / "mil.parquet"
        enr_dest = manifest_parent / "enr.parquet"
        mil_dest.write_bytes(mil_parquet.read_bytes())
        enr_dest.write_bytes(enr_parquet.read_bytes())

        # Pass resolved relative paths (as the manifest layer would produce)
        table_paths = {"mil": mil_dest, "enr": enr_dest}
        with DuckDbSession(table_paths) as session:
            assert session.execute(session.table("mil").count()) == 4
            assert session.execute(session.table("enr").count()) == 4


# ---------------------------------------------------------------------------
# Error handling
# ---------------------------------------------------------------------------


class TestErrorHandling:
    def test_unreadable_parquet_names_table_and_path(self, tmp_path: Path) -> None:
        bad_path = tmp_path / "bad.parquet"
        bad_path.write_text("not a parquet file")
        with pytest.raises(FileNotFoundError, match="Table 'bad'.*bad.parquet"):
            DuckDbSession({"bad": bad_path})

    def test_missing_parquet_file_names_table_and_path(self, tmp_path: Path) -> None:
        missing_path = tmp_path / "nonexistent.parquet"
        with pytest.raises(FileNotFoundError, match="Table 'missing'.*nonexistent.parquet"):
            DuckDbSession({"missing": missing_path})


# ---------------------------------------------------------------------------
# DuckDB options
# ---------------------------------------------------------------------------


class TestDuckDbOptions:
    def test_memory_limit_and_temp_dir_applied(
        self, table_paths: dict[str, Path], tmp_path: Path
    ) -> None:
        temp_dir = tmp_path / "duckdb_temp"
        session = DuckDbSession(
            table_paths,
            options={"memory_limit": "512MB", "temp_directory": str(temp_dir)},
        )
        # Verify the temp directory was created
        assert temp_dir.exists()
        # Verify execution still works with options
        result = session.execute(session.table("mil").count())
        assert int(result) == 4
        session.close()

    def test_threads_option(self, table_paths: dict[str, Path]) -> None:
        session = DuckDbSession(table_paths, options={"threads": "1"})
        result = session.execute(session.table("mil").count())
        assert int(result) == 4
        session.close()

    def test_low_memory_spill_smoke(self, tmp_path: Path) -> None:
        """Spill smoke test: small memory limit with enough data to exercise the setting."""
        # Generate enough rows to potentially trigger spilling with 128MB limit
        n = 500_000
        import random

        random.seed(42)
        data = {
            "id": list(range(n)),
            "category": [random.randint(0, 99) for _ in range(n)],
            "value": [random.random() for _ in range(n)],
        }
        p = tmp_path / "big.parquet"
        table = pa.table(data)
        pq.write_table(table, p)

        temp_dir = tmp_path / "spill_temp"
        session = DuckDbSession(
            {"big": p},
            options={"memory_limit": "128MB", "temp_directory": str(temp_dir)},
        )
        # Aggregation that may need to spill
        tbl = session.table("big")
        result = session.execute(
            tbl.group_by("category").aggregate(
                count=tbl.count(),
                avg_value=tbl["value"].mean(),  # type: ignore[attr-defined]
            )
        )
        assert len(result) == 100
        session.close()


# ---------------------------------------------------------------------------
# Session lifecycle
# ---------------------------------------------------------------------------


class TestSessionLifecycle:
    def test_close_releases_resources(self, table_paths: dict[str, Path]) -> None:
        session = DuckDbSession(table_paths)
        session.close()
        # After close, registered tables are cleared
        assert len(session._registered) == 0

    def test_context_manager_closes(self, table_paths: dict[str, Path]) -> None:
        with DuckDbSession(table_paths) as session:
            assert session.execute(session.table("mil").count()) == 4
        # After context exit, should be closed
        assert len(session._registered) == 0

    def test_create_session_factory(self, table_paths: dict[str, Path]) -> None:
        session = create_session(table_paths, backend="duckdb")
        assert session.backend_name == "duckdb"
        assert session.execute(session.table("mil").count()) == 4
        session.close()

    def test_create_session_unsupported_backend(self, table_paths: dict[str, Path]) -> None:
        with pytest.raises(ValueError, match="Unsupported backend"):
            create_session(table_paths, backend="oracle")
