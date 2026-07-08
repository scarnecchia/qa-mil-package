"""Engine session protocol — backend abstraction seam."""

from __future__ import annotations

from collections.abc import Mapping
from pathlib import Path
from typing import Any, Protocol, runtime_checkable

import ibis


@runtime_checkable
class EngineSession(Protocol):
    """Abstract engine session that Spark can mirror later."""

    backend_name: str

    def table(self, name: str) -> ibis.Table: ...
    def tables(self) -> Mapping[str, ibis.Table]: ...
    def execute(self, expr: ibis.expr.Expr) -> Any: ...  # noqa: ANN401
    def close(self) -> None: ...


def create_session(
    table_paths: Mapping[str, Path],
    *,
    backend: str = "duckdb",
    options: Mapping[str, str] | None = None,
) -> EngineSession:
    """Factory: create an engine session from resolved table paths.

    Args:
        table_paths: Mapping of table key → resolved parquet path.
        backend: Backend name ("duckdb" or "spark").
        options: Backend-specific options.

    Returns an EngineSession instance.
    """
    if backend == "duckdb":
        from qa_mil.engine.duckdb import DuckDbSession

        return DuckDbSession(table_paths, options=dict(options or {}))
    raise ValueError(f"Unsupported backend: {backend!r}")
