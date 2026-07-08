"""Check framework — enums, flag schema, flagid helper, and base protocol."""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from typing import Any, Protocol, runtime_checkable

import ibis


class Severity(StrEnum):
    """Check severity: Warn continues after failing rows, Abort stops execution."""

    WARN = "Warn"
    ABORT = "Abort"


def flag_type_to_severity(flag_type: str) -> Severity:
    """Map a CheckFlagDef flag_type ('Warn'/'Abort') to a Severity enum.

    Raises ValueError for any value other than 'Warn' or 'Abort'.
    """
    if flag_type == "Abort":
        return Severity.ABORT
    if flag_type == "Warn":
        return Severity.WARN
    raise ValueError(f"flag_type must be 'Warn' or 'Abort', got {flag_type!r}")


def validate_flag_def_identity(
    flag_def_check_id: str,
    flag_def_level: int,
    flag_def_tabid: str,
    flag_def_varid: str,
    *,
    expected_check_id: str,
    expected_level: int,
    expected_tabid: str,
) -> None:
    """Validate that a CheckFlagDef row matches the expected check identity.

    Raises ValueError with all mismatches listed.
    """
    errors: list[str] = []
    if flag_def_check_id != expected_check_id:
        errors.append(f"check_id={flag_def_check_id!r} (expected {expected_check_id!r})")
    if flag_def_level != expected_level:
        errors.append(f"level={flag_def_level} (expected {expected_level})")
    if flag_def_tabid.upper() != expected_tabid.upper():
        errors.append(f"tabid={flag_def_tabid!r} (expected {expected_tabid!r})")
    if flag_def_varid != "00":
        errors.append(f'varid={flag_def_varid!r} (expected "00")')
    if errors:
        raise ValueError(f"flag_def mismatch: {'; '.join(errors)}")


class OutputScope(StrEnum):
    """Output destination: dplocal for patient-level, msoc for aggregate."""

    DPLOCAL = "dplocal"
    MSOC = "msoc"


def make_flagid(tabid: str, level: int, varid: str, checknum: str | int) -> str:
    """Generate an exact SAS-compatible flagid.

    Format: ``{TABID}_{level}_{varid}_00-0_{checknum}``

    Args:
        tabid: Table identifier (uppercased to match SAS).
        level: Check level (1, 2, or 3).
        varid: Variable ID for variable-level checks, or "00" for table-level.
        checknum: Check number.

    Examples:
        >>> make_flagid("MIL", 3, "00", 371)
        'MIL_3_00_00-0_371'
        >>> make_flagid("MIL", 1, "MPATID", 110)
        'MIL_1_MPATID_00-0_110'
    """
    return f"{tabid.upper()}_{level}_{varid}_00-0_{checknum}"


@dataclass(frozen=True)
class CheckMetadata:
    """Static metadata for a logical check."""

    check_id: str
    level: int
    severity: Severity
    tables: frozenset[str]
    output_scope: OutputScope
    description: str
    tabid: str
    enabled_by_default: bool = True


@dataclass(frozen=True)
class FlagRow:
    """Canonical internal flag row schema."""

    flagid: str
    flag_descr: str
    message: str
    flag_type: str
    abort_yn: str


@dataclass
class CheckContext:
    """Context passed to check build methods."""

    session: Any  # EngineSession
    metadata: CheckMetadata


@runtime_checkable
class Check(Protocol):
    """Check protocol — declare metadata and implement expression-building logic."""

    metadata: CheckMetadata

    def build(self, ctx: CheckContext) -> ibis.Table: ...


def expand_checks(checks: list[Check]) -> list[Check]:
    """Expand parameterized checks into logical check instances.

    Currently returns checks as-is since each Check is already a logical check.
    Override or extend for checks that represent multiple logical checks.
    """
    return checks
