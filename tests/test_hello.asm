.data

str_0: .asciz "Hello, World!"

.text
.globl main
main:
    addi sp, sp, -1024

    j line_1

line_1:
    la a0, str_0
    li a7, 4
    ecall
    li a0, 10
    li a7, 11
    ecall

line_2:
    li a7, 10
    ecall
