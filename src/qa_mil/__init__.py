"""QA MIL package - Python port of the SCDM MIL data QA review package."""

from __future__ import annotations

try:
    from importlib.metadata import version as _get_version

    __version__ = _get_version("qa-mil")
except Exception:  # pragma: no cover
    __version__ = "0.1.0"

__all__ = ["__version__"]
