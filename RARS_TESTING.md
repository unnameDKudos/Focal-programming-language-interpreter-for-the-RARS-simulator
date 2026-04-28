# Проверка в RARS

## Интерактивный режим

Открыть `rars_focal_interpreter.asm` в RARS, выполнить `Assemble` и `Run`.
Интерпретатор стартует в REPL:

```text
FOCAL/RARS REPL. Enter numbered lines, LOAD, SAVE, RUN, ERASE, QUIT.
> 10 SET A=2+3*4
> 20 TYPE "A = ",A,!
> 30 QUIT
> RUN
A = 14.0
```

Команды REPL:

- FOCAL-команда без номера — немедленное выполнение команды;
- `RUN` или `GO` — компиляция введенных строк в байткод и запуск VM;
- `LIST` — вывод текущего буфера программы;
- `LOAD <file>` — загрузка FOCAL-программы из файла в буфер;
- `SAVE <file>` — сохранение текущего буфера программы в файл;
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

Проверка немедленного вычисления в REPL:

```text
> TYPE 2+3*4,!
> SET A=5
> TYPE A*2,!
```

Ожидается:

```text
14.0
10.0
```

Проверка файловых команд:

```text
> ERASE
> 10 TYPE "file ok",!
> 20 QUIT
> SAVE C:\Users\Admin\Desktop\Focal simulator\saved.focal
> ERASE
> LOAD C:\Users\Admin\Desktop\Focal simulator\saved.focal
> LIST
> RUN
```

Ожидается, что `SAVE` напечатает `Saved`, `LOAD` напечатает `Loaded`, `LIST`
выведет две сохраненные строки, а `RUN` напечатает:

```text
file ok
```

В RARS GUI рекомендуется указывать полный путь. Относительный путь считается от
рабочей папки процесса Java/RARS, а не обязательно от папки проекта.

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
- `LOAD` читает файл целиком в буфер до 8191 символа;
- RARS REPL ограничен 128 строками по 127 символов.
