"""Stage 13 normative FOR contracts executed by the real RARS target."""

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
ARRAY = "FOCAL/RARS error [E09]: variable/array bounds\n"
MATH = "FOCAL/RARS error [E15]: invalid arithmetic operation\n"
CONTEXT = "FOCAL/RARS error [E16]: invalid DO/RETURN context\n"
MISSING = "FOCAL/RARS error [E08]: line not found\n"


class ForTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def execute(self, source, expected, *, stdin="", files=None, saved=None,
                timeout=30):
        with tempfile.TemporaryDirectory(prefix="focal-for-") as directory_name:
            directory = Path(directory_name)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding="utf-8", newline="")
            asm = directory / "for.asm"
            asm.write_text(source, encoding="utf-8", newline="\n")
            result = run_rars(self.env, asm, expected, stdin_text=stdin,
                              timeout=timeout)
            self.assertTrue(
                result.passed,
                f"{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}",
            )
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
        source = source.replace("repl_enabled:   .word 1",
                                "repl_enabled:   .word 0", 1)
        self.execute(source, expected, stdin=stdin, timeout=timeout)

    def test_normative_default_step_form(self):
        self.batch('1.01 FOR I=1,3;TYPE I,!\n1.02 Q\n',
                   '1.0\n2.0\n3.0\n')

    def test_alias_case_explicit_positive_negative_and_fractional_steps(self):
        program = (
            '1.01 f i=1,2,5;TYPE I,!\n'
            '1.02 FoR J=1,-0.5,-1;TYPE J,!\n'
            '1.03 FOR K=-0.5,.25,.25;TYPE K,!\n'
            '1.04 Q\n'
        )
        self.batch(program,
                   '1.0\n3.0\n5.0\n'
                   '1.0\n0.5\n0.0\n-0.5\n-1.0\n'
                   '-0.5\n-0.25\n0.0\n0.25\n')

    def test_endpoint_single_iteration_zero_iterations_and_final_value(self):
        program = (
            '1.01 FOR I=2,2;TYPE "I"\n'
            '1.02 FOR J=3,2;TYPE "BAD"\n'
            '1.03 FOR K=-3,-1,-2;TYPE "BAD"\n'
            '1.04 FOR L=1,2,5;TYPE L,!\n'
            '1.05 FOR M=1,2,10;TYPE M,!\n'
            '1.06 TYPE I,J,K,L,M,!;Q\n'
        )
        self.batch(program,
                   'I1.0\n3.0\n5.0\n1.0\n3.0\n5.0\n7.0\n9.0\n'
                   '3.03.0-3.07.011.0\n')

    def test_zero_steps_nonfinite_inputs_and_recovery(self):
        self.session([
            ('FOR I=1,0,3;TYPE "BAD"', MATH),
            ('FOR I=1,-0.0,3;TYPE "BAD"', MATH),
            ('FOR I=1E100,3;TYPE "BAD"', MATH),
            ('FOR I=1,1E100,3;TYPE "BAD"', MATH),
            ('FOR I=1,1E100;TYPE "BAD"', MATH),
            ('FOR I=1,1;TYPE "OK",!', 'OK\n'),
        ])

    def test_header_expressions_are_evaluated_once(self):
        program = (
            '1.01 SET A=1;SET S=1;SET L=3\n'
            '1.02 FOR I=A,S,L;TYPE I,!;SET A=99;SET S=99;SET L=0\n'
            '1.03 TYPE I,A,S,L,!;Q\n'
        )
        self.batch(program, '1.0\n2.0\n3.0\n4.099.099.00.0\n')

    def test_body_changes_public_loop_variable_before_next_increment(self):
        program = (
            '1.01 FOR I=1,2,5;TYPE I,!;SET I=I+1\n'
            '1.02 TYPE I,!;Q\n'
        )
        self.batch(program, '1.0\n4.0\n7.0\n')

    def test_first_two_significant_characters_and_scalar_restriction(self):
        self.session([
            ('FOR LONGNAME=1,2;TYPE LO,!', '1.0\n2.0\n'),
            ('TYPE LONGOTHER,!', '3.0\n'),
            ('FOR A(1)=1,2;TYPE A(1)', SYNTAX),
            ('FOR FOO=1,2;TYPE FOO', SYNTAX),
        ])

    def test_nested_loops_recreate_inner_context_and_scope_all_semicolons(self):
        program = (
            '1.01 FOR I=1,2;FOR J=1,3;TYPE I,J,!;SET X=X+1\n'
            '1.02 TYPE "X=",X,!;Q\n'
        )
        self.batch(program,
                   '1.01.0\n1.02.0\n1.03.0\n'
                   '2.01.0\n2.02.0\n2.03.0\nX=6.0\n')

    def test_comment_ends_loop_body_at_physical_line_end(self):
        self.batch('1.01 FOR I=1,2;TYPE I;COMMENT ;TYPE "BAD"\n1.02 TYPE !;Q\n',
                   '1.02.0\n')

    def test_comment_only_body_may_emit_zero_wordcode_instructions(self):
        self.batch('1.01 FOR I=1,3;COMMENT empty body\n1.02 TYPE I,!;Q\n',
                   '4.0\n')

    def test_depth_sixteen_succeeds_and_seventeen_is_controlled(self):
        names = [f"V{n}" for n in range(1, 10)] + [f"W{n}" for n in range(1, 9)]
        sixteen = '1.01 ' + ''.join(
            f'FOR {name}=1,1;' for name in names[:16]
        ) + 'TYPE "Z",!\n1.02 Q\n'
        self.batch(sixteen, 'Z\n', timeout=60)
        seventeen = '1.01 ' + ''.join(
            f'FOR {name}=1,1;' for name in names[:17]
        ) + 'TYPE "BAD"\n1.02 Q\n'
        self.batch(seventeen, CONTEXT, timeout=60)

    def test_do_returns_to_loop_and_for_inside_do_returns_normally(self):
        program = (
            '1.01 FOR I=1,3;DO 2;TYPE I,!\n'
            '1.02 DO 3;TYPE "A";Q\n'
            '2.01 TYPE "D"\n'
            '3.01 FOR J=1,2;TYPE J\n'
        )
        self.batch(program, 'D1.0\nD2.0\nD3.0\n1.02.0A')

    def test_return_inside_for_discards_owned_loop_but_not_caller_loop(self):
        program = (
            '1.01 FOR I=1,2;DO 2;TYPE "A"\n'
            '1.02 TYPE "Z",!;Q\n'
            '2.01 FOR J=1,5;RETURN;TYPE "BAD"\n'
        )
        self.batch(program, 'AAZ\n')

    def test_goto_and_if_from_body_exit_loop(self):
        goto_program = (
            '1.01 FOR I=1,3;TYPE I;GOTO 1.02;TYPE "BAD"\n'
            '1.02 TYPE "G",!;Q\n'
        )
        self.batch(goto_program, '1.0G\n')
        if_program = (
            '1.01 FOR I=1,3;TYPE I;IF (1) 9.99,9.99,1.02;TYPE "BAD"\n'
            '1.02 TYPE "I",!;Q\n'
        )
        self.batch(if_program, '1.0I\n')

    def test_descendant_do_internal_jump_preserves_caller_for(self):
        program = (
            '1.01 FOR I=1,2;DO 2;TYPE I,!\n'
            '1.02 Q\n'
            '2.01 TYPE "A";GOTO 2.02\n'
            '2.02 TYPE "B"\n'
        )
        self.batch(program, 'AB1.0\nAB2.0\n')

    def test_descendant_do_external_jump_discards_caller_for(self):
        program = (
            '1.01 FOR I=1,3;DO 2;TYPE "BAD"\n'
            '1.02 TYPE "BAD2"\n'
            '2.01 TYPE "A";GOTO 3.01\n'
            '3.01 TYPE "X",!;Q\n'
        )
        self.batch(program, 'AX\n')

    def test_selective_nested_do_for_unwind_preserves_outer_loop(self):
        for transfer in ['GOTO 2.02', 'IF (1) 9.99,9.99,2.02']:
            with self.subTest(transfer=transfer):
                program = (
                    '1.01 FOR I=1,2;DO 2;TYPE I,!\n'
                    '1.02 Q\n'
                    '2.01 FOR J=1,2;DO 3;TYPE "BAD"\n'
                    '2.02 TYPE "B"\n'
                    f'3.01 TYPE "A";{transfer}\n'
                )
                self.batch(program, 'AB1.0\nAB2.0\n')

    def test_for_inside_do_direct_jump_exits_loop_but_retains_do(self):
        program = (
            '1.01 DO 2;TYPE "Z",!;Q\n'
            '2.01 FOR I=1,3;TYPE I;GOTO 2.02;TYPE "BAD"\n'
            '2.02 TYPE "X"\n'
        )
        self.batch(program, '1.0XZ\n')

    def test_ask_type_and_symbol_state_survive_iterations(self):
        program = (
            '1.01 TYPE %4.01;FOR I=1,2;ASK X;SET S=S+X;TYPE X,!\n'
            '1.02 TYPE "S",S,!;Q\n'
        )
        self.batch(program, ': 2.0\n: 3.0\nS 5.0\n', stdin='2\n3\n')

    def test_immediate_stored_load_and_legacy_compatibility(self):
        self.session([
            ('FOR I=1,2;TYPE I,!', '1.0\n2.0\n'),
            ('1.01 FOR J=1,2;TYPE J,!', ''),
            ('1.02 Q', ''),
            ('RUN', '1.0\n2.0\n'),
            ('LOAD for-load.focal', 'Loaded\n'),
            ('RUN', '1.0\n3.0\n5.0\n'),
            ('SET S=0;FOR K=1,3 DO SET S=S+K;TYPE S,!', '6.0\n'),
        ], files={'for-load.focal':
                  '1.01 FOR K=1,2,5;TYPE K,!\n1.02 Q\n'})

    def test_factorial_historical_pattern_and_for_do_fraction(self):
        factorial = (
            '1.01 ASK N\n'
            '1.02 SET P=1;FOR I=1,N;SET P=P*I\n'
            '1.03 TYPE P,!;Q\n'
        )
        self.batch(factorial, ':120.0\n', stdin='5\n')
        fraction_do = (
            '1.01 FOR X=0,.25,1;DO 2\n'
            '1.02 TYPE X,!;Q\n'
            '2.01 TYPE X,!\n'
        )
        self.batch(fraction_do, '0.0\n0.25\n0.5\n0.75\n1.0\n1.25\n')

    def test_quit_runtime_error_and_missing_target_cleanup(self):
        self.session([
            ('1.01 FOR I=1,3;QUIT;TYPE "BAD"', ''),
            ('1.02 Q', ''),
            ('RUN', ''),
            ('RETURN', CONTEXT),
            ('FOR I=1,3;GOTO 9.99', MISSING),
            ('RETURN', CONTEXT),
            ('FOR I=1,2;TYPE A(1E10)', ARRAY),
            ('FOR I=1,1;TYPE "Alive",!', 'Alive\n'),
        ])

    def test_malformed_headers_and_compile_before_run_atomicity(self):
        for statement in [
            'FOR I=1;TYPE "BAD"',
            'FOR I=1,;TYPE "BAD"',
            'FOR I=1,2,;TYPE "BAD"',
            'FOR I=1,2,3,4;TYPE "BAD"',
            'FOR I=1,2;',
            'FOR I=1,2 TYPE "BAD"',
        ]:
            with self.subTest(statement=statement):
                self.session([(statement, SYNTAX),
                              ('TYPE "Alive",!', 'Alive\n')])
        self.session([
            ('TYPE "BAD";FOR I=1,3;TYPE I;BOGUS',
             'FOCAL/RARS error [E10]: unknown statement\n'),
            ('TYPE "Alive",!', 'Alive\n'),
        ])

    def test_source_preservation(self):
        source = ('1.01 fOr LongName = 1 , .25 , 2 ; TyPe LO , !\n'
                  '1.02 q\n')
        self.session([
            ('1.01 fOr LongName = 1 , .25 , 2 ; TyPe LO , !', ''),
            ('1.02 q', ''),
            ('LIST', source),
            ('SAVE for-source.focal', 'Saved\n'),
        ], saved={'for-source.focal': source.encode('ascii')})


if __name__ == "__main__":
    unittest.main()
