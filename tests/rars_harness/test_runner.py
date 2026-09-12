"""Infrastructure tests, not FOCAL semantic acceptance tests."""

import contextlib
import io
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))

import rars_test_support as support
import run_rars_tests as runner


class SupportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="focal-runner-selftest-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.jar = self.root / "RARS with spaces.jar"
        self.jar.write_bytes(b"test jar")
        self.asm = self.root / "program with spaces.asm"
        self.asm.write_text(".text\n", encoding="utf-8")
        self.env = support.Environment("java with spaces.exe", self.jar, "test-sha")

    def test_missing_jar_variable(self):
        with self.assertRaisesRegex(support.RunnerEnvironmentError, "RARS_JAR"):
            support.check_environment(None, self.asm)

    def test_wrong_jar_path(self):
        with self.assertRaisesRegex(support.RunnerEnvironmentError, "JAR"):
            support.check_environment(str(self.root / "missing.jar"), self.asm)

    def test_jar_directory_is_not_a_file(self):
        with self.assertRaises(support.RunnerEnvironmentError):
            support.check_environment(str(self.root), self.asm)

    def test_missing_java(self):
        with patch.object(support.shutil, "which", return_value=None):
            with self.assertRaisesRegex(support.RunnerEnvironmentError, "Java"):
                support.check_environment(str(self.jar), self.asm)

    def test_missing_template(self):
        with patch.object(support.shutil, "which", return_value="java"):
            with self.assertRaisesRegex(support.RunnerEnvironmentError, "ASM"):
                support.check_environment(str(self.jar), self.root / "missing.asm")

    def test_environment_hash(self):
        with patch.object(support.shutil, "which", return_value="java"):
            env = support.check_environment(str(self.jar), self.asm)
        self.assertEqual(env.sha256, support.sha256_file(self.jar))
        self.assertEqual(env.jar, self.jar.resolve())

    def run_result(self, code=0, stdout="ok\n", stderr="\nProgram terminated by calling exit\n"):
        result = subprocess.CompletedProcess([], code, stdout, stderr)
        with patch.object(support.subprocess, "run", return_value=result) as call:
            outcome = support.run_rars(self.env, self.asm, "ok\n")
        return outcome, call

    def test_assembly_failure_even_with_expected_stdout(self):
        outcome, _ = self.run_result(code=2)
        self.assertEqual(outcome.category, "ASSEMBLY")

    def test_simulation_failure_even_with_expected_stdout(self):
        outcome, _ = self.run_result(code=3)
        self.assertEqual(outcome.category, "SIMULATION")

    def test_launch_failure(self):
        outcome, _ = self.run_result(code=1, stderr="Invalid or corrupt jarfile")
        self.assertEqual(outcome.category, "ENVIRONMENT")

    def test_spawn_failure(self):
        with patch.object(support.subprocess, "run", side_effect=OSError("cannot start")):
            self.assertEqual(support.run_rars(self.env, self.asm, "ok").category, "ENVIRONMENT")

    def test_timeout_preserves_partial_output(self):
        error = subprocess.TimeoutExpired(["java"], 30, output=b"partial", stderr=b"detail")
        with patch.object(support.subprocess, "run", side_effect=error):
            result = support.run_rars(self.env, self.asm, "ok")
        self.assertEqual(result.category, "TIMEOUT")
        self.assertEqual(result.stdout, "partial")
        self.assertEqual(result.stderr, "detail")

    def test_mismatch(self):
        outcome, _ = self.run_result(stdout="wrong\n")
        self.assertEqual(outcome.category, "MISMATCH")

    def test_exact_is_default_and_rejects_extra_output(self):
        outcome, _ = self.run_result(stdout="extra\nok\n")
        self.assertEqual(outcome.category, "MISMATCH")

    def test_legacy_substring_is_explicit(self):
        self.assertTrue(support.compare_output("extra\nok\n", " ok \n", support.LEGACY_SUBSTRING))
        self.assertFalse(support.compare_output("extra\nok\n", "ok\n", support.EXACT))

    def test_lf_crlf(self):
        self.assertTrue(support.compare_output("one\r\ntwo\r\n", "one\ntwo\n", support.EXACT))

    def test_exact_preserves_spaces_and_final_newline(self):
        self.assertFalse(support.compare_output(" ok\n", "ok\n", support.EXACT))
        self.assertFalse(support.compare_output("ok", "ok\n", support.EXACT))

    def test_unknown_comparison_mode(self):
        with self.assertRaises(ValueError):
            support.compare_output("ok", "ok", "typo")

    def test_paths_flags_and_stdin(self):
        outcome, call = self.run_result()
        self.assertTrue(outcome.passed)
        self.assertEqual(call.call_args.args[0], [
            self.env.java, "-jar", str(self.jar), "nc", "me", "ae2", "se3", str(self.asm)
        ])
        self.assertEqual(call.call_args.kwargs["stdin"], subprocess.DEVNULL)
        self.assertEqual(call.call_args.kwargs["cwd"], self.asm.parent)
        self.assertFalse(call.call_args.kwargs.get("shell", False))

    def test_unexpected_diagnostics_are_not_ignored(self):
        for diagnostic in ("Error in source", "Simulation terminated due to errors.",
                           "Program terminated when maximum step limit 1 reached."):
            with self.subTest(diagnostic=diagnostic):
                outcome, _ = self.run_result(stderr=diagnostic)
                self.assertEqual(outcome.category, "RARS_DIAGNOSTIC")


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="focal-runner-selftest-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.demo = self.root / "demo"
        self.demo.mkdir()
        self.template = self.root / "interpreter.asm"
        self.original = (ROOT / "rars_focal_interpreter.asm").read_bytes()
        self.template.write_bytes(self.original)
        for name in runner.BASELINE_NAMES:
            (self.demo / (name + ".focal")).write_text('1: TYPE "ok",!\n', encoding="utf-8")
            (self.demo / (name + ".expected.txt")).write_text("ok\n", encoding="utf-8")
        self.env = support.Environment("java", self.root / "rars.jar", "test-sha")
        self.output_dirs = []
        self.fixture_bytes = {p: p.read_bytes() for p in self.demo.iterdir()}

    def fake_run(self, env, asm, expected, **kwargs):
        self.assertEqual(kwargs["comparison"], support.LEGACY_SUBSTRING)
        self.assertTrue(asm.is_file())
        self.assertIn("repl_enabled:   .word 0", asm.read_text(encoding="utf-8"))
        self.output_dirs.append(asm.parent)
        return support.RunResult("PASS", "", "ok\n", "", 0)

    def invoke(self, effect=None, env_error=None):
        output = io.StringIO()
        with patch.object(runner, "ROOT", self.root), \
             patch.object(runner, "TEMPLATE", self.template), \
             patch.object(runner, "DEMO_DIR", self.demo), \
             patch.object(runner, "check_environment", return_value=self.env, side_effect=env_error), \
             patch.object(runner, "git_head", return_value="test-head"), \
             patch.object(runner, "run_rars", side_effect=effect or self.fake_run), \
             contextlib.redirect_stdout(output):
            code = runner.main()
        return code, output.getvalue()

    def test_success_summary_and_exit_code(self):
        code, output = self.invoke()
        self.assertEqual(code, 0)
        self.assertIn("Passed: 7\nFailed: 0", output)
        self.assertIn("legacy-substring", output)
        self.assertIn("SHA-256: test-sha", output)
        self.assertIn("Git HEAD: test-head", output)

    def test_environment_failure_is_not_skip(self):
        code, output = self.invoke(env_error=support.RunnerEnvironmentError("missing RARS_JAR"))
        self.assertEqual(code, 2)
        self.assertIn("ENVIRONMENT", output)
        self.assertNotIn("[SKIP]", output)
        self.assertIn("Passed: 0\nFailed: 0", output)

    def test_missing_fixture_and_expected_continue(self):
        for suffix in (".focal", ".expected.txt"):
            with self.subTest(suffix=suffix):
                target = self.demo / (runner.BASELINE_NAMES[0] + suffix)
                saved = target.read_bytes()
                target.unlink()
                try:
                    code, output = self.invoke()
                    self.assertEqual(code, 1)
                    self.assertIn("Passed: 6\nFailed: 1", output)
                    self.assertIn("FIXTURE", output)
                finally:
                    target.write_bytes(saved)

    def test_failed_process_does_not_hide_other_tests(self):
        calls = 0

        def effect(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 1:
                return support.RunResult("SIMULATION", "test failure", "partial", "detail", 3)
            return self.fake_run(*args, **kwargs)

        code, output = self.invoke(effect=effect)
        self.assertEqual(code, 1)
        self.assertEqual(calls, 7)
        self.assertIn("Passed: 6\nFailed: 1", output)
        self.assertIn("partial", output)
        self.assertIn("detail", output)

    def test_independent_temp_dirs_and_preserved_inputs(self):
        old_dir = self.root / ".rars_test_build"
        old_dir.mkdir()
        sentinel = old_dir / "user.txt"
        sentinel.write_bytes(b"keep")
        self.invoke()
        first = set(self.output_dirs)
        self.output_dirs.clear()
        self.invoke()
        second = set(self.output_dirs)
        self.assertTrue(first.isdisjoint(second))
        self.assertTrue(all(not p.exists() for p in first | second))
        self.assertEqual(sentinel.read_bytes(), b"keep")
        self.assertEqual(self.template.read_bytes(), self.original)
        for path, data in self.fixture_bytes.items():
            self.assertEqual(path.read_bytes(), data)

    def test_build_does_not_overwrite_an_existing_file(self):
        fixture = self.demo / (runner.BASELINE_NAMES[0] + ".focal")
        with self.assertRaises(FileExistsError):
            runner.build_demo_asm(fixture, self.template, self.template)
        self.assertEqual(self.template.read_bytes(), self.original)

    def test_invalid_template_is_reported(self):
        self.template.write_text(".text\n", encoding="utf-8")
        code, output = self.invoke()
        self.assertEqual(code, 1)
        self.assertIn("BUILD", output)
        self.assertIn("Passed: 0\nFailed: 7", output)


if __name__ == "__main__":
    unittest.main()
