import os
import sys
from contextlib import redirect_stdout
from io import StringIO

from focal_interpreter.codegen import RISC_VCodeGenerator
from focal_interpreter.interpreter import Interpreter
from focal_interpreter.lexer import Lexer
from focal_interpreter.parser import Parser


def parse_program(source_code):
    lexer = Lexer(source_code)
    tokens = lexer.tokenize()
    parser = Parser(tokens)
    return parser.parse()


class TestRunner:
    def __init__(self):
        self.passed = 0
        self.failed = 0
        self.tests = []

    def add_test(self, filename, expected_output=None, input_data=None):
        self.tests.append({
            "filename": filename,
            "expected": expected_output,
            "input": input_data,
        })

    def run_test(self, test_info):
        filename = test_info["filename"]
        expected = test_info["expected"]
        input_data = test_info["input"]

        print(f"\n{'=' * 60}")
        print(f"Тест: {filename}")
        print(f"{'=' * 60}")

        if not os.path.exists(filename):
            print(f"[FAIL] Файл не найден: {filename}")
            self.failed += 1
            return False

        try:
            with open(filename, "r", encoding="utf-8") as f:
                source_code = f.read()

            print("Исходный код:")
            print(source_code)
            print("\nВывод:")

            output = self.run_interpreter(source_code, input_data)
            print(output, end="")

            if expected:
                if expected in output or output.strip() == expected.strip():
                    print("\n[OK] Интерпретатор: результат совпал")
                else:
                    print("\n[FAIL] Интерпретатор: результат не совпал")
                    print(f"Ожидалось: {expected}")
                    print(f"Получено: {output}")
                    self.failed += 1
                    return False
            else:
                print("\n[OK] Интерпретатор: выполнено без проверки вывода")

            if not self.validate_codegen(source_code):
                self.failed += 1
                return False

            self.passed += 1
            return True

        except Exception as e:
            print(f"[FAIL] Ошибка: {e}")
            import traceback

            traceback.print_exc()
            self.failed += 1
            return False

    def run_interpreter(self, source_code, input_data):
        output_buffer = StringIO()

        if input_data:
            import unittest.mock

            input_values = list(input_data)
            with unittest.mock.patch("builtins.input", side_effect=input_values):
                with redirect_stdout(output_buffer):
                    program = parse_program(source_code)
                    interpreter = Interpreter()
                    interpreter.interpret(program)
        else:
            with redirect_stdout(output_buffer):
                program = parse_program(source_code)
                interpreter = Interpreter()
                interpreter.interpret(program)

        return output_buffer.getvalue()

    def validate_codegen(self, source_code):
        try:
            program = parse_program(source_code)
            asm = RISC_VCodeGenerator().generate(program)
        except Exception as e:
            print(f"[FAIL] Генерация RISC-V: {e}")
            return False

        required = (".data", ".text", ".globl main", "main:")
        missing = [item for item in required if item not in asm]
        if missing:
            print(f"[FAIL] Генерация RISC-V: нет обязательных секций {missing}")
            return False

        for line in program:
            label = f"line_{line.line_number}:"
            if label not in asm:
                print(f"[FAIL] Генерация RISC-V: нет метки {label}")
                return False

        print("[OK] Генерация RISC-V: asm построен")
        return True

    def run_all(self):
        print("\n" + "=" * 60)
        print("ЗАПУСК ТЕСТОВ FOCAL")
        print("=" * 60)

        for test in self.tests:
            self.run_test(test)

        print("\n" + "=" * 60)
        print("ИТОГИ ТЕСТИРОВАНИЯ")
        print("=" * 60)
        print(f"[OK] Пройдено: {self.passed}")
        print(f"[FAIL] Провалено: {self.failed}")
        print(f"Всего: {self.passed + self.failed}")
        print("=" * 60)

        return self.failed == 0


def main():
    runner = TestRunner()

    print("Загрузка тестовых файлов...\n")

    runner.add_test("tests/test_hello.focal", expected_output="Hello, World!")
    runner.add_test("tests/test_factorial.focal", expected_output="Factorial", input_data=["5"])
    runner.add_test("tests/test_if.focal", expected_output="A is greater")
    runner.add_test("tests/test_array.focal", expected_output="A(2) = 30")
    runner.add_test("tests/test_functions.focal", expected_output="Square root")
    runner.add_test("tests/test_goto.focal", expected_output="1")
    runner.add_test("tests/test_operators.focal", expected_output="A + B = 15")

    success = runner.run_all()
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
