"""Exact end-to-end token/lifecycle tests against the target ASM in RARS."""
import os
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from rars_test_support import check_environment, run_rars

BANNER = 'FOCAL/RARS REPL. Enter HELP for commands.\n'
UNKNOWN = 'FOCAL/RARS error [E10]: unknown statement\n'
SYNTAX = 'FOCAL/RARS error [E10]: invalid source\n'
CONTEXT = 'FOCAL/RARS error [E16]: invalid DO/RETURN context\n'
HELP = ('Commands:\n'
        '  group.line text   add/replace; number only deletes (1.1 = 1.10)\n'
        '  FOCAL statement   execute immediately; keywords ignore case\n'
        '  RUN               run stored program; preserve variables\n'
        '  G / GO / GOTO [g.ll] jump; no target starts at the first stored line\n'
        '  LIST              show stored program\n'
        '  WRITE/W [ALL|g|g.ll] show all source, one group or one line\n'
        '  LOAD <file>       load program; preserve variables\n'
        '  SAVE <file>       save stored program\n'
        '  ERASE             clear program, variables and runtime state\n'
        '  HELP              show this help\n'
        '  QUIT / Q          stop FOCAL execution; return to REPL\n'
        '  EXIT              exit interpreter/RARS\n'
        'Statements: SET/S TYPE/T ASK/A GOTO/G/GO IF/I FOR/F DO/D RETURN/R QUIT/Q COMMENT/C.\n'
        'DO/D group calls a sorted group; DO/D g.ll calls one physical line.\n'
        'RETURN/R exits the innermost DO; line/group end returns naturally.\n'
        'IF/I (expr) negative[,zero[,positive]] branches by the Float32 sign.\n'
        'FOR/F variable=start[,step],limit; body loops through the physical-line tail.\n'
        'TYPE formats: % exponential; %W integer field; %W.0d fixed field.\n'
        'ASK items: "text", variable, !; each variable reads one expression after \':\'.\n'
        'Legacy integer targets, non-parenthesized IF and FOR ... DO are compatibility paths.\n')


class ReplTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        template = ROOT / 'rars_focal_interpreter.asm'
        cls.source = template.read_text(encoding='utf-8')
        cls.env = check_environment(os.environ.get('RARS_JAR'), template)

    def session(self, steps, *, after_exit='', files=None, exit_command='EXIT'):
        commands = ''.join(command + '\n' for command, _ in steps) + exit_command + '\n' + after_exit
        expected = BANNER + ''.join('> ' + output for _, output in steps) + '> '
        with tempfile.TemporaryDirectory(prefix='focal-repl-') as directory:
            directory = Path(directory)
            for name, content in (files or {}).items():
                (directory / name).write_text(content, encoding='utf-8', newline='\n')
            asm = directory / 'repl.asm'
            asm.write_text(self.source, encoding='utf-8', newline='\n')
            result = run_rars(self.env, asm, expected, stdin_text=commands, timeout=10)
        self.assertTrue(result.passed, f'{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}')

    def test_quit_and_q_return_to_repl(self):
        self.session([('QUIT', ''), ('SET A=7', ''), ('TYPE A,!', '7.0\n'),
                      ('Q', ''), ('S A=8', ''), ('T A,!', '8.0\n')])

    def test_exit_stops_process(self):
        self.session([], after_exit='TYPE "MUST NOT PRINT",!\n')

    def test_run_list_and_stored_quit(self):
        self.session([('1 TYPE "Before",!', ''), ('2 Q', ''), ('3 TYPE "Never",!', ''),
                      ('RUN', 'Before\n'), ('LIST', '1.01 TYPE "Before",!\n1.02 Q\n1.03 TYPE "Never",!\n'),
                      ('TYPE "After",!', 'After\n')])

    def test_invalid_prefixes(self):
        for token in ['RUNNER', 'LISTING', 'HELPER', 'SOMETHING', 'SE', 'TYP', 'AS',
                      'GOBLIN', 'GOTOXYZ', 'FO', 'FOOBAR', 'RET', 'RETURNING', 'QUI',
                      'EXI', 'EXITING', 'ERASER', 'LOADER', 'SAVER', 'COMM', 'WRIT',
                      'SET1', 'SET_X', 'RUN123']:
            with self.subTest(token=token):
                self.session([(token, UNKNOWN), ('QUIT', ''), ('TYPE "Alive",!', 'Alive\n')])

    def test_return_do_and_write_dispatch(self):
        for token in ['RETURN', 'R']:
            with self.subTest(token=token):
                self.session([('1 TYPE "NOT RUN",!', ''), (token, CONTEXT), ('Q', '')])
        for token in ['DO', 'D']:
            with self.subTest(token=token):
                self.session([('1 TYPE "NOT RUN",!', ''), (token, SYNTAX), ('Q', '')])
        # WRITE displays stored source without executing it.
        for token in ['WRITE', 'W']:
            with self.subTest(token=token):
                self.session([('1 TYPE "NOT RUN",!', ''), (token, '1.01 TYPE "NOT RUN",!\n'), ('Q', '')])

    def test_goto_argument_uses_stored_line_target(self):
        for token in ['G', 'GO', 'GOTO']:
            with self.subTest(token=token):
                self.session([('1 TYPE "TARGET",!', ''), (token + ' 1', 'TARGET\n'), ('Q', '')])

    def test_goto_without_argument_runs_through_focal_dispatch(self):
        for token in ['G', 'gO', 'GoTo']:
            with self.subTest(token=token):
                self.session([('S A=9', ''), ('1 TYPE A,!', ''), (token, '9.0\n')])

    def test_mixed_case_and_source_preservation(self):
        self.session([('1 tYpE "MiXeD Text",!', ''), ('2 qUiT', ''),
                      ('rUn', 'MiXeD Text\n'), ('lIsT', '1.01 tYpE "MiXeD Text",!\n1.02 qUiT\n'),
                      ('sEt a=5', ''), ('tYpE a,!', '5.0\n')])

    def test_help_and_mixed_case_exit(self):
        self.session([('hElP', HELP)])
        # No final prompt after the first EXIT; remaining input must be ignored.
        self.session([], exit_command='eXiT', after_exit='TYPE "bad",!\n')

    def test_erase_clears_program_scalar_array_and_runtime(self):
        self.session([('S A=7', ''), ('S B(2)=9', ''), ('1 Q', ''),
                      ('eRaSe', ''), ('LIST', ''), ('RUN', 'No program\n'),
                      ('T A,!', '0.0\n'), ('T B(2),!', '0.0\n')])

    def test_run_and_other_commands_preserve_variables(self):
        self.session([('S A=6', ''), ('1 TYPE A,!', ''), ('RUN', '6.0\n'),
                      ('RUN', '6.0\n'), ('LIST', '1.01 TYPE A,!\n'),
                      ('sAvE state.focal', 'Saved\n'), ('lOaD state.focal', 'Loaded\n'),
                      ('T A,!', '6.0\n'), ('RUN', '6.0\n')])

    def test_abbreviations_in_existing_grammar(self):
        self.session([('1 s A=0', ''), ('2 f I=1,3 d s A=A+I', ''),
                      ('3 i A=6 tHeN 5', ''), ('4 t "bad",!', ''), ('5 t A,!', ''),
                      ('6 g 8', ''), ('7 t "bad",!', ''), ('8 q', ''), ('RUN', '6.0\n')])

    def test_ask_abbreviation(self):
        for token in ['a', 'aSk']:
            with self.subTest(token=token):
                self.session([(token + ' "Value?",A\n1+2', 'Value?:'),
                              ('t A,!', '3.0\n')])

    def test_comments_preserve_text_and_do_not_execute_tail(self):
        self.session([('c TyPe "no"', ''), ('1 CoMmEnT arbitrary MiXeD text', ''),
                      ('2 T "yes",!', ''), ('RUN', 'yes\n'),
                      ('LIST', '1.01 CoMmEnT arbitrary MiXeD text\n1.02 T "yes",!\n')])

    def test_environment_requires_no_extra_arguments(self):
        for token in ['RUN', 'LIST', 'ERASE', 'HELP', 'EXIT']:
            with self.subTest(token=token):
                self.session([('1 Q', ''), (token + ' extra', SYNTAX), ('LIST', '1.01 Q\n')])

    def test_load_uses_same_token_matching_and_preserves_case(self):
        self.session([('LOAD mixed.focal', 'Loaded\n'), ('RUN', 'FiLe\n'),
                      ('LIST', '1.01 t "FiLe",!\n1.02 q\n')], files={'mixed.focal': '1 t "FiLe",!\n2 q\n'})

    def test_stored_prefixes_do_not_execute_as_statements(self):
        for token in ['SOMETHING', 'TYP', 'GOTOXYZ', 'FOOBAR', 'RUNNER']:
            with self.subTest(token=token):
                self.session([('1 ' + token, ''), ('RUN', UNKNOWN),
                              ('LIST', '1.01 ' + token + '\n'), ('T "Alive",!', 'Alive\n')])

    def test_nested_legacy_keyword_prefixes_are_rejected(self):
        for statement in ['IF 1 THENXYZ 2', 'IF 1 GOBLIN 2', 'FOR I=1,2 DOOM TYPE I']:
            with self.subTest(statement=statement):
                self.session([(statement, SYNTAX), ('T "Alive",!', 'Alive\n')])


if __name__ == '__main__':
    unittest.main()
