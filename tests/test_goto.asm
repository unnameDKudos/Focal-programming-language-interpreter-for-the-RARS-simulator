.data
    .align 2
var_I: .float 0.0

float_0: .float 1.0
float_1: .float 5.0
float_2: .float 0.0

.text
.globl main
main:
    addi sp, sp, -1024

    j line_1

line_1:
    la t0, float_0
    flw ft0, 0(t0)
    la t0, var_I
    fsw ft0, 0(t0)

line_2:
    la t0, var_I
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_3:
    la t0, var_I
    flw ft0, 0(t0)
    la t0, float_0
    flw ft1, 0(t0)
    fadd.s ft0, ft0, ft1
    la t0, var_I
    fsw ft0, 0(t0)

line_4:
    la t0, var_I
    flw ft0, 0(t0)
    la t0, float_1
    flw ft1, 0(t0)
    fle.s t0, ft0, ft1
    fcvt.s.w ft2, t0
    la t0, float_2
    flw ft0, 0(t0)
    feq.s t0, ft2, ft0
    bnez t0, if_skip_0
    j line_2
if_skip_0:

line_5:
    li a7, 10
    ecall
