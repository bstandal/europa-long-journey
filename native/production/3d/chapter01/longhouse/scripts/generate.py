"""Build the locked Chapter 01 Danube loess longhouse asset set."""

from pathlib import Path
import sys


CELL_DIR = Path(__file__).resolve().parents[1]
TOOLS_DIR = CELL_DIR.parent / "later-cells-tools"
sys.path.insert(0, str(TOOLS_DIR))

from chapter01_later_cells import main  # noqa: E402


if __name__ == "__main__":
    raise SystemExit(main("longhouse", CELL_DIR))
