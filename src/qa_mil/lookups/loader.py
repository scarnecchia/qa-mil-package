"""Loader for JSON lookup data (NUM-34).

Loads deterministic JSON files from src/qa_mil/lookups/ and validates them
through typed models. Fails clearly on duplicate keys, missing required fields,
unknown severities, invalid levels, and inconsistent check IDs.
"""

from __future__ import annotations

import json
from pathlib import Path

from qa_mil.lookups.models import (
    CheckFlagDef,
    IdLength,
    L1VariableRule,
    LookupData,
    VariableLength,
)

_LOOKUP_DIR = Path(__file__).parent


def _load_json(filename: str) -> list[dict]:
    """Load a JSON file from the lookup directory."""
    path = _LOOKUP_DIR / filename
    with path.open() as f:
        data = json.load(f)
    if not isinstance(data, list):
        raise ValueError(f"{filename} must contain a JSON array")
    return data


def _validate_no_duplicate_ids(items: list[dict], id_field: str, filename: str) -> None:
    """Check for duplicate IDs in a list of dicts."""
    seen: set[str] = set()
    for item in items:
        item_id = str(item.get(id_field, ""))
        if item_id in seen:
            raise ValueError(f"Duplicate {id_field}={item_id!r} found in {filename}")
        seen.add(item_id)


def load_check_flags() -> list[CheckFlagDef]:
    """Load and validate check flag definitions from checks.json."""
    raw = _load_json("checks.json")
    # Validate no duplicate check_id within same tabid+varid
    seen: set[str] = set()
    for item in raw:
        key = f"{item.get('tabid', '')}_{item.get('varid', '')}_{item.get('check_id', '')}"
        if key in seen:
            raise ValueError(f"Duplicate check definition: {key} in checks.json")
        seen.add(key)
    return [CheckFlagDef.model_validate(item) for item in raw]


def load_l1_rules() -> list[L1VariableRule]:
    """Load and validate Level 1 variable rules from level1_rules.json."""
    raw = _load_json("level1_rules.json")
    seen: set[str] = set()
    for item in raw:
        key = f"{item.get('tabid', '')}_{item.get('varid', '')}"
        if key in seen:
            raise ValueError(
                f"Duplicate varid={item.get('varid', '')!r} for "
                f"tabid={item.get('tabid', '')!r} in level1_rules.json"
            )
        seen.add(key)
    return [L1VariableRule.model_validate(item) for item in raw]


def load_variable_lengths() -> list[VariableLength]:
    """Load variable lengths from variable_lengths.json."""
    raw = _load_json("variable_lengths.json")
    return [VariableLength.model_validate(item) for item in raw]


def load_id_lengths() -> list[IdLength]:
    """Load ID lengths from id_lengths.json."""
    raw = _load_json("id_lengths.json")
    return [IdLength.model_validate(item) for item in raw]


def load_all() -> LookupData:
    """Load all lookup data and return a validated LookupData container."""
    return LookupData(
        check_flags=load_check_flags(),
        l1_rules=load_l1_rules(),
        variable_lengths=load_variable_lengths(),
        id_lengths=load_id_lengths(),
    )
