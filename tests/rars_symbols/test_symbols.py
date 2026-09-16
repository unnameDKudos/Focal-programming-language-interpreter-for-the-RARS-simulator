"""Symbol-table contracts against the real RARS target."""

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
CAPACITY = "FOCAL/RARS error [E09]: variable/array bounds\n"


class SymbolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin=None, files=None, saved=None):
        with tempfile.TemporaryDirectory(prefix="focal-symbols-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "symbols.asm"
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

    def test_identifier_grammar_and_first_two_identity(self):
        self.session([(
            "SET A=1;SET AB=2;SET ABCDE=3;SET ACROSS=4;SET A1B2=5;"
            "SET E3=6;TYPE A,!,AB,!,ABZZ,!,acorn,!,a1tail,!,e3tail,!",
            "1.0\n3.0\n3.0\n4.0\n5.0\n6.0\n",
        )])
        for statement in ["SET 1A=2", "SET A_B=2"]:
            with self.subTest(statement=statement):
                self.session([(statement, SYNTAX), ("TYPE \"Alive\",!", "Alive\n")])

    def test_case_insensitive_identity_preserves_source_text(self):
        source = "1.01 sEt LongName=7\n1.02 tYpE loWER,!\n1.03 q\n"
        self.session([
            ("1.01 sEt LongName=7", ""),
            ("1.02 tYpE loWER,!", ""),
            ("1.03 q", ""),
            ("RUN", "7.0\n"),
            ("LIST", source),
            ("SAVE mixed.focal", "Saved\n"),
        ], saved={"mixed.focal": source.encode("ascii")})

    def test_f_namespace_is_reserved_and_functions_still_work(self):
        for statement in ["SET F=1", "SET FAR=1", "TYPE FOOBAR,!", "TYPE FSIN(0),!"]:
            with self.subTest(statement=statement):
                self.session([(statement, SYNTAX), ("TYPE \"Alive\",!", "Alive\n")])
        self.session([(
            "TYPE FABS(-3),!,FSQT(4),!,FITR(3.9),!,FSGN(-2),!",
            "3.0\n2.0\n3.0\n-1.0\n",
        )])

    def test_scalar_and_indexed_entries_are_distinct(self):
        self.session([(
            "SET LONGNAME=4;SET LONGOTHER(1)=5;SET LONGOTHER(2)=6;"
            "TYPE LO,!,LO(1),!,LONGTAIL(2),!",
            "4.0\n5.0\n6.0\n",
        )])

    def test_index_rounding_is_nearest_even(self):
        self.session([
            ("SET A(1.4)=14;SET A(1.5)=15", ""),
            ("TYPE A(1),!,A(2),!", "14.0\n15.0\n"),
            ("SET A(2.5)=25;TYPE A(2),!", "25.0\n"),
            ("SET A(2.6)=26;TYPE A(3),!", "26.0\n"),
            ("SET A(-1.5)=15;SET A(-2.5)=25;TYPE A(-2),!", "25.0\n"),
            ("SET A(-1.4)=14;TYPE A(-1),!", "14.0\n"),
        ])

    def test_index_expression_and_long_name_alias(self):
        self.session([(
            "SET VALUE=2;SET ARRAYNAME(VALUE+1)=9;TYPE AR(3),!",
            "9.0\n",
        )])

    def test_invalid_index_conversion_is_controlled_and_recovers(self):
        for index in ["1E100", "-1E100", "1E10", "-1E10"]:
            with self.subTest(index=index):
                self.session([
                    (f"SET A({index})=1", CAPACITY),
                    ("TYPE A(0),!", "0.0\n"),
                    ("TYPE \"Alive\",!", "Alive\n"),
                ])

    def test_capacity_512_rewrite_and_failed_create_are_atomic(self):
        steps = [("SET A=1", ""), ("SET A=2", "")]
        steps += [(f"SET B({index})={index}", "") for index in range(511)]
        steps += [
            ("SET C=9", CAPACITY),
            ("SET B(0)=77", ""),
            ("TYPE A,!,B(0),!,B(510),!,C,!", "2.0\n77.0\n510.0\n0.0\n"),
        ]
        self.session(steps)

    def test_persistence_load_quit_and_erase(self):
        self.session([
            ("SET LONGNAME=12;SET ARRAY(2)=8", ""),
            ("QUIT", ""),
            ("LOAD keep.focal", "Loaded\n"),
            ("RUN", "12.0\n8.0\n"),
            ("RUN", "12.0\n8.0\n"),
            ("ERASE", ""),
            ("TYPE LO,!,AR(2),!", "0.0\n0.0\n"),
        ], files={"keep.focal": "1.01 TYPE LOWER,!\n1.02 TYPE ARRAY(2),!\n1.03 Q\n"})

    def test_ask_and_legacy_for_share_symbol_table(self):
        stdin = ("ASK \"Value=\",LONGNAME\n12.5\n"
                 "ASK \"Item=\",ARRAY(1.5)\n7.5\n"
                 "SET SUM=0;FOR INDEX=1,3 DO SET SUM=SUM+INDEX;TYPE SU,!\n"
                 "TYPE LO,!,AR(2),!\nEXIT\n")
        expected = (BANNER + "> Value=:> Item=:> 6.0\n> 12.5\n7.5\n> ")
        self.execute(self.source, expected, stdin=stdin)

    def test_compile_errors_do_not_create_or_modify_symbols(self):
        self.session([
            ("SET EXISTING=7", ""),
            ("SET NEWNAME=1;BOGUS", "FOCAL/RARS error [E10]: unknown statement\n"),
            ("TYPE EX,!,NE,!", "7.0\n0.0\n"),
            ("1.01 SET STORED=3;BOGUS", ""),
            ("RUN", "FOCAL/RARS error [E10]: unknown statement\n"),
            ("TYPE ST,!", "0.0\n"),
        ])

    def test_immediate_stored_load_and_batch_use_same_symbols(self):
        statement = "SET LONGNAME=1.5E1;SET ARRAY(1+1)=LONGOTHER+FABS(-2);TYPE AR(2),!"
        self.session([(statement, "17.0\n")])
        self.session([("1.01 " + statement, ""), ("1.02 Q", ""), ("RUN", "17.0\n")])
        program = "1.01 " + statement + "\n1.02 Q\n"
        self.session([("LOAD symbols.focal", "Loaded\n"), ("RUN", "17.0\n")],
                     files={"symbols.focal": program})
        self.batch(program, "17.0\n")


if __name__ == "__main__":
    unittest.main()
