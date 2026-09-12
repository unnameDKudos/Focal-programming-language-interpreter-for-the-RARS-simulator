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
.eqv OP_NOP        0
.eqv OP_PUSH_F     1
.eqv OP_PUSH_V     2
.eqv OP_STORE_V    3
.eqv OP_PUSH_ARR   4
.eqv OP_STORE_ARR  5
.eqv OP_ADD        16
.eqv OP_SUB        17
.eqv OP_MUL        18
.eqv OP_DIV        19
.eqv OP_NEG        20
.eqv OP_EQ         24
.eqv OP_NE         25
.eqv OP_LT         26
.eqv OP_LE         27
.eqv OP_GT         28
.eqv OP_GE         29
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
    .align 2
# LOAD safety rollback only; not an expanded user storage capacity.
repl_backup_count: .word 0
repl_backup_numbers: .space 512
repl_backup_texts: .space 16384
repl_backup_end:
zero_f:         .float 0.0
one_f:          .float 1.0
err_unknown:    .asciz "FOCAL/RARS error [E10]: unknown statement\n"
err_line:       .asciz "FOCAL/RARS error [E08]: line not found\n"
repl_banner:    .asciz "FOCAL/RARS REPL. Enter HELP for commands.\n"
repl_prompt:    .asciz "> "
repl_empty:     .asciz "No program\n"
repl_load_ok:   .asciz "Loaded\n"
repl_save_ok:   .asciz "Saved\n"
repl_file_err:  .asciz "File error\n"
repl_help_text: .asciz "Commands:\n  numbered line     add or replace program line\n  number only       delete program line\n  FOCAL command     execute immediately\n  RUN or GO         run stored program\n  LIST              show stored program\n  LOAD <file>       load program from file\n  SAVE <file>       save program to file\n  ERASE             clear stored program\n  HELP              show this help\n  QUIT              exit interpreter\nUse full file paths in RARS GUI for LOAD/SAVE.\n"
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
    call normalize_repl_keyword
    CHECK_ERROR (repl_loop)
    la a0, input_line
    call skip_spaces_a0
    CHECK_ERROR (repl_loop)
    lbu t0, 0(a0)
    beqz t0, repl_loop
    li t1, 10
    beq t0, t1, repl_loop
    call repl_is_run
    CHECK_ERROR (repl_loop)
    bnez a0, repl_run
    la a0, input_line
    call repl_is_list
    CHECK_ERROR (repl_loop)
    bnez a0, repl_list
    la a0, input_line
    call repl_is_erase
    CHECK_ERROR (repl_loop)
    bnez a0, repl_erase
    la a0, input_line
    call repl_is_load
    CHECK_ERROR (repl_loop)
    bnez a0, repl_load
    la a0, input_line
    call repl_is_save
    CHECK_ERROR (repl_loop)
    bnez a0, repl_save
    la a0, input_line
    call repl_is_help
    CHECK_ERROR (repl_loop)
    bnez a0, repl_help
    la a0, input_line
    call repl_is_quit
    CHECK_ERROR (repl_loop)
    beqz a0, safety_near_8
    j program_exit
safety_near_8:
    la a0, input_line
    call skip_spaces_a0
    CHECK_ERROR (repl_loop)
    lbu t0, 0(a0)
    li t1, 48
    blt t0, t1, repl_immediate
    li t1, 57
    bgt t0, t1, repl_immediate
    la a0, input_line
    call repl_store_line
    j repl_loop
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
    call repl_build_listing
    CHECK_ERROR (repl_loop)
    la a0, program_buf
    li a7, 4
    ecall
    j repl_loop
repl_erase:
    call repl_clear_program
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
normalize_repl_keyword:
    mv t0, a0
nrk_skip_spaces:
    CHECK_PARSE (t0, error_syntax)
    lbu t1, 0(t0)
    li t2, 32
    beq t1, t2, nrk_space_next
    li t2, 9
    beq t1, t2, nrk_space_next
    j nrk_check_number
nrk_space_next:
    addi t0, t0, 1
    j nrk_skip_spaces
nrk_check_number:
    li t2, 48
    blt t1, t2, nrk_upper
    li t2, 57
    bgt t1, t2, nrk_upper
nrk_digits:
    CHECK_PARSE (t0, error_syntax)
    lbu t1, 0(t0)
    li t2, 48
    blt t1, t2, nrk_after_digits
    li t2, 57
    bgt t1, t2, nrk_after_digits
    addi t0, t0, 1
    j nrk_digits
nrk_after_digits:
    li t2, 58
    bne t1, t2, nrk_skip_after_number
    addi t0, t0, 1
nrk_skip_after_number:
    CHECK_PARSE (t0, error_syntax)
    lbu t1, 0(t0)
    li t2, 32
    beq t1, t2, nrk_after_space_next
    li t2, 9
    beq t1, t2, nrk_after_space_next
    j nrk_upper
nrk_after_space_next:
    addi t0, t0, 1
    j nrk_skip_after_number
nrk_upper:
    CHECK_PARSE (t0, error_syntax)
    lbu t1, 0(t0)
    li t2, 97
    blt t1, t2, nrk_done
    li t2, 122
    bgt t1, t2, nrk_done
    addi t1, t1, -32
    sb t1, 0(t0)
    addi t0, t0, 1
    j nrk_upper
nrk_done:
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
    li a0, 48
    call repl_append_char_to_program
    CHECK_ERROR (repl_run_immediate_return)
    li a0, 58
    call repl_append_char_to_program
    CHECK_ERROR (repl_run_immediate_return)
    li a0, 32
    call repl_append_char_to_program
    CHECK_ERROR (repl_run_immediate_return)
    la a0, input_line
    call skip_spaces_a0
    CHECK_ERROR (repl_run_immediate_return)
rri_copy:
    CHECK_PARSE (a0, repl_run_immediate_bad_source)
    lbu t0, 0(a0)
    beqz t0, rri_copy_done
    li t1, 10
    beq t0, t1, rri_copy_done
    li t1, 13
    beq t0, t1, rri_copy_done
    mv t2, a0
    mv a0, t0
    call repl_append_char_to_program
    CHECK_ERROR (repl_run_immediate_return)
    mv a0, t2
    addi a0, a0, 1
    j rri_copy
rri_copy_done:
    li a0, 10
    call repl_append_char_to_program
    CHECK_ERROR (repl_run_immediate_return)
    sb zero, 0(s4)
    call reset_runtime
    la t0, program_buf
    la t1, source_ptr
    sw t0, 0(t1)
    call compile_program
    CHECK_ERROR (repl_run_immediate_return)
    la t0, bytecode_buf
    la t1, pc_ptr
    sw t0, 0(t1)
    call vm_run
    CHECK_ERROR (repl_run_immediate_return)
    j repl_run_immediate_return
repl_run_immediate_bad_source:
    call error_syntax
repl_run_immediate_return:
    lw ra, 0(sp)
    lw s4, 4(sp)
    addi sp, sp, 32
    ret
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
    CHECK_ERROR (repl_store_line_return)
    call skip_spaces_a0
    CHECK_ERROR (repl_store_line_return)
    la t0, parse_ptr
    sw a0, 0(t0)
    call parse_int
    CHECK_ERROR (repl_store_line_return)
    mv s0, a0
    la t0, parse_ptr
    lw a0, 0(t0)
    call skip_spaces_a0
    CHECK_ERROR (repl_store_line_return)
    CHECK_PARSE (a0, repl_store_line_bad_source)
    lbu t1, 0(a0)
    li t2, 58
    bne t1, t2, rsl_no_colon
    addi a0, a0, 1
rsl_no_colon:
    call skip_spaces_a0
    CHECK_ERROR (repl_store_line_return)
    mv s1, a0
    mv t0, a0
    li t2, 0
rsl_measure:
    CHECK_PARSE (t0, repl_store_line_bad_source)
    CHECK_PARSE (t0, repl_store_line_bad_source)
    lbu t1, 0(t0)
    beqz t1, rsl_measured
    li t3, 10
    beq t1, t3, rsl_measured
    addi t2, t2, 1
    li t3, LINE_LEN
    bgeu t2, t3, rsl_text_error
    addi t0, t0, 1
    j rsl_measure
rsl_text_error:
    call error_text
    j rsl_done
rsl_capacity_error:
    call error_lines
    j rsl_done
rsl_measured:
    mv a0, s0
    call repl_find_line
    CHECK_ERROR (repl_store_line_return)
    mv s2, a0
    CHECK_PARSE (s1, repl_store_line_bad_source)
    lbu t0, 0(s1)
    beqz t0, rsl_delete
    li t1, 10
    beq t0, t1, rsl_delete
    bltz s2, rsl_new
    mv s3, s2
    j rsl_copy
rsl_new:
    la t0, repl_line_count
    lw s3, 0(t0)
    li t1, MAX_LINES
    bgeu s3, t1, rsl_capacity_error
    addi t2, s3, 1
    sw t2, 0(t0)
rsl_copy:
    slli t0, s3, 2
    la t1, repl_numbers
    add t1, t1, t0
    sw s0, 0(t1)
    mv a0, s3
    call repl_text_addr
    CHECK_ERROR (repl_store_line_return)
    mv t0, a0
    mv t1, s1
    li t2, LINE_LEN
    addi t2, t2, -1
rsl_copy_loop:
    beqz t2, rsl_copy_done
    CHECK_PARSE (t1, repl_store_line_bad_source)
    lbu t3, 0(t1)
    beqz t3, rsl_copy_done
    li t4, 10
    beq t3, t4, rsl_copy_done
    sb t3, 0(t0)
    addi t0, t0, 1
    addi t1, t1, 1
    addi t2, t2, -1
    j rsl_copy_loop
rsl_copy_done:
    sb zero, 0(t0)
    j rsl_done
rsl_delete:
    bltz s2, rsl_done
    slli t0, s2, 2
    la t1, repl_numbers
    add t1, t1, t0
    sw zero, 0(t1)
rsl_done:
    j repl_store_line_return
repl_store_line_bad_source:
    call error_syntax
repl_store_line_return:
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
repl_build_program:
    ENTER_FRAME (48)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    la s4, program_buf
    sb zero, 0(s4)
    li s0, 0
rbp_outer:
    li s1, 0
    li s2, 100000
    la t0, repl_line_count
    lw s3, 0(t0)
    li t6, MAX_LINES
    bgtu s3, t6, repl_build_program_capacity_error
    li t1, 0
rbp_find:
    bge t1, s3, rbp_emit
    slli t2, t1, 2
    la t3, repl_numbers
    add t3, t3, t2
    lw t4, 0(t3)
    beqz t4, rbp_next
    ble t4, s0, rbp_next
    bge t4, s2, rbp_next
    mv s2, t4
    mv s1, t1
rbp_next:
    addi t1, t1, 1
    j rbp_find
rbp_emit:
    li t0, 100000
    beq s2, t0, rbp_done
    mv a0, s2
    call repl_append_int_to_program
    CHECK_ERROR (repl_build_program_return)
    li a0, 58
    call repl_append_char_to_program
    CHECK_ERROR (repl_build_program_return)
    li a0, 32
    call repl_append_char_to_program
    CHECK_ERROR (repl_build_program_return)
    mv a0, s1
    call repl_text_addr
    CHECK_ERROR (repl_build_program_return)
    call repl_append_string_to_program
    CHECK_ERROR (repl_build_program_return)
    li a0, 10
    call repl_append_char_to_program
    CHECK_ERROR (repl_build_program_return)
    mv s0, s2
    j rbp_outer
rbp_done:
    sb zero, 0(s4)
    la t0, program_buf_ptr
    sw s4, 0(t0)
    j repl_build_program_return
repl_build_program_capacity_error:
    call error_lines
repl_build_program_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    addi sp, sp, 48
    ret
repl_build_listing:
    ENTER_FRAME (48)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    la s4, program_buf
    sb zero, 0(s4)
    li s0, 0
rbl_outer:
    li s1, 0
    li s2, 100000
    la t0, repl_line_count
    lw s3, 0(t0)
    li t6, MAX_LINES
    bgtu s3, t6, repl_build_listing_capacity_error
    li t1, 0
rbl_find:
    bge t1, s3, rbl_emit
    slli t2, t1, 2
    la t3, repl_numbers
    add t3, t3, t2
    lw t4, 0(t3)
    beqz t4, rbl_next
    ble t4, s0, rbl_next
    bge t4, s2, rbl_next
    mv s2, t4
    mv s1, t1
rbl_next:
    addi t1, t1, 1
    j rbl_find
rbl_emit:
    li t0, 100000
    beq s2, t0, rbl_done
    mv a0, s2
    call repl_append_int_to_program
    CHECK_ERROR (repl_build_listing_return)
    li a0, 32
    call repl_append_char_to_program
    CHECK_ERROR (repl_build_listing_return)
    mv a0, s1
    call repl_text_addr
    CHECK_ERROR (repl_build_listing_return)
    call repl_append_string_to_program
    CHECK_ERROR (repl_build_listing_return)
    li a0, 10
    call repl_append_char_to_program
    CHECK_ERROR (repl_build_listing_return)
    mv s0, s2
    j rbl_outer
rbl_done:
    sb zero, 0(s4)
    la t0, program_buf_ptr
    sw s4, 0(t0)
    j repl_build_listing_return
repl_build_listing_capacity_error:
    call error_lines
repl_build_listing_return:
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    addi sp, sp, 48
    ret
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
repl_is_run:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    la a0, input_line
    call skip_spaces_a0
    CHECK_ERROR (repl_is_run_return)
    lbu t0, 0(a0)
    li t1, 71
    beq t0, t1, rir_go
    li t1, 82
    bne t0, t1, rir_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, rir_no
    lbu t0, 1(a0)
    li t1, 85
    bne t0, t1, rir_no
    lw t6, parse_end
    addi t6, t6, -2
    bgtu a0, t6, rir_no
    lbu t0, 2(a0)
    li t1, 78
    bne t0, t1, rir_no
rir_yes:
    li a0, 1
repl_is_run_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rir_go:
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, rir_no
    lbu t0, 1(a0)
    li t1, 79
    beq t0, t1, rir_yes
    j rir_no
rir_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_list:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_is_list_return)
    lbu t0, 0(a0)
    li t1, 76
    bne t0, t1, ril_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, ril_no
    lbu t0, 1(a0)
    li t1, 73
    bne t0, t1, ril_no
    li a0, 1
repl_is_list_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
ril_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_erase:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_is_erase_return)
    lbu t0, 0(a0)
    li t1, 69
    bne t0, t1, rie_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, rie_no
    lbu t0, 1(a0)
    li t1, 82
    bne t0, t1, rie_no
    li a0, 1
repl_is_erase_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rie_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_load:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_is_load_return)
    lbu t0, 0(a0)
    li t1, 76
    bne t0, t1, rild_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, rild_no
    lbu t0, 1(a0)
    li t1, 79
    bne t0, t1, rild_no
    lw t6, parse_end
    addi t6, t6, -2
    bgtu a0, t6, rild_no
    lbu t0, 2(a0)
    li t1, 65
    bne t0, t1, rild_no
    lw t6, parse_end
    addi t6, t6, -3
    bgtu a0, t6, rild_no
    lbu t0, 3(a0)
    li t1, 68
    bne t0, t1, rild_no
    li a0, 1
repl_is_load_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rild_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_save:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_is_save_return)
    lbu t0, 0(a0)
    li t1, 83
    bne t0, t1, risv_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, risv_no
    lbu t0, 1(a0)
    li t1, 65
    bne t0, t1, risv_no
    lw t6, parse_end
    addi t6, t6, -2
    bgtu a0, t6, risv_no
    lbu t0, 2(a0)
    li t1, 86
    bne t0, t1, risv_no
    lw t6, parse_end
    addi t6, t6, -3
    bgtu a0, t6, risv_no
    lbu t0, 3(a0)
    li t1, 69
    bne t0, t1, risv_no
    li a0, 1
repl_is_save_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
risv_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_help:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_is_help_return)
    lbu t0, 0(a0)
    li t1, 72
    bne t0, t1, rih_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, rih_no
    lbu t0, 1(a0)
    li t1, 69
    bne t0, t1, rih_no
    lw t6, parse_end
    addi t6, t6, -2
    bgtu a0, t6, rih_no
    lbu t0, 2(a0)
    li t1, 76
    bne t0, t1, rih_no
    lw t6, parse_end
    addi t6, t6, -3
    bgtu a0, t6, rih_no
    lbu t0, 3(a0)
    li t1, 80
    bne t0, t1, rih_no
    li a0, 1
repl_is_help_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rih_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_quit:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_spaces_a0
    CHECK_ERROR (repl_is_quit_return)
    lbu t0, 0(a0)
    li t1, 81
    bne t0, t1, riq_no
    lw t6, parse_end
    addi t6, t6, -1
    bgtu a0, t6, riq_no
    lbu t0, 1(a0)
    li t1, 85
    bne t0, t1, riq_no
    li a0, 1
repl_is_quit_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
riq_no:
    li a0, 0
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
    ENTER_FRAME (32)
    sw ra, 0(sp)
    la a0, input_line
    call repl_extract_file_name
    CHECK_ERROR (rlf_done)
    lbu t0, 0(a0)
    beqz t0, rlf_err
    li a1, 0
    li a7, 1024
    ecall
    bltz a0, rlf_err
    sw a0, 4(sp)
    la a1, program_buf
    li a2, 8192
    li a7, 63
    ecall
    sw a0, 8(sp)
    lw a0, 4(sp)
    li a7, 57
    ecall
    lw t0, 8(sp)
    bltz t0, rlf_err
    li t1, 8192
    bgeu t0, t1, rlf_full
    la t1, program_buf
    add t1, t1, t0
    sb zero, 0(t1)
    # Snapshot only after a bounded file read. Restore on any import error.
    call repl_snapshot
    sw zero, repl_line_count, t0
    la a0, program_buf
    call repl_import_program_buf
    lw t0, error_code
    bnez t0, rlf_restore
    la a0, repl_load_ok
    li a7, 4
    ecall
    j rlf_done
rlf_restore:
    call repl_restore
    j rlf_done
rlf_full:
    call error_program
    j rlf_done
rlf_err:
    call error_file
rlf_done:
repl_load_file_return:
    lw ra, 0(sp)
    addi sp, sp, 32
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
    ENTER_FRAME (32)
    sw ra, 0(sp)
    la a0, input_line
    call repl_extract_file_name
    CHECK_ERROR (repl_save_file_return)
    lbu t0, 0(a0)
    beqz t0, rsf_err
    call repl_build_program
    CHECK_ERROR (repl_save_file_return)
    la a0, program_buf
    call string_length
    CHECK_ERROR (repl_save_file_return)
    sw a0, 8(sp)
    la a0, file_name
    li a1, 1
    li a7, 1024
    ecall
    bltz a0, rsf_err
    sw a0, 4(sp)
    mv a0, a0
    la a1, program_buf
    lw a2, 8(sp)
    li a7, 64
    ecall
    lw t0, 8(sp)
    bne a0, t0, rsf_close_err
    lw a0, 4(sp)
    li a7, 57
    ecall
    la a0, repl_save_ok
    li a7, 4
    ecall
    j rsf_done
rsf_close_err:
    lw a0, 4(sp)
    li a7, 57
    ecall
rsf_err:
    call error_file
rsf_done:
repl_save_file_return:
    lw ra, 0(sp)
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
compile_program:
    ENTER_FRAME (32)
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    lw a0, source_ptr
    la t0, program_buf
    li a1, 8192
    beq a0, t0, cp_bind
    la t0, focal_program
    bne a0, t0, compile_program_bad_source
    la a1, focal_program_end
    sub a1, a1, a0
cp_bind:
    call set_parse_span
    CHECK_ERROR (compile_program_return)
    mv s0, a0
cp_loop:
    mv a0, s0
    call skip_spaces_a0
    CHECK_ERROR (compile_program_return)
    mv s0, a0
    CHECK_PARSE (s0, compile_program_bad_source)
    lbu t0, 0(s0)
    beqz t0, cp_done
    la t1, parse_ptr
    sw s0, 0(t1)
    call parse_int
    CHECK_ERROR (compile_program_return)
    mv s1, a0
    la t0, parse_ptr
    lw s0, 0(t0)
    CHECK_PARSE (s0, compile_program_bad_source)
    lbu t1, 0(s0)
    li t2, 58
    bne t1, t2, cp_skip_line
    addi s0, s0, 1
    sw s0, 0(t0)
    mv a0, s1
    call add_line_table_entry
    CHECK_ERROR (compile_program_return)
    call compile_statement
    CHECK_ERROR (compile_program_return)
cp_skip_line:
    la t0, parse_ptr
    lw s0, 0(t0)
cp_advance:
    CHECK_PARSE (s0, compile_program_bad_source)
    lbu t1, 0(s0)
    beqz t1, cp_done
    li t2, 10
    beq t1, t2, cp_next
    addi s0, s0, 1
    j cp_advance
cp_next:
    addi s0, s0, 1
    j cp_loop
cp_done:
    li a0, OP_HALT
    call emit_word
    CHECK_ERROR (compile_program_return)
    j compile_program_return
compile_program_bad_source:
    call error_syntax
compile_program_return:
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw ra, 0(sp)
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
    la t3, line_offsets
    add t3, t3, t2
    sw t5, 0(t3)
    addi t1, t1, 1
    sw t1, 0(t0)
    ret
compile_statement:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_statement_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_statement_bad_source)
    lbu t2, 0(t1)
    li t3, 83
    beq t2, t3, cs_set
    li t3, 115
    beq t2, t3, cs_set
    li t3, 84
    beq t2, t3, cs_type
    li t3, 116
    beq t2, t3, cs_type
    li t3, 65
    beq t2, t3, cs_ask
    li t3, 97
    beq t2, t3, cs_ask
    li t3, 73
    beq t2, t3, cs_if
    li t3, 105
    beq t2, t3, cs_if
    li t3, 70
    beq t2, t3, cs_for
    li t3, 102
    beq t2, t3, cs_for
    li t3, 71
    beq t2, t3, cs_goto
    li t3, 103
    beq t2, t3, cs_goto
    li t3, 81
    beq t2, t3, cs_quit
    li t3, 113
    beq t2, t3, cs_quit
    li a0, ERR_SYNTAX
    la a1, err_unknown
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
cs_done:
    j compile_statement_return
compile_statement_bad_source:
    call error_syntax
compile_statement_return:
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
    call is_parse_line_end
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
    j ct_loop
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
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_if_bad_source)
    lbu t2, 0(t1)
    li t3, 84
    beq t2, t3, cif_then
    li t3, 116
    beq t2, t3, cif_then
    li t3, 71
    beq t2, t3, cif_goto
    li t3, 103
    beq t2, t3, cif_goto
    li t3, 68
    beq t2, t3, cif_do
    li t3, 100
    beq t2, t3, cif_do
    j cif_done
cif_then:
    addi t1, t1, 4
    sw t1, 0(t0)
    call skip_parse_spaces
    CHECK_ERROR (compile_if_return)
    call parse_int
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
    call parse_int
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
    call parse_int
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
compile_expr:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_expr_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_expr_bad_source)
    lbu t2, 0(t1)
    li t3, 61
    beq t2, t3, ce_eq
    li t3, 60
    beq t2, t3, ce_lt_family
    li t3, 62
    beq t2, t3, ce_gt_family
    j ce_done
ce_eq:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_EQ
    call emit_word
    CHECK_ERROR (compile_expr_return)
    j ce_done
ce_lt_family:
    addi t1, t1, 1
    CHECK_PARSE (t1, compile_expr_bad_source)
    lbu t2, 0(t1)
    li t3, 61
    beq t2, t3, ce_le
    li t3, 62
    beq t2, t3, ce_ne
    sw t1, 0(t0)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_LT
    call emit_word
    CHECK_ERROR (compile_expr_return)
    j ce_done
ce_le:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_LE
    call emit_word
    CHECK_ERROR (compile_expr_return)
    j ce_done
ce_ne:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_NE
    call emit_word
    CHECK_ERROR (compile_expr_return)
    j ce_done
ce_gt_family:
    addi t1, t1, 1
    CHECK_PARSE (t1, compile_expr_bad_source)
    lbu t2, 0(t1)
    li t3, 61
    beq t2, t3, ce_ge
    sw t1, 0(t0)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_GT
    call emit_word
    CHECK_ERROR (compile_expr_return)
    j ce_done
ce_ge:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    CHECK_ERROR (compile_expr_return)
    li a0, OP_GE
    call emit_word
    CHECK_ERROR (compile_expr_return)
ce_done:
    j compile_expr_return
compile_expr_bad_source:
    call error_syntax
compile_expr_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_additive:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call compile_term
    CHECK_ERROR (compile_additive_return)
ca_loop:
    call skip_parse_spaces
    CHECK_ERROR (compile_additive_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_additive_bad_source)
    lbu t2, 0(t1)
    li t3, 43
    beq t2, t3, ca_plus
    li t3, 45
    beq t2, t3, ca_minus
    j ca_done
ca_plus:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_term
    CHECK_ERROR (compile_additive_return)
    li a0, OP_ADD
    call emit_word
    CHECK_ERROR (compile_additive_return)
    j ca_loop
ca_minus:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_term
    CHECK_ERROR (compile_additive_return)
    li a0, OP_SUB
    call emit_word
    CHECK_ERROR (compile_additive_return)
    j ca_loop
ca_done:
    j compile_additive_return
compile_additive_bad_source:
    call error_syntax
compile_additive_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_term:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call compile_factor
    CHECK_ERROR (compile_term_return)
cterm_loop:
    call skip_parse_spaces
    CHECK_ERROR (compile_term_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_term_bad_source)
    lbu t2, 0(t1)
    li t3, 42
    beq t2, t3, cterm_mul
    li t3, 47
    beq t2, t3, cterm_div
    j cterm_done
cterm_mul:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_factor
    CHECK_ERROR (compile_term_return)
    li a0, OP_MUL
    call emit_word
    CHECK_ERROR (compile_term_return)
    j cterm_loop
cterm_div:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_factor
    CHECK_ERROR (compile_term_return)
    li a0, OP_DIV
    call emit_word
    CHECK_ERROR (compile_term_return)
    j cterm_loop
cterm_done:
    j compile_term_return
compile_term_bad_source:
    call error_syntax
compile_term_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_factor:
    ENTER_FRAME (16)
    sw ra, 0(sp)
    call skip_parse_spaces
    CHECK_ERROR (compile_factor_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_factor_bad_source)
    lbu t2, 0(t1)
    li t3, 45
    beq t2, t3, cf_neg
    li t3, 40
    beq t2, t3, cf_paren
    li t3, 48
    blt t2, t3, cf_var
    li t3, 57
    ble t2, t3, cf_number
    j cf_var
cf_neg:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_factor
    CHECK_ERROR (compile_factor_return)
    li a0, OP_NEG
    call emit_word
    CHECK_ERROR (compile_factor_return)
    j cf_done
cf_paren:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_expr
    CHECK_ERROR (compile_factor_return)
    call skip_parse_spaces
    CHECK_ERROR (compile_factor_return)
    la t0, parse_ptr
    lw t1, 0(t0)
    CHECK_PARSE (t1, compile_factor_bad_source)
    CHECK_PARSE (t1, compile_factor_bad_source)
    lbu t2, 0(t1)
    li t3, 41
    bne t2, t3, compile_factor_bad_source
    addi t1, t1, 1
    sw t1, 0(t0)
    j cf_done
cf_number:
    call parse_int
    CHECK_ERROR (compile_factor_return)
    sw a0, 4(sp)
    li a0, OP_PUSH_F
    call emit_word
    CHECK_ERROR (compile_factor_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_factor_return)
    j cf_done
cf_var:
    call parse_variable_ref
    CHECK_ERROR (compile_factor_return)
    beqz a1, cf_scalar
    sw a0, 4(sp)
    li a0, OP_PUSH_ARR
    call emit_word
    CHECK_ERROR (compile_factor_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_factor_return)
    j cf_done
cf_scalar:
    sw a0, 4(sp)
    li a0, OP_PUSH_V
    call emit_word
    CHECK_ERROR (compile_factor_return)
    lw a0, 4(sp)
    call emit_word
    CHECK_ERROR (compile_factor_return)
cf_done:
    j compile_factor_return
compile_factor_bad_source:
    call error_syntax
compile_factor_return:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
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
    li t1, OP_PUSH_F
    beq s1, t1, vm_push_f
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
    mv a0, t5
    call set_pc_absolute
    CHECK_ERROR (set_pc_to_line_return)
    j sptl_done
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
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 3
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_type:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 4
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_ask:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 3
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_if:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 2
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_for:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 3
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_goto:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 4
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_quit:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 4
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
    ret
consume_do:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 2
    CHECK_PARSE (t1, error_syntax)
    sw t1, 0(t0)
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
