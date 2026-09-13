"""Stage 9 TYPE formatting contracts against the real RARS target."""

import os
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from embed_rars_demo import asm_string
from rars_test_support import check_environment, run_rars

BANNER = "FOCAL/RARS REPL. Enter HELP for commands.\n"
SYNTAX = "FOCAL/RARS error [E10]: invalid source\n"
MATH = "FOCAL/RARS error [E15]: invalid arithmetic operation\n"


class TypeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin=None, files=None, saved=None):
        with tempfile.TemporaryDirectory(prefix="focal-type-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "type.asm"
            asm.write_text(source, encoding="utf-8", newline="\n")
            result = run_rars(self.env, asm, expected, stdin_text=stdin, timeout=30)
            self.assertTrue(result.passed,
                            f"{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}")
            for name, content in (saved or {}).items():
                self.assertEqual((directory / name).read_bytes(), content)

    def session(self, steps, *, files=None, saved=None):
        stdin = "".join(command + "\n" for command, _ in steps) + "EXIT\n"
        expected = BANNER + "".join("> " + output for _, output in steps) + "> "
        self.execute(self.source, expected, stdin=stdin, files=files, saved=saved)

    def batch(self, program, expected):
        source, count = re.subn(
            r"(?m)(^focal_program:\n)\s*\.asciz[^\n]*",
            lambda match: match[1] + asm_string(program), self.source,
        )
        self.assertEqual(count, 1)
        source = source.replace("repl_enabled:   .word 1", "repl_enabled:   .word 0", 1)
        self.execute(source, expected)

    def test_basic_items_newlines_and_literal_controls(self):
        self.session([(
            'TYPE "A;%!,",!,1+2,!,!,"B",!,4,!',
            "A;%!,\n3.0\n\nB\n4.0\n",
        )])

    def test_exponential_format_and_persistence(self):
        self.session([
            ("TYPE %,0,!,1000,!,-.125,!", "0.0E+0\n1.0E+3\n-1.25E-1\n"),
            ("TYPE 25,!", "2.5E+1\n"),
            ("QUIT", ""),
            ("TYPE 1,!", "1.0E+0\n"),
        ])

    def test_integer_width_padding_sign_and_overflow(self):
        self.session([(
            "TYPE %1,0,!,%5,12.4,!,-12.5,!,123456,!",
            "0\n   12\n  -13\n123456\n",
        )])

    def test_width_is_independent_of_formatter_buffer(self):
        self.session([("TYPE %256,1,!", " " * 255 + "1\n")])

    def test_fixed_precision_rounding_and_switching(self):
        self.session([(
            "TYPE %8.02,1.24,!,1.25,!,-1.24,!,-1.25,!",
            "    1.24\n    1.25\n   -1.24\n   -1.25\n",
        ), (
            "TYPE %6.01,1.24,!,1.25,!,1.26,!,-1.24,!,-1.25,!,-1.26,!",
            "   1.2\n   1.3\n   1.3\n  -1.2\n  -1.3\n  -1.3\n",
        ), (
            "TYPE %5.00,12.5,!,%7.03,1.5,!,%4,9.6,!",
            "   13\n  1.500\n  10\n",
        )])

    def test_field_exact_fit_padding_and_wider_value(self):
        self.session([(
            "TYPE %4.01,1.2,!,%7.02,-1.2,!,%3.02,123.45,!",
            " 1.2\n  -1.20\n123.45\n",
        )])

    def test_float32_values_symbols_and_exponents(self):
        self.session([(
            "SET LONGNAME=1.25E2;TYPE %10.02,LONGOTHER+FABS(-.5),!,0,!,-0.0,!",
            "    125.50\n      0.00\n      0.00\n",
        )])

    def test_format_persists_through_run_load_and_quit(self):
        program = "1.01 TYPE %7.02,1.5,!\n1.02 Q\n"
        self.session([
            ("TYPE %5,7,!", "    7\n"),
            ("LOAD format.focal", "Loaded\n"),
            ("RUN", "   1.50\n"),
            ("TYPE 2.5,!", "   2.50\n"),
            ("QUIT", ""),
            ("TYPE 3.5,!", "   3.50\n"),
        ], files={"format.focal": program})

    def test_erase_and_restart_restore_default(self):
        self.session([
            ("TYPE %5.01,1,!", "  1.0\n"),
            ("ERASE", ""),
            ("TYPE 1,!", "1.0\n"),
        ])
        self.session([("TYPE 1,!", "1.0\n")])

    def test_malformed_formats_are_controlled_and_recover(self):
        bad = ["%0", "%2147483648", "%99999999999999999999",
               "%8.", "%8.2", "%8.0", "%8.0253", "%X", "%10X",
               "%1.00X"]
        for spec in bad:
            with self.subTest(spec=spec):
                self.session([
                    (f"TYPE {spec},1,!", SYNTAX),
                    ('TYPE "Alive",!', "Alive\n"),
                ])

    def test_missing_items_and_invalid_separators_recover(self):
        for statement in ["TYPE", "TYPE ,1", "TYPE 1 2", "TYPE 1,", "TYPE !,,1"]:
            with self.subTest(statement=statement):
                self.session([
                    (statement, SYNTAX),
                    ('TYPE "Alive",!', "Alive\n"),
                ])

    def test_nonfinite_is_controlled_and_recovers(self):
        self.session([
            ("TYPE %,1E100,!", MATH),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_immediate_compile_is_atomic_for_output_and_format(self):
        self.session([
            ("TYPE %5,1,!", "    1\n"),
            ("TYPE %8.02;BOGUS", "FOCAL/RARS error [E10]: unknown statement\n"),
            ("TYPE 2,!", "    2\n"),
            ('TYPE "MUST NOT PRINT",!;BOGUS', "FOCAL/RARS error [E10]: unknown statement\n"),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_common_frontend_source_preservation_and_batch(self):
        statement = 'TYPE %8.02,LONGNAME+1.25,!;COMMENT keep % ! ; text'
        source = "1.01 SET LONGNAME=2\n1.02 " + statement + "\n1.03 Q\n"
        self.session([
            ("1.01 SET LONGNAME=2", ""),
            ("1.02 " + statement, ""),
            ("1.03 Q", ""),
            ("RUN", "    3.25\n"),
            ("LIST", source),
            ("SAVE type.focal", "Saved\n"),
        ], saved={"type.focal": source.encode("ascii")})
        self.session([("LOAD type.focal", "Loaded\n"), ("RUN", "    3.25\n")],
                     files={"type.focal": source})
        self.batch(source, "    3.25\n")


if __name__ == "__main__":
    unittest.main()
