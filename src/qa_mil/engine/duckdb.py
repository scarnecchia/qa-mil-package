"""DuckDB/Ibis engine session."""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Any

import ibis


class DuckDbSession:
    """DuckDB-backed Ibis engine session.

    Registers parquet tables lazily and executes Ibis expressions against them.
    """

    def __init__(
        self,
        table_paths: Mapping[str, Path],
        *,
        options: Mapping[str, str] | None = None,
    ) -> None:
        self.backend_name = "duckdb"
        self._options = dict(options or {})
        self._conn = self._open_connection()
        self._registered: set[str] = set()

        # Register all manifest tables up front (fail fast on unreadable parquet)
        for key, path in table_paths.items():
            self._register_table(key, path)

    def _open_connection(self) -> ibis.BaseBackend:
        """Open a DuckDB connection with configured options."""
        import duckdb

        config: dict[str, str | bool | int | float | list[str]] = {}
        # Map our config keys to DuckDB SET commands
        if "memory_limit" in self._options:
            config["memory_limit"] = self._options["memory_limit"]
        if "temp_directory" in self._options:
            # Ensure temp directory exists
            Path(self._options["temp_directory"]).mkdir(parents=True, exist_ok=True)
            config["temp_directory"] = self._options["temp_directory"]
        if "threads" in self._options:
            config["threads"] = int(self._options["threads"])

        # Create DuckDB connection with config
        conn = duckdb.connect(config=config) if config else duckdb.connect()
        return ibis.duckdb.from_connection(conn)

    def _register_table(self, key: str, path: Path) -> None:
        """Register a single parquet table under its manifest key.

        Raises FileNotFoundError with table key and path if the parquet is unreadable.
        """
        key_lower = key.lower()
        raw_path = str(path)
        try:
            # Use read_parquet for lazy registration via DuckDB's parquet scanner.
            self._conn.read_parquet(raw_path, table_name=key_lower)
            self._registered.add(key_lower)
        except Exception as e:
            raise FileNotFoundError(
                f"Table '{key}' parquet registration failed at path '{raw_path}': {e}"
            ) from e

    def table(self, name: str) -> ibis.Table:
        """Get an Ibis table by manifest key."""
        name_lower = name.lower()
        if name_lower not in self._registered:
            raise KeyError(
                f"Table '{name}' is not registered. Available: {sorted(self._registered)}"
            )
        return self._conn.table(name_lower)

    def tables(self) -> Mapping[str, ibis.Table]:
        """Get all registered tables."""
        return {key: self._conn.table(key) for key in self._registered}

    def execute(self, expr: ibis.expr.Expr) -> Any:  # noqa: ANN401
        """Execute an Ibis expression and materialize results."""
        return self._conn.execute(expr)

    def close(self) -> None:
        """Close the connection and release resources."""
        self._conn.disconnect()
        self._registered.clear()

    def __enter__(self) -> DuckDbSession:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()
