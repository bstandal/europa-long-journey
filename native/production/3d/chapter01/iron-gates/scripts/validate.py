"""Validate the exported Iron Gates package, bindings and byte manifest."""

from pathlib import Path
import sys


CELL_DIR = Path(__file__).resolve().parents[1]
TOOLS_DIR = CELL_DIR.parent / "later-cells-tools"
sys.path.insert(0, str(TOOLS_DIR))

from chapter01_later_cells import validate  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(validate("iron-gates", CELL_DIR))
