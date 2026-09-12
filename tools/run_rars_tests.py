"""Seven legacy RARS baseline tests, not the future normative language suite."""

import os
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

from embed_rars_demo import asm_string
from rars_test_support import (
    LEGACY_SUBSTRING, RunnerEnvironmentError, check_environment, git_head, run_rars,
)

ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "rars_focal_interpreter.asm"
DEMO_DIR = ROOT / "demo" / "rars"
# Missing fixtures must fail, not silently shrink the suite.
BASELINE_NAMES = ("array_sum", "for_sum", "goto", "hello", "if", "operators", "sort")


def build_demo_asm(focal_path, output_path, template=TEMPLATE):
    asm = template.read_text(encoding="utf-8")
    source = focal_path.read_text(encoding="utf-8")
    if not source.endswith("\n"):
        source += "\n"
    lines = asm.splitlines()
    repl_markers = source_markers = 0
    for idx, line in enumerate(lines):
        if line.strip().startswith("repl_enabled:"):
            lines[idx] = "repl_enabled:   .word 0"
            repl_markers += 1
        if (line.strip().startswith(".asciz ") and idx > 0
                and lines[idx - 1].strip() == "focal_program:"):
            lines[idx] = asm_string(source)
            source_markers += 1
    if repl_markers != 1 or source_markers != 1:
        raise ValueError("Template must contain exactly one repl_enabled and focal_program .asciz")
    # Exclusive creation also protects existing files against caller mistakes.
    with output_path.open("x", encoding="utf-8", newline="\n") as output:
        output.write("\n".join(lines) + "\n")


def main():
    passed = failed = 0
    print(f"Suite: legacy baseline ({LEGACY_SUBSTRING}; 7 fixtures)")
    try:
        environment = check_environment(os.environ.get("RARS_JAR"), TEMPLATE)
    except (RunnerEnvironmentError, OSError, ValueError) as error:
        print(f"[FAIL][ENVIRONMENT] {error}")
        print("Passed: 0\nFailed: 0")
        print("No tests executed; environment check failed.")
        return 2

    print(f"Java: {environment.java}")
    print(f"RARS JAR: {environment.jar}")
    print(f"RARS ID: {environment.rars_id}")
    print(f"SHA-256: {environment.sha256}")
    print(f"Git HEAD: {git_head(ROOT)}")
    try:
        # Never touch ROOT/.rars_test_build or any caller-owned directory.
        with TemporaryDirectory(prefix="focal-rars-baseline-") as directory:
            for name in BASELINE_NAMES:
                focal = DEMO_DIR / f"{name}.focal"
                expected_path = focal.with_suffix(".expected.txt")
                try:
                    for path in (focal, expected_path):
                        if not path.is_file():
                            raise FileNotFoundError(f"Missing fixture/expected file: {path}")
                    expected = expected_path.read_text(encoding="utf-8")
                    if not expected.strip():
                        raise ValueError(f"Empty legacy expectation would match everything: {expected_path}")
                except (OSError, UnicodeError, ValueError) as error:
                    print(f"[FAIL][FIXTURE] {focal.name}: {error}")
                    failed += 1
                    continue
                asm_path = Path(directory) / f"{name}.asm"
                try:
                    build_demo_asm(focal, asm_path, TEMPLATE)
                except (OSError, UnicodeError, ValueError) as error:
                    print(f"[FAIL][BUILD] {focal.name}: {error}")
                    failed += 1
                    continue
                result = run_rars(environment, asm_path, expected, comparison=LEGACY_SUBSTRING)
                if result.passed:
                    print(f"[OK] {focal.name}")
                    passed += 1
                else:
                    failed += 1
                    print(f"[FAIL][{result.category}] {focal.name}: {result.detail}")
                    print(f"Expected ({LEGACY_SUBSTRING}):\n{expected}")
                    print(f"Actual stdout:\n{result.stdout}")
                    print(f"Actual stderr:\n{result.stderr}")
    except OSError as error:
        print(f"[FAIL][ENVIRONMENT] Temporary workspace error: {error}")
        print(f"Passed: {passed}\nFailed: {failed}")
        return 2
    print(f"Passed: {passed}\nFailed: {failed}")
    return 0 if failed == 0 and passed == len(BASELINE_NAMES) else 1


if __name__ == "__main__":
    sys.exit(main())
