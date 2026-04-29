import re
import sys
from pathlib import Path

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


def run(source_code: str, start_line=None):
    try:
        program = parse_source(source_code)
        interpreter = Interpreter()
        interpreter.interpret(program, start_line=start_line)

    except Exception as e:
        print(f"Error: {e}")
        import traceback

        traceback.print_exc()


def repl():
    print("FOCAL Interpreter")
    print("Commands: RUN/GO [line], LIST, LOAD <file>, SAVE <file>, ERASE, HELP, QUIT")
    print()

    stored_lines = {}

    def build_source():
        return "\n".join(
            f"{line_no}: {stored_lines[line_no]}"
            for line_no in sorted(stored_lines)
        )

    def print_help():
        print("Enter numbered lines, then RUN:")
        print('  10 SET A=2+3*4')
        print('  20 TYPE "A = ",A,!')
        print("  30 QUIT")
        print("  RUN")
        print("Commands:")
        print("  RUN/GO [line]  run stored program")
        print("  LIST           show stored program")
        print("  LOAD <file>    load program from file")
        print("  SAVE <file>    save stored program to file")
        print("  ERASE          clear stored program")
        print("  HELP           show this help")
        print("  QUIT           exit REPL")

    while True:
        try:
            line = input("> ")
            stripped = line.strip()

            if not stripped:
                continue

            command = stripped.upper()
            if command == "QUIT":
                break

            if command == "HELP":
                print_help()
                continue

            load_match = re.match(r"^LOAD\s+(.+)$", stripped, re.IGNORECASE)
            if load_match:
                path = Path(load_match.group(1).strip())
                try:
                    loaded = {}
                    for source_line in path.read_text(encoding="utf-8").splitlines():
                        numbered = re.match(r"^\s*(\d+)\s*:?\s*(.*)$", source_line)
                        if numbered and numbered.group(2):
                            loaded[int(numbered.group(1))] = numbered.group(2)
                    stored_lines.clear()
                    stored_lines.update(loaded)
                    print("Loaded")
                except OSError as e:
                    print(f"Error: {e}")
                continue

            save_match = re.match(r"^SAVE\s+(.+)$", stripped, re.IGNORECASE)
            if save_match:
                path = Path(save_match.group(1).strip())
                try:
                    path.write_text(build_source() + ("\n" if stored_lines else ""), encoding="utf-8")
                    print("Saved")
                except OSError as e:
                    print(f"Error: {e}")
                continue

            run_match = re.match(r"^(RUN|GO)(?:\s+(\d+))?$", command)
            if run_match:
                source = build_source()
                if source:
                    start_line = int(run_match.group(2)) if run_match.group(2) else None
                    run(source, start_line=start_line)
                else:
                    print("No program. Enter numbered lines first.")
                continue

            if command == "LIST":
                for line_no in sorted(stored_lines):
                    print(f"{line_no} {stored_lines[line_no]}")
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
