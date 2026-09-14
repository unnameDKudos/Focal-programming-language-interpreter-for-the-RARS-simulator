# Проверка в RARS

## Интерактивный режим

Открыть `rars_focal_interpreter.asm` в RARS, выполнить `Assemble` и `Run`.
Интерпретатор стартует в REPL:

```text
FOCAL/RARS REPL. Enter HELP for commands.
> 1.10 SET A=2+3*4
> 1.20 TYPE "A = ",A,!
> 1.30 QUIT
> RUN
A = 14.0
```

Команды REPL:

- FOCAL-команда без номера — немедленное выполнение команды;
- `RUN` — команда среды: компиляция хранимых строк и запуск VM;
- `G` / `GO` / `GOTO [g.ll]` — FOCAL-переход: без цели передаёт управление
  первой хранимой строке, с целью — указанной composite-строке;
- `LIST` — вывод текущего буфера программы;
- `WRITE` / `W` — просмотр всего исходника; `ALL`, группа или номер строки
  выбирают весь исходник, группу или одну строку соответственно;
- `LOAD <file>` — загрузка FOCAL-программы из файла в буфер;
- `SAVE <file>` — сохранение текущего буфера программы в файл;
- `ERASE` — очистка программы, переменных (включая массивы) и runtime state;
- `HELP` — вывод справки по командам REPL;
- `QUIT` / `Q` — завершение текущего FOCAL-выполнения, возврат в REPL;
- `EXIT` — завершение процесса RARS.

Команды REPL можно вводить в любом регистре. Например, `help`, `load`, `save`
и `run` эквивалентны `HELP`, `LOAD`, `SAVE` и `RUN`.

Проверяется полный токен: `RUNNER`, `LISTING`, `SOMETHING`, `SE`, `TYP`
не являются сокращениями. Ключевые слова сравниваются без учета регистра,
но хранимый исходник и строковые литералы не переписываются. Допустимые имена:
SET/S, TYPE/T, ASK/A, GOTO/G/GO, IF/I, FOR/F, DO/D, RETURN/R, QUIT/Q, COMMENT/C,
WRITE/W. `DO/D group` вызывает отсортированную группу, `DO/D g.ll` — одну
физическую строку; `RETURN/R` досрочно завершает верхний вызов, а нормальный
конец вызванной строки/группы возвращает управление автоматически. Нормативный
`IF/I` является sign-IF; прежний внутристрочный DO доступен только в явно
отделённой непарентезированной compatibility-грамматике IF/FOR.
RUN, LIST, LOAD, SAVE и immediate execution сами по себе не очищают переменные.

Строки можно вводить в любом порядке. Повторный ввод номера заменяет строку,
строка без текста удаляет номер:

```text
> 1.30 QUIT
> 1.10 SET A=5
> 1.20 TYPE A,!
> LIST
1.10 SET A=5
1.20 TYPE A,!
1.30 QUIT
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
> 1.10 TYPE "file ok",!
> 1.20 QUIT
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

## Low-level safety suite (этап 2)

Отдельный прогон в том же окружении, из корня репозитория:

```powershell
$env:RARS_JAR = 'C:\Users\Admin\Desktop\rars1_6\rars1_6.jar'
py -3 -B -m unittest discover -s tests/rars_safety -p "test_*.py" -v
$LASTEXITCODE
```

Успех: `Ran 15 tests`, `OK`, код 0. Это 91 реальный запуск RARS:
69 низкоуровневых subtests, один ABI harness, 16 batch/REPL-сценариев и пять
ASK nested-evaluator harness-сценариев.
Harness добавляет только входную точку и тестовые данные во временную копию
целевого ASM и вызывает его процедуры. Python не реализует семантику FOCAL
и не является нормативным oracle. Эти проверки ресурсов не засчитываются
автоматически в нормативный минимум 40 языковых сценариев.

Проверяются границы wordcode (emit/fetch/patch/jump), 512-элементного VM-стека
(включая атомарный pop2), строкового пула, program_buf, input_line, 128 записей
таблиц/REPL slots, единой symbol table, сохранение sp и s0–s11,
sticky-ошибка, сброс временного состояния и восстановление REPL.
Проверены отказ при слишком глубокой компиляции и сохранение исходных строк
после ошибок RUN/LOAD; значения уже присвоенных переменных не откатываются.

Все сравнения здесь `exact`. Для REPL runner получает `stdin_text`; без него
сохраняется прежний `stdin=DEVNULL`. Ошибки ассемблирования/симуляции,
неожиданный stderr и timeout остаются отказами. Файлы LOAD/SAVE создаются
только во временном каталоге конкретного теста. Окружение не устанавливается
и отсутствие Java/JAR не превращается в SKIP.

Основные пользовательские лимиты сохранены: wordcode 16384 байта, VM 2048 байт,
str_pool 4096 байт, program_buf 8192 байта (включая NUL), input_line/file_name
и блок файлового ввода по 256 байт, REPL slots по 128 байт. Отдельный лимит
процедурного sp — 64 КиБ
от выровненного стартового sp; он не относится к вычислительному стеку VM.
Для сохранности исходника при ошибке существующего LOAD добавлена фиксированная
резервная копия REPL storage; это не расширяет пользовательскую вместимость.

## Токены и lifecycle REPL (этап 3)

В настроенном окружении с `RARS_JAR`, из корня репозитория:

```powershell
py -3 -B -m unittest discover -s tests/rars_repl -p "test_*.py" -v
```

Все сценарии — end-to-end через настоящий RARS, с полным `exact`-сравнением
stdout и прежней строгой проверкой stderr/exit code. Проверяются точные имена
и сокращения, недопустимые префиксы, разделение environment/FOCAL dispatch,
QUIT/Q и EXIT, ERASE, сохранность переменных и регистра исходника, HELP,
а также токены в stored/LOAD и старых конструкциях IF/FOR. Python — только
драйвер, не нормативный интерпретатор. Семантика будущих DO/RETURN
этими тестами не утверждается.

Для safety suite этапа 2 адаптирован только teardown: последний отдельный
`QUIT` во входе сеанса заменяется на `EXIT`. Это следствие нового FR-15/23;
FOCAL QUIT внутри программ и проверки безопасности сохранены. На этапе 4
точечно обновлены ожидаемые номера в LIST и canonical key в ABI harness.
Не завершайте автоматический REPL-сеанс одним QUIT: он больше не закрывает
процесс; конец stdin сам по себе также не служит командой выхода.

## Номера, storage и просмотр (этап 4)

```powershell
py -3 -B -m unittest discover -s tests/rars_storage -p "test_*.py" -v
```

Нормативные номера: `01.01`–`99.99`, без `xx.00`; ведущий ноль группы
не обязателен. Один знак после точки означает десятки: `2.1` = `2.10`,
но `2.01` — другая строка. Используется целый ключ `group*100+line`, не float.
LIST/WRITE выводят `g.ll`, один пробел и исходный операторный текст.
Входное двоеточие после номера допустимо, но в вывод не попадает.

Хранилище — 128 несортированных физических slots. Нулевой ключ означает
свободный slot; счётчик отражает активные строки. Замена не увеличивает
счётчик, удаление уменьшает его, освобождённые slots используются повторно.
Максимум операторного текста — 127 байт плюс NUL; отказ происходит до замены.

LIST и WRITE используют общий отсортированный обход и formatter. Вывод
потоковый: все 128 максимальных строк доступны для просмотра независимо от
8-КиБ program_buf. Поддерживаются WRITE/W, WRITE/W ALL, WRITE/W g,
WRITE/W g.ll, включая WRITE внутри исполняемой программы. Отсутствующая
группа/строка — контролируемая ошибка; пустой просмотр ALL ничего не печатает.

RUN использует тот же обход и formatter, но пока сохраняет ограниченный
program_buf. Компилятор batch/embedded также разбирает канонические ключи,
учитывает замену/удаление и упорядочивает строки до генерации wordcode.
В line_numbers лежат канонические ключи; после успешной компиляции
line_offsets содержит соответствующие байтовые смещения от bytecode_buf.
До завершения первой фазы эта таблица временно содержит указатели
на исходные операторы; VM допускается запускать только после проверки ошибки.

Migration path для старых fixtures: целый номер N от 1 до 9801 временно
принимается как порядковый номер среди 99 строк каждой группы:
`1 -> 1.01`, `99 -> 1.99`, `100 -> 2.01`. То же преобразование используется
для старых числовых целей GOTO/IF; fixtures demo/rars не переписаны.
Это совместимость, не нормативная integer-only модель. В WRITE целое число
всегда означает группу, а не legacy-номер строки.

Новый suite использует только exact output настоящего RARS; дополнительный
ASM harness проверяет ключи 101/110, адреса wordcode и ABI. В старых suites
изменены конкретные ожидания canonical LIST, ключ ABI lookup и проверки
прежней заглушки WRITE. Никакой нормализации фактического stdout или
ослабления сравнения не добавлено.

## Атомарный LOAD и канонический SAVE (этап 5)

```powershell
py -3 -B -m unittest discover -s tests/rars_files -p "test_*.py" -v
```

LOAD читает файл последовательными блоками по 256 байт и собирает по одной
физической строке в ограниченном `input_line`. Поэтому общий размер файла не
зависит от 8-КиБ `program_buf`: допустимы все 128 активных строк с операторным
текстом по 127 байт. LF и CRLF обрабатываются одинаково, завершающий LF не
обязателен. Каждая непустая строка передаётся существующим процедурам разбора
номера и REPL storage, включая replacement, delete и legacy migration.

Перед импортом сохраняется фиксированный снимок ключей, текстов и active count.
Рабочей областью транзакции служит очищенное live storage; любая ошибка чтения,
номера, формата строки, длины или вместимости закрывает файл и восстанавливает
снимок. Ошибка открытия происходит до изменения storage. Переменные и массивы
LOAD не изменяет.

SAVE не строит промежуточную копию в `program_buf`. Он использует общий со
Stage 4 отсортированный обход, formatter `g.ll` и проверку slot, после чего
потоково записывает номер, пробел, неизменённый операторный текст и LF.
Обрабатываются короткие записи syscall; нулевой или ошибочный результат даёт
контролируемую E12. Пустая программа создаёт пустой файл. Внешний откат уже
частично записанного файла не обещается, а внутреннее состояние не меняется.

Suite проверяет точный stdout настоящего RARS и точные байты созданных файлов:
канонический порядок, replacement/delete, LF/CRLF/no-final-LF, сохранение
регистра текста и переменных, откат после каждой категории ошибки, recovery,
пустой SAVE, SAVE→ERASE→LOAD и предельную программу больше 8191 байта. Python
используется только как драйвер и для fixture/file assertions, не как oracle
семантики FOCAL.

## Разделитель, COMMENT и единый frontend (этап 6)

```powershell
py -3 -B -m unittest discover -s tests/rars_frontend -p "test_*.py" -v
```

`compile_physical_line` является общей точкой компиляции одной физической
FOCAL-строки для immediate-ввода и для строк `compile_program`. Последний путь
одинаков для stored RUN, source после LOAD и embedded/batch программы. Frontend
последовательно вызывает прежний `compile_statement`, проверяет его лексическую
границу и потребляет `;`. Пустые участки между разделителями ничего не
генерируют. Весь immediate wordcode строится до запуска VM, поэтому ошибка
позднего оператора не выполняет уже скомпилированный префикс.

Локальная проверка конца statement считает `;` границей, но не потребляет его.
Благодаря этому строковые литералы разбираются существующим string parser и
могут содержать `;`; предварительного split исходного текста нет. COMMENT/C
точно распознаётся таблицей токенов и передвигает `parse_ptr` непосредственно
до LF, CR или NUL. Поэтому comment-tail не разбирается и не может поглотить
следующую физическую строку из `program_buf`.

LIST/WRITE/SAVE по-прежнему выводят сохранённый операторный текст без
переписывания пробелов, регистра, `;` или COMMENT. `line_offsets` фиксируется
до вызова общего frontend и остаётся адресом начала numbered physical line.
Новый exact suite проверяет empty operators, strings, COMMENT boundaries,
QUIT, отсутствие partial immediate execution, совпадение immediate/stored/
LOAD/batch, сохранность source и отдельный ASM-тест line offset.

## Числа, выражения, степень и функции (этап 7)

```powershell
py -3 -B -m unittest discover -s tests/rars_expr -p "test_*.py" -v
```

`compile_expr` остаётся единственной точкой expression grammar. Арифметические
уровни: binary `+/-`; затем `/`; затем `*`; затем unary sign над power;
right-associative `^`; primary (literal, variable, function или grouping).
Таким образом `*` связывает сильнее `/`, `-A^I` означает `-(A^I)`, а знак
после обычного binary operator без группировки отвергается. Правая сторона `^`
может иметь один знак, поэтому `2^-2` допустимо.

Decimal scanner принимает целую, fixed-point и E/e формы, строит значение
только Float32-инструкциями RARS и помещает raw IEEE-754 binary32 bits после
`OP_PUSH_BITS`. Старый integer-конвертирующий `OP_PUSH_F` оставлен для прежнего
служебного wordcode. Скобки `()`, `[]`, `<>` проверяются попарно; исходник не
переписывается.

Добавлены `OP_POW`, `OP_ABS`, `OP_SQRT`, `OP_TRUNC`, `OP_SGN`. Степень
проверяет целочисленность показателя и использует exponentiation by squaring;
отрицательный показатель вычисляется через reciprocal, `0^0` даёт 1.
Деление на ноль, дробный показатель, `0` в отрицательной степени и отрицательный
аргумент FSQT дают sticky E15 без исключения RARS. Реализованы только FABS,
FSQT, FITR и FSGN, с тремя эквивалентными типами скобок.

Suite использует настоящий RARS и exact stdout, проверяет literal wordcode bits,
нестандартные приоритеты, unary restrictions, brackets/functions, compile/runtime
recovery и общий immediate/stored/LOAD/batch path. Python остаётся драйвером,
не parser или semantic oracle.

## Таблица символов и индексированные переменные (этап 8)

```powershell
py -3 -B -m unittest discover -s tests/rars_symbols -p "test_*.py" -v
```

Идентификатор по FR-20 начинается с латинской буквы и продолжается латинскими
буквами или цифрами. Parser потребляет имя целиком, но canonical key состоит из
первых двух символов в верхнем ASCII-регистре; отсутствующий второй символ
кодируется нулём. Поэтому `A` и `AB` различны, а `AB`, `ABCDE` и `abOther`
обозначают один symbol. Любое пользовательское имя с первым символом `F`
отвергается; FABS, FSQT, FITR и FSGN распознаются прежним function parser.

Старые `vars[26]` и `arrays[26][100]` заменены одной фиксированной таблицей из
512 записей по 16 байт: canonical name key, scalar/indexed discriminator,
signed int32 index и Float32 value. Scalar и каждый конкретный indexed element
занимают отдельную запись. Lookup отсутствующего значения возвращает ноль и не
выделяет запись; только runtime STORE выполняет find-or-create. Перезапись
существующей записи допустима при полной таблице, а отказ 513-й записи не меняет
count и существующие данные.

Indexed syntax — только `NAME(expr)`. Индекс вычисляется общим expression path,
проверяется на NaN, infinity и диапазон signed int32, затем явно округляется к
ближайшему целому с ties-to-even независимо от `frm`. Отрицательные индексы
допустимы. Wordcode scalar/indexed opcodes хранят canonical name key и выполняют
lookup во время VM execution; компиляция persistent таблицу не меняет. SET,
expression reads, существующий ASK и legacy FOR используют те же helpers.

Таблица сохраняется через immediate, RUN, LIST/WRITE, SAVE, LOAD и QUIT. LOAD
меняет только source. `reset_runtime` очищает временное состояние, но не symbols;
ERASE очищает source, таблицу и runtime state. Новый suite использует настоящий
RARS и exact stdout, включая 512/513, persistence, source preservation,
nearest-even, F-reservation и immediate/stored/LOAD/batch paths. Python остаётся
только драйвером и генератором fixtures.

## TYPE и числовые форматы (этап 9)

```powershell
py -3 -B -m unittest discover -s tests/rars_type -p "test_*.py" -v
```

`TYPE`/`T` принимает непустой список элементов через запятую: строковый
литерал `"text"`, арифметическое выражение, `!` или директиву формата. Элементы
выполняются слева направо. `!` печатает LF. Символы `;`, `%`, `!` и `,` внутри
кавычек остаются обычным текстом; встроенные кавычки и escape-последовательности
не поддерживаются. Выражения проходят через общий `compile_expr`, а immediate,
stored, LOAD и batch — через общий physical-line frontend.

Поддерживаются только директивы FR-09: `%` включает нормализованный
экспоненциальный вывод, `%W` задаёт минимальную ширину целого поля без дробной
части, `%W.0d` — минимальную ширину поля с `d` цифрами после точки. `W` — любой
положительный decimal parameter, представимый положительным signed int32;
накопление цифр проверяется до умножения и не допускает wraparound. `d` — 0..9
и записывается ровно одной цифрой после `.0`. Знак, точка и дробные цифры входят
в ширину; слева добавляются потоково выводимые пробелы. Поэтому `W` не связан с
размером formatter buffer. Более длинное представление не обрезается.
Если безопасное fixed-масштабирование не помещается в signed int32, разрешённый
FR-09 экспоненциальный формат используется как fallback.

Default до первой директивы сохраняет совместимый RARS `PrintFloat`. Явный
формат хранится в persistent runtime state и действует на следующие числовые
элементы и операторы, включая RUN, LOAD и возврат QUIT в REPL. Компиляция формат
не меняет. ERASE, как полный сброс состояния по FR-23, и новый процесс
восстанавливают default. Для fixed-формата принято детерминированное округление
половин от нуля; FR-09 не требует точного округления конкретной исторической
машины. `+0.0` и `-0.0` печатаются одинаково.

Компилятор выдаёт `OP_SET_FORMAT` с тремя операндами; VM сначала полностью
считывает и проверяет mode/width/precision и только затем атомарно меняет
состояние. `OP_PRINT_F` проверяет состояние и конечность Float32, после чего
выбирает default, exponential или внутренний fixed formatter. NaN/∞ дают E15,
ошибочный format state — E10, усечённый wordcode — E02. Fixed formatter
использует статический 256-байтовый NUL-terminated buffer с проверкой каждой
записи; padding выводится отдельно и не может переполнить buffer.

Dedicated suite сверяет exact stdout настоящего RARS: строки, выражения и `!`,
все три директивы, переключение и lifetime формата, округление по обе стороны
half, padding/знак/overflow, Float32 exponent, negative zero, malformed syntax,
non-finite recovery, compile-before-run atomicity, source preservation и общий
immediate/stored/LOAD/batch path. Low-level safety suite дополнительно проверяет
последний доступный байт formatter buffer, отказ без записи за границей,
усечённый/повреждённый format opcode, corrupt persistent state и underflow
`OP_PRINT_F`. Python служит только драйвером и проверяет stdout/fixtures; вся
семантика форматирования исполняется ASM в RARS.

## Полноценный ASK (этап 10)

```powershell
py -3 -B -m unittest discover -s tests/rars_ask -p "test_*.py" -v
```

`ASK`/`A` принимает непустой список `item ("," item)*`, где item — строковый
литерал, scalar/indexed variable target или `!`. Строка выводится дословно,
`!` печатает LF. Для каждого variable target VM печатает ровно `:` без пробела
и newline, после чего читает отдельную bounded physical input line. `%`, `¤`,
`@`, буквенные ответы и специальные исторические delimiters ASK в обязательный
профиль не входят.

Ответ является исходным текстом одного FOCAL-выражения, а не аргументом RARS
`ReadFloat`. После удаления внешних пробелов он компилируется существующим
`compile_expr`; после выражения разрешены только пробелы и NUL/LF/CRLF.
Следовательно, ASK наследует Float32 literals, арифметику, степень, функции,
scalar/indexed reads и все E10/E15 semantics этапа 7 без второго parser.

`OP_ASK_V` и `OP_ASK_ARR` содержат canonical symbol key. Индексированный target
сначала вычисляет индекс из исходного ASK statement и применяет общий
nearest-even `index_from_ft0`; при ошибке индексирования prompt не печатается и
ответ не читается. Успешный ответ записывается только через
`symbol_store_ft0`, поэтому first-two identity, F-reservation, scalar/indexed
различие и общий предел 512 записей остаются едиными.

Runtime evaluator сохраняет основной `pc_ptr`, `bc_ptr`, `parse_begin`,
`parse_end`, `parse_ptr` и baseline `vm_sp_ptr`. Временный код выражения и
`OP_HALT` добавляются в свободный хвост `bytecode_buf`, выполняются вложенным
`vm_run`, дают ровно одно Float32 значение и затем скрываются восстановлением
исходного `bc_ptr`. Все курсоры и stack baseline восстанавливаются как при
успехе, так и при sticky compile/runtime error; TYPE format и symbols не
сбрасываются. Поэтому повторные ASK не расходуют wordcode постоянно.

Консольный ответ хранится в отдельном 256-байтовом `ask_input_buf` с NUL
reservation. RARS ReadString потребляет целую host physical line до локального
усечения; полное заполнение без LF отвергается как E07, а остаток этой строки не
становится следующим ответом или REPL-командой. Пустой/ошибочный ответ прекращает
текущее выполнение, не меняет текущий target и возвращает управление REPL.
Успешные присваивания более ранних ASK items не откатываются.

Dedicated suite использует настоящий RARS и exact stdout: строки/`!`/prompt,
несколько зависимых targets, полный expression profile, aliases/case/indexed
targets, 512/513 capacity, malformed lists and answers, runtime errors, длинный
input, TYPE format persistence, compile-before-run atomicity, source
preservation и immediate/stored/LOAD/batch paths. Safety suite дополнительно
проверяет operands/underflow, границы input buffer, нехватку bytecode, cleanup
pc/bc/parser/stack на success/error и повторное использование временного кода.
Python остаётся только драйвером и проверяет stdin/stdout/files.

## GOTO и исторический sign-IF (этап 11)

```powershell
py -3 -B -m unittest discover -s tests/rars_control -p "test_*.py" -v
```

Нормативная грамматика безусловного перехода — `GOTO [g.ll]`; `G` и `GO`
являются только точными aliases. Цель разбирается общим composite-number parser:
`1.1` означает `1.10`, а `2.01` и `2.10` различны; `xx.00` недопустим.
Отсутствующая цель передаёт управление строке с наименьшим canonical key.
Это именно переход внутри текущего VM execution, а не рекурсивный `RUN`.

Нормативный условный переход имеет вид
`IF (expression) negative[,zero[,positive]]`; точное сокращение — `I`.
Скобки обязательны. Выражение компилируется общим `compile_expr` ровно один раз,
а VM выбирает ветвь по знаку конечного Float32 без integer conversion. `+0.0` и
`-0.0` выбирают zero branch; NaN/∞ согласованно с arithmetic model дают E15.
При одной цели определена только отрицательная ветвь, при двух — отрицательная
и нулевая, при трёх — все три. Любая отсутствующая trailing-ветвь означает
обычный fall-through к следующему оператору той же физической строки или к
следующей строке. Четвёртая цель и malformed comma list дают E10.

Компилятор выдаёт `OP_SIGN_BRANCH` с тремя canonical keys; нулевой operand —
внутренний sentinel отсутствующей ветви. VM сначала полностью считывает opcode,
затем один раз снимает условие со стека и разрешает только выбранный ненулевой
key. Поэтому отсутствующая выбранная строка даёт E08, а отсутствующие цели в
невыбранных ветвях не мешают выполнению. `OP_JUMP` хранит один canonical key,
а `OP_JUMP_FIRST` реализует форму без цели. Оба перехода используют уже
построенные `line_numbers`/`line_offsets`; исходный текст во время перехода не
сканируется и программа повторно не компилируется. Двухфазная сортировка строк
делает forward/backward targets независимыми от порядка ввода.

Immediate physical line сначала целиком компилируется без исполнения. Если она
содержит line-control, stored source компилируется в тот же bytecode image, а
проверенная immediate line добавляется в его хвост и запускается оттуда. Это
позволяет `GOTO g.ll`, immediate sign-IF и `GO;...` безопасно переходить в
stored program без stale offsets и сохраняет compile-before-run atomicity.
После перехода остаток прежнего execution path естественно не исполняется.
QUIT, ASK values, symbols и persistent TYPE format сохраняют прежний runtime
contract; LOAD по-прежнему только меняет storage.

Старый boolean `IF expr THEN/GOTO/DO ...` не является FR-12. Он сохранён только
как изолированный compatibility path для непарентезированной формы; любой
`IF (` безусловно разбирается нормативным sign-IF parser. Legacy integer targets
остаются прежней миграцией и не расширяют composite grammar новых тестов.

Dedicated suite выполняет настоящий RARS с exact stdout и покрывает forward и
backward GOTO, loop, aliases/case, composite identity, unordered input,
semicolon/QUIT, no-target, immediate/stored/LOAD/batch, E08 и source
preservation; для IF — три знака, оба signed zero, 1/2/3 targets и fall-through,
expressions/symbols/index/functions, ASK/TYPE state, malformed syntax, выбранные
и невыбранные missing targets, E15 recovery и atomicity. Low-level safety suite
проверяет усечённый conditional opcode, stack underflow, corrupted selected key,
повреждённые line offsets и absolute jump до/после/между границами wordcode.
Python остаётся только драйвером, generator fixtures и механизмом assertions.

## DO / RETURN и стек контекстов (этап 12)

```powershell
py -3 -B -m unittest discover -s tests/rars_do -p "test_*.py" -v
```

Нормативная грамматика — `DO target`/`D target` и `RETURN`/`R`, где bare
decimal `target` означает группу `1..99`, а composite `g.ll` — точную строку.
`2.1` и `2.10` имеют один canonical key; legacy integer-ordinal GOTO grammar на
DO не распространяется. Bare `DO`, `DO ALL` и variable target не входят в
профиль. Исходное написание операторов сохраняется для LIST/WRITE/SAVE.

Компилятор выдаёт `OP_DO kind,scope` и `OP_RETURN`. Для каждой хранимой
физической строки он также выдаёт `OP_LINE_END canonical_key` и записывает её
проверяемый wordcode offset в `line_end_offsets`. Поэтому `DO g.ll` выполняет
все statements ровно этой физической строки, а `DO group` начинает с
минимального существующего ключа группы и проходит её строки в canonical
порядке. `OP_LINE_END` завершает line-call на границе указанной строки либо
group-call после последней строки группы. Естественный и явный возврат используют
одну процедуру checked pop; `RETURN` пропускает остаток текущей execution path.

FOCAL-стек DO является отдельным статическим массивом из 16 записей по 16 байт,
не связанным с RISC-V `sp` и вычислительным VM stack. Запись содержит абсолютный
`return_pc`, вид области (`LINE`/`GROUP`), canonical line key либо номер группы и
integrity tag по этим трём полям. Target, depth, return address, tag и границы
проверяются до commit; depth записывается последним. Семнадцатый вызов,
`RETURN` вне вызова и повреждённая запись дают контролируемую E16 без OOB.
Отсутствующая строка/группа даёт E08 до push.

DO выполняет raw validated transfer после push и потому не разрушает caller
context. Пользовательские `GOTO`, no-target `GO`, выбранные sign-IF branches и
legacy line-control opcodes проходят через общий DO-aware transfer. Сначала
полностью разрешается существующая target line через `line_numbers`/
`line_offsets`, затем все проверяемые контексты рассматриваются сверху вниз.
Контекст сохраняется, если target принадлежит его canonical scope; иначе он
включается в candidate unwind. Новый depth фиксируется один раз после полной
валидации. Так inner context может быть снят с сохранением outer context, а
переход наружу из всех вызовов удаляет их без исторического return-like
поведения. Missing selected target и повреждённый context не дают partial unwind.
Внутренние `OP_JUMP_ABS`/`OP_JUMP_Z_ABS` этого механизма не вызывают.

Immediate DO использует общий механизм stage 11: сохранённая программа и
полностью скомпилированная immediate physical line находятся в одном wordcode
image, а `return_pc` указывает на statement сразу после DO в immediate tail.
Stored RUN, LOAD→RUN и batch используют тот же compiler/VM path. ASK values,
symbol table и persistent TYPE format переживают вызовы без копирования;
`QUIT` прекращает всё текущее FOCAL execution. Перед каждым новым REPL/batch
execution `reset_runtime` обнуляет depth, поэтому QUIT и runtime error не
оставляют stale contexts.

Dedicated exact-stdout suite покрывает line/group calls, natural и explicit
RETURN, nested LIFO, 16/17, aliases/case/composite identity, missing targets,
внутренние и внешние GOTO/IF, selective unwind, immediate/stored/LOAD/batch,
QUIT/error cleanup, ASK/TYPE/symbol state, source preservation, compile-before-
run atomicity и адаптированные исторические примеры 2.36/2.37/RETURN. Low-level
safety cases проверяют усечённые opcodes, kind/scope/depth/return_pc, sentinel,
identity/offset границы строк и отсутствие частичного push/unwind. Python здесь
остаётся только RARS driver, generator fixtures и механизмом assertions.

## Ограничения

- значения внутри VM, literal parser, `ASK` и `TYPE` чисел используют Float32;
- `FOR` поддерживает только шаг `+1`;
- RARS REPL имеет 128 физических slots по 127 байт текста плюс NUL;
- RUN всё ещё ограничен 8191 байтом сериализованного исходника плюс NUL;
  при превышении выдаёт ошибку, хотя LIST/WRITE/SAVE доступны для всей программы;
- SAVE гарантирует контролируемую внутреннюю ошибку записи, но не откатывает
  внешнее содержимое уже частично записанного файла;
