# Генерация RISC-V кода

`compile_to_riscv.py` — вспомогательный инструмент проекта. Он переводит FOCAL
программу в самостоятельный RISC-V asm-файл для RARS.

Важно: это не заменяет целевой интерпретатор. Целевой результат находится в
`rars_focal_interpreter.asm`, где FOCAL выполняется внутри RARS через байткод и
VM.

## Использование

```bash
python compile_to_riscv.py tests/test_operators.focal tests/test_operators.asm
```

## Роль инструмента

- проверка Python-фронтенда;
- быстрые самостоятельные RARS-демо;
- источник решений для переноса конструкций в asm-интерпретатор.

## Ограничения

- генератор и RARS-интерпретатор — разные execution paths;
- тест `run_tests.py` проверяет построение asm, но не заменяет RARS REPL/VM.
