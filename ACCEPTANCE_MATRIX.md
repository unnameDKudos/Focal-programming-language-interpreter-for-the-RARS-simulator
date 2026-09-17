# Матрица приёмки TZ FOCAL/RARS v1.2

Статус относится к `rars_focal_interpreter.asm` и подтверждается отдельным
manifest `tests/rars_profile/manifest.json`. Финальный runner выполняет 55/55
mandatory scenarios на RARS 1.6: 25 negative, 11 REPL/file integration,
9 historical executions из 7 уникальных литературных fixtures, mandatory
SKIP = 0. Все обычные сравнения exact.

## Функциональные требования

| ID | Кратко | Implementation evidence | Acceptance IDs | Статус / примечание |
|---|---|---|---|---|
| FR-01 | RARS 1.6 RV32 | `main`, compiler, VM в одном ASM | AP-01 | PASS; runner фиксирует Java/JAR/hash/RV32 invocation |
| FR-02 | REPL/immediate state | `repl_loop`, `repl_run_immediate`, persistent symbols | AI-01 | PASS |
| FR-03 | Stored sorted RUN | `repl_store_line`, `compile_stored_program` | AI-02, AT-LARGE | PASS |
| FR-04 | Composite numbering | `parse_program_number`, integer key `g*100+l` | AP-07, AI-02, AT-E02 | PASS; `.00` rejected |
| FR-05 | Edit/replace/delete | slot preflight, active count, `find_next_slot` | AI-02, AT-D02 | PASS |
| FR-06 | `;` и COMMENT | `compile_physical_line`, `compile_comment` | AP-01, AT-H06 | PASS |
| FR-07 | Exact operator tokens | token table/whole-token dispatch | AP-01, AT-E01 | PASS |
| FR-08 | SET | `compile_set`, symbol store wordcode | AP-01, AT-H01, AT-E05 | PASS |
| FR-09 | TYPE | `compile_type`, persistent format VM ops | AP-01, AP-05, AT-E04 | PASS |
| FR-10 | ASK list/expressions | `compile_ask`, runtime `compile_expr` evaluator | AP-06, AT-H02, AT-H03 | PASS |
| FR-11 | G/GO/GOTO | `compile_goto`, validated line transfer | AP-07, AP-11, AT-E09 | PASS |
| FR-12 | Historical sign-IF | one expression + sign branch operands | AP-08, AT-H02-N/Z/P, AT-E07/E10 | PASS |
| FR-13 | FOR profile | `OP_FOR_ENTER/NEXT`, 16-entry FOR stack | AP-09, AT-H03/H06, AT-E06/E20/E21 | PASS |
| FR-14 | DO/RETURN | `OP_DO/OP_RETURN`, DO stack, `OP_LINE_END` | AP-10, AT-H04/H05A/H05B, AT-E08/E11/E12/E19 | PASS |
| FR-15 | QUIT vs EXIT | VM QUIT aborts execution; REPL EXIT exits process | AP-01, AI-01 | PASS |
| FR-16 | WRITE selectors | shared sorted `print_source` | AI-04 | PASS |
| FR-17 | Decimal/exponent literals | checked Float32 literal parser | AP-02 | PASS |
| FR-18 | Expressions/precedence | shared expression compiler and Float32 VM | AP-02, AP-06, AP-14, AT-E03/E13 | PASS |
| FR-19 | Integer power | checked exponent + exponentiation by squaring | AP-02, AP-14, AT-E14/E15 | PASS |
| FR-20 | First two symbol chars | normalized two-byte symbol key, reserved F | AP-03, AT-H03 | PASS |
| FR-21 | Indexed variables | unified 512-entry table, RNE index | AP-03, AP-13, AT-D01, AT-E17 | PASS |
| FR-22 | Four functions | VM FABS/FSQT/FITR/FSGN | AP-04, AT-D01, AT-E16 | PASS |
| FR-23 | Environment/state | exact REPL command dispatch, reset policies | AP-11, AI-01, AT-D02, AT-LARGE | PASS |
| FR-24 | Atomic LOAD/canonical SAVE | streaming transaction/snapshot and writer | AI-03, AT-D01/D02, AI-04, AT-E22/E24/E25 | PASS |
| FR-25 | Common grammar | `compile_physical_line` shared by all sources | AP-01, AP-06, AI-03 | PASS |
| FR-26 | Literary corpus | seven unique fixture programs, nine executions/passports | AT-H01, AT-H02-N/Z/P, AT-H03, AT-H04, AT-H05A/B, AT-H06 | PASS |

## Архитектура

| ID | Кратко | Implementation evidence | Acceptance IDs | Статус / примечание |
|---|---|---|---|---|
| AR-01 | Compile inside RARS | ASM parsers emit wordcode at runtime | AP-01 | PASS |
| AR-02 | Separate stack VM | `vm_stack`/`vm_sp_ptr` separate from RISC-V `sp` | AP-01, AP-02, AP-12, AT-E18 | PASS |
| AR-03 | Line address table | `line_numbers/offsets/end_offsets` | AP-07, AP-10, AT-LARGE | PASS |
| AR-04 | Explicit control contexts | tagged DO/FOR stacks | AP-09, AP-10, AT-E19/E20 | PASS |
| AR-05 | Bounded resources | emit/fetch/slot/symbol/stack guards | AP-12/AP-13, AT-E17..E23 | PASS |
| AR-06 | Python auxiliary only | runner launches RARS and compares fixed artifacts | AP-01 | PASS; no Python FOCAL evaluator used |

## Надёжность

| ID | Кратко | Implementation evidence | Acceptance IDs | Статус / примечание |
|---|---|---|---|---|
| REL-01 | Safe error return | sticky `error_code`, VM abort, REPL reset | AI-01, AT-E01, AT-E24/E25 | PASS; no timeout/RARS exception |
| REL-02 | Code/category text | central `set_error`/`report_error` | AT-E01, AT-E24/E25 | PASS |
| REL-03 | Required errors | syntax, math, target, resource and file guards | AT-E01..AT-E25 | PASS; all exact diagnostic codes |
| REL-04 | Preserve source | compile-before-run, LOAD snapshot, non-mutating VM | AT-D02, AI-04, AT-E22/E23/E24/E25 | PASS |
| REL-05 | Fixed maxima | 128x127 storage, 512 symbols/VM, 16 DO/FOR | AP-12/AP-13, AT-LARGE, AT-E17..E22 | PASS |

## Количественные критерии

| ID | Кратко | Evidence | Acceptance IDs | Статус / примечание |
|---|---|---|---|---|
| K-01 | Все требования traced | настоящая матрица + manifest validator | AT-LARGE и вся матрица | PASS; FR 26/26, AR 6/6, REL 5/5 |
| K-02 | ≥40, 100% | runner summary 55/55, SKIP 0 | AP-01, AP-14, AT-D01 | PASS |
| K-03 | ≥6 literary programs | validator counts unique historical fixture paths | AT-H01..AT-H06 | PASS; 7 programs, 9 executions |
| K-04 | Controlled negatives | exact error/recovery corpus | AP-12, AT-E01..AT-E25 | PASS; 25/25 |
| K-05 | Current documentation | TZ, guide, architecture, ПМИ, quick check | AP-01 plus document audit | PASS |

## Historical passports и результаты

Основной источник для всех AT-H: Л. Г. Осетинский, М. Г. Осетинский,
А. Н. Писаревский, «ФОКАЛ для микро- и мини-компьютеров», 1988, глава 2.
Полные machine-readable passports находятся в manifest.

| ID | Printed / PDF page | Пример и результат | Допустимая адаптация |
|---|---|---|---|
| AT-H01 | 14 / 15 | 2.5; `3.05.02.0` | точный четырёхстрочный листинг, project TYPE rendering |
| AT-H02-N/Z/P | 42–43 / 43–44 | шестистрочный sign-IF; удвоение меньшего/сообщение равенства | русский prompt/message заменён ASCII, внешний stdin |
| AT-H03 | 48 / 49 | factorial, N=5 → `N:N-FAKTORIAL=1.2E+2` | только ASCII label и project rendering; ASK/NF/FOR алгоритм сохранён |
| AT-H04 | 51–52 / 52–53 | точный 2.36 DO line → `XAYAZA` | без изменения FOCAL source; batch wrapper завершает выполнение |
| AT-H05A | 52 / 53 | 2.37 DO group → `5.0`, `4.0`, `3.0` | canonical spelling/project rendering |
| AT-H05B | 55 / 56 | RETURN fragment → `VYHOD1 X=-1`, `VYHOD2 X= 0`, `KONEC` | только ASCII strings/project `%2`; три DO, sign-IF и RETURN сохранены |
| AT-H06 | 56 / 57 | historical bare `%`; harmonic N=4 → `S=2.0833335E+0` | только ASCII COMMENT, external stdin `4.0`, defined TYPE rendering |

H06 uses exact comparison, not tolerance. Sequential Float32 additions of
`1`, `1/2`, `1/3`, `1/4` produce bits `0x40055556`; the historical bare `%`
format renders that value as `2.0833335E+0` under the defined TYPE contract.

## Non-profile limitations

The project intentionally does not implement the exclusions in TZ §4.7:
two-dimensional arrays, DO ALL, computed control targets, historical extended
FOR scope, fractional exponent, special ASK `%`/`¤`, the complete historical
TYPE system, extra transcendental/device functions, graphics or peripherals.
Legacy integer aliases and old boolean IF/FOR-DO are isolated compatibility
paths only and are not used by normative acceptance scenarios.
