.data
    .align 2
var_F: .float 0.0
    .align 2
var_I: .float 0.0
    .align 2
var_N: .float 0.0

float_0: .float 1.0
float_1: .float 0.0

str_0: .asciz "Enter number: "
str_1: .asciz "Factorial = "

.text
.globl main
main:
    addi sp, sp, -1024

    j line_1

line_1:
    la a0, str_0
    li a7, 4
    ecall
    li a7, 6
    ecall
    la t0, var_N
    fsw fa0, 0(t0)

line_2:
    la t0, float_0
    flw ft0, 0(t0)
    la t0, var_F
    fsw ft0, 0(t0)

line_3:
    la t0, float_0
    flw ft0, 0(t0)
    la t0, var_N
    flw ft1, 0(t0)
    la t0, float_0
    flw ft2, 0(t0)
    la t0, var_I
    fsw ft0, 0(t0)
    addi sp, sp, -12
    fsw ft1, 0(sp)
    fsw ft2, 4(sp)
    sw t0, 8(sp)
for_loop_0:
    lw t0, 8(sp)
    flw ft0, 0(t0)
    flw ft1, 0(sp)
    flw ft2, 4(sp)
    la t1, float_1
    flw ft3, 0(t1)
    flt.s t1, ft2, ft3
    bnez t1, for_neg_2
    flt.s t1, ft1, ft0
    bnez t1, for_end_1
    j for_check_3
for_neg_2:
    flt.s t1, ft0, ft1
    bnez t1, for_end_1
for_check_3:
    la t0, var_F
    flw ft0, 0(t0)
    la t0, var_I
    flw ft1, 0(t0)
    fmul.s ft0, ft0, ft1
    la t0, var_F
    fsw ft0, 0(t0)
    lw t0, 8(sp)
    flw ft0, 0(t0)
    flw ft1, 4(sp)
    fadd.s ft0, ft0, ft1
    fsw ft0, 0(t0)
    j for_loop_0
for_end_1:
    addi sp, sp, 12

line_4:
    la a0, str_1
    li a7, 4
    ecall
    la t0, var_F
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_5:
    li a7, 10
    ecall
