.data
    .align 2
var_A: .float 0.0
    .align 2
var_B: .float 0.0

float_0: .float 10.0
float_1: .float 5.0
float_2: .float 2.0
float_3: .float 1.0

str_0: .asciz "A = "
str_1: .asciz "B = "
str_2: .asciz "A + B = "
str_3: .asciz "A - B = "
str_4: .asciz "A * B = "
str_5: .asciz "A / B = "
str_6: .asciz "A ^ 2 = "

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
    la a0, str_0
    li a7, 4
    ecall
    la t0, var_A
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_4:
    la a0, str_1
    li a7, 4
    ecall
    la t0, var_B
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_5:
    la a0, str_2
    li a7, 4
    ecall
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    fadd.s ft0, ft0, ft1
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_6:
    la a0, str_3
    li a7, 4
    ecall
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    fsub.s ft0, ft0, ft1
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_7:
    la a0, str_4
    li a7, 4
    ecall
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    fmul.s ft0, ft0, ft1
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_8:
    la a0, str_5
    li a7, 4
    ecall
    la t0, var_A
    flw ft0, 0(t0)
    la t0, var_B
    flw ft1, 0(t0)
    fdiv.s ft0, ft0, ft1
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_9:
    la a0, str_6
    li a7, 4
    ecall
    la t0, var_A
    flw ft0, 0(t0)
    la t0, float_2
    flw ft1, 0(t0)
    fcvt.w.s t0, ft1
    fmv.s ft2, ft0
    la t1, float_3
    flw ft0, 0(t1)
    blez t0, pow_end_1
pow_loop_0:
    fmul.s ft0, ft0, ft2
    addi t0, t0, -1
    bnez t0, pow_loop_0
pow_end_1:
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_10:
    li a7, 10
    ecall
