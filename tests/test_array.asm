.data

    .align 2
arr_A: .space 400

float_0: .float 10.0
float_1: .float 0.0
float_2: .float 20.0
float_3: .float 1.0
float_4: .float 2.0

str_0: .asciz "A(0) = "
str_1: .asciz "A(1) = "
str_2: .asciz "A(2) = "

.text
.globl main
main:
    addi sp, sp, -1024

    j line_1

line_1:
    la t0, float_0
    flw ft0, 0(t0)
    la t1, float_1
    flw ft1, 0(t1)
    fcvt.w.s t1, ft1
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    fsw ft0, 0(t0)

line_2:
    la t0, float_2
    flw ft0, 0(t0)
    la t1, float_3
    flw ft1, 0(t1)
    fcvt.w.s t1, ft1
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    fsw ft0, 0(t0)

line_3:
    la t1, float_1
    flw ft0, 0(t1)
    fcvt.w.s t1, ft0
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    flw ft0, 0(t0)
    la t1, float_3
    flw ft1, 0(t1)
    fcvt.w.s t1, ft1
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    flw ft1, 0(t0)
    fadd.s ft0, ft0, ft1
    la t1, float_4
    flw ft1, 0(t1)
    fcvt.w.s t1, ft1
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    fsw ft0, 0(t0)

line_4:
    la a0, str_0
    li a7, 4
    ecall
    la t1, float_1
    flw ft0, 0(t1)
    fcvt.w.s t1, ft0
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_5:
    la a0, str_1
    li a7, 4
    ecall
    la t1, float_3
    flw ft0, 0(t1)
    fcvt.w.s t1, ft0
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_6:
    la a0, str_2
    li a7, 4
    ecall
    la t1, float_4
    flw ft0, 0(t1)
    fcvt.w.s t1, ft0
    la t0, arr_A
    slli t1, t1, 2
    add t0, t0, t1
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_7:
    li a7, 10
    ecall
