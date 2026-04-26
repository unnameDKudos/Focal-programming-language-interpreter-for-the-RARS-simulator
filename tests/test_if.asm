.data
    .align 2
var_A: .float 0.0
    .align 2
var_B: .float 0.0

float_0: .float 10.0
float_1: .float 5.0
float_2: .float 0.0

str_0: .asciz "A is greater"
str_1: .asciz "A is less"
str_2: .asciz "A equals B"

.text
.globl main
main:
    addi sp, sp, -1024

    j line_1

line_1:
    la t0, float_0
    flw ft0, 0(t0)
    la t0, var_A
    fsw ft0, 0(t0)

line_2:
    la t0, float_1
    flw ft0, 0(t0)
    la t0, var_B
    fsw ft0, 0(t0)

line_3:
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    flt.s t0, ft1, ft0
    fcvt.s.w ft2, t0
    la t0, float_2
    flw ft0, 0(t0)
    feq.s t0, ft2, ft0
    bnez t0, if_skip_0
    la a0, str_0
    li a7, 4
    ecall
    li a0, 10
    li a7, 11
    ecall
if_skip_0:

line_4:
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    flt.s t0, ft0, ft1
    fcvt.s.w ft2, t0
    la t0, float_2
    flw ft0, 0(t0)
    feq.s t0, ft2, ft0
    bnez t0, if_skip_1
    la a0, str_1
    li a7, 4
    ecall
    li a0, 10
    li a7, 11
    ecall
if_skip_1:

line_5:
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    feq.s t0, ft0, ft1
    fcvt.s.w ft2, t0
    la t0, float_2
    flw ft0, 0(t0)
    feq.s t0, ft2, ft0
    bnez t0, if_skip_2
    la a0, str_2
    li a7, 4
    ecall
    li a0, 10
    li a7, 11
    ecall
if_skip_2:

line_6:
    li a7, 10
    ecall
