# Интерпретатор FOCAL (RV32, RARS): исходник -> байткод -> стековая ВМ.
# Литералы в тексте: целые; в ВМ — float, ввод-вывод через ecall.

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
.eqv ARRAY_LEN     100

.data
    .align 2

# Программа (подмена через embed_rars_demo.py или вручную).
focal_program:
    .asciz "1: SET A=2+3*4\n2: SET B=(2+3)*4\n3: TYPE \"A = \",A,!\n4: TYPE \"B = \",B,!\n5: IF A<B THEN 7\n6: TYPE \"bad\",!\n7: TYPE \"ok\",!\n8: QUIT\n"

parse_ptr:      .word 0
source_ptr:     .word 0
bc_ptr:         .word 0
pc_ptr:         .word 0
vm_sp_ptr:      .word 0
str_pool_ptr:   .word 0
line_count:     .word 0

vars:           .space 104              # 26 float variables
arrays:         .space 10400            # 26 * 100 * 4
line_numbers:   .space 512              # MAX_LINES * 4
line_offsets:   .space 512              # MAX_LINES * 4, absolute bytecode addr
bytecode_buf:   .space 16384
vm_stack:       .space 2048
str_pool:       .space 4096

zero_f:         .float 0.0
one_f:          .float 1.0
err_unknown:    .asciz "FOCAL/RARS error: unknown statement\n"
err_line:       .asciz "FOCAL/RARS error: line not found\n"

.text
.globl main
main:
    la t0, bytecode_buf
    la t1, bc_ptr
    sw t0, 0(t1)
    la t0, str_pool
    la t1, str_pool_ptr
    sw t0, 0(t1)
    la t0, vm_stack
    la t1, vm_sp_ptr
    sw t0, 0(t1)
    la t0, focal_program
    la t1, source_ptr
    sw t0, 0(t1)

    call compile_program
    la t0, bytecode_buf
    la t1, pc_ptr
    sw t0, 0(t1)
    call vm_run

program_exit:
    li a7, 10
    ecall

# --- компиляция в байткод, таблица номеров строк

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
    mv s1, a0                       # line number

    la t0, parse_ptr
    lw s0, 0(t0)
    lbu t1, 0(s0)
    li t2, 58                        # ':'
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

    li t3, 83                        # S -> SET
    beq t2, t3, cs_set
    li t3, 84                        # T -> TYPE / THEN not top-level
    beq t2, t3, cs_type
    li t3, 65                        # A -> ASK
    beq t2, t3, cs_ask
    li t3, 73                        # I -> IF
    beq t2, t3, cs_if
    li t3, 70                        # F -> FOR
    beq t2, t3, cs_for
    li t3, 71                        # G -> GOTO
    beq t2, t3, cs_goto
    li t3, 81                        # Q -> QUIT
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
    sw a0, 4(sp)                     # var id
    sw a1, 8(sp)                     # 0 scalar, 1 array; index code already emitted

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
    li t3, 34                        # '"'
    beq t2, t3, ct_string
    li t3, 33                        # '!'
    beq t2, t3, ct_newline
    li t3, 44                        # ','
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
    li t3, 84                        # THEN
    beq t2, t3, cif_then
    li t3, 71                        # GOTO
    beq t2, t3, cif_goto
    li t3, 68                        # DO
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
    sw a0, 4(sp)                     # loop variable id
    call skip_parse_spaces
    call consume_equal
    call compile_expr                # start
    li a0, OP_STORE_V
    call emit_word
    lw a0, 4(sp)
    call emit_word

    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 12(sp)                    # loop start absolute offset

    li a0, OP_PUSH_V
    call emit_word
    lw a0, 4(sp)
    call emit_word

    call skip_parse_spaces
    call consume_comma
    call compile_expr                # end
    li a0, OP_GT
    call emit_word

    # If i>end, exit. Otherwise skip the exit jump and execute the body.
    li a0, OP_JUMP_Z_ABS
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 16(sp)                    # skip-exit placeholder
    li a0, 0
    call emit_word
    li a0, OP_JUMP_ABS
    call emit_word
    la t0, bc_ptr
    lw t1, 0(t0)
    sw t1, 8(sp)                     # loop-end placeholder
    li a0, 0
    call emit_word

    la t0, bc_ptr
    lw t1, 0(t0)
    lw t2, 16(sp)
    sw t1, 0(t2)                     # skip exit points to body

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

# --- выражения (код на стек)

compile_expr:
    addi sp, sp, -16
    sw ra, 0(sp)
    call compile_additive
    call skip_parse_spaces

    la t0, parse_ptr
    lw t1, 0(t0)
    lbu t2, 0(t1)
    li t3, 61                        # =
    beq t2, t3, ce_eq
    li t3, 60                        # <, <=, <>
    beq t2, t3, ce_lt_family
    li t3, 62                        # >, >=
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
    li t3, 43                        # +
    beq t2, t3, ca_plus
    li t3, 45                        # -
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
    li t3, 42                        # *
    beq t2, t3, cterm_mul
    li t3, 47                        # /
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

    li t3, 45                        # unary -
    beq t2, t3, cf_neg
    li t3, 40                        # (
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
    addi t1, t1, 1                   # consume ')'
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

# Returns a0=var id, a1=0 scalar / 1 array. If array, index expression is
# compiled before returning.
parse_variable_ref:
    addi sp, sp, -16
    sw ra, 0(sp)
    call skip_parse_spaces
    la t0, parse_ptr
    lw t1, 0(t0)
    lbu t2, 0(t1)
    addi t2, t2, -65
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
    addi t1, t1, 1                   # consume ')'
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

# --- исполнение байткода

vm_run:
    addi sp, sp, -16
    sw ra, 0(sp)
vm_loop:
    la t0, pc_ptr
    lw s0, 0(t0)
    lw s1, 0(s0)                     # opcode
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
    call vm_pop_ft0                    # index
    fcvt.w.s t3, ft0
    call array_addr
    flw ft0, 0(a0)
    call vm_push_ft0
    j vm_loop
vm_store_arr:
    call fetch_word
    mv t2, a0
    call vm_pop_ft0                    # value
    fmv.s ft2, ft0
    call vm_pop_ft0                    # index
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
    # input: t2 var id, t3 index
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

# --- emit, пропуск пробелов

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
    addi t1, t1, 1                   # opening quote
    la t2, str_pool_ptr
    lw a0, 0(t2)                      # result address
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
