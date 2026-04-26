from typing import List, Dict, Optional, Tuple

from focal_interpreter.lexer import TokenType
from focal_interpreter.parser import (
    ASTNode, NumberNode, StringNode, VariableNode, BinaryOpNode,
    UnaryOpNode, FunctionCallNode, SetStatement, TypeStatement,
    AskStatement, IfStatement, ForStatement, GotoStatement,
    DoStatement, QuitStatement, ProgramLine
)


def _float_key(x: float) -> str:
    if x == 0.0:
        return "0"
    if x == 1.0:
        return "1"
    if x == -1.0:
        return "-1"
    return repr(x)


def _float_asm(x: float) -> str:
    if x == 0.0:
        return "0.0"
    if x == 1.0:
        return "1.0"
    if x == -1.0:
        return "-1.0"
    s = repr(x)
    if "e" in s.lower():
        return s
    if "." in s:
        return s
    return f"{s}.0"


class RISC_VCodeGenerator:

    def __init__(self):
        self.variables: Dict[str, int] = {}
        self.arrays: Dict[str, int] = {}
        self.next_memory_addr = 0x10010000

        self.strings: List[str] = []
        self.string_labels: Dict[str, str] = {}

        self.float_constants: Dict[str, Tuple[float, str]] = {}

        self.line_labels: Dict[int, str] = {}
        self.used_functions = set()

        self.label_counter = 0
        self.temp_counter = 0

        self.available_regs = ['t0', 't1', 't2', 't3', 't4', 't5', 't6']
        self.reg_usage: Dict[str, bool] = {reg: False for reg in self.available_regs}
        self.available_float_regs = ['ft0', 'ft1', 'ft2', 'ft3', 'ft4', 'ft5', 'ft6']
        self.float_reg_usage: Dict[str, bool] = {r: False for r in self.available_float_regs}

    def generate(self, program: List[ProgramLine]) -> str:
        for line in program:
            label = f"line_{line.line_number}"
            self.line_labels[line.line_number] = label

        body_lines = []
        for line in program:
            body_lines.append(f"{self.line_labels[line.line_number]}:")
            body_lines.extend(self.generate_statement(line.statement))
            body_lines.append("")

        helpers = self.generate_helpers()
        data_section = self.generate_data_section()

        full_code = []
        full_code.append(".data")
        full_code.extend(data_section)
        full_code.append("")
        full_code.append(".text")
        full_code.append(".globl main")
        full_code.append("main:")
        full_code.append("    addi sp, sp, -1024")
        full_code.append("")
        if program:
            full_code.append(f"    j {self.line_labels[program[0].line_number]}")
        full_code.append("")
        full_code.extend(body_lines)

        if helpers:
            full_code.append("")
            full_code.extend(helpers)

        if program and not isinstance(program[-1].statement, QuitStatement):
            full_code.append("    li a7, 10")
            full_code.append("    ecall")

        return "\n".join(full_code)

    def generate_data_section(self) -> List[str]:
        data = []

        if self.variables:
            for var_name, addr in sorted(self.variables.items()):
                data.append("    .align 2")
                data.append(f"var_{var_name}: .float 0.0")

        if self.arrays:
            data.append("")
            for arr_name, base_addr in sorted(self.arrays.items()):
                data.append("    .align 2")
                data.append(f"arr_{arr_name}: .space 400")

        if self.float_constants:
            data.append("")
            for (val, label) in self.float_constants.values():
                data.append(f"{label}: .float {_float_asm(val)}")

        if self.strings:
            data.append("")
            for i, string in enumerate(self.strings):
                label = self.string_labels.get(string, f"str_{i}")
                escaped = string.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')
                data.append(f"{label}: .asciz \"{escaped}\"")

        return data if data else []

    def generate_statement(self, statement: ASTNode) -> List[str]:
        code = []

        if isinstance(statement, SetStatement):
            code.extend(self.generate_set(statement))
        elif isinstance(statement, TypeStatement):
            code.extend(self.generate_type(statement))
        elif isinstance(statement, AskStatement):
            code.extend(self.generate_ask(statement))
        elif isinstance(statement, IfStatement):
            code.extend(self.generate_if(statement))
        elif isinstance(statement, ForStatement):
            code.extend(self.generate_for(statement))
        elif isinstance(statement, GotoStatement):
            code.extend(self.generate_goto(statement))
        elif isinstance(statement, DoStatement):
            code.extend(self.generate_do(statement))
        elif isinstance(statement, QuitStatement):
            code.extend(self.generate_quit(statement))

        return code

    def generate_set(self, stmt: SetStatement) -> List[str]:
        code = []

        expr_reg = self.generate_expression(stmt.expression, code)
        var_addr_reg = self.get_variable_address(stmt.variable, code)

        code.append(f"    fsw {expr_reg}, 0({var_addr_reg})")

        self.free_float_register(expr_reg)
        self.free_register(var_addr_reg)

        return code

    def generate_type(self, stmt: TypeStatement) -> List[str]:
        code = []

        for item in stmt.items:
            if isinstance(item, StringNode):
                if item.value == "\n":
                    code.append("    li a0, 10")
                    code.append("    li a7, 11")
                    code.append("    ecall")
                else:
                    str_label = self.get_string_label(item.value)
                    code.append(f"    la a0, {str_label}")
                    code.append("    li a7, 4")
                    code.append("    ecall")
            else:
                value_reg = self.generate_expression(item, code)
                code.append(f"    fmv.s fa0, {value_reg}")
                code.append("    li a7, 2")
                code.append("    ecall")
                self.free_float_register(value_reg)

        return code

    def generate_ask(self, stmt: AskStatement) -> List[str]:
        code = []

        prompt_label = self.get_string_label(stmt.prompt)
        code.append(f"    la a0, {prompt_label}")
        code.append("    li a7, 4")
        code.append("    ecall")

        code.append("    li a7, 6")
        code.append("    ecall")

        var_addr_reg = self.get_variable_address(stmt.variable, code)
        code.append(f"    fsw fa0, 0({var_addr_reg})")

        self.free_register(var_addr_reg)

        return code

    def generate_if(self, stmt: IfStatement) -> List[str]:
        code = []

        cond_reg = self.generate_expression(stmt.condition, code)
        skip_label = self.new_label("if_skip")

        fzero_label = self.get_float_label(0.0)
        addr_reg = self.allocate_register()
        fzero_reg = self.allocate_float_register()
        code.append(f"    la {addr_reg}, {fzero_label}")
        code.append(f"    flw {fzero_reg}, 0({addr_reg})")
        code.append(f"    feq.s {addr_reg}, {cond_reg}, {fzero_reg}")
        code.append(f"    bnez {addr_reg}, {skip_label}")

        self.free_register(addr_reg)
        self.free_float_register(fzero_reg)
        self.free_float_register(cond_reg)

        if isinstance(stmt.action, int):
            target_label = self.line_labels.get(stmt.action, f"line_{stmt.action}")
            code.append(f"    j {target_label}")
        else:
            code.extend(self.generate_statement(stmt.action))

        code.append(f"{skip_label}:")

        return code

    def generate_for(self, stmt: ForStatement) -> List[str]:
        code = []

        start_reg = self.generate_expression(stmt.start, code)
        end_reg = self.generate_expression(stmt.end, code)
        step_reg = self.generate_expression(stmt.step, code) if stmt.step else None

        if step_reg is None:
            step_reg = self.allocate_float_register()
            one_label = self.get_float_label(1.0)
            addr_reg = self.allocate_register()
            code.append(f"    la {addr_reg}, {one_label}")
            code.append(f"    flw {step_reg}, 0({addr_reg})")
            self.free_register(addr_reg)

        var_addr_reg = self.get_variable_address(stmt.variable, code)
        code.append(f"    fsw {start_reg}, 0({var_addr_reg})")

        code.append("    addi sp, sp, -12")
        code.append(f"    fsw {end_reg}, 0(sp)")
        code.append(f"    fsw {step_reg}, 4(sp)")
        code.append(f"    sw {var_addr_reg}, 8(sp)")
        self.free_float_register(start_reg)
        self.free_float_register(end_reg)
        self.free_float_register(step_reg)
        self.free_register(var_addr_reg)

        loop_start = self.new_label("for_loop")
        loop_end = self.new_label("for_end")

        code.append(f"{loop_start}:")

        addr_reg = self.allocate_register()
        cur_reg = self.allocate_float_register()
        end_f_reg = self.allocate_float_register()
        step_f_reg = self.allocate_float_register()
        fz = self.allocate_float_register()
        code.append("    lw {}, 8(sp)".format(addr_reg))
        code.append(f"    flw {cur_reg}, 0({addr_reg})")
        code.append("    flw {}, 0(sp)".format(end_f_reg))
        code.append("    flw {}, 4(sp)".format(step_f_reg))
        zero_lab = self.get_float_label(0.0)
        addr_reg_zero = self.allocate_register()
        code.append(f"    la {addr_reg_zero}, {zero_lab}")
        code.append(f"    flw {fz}, 0({addr_reg_zero})")
        self.free_register(addr_reg_zero)

        neg_label = self.new_label("for_neg")
        check_label = self.new_label("for_check")
        cmp_reg = self.allocate_register()
        code.append("    flt.s {}, {}, {}".format(cmp_reg, step_f_reg, fz))
        code.append("    bnez {}, {}".format(cmp_reg, neg_label))
        code.append("    flt.s {}, {}, {}".format(cmp_reg, end_f_reg, cur_reg))
        code.append("    bnez {}, {}".format(cmp_reg, loop_end))
        code.append("    j {}".format(check_label))
        code.append("{}:".format(neg_label))
        code.append("    flt.s {}, {}, {}".format(cmp_reg, cur_reg, end_f_reg))
        code.append("    bnez {}, {}".format(cmp_reg, loop_end))
        code.append("{}:".format(check_label))

        self.free_float_register(end_f_reg)
        self.free_float_register(fz)
        self.free_register(cmp_reg)
        self.free_register(addr_reg)
        self.free_float_register(cur_reg)
        self.free_float_register(step_f_reg)

        code.extend(self.generate_statement(stmt.body))

        addr_reg2 = self.allocate_register()
        cur_reg2 = self.allocate_float_register()
        step_f_reg2 = self.allocate_float_register()
        code.append("    lw {}, 8(sp)".format(addr_reg2))
        code.append("    flw {}, 0({})".format(cur_reg2, addr_reg2))
        code.append("    flw {}, 4(sp)".format(step_f_reg2))
        code.append("    fadd.s {}, {}, {}".format(cur_reg2, cur_reg2, step_f_reg2))
        code.append("    fsw {}, 0({})".format(cur_reg2, addr_reg2))
        self.free_register(addr_reg2)
        self.free_float_register(cur_reg2)
        self.free_float_register(step_f_reg2)

        code.append(f"    j {loop_start}")
        code.append(f"{loop_end}:")

        code.append("    addi sp, sp, 12")

        return code

    def generate_goto(self, stmt: GotoStatement) -> List[str]:
        code = []
        target_label = self.line_labels.get(stmt.line_number, f"line_{stmt.line_number}")
        code.append(f"    j {target_label}")
        return code

    def generate_do(self, stmt: DoStatement) -> List[str]:
        code = []
        for line_num in range(stmt.start_line, stmt.end_line + 1):
            if line_num in self.line_labels:
                pass
        return code

    def generate_quit(self, stmt: QuitStatement) -> List[str]:
        code = []
        code.append("    li a7, 10")
        code.append("    ecall")
        return code

    def generate_expression(self, node: ASTNode, code: List[str]) -> Optional[str]:
        if isinstance(node, NumberNode):
            lab = self.get_float_label(node.value)
            addr_reg = self.allocate_register()
            freg = self.allocate_float_register()
            code.append(f"    la {addr_reg}, {lab}")
            code.append(f"    flw {freg}, 0({addr_reg})")
            self.free_register(addr_reg)
            return freg

        elif isinstance(node, StringNode):
            return None

        elif isinstance(node, VariableNode):
            var_addr_reg = self.get_variable_address(node, code)
            freg = self.allocate_float_register()
            code.append(f"    flw {freg}, 0({var_addr_reg})")
            self.free_register(var_addr_reg)
            return freg

        elif isinstance(node, BinaryOpNode):
            return self.generate_binary_op(node, code)

        elif isinstance(node, UnaryOpNode):
            return self.generate_unary_op(node, code)

        elif isinstance(node, FunctionCallNode):
            return self.generate_function_call(node, code)

        else:
            freg = self.allocate_float_register()
            lab = self.get_float_label(0.0)
            addr_reg = self.allocate_register()
            code.append(f"    la {addr_reg}, {lab}")
            code.append(f"    flw {freg}, 0({addr_reg})")
            self.free_register(addr_reg)
            return freg

    def _cmp_to_float(self, code: List[str], int_reg: str) -> str:
        result_f = self.allocate_float_register()
        code.append(f"    fcvt.s.w {result_f}, {int_reg}")
        return result_f

    def generate_binary_op(self, node: BinaryOpNode, code: List[str]) -> Optional[str]:
        left_reg = self.generate_expression(node.left, code)
        right_reg = self.generate_expression(node.right, code)

        if node.op == TokenType.PLUS:
            code.append(f"    fadd.s {left_reg}, {left_reg}, {right_reg}")
            self.free_float_register(right_reg)
            return left_reg
        elif node.op == TokenType.MINUS:
            code.append(f"    fsub.s {left_reg}, {left_reg}, {right_reg}")
            self.free_float_register(right_reg)
            return left_reg
        elif node.op == TokenType.MULTIPLY:
            code.append(f"    fmul.s {left_reg}, {left_reg}, {right_reg}")
            self.free_float_register(right_reg)
            return left_reg
        elif node.op == TokenType.DIVIDE:
            code.append(f"    fdiv.s {left_reg}, {left_reg}, {right_reg}")
            self.free_float_register(right_reg)
            return left_reg
        elif node.op == TokenType.POWER:
            exp_reg = self.allocate_register()
            code.append(f"    fcvt.w.s {exp_reg}, {right_reg}")
            base_reg = self.allocate_float_register()
            code.append(f"    fmv.s {base_reg}, {left_reg}")
            one_lab = self.get_float_label(1.0)
            addr = self.allocate_register()
            code.append(f"    la {addr}, {one_lab}")
            code.append(f"    flw {left_reg}, 0({addr})")
            self.free_register(addr)
            pow_loop = self.new_label("pow_loop")
            pow_end = self.new_label("pow_end")
            code.append(f"    blez {exp_reg}, {pow_end}")
            code.append(f"{pow_loop}:")
            code.append(f"    fmul.s {left_reg}, {left_reg}, {base_reg}")
            code.append(f"    addi {exp_reg}, {exp_reg}, -1")
            code.append(f"    bnez {exp_reg}, {pow_loop}")
            code.append(f"{pow_end}:")
            self.free_float_register(base_reg)
            self.free_register(exp_reg)
            self.free_float_register(right_reg)
            return left_reg
        elif node.op == TokenType.EQUAL:
            cmp_i = self.allocate_register()
            code.append(f"    feq.s {cmp_i}, {left_reg}, {right_reg}")
            result_reg = self._cmp_to_float(code, cmp_i)
            self.free_register(cmp_i)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.NOT_EQUAL:
            cmp_i = self.allocate_register()
            code.append(f"    feq.s {cmp_i}, {left_reg}, {right_reg}")
            code.append(f"    seqz {cmp_i}, {cmp_i}")
            result_reg = self._cmp_to_float(code, cmp_i)
            self.free_register(cmp_i)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.LESS:
            cmp_i = self.allocate_register()
            code.append(f"    flt.s {cmp_i}, {left_reg}, {right_reg}")
            result_reg = self._cmp_to_float(code, cmp_i)
            self.free_register(cmp_i)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.GREATER:
            cmp_i = self.allocate_register()
            code.append(f"    flt.s {cmp_i}, {right_reg}, {left_reg}")
            result_reg = self._cmp_to_float(code, cmp_i)
            self.free_register(cmp_i)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.LESS_EQUAL:
            cmp_i = self.allocate_register()
            code.append(f"    fle.s {cmp_i}, {left_reg}, {right_reg}")
            result_reg = self._cmp_to_float(code, cmp_i)
            self.free_register(cmp_i)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.GREATER_EQUAL:
            cmp_i = self.allocate_register()
            code.append(f"    fle.s {cmp_i}, {right_reg}, {left_reg}")
            result_reg = self._cmp_to_float(code, cmp_i)
            self.free_register(cmp_i)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.AND:
            fzero_lab = self.get_float_label(0.0)
            addr = self.allocate_register()
            fz = self.allocate_float_register()
            code.append(f"    la {addr}, {fzero_lab}")
            code.append(f"    flw {fz}, 0({addr})")
            t1 = self.allocate_register()
            t2 = self.allocate_register()
            code.append(f"    feq.s {t1}, {left_reg}, {fz}")
            code.append(f"    feq.s {t2}, {right_reg}, {fz}")
            code.append(f"    or {t1}, {t1}, {t2}")
            code.append(f"    seqz {t1}, {t1}")
            self.free_register(addr)
            self.free_float_register(fz)
            self.free_register(t2)
            result_reg = self._cmp_to_float(code, t1)
            self.free_register(t1)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        elif node.op == TokenType.OR:
            fzero_lab = self.get_float_label(0.0)
            addr = self.allocate_register()
            fz = self.allocate_float_register()
            code.append(f"    la {addr}, {fzero_lab}")
            code.append(f"    flw {fz}, 0({addr})")
            t1 = self.allocate_register()
            t2 = self.allocate_register()
            code.append(f"    feq.s {t1}, {left_reg}, {fz}")
            code.append(f"    feq.s {t2}, {right_reg}, {fz}")
            code.append(f"    and {t1}, {t1}, {t2}")
            code.append(f"    seqz {t1}, {t1}")
            self.free_register(addr)
            self.free_float_register(fz)
            self.free_register(t2)
            result_reg = self._cmp_to_float(code, t1)
            self.free_register(t1)
            self.free_float_register(left_reg)
            self.free_float_register(right_reg)
            return result_reg
        else:
            self.free_float_register(right_reg)
            return left_reg

    def generate_unary_op(self, node: UnaryOpNode, code: List[str]) -> Optional[str]:
        operand_reg = self.generate_expression(node.operand, code)
        result_reg = self.allocate_float_register()

        if node.op == TokenType.MINUS:
            code.append(f"    fneg.s {result_reg}, {operand_reg}")
        elif node.op == TokenType.NOT:
            fzero_lab = self.get_float_label(0.0)
            addr = self.allocate_register()
            fz = self.allocate_float_register()
            code.append(f"    la {addr}, {fzero_lab}")
            code.append(f"    flw {fz}, 0({addr})")
            ti = self.allocate_register()
            code.append(f"    feq.s {ti}, {operand_reg}, {fz}")
            self.free_register(addr)
            self.free_float_register(fz)
            self.free_float_register(result_reg)
            result_reg = self._cmp_to_float(code, ti)
            self.free_register(ti)
        else:
            code.append(f"    fmv.s {result_reg}, {operand_reg}")

        self.free_float_register(operand_reg)
        return result_reg

    def generate_function_call(self, node: FunctionCallNode, code: List[str]) -> Optional[str]:
        result_reg = self.allocate_float_register()
        self.used_functions.add(node.name)

        if len(node.args) == 0:
            if node.name == "FRAN":
                lab = self.get_float_label(0.0)
                addr = self.allocate_register()
                code.append(f"    la {addr}, {lab}")
                code.append(f"    flw {result_reg}, 0({addr})")
                self.free_register(addr)
            else:
                lab = self.get_float_label(0.0)
                addr = self.allocate_register()
                code.append(f"    la {addr}, {lab}")
                code.append(f"    flw {result_reg}, 0({addr})")
                self.free_register(addr)
        else:
            arg_reg = self.generate_expression(node.args[0], code)

            if node.name == "FABS":
                code.append(f"    fabs.s {result_reg}, {arg_reg}")
            elif node.name == "FSQT":
                code.append(f"    fsqrt.s {result_reg}, {arg_reg}")
            elif node.name in ("FSIN", "FCOS", "FLOG", "FEXP"):
                code.append(f"    fmv.s fa0, {arg_reg}")
                code.append(f"    jal ra, _focal_{node.name.lower()}")
                code.append(f"    fmv.s {result_reg}, fa0")
            else:
                code.append(f"    fmv.s {result_reg}, {arg_reg}")

            self.free_float_register(arg_reg)

        return result_reg

    def generate_helpers(self) -> List[str]:
        lines = []
        helpers = set()
        if "FSIN" in self.used_functions:
            helpers.add("sin")
        if "FCOS" in self.used_functions:
            helpers.add("cos")
        if "FEXP" in self.used_functions:
            helpers.add("exp")
        if "FLOG" in self.used_functions:
            helpers.add("log")

        if "sin" in helpers:
            lines.extend(self._helper_sin())
        if "cos" in helpers:
            lines.extend(self._helper_cos())
        if "exp" in helpers:
            lines.extend(self._helper_exp())
        if "log" in helpers:
            lines.extend(self._helper_log())
        return lines

    def _helper_sin(self) -> List[str]:
        c1 = self.get_float_label(0.16666667)
        c2 = self.get_float_label(0.008333333)
        c3 = self.get_float_label(0.0001984127)
        lines = [
            "_focal_fsin:",
            "    fmv.s ft0, fa0",
            "    fmul.s ft1, ft0, ft0",
            "    fmul.s ft2, ft1, ft0",
            "    fmul.s ft3, ft2, ft1",
            "    fmul.s ft4, ft3, ft1",
            f"    la t0, {c1}",
            "    flw ft5, 0(t0)",
            "    fmul.s ft2, ft2, ft5",
            f"    la t0, {c2}",
            "    flw ft5, 0(t0)",
            "    fmul.s ft3, ft3, ft5",
            f"    la t0, {c3}",
            "    flw ft5, 0(t0)",
            "    fmul.s ft4, ft4, ft5",
            "    fsub.s ft0, ft0, ft2",
            "    fadd.s ft0, ft0, ft3",
            "    fsub.s ft0, ft0, ft4",
            "    fmv.s fa0, ft0",
            "    ret",
        ]
        return lines

    def _helper_cos(self) -> List[str]:
        c1 = self.get_float_label(0.5)
        c2 = self.get_float_label(0.041666667)
        c3 = self.get_float_label(0.0013888889)
        one = self.get_float_label(1.0)
        lines = [
            "_focal_fcos:",
            "    fmv.s ft0, fa0",
            "    fmul.s ft1, ft0, ft0",
            "    fmul.s ft2, ft1, ft1",
            "    fmul.s ft3, ft2, ft1",
            f"    la t0, {one}",
            "    flw ft4, 0(t0)",
            f"    la t0, {c1}",
            "    flw ft5, 0(t0)",
            "    fmul.s ft1, ft1, ft5",
            f"    la t0, {c2}",
            "    flw ft5, 0(t0)",
            "    fmul.s ft2, ft2, ft5",
            f"    la t0, {c3}",
            "    flw ft5, 0(t0)",
            "    fmul.s ft3, ft3, ft5",
            "    fsub.s ft4, ft4, ft1",
            "    fadd.s ft4, ft4, ft2",
            "    fsub.s ft4, ft4, ft3",
            "    fmv.s fa0, ft4",
            "    ret",
        ]
        return lines

    def _helper_exp(self) -> List[str]:
        c1 = self.get_float_label(0.5)
        c2 = self.get_float_label(0.16666667)
        c3 = self.get_float_label(0.041666667)
        c4 = self.get_float_label(0.008333333)
        one = self.get_float_label(1.0)
        lines = [
            "_focal_fexp:",
            "    fmv.s ft0, fa0",
            "    fmul.s ft1, ft0, ft0",
            "    fmul.s ft2, ft1, ft0",
            "    fmul.s ft3, ft2, ft0",
            "    fmul.s ft4, ft3, ft0",
            f"    la t0, {one}",
            "    flw ft5, 0(t0)",
            f"    la t0, {c1}",
            "    flw ft6, 0(t0)",
            "    fmul.s ft1, ft1, ft6",
            f"    la t0, {c2}",
            "    flw ft6, 0(t0)",
            "    fmul.s ft2, ft2, ft6",
            f"    la t0, {c3}",
            "    flw ft6, 0(t0)",
            "    fmul.s ft3, ft3, ft6",
            f"    la t0, {c4}",
            "    flw ft6, 0(t0)",
            "    fmul.s ft4, ft4, ft6",
            "    fadd.s ft5, ft5, ft0",
            "    fadd.s ft5, ft5, ft1",
            "    fadd.s ft5, ft5, ft2",
            "    fadd.s ft5, ft5, ft3",
            "    fadd.s ft5, ft5, ft4",
            "    fmv.s fa0, ft5",
            "    ret",
        ]
        return lines

    def _helper_log(self) -> List[str]:
        c1 = self.get_float_label(0.33333333)
        c2 = self.get_float_label(0.2)
        two = self.get_float_label(2.0)
        one = self.get_float_label(1.0)
        lines = [
            "_focal_flog:",
            "    fmv.s ft0, fa0",
            f"    la t0, {one}",
            "    flw ft1, 0(t0)",
            f"    la t0, {two}",
            "    flw ft2, 0(t0)",
            "    fsub.s ft3, ft0, ft1",
            "    fadd.s ft4, ft0, ft1",
            "    fdiv.s ft3, ft3, ft4",
            "    fmul.s ft4, ft3, ft3",
            "    fmul.s ft5, ft4, ft3",
            "    fmul.s ft6, ft5, ft4",
            f"    la t0, {c1}",
            "    flw ft7, 0(t0)",
            "    fmul.s ft5, ft5, ft7",
            f"    la t0, {c2}",
            "    flw ft7, 0(t0)",
            "    fmul.s ft6, ft6, ft7",
            "    fadd.s ft3, ft3, ft5",
            "    fadd.s ft3, ft3, ft6",
            "    fmul.s ft3, ft3, ft2",
            "    fmv.s fa0, ft3",
            "    ret",
        ]
        return lines

    def get_variable_address(self, variable: VariableNode, code: List[str]) -> str:
        reg = self.allocate_register()

        if variable.index is None:
            if variable.name not in self.variables:
                self.variables[variable.name] = self.next_memory_addr
                self.next_memory_addr += 4
            code.append(f"    la {reg}, var_{variable.name}")
        else:
            index_f = self.generate_expression(variable.index, code)
            index_i = self.allocate_register()
            code.append(f"    fcvt.w.s {index_i}, {index_f}")
            self.free_float_register(index_f)

            if variable.name not in self.arrays:
                self.arrays[variable.name] = self.next_memory_addr
                self.next_memory_addr += 400

            code.append(f"    la {reg}, arr_{variable.name}")
            code.append(f"    slli {index_i}, {index_i}, 2")
            code.append(f"    add {reg}, {reg}, {index_i}")
            self.free_register(index_i)

        return reg

    def get_string_label(self, string: str) -> str:
        if string not in self.string_labels:
            label = f"str_{len(self.strings)}"
            self.strings.append(string)
            self.string_labels[string] = label
        return self.string_labels[string]

    def get_float_label(self, value: float) -> str:
        k = _float_key(value)
        if k not in self.float_constants:
            label = f"float_{len(self.float_constants)}"
            self.float_constants[k] = (value, label)
        return self.float_constants[k][1]

    def allocate_register(self) -> str:
        for reg in self.available_regs:
            if not self.reg_usage[reg]:
                self.reg_usage[reg] = True
                return reg
        return 't6'

    def free_register(self, reg: Optional[str]):
        if reg and reg in self.reg_usage:
            self.reg_usage[reg] = False

    def allocate_float_register(self) -> str:
        for r in self.available_float_regs:
            if not self.float_reg_usage[r]:
                self.float_reg_usage[r] = True
                return r
        return "ft6"

    def free_float_register(self, reg: Optional[str]):
        if reg and reg in self.float_reg_usage:
            self.float_reg_usage[reg] = False

    def new_label(self, prefix: str) -> str:
        label = f"{prefix}_{self.label_counter}"
        self.label_counter += 1
        return label
