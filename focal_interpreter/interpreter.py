
import math
import random
from typing import Dict, Optional, List, Any
from focal_interpreter.lexer import TokenType
from focal_interpreter.parser import (
    ASTNode, NumberNode, StringNode, VariableNode, BinaryOpNode,
    UnaryOpNode, FunctionCallNode, SetStatement, TypeStatement,
    AskStatement, IfStatement, ForStatement, GotoStatement,
    DoStatement, QuitStatement, ProgramLine
)


class Interpreter:

    def __init__(self):
        self.variables: Dict[str, Any] = {}
        self.arrays: Dict[str, List[float]] = {}
        self.program_lines: Dict[int, ProgramLine] = {}
        self.current_line: Optional[int] = None
        self.should_quit = False
        self.output_buffer = []

    def interpret(self, program: List[ProgramLine]):
        for line in program:
            self.program_lines[line.line_number] = line

        sorted_lines = sorted(self.program_lines.keys())

        self.current_line = sorted_lines[0] if sorted_lines else None

        while self.current_line is not None and not self.should_quit:
            if self.current_line in self.program_lines:
                line = self.program_lines[self.current_line]
                previous_line = self.current_line
                self.execute_statement(line.statement)

                if not self.should_quit and self.current_line == previous_line:
                    next_lines = [l for l in sorted_lines if l > self.current_line]
                    self.current_line = next_lines[0] if next_lines else None
            else:
                break

    def execute_statement(self, statement: ASTNode):
        if isinstance(statement, SetStatement):
            self.execute_set(statement)
        elif isinstance(statement, TypeStatement):
            self.execute_type(statement)
        elif isinstance(statement, AskStatement):
            self.execute_ask(statement)
        elif isinstance(statement, IfStatement):
            self.execute_if(statement)
        elif isinstance(statement, ForStatement):
            self.execute_for(statement)
        elif isinstance(statement, GotoStatement):
            self.execute_goto(statement)
        elif isinstance(statement, DoStatement):
            self.execute_do(statement)
        elif isinstance(statement, QuitStatement):
            self.execute_quit(statement)
        else:
            self.evaluate(statement)

    def execute_set(self, stmt: SetStatement):
        value = self.evaluate(stmt.expression)
        self.set_variable(stmt.variable, value)

    def execute_type(self, stmt: TypeStatement):
        output = []
        for item in stmt.items:
            value = self.evaluate(item)
            if isinstance(value, str):
                output.append(value)
            else:
                output.append(str(value))

        result = ''.join(output)
        self.output_buffer.append(result)
        print(result, end='')

    def execute_ask(self, stmt: AskStatement):
        try:
            value = input(stmt.prompt)
            num_value = float(value)
            self.set_variable(stmt.variable, num_value)
        except ValueError:
            self.set_variable(stmt.variable, 0.0)

    def execute_if(self, stmt: IfStatement):
        condition = self.evaluate(stmt.condition)

        if condition:
            if isinstance(stmt.action, int):
                self.current_line = stmt.action
            else:
                self.execute_statement(stmt.action)

    def execute_for(self, stmt: ForStatement):
        start = self.evaluate(stmt.start)
        end = self.evaluate(stmt.end)
        step = self.evaluate(stmt.step) if stmt.step else 1.0

        var_name = stmt.variable.name

        i = start
        if step > 0:
            while i <= end:
                self.set_variable(stmt.variable, i)
                self.execute_statement(stmt.body)
                i += step
        else:
            while i >= end:
                self.set_variable(stmt.variable, i)
                self.execute_statement(stmt.body)
                i += step

    def execute_goto(self, stmt: GotoStatement):
        self.current_line = stmt.line_number

    def execute_do(self, stmt: DoStatement):
        sorted_lines = sorted(self.program_lines.keys())
        start_idx = None
        end_idx = None

        for i, line_num in enumerate(sorted_lines):
            if line_num >= stmt.start_line and start_idx is None:
                start_idx = i
            if line_num <= stmt.end_line:
                end_idx = i

        if start_idx is not None and end_idx is not None:
            for i in range(start_idx, end_idx + 1):
                line = self.program_lines[sorted_lines[i]]
                self.execute_statement(line.statement)

    def execute_quit(self, stmt: QuitStatement):
        self.should_quit = True

    def set_variable(self, variable: VariableNode, value: float):
        if variable.index:
            index = int(self.evaluate(variable.index))
            if variable.name not in self.arrays:
                self.arrays[variable.name] = [0.0] * 100
            if 0 <= index < len(self.arrays[variable.name]):
                self.arrays[variable.name][index] = float(value)
        else:
            self.variables[variable.name] = float(value)

    def get_variable(self, variable: VariableNode) -> float:
        if variable.index:
            index = int(self.evaluate(variable.index))
            if variable.name in self.arrays:
                if 0 <= index < len(self.arrays[variable.name]):
                    return self.arrays[variable.name][index]
            return 0.0
        else:
            return self.variables.get(variable.name, 0.0)

    def evaluate(self, node: ASTNode) -> Any:
        if isinstance(node, NumberNode):
            return node.value

        if isinstance(node, StringNode):
            return node.value

        if isinstance(node, VariableNode):
            return self.get_variable(node)

        if isinstance(node, BinaryOpNode):
            return self.evaluate_binary_op(node)

        if isinstance(node, UnaryOpNode):
            return self.evaluate_unary_op(node)

        if isinstance(node, FunctionCallNode):
            return self.evaluate_function(node)

        return 0.0

    def evaluate_binary_op(self, node: BinaryOpNode) -> float:
        left = self.evaluate(node.left)
        right = self.evaluate(node.right)

        if node.op == TokenType.PLUS:
            return left + right
        elif node.op == TokenType.MINUS:
            return left - right
        elif node.op == TokenType.MULTIPLY:
            return left * right
        elif node.op == TokenType.DIVIDE:
            if right == 0:
                raise ZeroDivisionError("Division by zero")
            return left / right
        elif node.op == TokenType.POWER:
            return left ** right
        elif node.op == TokenType.EQUAL:
            return 1.0 if left == right else 0.0
        elif node.op == TokenType.NOT_EQUAL:
            return 1.0 if left != right else 0.0
        elif node.op == TokenType.LESS:
            return 1.0 if left < right else 0.0
        elif node.op == TokenType.GREATER:
            return 1.0 if left > right else 0.0
        elif node.op == TokenType.LESS_EQUAL:
            return 1.0 if left <= right else 0.0
        elif node.op == TokenType.GREATER_EQUAL:
            return 1.0 if left >= right else 0.0
        elif node.op == TokenType.AND:
            return 1.0 if (left != 0 and right != 0) else 0.0
        elif node.op == TokenType.OR:
            return 1.0 if (left != 0 or right != 0) else 0.0

        return 0.0

    def evaluate_unary_op(self, node: UnaryOpNode) -> float:
        operand = self.evaluate(node.operand)

        if node.op == TokenType.MINUS:
            return -operand
        elif node.op == TokenType.NOT:
            return 0.0 if operand != 0 else 1.0

        return operand

    def evaluate_function(self, node: FunctionCallNode) -> float:
        args = [self.evaluate(arg) for arg in node.args]

        if node.name == "FSQT":
            if args[0] < 0:
                raise ValueError("Square root of negative number")
            return math.sqrt(args[0])
        elif node.name == "FABS":
            return abs(args[0])
        elif node.name == "FEXP":
            return math.exp(args[0])
        elif node.name == "FLOG":
            if args[0] <= 0:
                raise ValueError("Logarithm of non-positive number")
            return math.log(args[0])
        elif node.name == "FSIN":
            return math.sin(args[0])
        elif node.name == "FCOS":
            return math.cos(args[0])
        elif node.name == "FATN":
            return math.atan(args[0])
        elif node.name == "FITR":
            return math.trunc(args[0])
        elif node.name == "FRND":
            return round(args[0])
        elif node.name == "FSTR":
            return str(args[0])
        elif node.name == "FVAL":
            try:
                return float(args[0])
            except:
                return 0.0
        elif node.name == "FRAN":
            return random.random()

        return 0.0
