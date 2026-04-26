import os
import sys

from focal_interpreter.codegen import RISC_VCodeGenerator
from focal_interpreter.lexer import Lexer
from focal_interpreter.parser import Parser


def compile_focal_to_riscv(input_file: str, output_file: str = None):
    if not os.path.exists(input_file):
        print(f"Ошибка: файл '{input_file}' не найден")
        return False

    try:
        with open(input_file, "r", encoding="utf-8") as f:
            source_code = f.read()

        lexer = Lexer(source_code)
        tokens = lexer.tokenize()

        parser = Parser(tokens)
        program = parser.parse()

        generator = RISC_VCodeGenerator()
        riscv_code = generator.generate(program)

        if output_file is None:
            base_name = os.path.splitext(input_file)[0]
            output_file = f"{base_name}.asm"

        with open(output_file, "w", encoding="utf-8") as f:
            f.write(riscv_code)

        print("[OK] Компиляция успешна")
        print(f"  Входной файл: {input_file}")
        print(f"  Выходной файл: {output_file}")
        return True

    except Exception as e:
        print(f"Ошибка компиляции: {e}")
        import traceback

        traceback.print_exc()
        return False


def main():
    if len(sys.argv) < 2:
        print("Использование: python compile_to_riscv.py <input.focal> [output.asm]")
        print("Пример: python compile_to_riscv.py tests/test_hello.focal")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    success = compile_focal_to_riscv(input_file, output_file)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
