"""Static check registry."""

from __future__ import annotations

from typing import Any

from qa_mil.checks.base import (
    Check,
    Severity,  # noqa: E402
)
from qa_mil.checks.level2.checks import (  # noqa: E402
    CrossTableConsistencyCheck,
    DateRangeCheck,
    DuplicateKeyCheck,
    EnrollmentCoverageCheck,
    ValueDomainCheck,
)
from qa_mil.checks.level3.birth_type import BirthTypeLinkageCheck
from qa_mil.lookups.loader import load_l1_rules  # noqa: E402

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


# --- Register Level 3 checks 394, 396, 397 ---
from qa_mil.checks.level3.linkage_checks import (  # noqa: E402
    BirthTypeNoLinkageCheck,
    InfantNotLinkedCheck,
    MotherNotLinkedCheck,
)

_register(BirthTypeNoLinkageCheck(tabid=_TABID_MIL))
_register(MotherNotLinkedCheck(tabid=_TABID_MIL))
_register(InfantNotLinkedCheck(tabid=_TABID_MIL))


# --- Register Level 1 checks ---
from qa_mil.checks.level1.checks import (  # noqa: E402
    AgeRangeCheck,
    MissingColumnCheck,
    NullValuesCheck,
    TableExistsCheck,
    TablePopulatedCheck,
    VariableLengthCheck,
    VariableNotPopulatedCheck,
    VariableTypeCheck,
)

# Table-level checks
_register(TableExistsCheck())
_register(TablePopulatedCheck())
# Check 102 (table sort order) is intentionally not registered: it depends on
# SAS physical/input row order, which is not a reliable parquet table invariant.

# Variable-level checks (parameterized from lookup rules)
_l1_rules = load_l1_rules()
for rule in _l1_rules:
    if rule.tabid.upper() != _TABID_MIL:
        continue
    _register(MissingColumnCheck(variable=rule.variable, varid=rule.varid))
    _register(VariableNotPopulatedCheck(variable=rule.variable, varid=rule.varid))
    _register(
        VariableTypeCheck(variable=rule.variable, varid=rule.varid, expected_type=rule.vartype)
    )
    if rule.varlength > 0:
        _register(
            VariableLengthCheck(
                variable=rule.variable, varid=rule.varid, expected_length=rule.varlength
            )
        )
    _register(NullValuesCheck(variable=rule.variable, varid=rule.varid))

# Special variable checks
_register(AgeRangeCheck())


# --- Register Level 2 checks ---

# NUM-40: Duplicate/key family
_register(DuplicateKeyCheck(check_id="211", key_columns=("MPatID", "CPatID", "ADate")))
_register(
    DuplicateKeyCheck(
        check_id="217", key_columns=("MPatID", "ADate", "EncounterID"), severity=Severity.ABORT
    )
)
_register(
    DuplicateKeyCheck(check_id="218", key_columns=("MPatID", "ADate"), severity=Severity.ABORT)
)
_register(DuplicateKeyCheck(check_id="219", key_columns=("CPatID",), severity=Severity.ABORT))

# NUM-41: Date/range/value-domain family
_register(
    DateRangeCheck(
        check_id="201", date_column="ADate", min_date="2010-01-01", max_date="2025-12-31"
    )
)
_register(
    ValueDomainCheck(check_id="204", variable="Birth_Type", allowed_values=(1, 2, 3, 4, 5, 6, 7, 8))
)

# NUM-42: Cross-table consistency family
_register(CrossTableConsistencyCheck(check_id="221", reference_table="enr", join_column="MPatID"))
_register(CrossTableConsistencyCheck(check_id="223", reference_table="enr", join_column="CPatID"))

# NUM-43: Enrollment/eligibility family
_register(EnrollmentCoverageCheck(check_id="200", date_column="ADate", severity=Severity.ABORT))
