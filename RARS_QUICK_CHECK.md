# Быстрая проверка и сценарий демонстрации

## Запуск

Откройте `rars_focal_interpreter.asm` в RARS 1.6, выберите Assemble и Run.
Ожидаемое приглашение:

```text
FOCAL/RARS REPL. Enter HELP for commands.
>
```

`QUIT/Q` завершает только текущее FOCAL execution; для выхода из процесса после
демонстрации введите `EXIT`.

## Сценарий защиты (до 10 минут)

1. Immediate arithmetic и сохранение state:

   ```text
   SET A=5
   TYPE (A+3)*2,!
   ```

   Ожидается `16.0`.

2. Stored lines, сортировка номеров и RUN:

   ```text
   2.10 TYPE "B",!;QUIT
   1.01 TYPE "A"
   LIST
   RUN
   ```

   LIST показывает `1.01`, затем `2.10`; RUN печатает `AB`.

3. ASK и historical sign-IF:

   ```text
   ERASE
   1.01 ASK X
   1.02 IF (X) 2.01,2.02,2.03
   2.01 TYPE "NEG",!;QUIT
   2.02 TYPE "ZERO",!;QUIT
   2.03 TYPE "POS",!;QUIT
   RUN
   ```

   После `:` введите `-2`; ожидается `NEG`.

4. FOR с явным шагом:

   ```text
   FOR I=1,2,5;TYPE I,!
   ```

   Ожидаются `1.0`, `3.0`, `5.0`.

5. DO/RETURN:

   ```text
   ERASE
   2.10 TYPE "SUB";RETURN;TYPE "BAD"
   1.01 TYPE "A";DO 2.10;TYPE "B",!;QUIT
   RUN
   ```

   Ожидается `ASUBB`.

6. Sorting demo через файл (путь можно сделать абсолютным):

   ```text
   LOAD tests/rars_profile/fixtures/files/sort.focal
   LIST
   RUN
   ```

   Ожидаются `1.0` … `5.0` по одному значению на строке.

7. SAVE → ERASE → LOAD:

   ```text
   SAVE saved.focal
   ERASE
   LIST
   LOAD saved.focal
   LIST
   RUN
   ```

   Первый LIST пуст, второй восстанавливает canonical source, RUN снова сортирует.

8. Controlled error и recovery:

   ```text
   TYPE 1/0,!
   TYPE "Alive",!
   ```

   Сначала выводится `E15`, затем `Alive`: REPL и stored source остаются рабочими.

## Автоматическая финальная проверка

В PowerShell из корня репозитория:

```powershell
$env:RARS_JAR = 'C:\Users\Admin\Desktop\rars1_6\rars1_6.jar'
Get-FileHash -LiteralPath $env:RARS_JAR -Algorithm SHA256
java -version
py -3 -B tools/run_rars_profile_tests.py
```

Проверенный SHA-256 RARS 1.6:
`780F730EB457B1BA609E968ACCC2C8B77D8F92C3D9DBF30CC7FDB3CFB14E8C24`.
Успех — `Mandatory scenarios: 54/54`, `Mandatory skipped: 0`,
`Acceptance: PASS`.

Пользовательские границы: 128 active lines, 127 байт operator text, 512 symbol
entries, VM stack 512, DO/FOR depth 16. RUN компилирует storage напрямую и не
имеет прежнего ограничения суммарного source в 8191 байт.
