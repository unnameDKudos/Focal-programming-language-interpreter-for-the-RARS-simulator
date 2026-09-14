"""Stage 12 DO/RETURN contracts executed by the real RARS target."""

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
NUMBER = "FOCAL/RARS error [E14]: invalid line number or selector\n"
CONTEXT = "FOCAL/RARS error [E16]: invalid DO/RETURN context\n"


class DoTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin="", files=None, saved=None,
                timeout=30):
        with tempfile.TemporaryDirectory(prefix="focal-do-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "do.asm"
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

    def batch(self, program, expected, *, stdin="", timeout=30):
        source, count = re.subn(
            r"(?m)(^focal_program:\n)\s*\.asciz[^\n]*",
            lambda match: match[1] + asm_string(program), self.source,
        )
        self.assertEqual(count, 1)
        source = source.replace("repl_enabled:   .word 1", "repl_enabled:   .word 0", 1)
        self.execute(source, expected, stdin=stdin, timeout=timeout)

    def test_do_line_returns_to_immediate_suffix(self):
        self.session([
            ('4.50 TYPE "A"', ""),
            ('TYPE "X";DO 4.50;TYPE "Y",!', "XAY\n"),
        ])

    def test_do_line_alias_case_composite_identity_and_full_physical_line(self):
        for statement in ["D 2.1", "dO 2.10"]:
            with self.subTest(statement=statement):
                self.session([
                    ('2.10 TYPE "A";TYPE "B"', ""),
                    (f'TYPE "X";{statement};TYPE "Y",!', "XABY\n"),
                ])

    def test_do_group_runs_sorted_existing_lines_and_returns(self):
        self.session([
            ('4.30 TYPE "C"', ""),
            ('4.01 TYPE "A"', ""),
            ('4.20 TYPE "B"', ""),
            ('5.01 TYPE "BAD"', ""),
            ('TYPE "X";DO 4;TYPE "Y",!', "XABCY\n"),
        ])

    def test_nested_line_and_group_calls_return_lifo(self):
        self.session([
            ('2.01 TYPE "A";DO 3.10;TYPE "D"', ""),
            ('2.20 TYPE "E"', ""),
            ('3.10 TYPE "B";DO 4.01;TYPE "C"', ""),
            ('4.01 TYPE "b"', ""),
            ('TYPE "X";DO 2;TYPE "Y",!', "XABbCDEY\n"),
        ])

    def test_explicit_return_skips_remainder_and_returns_one_level(self):
        self.session([
            ('2.01 TYPE "A";DO 3.01;TYPE "D"', ""),
            ('2.02 TYPE "E"', ""),
            ('3.01 TYPE "B";RETURN;TYPE "BAD"', ""),
            ('3.02 TYPE "BAD2"', ""),
            ('TYPE "X";DO 2;TYPE "Y",!', "XABDEY\n"),
        ])

    def test_return_outside_do_is_controlled_and_recovers(self):
        for statement in ["R", "rEtUrN"]:
            with self.subTest(statement=statement):
                self.session([
                    (statement, CONTEXT),
                    ('TYPE "Alive",!', "Alive\n"),
                ])

    def test_goto_inside_group_retains_context_and_line_call_escape_discards_it(self):
        self.session([
            ('2.01 TYPE "A";GOTO 2.20;TYPE "BAD"', ""),
            ('2.10 TYPE "BAD2"', ""),
            ('2.20 TYPE "B"', ""),
            ('TYPE "X";DO 2;TYPE "Y",!', "XABY\n"),
        ])
        self.session([
            ('2.01 TYPE "A";GOTO 4.01', ""),
            ('4.01 TYPE "B";RETURN', ""),
            ('TYPE "X";DO 2.01;TYPE "BAD",!', "XAB" + CONTEXT),
        ])

    def test_if_inside_group_and_selective_nested_unwind(self):
        self.session([
            ('2.01 TYPE "A";DO 3', ""),
            ('2.20 TYPE "D"', ""),
            ('3.01 TYPE "B";IF (1) 9.99,9.99,2.10', ""),
            ('3.20 TYPE "BAD"', ""),
            ('2.10 TYPE "C"', ""),
            ('TYPE "X";DO 2;TYPE "Y",!', "XABCDY\n"),
        ])

    def test_external_jump_unwinds_all_contexts(self):
        self.session([
            ('2.01 TYPE "A";DO 3;TYPE "BAD2"', ""),
            ('3.01 TYPE "B";GOTO 4.01', ""),
            ('4.01 TYPE "C";RETURN', ""),
            ('TYPE "X";DO 2;TYPE "BAD",!', "XABC" + CONTEXT),
        ])
        self.session([
            ('2.01 TYPE "A";DO 3;TYPE "BAD2"', ""),
            ('3.01 TYPE "B";IF (1) 9.99,9.99,4.01', ""),
            ('4.01 TYPE "C";RETURN', ""),
            ('TYPE "X";DO 2;TYPE "BAD",!', "XABC" + CONTEXT),
        ])

    def test_missing_do_target_does_not_execute_suffix_and_recovers(self):
        self.session([
            ('TYPE "BEFORE";DO 9.99;TYPE "BAD"', "BEFORE" + MISSING),
            ('DO 9', MISSING),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_quit_and_runtime_error_discard_stale_contexts(self):
        self.session([
            ('2.01 TYPE "Q";QUIT;TYPE "BAD"', ""),
            ('3.01 TYPE A(1E10),!', ""),
            ('DO 2;TYPE "BAD2"', "Q"),
            ("RETURN", CONTEXT),
            ("DO 3", "FOCAL/RARS error [E09]: variable/array bounds\n"),
            ("RETURN", CONTEXT),
            ('TYPE "Alive",!', "Alive\n"),
        ])

    def test_sixteen_contexts_succeed_and_seventeenth_is_controlled(self):
        success = [(f'{group}.01 DO {group + 1}', "") for group in range(1, 16)]
        success.append(('16.01 TYPE "Z"', ""))
        success.append(('TYPE "X";DO 1;TYPE "Y",!', "XZY\n"))
        self.session(success, timeout=60)

        overflow = [(f'{group}.01 DO {group + 1}', "") for group in range(1, 17)]
        overflow.append(('17.01 TYPE "BAD"', ""))
        overflow.append(('DO 1', CONTEXT))
        overflow.append(('TYPE "Alive",!', "Alive\n"))
        self.session(overflow, timeout=60)

    def test_do_grammar_rejects_missing_all_variable_and_bad_composite(self):
        for statement, error in [
            ("DO", SYNTAX),
            ("DO ALL", NUMBER),
            ("DO X", NUMBER),
            ("DO 2.00", NUMBER),
        ]:
            with self.subTest(statement=statement):
                self.session([
                    (statement, error),
                    ('TYPE "Alive",!', "Alive\n"),
                ])

    def test_compile_before_run_atomicity_and_source_preservation(self):
        source = ('1.01 TyPe "M";dO 2.1;TyPe "N";q\n'
                  '2.10 tYpE "S";ReTuRn\n')
        self.session([
            ('2.10 tYpE "S";ReTuRn', ""),
            ('1.01 TyPe "M";dO 2.1;TyPe "N";q', ""),
            ('TYPE "BAD";DO 2.1;BOGUS', UNKNOWN),
            ("LIST", source),
            ("SAVE do-source.focal", "Saved\n"),
        ], saved={"do-source.focal": source.encode("ascii")})

    def test_stored_load_batch_ask_symbols_and_type_state(self):
        program = (
            '1.01 ASK X\n'
            '1.02 TYPE %6.01;DO 3\n'
            '1.03 TYPE "R",X,!;Q\n'
            '3.01 SET X=X+1;TYPE "S",X,!\n'
        )
        self.session([
            ("LOAD do-state.focal", "Loaded\n"),
            ("RUN\n2", ":S   3.0\nR   3.0\n"),
        ], files={"do-state.focal": program})
        self.batch(program.replace("ASK X", "SET X=4"), "S   5.0\nR   5.0\n")

    def test_historical_examples_2_36_2_37_and_return_pattern(self):
        # Historical 2.36/2.37 concepts, adapted only to the frozen syntax and
        # current TYPE rendering: one line and a group are natural routines.
        line_and_group = (
            '1.01 TYPE "L";DO 2.20;TYPE "G";DO 3;TYPE !;Q\n'
            '2.20 TYPE "INE"\n'
            '3.10 TYPE "RO"\n'
            '3.20 TYPE "UP"\n'
        )
        self.batch(line_and_group, "LINEGROUP\n")

        repeated_group = (
            '1.05 SET A=5\n'
            '1.10 DO 2;DO 2\n'
            '1.15 TYPE A,!;Q\n'
            '2.10 TYPE A,!\n'
            '2.20 SET A=A-1\n'
        )
        self.batch(repeated_group, "5.0\n4.0\n3.0\n")

        explicit_return = (
            '1.01 DO 2;TYPE "A";Q\n'
            '2.01 TYPE "B";RETURN;TYPE "BAD"\n'
            '2.02 TYPE "BAD2"\n'
        )
        self.batch(explicit_return, "BA")


if __name__ == "__main__":
    unittest.main()
