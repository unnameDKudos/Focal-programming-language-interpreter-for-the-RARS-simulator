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


def for_image(*, key=73, explicit_step=False):
    """Emit one valid ENTER/HALT/NEXT/HALT FOR block into bytecode_buf."""
    return f"""
li a0, OP_FOR_ENTER
call emit_word
li a0, {key}
call emit_word
li a0, {1 if explicit_step else 0}
call emit_word
la a0, bytecode_buf
addi a0, a0, 24
call emit_word
la a0, bytecode_buf
addi a0, a0, 28
call emit_word
la a0, bytecode_buf
addi a0, a0, 32
call emit_word
li a0, OP_HALT
call emit_word
li a0, OP_FOR_NEXT
call emit_word
li a0, OP_HALT
call emit_word
"""


def empty_for_image(*, key=73):
    """Emit a valid ENTER/NEXT/HALT block whose body emits zero words."""
    return f"""
li a0, OP_FOR_ENTER
call emit_word
li a0, {key}
call emit_word
li a0, 0
call emit_word
la a0, bytecode_buf
addi a0, a0, 24
call emit_word
la a0, bytecode_buf
addi a0, a0, 24
call emit_word
la a0, bytecode_buf
addi a0, a0, 28
call emit_word
li a0, OP_FOR_NEXT
call emit_word
li a0, OP_HALT
call emit_word
"""


def push_bits(bits):
    return f"li t0, {bits}\nfmv.w.x ft0, t0\ncall vm_push_ft0\n"


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
    "symbol_missing_lookup_no_allocation": """
li a0, 65
li a1, 0
li a2, 0
call symbol_find
bnez a0, test_fail
lw t0, symbol_count
bnez t0, test_fail
""" + error_is("0"),
    "symbol_compile_does_not_allocate": """
la a0, test_symbol_source
li a1, 32
call set_parse_span
call compile_physical_line
lw t0, symbol_count
bnez t0, test_fail
""" + error_is("0"),
    "missing_operand": "li a0, OP_PUSH_F\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_BC_ACCESS"),
    "expression_opcode_safety": """
li a0, OP_PUSH_BITS
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li a0, OP_POW
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW") + """
call reset_runtime
li a0, OP_ABS
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW") + """
call reset_runtime
li a0, OP_SQRT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW") + """
call reset_runtime
li a0, OP_TRUNC
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW") + """
call reset_runtime
li a0, OP_SGN
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW"),
    "unknown_opcode": "li a0, 999\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_BC_ACCESS"),
    "malformed_string_operand": "li a0, OP_PRINT_S\ncall emit_word\nli a0, 1\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_STRING"),
    "malformed_symbol_operand": "li a0, OP_PUSH_V\ncall emit_word\nli a0, 26\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_ARRAY"),
    "malformed_indexed_symbol_operand": """
fmv.w.x ft0, zero
call vm_push_ft0
li a0, OP_PUSH_ARR
call emit_word
li a0, 26
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_ARRAY"),
    "type_buffer_last_byte_and_overflow": """
la t0, type_num_buf_end
li t1, 85
sb t1, 0(t0)
addi a1, t0, -2
li a0, 65
call type_buf_append
lw t0, error_code
bnez t0, test_fail
la t0, type_num_buf_end
lbu t1, -2(t0)
li t2, 65
bne t1, t2, test_fail
lbu t1, -1(t0)
bnez t1, test_fail
lbu t1, 0(t0)
li t2, 85
bne t1, t2, test_fail
addi a1, t0, -1
li a0, 66
call type_buf_append
""" + error_is("ERR_TEXT") + """
la t0, type_num_buf_end
lbu t1, -1(t0)
bnez t1, test_fail
lbu t1, 0(t0)
li t2, 85
bne t1, t2, test_fail
""",
    "format_opcode_missing_operand": """
li a0, OP_SET_FORMAT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS"),
    "format_opcode_invalid_state_is_atomic": """
li t0, TYPE_FMT_FIXED
sw t0, type_format_mode, t1
li t0, 7
sw t0, type_format_width, t1
li t0, 2
sw t0, type_format_precision, t1
li a0, OP_SET_FORMAT
call emit_word
li a0, 99
call emit_word
li a0, 8
call emit_word
li a0, 3
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_SYNTAX") + """
lw t0, type_format_mode
li t1, TYPE_FMT_FIXED
bne t0, t1, test_fail
lw t0, type_format_width
li t1, 7
bne t0, t1, test_fail
lw t0, type_format_precision
li t1, 2
bne t0, t1, test_fail
""",
    "corrupt_type_format_state": """
li a0, TYPE_FMT_FIXED
li a1, 256
li a2, 0
call validate_type_format
lw t0, error_code
bnez t0, test_fail
li t0, TYPE_FMT_FIXED
sw t0, type_format_mode, t1
li t0, -1
sw t0, type_format_width, t1
sw zero, type_format_precision, t1
fmv.w.x ft0, zero
call type_print_ft0
""" + error_is("ERR_SYNTAX"),
    "print_float_stack_underflow": """
li a0, OP_PRINT_F
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW"),
    "ask_scalar_missing_operand": """
li a0, OP_ASK_V
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS"),
    "ask_malformed_symbol_operand": """
li a0, OP_ASK_V
call emit_word
li a0, 26
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_ARRAY"),
    "ask_indexed_stack_underflow": """
li a0, OP_ASK_ARR
call emit_word
li a0, 65
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW"),
    "bad_absolute_jump": "li a0, OP_JUMP_ABS\ncall emit_word\nli a0, 1\ncall emit_word\nla t0, bytecode_buf\nsw t0, pc_ptr, t1\ncall vm_run\n" + error_is("ERR_BC_ACCESS"),
    "absolute_jump_boundaries": """
li a0, OP_JUMP_ABS
call emit_word
la a0, bytecode_buf
addi a0, a0, 1
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li a0, OP_JUMP_ABS
call emit_word
la a0, bytecode_buf
addi a0, a0, -4
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li a0, OP_JUMP_ABS
call emit_word
la a0, bytecode_buf
addi a0, a0, 8
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS"),
    "jump_missing_and_unknown_line_operands": """
li a0, OP_JUMP
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li a0, OP_JUMP
call emit_word
li a0, 9999
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_LINES"),
    "sign_branch_truncated_operands": """
li a0, OP_SIGN_BRANCH
call emit_word
li a0, 101
call emit_word
li a0, 102
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS"),
    "sign_branch_stack_underflow": """
li a0, OP_SIGN_BRANCH
call emit_word
li a0, 101
call emit_word
li a0, 102
call emit_word
li a0, 103
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW"),
    "sign_branch_corrupt_selected_target": """
li t0, 0xbf800000
fmv.w.x ft0, t0
call vm_push_ft0
li a0, OP_SIGN_BRANCH
call emit_word
li a0, 9999
call emit_word
li a0, 0
call emit_word
li a0, 0
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_LINES"),
    "do_opcode_truncated_operands": """
li a0, OP_DO
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li a0, OP_DO
call emit_word
li a0, DO_KIND_LINE
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS"),
    "do_opcode_bad_kind": """
li a0, OP_DO
call emit_word
li a0, 99
call emit_word
li a0, 101
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
bnez t0, test_fail
lw t0, do_context_sentinel
li t1, 0x444f4358
bne t0, t1, test_fail
""",
    "for_enter_truncated_operands": """
li a0, OP_FOR_ENTER
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS") + """
lw t0, for_depth
bnez t0, test_fail
""",
    "for_enter_stack_underflow_is_atomic": for_image() + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_VM_UNDERFLOW") + """
lw t0, for_depth
bnez t0, test_fail
""" + pointer_is("vm_sp_ptr", "vm_stack"),
    "for_enter_bad_symbol_key": for_image(key=70) + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_ARRAY") + """
lw t0, for_depth
bnez t0, test_fail
""",
    "for_zero_step_and_zero_iteration_do_not_push": for_image(explicit_step=True)
    + push_bits("0x3f800000") + push_bits("0x80000000") + push_bits("0x40400000") + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_MATH") + """
lw t0, for_depth
bnez t0, test_fail
call reset_runtime
""" + for_image() + push_bits("0x40400000") + push_bits("0x40000000") + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
lw t0, error_code
bnez t0, test_fail
lw t0, for_depth
bnez t0, test_fail
li a0, 73
li a1, 0
li a2, 0
call symbol_load_ft0
fmv.x.w t0, ft0
li t1, 0x40400000
bne t0, t1, test_fail
""",
    "for_stack_capacity_and_sentinel": for_image() + push_bits("0x3f800000") * 2 + """
li t0, FOR_MAX
sw t0, for_depth, t1
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_CONTEXT") + """
lw t0, for_depth
li t1, FOR_MAX
bne t0, t1, test_fail
lw t0, for_context_sentinel
li t1, FOR_CTX_TAG
bne t0, t1, test_fail
""",
    "for_symbol_capacity_failure_does_not_push": for_image() + push_bits("0x3f800000") * 2 + """
li t0, SYMBOL_MAX
sw t0, symbol_count, t1
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_ARRAY") + """
lw t0, for_depth
bnez t0, test_fail
""",
    "for_next_without_context": """
li a0, OP_FOR_NEXT
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_CONTEXT") + """
lw t0, for_depth
bnez t0, test_fail
""",
    "for_next_rejects_depth_above_limit": """
li a0, OP_FOR_NEXT
call emit_word
li a0, OP_HALT
call emit_word
li t0, 17
sw t0, for_depth, t1
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_CONTEXT") + """
lw t0, for_depth
li t1, 17
bne t0, t1, test_fail
""",
    "for_next_completion_pops_and_stores_out_of_range": for_image()
    + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
lw t0, for_depth
li t1, 1
bne t0, t1, test_fail
call vm_run
lw t0, error_code
bnez t0, test_fail
lw t0, for_depth
bnez t0, test_fail
li a0, 73
li a1, 0
li a2, 0
call symbol_load_ft0
fmv.x.w t0, ft0
li t1, 0x40000000
bne t0, t1, test_fail
""",
    "for_empty_body_next_address_is_valid": empty_for_image()
    + push_bits("0x3f800000") + push_bits("0x40400000") + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
lw t0, error_code
bnez t0, test_fail
lw t0, for_depth
bnez t0, test_fail
li a0, 73
li a1, 0
li a2, 0
call symbol_load_ft0
fmv.x.w t0, ft0
li t1, 0x40800000
bne t0, t1, test_fail
lw t0, for_context_sentinel
li t1, FOR_CTX_TAG
bne t0, t1, test_fail
""",
    "for_increment_nonfinite_is_controlled": for_image(explicit_step=True)
    + push_bits("0x7f7fffff") * 3 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
call vm_run
""" + error_is("ERR_MATH") + """
lw t0, for_depth
li t1, 1
bne t0, t1, test_fail
""",
    "for_context_corrupt_fields_are_rejected": for_image()
    + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
li t0, 0x7f800000
la t1, for_contexts
sw t0, 4(t1)
call vm_run
""" + error_is("ERR_CONTEXT") + """
lw t0, for_depth
li t1, 1
bne t0, t1, test_fail
lw t0, for_context_sentinel
li t1, FOR_CTX_TAG
bne t0, t1, test_fail
""",
    "for_context_corrupt_body_next_owner_tag_and_continuation": for_image()
    + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
la t0, bytecode_buf
addi t0, t0, 1
la a0, for_contexts
sw t0, 12(a0)
call validate_for_context
""" + error_is("ERR_CONTEXT") + """
call reset_runtime
""" + for_image() + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
li t0, 0x7f800000
la a0, for_contexts
sw t0, 8(a0)
call validate_for_context
""" + error_is("ERR_CONTEXT") + """
call reset_runtime
""" + for_image() + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
la t0, bytecode_buf
addi t0, t0, 29
la a0, for_contexts
sw t0, 16(a0)
call validate_for_context
""" + error_is("ERR_CONTEXT") + """
call reset_runtime
""" + for_image() + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
li t0, 17
la a0, for_contexts
sw t0, 20(a0)
call validate_for_context
""" + error_is("ERR_CONTEXT") + """
call reset_runtime
""" + for_image() + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
la a0, for_contexts
sw zero, 28(a0)
call validate_for_context
""" + error_is("ERR_CONTEXT") + """
call reset_runtime
""" + for_image() + push_bits("0x3f800000") * 2 + """
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
la t0, bytecode_buf
sw t0, 20(t0)
la a0, for_contexts
call validate_for_context
""" + error_is("ERR_CONTEXT"),
    "do_missing_target_push_is_atomic": """
li a0, OP_HALT
call emit_word
li a0, DO_KIND_LINE
li a1, 9999
call do_call
""" + error_is("ERR_LINES") + """
lw t0, do_depth
bnez t0, test_fail
lw t0, do_context_sentinel
li t1, 0x444f4358
bne t0, t1, test_fail
""",
    "do_stack_capacity_and_sentinel": """
li a0, OP_NOP
call emit_word
li a0, OP_LINE_END
call emit_word
li a0, 101
call emit_word
li a0, OP_HALT
call emit_word
li t0, 1
sw t0, line_count, t1
li t0, 101
sw t0, line_numbers, t1
sw zero, line_offsets, t1
li t0, 4
sw t0, line_end_offsets, t1
li t0, DO_MAX
sw t0, do_depth, t1
li a0, DO_KIND_LINE
li a1, 101
call do_call
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, DO_MAX
bne t0, t1, test_fail
lw t0, do_context_sentinel
li t1, 0x444f4358
bne t0, t1, test_fail
""",
    "return_outside_and_corrupt_depth": """
call do_return_top
""" + error_is("ERR_CONTEXT") + """
call reset_runtime
li t0, 17
sw t0, do_depth, t1
call do_return_top
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, 17
bne t0, t1, test_fail
""",
    "return_rejects_corrupt_active_context": """
li a0, OP_HALT
call emit_word
la t2, do_contexts
la t0, bytecode_buf
sw t0, 0(t2)
li t0, 99
sw t0, 4(t2)
li t0, 101
sw t0, 8(t2)
lw t3, 0(t2)
lw t4, 4(t2)
xor t3, t3, t4
lw t4, 8(t2)
xor t3, t3, t4
li t4, DO_CTX_TAG
xor t3, t3, t4
sw t3, 12(t2)
li t0, 1
sw t0, do_depth, t1
call do_return_top
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, 1
bne t0, t1, test_fail
lw t0, do_context_sentinel
li t1, 0x444f4358
bne t0, t1, test_fail
""",
    "return_rejects_bad_return_pc": """
li a0, OP_HALT
call emit_word
la t2, do_contexts
la t0, bytecode_buf
addi t0, t0, 1
sw t0, 0(t2)
li t0, DO_KIND_LINE
sw t0, 4(t2)
li t0, 101
sw t0, 8(t2)
lw t3, 0(t2)
lw t4, 4(t2)
xor t3, t3, t4
lw t4, 8(t2)
xor t3, t3, t4
li t4, DO_CTX_TAG
xor t3, t3, t4
sw t3, 12(t2)
li t0, 1
sw t0, do_depth, t1
call do_return_top
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, 1
bne t0, t1, test_fail
""",
    "line_end_opcode_truncated": """
li a0, OP_LINE_END
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_BC_ACCESS"),
    "line_end_rejects_wrong_identity": """
li t0, 1
sw t0, line_count, t1
li t0, 101
sw t0, line_numbers, t1
sw zero, line_end_offsets, t1
li a0, OP_LINE_END
call emit_word
li a0, 102
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_CONTEXT"),
    "line_end_rejects_corrupt_metadata": """
li t0, 1
sw t0, line_count, t1
li t0, 101
sw t0, line_numbers, t1
li t0, 4
sw t0, line_end_offsets, t1
li a0, OP_LINE_END
call emit_word
li a0, 101
call emit_word
li a0, OP_HALT
call emit_word
la t0, bytecode_buf
sw t0, pc_ptr, t1
call vm_run
""" + error_is("ERR_CONTEXT"),
    "missing_external_target_does_not_unwind": """
li t0, 1
sw t0, do_depth, t1
li t0, 0x12345678
sw t0, do_contexts, t1
li t0, 1
sw t0, for_depth, t1
li t0, 0x87654321
sw t0, for_contexts, t1
li a0, 9999
call external_set_pc_to_line
""" + error_is("ERR_LINES") + """
lw t0, do_depth
li t1, 1
bne t0, t1, test_fail
lw t0, do_contexts
li t1, 0x12345678
bne t0, t1, test_fail
lw t0, for_depth
li t1, 1
bne t0, t1, test_fail
lw t0, for_contexts
li t1, 0x87654321
bne t0, t1, test_fail
""",
    "corrupt_for_prevents_partial_do_for_transfer": """
li a0, OP_NOP
call emit_word
li a0, OP_LINE_END
call emit_word
li a0, 202
call emit_word
li a0, OP_HALT
call emit_word
li t0, 1
sw t0, line_count, t1
li t0, 202
sw t0, line_numbers, t1
sw zero, line_offsets, t1
li t0, 4
sw t0, line_end_offsets, t1
la t2, do_contexts
la t0, bytecode_buf
addi t0, t0, 12
sw t0, 0(t2)
li t1, DO_KIND_GROUP
sw t1, 4(t2)
li t3, 3
sw t3, 8(t2)
xor t4, t0, t1
xor t4, t4, t3
li t5, DO_CTX_TAG
xor t4, t4, t5
sw t4, 12(t2)
li t0, 1
sw t0, do_depth, t1
sw t0, for_depth, t1
li t1, 0x12345678
sw t1, for_contexts, t2
li a0, 202
call external_set_pc_to_line
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, 1
bne t0, t1, test_fail
lw t0, for_depth
bne t0, t1, test_fail
""",
    "do_return_validates_for_before_committing_depths": """
li a0, OP_HALT
call emit_word
la t2, do_contexts
la t0, bytecode_buf
sw t0, 0(t2)
li t1, DO_KIND_LINE
sw t1, 4(t2)
li t3, 101
sw t3, 8(t2)
xor t4, t0, t1
xor t4, t4, t3
li t5, DO_CTX_TAG
xor t4, t4, t5
sw t4, 12(t2)
li t0, 1
sw t0, do_depth, t1
sw t0, for_depth, t1
li t1, 0x12345678
sw t1, for_contexts, t2
call do_return_top
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, 1
bne t0, t1, test_fail
lw t0, for_depth
bne t0, t1, test_fail
""",
    "reset_runtime_clears_both_control_depths": """
li t0, 7
sw t0, do_depth, t1
li t0, 9
sw t0, for_depth, t1
call reset_runtime
lw t0, do_depth
bnez t0, test_fail
lw t0, for_depth
bnez t0, test_fail
""" + error_is("0"),
    "corrupt_context_does_not_partially_unwind": """
li a0, OP_NOP
call emit_word
li a0, OP_LINE_END
call emit_word
li a0, 202
call emit_word
li a0, OP_HALT
call emit_word
li t0, 1
sw t0, line_count, t1
li t0, 202
sw t0, line_numbers, t1
sw zero, line_offsets, t1
li t0, 4
sw t0, line_end_offsets, t1
la t2, do_contexts
la t0, bytecode_buf
sw t0, 0(t2)
li t1, DO_KIND_GROUP
sw t1, 4(t2)
li t1, 2
sw t1, 8(t2)
sw t0, 16(t2)
li t1, 99
sw t1, 20(t2)
li t1, 303
sw t1, 24(t2)
li t0, 2
sw t0, do_depth, t1
li a0, 202
call external_set_pc_to_line
""" + error_is("ERR_CONTEXT") + """
lw t0, do_depth
li t1, 2
bne t0, t1, test_fail
""",
    "corrupt_line_target_offsets": """
li t0, 1
sw t0, line_count, t1
li t0, 101
sw t0, line_numbers, t1
li t0, 1
sw t0, line_offsets, t1
li a0, OP_HALT
call emit_word
li a0, 101
call set_pc_to_line
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li t0, 1
sw t0, line_count, t1
li t0, 101
sw t0, line_numbers, t1
li t0, -4
sw t0, line_offsets, t1
li a0, OP_HALT
call emit_word
li a0, 101
call set_pc_to_line
""" + error_is("ERR_BC_ACCESS") + """
call reset_runtime
li t0, 1
sw t0, line_count, t1
li t0, 101
sw t0, line_numbers, t1
li t0, 4
sw t0, line_offsets, t1
sw t0, line_end_offsets, t1
li a0, OP_NOP
call emit_word
li a0, OP_LINE_END
call emit_word
li a0, 101
call emit_word
li a0, OP_HALT
call emit_word
li a0, 101
call set_pc_to_line
""" + error_is("ERR_BC_ACCESS"),
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
    "index_nearest_even": """
li t0, 0x3fc00000
fmv.w.x ft0, t0
call index_from_ft0
li t0, 2
bne a0, t0, test_fail
li t0, 0x40200000
fmv.w.x ft0, t0
call index_from_ft0
li t0, 2
bne a0, t0, test_fail
li t0, 0xbfc00000
fmv.w.x ft0, t0
call index_from_ft0
li t0, -2
bne a0, t0, test_fail
li t0, 0xc0200000
fmv.w.x ft0, t0
call index_from_ft0
li t0, -2
bne a0, t0, test_fail
""" + error_is("0"),
    "invalid_index_conversion": """
li t0, 0x7f800000
fmv.w.x ft0, t0
call index_from_ft0
""" + error_is("ERR_ARRAY"),
    "symbol_capacity_and_atomic_failure": """
la t0, symbol_table_end
li t1, 0x12345678
sw t1, 0(t0)
li s0, 0
symbol_fill_loop:
li a0, 65
li a1, 1
mv a2, s0
fcvt.s.w ft0, s0
call symbol_store_ft0
lw t0, error_code
bnez t0, test_fail
addi s0, s0, 1
li t0, SYMBOL_MAX
blt s0, t0, symbol_fill_loop
lw t0, symbol_count
li t1, SYMBOL_MAX
bne t0, t1, test_fail
la t0, symbol_table_end
lw t1, 0(t0)
li t2, 0x12345678
bne t1, t2, test_fail
li t0, 0x41100000
fmv.w.x ft0, t0
li a0, 66
li a1, 0
li a2, 0
call symbol_store_ft0
""" + error_is("ERR_ARRAY") + """
lw t0, symbol_count
li t1, SYMBOL_MAX
bne t0, t1, test_fail
la t0, symbol_table_end
lw t1, 0(t0)
li t2, 0x12345678
bne t1, t2, test_fail
lw t0, -16(t0)
li t1, 65
bne t0, t1, test_fail
call reset_runtime
li t0, 0x44424000
fmv.w.x ft0, t0
li a0, 65
li a1, 1
li a2, 0
call symbol_store_ft0
lw t0, symbol_count
li t1, SYMBOL_MAX
bne t0, t1, test_fail
li a0, 65
li a1, 1
li a2, 0
call symbol_load_ft0
fmv.x.w t0, ft0
li t1, 0x44424000
bne t0, t1, test_fail
""" + error_is("0"),
    "corrupt_symbol_count": """
li t0, -1
sw t0, symbol_count, t1
la t0, symbol_table_end
li t1, 0x76543210
sw t1, 0(t0)
li a0, 65
li a1, 0
li a2, 0
call symbol_find
""" + error_is("ERR_ARRAY") + """
la t0, symbol_table_end
lw t1, 0(t0)
li t2, 0x76543210
bne t1, t2, test_fail
""",
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
        return target + ('\n.data\n.align 2\ntest_sp: .word 0\n'
                         'test_pass_message: .asciz "PASS\\n"\n'
                         'test_fail_message: .asciz "FAIL\\n"\n'
                         'test_string: .asciz "\\\"x\\\""\n'
                         'test_symbol_source: .asciz "SET ALPHA=1"\n')

    def execute(self, source, expected, stdin=None, files=None):
        if stdin is not None and stdin.endswith('\nQUIT\n'):
            # QUIT returns to the REPL, so EXIT terminates the test process;
            # stored FOCAL QUIT and every safety assertion remain unchanged.
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
        commands = '1 TYPE "KEEP",!\nTYPE A(1E10),!\nTYPE "AFTER",!\nLIST\nQUIT\n'
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

    def test_full_128_line_program_runs_without_staging_buffer(self):
        comment = 'COMMENT ' + 'x' * 119
        numbered = [f'{1 if index < 99 else 2}.{index + 1 if index < 99 else index - 98:02}'
                    for index in range(128)]
        commands = ''.join(f'{number} {comment}\n' for number in numbered[:-1])
        commands += f'{numbered[-1]} TYPE 42,!;Q\nRUN\nEXIT\n'
        expected = ('FOCAL/RARS REPL. Enter HELP for commands.\n' + '> ' * 129
                    + '42.0\n> ')
        self.execute(self.source, expected, commands)

    def test_load_error_keeps_source(self):
        for content, code, message in [
            ('1 QUIT\n2 ' + 'x' * 128 + '\n', 7, 'text buffer bounds'),
            (''.join(f'{n} QUIT\n' for n in range(1, 130)), 8, 'line table/storage bounds'),
            # This input is rejected because its single physical line cannot
            # fit, not because of the total file size.
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
                     '> 1.01 SET A=7\n1.02 TYPE A(1E10),!\n> ',
                     '1 SET A=7\n2 TYPE A(1E10),!\nRUN\nTYPE A,!\nLIST\nQUIT\n')

    def test_ask_nested_evaluator_state_and_boundaries(self):
        success = """
li a0, OP_HALT
call emit_word
la a0, test_symbol_source
li a1, 32
call set_parse_span
li t0, 0x3f800000
fmv.w.x ft0, t0
call vm_push_ft0
lw s0, pc_ptr
lw s1, bc_ptr
lw s2, parse_begin
lw s3, parse_end
lw s4, parse_ptr
lw s5, vm_sp_ptr
li t0, TYPE_FMT_FIXED
sw t0, type_format_mode, t1
li t0, 8
sw t0, type_format_width, t1
li t0, 2
sw t0, type_format_precision, t1
call ask_read_expression
""" + error_is("0") + """
fmv.x.w t0, ft0
li t1, 0x40400000
bne t0, t1, test_fail
lw t0, pc_ptr
bne t0, s0, test_fail
lw t0, bc_ptr
bne t0, s1, test_fail
lw t0, parse_begin
bne t0, s2, test_fail
lw t0, parse_end
bne t0, s3, test_fail
lw t0, parse_ptr
bne t0, s4, test_fail
lw t0, vm_sp_ptr
bne t0, s5, test_fail
la t0, vm_stack
lw t1, 0(t0)
li t2, 0x3f800000
bne t1, t2, test_fail
lw t0, type_format_mode
li t1, TYPE_FMT_FIXED
bne t0, t1, test_fail
lw t0, type_format_width
li t1, 8
bne t0, t1, test_fail
lw t0, type_format_precision
li t1, 2
bne t0, t1, test_fail
"""
        runtime_error = """
li a0, OP_HALT
call emit_word
la a0, test_symbol_source
li a1, 32
call set_parse_span
li t0, 0x3f800000
fmv.w.x ft0, t0
call vm_push_ft0
lw s0, pc_ptr
lw s1, bc_ptr
lw s2, parse_begin
lw s3, parse_end
lw s4, parse_ptr
lw s5, vm_sp_ptr
call ask_read_expression
""" + error_is("ERR_MATH") + """
lw t0, pc_ptr
bne t0, s0, test_fail
lw t0, bc_ptr
bne t0, s1, test_fail
lw t0, parse_begin
bne t0, s2, test_fail
lw t0, parse_end
bne t0, s3, test_fail
lw t0, parse_ptr
bne t0, s4, test_fail
lw t0, vm_sp_ptr
bne t0, s5, test_fail
la t0, vm_stack
lw t1, 0(t0)
li t2, 0x3f800000
bne t1, t2, test_fail
"""
        capacity = """
la t0, vm_stack
li t1, 0x12345678
sw t1, 0(t0)
addi t0, t0, 4
sw t0, vm_sp_ptr, t1
la t0, bytecode_end
addi t0, t0, -4
sw t0, bc_ptr, t1
la t0, bytecode_buf
sw t0, pc_ptr, t1
lw s0, pc_ptr
lw s1, bc_ptr
lw s2, vm_sp_ptr
call ask_read_expression
""" + error_is("ERR_BC_FULL") + """
lw t0, pc_ptr
bne t0, s0, test_fail
lw t0, bc_ptr
bne t0, s1, test_fail
lw t0, vm_sp_ptr
bne t0, s2, test_fail
la t0, vm_stack
lw t1, 0(t0)
li t2, 0x12345678
bne t1, t2, test_fail
"""
        input_boundary = """
la t0, ask_input_buf_end
li t1, 85
sb t1, 0(t0)
lw s0, pc_ptr
lw s1, bc_ptr
lw s2, vm_sp_ptr
call ask_read_expression
""" + error_is("ERR_TEXT") + """
lw t0, pc_ptr
bne t0, s0, test_fail
lw t0, bc_ptr
bne t0, s1, test_fail
lw t0, vm_sp_ptr
bne t0, s2, test_fail
la t0, ask_input_buf_end
lbu t1, 0(t0)
li t2, 85
bne t1, t2, test_fail
"""
        cases = [
            ("success", success, "1+2\n"),
            ("runtime_error", runtime_error, "1/0\n"),
            ("bytecode_capacity", capacity, "1\n"),
            ("input_boundary", input_boundary, "1" * 300 + "\n"),
        ]
        for name, body, stdin in cases:
            with self.subTest(name=name):
                self.execute(self.harness(body), ":PASS\n", stdin=stdin)

    def test_repeated_ask_evaluation_reuses_temporary_wordcode(self):
        body = """
li a0, OP_HALT
call emit_word
lw s0, bc_ptr
lw s1, pc_ptr
lw s2, vm_sp_ptr
li s3, 32
ask_repeat_loop:
call ask_read_expression
lw t0, error_code
bnez t0, test_fail
fmv.x.w t0, ft0
li t1, 0x3f800000
bne t0, t1, test_fail
lw t0, bc_ptr
bne t0, s0, test_fail
lw t0, pc_ptr
bne t0, s1, test_fail
lw t0, vm_sp_ptr
bne t0, s2, test_fail
addi s3, s3, -1
bnez s3, ask_repeat_loop
"""
        self.execute(self.harness(body), ":" * 32 + "PASS\n", stdin="1\n" * 32)


if __name__ == "__main__":
    unittest.main()
