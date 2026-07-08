"""CLI entrypoint for qa-mil."""

from __future__ import annotations

import typer

app = typer.Typer(
    name="qa-mil",
    help="SCDM MIL data QA review tool (Python port).",
    no_args_is_help=True,
)


@app.command()
def version() -> None:
    """Print the qa-mil package version."""
    from qa_mil import __version__

    typer.echo(__version__)


@app.command()
def validate_config(
    config: str = typer.Option(..., "--config", help="Path to the config YAML file."),
) -> None:
    """Validate config and input manifest (placeholder — full implementation in NUM-30)."""
    typer.echo(f"validate-config placeholder — config: {config}")


if __name__ == "__main__":
    app()
