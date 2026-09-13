"""Stage 6 physical-line frontend contracts against the real RARS target."""

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
UNKNOWN = "FOCAL/RARS error [E10]: unknown statement\n"


class FrontendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin=None, files=None, saved=None):
        with tempfile.TemporaryDirectory(prefix="focal-frontend-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                path = directory / name
                if isinstance(content, bytes):
                    path.write_bytes(content)
                else:
                    path.write_text(content, encoding="utf-8", newline="")
            asm = directory / "frontend.asm"
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

    def test_immediate_semicolons_and_empty_operators(self):
        self.session([
            ("SET A=1;TYPE A,!", "1.0\n"),
            ("SET A=2 ; SET B=3 ; TYPE A+B,!", "5.0\n"),
            (";SET A=4;;TYPE A,!;;;", "4.0\n"),
            (";;;", ""),
            (" ; ; ", ""),
            ("SET A=6;", ""),
            ("TYPE A,!", "6.0\n"),
        ])

    def test_semicolon_inside_string_is_not_a_separator(self):
        self.session([
            ("TYPE \"A;B\",!", "A;B\n"),
            ("TYPE \"A;B\",!;TYPE \"C\",!", "A;B\nC\n"),
        ])

    def test_comment_consumes_the_physical_line(self):
        self.session([
            ("COMMENT garbage ; TYPE \"BAD\",! ( [", ""),
            ("c anything ; SET A=99", ""),
            ("SET A=1; CoMmEnT rest ; SET A=2", ""),
            ("TYPE A,!", "1.0\n"),
        ])

    def test_comment_prefixes_remain_invalid(self):
        for statement in ["COMM ignored", "COMMENTARY ignored", "CX ignored"]:
            with self.subTest(statement=statement):
                self.session([(statement, UNKNOWN), ("TYPE \"Alive\",!", "Alive\n")])

    def test_quit_in_middle_stops_before_later_statements(self):
        self.session([
            ("SET A=1; QUIT; SET A=2", ""),
            ("TYPE A,!", "1.0\n"),
        ])

    def test_late_immediate_compile_error_has_no_partial_execution(self):
        self.session([
            ("SET A=0", ""),
            ("SET A=1;BOGUS", UNKNOWN),
            ("TYPE A,!", "0.0\n"),
        ])

    def test_stored_run_comment_boundary_and_source_preservation(self):
        wanted = (b"1.05 ;;;\n"
                  b"1.10 SET A=1; COMMENT stop ; SET A=99\n"
                  b"1.20 TYPE \"A;B\",!; TYPE A,!\n"
                  b"1.30 Q;TYPE \"BAD\",!\n")
        listing = wanted.decode("ascii")
        self.session([
            ("1.05 ;;;", ""),
            ("1.20 TYPE \"A;B\",!; TYPE A,!", ""),
            ("1.10 SET A=1; COMMENT stop ; SET A=99", ""),
            ("1.30 Q;TYPE \"BAD\",!", ""),
            ("RUN", "A;B\n1.0\n"),
            ("LIST", listing),
            ("SAVE frontend.focal", "Saved\n"),
        ], saved={"frontend.focal": wanted})

    def test_load_uses_the_same_frontend_on_run(self):
        program = (b"1.10 SET A=2;C tail ; SET A=99\r\n"
                   b"1.20 TYPE \"L;D\",!;TYPE A,!\n"
                   b"1.30 Q")
        listing = ("1.10 SET A=2;C tail ; SET A=99\n"
                   "1.20 TYPE \"L;D\",!;TYPE A,!\n"
                   "1.30 Q\n")
        self.session([
            ("LOAD frontend.focal", "Loaded\n"),
            ("RUN", "L;D\n2.0\n"),
            ("LIST", listing),
        ], files={"frontend.focal": program})

    def test_immediate_stored_load_and_batch_have_same_result(self):
        statement = "SET A=2;SET B=3;TYPE \"S;\",A+B,!;COMMENT ignored ; BOGUS"
        self.session([(statement, "S;5.0\n")])
        self.session([("1.01 " + statement, ""), ("1.02 Q", ""),
                      ("RUN", "S;5.0\n")])
        self.session([("LOAD same.focal", "Loaded\n"), ("RUN", "S;5.0\n")],
                     files={"same.focal": ("1.01 " + statement + "\n1.02 Q\n")})
        self.batch("1.01 " + statement + "\n1.02 Q\n", "S;5.0\n")

    def test_stored_late_error_keeps_source_and_recovers(self):
        self.session([
            ("1.01 SET A=1;BOGUS", ""),
            ("RUN", UNKNOWN),
            ("LIST", "1.01 SET A=1;BOGUS\n"),
            ("TYPE A,!", "0.0\n"),
            ("TYPE \"Alive\",!", "Alive\n"),
        ])

    def test_line_offset_is_start_of_multi_statement_physical_line(self):
        program = ("1.10 SET A=1;TYPE A,!\n"
                   "1.20 TYPE \"next\",!\n")
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
    bnez t0, frontend_fail
    lw t0, line_count
    li t1, 2
    bne t0, t1, frontend_fail
    la t0, line_offsets
    lw t1, 0(t0)
    bnez t1, frontend_fail
    lw t2, 4(t0)
    blez t2, frontend_fail
    la t3, bytecode_buf
    add t4, t3, t2
    lw t5, 0(t4)
    li t6, OP_PRINT_S
    bne t5, t6, frontend_fail
    li a0, 110
    call set_pc_to_line
    lw t0, error_code
    bnez t0, frontend_fail
    lw t0, pc_ptr
    la t1, bytecode_buf
    bne t0, t1, frontend_fail
    la a0, frontend_ok
    li a7, 4
    ecall
    li a7, 10
    ecall
frontend_fail:
    la a0, frontend_bad
    li a7, 4
    ecall
    li a7, 10
    ecall
"""
        source = source.replace("\nmain:\n", "\nfocal_main:\n", 1)
        source = source.replace("\n.text\n", body + "\n.text\n", 1)
        source += ('\n.data\nfrontend_ok: .asciz "PASS\\n"\n'
                   'frontend_bad: .asciz "FAIL\\n"\n')
        self.execute(source, "PASS\n")


if __name__ == "__main__":
    unittest.main()
