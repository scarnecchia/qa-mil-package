"""Spark backend engine session (NUM-46).

Mirrors the EngineSession protocol from base.py. Uses PySpark to register
parquet tables and execute Ibis expressions via the Spark backend.

Tests should be marked to skip if PySpark is not installed.
"""

from __future__ import annotations

import contextlib
from collections.abc import Mapping
from pathlib import Path
from typing import Any

import ibis


class SparkSession:
    """Spark-backed Ibis engine session.

    Mirrors the DuckDbSession API. Requires PySpark to be installed.
    """

    def __init__(
        self,
        table_paths: Mapping[str, Path],
        *,
        options: Mapping[str, str] | None = None,
    ) -> None:
        self.backend_name = "spark"
        self._options = dict(options or {})
        self._conn = self._open_connection()
        self._registered: set[str] = set()

        for key, path in table_paths.items():
            self._register_table(key, path)

    def _open_connection(self) -> Any:
        """Open a Spark-backed Ibis connection."""
        try:
            from pyspark.sql import SparkSession as PySparkSession  # type: ignore[import-not-found]

            builder = PySparkSession.builder.appName("qa-mil")
            if "memory_limit" in self._options:
                builder = builder.config("spark.driver.memory", self._options["memory_limit"])
            if "temp_directory" in self._options:
                builder = builder.config("spark.sql.warehouse.dir", self._options["temp_directory"])
            spark = builder.getOrCreate()
            return ibis.pyspark.from_session(spark)
        except ImportError as e:
            raise ImportError(
                "PySpark is required for the Spark backend. Install with: pip install pyspark"
            ) from e

    def _register_table(self, key: str, path: Path) -> None:
        """Register a parquet table under its manifest key."""
        key_lower = key.lower()
        raw_path = str(path)
        try:
            self._conn.read_parquet(raw_path, table_name=key_lower)
            self._registered.add(key_lower)
        except Exception as e:
            raise FileNotFoundError(
                f"Table '{key}' parquet registration failed at path '{raw_path}': {e}"
            ) from e

    def table(self, name: str) -> ibis.Table:
        name_lower = name.lower()
        if name_lower not in self._registered:
            raise KeyError(
                f"Table '{name}' is not registered. Available: {sorted(self._registered)}"
            )
        return self._conn.table(name_lower)

    def tables(self) -> dict[str, ibis.Table]:
        return {key: self._conn.table(key) for key in self._registered}

    def execute(self, expr: Any) -> Any:  # noqa: ANN401
        return self._conn.execute(expr)

    def close(self) -> None:
        self._registered.clear()
        with contextlib.suppress(Exception):
            self._conn.disconnect()

    def __enter__(self) -> SparkSession:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()
