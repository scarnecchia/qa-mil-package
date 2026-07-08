"""Tests for Spark backend (NUM-46) and backend equivalence (NUM-47).

Tests skip gracefully if PySpark is not installed.
"""

from __future__ import annotations

import tomllib
from pathlib import Path

import pytest

from tests.conftest import write_parquet

pyspark_available = True
try:
    import pyspark  # type: ignore[import-not-found] # noqa: F401
except ImportError:
    pyspark_available = False

spark_skip = pytest.mark.skipif(
    not pyspark_available,
    reason="PySpark not installed — Spark tests are integration tests",
)


def test_project_declares_spark_extra() -> None:
    """Spark backend users should have an installable optional dependency extra."""
    project = tomllib.loads(Path("pyproject.toml").read_text())

    assert "ibis-framework[pyspark]>=9.0" in project["project"]["optional-dependencies"]["spark"]


@pytest.mark.skipif(pyspark_available, reason="only checks missing-dependency guidance")
def test_spark_factory_error_mentions_project_extra(tmp_path: Path) -> None:
    """Missing Spark dependencies should tell users how to install the backend."""
    from qa_mil.engine.base import create_session

    paths = _write_test_parquets(tmp_path)

    with pytest.raises(ImportError, match="qa-mil\\[spark\\]"):
        create_session(paths, backend="spark")


def _write_test_parquets(tmp_path: Path) -> dict[str, Path]:
    """Create MIL and ENR parquet files for testing."""
    mil_path = tmp_path / "mil.parquet"
    write_parquet(
        mil_path,
        {
            "MPatID": ["M001", "M002", "M003"],
            "CPatID": ["C001", "C002", "C003"],
            "ADate": ["2020-01-15", "2020-02-20", "2020-03-10"],
            "EncounterID": ["E1", "E2", "E3"],
            "Birth_Type": [1, 2, 3],
        },
    )
    return {"mil": mil_path}


@spark_skip
class TestSparkBackend:
    def test_session_creates(self, tmp_path: Path) -> None:
        from qa_mil.engine.spark import SparkSession

        paths = _write_test_parquets(tmp_path)
        with SparkSession(paths) as session:
            assert session.backend_name == "spark"
            assert "mil" in session.tables()

    def test_table_access(self, tmp_path: Path) -> None:
        from qa_mil.engine.spark import SparkSession

        paths = _write_test_parquets(tmp_path)
        with SparkSession(paths) as session:
            tbl = session.table("mil")
            assert "MPatID" in tbl.columns

    def test_row_count(self, tmp_path: Path) -> None:
        from qa_mil.engine.spark import SparkSession

        paths = _write_test_parquets(tmp_path)
        with SparkSession(paths) as session:
            result = session.execute(session.table("mil").count())
            assert int(result) == 3

    def test_filter(self, tmp_path: Path) -> None:
        from qa_mil.engine.spark import SparkSession

        paths = _write_test_parquets(tmp_path)
        with SparkSession(paths) as session:
            tbl = session.table("mil")
            result = session.execute(tbl.filter(tbl["Birth_Type"] == 2))
            assert len(result) == 1


class TestBackendEquivalence:
    """Backend equivalence tests compare DuckDB and Spark outputs.

    These tests skip if Spark is not available.
    """

    @spark_skip
    def test_duckdb_spark_same_row_count(self, tmp_path: Path) -> None:
        from qa_mil.engine.duckdb import DuckDbSession
        from qa_mil.engine.spark import SparkSession

        paths = _write_test_parquets(tmp_path)

        with DuckDbSession(paths) as duckdb_session:
            duckdb_count = int(duckdb_session.execute(duckdb_session.table("mil").count()))

        with SparkSession(paths) as spark_session:
            spark_count = int(spark_session.execute(spark_session.table("mil").count()))

        assert duckdb_count == spark_count

    def test_backend_selection_is_config_only(self, tmp_path: Path) -> None:
        """Backend selection should be config-only, not code-level."""
        from qa_mil.engine.base import create_session

        paths = _write_test_parquets(tmp_path)

        # DuckDB always works
        session = create_session(paths, backend="duckdb")
        assert session.backend_name == "duckdb"
        session.close()

    @spark_skip
    def test_backend_factory_creates_spark(self, tmp_path: Path) -> None:
        """The shared engine factory should route Spark configs to SparkSession."""
        from qa_mil.engine.base import create_session

        paths = _write_test_parquets(tmp_path)

        session = create_session(paths, backend="spark")
        try:
            assert session.backend_name == "spark"
            assert "mil" in session.tables()
        finally:
            session.close()

    def test_no_backend_specific_check_forks(self) -> None:
        """Check code should not contain backend-specific conditionals."""
        # Check source for backend-specific conditionals
        import inspect

        import qa_mil.checks.level1.checks as l1
        import qa_mil.checks.level2.checks as l2
        import qa_mil.checks.level3.birth_type as l3_bt
        import qa_mil.checks.level3.linkage_checks as l3_lc

        for module in [l1, l2, l3_bt, l3_lc]:
            source = inspect.getsource(module)
            # No backend-specific conditionals should exist in check code
            assert "backend_name" not in source or "backend" not in source.lower().replace(
                "backend_name", ""
            ), f"Backend-specific conditional found in {module.__name__}"
