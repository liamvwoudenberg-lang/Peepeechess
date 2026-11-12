"""Dev entry: python dev_build.py OUT_DIR [class ...]  -> OUT_DIR/test_<class>.glb (test rigs, not characters)."""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from peepee_assets import runtime
from peepee_assets.animation import testrig, spec
args = runtime.script_args()
out = Path(args[0])
for cls in (args[1:] or spec.CLASSES):
    size = testrig.build(cls, out / f"test_{cls}.glb")
    runtime.log(f"{cls}: {size} bytes")
