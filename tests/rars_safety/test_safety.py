"""Real RARS tests of the target ASM, not a Python implementation of its VM.

Run separately from runner self-tests. No SKIP on missing environment.
The harness inserts only a test entry point/data into a temporary copy;
all tested procedures are the unmodified procedures of the target file.
"""

import os
from pathlib import Path
import re
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from rars_test_support import check_environment, run_rars
from embed_rars_demo import asm_string


def error_is(name):
    return f"lw t0, error_code\nli t1, {name}\nbne t0, t1, test_fail\n"


def pointer_is(pointer, address):
    return f"lw t0, {pointer}\nla t1, {address}\nbne t0, t1, test_fail\n"


CASES = {
    "bytecode_last_word_and_overflow": """la t0, bytecode_end
addi t0, t0, -4
sw t0, bc_ptr, t1
la t0, bytecode_end
li t1, 12345
sw t1, 0(t0)
li a0, 42
call emit_word
lw t0, error_code
bnez t0, test_fail
li a0, 99
call emit_word
""" + error_is("ERR_BC_FULL") + pointer_is("bc_ptr", "bytecode_end") + """
la t0, bytecode_end
lw t1, 0(t0)
li t2, 12345
bne t1, t2, test_fail
lw t1, -4(t0)
li t2, 42
bne t1, t2, test_fail
""",
    "fetch_past_generated_code": "la t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall fetch_word\n" + error_is("ERR_BC_ACCESS"),
    "unaligned_emit": "la t0, bytecode_buf\naddi t0, t0, 1\nsw t0, bc_ptr, t1\ncall emit_word\n" + error_is("ERR_BC_ACCESS"),
    "patch_outside_generated_code": "la a0, bytecode_buf\nli a1, 17\ncall patch_word\n" + error_is("ERR_BC_ACCESS"),
    "patch_last_generated_word": "li a0, OP_HALT\ncall emit_word\nla a0, bytecode_buf\nli a1, OP_NOP\ncall patch_word\nlw t0, bytecode_buf\nli t1, OP_NOP\nbne t0, t1, test_fail\n" + error_is("0"),
    "vm_overflow": """
la t0, vm_stack_end
addi t0, t0, -4
sw t0, vm_sp_ptr, t1
li t1, 777
sw t1, 4(t0)
fmv.w.x ft0, zero
call vm_push_ft0
lw t0, error_code
bnez t0, test_fail
call vm_push_ft0
""" + error_is("ERR_VM_OVERFLOW") + pointer_is("vm_sp_ptr", "vm_stack_end") + "lw t0, vm_stack_end\nli t1, 777\nbne t0, t1, test_fail\n",
    "vm_underflow": "call vm_pop_ft0\n" + error_is("ERR_VM_UNDERFLOW") + pointer_is("vm_sp_ptr", "vm_stack"),
    "binary_pop_is_atomic": """
li t0, 123
fmv.w.x ft0, t0
call vm_push_ft0
call vm_pop2
""" + error_is("ERR_VM_UNDERFLOW") + "la t0, vm_stack\naddi t1, t0, 4\nlw t2, vm_sp_ptr\nbne t1, t2, test_fail\nlw t1, 0(t0)\nli t2, 123\nbne t1, t2, test_fail\n",
    "bad_stack_pointer": "la t0, vm_stack\naddi t0, t0, 1\nsw t0, vm_sp_ptr, t1\ncall vm_pop_ft0\n" + error_is("ERR_VM_UNDERFLOW") + pointer_is("vm_sp_ptr", "vm_stack"),
    "string_pool_overflow": """
la a0, test_string
li a1, 4
call set_parse_span
la t0, test_string
sw t0, parse_ptr, t1
la t0, str_pool_end
addi t0, t0, -1
sw t0, str_pool_ptr, t1
li t1, 55
sb t1, 0(t0)
sb t1, 1(t0)
call copy_string_to_pool
""" + error_is("ERR_STRING") + "la t0, str_pool_end\nlbu t1, 0(t0)\nli t2, 55\nbne t1, t2, test_fail\nlbu t1, -1(t0)\nbne t1, t2, test_fail\n",
    "program_nul_reservation": """
la s4, program_buf_end
addi s4, s4, -2
li a0, 65
call repl_append_char_to_program
lw t0, error_code
bnez t0, test_fail
li a0, 66
call repl_append_char_to_program
""" + error_is("ERR_PROGRAM") + "la t0, program_buf_end\nlbu t1, -1(t0)\nbnez t1, test_fail\nlbu t1, -2(t0)\nli t2, 65\nbne t1, t2, test_fail\n",
    "line_table_overflow": """
li t0, MAX_LINES
sw t0, line_count, t1
la t0, line_numbers_end
li t1, 4321
sw t1, 0(t0)
li a0, 129
call add_line_table_entry
""" + error_is("ERR_LINES") + "lw t0, line_count\nli t1, MAX_LINES\nbne t0, t1, test_fail\nlw t0, line_numbers_end\nli t1, 4321\nbne t0, t1, test_fail\n",
    "repl_storage_overflow": """
li t0, MAX_LINES
sw t0, repl_line_count, t1
la t0, input_line
li t1, 49
sb t1, 0(t0)
li t1, 32
sb t1, 1(t0)
li t1, 81
sb t1, 2(t0)
sb zero, 3(t0)
mv a0, t0
call repl_store_line
""" + error_is("ERR_LINES"),
    "invalid_repl_slot": "li a0, 128\ncall repl_text_addr\n" + error_is("ERR_LINES"),
    "array_bounds": "li t2, 0\nli t3, 100\ncall array_addr\n" + error_is("ERR_ARRAY"),
    "missing_operand": "li a0, OP_PUSH_F\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_BC_ACCESS"),
    "unknown_opcode": "li a0, 999\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_BC_ACCESS"),
    "malformed_string_operand": "li a0, OP_PRINT_S\ncall emit_word\nli a0, 1\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_STRING"),
    "malformed_variable_operand": "li a0, OP_PUSH_V\ncall emit_word\nli a0, 26\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_ARRAY"),
    "bad_absolute_jump": "li a0, OP_JUMP_ABS\ncall emit_word\nli a0, 1\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_BC_ACCESS"),
    "procedural_stack_guard": "mv t0, sp\nsw t0, proc_stack_floor, t1\ncall compile_program\n" + error_is("ERR_PROC_STACK"),
}


CASES.update({
    "last_fetch_then_end": "li a0, OP_HALT\ncall emit_word\ncall fetch_word\nli t0, OP_HALT\nbne a0, t0, test_fail\ncall fetch_word\n" + error_is("ERR_BC_ACCESS"),
    "corrupt_emitted_end": "li t0, -4\nsw t0, bc_ptr, t1\ncall fetch_word\n" + error_is("ERR_BC_ACCESS"),
    "unaligned_patch": "li a0, 1\ncall emit_word\nla a0, bytecode_buf\naddi a0, a0, 1\ncall patch_word\n" + error_is("ERR_BC_ACCESS"),
    "binary_pop_order": "li t0, 11\nfmv.w.x ft0, t0\ncall vm_push_ft0\nli t0, 22\nfmv.w.x ft0, t0\ncall vm_push_ft0\ncall vm_pop2\nfmv.x.w t0, ft0\nli t1, 22\nbne t0, t1, test_fail\nfmv.x.w t0, ft1\nli t1, 11\nbne t0, t1, test_fail\n" + pointer_is("vm_sp_ptr", "vm_stack") + error_is("0"),
    "empty_binary_pop": "call vm_pop2\n" + error_is("ERR_VM_UNDERFLOW") + pointer_is("vm_sp_ptr", "vm_stack"),
    "invalid_push_pointer": "li t0, -4\nsw t0, vm_sp_ptr, t1\ncall vm_push_ft0\n" + error_is("ERR_VM_OVERFLOW") + pointer_is("vm_sp_ptr", "vm_stack"),
    "last_pool_string": "la a0, test_string\nli a1, 4\ncall set_parse_span\nla t0, str_pool_end\naddi t0, t0, -2\nsw t0, str_pool_ptr, t1\ncall copy_string_to_pool\nlbu t0, 0(a0)\nli t1, 120\nbne t0, t1, test_fail\nlbu t0, 1(a0)\nbnez t0, test_fail\n" + pointer_is("str_pool_ptr", "str_pool_end") + error_is("0"),
    "unterminated_pool_operand": "la t0, str_pool\nli t1, 65\nsb t1, 0(t0)\naddi t1, t0, 1\nsw t1, str_pool_ptr, t2\nmv a0, t0\ncall check_pool_string\n" + error_is("ERR_STRING"),
    "last_line_entry": "li t0, 127\nsw t0, line_count, t1\nli a0, 128\ncall add_line_table_entry\nlw t0, line_count\nli t1, 128\nbne t0, t1, test_fail\nla t0, line_offsets_end\nlw t1, -4(t0)\nbnez t1, test_fail\n" + error_is("0"),
    "corrupt_line_lookup_count": "li t0, -1\nsw t0, line_count, t1\nli a0, 1\ncall set_pc_to_line\n" + error_is("ERR_LINES"),
    "corrupt_repl_lookup_count": "li t0, -1\nsw t0, repl_line_count, t1\ncall repl_find_line\n" + error_is("ERR_LINES"),
    "last_repl_slot": "li a0, 127\ncall repl_text_addr\nla t0, repl_texts_end\naddi t0, t0, -128\nbne a0, t0, test_fail\n" + error_is("0"),
    "negative_array_index": "li t2, 0\nli t3, -1\ncall array_addr\n" + error_is("ERR_ARRAY"),
    "last_array_element": "li t2, 25\nli t3, 99\ncall array_addr\nla t0, arrays_end\naddi t0, t0, -4\nbne a0, t0, test_fail\n" + error_is("0"),
    "invalid_parse_pointer": "la a0, test_string\nli a1, 4\ncall set_parse_span\nli t0, 1\nsw t0, parse_ptr, t1\ncall compile_expr\n" + error_is("ERR_SYNTAX"),
    "sticky_error_and_reset": "call vm_pop_ft0\ncall emit_word\ncall error_string\n" + error_is("ERR_VM_UNDERFLOW") + pointer_is("bc_ptr", "bytecode_buf") + "call reset_runtime\n" + error_is("0") + pointer_is("vm_sp_ptr", "vm_stack") + pointer_is("pc_ptr", "bytecode_buf") + pointer_is("str_pool_ptr", "str_pool"),
    "nested_stack_unwind": "la a0, test_string\nli a1, 4\ncall set_parse_span\naddi t0, sp, -32\nsw t0, proc_stack_floor, t1\ncall compile_expr\n" + error_is("ERR_PROC_STACK"),
})


class SafetyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.template = ROOT / "rars_focal_interpreter.asm"
        cls.source = cls.template.read_text(encoding="utf-8")
        cls.env = check_environment(os.environ.get("RARS_JAR"), cls.template)

    def harness(self, body):
        entry = """
.text
main:
    andi sp, sp, -16
    call init_safety
    call reset_runtime
    sw sp, test_sp, t0
""" + body + """
    lw t0, test_sp
    bne sp, t0, test_fail
    la a0, test_pass_message
    li a7, 4
    ecall
    li a7, 10
    ecall
test_fail:
    la a0, test_fail_message
    li a7, 4
    ecall
    li a7, 10
    ecall
"""
        target = self.source.replace("\nmain:\n", "\nfocal_main:\n", 1)
        target = target.replace("\n.text\n", entry + "\n.text\n", 1)
        return target + '\n.data\n.align 2\ntest_sp: .word 0\ntest_pass_message: .asciz "PASS\\n"\ntest_fail_message: .asciz "FAIL\\n"\ntest_string: .asciz "\\\"x\\\""\n'

    def execute(self, source, expected, stdin=None, files=None):
        if stdin is not None:
            # Stage 2 used a final bare QUIT solely as test-session teardown.
            # FR-15/23 now require EXIT there; stored FOCAL QUIT and every
            # safety assertion/expected output remain unchanged.
            self.assertTrue(stdin.endswith('\nQUIT\n'))
            stdin = stdin.removesuffix('QUIT\n') + 'EXIT\n'
        with tempfile.TemporaryDirectory(prefix="focal-safety-") as directory:
            for name, content in (files or {}).items():
                (Path(directory) / name).write_text(content, encoding="utf-8", newline="\n")
            asm = Path(directory) / "safety.asm"
            asm.write_text(source, encoding="utf-8", newline="\n")
            result = run_rars(self.env, asm, expected, stdin_text=stdin)
        self.assertTrue(result.passed, f"{result.category}: {result.detail}\n{result.stdout}\n{result.stderr}")

    def test_low_level_boundaries(self):
        for name, body in CASES.items():
            with self.subTest(name=name):
                self.execute(self.harness(body), "PASS\n")

    def test_repl_recovers_and_keeps_source(self):
        commands = '1 TYPE "KEEP",!\nTYPE A(100),!\nTYPE "AFTER",!\nLIST\nQUIT\n'
        expected = ('FOCAL/RARS REPL. Enter HELP for commands.\n> > '
                    'FOCAL/RARS error [E09]: variable/array bounds\n'
                    '> AFTER\n> 1.01 TYPE "KEEP",!\n> ')
        self.execute(self.source, expected, commands)

    def test_long_replacement_keeps_original(self):
        commands = '1 TYPE "KEEP",!\n1 ' + 'X' * 128 + '\nLIST\nQUIT\n'
        expected = ('FOCAL/RARS REPL. Enter HELP for commands.\n> > '
                    'FOCAL/RARS error [E07]: text buffer bounds\n'
                    '> 1.01 TYPE "KEEP",!\n> ')
        self.execute(self.source, expected, commands)

    def test_repeated_compile_errors_recover(self):
        bad = ['TYPE (', 'TYPE A(', 'TYPE "open', 'SET A=', 'S']
        diagnostics = [10, 10, 5, 10, 10]
        messages = {10: 'invalid source', 5: 'string pool bounds'}
        commands = '1 TYPE "KEEP",!\n'
        expected = 'FOCAL/RARS REPL. Enter HELP for commands.\n> > '
        for command, code in zip(bad * 4, diagnostics * 4):
            commands += command + '\nTYPE "AFTER",!\n'
            expected += f'FOCAL/RARS error [E{code:02}]: {messages[code]}\n> AFTER\n> '
        commands += 'LIST\nQUIT\n'
        expected += '1.01 TYPE "KEEP",!\n> '
        self.execute(self.source, expected, commands)

    def test_full_input_rejected_without_truncation(self):
        self.execute(self.source,
                     'FOCAL/RARS REPL. Enter HELP for commands.\n> '
                     'FOCAL/RARS error [E07]: text buffer bounds\n> AFTER\n> ',
                     'X' * 300 + '\nTYPE "AFTER",!\nQUIT\n')

    def test_repl_last_slot_and_overflow(self):
        commands = ''.join(f'{n} QUIT\n' for n in range(1, 130))
        commands += 'RUN\nTYPE "AFTER",!\nQUIT\n'
        expected = ('FOCAL/RARS REPL. Enter HELP for commands.\n' + '> ' * 129
                    + 'FOCAL/RARS error [E08]: line table/storage bounds\n> > AFTER\n> ')
        self.execute(self.source, expected, commands)

    def test_run_buffer_overflow_keeps_source(self):
        line = 'TYPE "' + 'x' * 116 + '",!'
        commands = ''.join(f'{n} {line}\n' for n in range(1, 70))
        commands += 'RUN\n' + ''.join(f'{n}\n' for n in range(2, 70)) + 'LIST\nQUIT\n'
        expected = ('FOCAL/RARS REPL. Enter HELP for commands.\n' + '> ' * 70
                    + 'FOCAL/RARS error [E06]: program buffer bounds\n' + '> ' * 69
                    + f'1.01 {line}\n> ')
        self.execute(self.source, expected, commands)

    def test_load_error_keeps_source(self):
        for content, code, message in [
            ('1 QUIT\n2 ' + 'x' * 128 + '\n', 7, 'text buffer bounds'),
            (''.join(f'{n} QUIT\n' for n in range(1, 130)), 8, 'line table/storage bounds'),
            # Stage 5 streams files beyond 8191 bytes; this is now rejected
            # because its single physical line cannot fit, not by file size.
            ('x' * 8192, 7, 'text buffer bounds'),
            ('1 ' + 'x' * 256 + '\n', 7, 'text buffer bounds'),
        ]:
            with self.subTest(code=code, size=len(content)):
                self.execute(self.source,
                             'FOCAL/RARS REPL. Enter HELP for commands.\n> > '
                             f'FOCAL/RARS error [E{code:02}]: {message}\n'
                             '> 1.01 TYPE "KEEP",!\n> AFTER\n> ',
                             '1 TYPE "KEEP",!\nLOAD bad.focal\nLIST\nTYPE "AFTER",!\nQUIT\n',
                             {'bad.focal': content})

    def test_load_and_save_existing_format(self):
        self.execute(self.source,
                     'FOCAL/RARS REPL. Enter HELP for commands.\n> > Saved\n> > Loaded\n> KEEP\n> ',
                     '1 TYPE "KEEP",!\nSAVE saved.focal\nERASE\nLOAD saved.focal\nRUN\nQUIT\n')

    def test_abi_success_and_error(self):
        seed = ''.join(f'li s{n}, {700+n}\n' for n in range(12))
        verify = ''.join(f'li t0, {700+n}\nbne s{n}, t0, test_fail\n' for n in range(12))
        body = (seed + 'la t0, focal_program\nsw t0, source_ptr, t1\ncall compile_program\n'
                + error_is('0') + verify + 'li a0, 101\ncall set_pc_to_line\n'
                + error_is('0') + verify + 'call reset_runtime\nli a0, OP_ADD\ncall emit_word\n'
                + 'call vm_run\n' + error_is('ERR_VM_UNDERFLOW') + verify)
        self.execute(self.harness(body), 'PASS\n')

    def test_compiler_limits_in_batch(self):
        for program, code, message in [
            (''.join(f'{n}: QUIT\n' for n in range(1, 130)), 8, 'line table/storage bounds'),
            ('1: TYPE ' + '(' * 1500 + '1' + ')' * 1500 + '\n', 11, 'procedural stack limit'),
        ]:
            with self.subTest(code=code):
                source, count = re.subn(r'(?m)(^focal_program:\n)\s*\.asciz[^\n]*',
                                        lambda m: m[1] + asm_string(program), self.source)
                self.assertEqual(count, 1)
                source = source.replace('repl_enabled:   .word 1', 'repl_enabled:   .word 0', 1)
                self.execute(source, f'FOCAL/RARS error [E{code:02}]: {message}\n')

    def test_compiler_resource_errors_recover(self):
        for statement, code, message in [
            ('TYPE ' + ','.join(['1'] * 40), 1, 'bytecode capacity'),
            ('TYPE "' + 'x' * 100 + '"', 5, 'string pool bounds'),
        ]:
            with self.subTest(code=code):
                commands = ''.join(f'{n} {statement}\n' for n in range(1, 61))
                commands += 'RUN\nTYPE "AFTER",!\n'
                commands += ''.join(f'{n}\n' for n in range(2, 61)) + 'LIST\nQUIT\n'
                expected = ('FOCAL/RARS REPL. Enter HELP for commands.\n' + '> ' * 61
                            + f'FOCAL/RARS error [E{code:02}]: {message}\n> AFTER\n'
                            + '> ' * 60 + f'1.01 {statement}\n> ')
                self.execute(self.source, expected, commands)

    def test_runtime_error_does_not_rollback_variables(self):
        self.execute(self.source,
                     'FOCAL/RARS REPL. Enter HELP for commands.\n> > > '
                     'FOCAL/RARS error [E09]: variable/array bounds\n> 7.0\n'
                     '> 1.01 SET A=7\n1.02 TYPE A(100),!\n> ',
                     '1 SET A=7\n2 TYPE A(100),!\nRUN\nTYPE A,!\nLIST\nQUIT\n')


if __name__ == "__main__":
    unittest.main()
