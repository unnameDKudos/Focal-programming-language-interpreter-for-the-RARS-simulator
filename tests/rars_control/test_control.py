"""GOTO and sign-IF contracts executed by the real RARS target."""

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
MISSING = "FOCAL/RARS error [E08]: line not found\n"
SYNTAX = "FOCAL/RARS error [E10]: invalid source\n"
UNKNOWN = "FOCAL/RARS error [E10]: unknown statement\n"
MATH = "FOCAL/RARS error [E15]: invalid arithmetic operation\n"


class ControlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin="", files=None, saved=None,
                timeout=30):
        with tempfile.TemporaryDirectory(prefix="focal-control-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "control.asm"
            asm.write_text(source, encoding="utf-8", newline="\n")
            result = run_rars(self.env, asm, expected, stdin_text=stdin, timeout=timeout)
            self.assertTrue(result.passed,
                            f"{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}")
            for name, content in (saved or {}).items():
                self.assertEqual((directory / name).read_bytes(), content)

    def session(self, steps, *, files=None, saved=None, timeout=30):
        stdin = "".join(block + "\n" for block, _ in steps) + "EXIT\n"
        expected = BANNER + "".join("> " + output for _, output in steps) + "> "
        self.execute(self.source, expected, stdin=stdin, files=files, saved=saved,
                     timeout=timeout)

    def batch(self, program, expected, *, stdin=""):
        source, count = re.subn(
            r"(?m)(^focal_program:\n)\s*\.asciz[^\n]*",
            lambda match: match[1] + asm_string(program), self.source,
        )
        self.assertEqual(count, 1)
        source = source.replace("repl_enabled:   .word 1", "repl_enabled:   .word 0", 1)
        self.execute(source, expected, stdin=stdin)

    def test_normative_sign_if_three_targets(self):
        program = (
            '1.01 IF (-1) 1.10,1.20,1.30\n'
            '1.10 TYPE "N",!;Q\n'
            '1.20 TYPE "Z",!;Q\n'
            '1.30 TYPE "P",!;Q\n'
        )
        self.batch(program, "N\n")

    def test_forward_goto_aliases_composite_identity_and_unordered_storage(self):
        for token in ["G", "gO", "GoTo"]:
            with self.subTest(token=token):
                self.session([
                    ('2.10 TYPE "WRONG",!;Q', ""),
                    (f'1.10 TYPE "A";{token} 2.01;TYPE "BAD",!', ""),
                    ('2.01 TYPE "B",!;Q', ""),
                    ('1.20 TYPE "BAD2",!;Q', ""),
                    ("RUN", "AB\n"),
                    ("GOTO 1.1", "AB\n"),
                ])

    def test_backward_goto_loop_and_multiple_jumps_to_a_line(self):
        self.session([
            ("1.01 SET C=C+1", ""),
            ("1.02 IF (C-3) 1.03,1.04", ""),
            ("1.03 GOTO 1.01", ""),
            ('1.04 TYPE C,!;Q', ""),
            ("RUN", "3.0\n"),
            ("SET C=0", ""),
            ("GOTO 1.01", "3.0\n"),
        ])

    def test_no_target_goto_transfers_to_first_line_without_recursive_run(self):
        self.session([
            ("1.01 SET A=A+1;IF (A-2) 1.30,1.20", ""),
            ('1.20 TYPE A,!;Q', ""),
            ("1.30 GO", ""),
            ("RUN", "2.0\n"),
        ])
        for token in ["G", "GO", "GOTO"]:
            with self.subTest(token=token):
                self.session([
                    ('1.01 TYPE "FIRST",!;Q', ""),
                    (token + ';TYPE "BAD",!', "FIRST\n"),
                ])

    def test_immediate_goto_target_starts_stored_program_at_that_line(self):
        self.session([
            ('1.10 TYPE "BAD",!;Q', ""),
            ('1.20 TYPE "TARGET",!;Q', ""),
            ("gOtO 1.2", "TARGET\n"),
        ])

    def test_missing_goto_target_is_controlled_and_source_survives(self):
        source = "1.01 GOTO 9.99\n"
        self.session([
            ("1.01 GOTO 9.99", ""),
            ("RUN", MISSING),
            ("LIST", source),
            ("GOTO 8.88", MISSING),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_load_run_and_batch_share_goto_compiler(self):
        program = ('1.30 TYPE "BAD",!\n'
                   '1.10 GO 1.20\n'
                   '1.20 TYPE "LOAD",!;Q\n')
        self.session([
            ("LOAD jump.focal", "Loaded\n"),
            ("RUN", "LOAD\n"),
        ], files={"jump.focal": program})
        self.batch(program.replace("LOAD", "BATCH"), "BATCH\n")

    def test_sign_classification_including_both_zeros(self):
        targets = [
            ('9.10 TYPE "N",!;Q', ""),
            ('9.20 TYPE "Z",!;Q', ""),
            ('9.30 TYPE "P",!;Q', ""),
        ]
        self.session(targets + [
            ("IF (-2.5) 9.10,9.20,9.30", "N\n"),
            ("IF (+0.0) 9.10,9.20,9.30", "Z\n"),
            ("IF (-0.0) 9.10,9.20,9.30", "Z\n"),
            ("IF (2.5) 9.10,9.20,9.30", "P\n"),
        ])

    def test_nonfinite_sign_condition_is_controlled_and_recovers(self):
        self.session([
            ('1.10 TYPE "TARGET",!;Q', ""),
            ("IF (1E100) 1.10,1.10,1.10", MATH),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_sign_if_expression_symbol_index_and_function(self):
        self.session([
            ('9.10 TYPE "N",!;Q', ""),
            ('9.20 TYPE "Z",!;Q', ""),
            ('9.30 TYPE "P",!;Q', ""),
            ("SET LONGNAME=-2;SET AR(2)=0", ""),
            ("iF (LONGOTHER+1) 9.10,9.20,9.30", "N\n"),
            ("I (AR(1+1)) 9.10,9.20,9.30", "Z\n"),
            ("If (FSGN(FABS(-3))) 9.10,9.20,9.30", "P\n"),
        ])

    def test_one_two_and_three_target_fallthrough_semantics(self):
        self.session([
            ('1.10 TYPE "N",!;Q', ""),
            ('1.20 TYPE "Z",!;Q', ""),
            ('1.30 TYPE "P",!;Q', ""),
            ('IF (-1) 1.10;TYPE "BAD",!', "N\n"),
            ('IF (0) 1.10;TYPE "ZERO-FALL",!', "ZERO-FALL\n"),
            ('IF (1) 1.10;TYPE "POS-FALL",!', "POS-FALL\n"),
            ('IF (0) 1.10,1.20;TYPE "BAD",!', "Z\n"),
            ('IF (1) 1.10,1.20;TYPE "POS-FALL2",!', "POS-FALL2\n"),
            ('IF (1) 1.10,1.20,1.30;TYPE "BAD",!', "P\n"),
        ])

    def test_only_selected_if_target_is_resolved(self):
        self.session([
            ('1.20 TYPE "Z",!;Q', ""),
            ("IF (0) 8.88,1.20,9.99", "Z\n"),
            ("IF (-1) 8.88,1.20,9.99", MISSING),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_malformed_sign_if_lists_and_expression_are_atomic(self):
        bad = [
            "IF (1)",
            "IF () 1.10",
            "IF (1 1.10",
            "IF (1) 1.10,",
            "IF (1) 1.10,,1.20",
            "IF (1) 1.10,1.20,1.30,1.40",
        ]
        for statement in bad:
            with self.subTest(statement=statement):
                self.session([
                    (statement, SYNTAX),
                    ('TYPE "Alive",!', "Alive\n"),
                ])
        self.session([
            ('1.10 TYPE "TARGET",!;Q', ""),
            ('TYPE "BAD",!;IF (1) 1.10,1.10,1.10;BOGUS', UNKNOWN),
            ('GOTO 1.10;BOGUS', UNKNOWN),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_ask_value_and_type_format_survive_branch(self):
        program = (
            '1.01 ASK X\n'
            '1.02 IF (X) 1.10,1.20,1.30\n'
            '1.10 TYPE "N",X,!;Q\n'
            '1.20 TYPE "Z",X,!;Q\n'
            '1.30 TYPE "P",X,!;Q\n'
        )
        self.session([
            ("LOAD ask-branch.focal", "Loaded\n"),
            ("TYPE %6.01", ""),
            ("RUN\n-2", ":N  -2.0\n"),
        ], files={"ask-branch.focal": program})

    def test_source_preservation_for_goto_and_sign_if(self):
        source = ('1.10 gO 2.01\n'
                  '2.01 iF ( A-1 ) 3.10, 3.20 ,3.30\n'
                  '3.10 Q\n3.20 Q\n3.30 Q\n')
        self.session([
            ("1.10 gO 2.01", ""),
            ("2.01 iF ( A-1 ) 3.10, 3.20 ,3.30", ""),
            ("3.10 Q", ""),
            ("3.20 Q", ""),
            ("3.30 Q", ""),
            ("LIST", source),
            ("SAVE control.focal", "Saved\n"),
        ], saved={"control.focal": source.encode("ascii")})

    def test_legacy_boolean_if_is_non_parenthesized_compatibility_only(self):
        self.session([
            ('1.01 IF 1 THEN 1.03', ""),
            ('1.02 TYPE "BAD",!;Q', ""),
            ('1.03 TYPE "LEGACY",!;Q', ""),
            ("RUN", "LEGACY\n"),
        ])


if __name__ == "__main__":
    unittest.main()
