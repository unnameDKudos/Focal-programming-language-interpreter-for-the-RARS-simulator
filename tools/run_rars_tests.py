import os
import subprocess
import sys
import tempfile
from pathlib import Path

from embed_rars_demo import asm_string


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "rars_focal_interpreter.asm"
DEMO_DIR = ROOT / "demo" / "rars"


def build_demo_asm(focal_path: Path, output_path: Path):
    asm = TEMPLATE.read_text(encoding="utf-8")
    source = focal_path.read_text(encoding="utf-8")
    if not source.endswith("\n"):
        source += "\n"

    lines = asm.splitlines()
    for idx, line in enumerate(lines):
        if line.strip().startswith(".asciz ") and idx > 0 and lines[idx - 1].strip() == "focal_program:":
            lines[idx] = asm_string(source)
            output_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
            return

    raise RuntimeError("Cannot find focal_program .asciz in template")


def run_rars(jar: str, asm_path: Path):
    cmd = ["java", "-jar", jar, "nc", str(asm_path)]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.returncode, result.stdout, result.stderr


def main():
    jar = os.environ.get("RARS_JAR")
    if not jar:
        print("[SKIP] RARS_JAR is not set")
        print("       Example: set RARS_JAR=C:\\path\\to\\rars.jar")
        return 0

    focal_files = sorted(DEMO_DIR.glob("*.focal"))
    if not focal_files:
        print("[FAIL] No demo .focal files found")
        return 1

    passed = 0
    failed = 0

    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        for focal in focal_files:
            expected_path = focal.with_suffix(".expected.txt")
            expected = expected_path.read_text(encoding="utf-8").strip()
            asm_path = tmp_dir / f"{focal.stem}.asm"
            build_demo_asm(focal, asm_path)

            code, stdout, stderr = run_rars(jar, asm_path)
            actual = stdout.strip()
            if code == 0 and expected in actual:
                print(f"[OK] {focal.name}")
                passed += 1
            else:
                print(f"[FAIL] {focal.name}")
                print(f"Expected:\n{expected}")
                print(f"Actual stdout:\n{stdout}")
                print(f"Actual stderr:\n{stderr}")
                failed += 1

    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
