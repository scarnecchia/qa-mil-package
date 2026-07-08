"""Typed models for lookup metadata (NUM-34).

These models validate the JSON lookup data at load time and expose normalized
objects without leaking SAS table structure.
"""

from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CheckFlagDef(BaseModel):
    """A single check flag definition from lkp_all_flags."""

    model_config = ConfigDict(extra="forbid", frozen=True)

    check_id: str = Field(..., description="Check number, e.g. '110'.")
    level: int = Field(..., description="Check level: 1, 2, or 3.")
    tabid: str = Field(..., description="Table ID, e.g. 'MIL'.")
    varid: str = Field(..., description="Variable ID, e.g. '01' or '00' for table-level.")
    flag_descr: str = Field(..., description="Flag description text.")
    flag_type: str = Field(..., description="Flag type: 'Warn' or 'Abort'.")
    abort_yn: str = Field(..., description="Abort indicator: 'Y' or 'N'.")
    flagyn: str = Field(default="Y", description="Whether flag is active: 'Y' or 'N'.")
    variable1: str = Field(default="", description="Variable name associated with this flag.")

    @field_validator("flag_type")
    @classmethod
    def validate_flag_type(cls, v: str) -> str:
        if v not in ("Warn", "Abort"):
            raise ValueError(f"flag_type must be 'Warn' or 'Abort', got {v!r}")
        return v

    @field_validator("abort_yn")
    @classmethod
    def validate_abort_yn(cls, v: str) -> str:
        v = v.upper()
        if v not in ("Y", "N"):
            raise ValueError(f"abort_yn must be 'Y' or 'N', got {v!r}")
        return v


class L1VariableRule(BaseModel):
    """A single Level 1 variable rule from lkp_all_l1."""

    model_config = ConfigDict(extra="forbid")

    tabid: str = Field(..., description="Table ID, e.g. 'MIL'.")
    variable: str = Field(..., description="Variable name, e.g. 'MPatID'.")
    varid: str = Field(..., description="Variable ID, e.g. '01'.")
    vartype: str = Field(..., description="Variable type: 'C' (char) or 'N' (numeric).")
    varlength: int = Field(..., description="Expected SAS variable length.")
    sortorder: int | None = Field(default=None, description="Sort order position if applicable.")
    flagcondition: str = Field(default="", description="SAS flag condition expression.")
    validvaluetype: str = Field(default="", description="Valid value type descriptor.")


class VariableLength(BaseModel):
    """Variable length entry from lkp_all_saslength."""

    model_config = ConfigDict(extra="forbid")

    tabid: str
    variable: str
    length: int


class IdLength(BaseModel):
    """ID length entry from lkp_l1_idlength."""

    model_config = ConfigDict(extra="forbid", populate_by_name=True)

    tabid: str
    variable: str
    id_length: int = Field(..., alias="idLength")


class LookupData(BaseModel):
    """Container for all loaded lookup data."""

    model_config = ConfigDict(extra="forbid")

    check_flags: list[CheckFlagDef] = Field(default_factory=list)
    l1_rules: list[L1VariableRule] = Field(default_factory=list)
    variable_lengths: list[VariableLength] = Field(default_factory=list)
    id_lengths: list[IdLength] = Field(default_factory=list)
