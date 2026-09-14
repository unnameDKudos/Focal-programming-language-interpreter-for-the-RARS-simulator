# Архитектура RARS-интерпретатора FOCAL

Нормативный путь выполняется целиком в RV32-коде:

```text
FOCAL source -> compiler -> 32-bit wordcode -> stack VM
```

Python не участвует в пользовательском исполнении и не является semantic
oracle; в automated suites он только запускает RARS и проверяет результаты.

## Память и исходный текст

- `repl_numbers[128]` и `repl_texts[128][128]` — active key и 127 байт
  operator text плюс NUL; нулевой key означает свободный slot.
- `program_buf[8192]` — ограниченная служебная область legacy/import harness;
  production RUN, LIST, WRITE и SAVE от неё не зависят.
- `focal_program` — contiguous embedded/batch source.
- `line_numbers`, `line_offsets`, `line_end_offsets` — canonical key,
  смещение начала wordcode и смещение конца каждой физической строки.
- `bytecode_buf[16384]` и `str_pool[4096]` — wordcode и строковые константы.
- `symbol_table[512]` — общая таблица scalar/indexed Float32 entries.
- `vm_stack[512]`, `do_stack[16]`, `for_stack[16]` — независимые стеки VM,
  вызовов и циклов. Процедурный RISC-V `sp` имеет отдельный guard.

LOAD читает файл блоками, собирает одну physical line, валидирует и помещает её
в транзакционное storage; ошибка восстанавливает snapshot. LIST/WRITE/SAVE
обходят active slots напрямую в порядке canonical key. SAVE пишет номер `g.ll`,
пробел, неизменённый operator text и LF.

## Компиляция

Immediate source связывается с bounded `input_line`; embedded source — с
`focal_program`. Stored RUN использует `compile_stored_program` без общей
сериализации: первая фаза сортированно собирает keys и проверенные pointers на
slots, вторая связывает отдельный 128-байтный parse span, вызывает общий
`compile_physical_line`, заменяет pointer на wordcode offset и записывает
`line_end_offsets`. Поэтому полные 128 x 127 bytes доступны RUN независимо от
размера `program_buf`.

`compile_physical_line` является общей грамматической точкой для immediate,
stored/LOAD и batch. Он компилирует все statements до выполнения, обрабатывает
`;`, пустые statements и COMMENT. Late compile error не оставляет частичного
вывода/перехода. GOTO/IF/DO operands хранят canonical line key и разрешаются по
единой таблице compiled line offsets.

## Wordcode и VM

Каждый opcode и operand — 32-битное слово. Реализованы семейства:

- literals, symbol/indexed load/store, string references;
- Float32 `+`, `-`, `*`, `/`, unary sign, integer `^`;
- FABS, FSQT, FITR, FSGN;
- TYPE string/number/newline/format и runtime ASK;
- internal absolute jumps, user line transfer и sign branch;
- DO enter/return и identity-bearing `OP_LINE_END`;
- FOR enter/next with body/continuation metadata;
- WRITE selectors, QUIT и HALT.

Dispatch проверяет, что opcode и все operands выровнены и находятся в emitted
диапазоне. Internal jumps валидируют wordcode address; user line-control сначала
полностью разрешает selected target, затем атомарно вычисляет selective unwind
DO/FOR и только после этого меняет `pc`/depth.

DO context хранит return PC, canonical scope, kind и integrity tag. Natural
line/group completion обрабатывает `OP_LINE_END`, explicit RETURN снимает один
валидный context. FOR context хранит symbol key, Float32 step/limit, body/NEXT/
continuation addresses, owner DO depth и tag. Нулевой/неfinite step и 17-й
context диагностируются до небезопасной записи.

## Ошибки и lifecycle

`reset_runtime` очищает transient compiler/VM state и оба control stacks, но не
stored source, symbol table и persistent TYPE format. QUIT прекращает текущее
FOCAL execution и возвращает REPL; EXIT завершает RARS. Error code sticky в
рамках операции, а recovery начинается с чистого transient state. Все записи в
статические области предваряются bounds checks; ожидаемые ошибки печатаются как
`FOCAL/RARS error [Exx]: ...`, без RARS runtime exception.

## Использование AI при разработке

AI применялся как вспомогательный инструмент анализа требований, ревью ASM,
подготовки тестовых сценариев и документации. Предложенные изменения проверяются
автоматизированными exact-тестами целевого ASM на настоящем RARS 1.6, включая
негативные resource/safety cases и литературный corpus. Python-прототип не
используется как semantic oracle; ответственность за окончательный код,
интерпретацию ТЗ и представление результатов остаётся у автора проекта.
