"""ASK contracts executed by the real RARS target."""

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
TEXT = "FOCAL/RARS error [E07]: text buffer bounds\n"
SYMBOL = "FOCAL/RARS error [E09]: variable/array bounds\n"


class AskTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin="", files=None, saved=None, timeout=30):
        with tempfile.TemporaryDirectory(prefix="focal-ask-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "ask.asm"
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

    def batch(self, program, responses, expected):
        source, count = re.subn(
            r"(?m)(^focal_program:\n)\s*\.asciz[^\n]*",
            lambda match: match[1] + asm_string(program), self.source,
        )
        self.assertEqual(count, 1)
        source = source.replace("repl_enabled:   .word 1", "repl_enabled:   .word 0", 1)
        self.execute(source, expected, stdin=responses)

    def test_scalar_prompt_abbreviations_and_newline(self):
        for token in ["ASK", "a", "aSk"]:
            with self.subTest(token=token):
                self.session([
                    (f'{token} "Value?",LONGNAME,!\n1+2', "Value?:\n"),
                    ("TYPE LONGOTHER,!", "3.0\n"),
                ])

    def test_strings_controls_newlines_and_arbitrary_order(self):
        self.session([
            ('ASK !,"A;,!%",!,X," done",!\n4', "\nA;,!%\n: done\n"),
            ("TYPE X,!", "4.0\n"),
        ])

    def test_multiple_targets_see_previous_assignments(self):
        self.session([
            ("SET A=2", ""),
            ('ASK "X=",X,"Y=",Y,"Z=",Z,!\nA+3\nX*2\n(X+Y)/3',
             "X=:Y=:Z=:\n"),
            ("TYPE X,!,Y,!,Z,!", "5.0\n10.0\n5.0\n"),
        ])

    def test_expression_profile(self):
        self.session([
            ("ASK A,B,C,D\n1.25E2\n2^-2\nFABS(-3)+FSQT(9)\nFITR(3.9)+FSGN(-5)",
             "::::"),
            ("TYPE A,!,B,!,C,!,D,!", "125.0\n0.25\n6.0\n2.0\n"),
            ("SET A=2;SET AR(2)=7;SET I=1", ""),
            ("ASK X,Y\nA+AR(I+1)\n(X+A)*2", "::"),
            ("TYPE X,!,Y,!", "9.0\n22.0\n"),
        ])

    def test_scalar_alias_case_and_indexed_targets(self):
        self.session([
            ("ASK LongName,aRrAy(1.5)\n7\n9", "::"),
            ("TYPE LO,!,longOther,!,AR(2),!", "7.0\n7.0\n9.0\n"),
            ("ASK I,A(I)\n1.5\n42", "::"),
            ("TYPE I,!,A(2),!", "1.5\n42.0\n"),
        ])

    def test_malformed_ask_lists_are_compile_errors(self):
        bad = ["ASK", "ASK ,", "ASK X,", "ASK ,X", "ASK X,,Y", "ASK X Y",
               'ASK "x" Y', "ASK %", "ASK @", "ASK FOO"]
        for statement in bad:
            with self.subTest(statement=statement):
                self.session([(statement, SYNTAX), ('TYPE "Alive",!', "Alive\n")])

    def test_invalid_input_expression_does_not_change_target(self):
        bad = ["", "SET A=2", "TYPE A", "1;2", "1 garbage", "@", "(1]"]
        for answer in bad:
            with self.subTest(answer=answer):
                self.session([
                    ("SET X=7", ""),
                    ("ASK X\n" + answer, ":" + SYNTAX),
                    ("TYPE X,!", "7.0\n"),
                ])

    def test_runtime_expression_errors_recover_without_assignment(self):
        for answer in ["1/0", "FSQT(-1)", "2^1.5", "0^-1"]:
            with self.subTest(answer=answer):
                self.session([
                    ("SET X=7", ""),
                    ("ASK X\n" + answer, ":" + MATH),
                    ("TYPE X,!", "7.0\n"),
                ])

    def test_previous_target_survives_later_input_error(self):
        self.session([
            ("SET X=1;SET Y=2", ""),
            ("ASK X,Y\n5\n1/0", "::" + MATH),
            ("TYPE X,!,Y,!", "5.0\n2.0\n"),
        ])

    def test_invalid_index_is_checked_before_prompt_or_input(self):
        for index in ["1E10", "1E100", "-1E100"]:
            with self.subTest(index=index):
                stdin = (f'ASK A({index})\nTYPE "NOT READ",!\n'
                         'TYPE A(0),!\nEXIT\n')
                expected = BANNER + "> " + SYMBOL + "> NOT READ\n> 0.0\n> "
                self.execute(self.source, expected, stdin=stdin)

    def test_type_format_persists_across_ask(self):
        self.session([
            ("TYPE %8.02", ""),
            ("ASK X\n1.5", ":"),
            ("TYPE X,!", "    1.50\n"),
        ])

    def test_compile_before_run_atomicity_consumes_no_input(self):
        self.session([
            ("ASK X;BOGUS", "FOCAL/RARS error [E10]: unknown statement\n"),
            ("TYPE X,!", "0.0\n"),
            ('ASK "MUST NOT PRINT",X;ASK Y,', SYNTAX),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_too_long_input_is_drained_and_recovers(self):
        stdin = "ASK X\n" + "1" * 300 + '\nTYPE "Alive",!\nTYPE X,!\nEXIT\n'
        expected = BANNER + "> :" + TEXT + "> Alive\n> 0.0\n> "
        self.execute(self.source, expected, stdin=stdin)

    def test_capacity_failure_occurs_after_input_but_does_not_create_target(self):
        steps = [("SET A=1", "")]
        steps += [(f"SET B({index})={index}", "") for index in range(511)]
        steps += [
            ("ASK C\n9", ":" + SYMBOL),
            ("TYPE C,!", "0.0\n"),
        ]
        self.session(steps, timeout=60)

    def test_stored_load_source_preservation_and_runtime_error(self):
        statement = 'aSk "X=",LongName,!'
        source = "1.01 " + statement + "\n1.02 TYPE LO,!\n1.03 Q\n"
        self.session([
            ("1.01 " + statement, ""),
            ("1.02 TYPE LO,!", ""),
            ("1.03 Q", ""),
            ("LIST", source),
            ("SAVE ask.focal", "Saved\n"),
            ("RUN\n1 garbage", "X=:" + SYNTAX),
            ("LIST", source),
            ('TYPE "Alive",!', "Alive\n"),
        ], saved={"ask.focal": source.encode("ascii")})
        self.session([
            ("LOAD ask.focal", "Loaded\n"),
            ("RUN\n4+1", "X=:\n5.0\n"),
        ], files={"ask.focal": source})

    def test_batch_uses_the_same_compile_ask(self):
        program = '1.01 ASK "X=",X,!\n1.02 TYPE X,!\n1.03 Q\n'
        self.batch(program, "2^3\n", "X=:\n8.0\n")

    def test_batch_eof_during_ask_is_controlled(self):
        program = "1.01 ASK X\n1.02 Q\n"
        self.batch(program, "", ":" + SYNTAX)


if __name__ == "__main__":
    unittest.main()
