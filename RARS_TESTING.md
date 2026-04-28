# Проверка в RARS

## Интерактивный режим

Открыть `rars_focal_interpreter.asm` в RARS, выполнить `Assemble` и `Run`.
Интерпретатор стартует в REPL:

```text
FOCAL/RARS REPL. Enter numbered lines, RUN, ERASE, QUIT.
> 10 SET A=2+3*4
> 20 TYPE "A = ",A,!
> 30 QUIT
> RUN
A = 14.0
```

Команды REPL:

- `RUN` или `GO` — компиляция введенных строк в байткод и запуск VM;
- `LIST` — вывод текущего буфера программы;
- `ERASE` — очистка буфера;
- `QUIT` — выход.

Строки можно вводить в любом порядке. Повторный ввод номера заменяет строку,
строка без текста удаляет номер:

```text
> 30 QUIT
> 10 SET A=5
> 20 TYPE A,!
> LIST
10: SET A=5
20: TYPE A,!
30: QUIT
> RUN
5.0
```

## Демо-программы

Демо лежат в `demo/rars/`; рядом с каждой программой есть `*.expected.txt`.

Создать отдельный asm с демо:

```bash
python tools/embed_rars_demo.py demo/rars/operators.focal -o demo/rars/operators.asm
```

Затем открыть `demo/rars/operators.asm` в RARS и выполнить `Assemble`/`Run`.

## Автоматический запуск RARS

Если есть `rars.jar`, можно запустить интеграционные проверки:

```bash
set RARS_JAR=C:\path\to\rars.jar
python tools/run_rars_tests.py
```

Если `RARS_JAR` не задан, скрипт завершится со статусом skip.

## Ограничения

- числовые литералы в RARS-исходнике пока целые;
- значения внутри VM, `ASK` и `TYPE` чисел используют float;
- `FOR` поддерживает только шаг `+1`;
- RARS REPL ограничен 128 строками по 127 символов.
