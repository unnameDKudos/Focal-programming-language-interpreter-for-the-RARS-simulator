# Safety convention: sticky first error; callers test after fallible calls and
# return through their own epilogue. Only the top level reports/resets it.
# RARS call also uses t1 as its address scratch. a*/t*/ft* are caller-saved. CHECK_ERROR uses t6; ENTER_FRAME uses t5/t6.
# append helpers intentionally update s4 (private builder cursor), saved by
# their owning REPL procedure. VM helpers preserve t2/t3 and ft2.
# Procedural sp (64 KiB guarded budget) is distinct from 512-word vm_stack.
.eqv ERR_BC_FULL 1
.eqv ERR_BC_ACCESS 2
.eqv ERR_VM_OVERFLOW 3
.eqv ERR_VM_UNDERFLOW 4
.eqv ERR_STRING 5
.eqv ERR_PROGRAM 6
.eqv ERR_TEXT 7
.eqv ERR_LINES 8
.eqv ERR_ARRAY 9
.eqv ERR_SYNTAX 10
.eqv ERR_PROC_STACK 11
.eqv ERR_FILE 12
.macro CHECK_ERROR (%target)
    lw t6, error_code
    beqz t6, safety_near_1
    j %target
safety_near_1:
.end_macro
.macro ENTER_FRAME (%size)
    CHECK_ERROR (safety_return)
    lw t6, proc_stack_floor
    addi t5, sp, -%size
    bgeu t5, t6, safety_near_2
    j error_proc_stack
safety_near_2:
    mv sp, t5
.end_macro
.macro CHECK_PARSE (%ptr, %target)
    lw t6, parse_begin
    bgeu %ptr, t6, safety_near_3
    j %target
safety_near_3:
    lw t6, parse_end
    bleu %ptr, t6, safety_near_4
    j %target
safety_near_4:
.end_macro
# Valid next-free bytecode pointer, inclusive end; preserves t0..t4.
.macro CHECK_BC (%ptr)
    andi t6, %ptr, 3
    beqz t6, safety_near_5
    j error_bc_access
safety_near_5:
    la t6, bytecode_buf
    bgeu %ptr, t6, safety_near_6
    j error_bc_access
safety_near_6:
    la t6, bytecode_end
    bleu %ptr, t6, safety_near_7
    j error_bc_access
safety_near_7:
.end_macro
.eqv ERR_DEFERRED 13
.eqv ERR_NUMBER 14
.eqv ERR_MATH 15
.eqv TK_SET 1
.eqv TK_TYPE 2
.eqv TK_ASK 3
.eqv TK_GOTO 4
.eqv TK_IF 5
.eqv TK_FOR 6
.eqv TK_DO 7
.eqv TK_RETURN 8
.eqv TK_QUIT 9
.eqv TK_COMMENT 10
.eqv TK_WRITE 11
.eqv TK_THEN 12
.eqv TK_ALL 13
.eqv TK_RUN 101
.eqv TK_LIST 102
.eqv TK_LOAD 103
.eqv TK_SAVE 104
.eqv TK_ERASE 105
.eqv TK_HELP 106
.eqv TK_EXIT 107
.eqv OP_NOP        0
.eqv OP_PUSH_F     1
.eqv OP_PUSH_V     2
.eqv OP_STORE_V    3
.eqv OP_PUSH_ARR   4
.eqv OP_STORE_ARR  5
.eqv OP_PUSH_BITS  6
.eqv OP_ADD        16
.eqv OP_SUB        17
.eqv OP_MUL        18
.eqv OP_DIV        19
.eqv OP_NEG        20
.eqv OP_POW        21
.eqv OP_ABS        22
.eqv OP_SQRT       23
.eqv OP_EQ         24
.eqv OP_NE         25
.eqv OP_LT         26
.eqv OP_LE         27
.eqv OP_GT         28
.eqv OP_GE         29
.eqv OP_TRUNC      30
.eqv OP_SGN        31
.eqv OP_JUMP       48
.eqv OP_JUMP_Z     49
.eqv OP_JUMP_NZ    50
.eqv OP_HALT       51
.eqv OP_JUMP_Z_ABS 52
.eqv OP_JUMP_ABS   53
.eqv OP_PRINT_S    64
.eqv OP_PRINT_F    65
.eqv OP_PRINT_NL   66
.eqv OP_READ_F     67
.eqv OP_WRITE      68
.eqv MAX_LINES     128
.eqv LINE_LEN      128
.eqv ARRAY_LEN     100
.data
    .align 2
focal_program:
    .asciz "1: SET A=2+3*4\n2: SET B=(2+3)*4\n3: TYPE \"A = \",A,!\n4: TYPE \"B = \",B,!\n5: IF A<B THEN 7\n6: TYPE \"bad\",!\n7: TYPE \"ok\",!\n8: QUIT\n"
focal_program_end:
    .align 2
error_code: .word 0
error_message: .word 0
proc_stack_floor: .word 0
parse_begin: .word 0
parse_end: .word 0
parse_ptr:      .word 0
source_ptr:     .word 0
bc_ptr:         .word 0
pc_ptr:         .word 0
vm_sp_ptr:      .word 0
str_pool_ptr:   .word 0
line_count:     .word 0
repl_enabled:   .word 1
repl_line_count:.word 0
vars:           .space 104
vars_end:
arrays:         .space 10400
arrays_end:
line_numbers:   .space 512
line_numbers_end:
line_offsets:   .space 512
line_offsets_end:
repl_numbers:   .space 512
repl_numbers_end:
repl_texts:      .space 16384
repl_texts_end:
bytecode_buf:   .space 16384
bytecode_end:
vm_stack:       .space 2048
vm_stack_end:
str_pool:       .space 4096
str_pool_end:
program_buf:    .space 8192
program_buf_end:
program_buf_ptr:.word 0
input_line:     .space 256
input_line_end:
file_name:      .space 256
file_name_end:
file_io_buf:    .space 256
file_io_buf_end:
file_space:     .byte 32
file_newline:   .byte 10
    .align 2
# LOAD transaction rollback only; not an expanded user storage capacity.
repl_backup_count: .word 0
repl_backup_numbers: .space 512
repl_backup_texts: .space 16384
repl_backup_end:
zero_f:         .float 0.0
one_f:          .float 1.0
neg_one_f:      .float -1.0
ten_f:          .float 10.0
tenth_f:        .float 0.1
err_unknown:    .asciz "FOCAL/RARS error [E10]: unknown statement\n"
err_line:       .asciz "FOCAL/RARS error [E08]: line not found\n"
repl_banner:    .asciz "FOCAL/RARS REPL. Enter HELP for commands.\n"
repl_prompt:    .asciz "> "
repl_empty:     .asciz "No program\n"
repl_load_ok:   .asciz "Loaded\n"
repl_save_ok:   .asciz "Saved\n"
repl_file_err:  .asciz "File error\n"
repl_help_text: .asciz "Commands:\n  group.line text   add/replace; number only deletes (1.1 = 1.10)\n  FOCAL statement   execute immediately; keywords ignore case\n  RUN               run stored program; preserve variables\n  G / GO / GOTO     FOCAL jump; no argument runs stored program\n  LIST              show stored program\n  WRITE/W [ALL|g|g.ll] show all source, one group or one line\n  LOAD <file>       load program; preserve variables\n  SAVE <file>       save stored program\n  ERASE             clear program, variables and runtime state\n  HELP              show this help\n  QUIT / Q          stop FOCAL execution; return to REPL\n  EXIT              exit interpreter/RARS\nStatements: SET/S TYPE/T ASK/A GOTO/G/GO IF/I FOR/F QUIT/Q COMMENT/C.\nStandalone DO/D RETURN/R: recognized; not implemented yet.\nLegacy integer aliases remain temporary; identifiers and IF/FOR remain legacy.\n"
msg_bc_full: .asciz "FOCAL/RARS error [E01]: bytecode capacity\n"
msg_bc_access: .asciz "FOCAL/RARS error [E02]: invalid wordcode access\n"
msg_vm_overflow: .asciz "FOCAL/RARS error [E03]: VM stack overflow\n"
msg_vm_underflow: .asciz "FOCAL/RARS error [E04]: VM stack underflow\n"
msg_string: .asciz "FOCAL/RARS error [E05]: string pool bounds\n"
msg_program: .asciz "FOCAL/RARS error [E06]: program buffer bounds\n"
msg_text: .asciz "FOCAL/RARS error [E07]: text buffer bounds\n"
msg_lines: .asciz "FOCAL/RARS error [E08]: line table/storage bounds\n"
msg_array: .asciz "FOCAL/RARS error [E09]: variable/array bounds\n"
msg_syntax: .asciz "FOCAL/RARS error [E10]: invalid source\n"
msg_proc_stack: .asciz "FOCAL/RARS error [E11]: procedural stack limit\n"
msg_file: .asciz "FOCAL/RARS error [E12]: file I/O\n"
msg_math: .asciz "FOCAL/RARS error [E15]: invalid arithmetic operation\n"
# Immutable keyword table; input bytes are compared, never normalized in place.
    .align 2
keyword_table:
    .word kw_SET, TK_SET
    .word kw_S, TK_SET
    .word kw_TYPE, TK_TYPE
    .word kw_T, TK_TYPE
    .word kw_ASK, TK_ASK
    .word kw_A, TK_ASK
    .word kw_GOTO, TK_GOTO
    .word kw_G, TK_GOTO
    .word kw_GO, TK_GOTO
    .word kw_IF, TK_IF
    .word kw_I, TK_IF
    .word kw_FOR, TK_FOR
    .word kw_F, TK_FOR
    .word kw_DO, TK_DO
    .word kw_D, TK_DO
    .word kw_RETURN, TK_RETURN
    .word kw_R, TK_RETURN
    .word kw_QUIT, TK_QUIT
    .word kw_Q, TK_QUIT
    .word kw_COMMENT, TK_COMMENT
    .word kw_C, TK_COMMENT
    .word kw_WRITE, TK_WRITE
    .word kw_W, TK_WRITE
    .word kw_ALL, TK_ALL
    .word kw_THEN, TK_THEN
    .word kw_RUN, TK_RUN
    .word kw_LIST, TK_LIST
    .word kw_LOAD, TK_LOAD
    .word kw_SAVE, TK_SAVE
    .word kw_ERASE, TK_ERASE
    .word kw_HELP, TK_HELP
    .word kw_EXIT, TK_EXIT
    .word 0, 0
    .align 2
function_table:
    .word fn_FABS, OP_ABS
    .word fn_FSQT, OP_SQRT
    .word fn_FITR, OP_TRUNC
    .word fn_FSGN, OP_SGN
    .word 0, 0
fn_FABS: .asciz "FABS"
fn_FSQT: .asciz "FSQT"
fn_FITR: .asciz "FITR"
fn_FSGN: .asciz "FSGN"
kw_SET: .asciz "SET"
kw_S: .asciz "S"
kw_TYPE: .asciz "TYPE"
kw_T: .asciz "T"
kw_ASK: .asciz "ASK"
kw_A: .asciz "A"
kw_GOTO: .asciz "GOTO"
kw_G: .asciz "G"
kw_GO: .asciz "GO"
kw_IF: .asciz "IF"
kw_I: .asciz "I"
kw_FOR: .asciz "FOR"
kw_F: .asciz "F"
kw_DO: .asciz "DO"
kw_D: .asciz "D"
kw_RETURN: .asciz "RETURN"
kw_R: .asciz "R"
kw_QUIT: .asciz "QUIT"
kw_Q: .asciz "Q"
kw_COMMENT: .asciz "COMMENT"
kw_C: .asciz "C"
kw_WRITE: .asciz "WRITE"
kw_W: .asciz "W"
kw_ALL: .asciz "ALL"
kw_THEN: .asciz "THEN"
kw_RUN: .asciz "RUN"
kw_LIST: .asciz "LIST"
kw_LOAD: .asciz "LOAD"
kw_SAVE: .asciz "SAVE"
kw_ERASE: .asciz "ERASE"
kw_HELP: .asciz "HELP"
kw_EXIT: .asciz "EXIT"
number_text: .space 8
msg_number: .asciz "FOCAL/RARS error [E14]: invalid line number or selector\n"
msg_deferred: .asciz "FOCAL/RARS error [E13]: recognized statement not implemented yet\n"
.text
.globl main
main:
    andi sp, sp, -16
    call init_safety
    la t0, repl_enabled
    lw t1, 0(t0)
    bnez t1, rars_repl
run_embedded_program:
    call reset_runtime
    la t0, focal_program
    la t1, source_ptr
    sw t0, 0(t1)
    call compile_program
    CHECK_ERROR (batch_done)
    la t0, bytecode_buf
    la t1, pc_ptr
    sw t0, 0(t1)
    call vm_run
batch_done:
    call report_error
    call reset_runtime
    j program_exit
rars_repl:
    call reset_runtime
    call repl_clear_program
    la a0, repl_banner
    li a7, 4
    ecall
repl_loop:
    call report_error
    call reset_runtime
    la a0, repl_prompt
    li a7, 4
    ecall
    la a0, input_line
    li a1, 256
    li a7, 8
    ecall
    call validate_input
    CHECK_ERROR (repl_loop)
    la a0, input_line
    call skip_spaces_a0
    CHECK_ERROR (repl_loop)
    lbu t0, 0(a0)
    beqz t0, repl_loop
    li t1, 10
    beq t0, t1, repl_loop
    li t1, 48
    bltu t0, t1, repl_dispatch
    li t1, 57
    bgtu t0, t1, repl_dispatch
    call repl_store_line
    j repl_loop
repl_dispatch:
    # A leading separator starts an immediate FOCAL physical line. It is not
    # an environment command token and is handled by the common frontend.
    li t1, 59
    beq t0, t1, repl_immediate
    sw a0, parse_ptr, t0
    call read_keyword
    CHECK_ERROR (repl_loop)
    # s5 belongs to the top-level dispatch, not to any nested procedure.
    mv s5, a0
    li t0, TK_RUN
    bltu s5, t0, repl_focal
    li t0, TK_LOAD
    beq s5, t0, repl_load
    li t0, TK_SAVE
    beq s5, t0, repl_save
    call require_command_end
    CHECK_ERROR (repl_loop)
    li t0, TK_RUN
    beq s5, t0, repl_run
    li t0, TK_LIST
    beq s5, t0, repl_list
    li t0, TK_ERASE
    beq s5, t0, repl_erase
    li t0, TK_HELP
    beq s5, t0, repl_help
    # Only the exact environment token EXIT reaches process termination.
    j program_exit
repl_focal:
    li t0, TK_GOTO
    bne s5, t0, repl_immediate
    # FR-23: argument-less G/GO/GOTO is a FOCAL start request.
    # An argument follows the unchanged immediate/compiler GOTO path.
    call skip_parse_spaces
    CHECK_ERROR (repl_loop)
    call is_parse_line_end
    CHECK_ERROR (repl_loop)
    bnez a0, repl_run

repl_immediate:
    call repl_run_immediate
    j repl_loop
repl_run:
    call repl_build_program
    CHECK_ERROR (repl_loop)
    la t0, program_buf
    lbu t1, 0(t0)
    beqz t1, repl_no_program
    call reset_runtime
    la t0, program_buf
    la t1, source_ptr
    sw t0, 0(t1)
    call compile_program
    CHECK_ERROR (repl_loop)
    la t0, bytecode_buf
    la t1, pc_ptr
    sw t0, 0(t1)
    call vm_run
    j repl_loop
repl_no_program:
    la a0, repl_empty
    li a7, 4
    ecall
    j repl_loop
repl_list:
    li a0, 0
    li a1, 0
    call print_source
    j repl_loop
repl_erase:
    call repl_clear_program
    call clear_variables
    call reset_runtime
    j repl_loop
repl_load:
    call repl_load_file
    j repl_loop
repl_save:
    call repl_save_file
    j repl_loop
repl_help:
    la a0, repl_help_text
    li a7, 4
    ecall
    j repl_loop
repl_clear_program:
    la t0, program_buf
    la t1, program_buf_ptr
    sw t0, 0(t1)
    sb zero, 0(t0)
clear_storage_numbers:
    la t0, repl_line_count
    sw zero, 0(t0)
    la t0, repl_numbers
    li t1, 0
rcp_loop:
    li t2, MAX_LINES
    bge t1, t2, rcp_done
    sw zero, 0(t0)
    addi t0, t0, 4
    addi t1, t1, 1
    j rcp_loop
rcp_done:
    ret
# ERASE is the only command that clears both scalar and indexed variables.
clear_variables:
    la t0, vars
    la t1, arrays_end
cv_loop:
    bgeu t0, t1, cv_done
    sw zero, 0(t0)
    addi t0, t0, 4
    j cv_loop
cv_done:
    ret
reset_runtime:
    sw zero, error_code, t0
    sw zero, error_message, t0
    sw zero, parse_begin, t0
    sw zero, parse_end, t0
    sw zero, parse_ptr, t0
    sw zero, source_ptr, t0
    la t0, bytecode_buf
    sw t0, pc_ptr, t1
    la t0, bytecode_buf
    la t1, bc_ptr
    sw t0, 0(t1)
    la t0, str_pool
    la t1, str_pool_ptr
    sw t0, 0(t1)
    la t0, vm_stack
    la t1, vm_sp_ptr
    sw t0, 0(t1)
    la t0, line_count
    sw zero, 0(t0)
    ret
repl_run_immediate:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s4, 4(sp)
    la s4, program_buf
    sb zero, 0(s4)
    la a0, input_line
    call skip_spaces_a0
    CHECK_ERROR (rri_done)
rri_copy:
    CHECK_PARSE (a0, rri_bad)
    lbu t0, 0(a0)
    beqz t0, rri_compile
    li t1, 10
    beq t0, t1, rri_compile
    li t1, 13
    beq t0, t1, rri_compile
    mv t2, a0
    mv a0, t0
    call repl_append_char_to_program
    CHECK_ERROR (rri_done)
    addi a0, t2, 1
    j rri_copy
rri_compile:
    call reset_runtime
    la a0, program_buf
    li a1, 8192
    call set_parse_span
    CHECK_ERROR (rri_done)
    # Immediate code has no source-line identity: no fake public 0: header.
    call compile_physical_line
    CHECK_ERROR (rri_done)
    li a0, OP_HALT
    call emit_word
    CHECK_ERROR (rri_done)
    la t0, bytecode_buf
    sw t0, pc_ptr, t1
    call vm_run
    j rri_done
rri_bad:
    call error_syntax
rri_done:
    lw ra, 0(sp)
    lw s4, 4(sp)
    addi sp, sp, 32
    ret
# repl_line_count is ACTIVE count, not a high-water slot index.
# repl_numbers[i]==0 is the sole free-slot marker. Preflight before mutation.
repl_store_line:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    la a0, input_line
    li a1, 256
    call set_parse_span
    CHECK_ERROR (rsl_done)
    call skip_parse_spaces
    CHECK_ERROR (rsl_done)
    li a0, 0
    call parse_program_number
    CHECK_ERROR (rsl_done)
    mv s0, a0
    call skip_parse_spaces
    CHECK_ERROR (rsl_done)
    lw a0, parse_ptr
    lbu t0, 0(a0)
    li t1, 58
    bne t0, t1, rsl_after_colon
    addi a0, a0, 1
rsl_after_colon:
    call skip_spaces_a0
    CHECK_ERROR (rsl_done)
    mv s1, a0
    mv t0, a0
    li s3, 0
rsl_measure:
    CHECK_PARSE (t0, rsl_bad)
    lbu t1, 0(t0)
    beqz t1, rsl_measured
    li t2, 10
    beq t1, t2, rsl_measured
    li t2, 13
    beq t1, t2, rsl_measured
    addi s3, s3, 1
    li t2, LINE_LEN
    bgeu s3, t2, rsl_text_error
    addi t0, t0, 1
    j rsl_measure
rsl_measured:
    mv a0, s0
    call repl_find_line
    CHECK_ERROR (rsl_done)
    mv s2, a0
    beqz s3, rsl_delete
    bgez s2, rsl_copy
    lw t0, repl_line_count
    li t1, MAX_LINES
    bgeu t0, t1, rsl_full
    li s2, 0
    la t0, repl_numbers
rsl_find_free:
    li t1, MAX_LINES
    bgeu s2, t1, rsl_full
    lw t1, 0(t0)
    beqz t1, rsl_copy
    addi s2, s2, 1
    addi t0, t0, 4
    j rsl_find_free
rsl_copy:
    mv a0, s2
    call repl_text_addr
    CHECK_ERROR (rsl_done)
    # All remaining writes are within the preflighted source and slot.
    mv t0, a0
    mv t1, s1
    mv t2, s3
rsl_copy_loop:
    beqz t2, rsl_commit
    lbu t3, 0(t1)
    sb t3, 0(t0)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    j rsl_copy_loop
rsl_commit:
    sb zero, 0(t0)
    slli t0, s2, 2
    la t1, repl_numbers
    add t1, t1, t0
    lw t2, 0(t1)
    bnez t2, rsl_set_key
    lw t2, repl_line_count
    addi t2, t2, 1
    sw t2, repl_line_count, t0
rsl_set_key:
    sw s0, 0(t1)
    j rsl_done
rsl_delete:
    bltz s2, rsl_done
    lw t0, repl_line_count
    beqz t0, rsl_full
    slli t0, s2, 2
    la t1, repl_numbers
    add t1, t1, t0
    sw zero, 0(t1)
    lw t0, repl_line_count
    addi t0, t0, -1
    sw t0, repl_line_count, t1
    j rsl_done
rsl_text_error:
    call error_text
    j rsl_done
rsl_full:
    call error_lines
    j rsl_done
rsl_bad:
    call error_syntax
rsl_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    addi sp, sp, 32
    ret
repl_find_line:
    CHECK_ERROR (safety_return)
    la t0, repl_line_count
    lw t1, 0(t0)
    li t6, MAX_LINES
    bleu t1, t6, safety_near_9
    j error_lines
safety_near_9:
    li t1, MAX_LINES
    li t2, 0
rfl_loop:
    bge t2, t1, rfl_not_found
    slli t3, t2, 2
    la t4, repl_numbers
    add t4, t4, t3
    lw t5, 0(t4)
    beq t5, a0, rfl_found
    addi t2, t2, 1
    j rfl_loop
rfl_found:
    mv a0, t2
    ret
rfl_not_found:
    li a0, -1
    ret
repl_text_addr:
    CHECK_ERROR (safety_return)
    li t6, MAX_LINES
    bltu a0, t6, safety_near_10
    j error_lines
safety_near_10:
    li t0, LINE_LEN
    mul t1, a0, t0
    la a0, repl_texts
    add a0, a0, t1
    ret
# RUN/SAVE retain the bounded 8-KiB staging buffer. LIST/WRITE stream directly.
repl_build_program:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s4, 12(sp)
    la s4, program_buf
    sb zero, 0(s4)
    li s0, 0
rbp_loop:
    mv a0, s0
    li a1, 101
    li a2, 9999
    call find_next_slot
    CHECK_ERROR (rbp_done)
    bltz a0, rbp_complete
    mv s0, a1
    mv s1, a0
    mv a0, s0
    call format_line_number
    CHECK_ERROR (rbp_done)
    mv t0, a0
rbp_number:
    lbu a0, 0(t0)
    beqz a0, rbp_text
    call repl_append_char_to_program
    CHECK_ERROR (rbp_done)
    addi t0, t0, 1
    j rbp_number
rbp_text:
    li a0, 32
    call repl_append_char_to_program
    CHECK_ERROR (rbp_done)
    mv a0, s1
    call repl_text_addr
    CHECK_ERROR (rbp_done)
    call repl_append_string_to_program
    CHECK_ERROR (rbp_done)
    li a0, 10
    call repl_append_char_to_program
    CHECK_ERROR (rbp_done)
    j rbp_loop
rbp_complete:
    sw s4, program_buf_ptr, t0
rbp_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s4, 12(sp)
    addi sp, sp, 32
    ret
# Compatibility entry point: no separate listing implementation.
repl_build_listing:
    li a0, 0
    li a1, 0
    j print_source
# Private append convention: s4 is in/out; t0/t2..t4 survive the call.
repl_append_char_to_program:
    CHECK_ERROR (safety_return)
    la t6, program_buf
    bgeu s4, t6, safety_near_11
    j error_program
safety_near_11:
    la t6, program_buf_end
    addi t6, t6, -1
    bltu s4, t6, safety_near_12
    j error_program
safety_near_12:
    sb a0, 0(s4)
    addi s4, s4, 1
    sb zero, 0(s4)
    ret
repl_append_string_to_program:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    mv t0, a0
    # The only caller passes the beginning of a physical REPL slot.
    la t6, repl_texts
    bltu t0, t6, ras_bad
    la t6, repl_texts_end
    bgeu t0, t6, ras_bad
    la t6, repl_texts
    sub t6, t0, t6
    andi t6, t6, 127
    bnez t6, ras_bad
    addi t2, t0, LINE_LEN
ras_loop:
    bgeu t0, t2, ras_bad
    lbu a0, 0(t0)
    beqz a0, ras_done
    call repl_append_char_to_program
    CHECK_ERROR (ras_done)
    addi t0, t0, 1
    j ras_loop
ras_bad:
    call error_text
ras_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_append_int_to_program:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    mv t0, a0
    addi t1, sp, 8
    li t2, 0
    bnez t0, rai_digits
    li a0, 48
    call repl_append_char_to_program
    CHECK_ERROR (repl_append_int_to_program_return)
    j rai_done
rai_digits:
    li t3, 10
rai_collect:
    rem t4, t0, t3
    div t0, t0, t3
    addi t4, t4, 48
    sb t4, 0(t1)
    addi t1, t1, 1
    addi t2, t2, 1
    bnez t0, rai_collect
    # RARS expands call through t1; keep the scratch cursor in t0.
    mv t0, t1
rai_emit:
    beqz t2, rai_done
    addi t0, t0, -1
    lbu a0, 0(t0)
    call repl_append_char_to_program
    CHECK_ERROR (repl_append_int_to_program_return)
    addi t2, t2, -1
    j rai_emit
rai_done:
repl_append_int_to_program_return:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
# Read a complete identifier token at parse_ptr, within the bound source span.
# Returns a0=TK_* (0 unknown), a1=first byte after token; updates parse_ptr.
# Only comparisons fold ASCII case. Source and literals are never rewritten.
# Identifier continuation includes digits/_ so SET1 and RUN_X cannot match.
read_keyword:
    CHECK_ERROR (safety_return)
    lw t0, parse_ptr
    mv t1, t0
rk_scan:
    CHECK_PARSE (t1, error_syntax)
    lbu t2, 0(t1)
    li t3, 65
    bltu t2, t3, rk_digit
    li t3, 90
    bleu t2, t3, rk_next
    li t3, 97
    bltu t2, t3, rk_underscore
    li t3, 122
    bleu t2, t3, rk_next
    j rk_lookup
rk_digit:
    li t3, 48
    bltu t2, t3, rk_lookup
    li t3, 57
    bleu t2, t3, rk_next
    j rk_lookup
rk_underscore:
    li t3, 95
    bne t2, t3, rk_lookup
rk_next:
    addi t1, t1, 1
    j rk_scan
rk_lookup:
    mv a1, t1
    sw t1, parse_ptr, t2
    la a2, keyword_table
rk_entry:
    lw a3, 0(a2)
    beqz a3, rk_unknown
    mv a4, t0
rk_compare:
    lbu t3, 0(a3)
    beq a4, a1, rk_at_end
    beqz t3, rk_mismatch
    lbu t2, 0(a4)
    li t4, 97
    bltu t2, t4, rk_folded
    li t4, 122
    bgtu t2, t4, rk_folded
    addi t2, t2, -32
rk_folded:
    bne t2, t3, rk_mismatch
    addi a4, a4, 1
    addi a3, a3, 1
    j rk_compare
rk_at_end:
    bnez t3, rk_mismatch
    lw a0, 4(a2)
    ret
rk_mismatch:
    addi a2, a2, 8
    j rk_entry
rk_unknown:
    li a0, 0
    ret
require_command_end:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_parse_spaces
    CHECK_ERROR (rce_done)
    lw t0, parse_ptr
    CHECK_PARSE (t0, rce_bad)
    lbu t1, 0(t0)
    beqz t1, rce_done
    li t2, 10
    beq t1, t2, rce_done
    li t2, 13
    beq t1, t2, rce_done
rce_bad:
    call error_syntax
rce_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_extract_file_name:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_extract_file_name_return)
    addi a0, a0, 4
    call skip_spaces_a0
    CHECK_ERROR (repl_extract_file_name_return)
    la t0, file_name
    li t1, 255
refn_loop:
    beqz t1, repl_extract_file_name_bad_source
    CHECK_PARSE (a0, repl_extract_file_name_bad_source)
    lbu t2, 0(a0)
    beqz t2, refn_done
    li t3, 10
    beq t2, t3, refn_done
    li t3, 13
    beq t2, t3, refn_done
    sb t2, 0(t0)
    addi t0, t0, 1
    addi a0, a0, 1
    addi t1, t1, -1
    j refn_loop
refn_done:
    sb zero, 0(t0)
    la a0, file_name
    j repl_extract_file_name_return
repl_extract_file_name_bad_source:
    call error_syntax
repl_extract_file_name_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_load_file:
    ENTER_FRAME (64)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    sw s5, 24(sp)
    la a0, input_line
    call repl_extract_file_name
    CHECK_ERROR (rlf_done)
    lbu t0, 0(a0)
    beqz t0, rlf_err
    li a1, 0
    li a7, 1024
    ecall
    bltz a0, rlf_err
    mv s0, a0
    # The live storage is the transaction work area. The fixed backup makes
    # every parse/read/capacity failure invisible to the previous program.
    call repl_snapshot
    call clear_storage_numbers
    la s1, input_line
    li s2, 0
    li s5, 0
rlf_read:
    mv a0, s0
    la a1, file_io_buf
    li a2, 256
    li a7, 63
    ecall
    bltz a0, rlf_read_error
    beqz a0, rlf_eof
    mv s3, a0
    li s4, 0
rlf_byte_loop:
    bgeu s4, s3, rlf_read
    la t0, file_io_buf
    add t0, t0, s4
    lbu t1, 0(t0)
    addi s4, s4, 1
    bnez s5, rlf_after_cr
    beqz t1, rlf_nul_error
    li t2, 13
    beq t1, t2, rlf_got_cr
    li t2, 10
    beq t1, t2, rlf_line_end
    li t2, 255
    bgeu s2, t2, rlf_text_error
    sb t1, 0(s1)
    addi s1, s1, 1
    addi s2, s2, 1
    j rlf_byte_loop
rlf_got_cr:
    li s5, 1
    j rlf_byte_loop
rlf_after_cr:
    li t2, 10
    bne t1, t2, rlf_syntax_error
    li s5, 0
rlf_line_end:
    mv a0, s2
    call repl_load_store_line
    CHECK_ERROR (rlf_restore)
    la s1, input_line
    li s2, 0
    j rlf_byte_loop
rlf_eof:
    # A final line needs no terminator. A trailing CR is also a line ending.
    mv a0, s2
    call repl_load_store_line
    CHECK_ERROR (rlf_restore)
    mv a0, s0
    li a7, 57
    ecall
    la a0, repl_load_ok
    li a7, 4
    ecall
    j rlf_done
rlf_read_error:
    call error_file
    j rlf_restore
rlf_nul_error:
rlf_syntax_error:
    call error_syntax
    j rlf_restore
rlf_text_error:
    call error_text
rlf_restore:
    mv a0, s0
    li a7, 57
    ecall
    call repl_restore
    j rlf_done
rlf_err:
    call error_file
rlf_done:
repl_load_file_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    lw s5, 24(sp)
    addi sp, sp, 64
    ret

# Commit one complete physical file line through the Stage-4 parser/storage.
# a0 is the byte count already assembled at input_line; blank lines are inert.
repl_load_store_line:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    beqz a0, rlsl_done
    la t0, input_line
    add t0, t0, a0
    sb zero, 0(t0)
    call repl_store_line
rlsl_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
# Fixed-count copies over exactly the existing storage; no unchecked count.
repl_snapshot:
    lw t0, repl_line_count
    sw t0, repl_backup_count, t1
    la t0, repl_numbers
    la t1, repl_backup_numbers
    li t2, 16896
    j repl_copy_snapshot
repl_restore:
    lw t0, repl_backup_count
    sw t0, repl_line_count, t1
    la t0, repl_backup_numbers
    la t1, repl_numbers
    li t2, 16896
repl_copy_snapshot:
    bnez t2, safety_near_13
    j safety_return
safety_near_13:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -4
    j repl_copy_snapshot
repl_save_file:
    ENTER_FRAME (48)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    la a0, input_line
    call repl_extract_file_name
    CHECK_ERROR (repl_save_file_return)
    lbu t0, 0(a0)
    beqz t0, rsf_err
    la a0, file_name
    li a1, 1
    li a7, 1024
    ecall
    bltz a0, rsf_err
    mv s0, a0
    li s1, 0
rsf_loop:
    mv a0, s1
    li a1, 101
    li a2, 9999
    call find_next_slot
    CHECK_ERROR (rsf_close)
    bltz a0, rsf_success
    mv s2, a0
    mv s1, a1
    mv a0, s2
    call repl_text_addr
    CHECK_ERROR (rsf_close)
    mv s3, a0
    call check_slot_text
    CHECK_ERROR (rsf_close)
    mv s4, a1
    mv a0, s1
    call format_line_number
    CHECK_ERROR (rsf_close)
    mv a2, a1
    mv a1, a0
    mv a0, s0
    call write_fd_all
    CHECK_ERROR (rsf_close)
    mv a0, s0
    la a1, file_space
    li a2, 1
    call write_fd_all
    CHECK_ERROR (rsf_close)
    mv a0, s0
    mv a1, s3
    mv a2, s4
    call write_fd_all
    CHECK_ERROR (rsf_close)
    mv a0, s0
    la a1, file_newline
    li a2, 1
    call write_fd_all
    CHECK_ERROR (rsf_close)
    j rsf_loop
rsf_success:
    mv a0, s0
    li a7, 57
    ecall
    la a0, repl_save_ok
    li a7, 4
    ecall
    j rsf_done
rsf_close:
    mv a0, s0
    li a7, 57
    ecall
    j rsf_done
rsf_err:
    call error_file
rsf_done:
repl_save_file_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    addi sp, sp, 48
    ret

# Complete writes only. A zero, negative, or over-sized syscall result is I/O.
# a0=fd, a1=buffer, a2=count.
write_fd_all:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    mv s0, a0
    mv s1, a1
    mv s2, a2
wfa_loop:
    beqz s2, wfa_done
    mv a0, s0
    mv a1, s1
    mv a2, s2
    li a7, 64
    ecall
    blez a0, wfa_error
    bgtu a0, s2, wfa_error
    add s1, s1, a0
    sub s2, s2, a0
    j wfa_loop
wfa_error:
    call error_file
wfa_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    addi sp, sp, 32
    ret
repl_import_program_buf:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    mv s0, a0
rip_outer:
    la t6, program_buf
    bltu s0, t6, repl_import_program_buf_bad_source
    la t6, program_buf_end
    bgeu s0, t6, repl_import_program_buf_bad_source
    lbu t0, 0(s0)
    beqz t0, rip_done
    li t1, 10
    beq t0, t1, rip_skip_nl
    li t1, 13
    beq t0, t1, rip_skip_nl
    la s1, input_line
    li t2, 255
rip_copy:
    beqz t2, rip_full
    la t6, program_buf
    bltu s0, t6, repl_import_program_buf_bad_source
    la t6, program_buf_end
    bgeu s0, t6, repl_import_program_buf_bad_source
    lbu t0, 0(s0)
    beqz t0, rip_copy_done
    li t1, 10
    beq t0, t1, rip_copy_done
    li t1, 13
    beq t0, t1, rip_copy_done
    sb t0, 0(s1)
    addi s1, s1, 1
    addi s0, s0, 1
    addi t2, t2, -1
    j rip_copy
rip_full:
    la t6, program_buf_end
    bgeu s0, t6, repl_import_program_buf_bad_source
    la t6, program_buf
    bltu s0, t6, repl_import_program_buf_bad_source
    la t6, program_buf_end
    bgeu s0, t6, repl_import_program_buf_bad_source
    lbu t0, 0(s0)
    beqz t0, rip_copy_done
    li t1, 10
    beq t0, t1, rip_copy_done
    li t1, 13
    beq t0, t1, rip_copy_done
    call error_text
    j rip_done
rip_copy_done:
    sb zero, 0(s1)
    la a0, input_line
    call repl_store_line
    CHECK_ERROR (repl_import_program_buf_return)
rip_to_next:
    la t6, program_buf
    bltu s0, t6, repl_import_program_buf_bad_source
    la t6, program_buf_end
    bgeu s0, t6, repl_import_program_buf_bad_source
    lbu t0, 0(s0)
    beqz t0, rip_outer
    li t1, 10
    beq t0, t1, rip_skip_nl
    li t1, 13
    beq t0, t1, rip_skip_nl
    addi s0, s0, 1
    j rip_to_next
rip_skip_nl:
    addi s0, s0, 1
    j rip_outer
rip_done:
    j repl_import_program_buf_return
repl_import_program_buf_bad_source:
    call error_syntax
repl_import_program_buf_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    addi sp, sp, 32
    ret
string_length:
    mv t0, a0
    li a0, 0
sl_loop:
    la t6, program_buf
    bgeu t0, t6, safety_near_14
    j error_program
safety_near_14:
    la t6, program_buf_end
    bltu t0, t6, safety_near_15
    j error_program
safety_near_15:
    lbu t1, 0(t0)
    beqz t1, sl_done
    addi a0, a0, 1
    addi t0, t0, 1
    j sl_loop
sl_done:
    ret
program_exit:
    li a7, 10
    ecall
# Two phases: collect canonical source identities, then emit in key order.
# Until compilation succeeds, line_offsets holds bounded source pointers;
# the emission pass replaces every entry with its actual wordcode address.
# VM must only run after the caller has checked error_code (stage-2 contract).
compile_program:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    lw a0, source_ptr
    la t0, program_buf
    li a1, 8192
    beq a0, t0, cp_bind
    la t0, focal_program
    bne a0, t0, cp_bad
    la a1, focal_program_end
    sub a1, a1, a0
cp_bind:
    call set_parse_span
    CHECK_ERROR (cp_done)
    mv s0, a0
    li s3, 0
    sw zero, line_count, t0
cp_collect:
    mv a0, s0
    call skip_spaces_a0
    CHECK_ERROR (cp_done)
    mv s0, a0
    lbu t0, 0(s0)
    beqz t0, cp_sort_begin
    li t1, 10
    beq t0, t1, cp_next_source
    li t1, 13
    beq t0, t1, cp_next_source
    sw s0, parse_ptr, t0
    li a0, 0
    call parse_program_number
    CHECK_ERROR (cp_done)
    mv s1, a0
    call skip_parse_spaces
    CHECK_ERROR (cp_done)
    lw a0, parse_ptr
    lbu t0, 0(a0)
    li t1, 58
    bne t0, t1, cp_separator
    addi a0, a0, 1
cp_separator:
    call skip_spaces_a0
    CHECK_ERROR (cp_done)
    mv s2, a0
    mv s0, a0
    li s4, 0
    la t0, line_numbers
cp_find_existing:
    bgeu s4, s3, cp_record
    lw t1, 0(t0)
    beq t1, s1, cp_record
    addi t0, t0, 4
    addi s4, s4, 1
    j cp_find_existing
cp_record:
    lbu t0, 0(s2)
    beqz t0, cp_delete
    li t1, 10
    beq t0, t1, cp_delete
    li t1, 13
    beq t0, t1, cp_delete
    bltu s4, s3, cp_store
    li t0, MAX_LINES
    bgeu s3, t0, cp_full
    addi s3, s3, 1
cp_store:
    slli t0, s4, 2
    la t1, line_numbers
    add t1, t1, t0
    sw s1, 0(t1)
    la t1, line_offsets
    add t1, t1, t0
    sw s2, 0(t1)
    j cp_scan_tail
cp_delete:
    bgeu s4, s3, cp_scan_tail
    addi s3, s3, -1
    slli t0, s3, 2
    slli t1, s4, 2
    la t2, line_numbers
    add t3, t2, t0
    add t2, t2, t1
    lw t4, 0(t3)
    sw t4, 0(t2)
    la t2, line_offsets
    add t3, t2, t0
    add t2, t2, t1
    lw t4, 0(t3)
    sw t4, 0(t2)
cp_scan_tail:
    sw s3, line_count, t0
    CHECK_PARSE (s0, cp_bad)
    lbu t0, 0(s0)
    beqz t0, cp_sort_begin
    li t1, 10
    beq t0, t1, cp_next_source
    addi s0, s0, 1
    j cp_scan_tail
cp_next_source:
    addi s0, s0, 1
    j cp_collect
cp_sort_begin:
    sw s3, line_count, t0
    li s0, 0
cp_sort_outer:
    bgeu s0, s3, cp_emit_begin
    mv s1, s0
    slli t0, s0, 2
    la t1, line_numbers
    add t1, t1, t0
    lw s2, 0(t1)
    addi t0, s0, 1
cp_sort_inner:
    bgeu t0, s3, cp_sort_swap
    slli t1, t0, 2
    la t2, line_numbers
    add t2, t2, t1
    lw t3, 0(t2)
    bgeu t3, s2, cp_sort_next
    mv s1, t0
    mv s2, t3
cp_sort_next:
    addi t0, t0, 1
    j cp_sort_inner
cp_sort_swap:
    slli t0, s0, 2
    slli t1, s1, 2
    la t2, line_numbers
    add t3, t2, t0
    add t2, t2, t1
    lw t4, 0(t3)
    lw t5, 0(t2)
    sw t5, 0(t3)
    sw t4, 0(t2)
    la t2, line_offsets
    add t3, t2, t0
    add t2, t2, t1
    lw t4, 0(t3)
    lw t5, 0(t2)
    sw t5, 0(t3)
    sw t4, 0(t2)
    addi s0, s0, 1
    j cp_sort_outer
cp_emit_begin:
    li s0, 0
cp_emit_loop:
    bgeu s0, s3, cp_halt
    slli t0, s0, 2
    la t1, line_offsets
    add t1, t1, t0
    lw t2, 0(t1)
    sw t2, parse_ptr, t0
    lw t2, bc_ptr
    la t3, bytecode_buf
    sub t2, t2, t3
    sw t2, 0(t1)
    call compile_physical_line
    CHECK_ERROR (cp_done)
    addi s0, s0, 1
    j cp_emit_loop
cp_halt:
    li a0, OP_HALT
    call emit_word
    j cp_done
cp_full:
    call error_lines
    j cp_done
cp_bad:
    call error_syntax
cp_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    addi sp, sp, 32
    ret
add_line_table_entry:
    CHECK_ERROR (safety_return)
    lw t5, bc_ptr
    CHECK_BC (t5)
    la t0, line_count
    lw t1, 0(t0)
    li t6, MAX_LINES
    bltu t1, t6, safety_near_16
    j error_lines
safety_near_16:
    slli t2, t1, 2
    la t3, line_numbers
    add t3, t3, t2
    sw a0, 0(t3)
    la t4, bc_ptr
    lw t5, 0(t4)
    la t4, bytecode_buf
    sub t5, t5, t4
    la t3, line_offsets
    add t3, t3, t2
    sw t5, 0(t3)
    addi t1, t1, 1
    sw t1, 0(t0)
    ret
# Compile one complete physical FOCAL line. Semicolons are recognized only
# here, after each statement parser has respected string/token boundaries.
# Empty statements emit no wordcode. COMMENT advances to the physical end.
compile_physical_line:
    ENTER_FRAME (16)
    sw ra, 0(sp)
cpl_next:
    call skip_parse_spaces
    CHECK_ERROR (compile_physical_line_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_physical_line_bad_source)
    lbu t1, 0(t0)
    beqz t1, compile_physical_line_return
    li t2, 10
    beq t1, t2, compile_physical_line_return
    li t2, 13
    beq t1, t2, compile_physical_line_return
    li t2, 59
    bne t1, t2, cpl_statement
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    j cpl_next
cpl_statement:
    call compile_statement
    CHECK_ERROR (compile_physical_line_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_physical_line_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_physical_line_bad_source)
    lbu t1, 0(t0)
    beqz t1, compile_physical_line_return
    li t2, 10
    beq t1, t2, compile_physical_line_return
    li t2, 13
    beq t1, t2, compile_physical_line_return
    li t2, 59
    bne t1, t2, compile_physical_line_bad_source
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    j cpl_next
compile_physical_line_bad_source:
    call error_syntax
compile_physical_line_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# Compile exactly one non-empty statement and leave parse_ptr at its lexical
# end. Physical separators and empty statements belong to the wrapper above.
compile_statement:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_statement_return)
    lw t0, parse_ptr
    sw t0, 4(sp)
    call read_keyword
    CHECK_ERROR (compile_statement_return)
    # Existing compiler procedures consume their own leading keyword.
    lw t0, 4(sp)
    sw t0, parse_ptr, t1
    li t0, TK_SET
    beq a0, t0, cs_set
    li t0, TK_TYPE
    beq a0, t0, cs_type
    li t0, TK_ASK
    beq a0, t0, cs_ask
    li t0, TK_GOTO
    beq a0, t0, cs_goto
    li t0, TK_IF
    beq a0, t0, cs_if
    li t0, TK_FOR
    beq a0, t0, cs_for
    li t0, TK_QUIT
    beq a0, t0, cs_quit
    li t0, TK_COMMENT
    beq a0, t0, cs_comment
    li t0, TK_DO
    beq a0, t0, cs_deferred
    li t0, TK_RETURN
    beq a0, t0, cs_deferred
    li t0, TK_WRITE
    beq a0, t0, cs_write
    li a0, ERR_SYNTAX
    la a1, err_unknown
    call set_error
    j cs_done
cs_write:
    call compile_write
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_deferred:
    li a0, ERR_DEFERRED
    la a1, msg_deferred
    call set_error
    j cs_done
cs_set:
    call compile_set
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_type:
    call compile_type
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_ask:
    call compile_ask
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_if:
    call compile_if
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_for:
    call compile_for
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_goto:
    call compile_goto
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_quit:
    call consume_quit
    CHECK_ERROR (compile_statement_return)
    li a0, OP_HALT
    call emit_word
    CHECK_ERROR (compile_statement_return)
    j cs_done
cs_comment:
    call compile_comment
    CHECK_ERROR (compile_statement_return)
cs_done:
    j compile_statement_return
compile_statement_bad_source:
    call error_syntax
compile_statement_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# COMMENT/C consumes unparsed bytes only to LF/CR/NUL. Thus a comment cannot
# swallow the next numbered line in program_buf or embedded batch source.
compile_comment:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call consume_comment
    CHECK_ERROR (compile_comment_return)
cc_tail:
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_comment_bad_source)
    lbu t1, 0(t0)
    beqz t1, compile_comment_return
    li t2, 10
    beq t1, t2, compile_comment_return
    li t2, 13
    beq t1, t2, compile_comment_return
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    j cc_tail
compile_comment_bad_source:
    call error_syntax
compile_comment_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_set:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    call consume_set
    CHECK_ERROR (compile_set_return)
    call parse_variable_ref
    CHECK_ERROR (compile_set_return)
    sw a0, 4(sp)
    sw a1, 8(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_set_return)
    call consume_equal
    CHECK_ERROR (compile_set_return)
    call compile_expr
    CHECK_ERROR (compile_set_return)
    lw t0, 8(sp)
    lw t1, 4(sp)
    beqz t0, cset_scalar
    li a0, OP_STORE_ARR
    call emit_word
    CHECK_ERROR (compile_set_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_set_return)
    j cset_done
cset_scalar:
    li a0, OP_STORE_V
    call emit_word
    CHECK_ERROR (compile_set_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_set_return)
cset_done:
compile_set_return:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
compile_type:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call consume_type
    CHECK_ERROR (compile_type_return)
ct_loop:
    call skip_parse_spaces
    CHECK_ERROR (compile_type_return)
    call is_parse_statement_end
    CHECK_ERROR (compile_type_return)
    bnez a0, ct_done
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_type_bad_source)
    lbu t2, 0(t1)
    li t3, 34
    beq t2, t3, ct_string
    li t3, 33
    beq t2, t3, ct_newline
    li t3, 44
    beq t2, t3, ct_comma
    call compile_expr
    CHECK_ERROR (compile_type_return)
    li a0, OP_PRINT_F
    call emit_word
    CHECK_ERROR (compile_type_return)
    # Numeric/variable expressions in TYPE require an actual list/control or
    # statement boundary. This prevents E3 and 1.2.3 becoming two operands.
    call skip_parse_spaces
    CHECK_ERROR (compile_type_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_type_bad_source)
    lbu t1, 0(t0)
    beqz t1, ct_loop
    li t2, 10
    beq t1, t2, ct_loop
    li t2, 13
    beq t1, t2, ct_loop
    li t2, 59
    beq t1, t2, ct_loop
    li t2, 44
    beq t1, t2, ct_loop
    li t2, 33
    beq t1, t2, ct_loop
    j compile_type_bad_source
ct_string:
    call copy_string_to_pool
    CHECK_ERROR (compile_type_return)
    sw a0, 4(sp)
    li a0, OP_PRINT_S
    call emit_word
    CHECK_ERROR (compile_type_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_type_return)
    j ct_loop
ct_newline:
    addi t1, t1, 1
    sw t1, 0(t0)
    li a0, OP_PRINT_NL
    call emit_word
    CHECK_ERROR (compile_type_return)
    j ct_loop
ct_comma:
    addi t1, t1, 1
    sw t1, 0(t0)
    j ct_loop
ct_done:
    j compile_type_return
compile_type_bad_source:
    call error_syntax
compile_type_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_ask:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call consume_ask
    CHECK_ERROR (compile_ask_return)
    call parse_variable_ref
    CHECK_ERROR (compile_ask_return)
    sw a0, 4(sp)
    sw a1, 8(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_ask_return)
    call consume_comma
    CHECK_ERROR (compile_ask_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_ask_return)
    call copy_string_to_pool
    CHECK_ERROR (compile_ask_return)
    sw a0, 12(sp)
    li a0, OP_PRINT_S
    call emit_word
    CHECK_ERROR (compile_ask_return)
    lw a0, 12(sp)
    call emit_word
    CHECK_ERROR (compile_ask_return)
    li a0, OP_READ_F
    call emit_word
    CHECK_ERROR (compile_ask_return)
    lw t0, 8(sp)
    lw t1, 4(sp)
    beqz t0, cask_scalar
    li a0, OP_STORE_ARR
    call emit_word
    CHECK_ERROR (compile_ask_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_ask_return)
    j cask_done
cask_scalar:
    li a0, OP_STORE_V
    call emit_word
    CHECK_ERROR (compile_ask_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_ask_return)
cask_done:
compile_ask_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_if:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call consume_if
    CHECK_ERROR (compile_if_return)
    call compile_expr
    CHECK_ERROR (compile_if_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_if_return)
    lw t0, parse_ptr
    sw t0, 12(sp)
    call read_keyword
    CHECK_ERROR (compile_if_return)
    lw t0, 12(sp)
    sw t0, parse_ptr, t1
    li t0, TK_THEN
    beq a0, t0, cif_then
    li t0, TK_GOTO
    beq a0, t0, cif_goto
    li t0, TK_DO
    beq a0, t0, cif_do
    call error_syntax
    j compile_if_return
cif_then:
    call consume_then
    CHECK_ERROR (compile_if_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_if_return)
    li a0, 0
    call parse_program_number
    CHECK_ERROR (compile_if_return)
    sw a0, 4(sp)
    li a0, OP_JUMP_NZ
    call emit_word
    CHECK_ERROR (compile_if_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_if_return)
    j cif_done
cif_goto:
    call consume_goto
    CHECK_ERROR (compile_if_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_if_return)
    li a0, 0
    call parse_program_number
    CHECK_ERROR (compile_if_return)
    sw a0, 4(sp)
    li a0, OP_JUMP_NZ
    call emit_word
    CHECK_ERROR (compile_if_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_if_return)
    j cif_done
cif_do:
    li a0, OP_JUMP_Z_ABS
    call emit_word
    CHECK_ERROR (compile_if_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 4(sp)
    li a0, 0
    call emit_word
    CHECK_ERROR (compile_if_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_if_return)
    call consume_do
    CHECK_ERROR (compile_if_return)
    call compile_statement
    CHECK_ERROR (compile_if_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 4(sp)
    mv a0, t2
    mv a1, t1
    call patch_word
    CHECK_ERROR (compile_if_return)
cif_done:
    j compile_if_return
compile_if_bad_source:
    call error_syntax
compile_if_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_goto:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call consume_goto
    CHECK_ERROR (compile_goto_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_goto_return)
    li a0, 0
    call parse_program_number
    CHECK_ERROR (compile_goto_return)
    sw a0, 4(sp)
    li a0, OP_JUMP
    call emit_word
    CHECK_ERROR (compile_goto_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_goto_return)
compile_goto_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_for:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    call consume_for
    CHECK_ERROR (compile_for_return)
    call parse_variable_ref
    CHECK_ERROR (compile_for_return)
    sw a0, 4(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_for_return)
    call consume_equal
    CHECK_ERROR (compile_for_return)
    call compile_expr
    CHECK_ERROR (compile_for_return)
    li a0, OP_STORE_V
    call emit_word
    CHECK_ERROR (compile_for_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_for_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 12(sp)
    li a0, OP_PUSH_V
    call emit_word
    CHECK_ERROR (compile_for_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_for_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_for_return)
    call consume_comma
    CHECK_ERROR (compile_for_return)
    call compile_expr
    CHECK_ERROR (compile_for_return)
    li a0, OP_GT
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, OP_JUMP_Z_ABS
    call emit_word
    CHECK_ERROR (compile_for_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 16(sp)
    li a0, 0
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, OP_JUMP_ABS
    call emit_word
    CHECK_ERROR (compile_for_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 8(sp)
    li a0, 0
    call emit_word
    CHECK_ERROR (compile_for_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 16(sp)
    mv a0, t2
    mv a1, t1
    call patch_word
    CHECK_ERROR (compile_for_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_for_return)
    call consume_do
    CHECK_ERROR (compile_for_return)
    call compile_statement
    CHECK_ERROR (compile_for_return)
    li a0, OP_PUSH_V
    call emit_word
    CHECK_ERROR (compile_for_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, OP_PUSH_F
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, 1
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, OP_ADD
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, OP_STORE_V
    call emit_word
    CHECK_ERROR (compile_for_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_for_return)
    li a0, OP_JUMP_ABS
    call emit_word
    CHECK_ERROR (compile_for_return)
    lw a0, 12(sp)
    call emit_word
    CHECK_ERROR (compile_for_return)
    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 8(sp)
    mv a0, t2
    mv a1, t1
    call patch_word
    CHECK_ERROR (compile_for_return)
compile_for_return:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
# Normative expression path. Comparisons remain only for the existing legacy
# IF/FOR callers; arithmetic levels below implement the v1.2 precedence.
compile_expr:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_expr_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_expr_bad_source)
    lbu t1, 0(t0)
    li t2, 61
    beq t1, t2, cexpr_eq
    li t2, 60
    beq t1, t2, cexpr_lt
    li t2, 62
    beq t1, t2, cexpr_gt
    j compile_expr_return
cexpr_eq:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_EQ
    call emit_word
    j compile_expr_return
cexpr_lt:
    addi t0, t0, 1
    CHECK_PARSE (t0, compile_expr_bad_source)
    lbu t1, 0(t0)
    li t2, 61
    beq t1, t2, cexpr_le
    li t2, 62
    beq t1, t2, cexpr_ne
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_LT
    call emit_word
    j compile_expr_return
cexpr_le:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_LE
    call emit_word
    j compile_expr_return
cexpr_ne:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_NE
    call emit_word
    j compile_expr_return
cexpr_gt:
    addi t0, t0, 1
    CHECK_PARSE (t0, compile_expr_bad_source)
    lbu t1, 0(t0)
    li t2, 61
    beq t1, t2, cexpr_ge
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_GT
    call emit_word
    j compile_expr_return
cexpr_ge:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_GE
    call emit_word
    j compile_expr_return
compile_expr_bad_source:
    call error_syntax
compile_expr_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# Lowest arithmetic level. A unary sign is allowed only at the beginning of a
# complete expression/group/function argument, never after a binary + or -.
compile_additive:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    li a0, 1
    call compile_division
    CHECK_ERROR (compile_additive_return)
cadd_loop:
    call skip_parse_spaces
    CHECK_ERROR (compile_additive_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_additive_bad_source)
    lbu t1, 0(t0)
    li t2, 43
    beq t1, t2, cadd_plus
    li t2, 45
    beq t1, t2, cadd_minus
    j compile_additive_return
cadd_plus:
    li t3, OP_ADD
    j cadd_rhs
cadd_minus:
    li t3, OP_SUB
cadd_rhs:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    sw t3, 4(sp)
    li a0, 0
    call compile_division
    CHECK_ERROR (compile_additive_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_additive_return)
    j cadd_loop
compile_additive_bad_source:
    call error_syntax
compile_additive_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# Division is deliberately below multiplication: 8/2*2 means 8/(2*2).
# a0 says whether the first factor may carry one unary sign.
compile_division:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    sw s0, 4(sp)
    mv s0, a0
    mv a0, s0
    call compile_multiplication
    CHECK_ERROR (compile_division_return)
cdiv_loop:
    call skip_parse_spaces
    CHECK_ERROR (compile_division_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_division_bad_source)
    lbu t1, 0(t0)
    li t2, 47
    bne t1, t2, compile_division_return
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    li a0, 0
    call compile_multiplication
    CHECK_ERROR (compile_division_return)
    li a0, OP_DIV
    call emit_word
    CHECK_ERROR (compile_division_return)
    j cdiv_loop
compile_division_bad_source:
    call error_syntax
compile_division_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    addi sp, sp, 16
    ret

# a0 says whether the first power may carry one unary sign. Operands following
# '*' are unsigned unless explicitly grouped.
compile_multiplication:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    beqz a0, cmul_first_power
    call compile_unary
    j cmul_first_done
cmul_first_power:
    call compile_power
cmul_first_done:
    CHECK_ERROR (compile_multiplication_return)
cmul_loop:
    call skip_parse_spaces
    CHECK_ERROR (compile_multiplication_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_multiplication_bad_source)
    lbu t1, 0(t0)
    li t2, 42
    bne t1, t2, compile_multiplication_return
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_power
    CHECK_ERROR (compile_multiplication_return)
    li a0, OP_MUL
    call emit_word
    CHECK_ERROR (compile_multiplication_return)
    j cmul_loop
compile_multiplication_bad_source:
    call error_syntax
compile_multiplication_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# Exactly one optional sign. Power binds inside it, hence -A^I == -(A^I).
compile_unary:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    sw zero, 4(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_unary_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_unary_bad_source)
    lbu t1, 0(t0)
    li t2, 43
    beq t1, t2, cunary_plus
    li t2, 45
    bne t1, t2, cunary_operand
    li t3, 1
    sw t3, 4(sp)
cunary_plus:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
cunary_operand:
    call compile_power
    CHECK_ERROR (compile_unary_return)
    lw t0, 4(sp)
    beqz t0, compile_unary_return
    li a0, OP_NEG
    call emit_word
    j compile_unary_return
compile_unary_bad_source:
    call error_syntax
compile_unary_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# Right-associative integer power. Its RHS may have one unary sign so 2^-2 is
# valid, while other binary operators still reject an ungrouped sign.
compile_power:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call compile_primary
    CHECK_ERROR (compile_power_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_power_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_power_bad_source)
    lbu t1, 0(t0)
    li t2, 94
    bne t1, t2, compile_power_return
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_unary
    CHECK_ERROR (compile_power_return)
    li a0, OP_POW
    call emit_word
    j compile_power_return
compile_power_bad_source:
    call error_syntax
compile_power_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret

# Primary: binary32 literal, variable, grouping, or one normative F-function.
compile_primary:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_primary_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_primary_bad_source)
    lbu t1, 0(t0)
    li t2, 40
    beq t1, t2, cprimary_paren
    li t2, 91
    beq t1, t2, cprimary_square
    li t2, 60
    beq t1, t2, cprimary_angle
    li t2, 46
    beq t1, t2, cprimary_number
    li t2, 48
    bltu t1, t2, cprimary_name
    li t2, 57
    bleu t1, t2, cprimary_number
cprimary_name:
    call read_function
    CHECK_ERROR (compile_primary_return)
    beqz a0, cprimary_variable
    mv s1, a0
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_primary_bad_source)
    lbu t1, 0(t0)
    li t2, 40
    beq t1, t2, cprimary_function_paren
    li t2, 91
    beq t1, t2, cprimary_function_square
    li t2, 60
    bne t1, t2, compile_primary_bad_source
    li s0, 62
    j cprimary_open
cprimary_function_paren:
    li s0, 41
    j cprimary_open
cprimary_function_square:
    li s0, 93
    j cprimary_open
cprimary_paren:
    li s0, 41
    li s1, 0
    j cprimary_open
cprimary_square:
    li s0, 93
    li s1, 0
    j cprimary_open
cprimary_angle:
    li s0, 62
    li s1, 0
cprimary_open:
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    call compile_additive
    CHECK_ERROR (compile_primary_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_primary_return)
    lw t0, parse_ptr
    CHECK_PARSE (t0, compile_primary_bad_source)
    lbu t1, 0(t0)
    bne t1, s0, compile_primary_bad_source
    addi t0, t0, 1
    sw t0, parse_ptr, t1
    beqz s1, compile_primary_return
    mv a0, s1
    call emit_word
    j compile_primary_return
cprimary_number:
    call parse_float_literal
    CHECK_ERROR (compile_primary_return)
    mv s2, a0
    li a0, OP_PUSH_BITS
    call emit_word
    CHECK_ERROR (compile_primary_return)
    mv a0, s2
    call emit_word
    j compile_primary_return
cprimary_variable:
    call parse_variable_ref
    CHECK_ERROR (compile_primary_return)
    mv s2, a0
    beqz a1, cprimary_scalar
    li a0, OP_PUSH_ARR
    call emit_word
    CHECK_ERROR (compile_primary_return)
    mv a0, s2
    call emit_word
    j compile_primary_return
cprimary_scalar:
    li a0, OP_PUSH_V
    call emit_word
    CHECK_ERROR (compile_primary_return)
    mv a0, s2
    call emit_word
    j compile_primary_return
compile_primary_bad_source:
    call error_syntax
compile_primary_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    addi sp, sp, 32
    ret

# Case-insensitive exact match for FABS/FSQT/FITR/FSGN. On success parse_ptr
# points at the opening bracket and a0 is the function opcode; otherwise zero.
read_function:
    CHECK_ERROR (safety_return)
    la a2, function_table
rf_entry:
    lw a4, 0(a2)
    beqz a4, rf_none
    lw a5, parse_ptr
rf_compare:
    lbu t2, 0(a4)
    beqz t2, rf_name_end
    CHECK_PARSE (a5, rf_none)
    lbu t3, 0(a5)
    li t4, 97
    bltu t3, t4, rf_folded
    li t4, 122
    bgtu t3, t4, rf_folded
    addi t3, t3, -32
rf_folded:
    bne t2, t3, rf_next
    addi a4, a4, 1
    addi a5, a5, 1
    j rf_compare
rf_name_end:
    CHECK_PARSE (a5, rf_none)
rf_skip_spaces:
    lbu t3, 0(a5)
    li t4, 32
    beq t3, t4, rf_space
    li t4, 9
    bne t3, t4, rf_bracket
rf_space:
    addi a5, a5, 1
    CHECK_PARSE (a5, rf_none)
    j rf_skip_spaces
rf_bracket:
    li t4, 40
    beq t3, t4, rf_found
    li t4, 91
    beq t3, t4, rf_found
    li t4, 60
    bne t3, t4, rf_next
rf_found:
    sw a5, parse_ptr, t4
    lw a0, 4(a2)
    ret
rf_next:
    addi a2, a2, 8
    j rf_entry
rf_none:
    li a0, 0
    ret

# Decimal/exponent scanner and binary32 converter. The sign belongs to unary,
# not to this literal. Returns raw IEEE-754 single bits in a0.
parse_float_literal:
    la t0, parse_ptr
    lw t1, 0(t0)
    li t3, 0
    fmv.w.x ft0, zero
    la t4, ten_f
    flw ft1, 0(t4)
pfl_integer:
    CHECK_PARSE (t1, pfl_bad)
    lbu t2, 0(t1)
    li t4, 48
    bltu t2, t4, pfl_after_integer
    li t4, 57
    bgtu t2, t4, pfl_after_integer
    addi t2, t2, -48
    fcvt.s.w ft2, t2
    fmul.s ft0, ft0, ft1
    fadd.s ft0, ft0, ft2
    addi t3, t3, 1
    addi t1, t1, 1
    j pfl_integer
pfl_after_integer:
    li t4, 46
    bne t2, t4, pfl_digits_done
    addi t1, t1, 1
    la t4, tenth_f
    flw ft3, 0(t4)
    flw ft4, 0(t4)
pfl_fraction:
    CHECK_PARSE (t1, pfl_bad)
    lbu t2, 0(t1)
    li t4, 48
    bltu t2, t4, pfl_digits_done
    li t4, 57
    bgtu t2, t4, pfl_digits_done
    addi t2, t2, -48
    fcvt.s.w ft2, t2
    fmul.s ft2, ft2, ft3
    fadd.s ft0, ft0, ft2
    fmul.s ft3, ft3, ft4
    addi t3, t3, 1
    addi t1, t1, 1
    j pfl_fraction
pfl_digits_done:
    beqz t3, pfl_bad
    CHECK_PARSE (t1, pfl_bad)
    lbu t2, 0(t1)
    li t4, 69
    beq t2, t4, pfl_exponent
    li t4, 101
    bne t2, t4, pfl_finish
pfl_exponent:
    addi t1, t1, 1
    CHECK_PARSE (t1, pfl_bad)
    lbu t2, 0(t1)
    li a4, 0
    li t4, 43
    beq t2, t4, pfl_exp_sign_done
    li t4, 45
    bne t2, t4, pfl_exp_start
    li a4, 1
pfl_exp_sign_done:
    addi t1, t1, 1
pfl_exp_start:
    li a2, 0
    li a3, 0
pfl_exp_digits:
    CHECK_PARSE (t1, pfl_bad)
    lbu t2, 0(t1)
    li t4, 48
    bltu t2, t4, pfl_exp_done
    li t4, 57
    bgtu t2, t4, pfl_exp_done
    li t4, 100
    bgtu a2, t4, pfl_math
    li t4, 10
    mul a2, a2, t4
    addi t2, t2, -48
    add a2, a2, t2
    li t4, 1000
    bgtu a2, t4, pfl_math
    addi a3, a3, 1
    addi t1, t1, 1
    j pfl_exp_digits
pfl_exp_done:
    beqz a3, pfl_bad
    la t4, ten_f
    flw ft1, 0(t4)
    la t4, one_f
    flw ft2, 0(t4)
pfl_scale:
    beqz a2, pfl_apply_scale
    fmul.s ft2, ft2, ft1
    addi a2, a2, -1
    j pfl_scale
pfl_apply_scale:
    bnez a4, pfl_scale_down
    fmul.s ft0, ft0, ft2
    j pfl_finish
pfl_scale_down:
    fdiv.s ft0, ft0, ft2
pfl_finish:
    sw t1, 0(t0)
    fmv.x.w a0, ft0
    ret
pfl_bad:
    j error_syntax
pfl_math:
    j error_math
parse_variable_ref:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_parse_spaces
    CHECK_ERROR (parse_variable_ref_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, parse_variable_ref_bad_source)
    lbu t2, 0(t1)
    li t3, 97
    blt t2, t3, pvr_upper
    li t3, 122
    bgt t2, t3, pvr_upper
    addi t2, t2, -97
    j pvr_index_ready
pvr_upper:
    addi t2, t2, -65
pvr_index_ready:
    li t6, 26
    bgeu t2, t6, parse_variable_ref_bad_source
    sw t2, 4(sp)
    addi t1, t1, 1
    sw t1, 0(t0)
    call skip_parse_spaces
    CHECK_ERROR (parse_variable_ref_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, parse_variable_ref_bad_source)
    lbu t2, 0(t1)
    li t3, 40
    bne t2, t3, pvr_scalar
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_expr
    CHECK_ERROR (parse_variable_ref_return)
    call skip_parse_spaces
    CHECK_ERROR (parse_variable_ref_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, parse_variable_ref_bad_source)
    CHECK_PARSE (t1, parse_variable_ref_bad_source)
    lbu t2, 0(t1)
    li t3, 41
    bne t2, t3, parse_variable_ref_bad_source
    addi t1, t1, 1
    sw t1, 0(t0)
    lw a0, 4(sp)
    li a1, 1
    j pvr_done
pvr_scalar:
    lw a0, 4(sp)
    li a1, 0
pvr_done:
    j parse_variable_ref_return
parse_variable_ref_bad_source:
    call error_syntax
parse_variable_ref_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
vm_run:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
vm_loop:
    la t0, pc_ptr
    lw s0, 0(t0)
    call fetch_word
    CHECK_ERROR (vm_run_return)
    mv s1, a0
    li t1, OP_WRITE
    bne s1, t1, vm_not_write
    j vm_write
vm_not_write:
    li t1, OP_PUSH_F
    beq s1, t1, vm_push_f
    li t1, OP_PUSH_BITS
    beq s1, t1, vm_push_bits
    li t1, OP_PUSH_V
    beq s1, t1, vm_push_v
    li t1, OP_STORE_V
    beq s1, t1, vm_store_v
    li t1, OP_PUSH_ARR
    beq s1, t1, vm_push_arr
    li t1, OP_STORE_ARR
    beq s1, t1, vm_store_arr
    li t1, OP_ADD
    bne s1, t1, safety_near_17
    j vm_add
safety_near_17:
    li t1, OP_SUB
    bne s1, t1, safety_near_18
    j vm_sub
safety_near_18:
    li t1, OP_MUL
    bne s1, t1, safety_near_19
    j vm_mul
safety_near_19:
    li t1, OP_DIV
    bne s1, t1, safety_near_20
    j vm_div
safety_near_20:
    li t1, OP_NEG
    bne s1, t1, safety_near_21
    j vm_neg
safety_near_21:
    li t1, OP_POW
    bne s1, t1, safety_near_pow
    j vm_pow
safety_near_pow:
    li t1, OP_ABS
    bne s1, t1, safety_near_abs
    j vm_abs
safety_near_abs:
    li t1, OP_SQRT
    bne s1, t1, safety_near_sqrt
    j vm_sqrt
safety_near_sqrt:
    li t1, OP_EQ
    bne s1, t1, safety_near_22
    j vm_eq
safety_near_22:
    li t1, OP_NE
    bne s1, t1, safety_near_23
    j vm_ne
safety_near_23:
    li t1, OP_LT
    bne s1, t1, safety_near_24
    j vm_lt
safety_near_24:
    li t1, OP_LE
    bne s1, t1, safety_near_25
    j vm_le
safety_near_25:
    li t1, OP_GT
    bne s1, t1, safety_near_26
    j vm_gt
safety_near_26:
    li t1, OP_GE
    bne s1, t1, safety_near_27
    j vm_ge
safety_near_27:
    li t1, OP_TRUNC
    bne s1, t1, safety_near_trunc
    j vm_trunc
safety_near_trunc:
    li t1, OP_SGN
    bne s1, t1, safety_near_sgn
    j vm_sgn
safety_near_sgn:
    li t1, OP_JUMP
    bne s1, t1, safety_near_28
    j vm_jump
safety_near_28:
    li t1, OP_JUMP_Z
    bne s1, t1, safety_near_29
    j vm_jump_z
safety_near_29:
    li t1, OP_JUMP_NZ
    bne s1, t1, safety_near_30
    j vm_jump_nz
safety_near_30:
    li t1, OP_JUMP_Z_ABS
    bne s1, t1, safety_near_31
    j vm_jump_z_abs
safety_near_31:
    li t1, OP_JUMP_ABS
    bne s1, t1, safety_near_32
    j vm_jump_abs
safety_near_32:
    li t1, OP_PRINT_S
    bne s1, t1, safety_near_33
    j vm_print_s
safety_near_33:
    li t1, OP_PRINT_F
    bne s1, t1, safety_near_34
    j vm_print_f
safety_near_34:
    li t1, OP_PRINT_NL
    bne s1, t1, safety_near_35
    j vm_print_nl
safety_near_35:
    li t1, OP_READ_F
    bne s1, t1, safety_near_36
    j vm_read_f
safety_near_36:
    li t1, OP_HALT
    bne s1, t1, safety_near_37
    j vm_halt
safety_near_37:
    beqz s1, vm_loop
    call error_bc_access
    j vm_halt
vm_push_f:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    fcvt.s.w ft0, a0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_push_bits:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    fmv.w.x ft0, a0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_push_v:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call check_variable
    CHECK_ERROR (vm_run_return)
    slli t0, a0, 2
    la t1, vars
    add t1, t1, t0
    flw ft0, 0(t1)
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_store_v:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call check_variable
    CHECK_ERROR (vm_run_return)
    mv t2, a0
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    slli t0, t2, 2
    la t1, vars
    add t1, t1, t0
    fsw ft0, 0(t1)
    j vm_loop
vm_push_arr:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call check_variable
    CHECK_ERROR (vm_run_return)
    mv t2, a0
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    fcvt.w.s t3, ft0
    call array_addr
    CHECK_ERROR (vm_run_return)
    flw ft0, 0(a0)
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_store_arr:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call check_variable
    CHECK_ERROR (vm_run_return)
    mv t2, a0
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    fmv.s ft2, ft0
    fcvt.w.s t3, ft1
    call array_addr
    CHECK_ERROR (vm_run_return)
    fsw ft2, 0(a0)
    j vm_loop
vm_add:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    fadd.s ft0, ft1, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_sub:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    fsub.s ft0, ft1, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_mul:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    fmul.s ft0, ft1, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_div:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    la t0, zero_f
    flw ft2, 0(t0)
    feq.s t0, ft0, ft2
    bnez t0, vm_math_error
    fdiv.s ft0, ft1, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_neg:
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    fneg.s ft0, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_pow:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    # exponent must round-trip through a signed integer with truncation.
    fcvt.w.s t0, ft0, rtz
    fcvt.s.w ft2, t0
    feq.s t2, ft0, ft2
    beqz t2, vm_math_error
    li t2, -2147483648
    beq t0, t2, vm_math_error
    li t1, 0
    bgez t0, vm_pow_magnitude
    la t2, zero_f
    flw ft2, 0(t2)
    feq.s t2, ft1, ft2
    bnez t2, vm_math_error
    neg t0, t0
    li t1, 1
vm_pow_magnitude:
    fsgnj.s ft3, ft1, ft1
    la t2, one_f
    flw ft0, 0(t2)
vm_pow_loop:
    beqz t0, vm_pow_reciprocal
    andi t2, t0, 1
    beqz t2, vm_pow_square
    fmul.s ft0, ft0, ft3
vm_pow_square:
    srli t0, t0, 1
    beqz t0, vm_pow_reciprocal
    fmul.s ft3, ft3, ft3
    j vm_pow_loop
vm_pow_reciprocal:
    beqz t1, vm_pow_push
    la t2, one_f
    flw ft2, 0(t2)
    fdiv.s ft0, ft2, ft0
vm_pow_push:
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_abs:
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    fsgnjx.s ft0, ft0, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_sqrt:
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    la t0, zero_f
    flw ft1, 0(t0)
    flt.s t0, ft0, ft1
    bnez t0, vm_math_error
    fsqrt.s ft0, ft0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_trunc:
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    # Reject NaN/infinity under the existing arithmetic-error contract. For
    # finite binary32 values at or above 2^23, every representable value is
    # already integral, so preserve it without narrowing through signed int32.
    fmv.x.w t0, ft0
    slli t1, t0, 1
    srli t1, t1, 1
    srli t2, t1, 23
    li t3, 255
    beq t2, t3, vm_math_error
    li t2, 0x4b000000
    bgeu t1, t2, vm_trunc_push
    fcvt.w.s t0, ft0, rtz
    fcvt.s.w ft0, t0
vm_trunc_push:
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_sgn:
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t0, ft0, ft1
    bnez t0, vm_sgn_zero
    flt.s t0, ft0, ft1
    bnez t0, vm_sgn_negative
    la t0, one_f
    flw ft0, 0(t0)
    j vm_sgn_push
vm_sgn_negative:
    la t0, neg_one_f
    flw ft0, 0(t0)
    j vm_sgn_push
vm_sgn_zero:
    fsgnj.s ft0, ft1, ft1
vm_sgn_push:
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_math_error:
    call error_math
    j vm_run_return
vm_eq:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    feq.s t0, ft1, ft0
    call push_bool_t0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_ne:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    feq.s t0, ft1, ft0
    seqz t0, t0
    call push_bool_t0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_lt:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    flt.s t0, ft1, ft0
    call push_bool_t0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_le:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    fle.s t0, ft1, ft0
    call push_bool_t0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_gt:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    flt.s t0, ft0, ft1
    call push_bool_t0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_ge:
    call vm_pop2
    CHECK_ERROR (vm_run_return)
    fle.s t0, ft0, ft1
    call push_bool_t0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_jump:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call set_pc_to_line
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_jump_z:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    mv s2, a0
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t1, ft0, ft1
    bnez t1, safety_near_38
    j vm_loop
safety_near_38:
    mv a0, s2
    call set_pc_to_line
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_jump_nz:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    mv s2, a0
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t1, ft0, ft1
    beqz t1, safety_near_39
    j vm_loop
safety_near_39:
    mv a0, s2
    call set_pc_to_line
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_jump_z_abs:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    mv s2, a0
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t1, ft0, ft1
    bnez t1, safety_near_40
    j vm_loop
safety_near_40:
    mv a0, s2
    call set_pc_absolute
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_jump_abs:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call set_pc_absolute
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_print_s:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    call check_pool_string
    CHECK_ERROR (vm_run_return)
    li a7, 4
    ecall
    j vm_loop
vm_print_f:
    call vm_pop_ft0
    CHECK_ERROR (vm_run_return)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    j vm_loop
vm_print_nl:
    li a0, 10
    li a7, 11
    ecall
    j vm_loop
vm_read_f:
    li a7, 6
    ecall
    fmv.s ft0, fa0
    call vm_push_ft0
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_write:
    call fetch_word
    CHECK_ERROR (vm_run_return)
    mv s2, a0
    call fetch_word
    CHECK_ERROR (vm_run_return)
    mv a1, a0
    mv a0, s2
    call print_source
    CHECK_ERROR (vm_run_return)
    j vm_loop
vm_halt:
vm_run_return:
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
# fetch/patch/jump share the actually emitted interval [bytecode_buf, bc_ptr).
fetch_word:
    CHECK_ERROR (safety_return)
    lw t1, pc_ptr
    CHECK_BC (t1)
    lw t0, bc_ptr
    CHECK_BC (t0)
    bltu t1, t0, safety_near_41
    j error_bc_access
safety_near_41:
    lw a0, 0(t1)
    addi t1, t1, 4
    sw t1, pc_ptr, t0
    ret
patch_word:
    CHECK_ERROR (safety_return)
    CHECK_BC (a0)
    lw t0, bc_ptr
    CHECK_BC (t0)
    bltu a0, t0, safety_near_42
    j error_bc_access
safety_near_42:
    sw a1, 0(a0)
    ret
set_pc_absolute:
    CHECK_ERROR (safety_return)
    CHECK_BC (a0)
    lw t0, bc_ptr
    CHECK_BC (t0)
    bltu a0, t0, safety_near_43
    j error_bc_access
safety_near_43:
    sw a0, pc_ptr, t0
    ret
vm_push_ft0:
    CHECK_ERROR (safety_return)
    lw t1, vm_sp_ptr
    andi t6, t1, 3
    beqz t6, safety_near_44
    j error_vm_overflow
safety_near_44:
    la t6, vm_stack
    bgeu t1, t6, safety_near_45
    j error_vm_overflow
safety_near_45:
    la t6, vm_stack_end
    bltu t1, t6, safety_near_46
    j error_vm_overflow
safety_near_46:
    fsw ft0, 0(t1)
    addi t1, t1, 4
    sw t1, vm_sp_ptr, t0
    ret
vm_pop_ft0:
    CHECK_ERROR (safety_return)
    lw t1, vm_sp_ptr
    andi t6, t1, 3
    beqz t6, safety_near_47
    j error_vm_underflow
safety_near_47:
    la t6, vm_stack_end
    bleu t1, t6, safety_near_48
    j error_vm_underflow
safety_near_48:
    la t6, vm_stack
    bgtu t1, t6, safety_near_49
    j error_vm_underflow
safety_near_49:
    addi t1, t1, -4
    flw ft0, 0(t1)
    sw t1, vm_sp_ptr, t0
    ret
vm_pop2:
    CHECK_ERROR (safety_return)
    lw t1, vm_sp_ptr
    andi t6, t1, 3
    beqz t6, safety_near_50
    j error_vm_underflow
safety_near_50:
    la t6, vm_stack_end
    bleu t1, t6, safety_near_51
    j error_vm_underflow
safety_near_51:
    la t6, vm_stack
    addi t6, t6, 8
    bgeu t1, t6, safety_near_52
    j error_vm_underflow
safety_near_52:
    # Atomic preflight: neither cursor nor operands change on underflow.
    flw ft0, -4(t1)
    flw ft1, -8(t1)
    addi t1, t1, -8
    sw t1, vm_sp_ptr, t0
    ret
push_bool_t0:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    la t1, zero_f
    beqz t0, pbt_zero
    la t1, one_f
pbt_zero:
    flw ft0, 0(t1)
    call vm_push_ft0
    CHECK_ERROR (push_bool_t0_return)
push_bool_t0_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
array_addr:
    CHECK_ERROR (safety_return)
    li t6, 26
    bltu t2, t6, safety_near_53
    j error_array
safety_near_53:
    li t6, ARRAY_LEN
    bltu t3, t6, safety_near_54
    j error_array
safety_near_54:
    li t0, ARRAY_LEN
    mul t1, t2, t0
    add t1, t1, t3
    slli t1, t1, 2
    la a0, arrays
    add a0, a0, t1
    ret
set_pc_to_line:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    sw s3, 4(sp)
    mv s3, a0
    la t0, line_count
    lw t1, 0(t0)
    li t6, MAX_LINES
    bleu t1, t6, sptl_count_ok
    call error_lines
    j set_pc_to_line_return
sptl_count_ok:
    li t2, 0
sptl_loop:
    bge t2, t1, sptl_fail
    slli t3, t2, 2
    la t4, line_numbers
    add t4, t4, t3
    lw t5, 0(t4)
    beq t5, s3, sptl_found
    addi t2, t2, 1
    j sptl_loop
sptl_found:
    la t4, line_offsets
    add t4, t4, t3
    lw t5, 0(t4)
    andi t6, t5, 3
    bnez t6, sptl_bad_offset
    la t0, bytecode_buf
    lw t1, bc_ptr
    sub t1, t1, t0
    bgeu t5, t1, sptl_bad_offset
    add a0, t0, t5
    call set_pc_absolute
    CHECK_ERROR (set_pc_to_line_return)
    j sptl_done
sptl_bad_offset:
    call error_bc_access
    j set_pc_to_line_return
sptl_fail:
    li a0, ERR_LINES
    la a1, err_line
    call set_error
sptl_done:
set_pc_to_line_return:
    lw s3, 4(sp)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
emit_word:
    CHECK_ERROR (safety_return)
    lw t1, bc_ptr
    CHECK_BC (t1)
    la t6, bytecode_end
    bne t1, t6, safety_near_55
    j error_bc_full
safety_near_55:
    sw a0, 0(t1)
    addi t1, t1, 4
    sw t1, bc_ptr, t0
    ret
skip_parse_spaces:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    la t0, parse_ptr
    lw a0, 0(t0)
    call skip_spaces_a0
    CHECK_ERROR (skip_parse_spaces_return)
    la t0, parse_ptr
    sw a0, 0(t0)
skip_parse_spaces_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
skip_spaces_a0:
ssa_loop:
    CHECK_PARSE (a0, error_syntax)
    lbu t0, 0(a0)
    li t1, 32
    beq t0, t1, ssa_next
    li t1, 9
    beq t0, t1, ssa_next
    ret
ssa_next:
    addi a0, a0, 1
    j ssa_loop
is_parse_line_end:
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, error_syntax)
    lbu t2, 0(t1)
    beqz t2, iple_yes
    li t3, 10
    beq t2, t3, iple_yes
    li a0, 0
    ret
iple_yes:
    li a0, 1
    ret

# Statement-local terminator. The physical-line frontend consumes ';'; the
# individual statement compiler only needs to stop before it.
is_parse_statement_end:
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, error_syntax)
    lbu t2, 0(t1)
    beqz t2, ipse_yes
    li t3, 10
    beq t2, t3, ipse_yes
    li t3, 13
    beq t2, t3, ipse_yes
    li t3, 59
    beq t2, t3, ipse_yes
    li a0, 0
    ret
ipse_yes:
    li a0, 1
    ret
parse_int:
    la t0, parse_ptr
    lw t1, 0(t0)
    mv a0, zero
    li t5, 0
    CHECK_PARSE (t1, error_syntax)
    lbu t2, 0(t1)
    li t3, 45
    bne t2, t3, pi_loop
    li t5, 1
    addi t1, t1, 1
pi_loop:
    CHECK_PARSE (t1, error_syntax)
    lbu t2, 0(t1)
    li t3, 48
    blt t2, t3, pi_done
    li t3, 57
    bgt t2, t3, pi_done
    li t3, 10
    mul a0, a0, t3
    addi t2, t2, -48
    add a0, a0, t2
    addi t1, t1, 1
    j pi_loop
pi_done:
    beqz t5, pi_store
    sub a0, zero, a0
pi_store:
    sw t1, 0(t0)
    ret
copy_string_to_pool:
    CHECK_ERROR (safety_return)
    lw t1, parse_ptr
    CHECK_PARSE (t1, error_string)
    lbu t4, 0(t1)
    li t5, 34
    beq t4, t5, safety_near_56
    j error_string
safety_near_56:
    addi t1, t1, 1
    mv a1, t1
    lw a0, str_pool_ptr
    la t6, str_pool
    bgeu a0, t6, safety_near_57
    j error_string
safety_near_57:
    la t6, str_pool_end
    bltu a0, t6, safety_near_58
    j error_string
safety_near_58:
    mv t3, a0
# Preflight source, closing quote and space including NUL; no partial write.
cstr_measure:
    CHECK_PARSE (t1, error_string)
    lbu t4, 0(t1)
    bnez t4, safety_near_59
    j error_string
safety_near_59:
    li t5, 10
    bne t4, t5, safety_near_60
    j error_string
safety_near_60:
    li t5, 34
    beq t4, t5, cstr_copy_begin
    addi t3, t3, 1
    la t6, str_pool_end
    bltu t3, t6, safety_near_61
    j error_string
safety_near_61:
    addi t1, t1, 1
    j cstr_measure
cstr_copy_begin:
    mv t2, a0
cstr_copy:
    beq a1, t1, cstr_done
    lbu t4, 0(a1)
    sb t4, 0(t2)
    addi a1, a1, 1
    addi t2, t2, 1
    j cstr_copy
cstr_done:
    sb zero, 0(t2)
    addi t2, t2, 1
    sw t2, str_pool_ptr, t0
    addi t1, t1, 1
    sw t1, parse_ptr, t0
    ret
consume_set:
    li a7, TK_SET
    j consume_keyword
consume_type:
    li a7, TK_TYPE
    j consume_keyword
consume_ask:
    li a7, TK_ASK
    j consume_keyword
consume_if:
    li a7, TK_IF
    j consume_keyword
consume_for:
    li a7, TK_FOR
    j consume_keyword
consume_goto:
    li a7, TK_GOTO
    j consume_keyword
consume_quit:
    li a7, TK_QUIT
    j consume_keyword
consume_comment:
    li a7, TK_COMMENT
    j consume_keyword
consume_do:
    li a7, TK_DO
    j consume_keyword
consume_then:
    li a7, TK_THEN
    j consume_keyword
consume_keyword:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    sw a7, 4(sp)
    call read_keyword
    CHECK_ERROR (ck_done)
    lw t0, 4(sp)
    beq a0, t0, ck_done
    call error_syntax
ck_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
consume_equal:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_comma:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret


# No frame has been allocated when ENTER_FRAME reaches an error leaf.
init_safety:
    li t0, 65536
    sub t0, sp, t0
    sw t0, proc_stack_floor, t1
    ret
safety_return:
    ret
set_error:
    lw t6, error_code
    bnez t6, safety_return
    sw a0, error_code, t6
    sw a1, error_message, t6
    ret
report_error:
    lw t0, error_code
    beqz t0, safety_return
    lw a0, error_message
    li a7, 4
    ecall
    ret
error_bc_full:
    li a0, ERR_BC_FULL
    la a1, msg_bc_full
    j set_error
error_bc_access:
    li a0, ERR_BC_ACCESS
    la a1, msg_bc_access
    j set_error
error_vm_overflow:
    li a0, ERR_VM_OVERFLOW
    la a1, msg_vm_overflow
    j error_vm_stack
error_vm_underflow:
    li a0, ERR_VM_UNDERFLOW
    la a1, msg_vm_underflow
    j error_vm_stack
# A valid cursor is left intact (notably one-operand pop2 underflow).
# A corrupted cursor is repaired without dereferencing it.
error_vm_stack:
    lw t5, vm_sp_ptr
    andi t6, t5, 3
    bnez t6, error_vm_repair
    la t6, vm_stack
    bltu t5, t6, error_vm_repair
    la t6, vm_stack_end
    bleu t5, t6, set_error
error_vm_repair:
    la t5, vm_stack
    sw t5, vm_sp_ptr, t6
    j set_error
error_string:
    li a0, ERR_STRING
    la a1, msg_string
    j set_error
error_program:
    li a0, ERR_PROGRAM
    la a1, msg_program
    j set_error
error_text:
    li a0, ERR_TEXT
    la a1, msg_text
    j set_error
error_lines:
    li a0, ERR_LINES
    la a1, msg_lines
    j set_error
error_array:
    li a0, ERR_ARRAY
    la a1, msg_array
    j set_error
error_syntax:
    li a0, ERR_SYNTAX
    la a1, msg_syntax
    j set_error
error_proc_stack:
    li a0, ERR_PROC_STACK
    la a1, msg_proc_stack
    j set_error
error_file:
    li a0, ERR_FILE
    la a1, msg_file
    j set_error
error_math:
    li a0, ERR_MATH
    la a1, msg_math
    j set_error

check_variable:
    CHECK_ERROR (safety_return)
    li t6, 26
    bgeu a0, t6, error_array
    ret
check_pool_string:
    CHECK_ERROR (safety_return)
    la t0, str_pool
    bltu a0, t0, error_string
    lw t1, str_pool_ptr
    bltu t1, t0, error_string
    la t0, str_pool_end
    bgtu t1, t0, error_string
    mv t0, a0
cps_loop:
    bgeu t0, t1, error_string
    lbu t6, 0(t0)
    beqz t6, safety_return
    addi t0, t0, 1
    j cps_loop

# Bind a trusted fixed buffer (a0, a1=capacity), locate NUL BEFORE parsing.
# Callers supply only statically allocated source/input regions.
set_parse_span:
    CHECK_ERROR (safety_return)
    mv t0, a0
    add t1, a0, a1
    bleu t1, a0, error_text
sps_scan:
    bgeu t0, t1, error_text
    lbu t2, 0(t0)
    beqz t2, sps_done
    addi t0, t0, 1
    j sps_scan
sps_done:
    sw a0, parse_begin, t1
    sw t0, parse_end, t1
    sw a0, parse_ptr, t1
    ret
validate_input:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    la a0, input_line
    li a1, 256
    call set_parse_span
    CHECK_ERROR (vi_done)
    lw t0, parse_end
    la t1, input_line_end
    addi t1, t1, -1
    bne t0, t1, vi_done
    # RARS ReadString consumes a host line but truncates it to n-1 bytes.
    # A full buffer without LF is ambiguous: reject, never accept truncation.
    lbu t2, -1(t0)
    li t1, 10
    beq t2, t1, vi_done
    call error_text
vi_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret


# One integer representation everywhere: group*100 + line, 101..9999,
# excluding keys ending in 00. No floating point is used for source numbers.
# a0=0: line number (temporary legacy integer ordinal allowed, 1..9801);
# a0=1: WRITE selector (bare integer is group, never a legacy line alias).
# Result a0=key, a1=2 exact line / 1 group; parse_ptr advances on success only.
parse_program_number:
    CHECK_ERROR (safety_return)
    mv a2, a0
    lw t1, parse_ptr
    li t2, 0
    li t3, 0
pn_group:
    CHECK_PARSE (t1, error_number)
    lbu t0, 0(t1)
    li t6, 48
    bltu t0, t6, pn_group_done
    li t6, 57
    bgtu t0, t6, pn_group_done
    addi t3, t3, 1
    li t6, 4
    bgtu t3, t6, error_number
    li t6, 10
    mul t2, t2, t6
    addi t0, t0, -48
    add t2, t2, t0
    addi t1, t1, 1
    j pn_group
pn_group_done:
    beqz t3, error_number
    beqz t2, error_number
    li t6, 46
    bne t0, t6, pn_integer
    li t6, 2
    bgtu t3, t6, error_number
    li t6, 99
    bgtu t2, t6, error_number
    addi t1, t1, 1
    li t4, 0
    li t5, 0
pn_fraction:
    CHECK_PARSE (t1, error_number)
    lbu t0, 0(t1)
    li t6, 48
    bltu t0, t6, pn_fraction_done
    li t6, 57
    bgtu t0, t6, pn_fraction_done
    addi t5, t5, 1
    li t6, 2
    bgtu t5, t6, error_number
    li t6, 10
    mul t4, t4, t6
    addi t0, t0, -48
    add t4, t4, t0
    addi t1, t1, 1
    j pn_fraction
pn_fraction_done:
    beqz t5, error_number
    beqz t4, error_number
    li t6, 1
    bne t5, t6, pn_key
    li t6, 10
    mul t4, t4, t6
pn_key:
    li t6, 100
    mul a0, t2, t6
    add a0, a0, t4
    li a1, 2
    j pn_delimiter
pn_integer:
    beqz a2, pn_legacy
    li t6, 99
    bgtu t2, t6, error_number
    li t6, 2
    bgtu t3, t6, error_number
    li t6, 100
    mul a0, t2, t6
    li a1, 1
    j pn_delimiter
pn_legacy:
    # Migration only: N -> ordinal among 99 lines per group, not decimal N.
    li t6, 9801
    bgtu t2, t6, error_number
    addi t2, t2, -1
    li t6, 99
    divu t4, t2, t6
    remu t5, t2, t6
    addi t4, t4, 1
    li t6, 100
    mul a0, t4, t6
    addi t5, t5, 1
    add a0, a0, t5
    li a1, 2
pn_delimiter:
    beqz t0, pn_ok
    li t6, 32
    beq t0, t6, pn_ok
    li t6, 9
    beq t0, t6, pn_ok
    li t6, 10
    beq t0, t6, pn_ok
    li t6, 13
    beq t0, t6, pn_ok
    li t6, 59
    beq t0, t6, pn_ok
    li t6, 58
    bne t0, t6, error_number
    bnez a2, error_number
pn_ok:
    sw t1, parse_ptr, t6
    ret
error_number:
    li a0, ERR_NUMBER
    la a1, msg_number
    j set_error

# Format a validated canonical key into a fixed 8-byte scratch buffer.
# Returns a0=buffer and a1=byte length (4 or 5). Shared by RUN/SAVE builders
# and LIST/WRITE.
format_line_number:
    CHECK_ERROR (safety_return)
    li t0, 101
    bltu a0, t0, error_number
    li t0, 9999
    bgtu a0, t0, error_number
    li t0, 100
    divu t1, a0, t0
    remu t2, a0, t0
    beqz t2, error_number
    la t3, number_text
    li a1, 4
    li t0, 10
    bltu t1, t0, fln_units
    li a1, 5
    divu t4, t1, t0
    addi t4, t4, 48
    sb t4, 0(t3)
    addi t3, t3, 1
fln_units:
    remu t1, t1, t0
    addi t1, t1, 48
    sb t1, 0(t3)
    li t1, 46
    sb t1, 1(t3)
    divu t1, t2, t0
    remu t2, t2, t0
    addi t1, t1, 48
    addi t2, t2, 48
    sb t1, 2(t3)
    sb t2, 3(t3)
    sb zero, 4(t3)
    la a0, number_text
    ret

# Common sorted traversal: a0=previous key, a1=lower, a2=upper (inclusive).
# Returns a0=physical slot (-1 if absent), a1=key. Zero slots are inactive.
find_next_slot:
    CHECK_ERROR (safety_return)
    lw t0, repl_line_count
    li t6, MAX_LINES
    bgtu t0, t6, error_lines
    li t0, 0
    li t1, 10000
    li a3, -1
    la t2, repl_numbers
fns_loop:
    li t6, MAX_LINES
    bgeu t0, t6, fns_done
    lw t3, 0(t2)
    beqz t3, fns_next
    li t6, 101
    bltu t3, t6, error_number
    li t6, 9999
    bgtu t3, t6, error_number
    li t6, 100
    remu t4, t3, t6
    beqz t4, error_number
    bleu t3, a0, fns_next
    bltu t3, a1, fns_next
    bgtu t3, a2, fns_next
    bgeu t3, t1, fns_next
    mv t1, t3
    mv a3, t0
fns_next:
    addi t0, t0, 1
    addi t2, t2, 4
    j fns_loop
fns_done:
    mv a0, a3
    mv a1, t1
    ret

# Check a physical slot's NUL before output may see its text; return length in a1.
check_slot_text:
    CHECK_ERROR (safety_return)
    la t0, repl_texts
    bltu a0, t0, error_text
    la t1, repl_texts_end
    bgeu a0, t1, error_text
    sub t0, a0, t0
    andi t0, t0, 127
    bnez t0, error_text
    mv t0, a0
    addi t1, a0, LINE_LEN
    li a1, 0
cst_scan:
    bgeu t0, t1, error_text
    lbu t2, 0(t0)
    beqz t2, safety_return
    addi t0, t0, 1
    addi a1, a1, 1
    j cst_scan

# LIST and VM WRITE share this streaming view, independent of program_buf.
# a0=0 all, 1 group (a1=group*100), 2 exact canonical key.
print_source:
    ENTER_FRAME (48)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    sw s5, 24(sp)
    mv s5, a0
    li s1, 101
    li s2, 9999
    li s0, 0
    li s3, 0
    beqz a0, ps_loop
    li t0, 2
    bgtu a0, t0, ps_bad
    mv s1, a1
    mv s2, a1
    li t0, 1
    bne a0, t0, ps_exact
    li t0, 100
    bltu a1, t0, ps_bad
    li t1, 9900
    bgtu a1, t1, ps_bad
    remu t1, a1, t0
    bnez t1, ps_bad
    addi s1, s1, 1
    addi s2, s2, 99
    j ps_loop
ps_exact:
    mv a0, a1
    call format_line_number
    CHECK_ERROR (ps_done)
ps_loop:
    mv a0, s0
    mv a1, s1
    mv a2, s2
    call find_next_slot
    CHECK_ERROR (ps_done)
    bltz a0, ps_end
    mv s0, a1
    call repl_text_addr
    CHECK_ERROR (ps_done)
    mv s4, a0
    call check_slot_text
    CHECK_ERROR (ps_done)
    mv a0, s0
    call format_line_number
    CHECK_ERROR (ps_done)
    li a7, 4
    ecall
    li a0, 32
    li a7, 11
    ecall
    mv a0, s4
    li a7, 4
    ecall
    li a0, 10
    li a7, 11
    ecall
    addi s3, s3, 1
    j ps_loop
ps_end:
    bnez s3, ps_done
    beqz s5, ps_done
    li a0, ERR_LINES
    la a1, err_line
    call set_error
    j ps_done
ps_bad:
    call error_number
ps_done:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    lw s5, 24(sp)
    addi sp, sp, 48
    ret

consume_write:
    li a7, TK_WRITE
    j consume_keyword
compile_write:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw zero, 4(sp)
    sw zero, 8(sp)
    call consume_write
    CHECK_ERROR (cw_done)
    call skip_parse_spaces
    CHECK_ERROR (cw_done)
    call is_parse_statement_end
    CHECK_ERROR (cw_done)
    bnez a0, cw_emit
    lw t0, parse_ptr
    lbu t1, 0(t0)
    li t2, 48
    bltu t1, t2, cw_all
    li t2, 57
    bgtu t1, t2, cw_all
    li a0, 1
    call parse_program_number
    CHECK_ERROR (cw_done)
    sw a0, 8(sp)
    sw a1, 4(sp)
    j cw_end
cw_all:
    call read_keyword
    CHECK_ERROR (cw_done)
    li t0, TK_ALL
    bne a0, t0, cw_bad
cw_end:
    call skip_parse_spaces
    CHECK_ERROR (cw_done)
    call is_parse_statement_end
    CHECK_ERROR (cw_done)
    beqz a0, cw_bad
cw_emit:
    li a0, OP_WRITE
    call emit_word
    CHECK_ERROR (cw_done)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (cw_done)
    lw a0, 8(sp)
    call emit_word
    j cw_done
cw_bad:
    call error_number
cw_done:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
