import argparse
from pathlib import Path


def asm_string(value: str) -> str:
    escaped = (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )
    return f'    .asciz "{escaped}"'


def main():
    parser = argparse.ArgumentParser(
        description="Create a RARS interpreter asm file with another embedded FOCAL program."
    )
    parser.add_argument("focal", help="FOCAL demo program")
    parser.add_argument(
        "-t",
        "--template",
        default="rars_focal_interpreter.asm",
        help="RARS interpreter template",
    )
    parser.add_argument(
        "-o",
        "--output",
        default="rars_demo.asm",
        help="Output asm file",
    )
    args = parser.parse_args()

    template = Path(args.template)
    focal = Path(args.focal)
    output = Path(args.output)

    asm = template.read_text(encoding="utf-8")
    source = focal.read_text(encoding="utf-8")
    if not source.endswith("\n"):
        source += "\n"

    lines = asm.splitlines()
    for idx, line in enumerate(lines):
        if line.strip().startswith(".asciz ") and idx > 0 and lines[idx - 1].strip() == "focal_program:":
            lines[idx] = asm_string(source)
            break
    else:
        raise SystemExit("Cannot find focal_program .asciz in template")

    output.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[OK] Created {output} from {focal}")


if __name__ == "__main__":
    main()
