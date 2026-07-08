"""Static check registry."""

from __future__ import annotations

from typing import Any

from qa_mil.checks.base import Check
from qa_mil.checks.level3.birth_type import BirthTypeLinkageCheck

# --- Registry of all checks ---
# Each entry is one logical check instance.
_registry: list[Any] = []


def _register(check: Any) -> None:
    """Register a check in the global registry."""
    _registry.append(check)


def list_checks() -> list[Check]:
    """Return all registered checks."""
    return list(_registry)


def enabled_checks(
    disabled_ids: list[str] | None = None,
    enabled_ids: list[str] | None = None,
) -> list[Check]:
    """Filter checks by config selection.

    Args:
        disabled_ids: Check IDs to exclude.
        enabled_ids: If non-empty, only include these check IDs.

    Returns filtered list of checks.
    """
    disabled_set = set(disabled_ids or [])
    all_checks = list_checks()

    if enabled_ids:
        enabled_set = set(enabled_ids)
        return [c for c in all_checks if c.metadata.check_id in enabled_set]

    return [c for c in all_checks if c.metadata.check_id not in disabled_set]


def disabled_checks(disabled_ids: list[str] | None = None) -> list[Check]:
    """Return checks that would be disabled by the given IDs."""
    disabled_set = set(disabled_ids or [])
    return [c for c in list_checks() if c.metadata.check_id in disabled_set]


def required_tables(
    disabled_ids: list[str] | None = None,
    enabled_ids: list[str] | None = None,
) -> dict[str, list[str]]:
    """Extract required tables from enabled checks.

    Returns mapping of table name → list of check IDs that require it.
    """
    checks = enabled_checks(disabled_ids, enabled_ids)
    tables: dict[str, list[str]] = {}
    for check in checks:
        for table in check.metadata.tables:
            tables.setdefault(table, []).append(check.metadata.check_id)
    return tables


def level_ordered_groups(
    disabled_ids: list[str] | None = None,
    enabled_ids: list[str] | None = None,
) -> list[list[Check]]:
    """Group enabled checks by level, ordered ascending.

    Returns a list of lists, one per level, each sorted by check_id.
    """
    checks = enabled_checks(disabled_ids, enabled_ids)
    if not checks:
        return []
    levels = sorted({c.metadata.level for c in checks})
    return [
        sorted(
            [c for c in checks if c.metadata.level == level],
            key=lambda c: c.metadata.check_id,
        )
        for level in levels
    ]


# --- Register Level 3 checks 371-375 ---
_TABID_MIL = "MIL"

for bt_value in range(1, 6):
    check_num = 370 + bt_value  # 371..375
    _register(
        BirthTypeLinkageCheck(
            birth_type=bt_value,
            tabid=_TABID_MIL,
        )
    )
