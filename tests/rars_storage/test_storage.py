"""Historical line keys/storage/view: exact output from the real target ASM."""
import os
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools'))
from rars_test_support import check_environment, run_rars
from embed_rars_demo import asm_string

BANNER = 'FOCAL/RARS REPL. Enter HELP for commands.\n'
NUMBER_ERROR = 'FOCAL/RARS error [E14]: invalid line number or selector\n'
CAPACITY = 'FOCAL/RARS error [E08]: line table/storage bounds\n'
TEXT_ERROR = 'FOCAL/RARS error [E07]: text buffer bounds\n'
MISSING = 'FOCAL/RARS error [E08]: line not found\n'


def listing(rows):
    return ''.join(f'{key} {text}\n' for key, text in rows)


class StorageTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / 'rars_focal_interpreter.asm'
        cls.source = cls.template.read_text(encoding='utf-8')
        cls.env = check_environment(os.environ.get('RARS_JAR'), cls.template)

    def execute(self, source, expected, stdin=None, files=None):
        with tempfile.TemporaryDirectory(prefix='focal-storage-') as directory:
            directory = Path(directory)
            for name, value in (files or {}).items():
                (directory / name).write_text(value, encoding='utf-8', newline='\n')
            asm = directory / 'storage.asm'
            asm.write_text(source, encoding='utf-8', newline='\n')
            result = run_rars(self.env, asm, expected, stdin_text=stdin)
        self.assertTrue(result.passed, f'{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}')

    def session(self, steps, files=None):
        self.execute(self.source, BANNER + ''.join('> ' + out for _, out in steps) + '> ',
                     ''.join(command + '\n' for command, _ in steps) + 'EXIT\n', files)

    def test_normalization_order_and_distinct_fraction(self):
        self.session([('99.99 Q', ''), ('10.3 C ten', ''), ('2.01 C hundredth', ''),
                      ('2.1 C tenth', ''), ('1.1 C old', ''), ('01.10 C replacement', ''),
                      ('1.01 C first', ''), ('2.5 C half', ''),
                      ('LIST', listing([('1.01', 'C first'), ('1.10', 'C replacement'),
                                       ('2.01', 'C hundredth'), ('2.10', 'C tenth'),
                                       ('2.50', 'C half'), ('10.30', 'C ten'), ('99.99', 'Q')]))])

    def test_invalid_numbers_keep_source(self):
        for number in ['0.10', '100.10', '1.00', '1.', '1.001', '1.1x', '1..1',
                       '01.000', '999999999999.1', '1.1.1']:
            with self.subTest(number=number):
                self.session([('1.01 C Keep', ''), (number + ' Q', NUMBER_ERROR),
                              ('LIST', '1.01 C Keep\n')])

    def test_missing_group_and_nonnumeric_rejected(self):
        for number in ['.10', 'x.10', '-1.10']:
            with self.subTest(number=number):
                self.session([(number + ' Q', 'FOCAL/RARS error [E10]: unknown statement\n'),
                              ('LIST', '')])

    def test_replace_delete_and_reuse(self):
        self.session([('2.1 C Two', ''), ('1.01 C One', ''), ('2.10 C New', ''),
                      ('1.01', ''), ('1.01', ''), ('1.1 C Reused', ''),
                      ('LIST', '1.10 C Reused\n2.10 C New\n'),
                      ('2.1', ''), ('1.10', ''), ('LIST', '')])

    def test_full_capacity_replace_delete_reuse(self):
        keys = [f'1.{n:02}' for n in range(1, 100)] + [f'2.{n:02}' for n in range(1, 30)]
        steps = [(key + ' Q', '') for key in reversed(keys)]
        steps += [('3.01 Q', CAPACITY), ('1.01 C replaced', ''), ('1.50', ''),
                  ('3.01 C reused', ''), ('LIST', listing(
                      [(k, 'C replaced' if k == '1.01' else 'Q') for k in keys if k != '1.50']
                      + [('3.01', 'C reused')]))]
        self.session(steps)

    def test_reuse_repeated_more_than_physical_capacity(self):
        steps = []
        for _ in range(140):
            steps += [('1.01 C temp', ''), ('1.01', '')]
        self.session(steps + [('99.99 Q', ''), ('LIST', '99.99 Q\n')])

    def test_text_boundary_case_and_spaces(self):
        text = 'C ' + 'x' * 125
        self.session([('1.01 ' + text, ''), ('LIST', '1.01 ' + text + '\n'),
                      ('1.01 ' + text + 'x', TEXT_ERROR), ('LIST', '1.01 ' + text + '\n'),
                      ('2.1: tYpE  "MiXeD  Text" , !', ''), ('WRITE 2.10', '2.10 tYpE  "MiXeD  Text" , !\n')])

    def test_list_and_write_all_stream_beyond_program_buffer(self):
        keys = [f'1.{n:02}' for n in range(1, 100)] + [f'2.{n:02}' for n in range(1, 30)]
        text = 'C ' + 'x' * 125
        expected = listing([(key, text) for key in keys])
        self.session([(key + ' ' + text, '') for key in keys] + [('LIST', expected), ('W ALL', expected)])

    def test_write_all_aliases_and_empty(self):
        steps = [('LIST', ''), ('WRITE', ''), ('W ALL', ''), ('2.1 C second', ''), ('1.01 C first', '')]
        expected = '1.01 C first\n2.10 C second\n'
        steps += [(command, expected) for command in ['WRITE', 'W', 'WRITE ALL', 'w aLl', 'LIST']]
        self.session(steps)

    def test_write_group_and_exact(self):
        self.session([('2.01 C a', ''), ('2.1 C b', ''), ('1.01 C c', ''),
                      ('WRITE 2', '2.01 C a\n2.10 C b\n'), ('W 02', '2.01 C a\n2.10 C b\n'),
                      ('WRITE 2.01', '2.01 C a\n'), ('W 2.1', '2.10 C b\n'),
                      ('WRITE 3', MISSING), ('W 2.02', MISSING), ('T "Alive",!', 'Alive\n')])

    def test_invalid_write_selectors(self):
        for selector in ['0', '100', '1.00', '2.', '1.001', 'ALL extra', '2 extra', '2.01 extra', 'AL']:
            with self.subTest(selector=selector):
                # Invalid selector syntax has one dedicated error category.
                self.session([('WRITE ' + selector, NUMBER_ERROR), ('T "Alive",!', 'Alive\n')])

    def test_write_inside_program_and_variables_unchanged(self):
        self.session([('S A=7', ''), ('1.01 W 2', ''), ('1.02 Q', ''), ('2.1 C Viewed', ''),
                      ('RUN', '2.10 C Viewed\n'), ('T A,!', '7.0\n'), ('WRITE 1.01', '1.01 W 2\n')])

    def test_run_sorted_and_canonical_goto_mapping(self):
        self.session([('1.20 T "third",!', ''), ('1.10 T "second",!', ''), ('1.01 GOTO 1.1', ''),
                      ('1.30 Q', ''), ('RUN', 'second\nthird\n'), ('1.10 GOTO 1.20', ''),
                      ('1.01 TYPE "first",!', ''), ('RUN', 'first\nthird\n')])

    def test_batch_shared_number_parser(self):
        program = '1.01: TYPE "first",!\n1.1 GOTO 2.01\n1.20 TYPE "bad",!\n2.01 TYPE "second",!\n2.10 Q\n'
        source, count = re.subn(r'(?m)(^focal_program:\n)\s*\.asciz[^\n]*',
                                lambda m: m[1] + asm_string(program), self.source)
        self.assertEqual(count, 1)
        source = source.replace('repl_enabled:   .word 1', 'repl_enabled:   .word 0', 1)
        self.execute(source, 'first\nsecond\n')

    def test_batch_sorted_replacement_and_delete(self):
        program = ('2.01 TYPE "last",!\n1.1 TYPE "old",!\n1.01 TYPE "first",!\n'
                   '1.10 TYPE "second",!\n1.20 TYPE "deleted",!\n1.20\n')
        source = re.sub(r'(?m)(^focal_program:\n)\s*\.asciz[^\n]*',
                        lambda m: m[1] + asm_string(program), self.source)
        source = source.replace('repl_enabled:   .word 1', 'repl_enabled:   .word 0', 1)
        self.execute(source, 'first\nsecond\nlast\n')

    def test_load_save_canonical_source_and_legacy_migration(self):
        self.session([('LOAD old.focal', 'Loaded\n'), ('LIST', '1.01 C One\n2.01 Q\n'),
                      ('SAVE canonical.focal', 'Saved\n'), ('ERASE', ''),
                      ('LOAD canonical.focal', 'Loaded\n'), ('LIST', '1.01 C One\n2.01 Q\n')],
                     {'old.focal': '1: C One\n100: Q\n'})

    def test_load_clears_old_slots_but_keeps_variables(self):
        self.session([('1.01 C old', ''), ('2.01 C old', ''), ('1.01', ''), ('S A=9', ''),
                      ('LOAD fresh.focal', 'Loaded\n'), ('LIST', '3.01 C fresh\n'),
                      ('T A,!', '9.0\n'), ('2.01 C new', ''),
                      ('LIST', '2.01 C new\n3.01 C fresh\n')], {'fresh.focal': '3.01 C fresh\n'})

    def test_line_table_keys_addresses_and_abi(self):
        # This harness calls target procedures; no independent VM or parser.
        source = re.sub(r'(?m)(^focal_program:\n)\s*\.asciz[^\n]*',
                        lambda m: m[1] + asm_string('1.10 TYPE "second",!\n1.01 TYPE "first",!\n'), self.source)
        seed = ''.join(f'li s{n}, {700+n}\n' for n in range(12))
        verify = ''.join(f'li t0, {700+n}\nbne s{n}, t0, address_fail\n' for n in range(12))
        body = '''
.text
main:
    andi sp, sp, -16
    call init_safety
    call reset_runtime
    sw sp, address_sp, t0
''' + seed + '''
    la t0, focal_program
    sw t0, source_ptr, t1
    call compile_program
    lw t0, error_code
    bnez t0, address_fail
    lw t0, line_count
    li t1, 2
    bne t0, t1, address_fail
    la t0, line_numbers
    lw t1, 0(t0)
    li t2, 101
    bne t1, t2, address_fail
    lw t1, 4(t0)
    li t2, 110
    bne t1, t2, address_fail
    li a0, 101
    call set_pc_to_line
    lw t0, pc_ptr
    lw t1, line_offsets
    bnez t1, address_fail
    la t2, bytecode_buf
    add t1, t1, t2
    bne t0, t1, address_fail
    li a0, 110
    call set_pc_to_line
    lw t0, pc_ptr
    la t1, line_offsets
    lw t2, 0(t1)
    lw t1, 4(t1)
    la t3, bytecode_buf
    add t4, t3, t1
    bne t0, t4, address_fail
    bleu t1, t2, address_fail
    lw t0, bc_ptr
    sub t0, t0, t3
    bgeu t1, t0, address_fail
    lw t0, error_code
    bnez t0, address_fail
''' + verify + '''
    lw t0, address_sp
    bne sp, t0, address_fail
    la a0, address_ok
    li a7, 4
    ecall
    li a7, 10
    ecall
address_fail:
    la a0, address_bad
    li a7, 4
    ecall
    li a7, 10
    ecall
'''
        source = source.replace('\nmain:\n', '\nfocal_main:\n', 1)
        source = source.replace('\n.text\n', body + '\n.text\n', 1)
        source += '\n.data\n.align 2\naddress_sp: .word 0\naddress_ok: .asciz "PASS\\n"\naddress_bad: .asciz "FAIL\\n"\n'
        self.execute(source, 'PASS\n')


if __name__ == '__main__':
    unittest.main()
