"""Final TZ v1.2 acceptance runner; Python is transport/assertion only."""

from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory

from rars_test_support import (
    BASELINE_RARS_SHA256,
    EXACT,
    RunnerEnvironmentError,
    check_environment,
    git_head,
    run_rars,
)
from run_rars_tests import build_demo_asm


ROOT = Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "rars_focal_interpreter.asm"
MANIFEST = ROOT / "tests" / "rars_profile" / "manifest.json"
BANNER = "FOCAL/RARS REPL. Enter HELP for commands.\n"
FR_IDS = {f"FR-{number:02}" for number in range(1, 27)}
AR_IDS = {f"AR-{number:02}" for number in range(1, 7)}
REL_IDS = {f"REL-{number:02}" for number in range(1, 6)}
K_IDS = {f"K-{number:02}" for number in range(1, 6)}
REQUIREMENT_IDS = FR_IDS | AR_IDS | REL_IDS | K_IDS
KINDS = {"positive", "negative", "integration", "historical"}


class ManifestError(Exception):
    pass


def load_manifest(path=MANIFEST):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise ManifestError(f"Cannot read acceptance manifest: {error}") from error


def validate_manifest(manifest, manifest_dir=MANIFEST.parent):
    scenarios = manifest.get("scenarios")
    if not isinstance(scenarios, list):
        raise ManifestError("manifest.scenarios must be an array")
    ids = set()
    coverage = set()
    mandatory = negative = integration = historical_executions = 0
    historical_programs = set()
    for index, scenario in enumerate(scenarios):
        where = f"scenario #{index + 1}"
        if not isinstance(scenario, dict):
            raise ManifestError(f"{where} must be an object")
        for field in ("id", "title", "requirements", "kind", "execution_mode",
                      "program", "oracle_basis"):
            if field not in scenario:
                raise ManifestError(f"{where} is missing {field}")
        scenario_id = scenario["id"]
        if not isinstance(scenario_id, str) or not scenario_id:
            raise ManifestError(f"{where} has invalid id")
        if scenario_id in ids:
            raise ManifestError(f"duplicate scenario id: {scenario_id}")
        ids.add(scenario_id)
        if scenario["kind"] not in KINDS:
            raise ManifestError(f"{scenario_id}: invalid kind {scenario['kind']!r}")
        if scenario["execution_mode"] not in {"batch", "repl", "harness"}:
            raise ManifestError(f"{scenario_id}: invalid execution_mode")
        if not isinstance(scenario["requirements"], list) or not scenario["requirements"]:
            raise ManifestError(f"{scenario_id}: requirements must be non-empty")
        unknown_requirements = [requirement for requirement in scenario["requirements"]
                                if requirement not in REQUIREMENT_IDS]
        if unknown_requirements:
            raise ManifestError(
                f"{scenario_id}: unknown requirement ID(s): "
                + ", ".join(map(str, unknown_requirements)))
        coverage.update(scenario["requirements"])
        if scenario.get("comparison", EXACT) != EXACT:
            raise ManifestError(f"{scenario_id}: profile comparison must be exact")
        if "expected_stdout" not in scenario:
            raise ManifestError(f"{scenario_id}: expected_stdout is required")
        if not isinstance(scenario["expected_stdout"], str):
            raise ManifestError(f"{scenario_id}: expected_stdout must be text")
        if scenario.get("mandatory", True):
            mandatory += 1
            negative += scenario["kind"] == "negative"
            integration += bool(scenario.get("integration", False) or
                                scenario["kind"] == "integration")
            historical_executions += scenario["kind"] == "historical"
        if scenario["kind"] == "historical":
            passport = scenario.get("historical_passport")
            required = {"book", "chapter", "printed_page", "pdf_page",
                        "example", "adaptations"}
            if not isinstance(passport, dict) or not required <= passport.keys():
                raise ManifestError(f"{scenario_id}: incomplete historical passport")
            if scenario.get("mandatory", True):
                program = scenario["program"]
                fixture = program.get("fixture") if isinstance(program, dict) else None
                if not isinstance(fixture, str) or not fixture:
                    raise ManifestError(
                        f"{scenario_id}: mandatory historical program must use fixture")
                historical_root = (manifest_dir / "fixtures" / "historical").resolve()
                historical_path = (manifest_dir / fixture).resolve()
                try:
                    historical_path.relative_to(historical_root)
                except ValueError as error:
                    raise ManifestError(
                        f"{scenario_id}: historical fixture must be inside "
                        "fixtures/historical") from error
                if historical_path == historical_root:
                    raise ManifestError(f"{scenario_id}: historical fixture must be a file")
                historical_programs.add(historical_path)

    missing_fr = sorted(FR_IDS - coverage)
    missing_ar = sorted(AR_IDS - coverage)
    missing_rel = sorted(REL_IDS - coverage)
    missing_k = sorted(K_IDS - coverage)
    errors = []
    if mandatory < 40:
        errors.append(f"mandatory={mandatory}, need >=40")
    if negative < 10:
        errors.append(f"negative={negative}, need >=10")
    if integration < 5:
        errors.append(f"integration={integration}, need >=5")
    if len(historical_programs) < 6:
        errors.append(
            f"historical_programs={len(historical_programs)}, need >=6")
    if missing_fr:
        errors.append("missing FR coverage: " + ", ".join(missing_fr))
    if missing_ar:
        errors.append("missing AR coverage: " + ", ".join(missing_ar))
    if missing_rel:
        errors.append("missing REL coverage: " + ", ".join(missing_rel))
    if missing_k:
        errors.append("missing K evidence: " + ", ".join(missing_k))
    if errors:
        raise ManifestError("; ".join(errors))
    return {
        "mandatory": mandatory,
        "negative": negative,
        "integration": integration,
        "historical_executions": historical_executions,
        "historical_programs": len(historical_programs),
        "fr": len(FR_IDS & coverage),
        "ar": len(AR_IDS & coverage),
        "rel": len(REL_IDS & coverage),
        "k": len(K_IDS & coverage),
    }


def canonical_keys(count):
    return [f"{index // 99 + 1}.{index % 99 + 1:02}" for index in range(count)]


def symbol_names(count):
    first = "ABCDEGHIJKLMNOPQRSTUVWXYZ"
    second = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    names = [a + b for a in first for b in second]
    if count > len(names):
        raise ManifestError("symbol generator exceeds distinct profile keys")
    return names[:count]


def generated_focal(name):
    if name in {"symbol_capacity_512", "symbol_overflow_513"}:
        count = 512 if name.endswith("512") else 513
        statements = [f"SET {symbol}=1" for symbol in symbol_names(count)]
        chunks = [";".join(statements[index:index + 5])
                  for index in range(0, len(statements), 5)]
        lines = [f"{key} {text}" for key, text in zip(canonical_keys(len(chunks)), chunks)]
        if count == 512:
            lines.append(f"{canonical_keys(len(chunks) + 1)[-1]} TYPE \"OK\",!;Q")
        return "\n".join(lines) + "\n"
    if name == "storage_overflow_129":
        return "".join(f"{key} COMMENT line\n" for key in canonical_keys(129))
    if name == "bytecode_overflow":
        text = "SET A=A+1;" * 10 + "COMMENT fill"
        return "".join(f"{key} {text}\n" for key in canonical_keys(128))
    if name == "large_valid_program":
        keys = canonical_keys(128)
        comment = "COMMENT " + "x" * 119
        lines = [f"{key} {comment}" for key in keys[:-1]]
        lines.append(f"{keys[-1]} TYPE 42,!;Q")
        return "\n".join(lines) + "\n"
    if name == "do_depth_17":
        lines = [f"{group}.01 DO {group + 1}" for group in range(1, 18)]
        lines.append("18.01 Q")
        return "\n".join(lines) + "\n"
    if name == "for_depth_17":
        names = [f"V{n}" for n in range(1, 10)] + [f"W{n}" for n in range(1, 9)]
        return "1.01 " + "".join(f"FOR {symbol}=1,1;" for symbol in names) + \
               "TYPE \"BAD\"\n1.02 Q\n"
    raise ManifestError(f"unknown FOCAL generator: {name}")


def resolve_program(spec, manifest_dir):
    if not isinstance(spec, dict):
        raise ManifestError("program must be an object")
    choices = [name for name in ("inline", "fixture", "generator", "harness")
               if name in spec]
    if len(choices) != 1:
        raise ManifestError("program must select exactly one source")
    choice = choices[0]
    if choice == "inline":
        return spec[choice]
    if choice == "fixture":
        path = (manifest_dir / spec[choice]).resolve()
        try:
            path.relative_to(manifest_dir.resolve())
        except ValueError as error:
            raise ManifestError(f"fixture escapes profile directory: {path}") from error
        try:
            return path.read_text(encoding="ascii")
        except (OSError, UnicodeError) as error:
            raise ManifestError(f"cannot read fixture {path}: {error}") from error
    if choice == "generator":
        return generated_focal(spec[choice])
    return spec[choice]


def file_bytes(spec, manifest_dir, created):
    if "inline" in spec:
        return spec["inline"].encode("ascii")
    if "fixture" in spec:
        path = (manifest_dir / spec["fixture"]).resolve()
        try:
            path.relative_to(manifest_dir.resolve())
            return path.read_bytes()
        except (OSError, ValueError) as error:
            raise ManifestError(f"cannot read file fixture {path}: {error}") from error
    if "generator" in spec:
        return generated_focal(spec["generator"]).encode("ascii")
    if "same_as" in spec:
        try:
            return created[spec["same_as"]]
        except KeyError as error:
            raise ManifestError(f"unknown same_as file: {spec['same_as']}") from error
    raise ManifestError("file spec needs inline, fixture, generator, or same_as")


def build_vm_stack_harness(count, expect_overflow):
    outcome = ("call report_error\n" if expect_overflow else
               "lw t0, error_code\nbnez t0, profile_fail\n"
               "la a0, profile_pass\nli a7, 4\necall\n")
    entry = f"""
.text
main:
    andi sp, sp, -16
    call init_safety
    call reset_runtime
    li s0, {count}
profile_emit_loop:
    beqz s0, profile_emit_done
    li a0, OP_PUSH_BITS
    call emit_word
    li a0, 0
    call emit_word
    addi s0, s0, -1
    j profile_emit_loop
profile_emit_done:
    li a0, OP_HALT
    call emit_word
    la t0, bytecode_buf
    sw t0, pc_ptr, t1
    call vm_run
    {outcome}
    li a7, 10
    ecall
profile_fail:
    la a0, profile_fail_text
    li a7, 4
    ecall
    li a7, 10
    ecall
"""
    target = TEMPLATE.read_text(encoding="utf-8")
    target = target.replace("\nmain:\n", "\nfocal_main:\n", 1)
    target = target.replace("\n.text\n", entry + "\n.text\n", 1)
    return target + ('\n.data\nprofile_pass: .asciz "PASS\\n"\n'
                     'profile_fail_text: .asciz "FAIL\\n"\n')


def build_harness(name):
    if name == "vm_stack_capacity_512":
        return build_vm_stack_harness(512, False)
    if name == "vm_stack_overflow_513":
        return build_vm_stack_harness(513, True)
    raise ManifestError(f"unknown harness: {name}")


def prepare_scenario(scenario, directory, manifest_dir):
    created = {}
    for name, spec in scenario.get("files", {}).items():
        if Path(name).name != name:
            raise ManifestError(f"unsafe scenario filename: {name}")
        content = file_bytes(spec, manifest_dir, created)
        (directory / name).write_bytes(content)
        created[name] = content

    mode = scenario["execution_mode"]
    program = resolve_program(scenario["program"], manifest_dir)
    asm_path = directory / "profile.asm"
    if mode == "batch":
        focal_path = directory / "program.focal"
        focal_path.write_text(program, encoding="ascii", newline="\n")
        build_demo_asm(focal_path, asm_path, TEMPLATE)
        stdin_text = scenario.get("stdin", "")
    elif mode == "repl":
        asm_path.write_text(TEMPLATE.read_text(encoding="utf-8"),
                            encoding="utf-8", newline="\n")
        stdin_text = program
    else:
        asm_path.write_text(build_harness(program), encoding="utf-8", newline="\n")
        stdin_text = scenario.get("stdin", "")
    return asm_path, stdin_text, created


def java_version(java):
    try:
        result = subprocess.run([java, "-version"], capture_output=True, text=True,
                                encoding="utf-8", errors="replace", timeout=10)
        lines = (result.stderr or result.stdout).splitlines()
        return lines[0] if lines else "unavailable"
    except (OSError, subprocess.TimeoutExpired):
        return "unavailable"


def run_scenario(environment, scenario, root, manifest_dir):
    directory = root / scenario["id"].lower().replace("-", "_")
    directory.mkdir()
    try:
        asm_path, stdin_text, created = prepare_scenario(scenario, directory, manifest_dir)
    except (OSError, UnicodeError, ValueError, ManifestError) as error:
        return False, f"FIXTURE: {error}"
    result = run_rars(environment, asm_path, scenario["expected_stdout"],
                      comparison=EXACT, timeout=scenario.get("timeout", 30),
                      stdin_text=stdin_text)
    if not result.passed:
        return False, (f"{result.category}: {result.detail}\n"
                       f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}")
    error_code = scenario.get("expected_error")
    if error_code and f"FOCAL/RARS error [{error_code}]" not in result.stdout:
        return False, f"expected diagnostic {error_code} was not present"
    for name, spec in scenario.get("expected_files", {}).items():
        try:
            expected = file_bytes(spec, manifest_dir, created)
            actual = (directory / name).read_bytes()
        except (OSError, ManifestError) as error:
            return False, f"FILE: {error}"
        if actual != expected:
            return False, f"FILE: {name} differs from exact expected bytes"
    return True, "exact"


def main():
    print("Suite: TZ v1.2 profile acceptance (exact comparisons)")
    try:
        manifest = load_manifest()
        counts = validate_manifest(manifest)
        environment = check_environment(os.environ.get("RARS_JAR"), TEMPLATE)
    except (ManifestError, RunnerEnvironmentError, OSError, ValueError) as error:
        print(f"Environment: FAIL ({error})")
        return 2

    print("Environment: PASS")
    print(f"Java executable: {environment.java}")
    print(f"Java version: {java_version(environment.java)}")
    print(f"RARS JAR: {environment.jar}")
    print(f"SHA-256: {environment.sha256}")
    print(f"Recognized baseline: {'yes' if environment.sha256 == BASELINE_RARS_SHA256 else 'no'}")
    print("RV32 invocation: java -jar <RARS_JAR> nc me ae2 se3 <asm>")
    print(f"Git HEAD: {git_head(ROOT)}")

    passed = 0
    passed_by = {"negative": 0, "integration": 0,
                 "historical_executions": 0}
    mandatory_scenarios = [item for item in manifest["scenarios"]
                           if item.get("mandatory", True)]
    with TemporaryDirectory(prefix="focal-rars-profile-") as temp:
        temp_root = Path(temp)
        for scenario in mandatory_scenarios:
            ok, detail = run_scenario(environment, scenario, temp_root, MANIFEST.parent)
            if ok:
                passed += 1
                if scenario["kind"] == "negative":
                    passed_by["negative"] += 1
                if scenario.get("integration", False) or scenario["kind"] == "integration":
                    passed_by["integration"] += 1
                if scenario["kind"] == "historical":
                    passed_by["historical_executions"] += 1
                print(f"[OK] {scenario['id']} {scenario['title']}")
            else:
                print(f"[FAIL] {scenario['id']} {scenario['title']}: {detail}")

    skipped = 0
    print(f"Mandatory scenarios: {passed}/{counts['mandatory']}")
    print(f"Negative: {passed_by['negative']}/{counts['negative']}")
    print(f"Integration: {passed_by['integration']}/{counts['integration']}")
    print("Historical executions: "
          f"{passed_by['historical_executions']}/"
          f"{counts['historical_executions']}")
    print(f"Historical programs: {counts['historical_programs']} (minimum 6)")
    print(f"FR coverage: {counts['fr']}/26")
    print(f"AR coverage: {counts['ar']}/6")
    print(f"REL coverage: {counts['rel']}/5")
    print(f"K evidence: {counts['k']}/5")
    print(f"Mandatory skipped: {skipped}")
    success = passed == counts["mandatory"] and skipped == 0
    print(f"Acceptance: {'PASS' if success else 'FAIL'}")
    return 0 if success else 1


if __name__ == "__main__":
    sys.exit(main())
