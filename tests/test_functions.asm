.data
    .align 2
var_W: .float 0.0
    .align 2
var_X: .float 0.0
    .align 2
var_Y: .float 0.0
    .align 2
var_Z: .float 0.0

float_0: .float 16.0
float_1: .float 0.0
float_2: .float 0.16666667
float_3: .float 0.008333333
float_4: .float 0.0001984127
float_5: .float 0.5
float_6: .float 0.041666667
float_7: .float 0.0013888889
float_8: .float 1.0

str_0: .asciz "Square root of "
str_1: .asciz " = "
str_2: .asciz "Sin(0) = "
str_3: .asciz "Cos(0) = "

.text
.globl main
main:
    addi sp, sp, -1024

    j line_1

line_1:
    la t0, float_0
    flw ft0, 0(t0)
    la t0, var_X
    fsw ft0, 0(t0)

line_2:
    la t0, var_X
    flw ft1, 0(t0)
    fsqrt.s ft0, ft1
    la t0, var_Y
    fsw ft0, 0(t0)

line_3:
    la a0, str_0
    li a7, 4
    ecall
    la t0, var_X
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    la a0, str_1
    li a7, 4
    ecall
    la t0, var_Y
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_4:
    la t0, float_1
    flw ft1, 0(t0)
    fmv.s fa0, ft1
    jal ra, _focal_fsin
    fmv.s ft0, fa0
    la t0, var_Z
    fsw ft0, 0(t0)

line_5:
    la a0, str_2
    li a7, 4
    ecall
    la t0, var_Z
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_6:
    la t0, float_1
    flw ft1, 0(t0)
    fmv.s fa0, ft1
    jal ra, _focal_fcos
    fmv.s ft0, fa0
    la t0, var_W
    fsw ft0, 0(t0)

line_7:
    la a0, str_3
    li a7, 4
    ecall
    la t0, var_W
    flw ft0, 0(t0)
    fmv.s fa0, ft0
    li a7, 2
    ecall
    li a0, 10
    li a7, 11
    ecall

line_8:
    li a7, 10
    ecall


_focal_fsin:
    fmv.s ft0, fa0
    fmul.s ft1, ft0, ft0
    fmul.s ft2, ft1, ft0
    fmul.s ft3, ft2, ft1
    fmul.s ft4, ft3, ft1
    la t0, float_2
    flw ft5, 0(t0)
    fmul.s ft2, ft2, ft5
    la t0, float_3
    flw ft5, 0(t0)
    fmul.s ft3, ft3, ft5
    la t0, float_4
    flw ft5, 0(t0)
    fmul.s ft4, ft4, ft5
    fsub.s ft0, ft0, ft2
    fadd.s ft0, ft0, ft3
    fsub.s ft0, ft0, ft4
    fmv.s fa0, ft0
    ret
_focal_fcos:
    fmv.s ft0, fa0
    fmul.s ft1, ft0, ft0
    fmul.s ft2, ft1, ft1
    fmul.s ft3, ft2, ft1
    la t0, float_8
    flw ft4, 0(t0)
    la t0, float_5
    flw ft5, 0(t0)
    fmul.s ft1, ft1, ft5
    la t0, float_6
    flw ft5, 0(t0)
    fmul.s ft2, ft2, ft5
    la t0, float_7
    flw ft5, 0(t0)
    fmul.s ft3, ft3, ft5
    fsub.s ft4, ft4, ft1
    fadd.s ft4, ft4, ft2
    fsub.s ft4, ft4, ft3
    fmv.s fa0, ft4
    ret