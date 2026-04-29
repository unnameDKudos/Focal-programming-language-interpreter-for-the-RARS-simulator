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
arrays:         .space 10400
line_numbers:   .space 512
line_offsets:   .space 512
repl_numbers:   .space 512
repl_texts:      .space 16384
bytecode_buf:   .space 16384
vm_stack:       .space 2048
str_pool:       .space 4096
program_buf:    .space 8192
program_buf_ptr:.word 0
input_line:     .space 256
file_name:      .space 256
zero_f:         .float 0.0
one_f:          .float 1.0
err_unknown:    .asciz "FOCAL/RARS error: unknown statement\n"
err_line:       .asciz "FOCAL/RARS error: line not found\n"
repl_banner:    .asciz "FOCAL/RARS REPL. Enter HELP for commands.\n"
repl_prompt:    .asciz "> "
repl_empty:     .asciz "No program\n"
repl_load_ok:   .asciz "Loaded\n"
repl_save_ok:   .asciz "Saved\n"
repl_file_err:  .asciz "File error\n"
repl_help_text: .asciz "Commands:\n  numbered line     add or replace program line\n  number only       delete program line\n  FOCAL command     execute immediately\n  RUN or GO         run stored program\n  LIST              show stored program\n  LOAD <file>       load program from file\n  SAVE <file>       save program to file\n  ERASE             clear stored program\n  HELP              show this help\n  QUIT              exit interpreter\nUse full file paths in RARS GUI for LOAD/SAVE.\n"
.text
.globl main
main:
    la t0, repl_enabled
    lw t1, 0(t0)
    bnez t1, rars_repl
run_embedded_program:
    call reset_runtime
    la t0, focal_program
    la t1, source_ptr
    sw t0, 0(t1)
    call compile_program
    la t0, bytecode_buf
    la t1, pc_ptr
    sw t0, 0(t1)
    call vm_run
    j program_exit
rars_repl:
    call reset_runtime
    call repl_clear_program
    la a0, repl_banner
    li a7, 4
    ecall
repl_loop:
    la a0, repl_prompt
    li a7, 4
    ecall
    la a0, input_line
    li a1, 256
    li a7, 8
    ecall
    la a0, input_line
    call normalize_repl_keyword
    la a0, input_line
    call skip_spaces_a0
    lbu t0, 0(a0)
    beqz t0, repl_loop
    li t1, 10
    beq t0, t1, repl_loop
    call repl_is_run
    bnez a0, repl_run
    la a0, input_line
    call repl_is_list
    bnez a0, repl_list
    la a0, input_line
    call repl_is_erase
    bnez a0, repl_erase
    la a0, input_line
    call repl_is_load
    bnez a0, repl_load
    la a0, input_line
    call repl_is_save
    bnez a0, repl_save
    la a0, input_line
    call repl_is_help
    bnez a0, repl_help
    la a0, input_line
    call repl_is_quit
    bnez a0, program_exit
    la a0, input_line
    call skip_spaces_a0
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
    la t0, program_buf
    lbu t1, 0(t0)
    beqz t1, repl_no_program
    call reset_runtime
    la t0, program_buf
    la t1, source_ptr
    sw t0, 0(t1)
    call compile_program
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
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s4, 4(sp)
    la s4, program_buf
    li a0, 48
    call repl_append_char_to_program
    li a0, 58
    call repl_append_char_to_program
    li a0, 32
    call repl_append_char_to_program
    la a0, input_line
    call skip_spaces_a0
rri_copy:
    lbu t0, 0(a0)
    beqz t0, rri_copy_done
    li t1, 10
    beq t0, t1, rri_copy_done
    li t1, 13
    beq t0, t1, rri_copy_done
    sb t0, 0(s4)
    addi s4, s4, 1
    addi a0, a0, 1
    j rri_copy
rri_copy_done:
    li a0, 10
    call repl_append_char_to_program
    sb zero, 0(s4)
    call reset_runtime
    la t0, program_buf
    la t1, source_ptr
    sw t0, 0(t1)
    call compile_program
    la t0, bytecode_buf
    la t1, pc_ptr
    sw t0, 0(t1)
    call vm_run
    lw ra, 0(sp)
    lw s4, 4(sp)
    addi sp, sp, 32
    ret
repl_store_line:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    call skip_spaces_a0
    la t0, parse_ptr
    sw a0, 0(t0)
    call parse_int
    mv s0, a0
    la t0, parse_ptr
    lw a0, 0(t0)
    call skip_spaces_a0
    lbu t1, 0(a0)
    li t2, 58
    bne t1, t2, rsl_no_colon
    addi a0, a0, 1
rsl_no_colon:
    call skip_spaces_a0
    mv s1, a0
    mv a0, s0
    call repl_find_line
    mv s2, a0
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
    bge s3, t1, rsl_done
    addi t2, s3, 1
    sw t2, 0(t0)
rsl_copy:
    slli t0, s3, 2
    la t1, repl_numbers
    add t1, t1, t0
    sw s0, 0(t1)
    mv a0, s3
    call repl_text_addr
    mv t0, a0
    mv t1, s1
    li t2, LINE_LEN
    addi t2, t2, -1
rsl_copy_loop:
    beqz t2, rsl_copy_done
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
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    addi sp, sp, 32
    ret
repl_find_line:
    la t0, repl_line_count
    lw t1, 0(t0)
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
    li t0, LINE_LEN
    mul t1, a0, t0
    la a0, repl_texts
    add a0, a0, t1
    ret
repl_build_program:
    addi sp, sp, -48
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    la s4, program_buf
    li s0, 0
rbp_outer:
    li s1, 0
    li s2, 100000
    la t0, repl_line_count
    lw s3, 0(t0)
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
    li a0, 58
    call repl_append_char_to_program
    li a0, 32
    call repl_append_char_to_program
    mv a0, s1
    call repl_text_addr
    call repl_append_string_to_program
    li a0, 10
    call repl_append_char_to_program
    mv s0, s2
    j rbp_outer
rbp_done:
    sb zero, 0(s4)
    la t0, program_buf_ptr
    sw s4, 0(t0)
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    addi sp, sp, 48
    ret
repl_build_listing:
    addi sp, sp, -48
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    sw s2, 12(sp)
    sw s3, 16(sp)
    sw s4, 20(sp)
    la s4, program_buf
    li s0, 0
rbl_outer:
    li s1, 0
    li s2, 100000
    la t0, repl_line_count
    lw s3, 0(t0)
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
    li a0, 32
    call repl_append_char_to_program
    mv a0, s1
    call repl_text_addr
    call repl_append_string_to_program
    li a0, 10
    call repl_append_char_to_program
    mv s0, s2
    j rbl_outer
rbl_done:
    sb zero, 0(s4)
    la t0, program_buf_ptr
    sw s4, 0(t0)
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    lw s2, 12(sp)
    lw s3, 16(sp)
    lw s4, 20(sp)
    addi sp, sp, 48
    ret
repl_append_char_to_program:
    sb a0, 0(s4)
    addi s4, s4, 1
    ret
repl_append_string_to_program:
    mv t0, a0
ras_loop:
    lbu t1, 0(t0)
    beqz t1, ras_done
    sb t1, 0(s4)
    addi s4, s4, 1
    addi t0, t0, 1
    j ras_loop
ras_done:
    ret
repl_append_int_to_program:
    addi sp, sp, -32
    sw ra, 0(sp)
    mv t0, a0
    addi t1, sp, 8
    li t2, 0
    bnez t0, rai_digits
    li t6, 48
    sb t6, 0(s4)
    addi s4, s4, 1
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
rai_emit:
    beqz t2, rai_done
    addi t1, t1, -1
    lbu t6, 0(t1)
    sb t6, 0(s4)
    addi s4, s4, 1
    addi t2, t2, -1
    j rai_emit
rai_done:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
repl_is_run:
    addi sp, sp, -16
    sw ra, 0(sp)
    la a0, input_line
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 71
    beq t0, t1, rir_go
    li t1, 82
    bne t0, t1, rir_no
    lbu t0, 1(a0)
    li t1, 85
    bne t0, t1, rir_no
    lbu t0, 2(a0)
    li t1, 78
    bne t0, t1, rir_no
rir_yes:
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rir_go:
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
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 76
    bne t0, t1, ril_no
    lbu t0, 1(a0)
    li t1, 73
    bne t0, t1, ril_no
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
ril_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_erase:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 69
    bne t0, t1, rie_no
    lbu t0, 1(a0)
    li t1, 82
    bne t0, t1, rie_no
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rie_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_load:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 76
    bne t0, t1, rild_no
    lbu t0, 1(a0)
    li t1, 79
    bne t0, t1, rild_no
    lbu t0, 2(a0)
    li t1, 65
    bne t0, t1, rild_no
    lbu t0, 3(a0)
    li t1, 68
    bne t0, t1, rild_no
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rild_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_save:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 83
    bne t0, t1, risv_no
    lbu t0, 1(a0)
    li t1, 65
    bne t0, t1, risv_no
    lbu t0, 2(a0)
    li t1, 86
    bne t0, t1, risv_no
    lbu t0, 3(a0)
    li t1, 69
    bne t0, t1, risv_no
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
risv_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_help:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 72
    bne t0, t1, rih_no
    lbu t0, 1(a0)
    li t1, 69
    bne t0, t1, rih_no
    lbu t0, 2(a0)
    li t1, 76
    bne t0, t1, rih_no
    lbu t0, 3(a0)
    li t1, 80
    bne t0, t1, rih_no
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
rih_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_is_quit:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    lbu t0, 0(a0)
    li t1, 81
    bne t0, t1, riq_no
    lbu t0, 1(a0)
    li t1, 85
    bne t0, t1, riq_no
    li a0, 1
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
riq_no:
    li a0, 0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_extract_file_name:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_spaces_a0
    addi a0, a0, 4
    call skip_spaces_a0
    la t0, file_name
    li t1, 255
refn_loop:
    beqz t1, refn_done
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
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
repl_load_file:
    addi sp, sp, -32
    sw ra, 0(sp)
    la a0, input_line
    call repl_extract_file_name
    lbu t0, 0(a0)
    beqz t0, rlf_err
    call repl_clear_program
    li a1, 0
    li a7, 1024
    ecall
    bltz a0, rlf_err
    sw a0, 4(sp)
    la a0, program_buf
    li a1, 8191
    lw a2, 4(sp)
    mv t0, a0
    mv a0, a2
    mv a2, a1
    mv a1, t0
    li a7, 63
    ecall
    bltz a0, rlf_close_err
    mv t0, a0
    la t1, program_buf
    add t1, t1, t0
    sb zero, 0(t1)
    lw a0, 4(sp)
    li a7, 57
    ecall
    la a0, program_buf
    call repl_import_program_buf
    la a0, repl_load_ok
    li a7, 4
    ecall
    j rlf_done
rlf_close_err:
    lw a0, 4(sp)
    li a7, 57
    ecall
rlf_err:
    la a0, repl_file_err
    li a7, 4
    ecall
rlf_done:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
repl_save_file:
    addi sp, sp, -32
    sw ra, 0(sp)
    la a0, input_line
    call repl_extract_file_name
    lbu t0, 0(a0)
    beqz t0, rsf_err
    call repl_build_program
    la a0, program_buf
    call string_length
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
    bltz a0, rsf_close_err
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
    la a0, repl_file_err
    li a7, 4
    ecall
rsf_done:
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
repl_import_program_buf:
    addi sp, sp, -32
    sw ra, 0(sp)
    sw s0, 4(sp)
    sw s1, 8(sp)
    mv s0, a0
rip_outer:
    lbu t0, 0(s0)
    beqz t0, rip_done
    li t1, 10
    beq t0, t1, rip_skip_nl
    li t1, 13
    beq t0, t1, rip_skip_nl
    la s1, input_line
    li t2, 255
rip_copy:
    beqz t2, rip_copy_done
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
rip_copy_done:
    sb zero, 0(s1)
    la a0, input_line
    call repl_store_line
rip_to_next:
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
    lw ra, 0(sp)
    lw s0, 4(sp)
    lw s1, 8(sp)
    addi sp, sp, 32
    ret
string_length:
    mv t0, a0
    li a0, 0
sl_loop:
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
    addi sp, sp, -16
    sw ra, 0(sp)
    la t0, source_ptr
    lw s0, 0(t0)
cp_loop:
    mv a0, s0
    call skip_spaces_a0
    mv s0, a0
    lbu t0, 0(s0)
    beqz t0, cp_done
    la t1, parse_ptr
    sw s0, 0(t1)
    call parse_int
    mv s1, a0
    la t0, parse_ptr
    lw s0, 0(t0)
    lbu t1, 0(s0)
    li t2, 58
    bne t1, t2, cp_skip_line
    addi s0, s0, 1
    sw s0, 0(t0)
    mv a0, s1
    call add_line_table_entry
    call compile_statement
cp_skip_line:
    la t0, parse_ptr
    lw s0, 0(t0)
cp_advance:
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
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
add_line_table_entry:
    la t0, line_count
    lw t1, 0(t0)
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
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    la a0, err_unknown
    li a7, 4
    ecall
    j cs_done
cs_set:
    call compile_set
    j cs_done
cs_type:
    call compile_type
    j cs_done
cs_ask:
    call compile_ask
    j cs_done
cs_if:
    call compile_if
    j cs_done
cs_for:
    call compile_for
    j cs_done
cs_goto:
    call compile_goto
    j cs_done
cs_quit:
    call consume_quit
    li a0, OP_HALT
    call emit_word
cs_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_set:
    addi sp, sp, -24
    sw ra, 0(sp)
    call consume_set
    call parse_variable_ref
    sw a0, 4(sp)
    sw a1, 8(sp)
    call skip_parse_spaces
    call consume_equal
    call compile_expr
    lw t0, 8(sp)
    lw t1, 4(sp)
    beqz t0, cset_scalar
    li a0, OP_STORE_ARR
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j cset_done
cset_scalar:
    li a0, OP_STORE_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
cset_done:
    lw ra, 0(sp)
    addi sp, sp, 24
    ret
compile_type:
    addi sp, sp, -16
    sw ra, 0(sp)
    call consume_type
ct_loop:
    call skip_parse_spaces
    call is_parse_line_end
    bnez a0, ct_done
    la t0, parse_ptr
    lw t1, 0(t0)
    lbu t2, 0(t1)
    li t3, 34
    beq t2, t3, ct_string
    li t3, 33
    beq t2, t3, ct_newline
    li t3, 44
    beq t2, t3, ct_comma
    call compile_expr
    li a0, OP_PRINT_F
    call emit_word
    j ct_loop
ct_string:
    call copy_string_to_pool
    sw a0, 4(sp)
    li a0, OP_PRINT_S
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j ct_loop
ct_newline:
    addi t1, t1, 1
    sw t1, 0(t0)
    li a0, OP_PRINT_NL
    call emit_word
    j ct_loop
ct_comma:
    addi t1, t1, 1
    sw t1, 0(t0)
    j ct_loop
ct_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_ask:
    addi sp, sp, -16
    sw ra, 0(sp)
    call consume_ask
    call parse_variable_ref
    sw a0, 4(sp)
    sw a1, 8(sp)
    call skip_parse_spaces
    call consume_comma
    call skip_parse_spaces
    call copy_string_to_pool
    sw a0, 12(sp)
    li a0, OP_PRINT_S
    call emit_word
    lw a0, 12(sp)
    call emit_word
    li a0, OP_READ_F
    call emit_word
    lw t0, 8(sp)
    lw t1, 4(sp)
    beqz t0, cask_scalar
    li a0, OP_STORE_ARR
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j cask_done
cask_scalar:
    li a0, OP_STORE_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
cask_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_if:
    addi sp, sp, -16
    sw ra, 0(sp)
    call consume_if
    call compile_expr
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    call parse_int
    sw a0, 4(sp)
    li a0, OP_JUMP_NZ
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j cif_done
cif_goto:
    call consume_goto
    call skip_parse_spaces
    call parse_int
    sw a0, 4(sp)
    li a0, OP_JUMP_NZ
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j cif_done
cif_do:
    li a0, OP_JUMP_Z_ABS
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 4(sp)
    li a0, 0
    call emit_word
    call skip_parse_spaces
    call consume_do
    call compile_statement
    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 4(sp)
    sw t1, 0(t2)
cif_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_goto:
    addi sp, sp, -16
    sw ra, 0(sp)
    call consume_goto
    call skip_parse_spaces
    call parse_int
    sw a0, 4(sp)
    li a0, OP_JUMP
    call emit_word
    lw a0, 4(sp)
    call emit_word
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_for:
    addi sp, sp, -32
    sw ra, 0(sp)
    call consume_for
    call parse_variable_ref
    sw a0, 4(sp)
    call skip_parse_spaces
    call consume_equal
    call compile_expr
    li a0, OP_STORE_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 12(sp)
    li a0, OP_PUSH_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
    call skip_parse_spaces
    call consume_comma
    call compile_expr
    li a0, OP_GT
    call emit_word
    li a0, OP_JUMP_Z_ABS
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 16(sp)
    li a0, 0
    call emit_word
    li a0, OP_JUMP_ABS
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 8(sp)
    li a0, 0
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 16(sp)
    sw t1, 0(t2)
    call skip_parse_spaces
    call consume_do
    call compile_statement
    li a0, OP_PUSH_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
    li a0, OP_PUSH_F
    call emit_word
    li a0, 1
    call emit_word
    li a0, OP_ADD
    call emit_word
    li a0, OP_STORE_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
    li a0, OP_JUMP_ABS
    call emit_word
    lw a0, 12(sp)
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 8(sp)
    sw t1, 0(t2)
    lw ra, 0(sp)
    addi sp, sp, 32
    ret
compile_expr:
    addi sp, sp, -16
    sw ra, 0(sp)
    call compile_additive
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    li a0, OP_EQ
    call emit_word
    j ce_done
ce_lt_family:
    addi t1, t1, 1
    lbu t2, 0(t1)
    li t3, 61
    beq t2, t3, ce_le
    li t3, 62
    beq t2, t3, ce_ne
    sw t1, 0(t0)
    call compile_additive
    li a0, OP_LT
    call emit_word
    j ce_done
ce_le:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    li a0, OP_LE
    call emit_word
    j ce_done
ce_ne:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    li a0, OP_NE
    call emit_word
    j ce_done
ce_gt_family:
    addi t1, t1, 1
    lbu t2, 0(t1)
    li t3, 61
    beq t2, t3, ce_ge
    sw t1, 0(t0)
    call compile_additive
    li a0, OP_GT
    call emit_word
    j ce_done
ce_ge:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_additive
    li a0, OP_GE
    call emit_word
ce_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_additive:
    addi sp, sp, -16
    sw ra, 0(sp)
    call compile_term
ca_loop:
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    li a0, OP_ADD
    call emit_word
    j ca_loop
ca_minus:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_term
    li a0, OP_SUB
    call emit_word
    j ca_loop
ca_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_term:
    addi sp, sp, -16
    sw ra, 0(sp)
    call compile_factor
cterm_loop:
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    li a0, OP_MUL
    call emit_word
    j cterm_loop
cterm_div:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_factor
    li a0, OP_DIV
    call emit_word
    j cterm_loop
cterm_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
compile_factor:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    li a0, OP_NEG
    call emit_word
    j cf_done
cf_paren:
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_expr
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)
    j cf_done
cf_number:
    call parse_int
    sw a0, 4(sp)
    li a0, OP_PUSH_F
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j cf_done
cf_var:
    call parse_variable_ref
    beqz a1, cf_scalar
    sw a0, 4(sp)
    li a0, OP_PUSH_ARR
    call emit_word
    lw a0, 4(sp)
    call emit_word
    j cf_done
cf_scalar:
    sw a0, 4(sp)
    li a0, OP_PUSH_V
    call emit_word
    lw a0, 4(sp)
    call emit_word
cf_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
parse_variable_ref:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
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
    sw t2, 4(sp)
    addi t1, t1, 1
    sw t1, 0(t0)
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
    lbu t2, 0(t1)
    li t3, 40
    bne t2, t3, pvr_scalar
    addi t1, t1, 1
    sw t1, 0(t0)
    call compile_expr
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)
    lw a0, 4(sp)
    li a1, 1
    j pvr_done
pvr_scalar:
    lw a0, 4(sp)
    li a1, 0
pvr_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
vm_run:
    addi sp, sp, -16
    sw ra, 0(sp)
vm_loop:
    la t0, pc_ptr
    lw s0, 0(t0)
    lw s1, 0(s0)
    addi s0, s0, 4
    sw s0, 0(t0)
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
    beq s1, t1, vm_add
    li t1, OP_SUB
    beq s1, t1, vm_sub
    li t1, OP_MUL
    beq s1, t1, vm_mul
    li t1, OP_DIV
    beq s1, t1, vm_div
    li t1, OP_NEG
    beq s1, t1, vm_neg
    li t1, OP_EQ
    beq s1, t1, vm_eq
    li t1, OP_NE
    beq s1, t1, vm_ne
    li t1, OP_LT
    beq s1, t1, vm_lt
    li t1, OP_LE
    beq s1, t1, vm_le
    li t1, OP_GT
    beq s1, t1, vm_gt
    li t1, OP_GE
    beq s1, t1, vm_ge
    li t1, OP_JUMP
    beq s1, t1, vm_jump
    li t1, OP_JUMP_Z
    beq s1, t1, vm_jump_z
    li t1, OP_JUMP_NZ
    beq s1, t1, vm_jump_nz
    li t1, OP_JUMP_Z_ABS
    beq s1, t1, vm_jump_z_abs
    li t1, OP_JUMP_ABS
    beq s1, t1, vm_jump_abs
    li t1, OP_PRINT_S
    beq s1, t1, vm_print_s
    li t1, OP_PRINT_F
    beq s1, t1, vm_print_f
    li t1, OP_PRINT_NL
    beq s1, t1, vm_print_nl
    li t1, OP_READ_F
    beq s1, t1, vm_read_f
    li t1, OP_HALT
    beq s1, t1, vm_halt
    j vm_loop
vm_push_f:
    call fetch_word
    fcvt.s.w ft0, a0
    call vm_push_ft0
    j vm_loop
vm_push_v:
    call fetch_word
    slli t0, a0, 2
    la t1, vars
    add t1, t1, t0
    flw ft0, 0(t1)
    call vm_push_ft0
    j vm_loop
vm_store_v:
    call fetch_word
    mv t2, a0
    call vm_pop_ft0
    slli t0, t2, 2
    la t1, vars
    add t1, t1, t0
    fsw ft0, 0(t1)
    j vm_loop
vm_push_arr:
    call fetch_word
    mv t2, a0
    call vm_pop_ft0
    fcvt.w.s t3, ft0
    call array_addr
    flw ft0, 0(a0)
    call vm_push_ft0
    j vm_loop
vm_store_arr:
    call fetch_word
    mv t2, a0
    call vm_pop_ft0
    fmv.s ft2, ft0
    call vm_pop_ft0
    fcvt.w.s t3, ft0
    call array_addr
    fsw ft2, 0(a0)
    j vm_loop
vm_add:
    call vm_pop2
    fadd.s ft0, ft1, ft0
    call vm_push_ft0
    j vm_loop
vm_sub:
    call vm_pop2
    fsub.s ft0, ft1, ft0
    call vm_push_ft0
    j vm_loop
vm_mul:
    call vm_pop2
    fmul.s ft0, ft1, ft0
    call vm_push_ft0
    j vm_loop
vm_div:
    call vm_pop2
    fdiv.s ft0, ft1, ft0
    call vm_push_ft0
    j vm_loop
vm_neg:
    call vm_pop_ft0
    fneg.s ft0, ft0
    call vm_push_ft0
    j vm_loop
vm_eq:
    call vm_pop2
    feq.s t0, ft1, ft0
    call push_bool_t0
    j vm_loop
vm_ne:
    call vm_pop2
    feq.s t0, ft1, ft0
    seqz t0, t0
    call push_bool_t0
    j vm_loop
vm_lt:
    call vm_pop2
    flt.s t0, ft1, ft0
    call push_bool_t0
    j vm_loop
vm_le:
    call vm_pop2
    fle.s t0, ft1, ft0
    call push_bool_t0
    j vm_loop
vm_gt:
    call vm_pop2
    flt.s t0, ft0, ft1
    call push_bool_t0
    j vm_loop
vm_ge:
    call vm_pop2
    fle.s t0, ft0, ft1
    call push_bool_t0
    j vm_loop
vm_jump:
    call fetch_word
    call set_pc_to_line
    j vm_loop
vm_jump_z:
    call fetch_word
    mv s2, a0
    call vm_pop_ft0
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t1, ft0, ft1
    beqz t1, vm_loop
    mv a0, s2
    call set_pc_to_line
    j vm_loop
vm_jump_nz:
    call fetch_word
    mv s2, a0
    call vm_pop_ft0
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t1, ft0, ft1
    bnez t1, vm_loop
    mv a0, s2
    call set_pc_to_line
    j vm_loop
vm_jump_z_abs:
    call fetch_word
    mv s2, a0
    call vm_pop_ft0
    la t0, zero_f
    flw ft1, 0(t0)
    feq.s t1, ft0, ft1
    beqz t1, vm_loop
    la t0, pc_ptr
    sw s2, 0(t0)
    j vm_loop
vm_jump_abs:
    call fetch_word
    la t0, pc_ptr
    sw a0, 0(t0)
    j vm_loop
vm_print_s:
    call fetch_word
    li a7, 4
    ecall
    j vm_loop
vm_print_f:
    call vm_pop_ft0
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
    j vm_loop
vm_halt:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
fetch_word:
    la t0, pc_ptr
    lw t1, 0(t0)
    lw a0, 0(t1)
    addi t1, t1, 4
    sw t1, 0(t0)
    ret
vm_push_ft0:
    la t0, vm_sp_ptr
    lw t1, 0(t0)
    fsw ft0, 0(t1)
    addi t1, t1, 4
    sw t1, 0(t0)
    ret
vm_pop_ft0:
    la t0, vm_sp_ptr
    lw t1, 0(t0)
    addi t1, t1, -4
    flw ft0, 0(t1)
    sw t1, 0(t0)
    ret
vm_pop2:
    addi sp, sp, -16
    sw ra, 0(sp)
    call vm_pop_ft0
    fmv.s ft2, ft0
    call vm_pop_ft0
    fmv.s ft1, ft0
    fmv.s ft0, ft2
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
push_bool_t0:
    addi sp, sp, -16
    sw ra, 0(sp)
    la t1, zero_f
    beqz t0, pbt_zero
    la t1, one_f
pbt_zero:
    flw ft0, 0(t1)
    call vm_push_ft0
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
array_addr:
    li t0, ARRAY_LEN
    mul t1, t2, t0
    add t1, t1, t3
    slli t1, t1, 2
    la a0, arrays
    add a0, a0, t1
    ret
set_pc_to_line:
    addi sp, sp, -16
    sw ra, 0(sp)
    mv s3, a0
    la t0, line_count
    lw t1, 0(t0)
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
    la t6, pc_ptr
    sw t5, 0(t6)
    j sptl_done
sptl_fail:
    la a0, err_line
    li a7, 4
    ecall
sptl_done:
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
emit_word:
    la t0, bc_ptr
    lw t1, 0(t0)
    sw a0, 0(t1)
    addi t1, t1, 4
    sw t1, 0(t0)
    ret
skip_parse_spaces:
    addi sp, sp, -16
    sw ra, 0(sp)
    la t0, parse_ptr
    lw a0, 0(t0)
    call skip_spaces_a0
    la t0, parse_ptr
    sw a0, 0(t0)
    lw ra, 0(sp)
    addi sp, sp, 16
    ret
skip_spaces_a0:
ssa_loop:
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
    lbu t2, 0(t1)
    li t3, 45
    bne t2, t3, pi_loop
    li t5, 1
    addi t1, t1, 1
pi_loop:
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
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    la t2, str_pool_ptr
    lw a0, 0(t2)
    mv t3, a0
cstr_loop:
    lbu t4, 0(t1)
    beqz t4, cstr_done
    li t5, 34
    beq t4, t5, cstr_quote
    sb t4, 0(t3)
    addi t3, t3, 1
    addi t1, t1, 1
    j cstr_loop
cstr_quote:
    addi t1, t1, 1
cstr_done:
    sb zero, 0(t3)
    addi t3, t3, 1
    sw t3, 0(t2)
    sw t1, 0(t0)
    ret
consume_set:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 3
    sw t1, 0(t0)
    ret
consume_type:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 4
    sw t1, 0(t0)
    ret
consume_ask:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 3
    sw t1, 0(t0)
    ret
consume_if:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 2
    sw t1, 0(t0)
    ret
consume_for:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 3
    sw t1, 0(t0)
    ret
consume_goto:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 4
    sw t1, 0(t0)
    ret
consume_quit:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 4
    sw t1, 0(t0)
    ret
consume_do:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 2
    sw t1, 0(t0)
    ret
consume_equal:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)
    ret
consume_comma:
    la t0, parse_ptr
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)
    ret
