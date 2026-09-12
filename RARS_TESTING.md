# Проверка в RARS

## Интерактивный режим

Открыть `rars_focal_interpreter.asm` в RARS, выполнить `Assemble` и `Run`.
Интерпретатор стартует в REPL:

```text
FOCAL/RARS REPL. Enter HELP for commands.
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
- `HELP` — вывод справки по командам REPL;
- `QUIT` — выход.

Команды REPL можно вводить в любом регистре. Например, `help`, `load`, `save`
и `run` эквивалентны `HELP`, `LOAD`, `SAVE` и `RUN`.

Строки можно вводить в любом порядке. Повторный ввод номера заменяет строку,
строка без текста удаляет номер:

```text
> 30 QUIT
> 10 SET A=5
> 20 TYPE A,!
> LIST
10 SET A=5
20 TYPE A,!
30 QUIT
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

Из корня репозитория в PowerShell (Java должна быть доступна в PATH):

```powershell
$env:RARS_JAR = 'C:\Users\Admin\Desktop\rars1_6\rars1_6.jar'
py -3 --version
py -3 -c "import sys; print(sys.executable)"
java -version
Get-FileHash -LiteralPath $env:RARS_JAR -Algorithm SHA256
py -3 -B -m unittest discover -s tests/rars_harness -p "test_*.py" -v
py -3 -B tools/run_rars_tests.py
$LASTEXITCODE
```

Можно использовать найденный `python.exe` вместо `py -3`; команда `python`
не является обязательной. Проверенный baseline: Python 3.14.7, Java
OpenJDK 17.0.20.1, RARS 1.6 в RV32, Git `34d09ae`. SHA-256 проверенного JAR:

```text
780F730EB457B1BA609E968ACCC2C8B77D8F92C3D9DBF30CC7FDB3CFB14E8C24
```

Runner выводит путь Java, путь JAR, его SHA-256, идентификатор известной
сборки RARS и Git HEAD. Неизвестный hash явно отмечается, версия по нему
не угадывается. Git нужен только для метаданных; интернет не используется.

Это семь **legacy baseline** тестов: `array_sum`, `for_sum`, `goto`, `hello`,
`if`, `operators`, `sort`. Их expected-файлы исторически проверялись как
подстроки, поэтому runner явно выбирает `legacy-substring`: после
нормализации LF/CRLF применяется прежнее сравнение
`expected.strip() in stdout.strip()`. Оно допускает дополнительный вывод
программы и не доказывает полную корректность языка. Файлы ожиданий не изменены.

В `tools/rars_test_support.py` отдельно предусмотрен режим `exact` (по
умолчанию): сравнение полного stdout, с нормализацией только LF/CRLF, без
удаления пробелов или последнего перевода строки. Будущие нормативные тесты
не должны неявно наследовать legacy-режим. Self-tests драйвера не входят в
40 языковых сценариев ТЗ.

Команда дочернего процесса: `java -jar <jar> nc me ae2 se3 <temporary.asm>`.
`me` отделяет сообщения RARS в stderr; `ae2` и `se3` задают ненулевые коды
ошибок ассемблирования и симуляции. Режим RV64 не включается. Только штатное
сообщение `Program terminated by calling exit` и пустые строки stderr
считаются нормальным завершением. Остальные диагностики не скрываются,
даже если stdout содержит ожидаемую подстроку.

Категории отказов: `ENVIRONMENT`, `FIXTURE`, `BUILD`, `ASSEMBLY`,
`SIMULATION`, `TIMEOUT`, `RARS_DIAGNOSTIC`, `MISMATCH`. Timeout одного
запуска — 30 секунд; его частичный вывод сохраняется в отчёте. Ошибка одного
сценария не мешает проверке остальных, если продолжение возможно.

Временные копии ASM создаются в собственном системном `TemporaryDirectory`
и удаляются после прогона. Исходник и fixtures не перезаписываются;
заранее существующий `.rars_test_build` не используется и не удаляется.
Runner работает в batch-режиме, без REPL и ввода ASK.

Успешный результат:

```text
Passed: 7
Failed: 0
```

Код завершения: 0 только при успехе всех семи тестов, 1 при отказах
сценариев, 2 при общей ошибке окружения. Отсутствующий `RARS_JAR` — ошибка,
не SKIP. При невозможности начать прогон счётчики равны 0/0, явно указано,
что тесты не выполнялись, и возвращается код 2.

## Ограничения

- числовые литералы в RARS-исходнике пока целые;
- значения внутри VM, `ASK` и `TYPE` чисел используют float;
- `FOR` поддерживает только шаг `+1`;
- `LOAD` читает файл целиком в буфер до 8191 символа;
- RARS REPL ограничен 128 строками по 127 символов.
