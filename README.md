# Интерпретатор FOCAL для RARS

Интерпретатор подмножества языка **FOCAL** для симулятора RARS (RISC-V, 32 бита). FOCAL-программа компилируется в байткод и выполняется стековой виртуальной машиной; исходник задаётся в буфере `focal_program` в файле `rars_focal_interpreter.asm`.

Параллельно в репозитории есть **прототип на Python** (`focal_interpreter/`): лексер, парсер, исполнение программ и скрипт `compile_to_riscv.py`, который строит отдельные RISC-V программы (обход «через один asm-файл», без встроенного интерпретатора в RARS).

## Структура

| Путь | Назначение |
|------|------------|
| `focal_interpreter/` | лексер, парсер, интерпретатор, генерация asm, точка входа `main` |
| `rars_focal_interpreter.asm` | интерпретатор FOCAL под RARS |
| `compile_to_riscv.py` | FOCAL → отдельный `.asm` |
| `run_tests.py` | прогон тестов |
| `tests/` | тесты `.focal` (и сгенерированные `.asm`) |
| `demo/rars/` | примеры для RARS, рядом ожидаемый вывод `*.expected.txt` |
| `tools/` | вспомогательные скрипты (встраивание демо, опциональный запуск RARS) |

## Быстрый старт

**Python** — запуск теста и REPL:

```bash
python -m focal_interpreter.main tests/test_hello.focal
python -m focal_interpreter.main
python run_tests.py
```

**RARS** — открыть `rars_focal_interpreter.asm`, `Assemble`, `Run`. По умолчанию
стартует REPL:

```text
> 10 SET A=2+3*4
> 20 TYPE "A = ",A,!
> 30 QUIT
> RUN
A = 14.0
```

Строки в RARS REPL можно вводить в любом порядке; повторный ввод номера заменяет
строку, пустая строка с номером удаляет ее. `LIST` и `RUN` работают по
возрастанию номеров.

Собрать отдельный asm с встроенной программой из `demo/rars/`:

```bash
python tools/embed_rars_demo.py demo/rars/hello.focal -o demo/rars/hello.asm
```

Полная схема запуска, демо и деталей — в сопутствующей документации к проекту.

Основные документы:

- `RARS_QUICK_CHECK.md` — короткая инструкция для ручной проверки в RARS.
- `FOCAL_USER_GUIDE.md` — синтаксис FOCAL, Python REPL, RARS REPL.
- `RARS_TESTING.md` — ручная и автоматическая проверка в RARS.
- `VM_ARCHITECTURE.md` — устройство байткода, VM и памяти.
- `CODE_GENERATION.md` — роль вспомогательного Python-генератора asm.
