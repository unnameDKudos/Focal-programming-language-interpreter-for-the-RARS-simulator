"""LOAD/SAVE contracts against the real RARS target."""

import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from rars_test_support import check_environment, run_rars

BANNER = "FOCAL/RARS REPL. Enter HELP for commands.\n"
NUMBER_ERROR = "FOCAL/RARS error [E14]: invalid line number or selector\n"
SYNTAX_ERROR = "FOCAL/RARS error [E10]: invalid source\n"
TEXT_ERROR = "FOCAL/RARS error [E07]: text buffer bounds\n"
CAPACITY_ERROR = "FOCAL/RARS error [E08]: line table/storage bounds\n"
FILE_ERROR = "FOCAL/RARS error [E12]: file I/O\n"


def canonical(rows):
    return "".join(f"{key} {text}\n" for key, text in rows)


def large_fixture():
    keys = ([f"1.{line:02}" for line in range(1, 100)]
            + [f"2.{line:02}" for line in range(1, 30)])
    text = "C " + "x" * 125
    rows = [(key, text) for key in keys]
    data = canonical(rows).encode("ascii")
    assert len(rows) == 128 and len(text) == 127 and len(data) > 8191
    return rows, data


class FileCommandTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, commands, outputs, *, files=None, saved=None):
        with tempfile.TemporaryDirectory(prefix="focal-files-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                path = directory / name
                path.parent.mkdir(parents=True, exist_ok=True)
                if isinstance(content, bytes):
                    path.write_bytes(content)
                else:
                    path.write_text(content, encoding="utf-8", newline="")
            asm = directory / "files.asm"
            asm.write_text(self.source, encoding="utf-8", newline="\n")
            stdin = "".join(command + "\n" for command in commands) + "EXIT\n"
            expected = BANNER + "".join("> " + output for output in outputs) + "> "
            result = run_rars(self.env, asm, expected, stdin_text=stdin, timeout=90)
            self.assertTrue(result.passed,
                            f"{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}")
            for name, content in (saved or {}).items():
                self.assertEqual((directory / name).read_bytes(), content)

    def test_load_canonicalizes_and_replaces_current_program(self):
        source = (b"2.1 C old\r\n"
                  b"1.01 tYpE  \"MiXeD  Text\" , !\n"
                  b"2.10 C replacement\r\n"
                  b"3.01 C deleted\n3.01")
        wanted = "1.01 tYpE  \"MiXeD  Text\" , !\n2.10 C replacement\n"
        commands = ["9.99 C previous", "S A=7", "LOAD mixed.focal", "LIST", "T A,!"]
        outputs = ["", "", "Loaded\n", wanted, "7.0\n"]
        self.execute(commands, outputs, files={"mixed.focal": source})

    def test_load_legacy_integer_migration(self):
        self.execute(["LOAD legacy.focal", "LIST"],
                     ["Loaded\n", "1.01 C One\n2.01 Q\n"],
                     files={"legacy.focal": b"100: Q\r\n1: C One\n"})

    def test_load_failures_are_atomic(self):
        too_many = canonical(
            [(f"1.{line:02}", "Q") for line in range(1, 100)]
            + [(f"2.{line:02}", "Q") for line in range(1, 31)]).encode("ascii")
        cases = [
            ("invalid-number", b"1.00 Q\n", NUMBER_ERROR),
            ("malformed-line", b".10 Q\n", NUMBER_ERROR),
            ("text-128", ("1.01 " + "C" * 128 + "\n").encode("ascii"), TEXT_ERROR),
            ("too-many-active", too_many, CAPACITY_ERROR),
            ("oversized-final-no-lf", ("1.01 " + "x" * 300).encode("ascii"), TEXT_ERROR),
            ("failure-after-valid-lines", b"2.01 C temporary\n1.00 Q\n", NUMBER_ERROR),
            ("embedded-nul", b"2.01 C hidden\x00suffix\n", SYNTAX_ERROR),
        ]
        for name, content, diagnostic in cases:
            with self.subTest(name=name):
                self.execute(
                    ["1.01 C Keep", "2.10 TYPE \"RUN\",!", "S A=7",
                     "LOAD bad.focal", "LIST", "RUN", "T A,!"],
                    ["", "", "", diagnostic,
                     "1.01 C Keep\n2.10 TYPE \"RUN\",!\n", "RUN\n", "7.0\n"],
                    files={"bad.focal": content},
                )

    def test_load_open_error_is_controlled_and_recovers(self):
        self.execute(["1.01 C Keep", "S A=7", "LOAD absent.focal", "LIST", "T A,!"],
                     ["", "", FILE_ERROR, "1.01 C Keep\n", "7.0\n"])

    def test_load_streams_full_capacity_beyond_program_buffer(self):
        rows, data = large_fixture()
        self.execute(["LOAD large.focal", "WRITE ALL"],
                     ["Loaded\n", canonical(rows)], files={"large.focal": data})

    def test_save_is_canonical_and_does_not_change_state(self):
        wanted = (b"1.01 tYpE  \"MiXeD  Text\" , !\n"
                  b"2.10 C replacement\n")
        commands = ["2.1 C old", "1.01 tYpE  \"MiXeD  Text\" , !", "S A=7",
                    "2.10 C replacement", "3.01 C removed", "3.01",
                    "SAVE canonical.focal", "LIST", "T A,!"]
        outputs = ["", "", "", "", "", "", "Saved\n", wanted.decode("ascii"), "7.0\n"]
        self.execute(commands, outputs, saved={"canonical.focal": wanted})

    def test_save_empty_program_creates_empty_file(self):
        self.execute(["SAVE empty.focal"], ["Saved\n"], saved={"empty.focal": b""})

    def test_save_erase_load_round_trip(self):
        wanted = b"1.01 C first\n2.10 TYPE \"second\",!\n"
        commands = ["2.1 TYPE \"second\",!", "1.01 C first", "SAVE round.focal",
                    "ERASE", "LOAD round.focal", "LIST"]
        outputs = ["", "", "Saved\n", "", "Loaded\n", wanted.decode("ascii")]
        self.execute(commands, outputs, saved={"round.focal": wanted})

    def test_save_and_reload_full_capacity_beyond_program_buffer(self):
        rows, wanted = large_fixture()
        commands = [f"{key} {text}" for key, text in reversed(rows)]
        outputs = [""] * len(commands)
        commands += ["SAVE large.focal", "ERASE", "LOAD large.focal", "WRITE ALL"]
        outputs += ["Saved\n", "", "Loaded\n", wanted.decode("ascii")]
        self.execute(commands, outputs, saved={"large.focal": wanted})

    def test_save_open_error_is_controlled_and_recovers(self):
        self.execute(["1.01 C Keep", "S A=7", "SAVE absent/out.focal", "LIST", "T A,!"],
                     ["", "", FILE_ERROR, "1.01 C Keep\n", "7.0\n"])


if __name__ == "__main__":
    unittest.main()
