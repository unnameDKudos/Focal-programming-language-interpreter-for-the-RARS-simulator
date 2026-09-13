"""Stage 7 Float32 expression contracts against the real RARS target."""

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


class ExpressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin=None, files=None):
        with tempfile.TemporaryDirectory(prefix="focal-expr-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "expr.asm"
            asm.write_text(source, encoding="utf-8", newline="\n")
            result = run_rars(self.env, asm, expected, stdin_text=stdin, timeout=30)
        self.assertTrue(result.passed,
                        f"{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}")

    def session(self, steps, *, files=None):
        stdin = "".join(command + "\n" for command, _ in steps) + "EXIT\n"
        expected = BANNER + "".join("> " + output for _, output in steps) + "> "
        self.execute(self.source, expected, stdin=stdin, files=files)

    def batch(self, program, expected):
        source, count = re.subn(
            r"(?m)(^focal_program:\n)\s*\.asciz[^\n]*",
            lambda match: match[1] + asm_string(program), self.source,
        )
        self.assertEqual(count, 1)
        source = source.replace("repl_enabled:   .word 1", "repl_enabled:   .word 0", 1)
        self.execute(source, expected)

    def test_integer_decimal_and_dot_literals(self):
        self.session([(
            "TYPE 1,!,1.0,!,0.5,!,.5,!,5.,!",
            "1.0\n1.0\n0.5\n0.5\n5.0\n",
        )])

    def test_exponent_literals(self):
        self.session([(
            "TYPE 1E3,!,1e+2,!,1E-3,!,1.5E2,!,.5E1,!,5.E-1,!",
            "1000.0\n100.0\n0.001\n150.0\n5.0\n0.5\n",
        )])

    def test_literal_wordcode_contains_binary32_bits(self):
        program = "1.01 SET A=.5\n"
        source, count = re.subn(
            r"(?m)(^focal_program:\n)\s*\.asciz[^\n]*",
            lambda match: match[1] + asm_string(program), self.source,
        )
        self.assertEqual(count, 1)
        body = """
.text
main:
    andi sp, sp, -16
    call init_safety
    call reset_runtime
    la t0, focal_program
    sw t0, source_ptr, t1
    call compile_program
    lw t0, error_code
    bnez t0, expr_bits_fail
    la t0, bytecode_buf
    lw t1, 0(t0)
    li t2, OP_PUSH_BITS
    bne t1, t2, expr_bits_fail
    lw t1, 4(t0)
    li t2, 0x3f000000
    bne t1, t2, expr_bits_fail
    la a0, expr_bits_ok
    li a7, 4
    ecall
    li a7, 10
    ecall
expr_bits_fail:
    la a0, expr_bits_bad
    li a7, 4
    ecall
    li a7, 10
    ecall
"""
        source = source.replace("\nmain:\n", "\nfocal_main:\n", 1)
        source = source.replace("\n.text\n", body + "\n.text\n", 1)
        source += ('\n.data\nexpr_bits_ok: .asciz "PASS\\n"\n'
                   'expr_bits_bad: .asciz "FAIL\\n"\n')
        self.execute(source, "PASS\n")

    def test_malformed_literals_are_controlled_and_recover(self):
        for literal in [".", "1E", "1E+", "1E-", "1.2.3", "1EE2"]:
            with self.subTest(literal=literal):
                self.session([
                    (f"TYPE {literal},!", SYNTAX),
                    ("TYPE \"Alive\",!", "Alive\n"),
                ])

    def test_precedence_including_multiply_above_divide(self):
        self.session([(
            "TYPE 10-3+1,!,2+3*4,!,[2+3]*4,!,8/2*2,!,20/2/5,!,2*3^2,!",
            "8.0\n14.0\n20.0\n2.0\n2.0\n18.0\n",
        )])

    def test_unary_and_power_binding(self):
        self.session([
            ("SET A=2;SET I=2", ""),
            ("TYPE -A^I,!,(-A)^I,!,+FABS(-3),!", "-4.0\n4.0\n3.0\n"),
            ("TYPE 8/(-2),!", "-4.0\n"),
        ])
        for expression in ["8/-2", "1+-2", "--2", "2*-2"]:
            with self.subTest(expression=expression):
                self.session([(f"TYPE {expression},!", SYNTAX),
                              ("TYPE \"Alive\",!", "Alive\n")])

    def test_grouping_brackets_and_matching(self):
        self.session([(
            "TYPE (1+2),!,[1+2],!,<1+2>,!,[1+<2*3>],!",
            "3.0\n3.0\n3.0\n7.0\n",
        )])
        for expression in ["(1+2]", "[1+2>", "<1+2)"]:
            with self.subTest(expression=expression):
                self.session([(f"TYPE {expression},!", SYNTAX),
                              ("TYPE \"Alive\",!", "Alive\n")])

    def test_integer_power_and_errors(self):
        self.session([(
            "TYPE 2^3,!,2^0,!,2^-2,!,0^0,!,2^3^2,!",
            "8.0\n1.0\n0.25\n1.0\n512.0\n",
        )])
        for expression in ["4^0.5", "0^-1"]:
            with self.subTest(expression=expression):
                self.session([(f"TYPE {expression},!", MATH),
                              ("TYPE \"Alive\",!", "Alive\n")])

    def test_functions_and_bracket_variants(self):
        self.session([(
            "TYPE FABS(3),!,FABS[-3],!,FSQT<4>,!,FITR(3.9),!,FITR[-3.9],!",
            "3.0\n3.0\n2.0\n3.0\n-3.0\n",
        ), (
            "TYPE fSgN(-2),!,FSGN(0),!,FSGN(+2),!",
            "-1.0\n0.0\n1.0\n",
        )])

    def test_fitr_preserves_large_integral_float32_values(self):
        self.session([(
            "TYPE FITR(3.9),!,FITR(-3.9),!,FITR(8388608),!",
            "3.0\n-3.0\n8388608.0\n",
        ), (
            "TYPE FSGN(FITR(1E10)-1E10),!,FSGN(FITR(-1E10)+1E10),!",
            "0.0\n0.0\n",
        ), (
            "TYPE FITR(1E100),!",
            MATH,
        ), (
            "TYPE \"Alive\",!",
            "Alive\n",
        )])

    def test_non_normative_f_function_is_rejected(self):
        self.session([("TYPE FSIN(0),!", SYNTAX),
                      ("TYPE \"Alive\",!", "Alive\n")])

    def test_sqrt_and_division_domain_errors_recover(self):
        for expression in ["FSQT(-1)", "1/0", "1/(2-2)"]:
            with self.subTest(expression=expression):
                self.session([(f"TYPE {expression},!", MATH),
                              ("TYPE \"Alive\",!", "Alive\n")])

    def test_late_compile_error_does_not_execute_prefix(self):
        self.session([
            ("SET A=0", ""),
            ("SET A=1;SET A=1E", SYNTAX),
            ("TYPE A,!", "0.0\n"),
        ])

    def test_stored_runtime_error_preserves_source_and_recovers(self):
        source = "1.01 SET A=.5E1;TYPE A/0,!\n1.02 Q\n"
        self.session([
            ("1.01 SET A=.5E1;TYPE A/0,!", ""),
            ("1.02 Q", ""),
            ("RUN", MATH),
            ("LIST", source),
            ("TYPE A,!", "5.0\n"),
            ("TYPE \"Alive\",!", "Alive\n"),
        ])

    def test_immediate_stored_load_and_batch_use_one_expression_path(self):
        statement = "SET A=.5E1;TYPE FSQT[A^2]+FITR(.9),!"
        self.session([(statement, "5.0\n")])
        self.session([("1.01 " + statement, ""), ("1.02 Q", ""),
                      ("RUN", "5.0\n")])
        program = "1.01 " + statement + "\n1.02 Q\n"
        self.session([("LOAD expr.focal", "Loaded\n"), ("RUN", "5.0\n")],
                     files={"expr.focal": program})
        self.batch(program, "5.0\n")


if __name__ == "__main__":
    unittest.main()
