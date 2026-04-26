import re
import sys

from focal_interpreter.interpreter import Interpreter
from focal_interpreter.lexer import Lexer
from focal_interpreter.parser import Parser


def parse_source(source_code: str):
    lexer = Lexer(source_code)
    tokens = lexer.tokenize()
    parser = Parser(tokens)
    return parser.parse()


def run_file(filename: str):
    try:
        with open(filename, "r", encoding="utf-8") as f:
            source_code = f.read()

        run(source_code)
    except FileNotFoundError:
        print(f"Error: File '{filename}' not found")
    except Exception as e:
        print(f"Error: {e}")


def run(source_code: str):
    try:
        program = parse_source(source_code)
        interpreter = Interpreter()
        interpreter.interpret(program)

    except Exception as e:
        print(f"Error: {e}")
        import traceback

        traceback.print_exc()


def repl():
    print("FOCAL Interpreter")
    print("Commands: RUN/GO, LIST, ERASE, QUIT")
    print()

    stored_lines = {}

    while True:
        try:
            line = input("> ")
            stripped = line.strip()

            if not stripped:
                continue

            command = stripped.upper()
            if command == "QUIT":
                break

            if command in ("RUN", "GO"):
                source = "\n".join(
                    f"{line_no}: {stored_lines[line_no]}"
                    for line_no in sorted(stored_lines)
                )
                if source:
                    run(source)
                continue

            if command == "LIST":
                for line_no in sorted(stored_lines):
                    print(f"{line_no}: {stored_lines[line_no]}")
                continue

            if command == "ERASE":
                stored_lines.clear()
                continue

            numbered = re.match(r"^(\d+)\s*:?\s*(.*)$", stripped)
            if numbered:
                line_no = int(numbered.group(1))
                statement = numbered.group(2)
                if statement:
                    stored_lines[line_no] = statement
                else:
                    stored_lines.pop(line_no, None)
                continue

            run(f"1: {line}")

        except KeyboardInterrupt:
            print("\nExiting...")
            break
        except EOFError:
            break
        except Exception as e:
            print(f"Error: {e}")


def main():
    if len(sys.argv) > 1:
        run_file(sys.argv[1])
    else:
        repl()


if __name__ == "__main__":
    main()
