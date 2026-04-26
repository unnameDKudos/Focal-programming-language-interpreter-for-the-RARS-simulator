
from typing import List, Optional, Union
from focal_interpreter.lexer import Token, TokenType


class ASTNode:
    pass


class NumberNode(ASTNode):
    def __init__(self, value: float):
        self.value = value
    
    def __repr__(self):
        return f"Number({self.value})"


class StringNode(ASTNode):
    def __init__(self, value: str):
        self.value = value
    
    def __repr__(self):
        return f"String({self.value!r})"


class VariableNode(ASTNode):
    def __init__(self, name: str, index: Optional[ASTNode] = None):
        self.name = name
        self.index = index
    
    def __repr__(self):
        if self.index:
            return f"Variable({self.name}[{self.index}])"
        return f"Variable({self.name})"


class BinaryOpNode(ASTNode):
    def __init__(self, left: ASTNode, op: TokenType, right: ASTNode):
        self.left = left
        self.op = op
        self.right = right
    
    def __repr__(self):
        return f"BinaryOp({self.left} {self.op.name} {self.right})"


class UnaryOpNode(ASTNode):
    def __init__(self, op: TokenType, operand: ASTNode):
        self.op = op
        self.operand = operand
    
    def __repr__(self):
        return f"UnaryOp({self.op.name} {self.operand})"


class FunctionCallNode(ASTNode):
    def __init__(self, name: str, args: List[ASTNode]):
        self.name = name
        self.args = args
    
    def __repr__(self):
        return f"Function({self.name}({', '.join(map(str, self.args))}))"


class SetStatement(ASTNode):
    def __init__(self, variable: VariableNode, expression: ASTNode):
        self.variable = variable
        self.expression = expression
    
    def __repr__(self):
        return f"SET {self.variable} = {self.expression}"


class TypeStatement(ASTNode):
    def __init__(self, items: List[ASTNode]):
        self.items = items
    
    def __repr__(self):
        return f"TYPE {self.items}"


class AskStatement(ASTNode):
    def __init__(self, variable: VariableNode, prompt: str):
        self.variable = variable
        self.prompt = prompt
    
    def __repr__(self):
        return f"ASK {self.variable}, {self.prompt!r}"


class IfStatement(ASTNode):
    def __init__(self, condition: ASTNode, action: Union[ASTNode, int]):
        self.condition = condition
        self.action = action
    
    def __repr__(self):
        return f"IF {self.condition} THEN {self.action}"


class ForStatement(ASTNode):
    def __init__(self, variable: VariableNode, start: ASTNode, end: ASTNode, 
                 step: Optional[ASTNode], body: ASTNode):
        self.variable = variable
        self.start = start
        self.end = end
        self.step = step
        self.body = body
    
    def __repr__(self):
        step_str = f", {self.step}" if self.step else ""
        return f"FOR {self.variable}={self.start},{self.end}{step_str} DO {self.body}"


class GotoStatement(ASTNode):
    def __init__(self, line_number: int):
        self.line_number = line_number
    
    def __repr__(self):
        return f"GOTO {self.line_number}"


class DoStatement(ASTNode):
    def __init__(self, start_line: int, end_line: int):
        self.start_line = start_line
        self.end_line = end_line
    
    def __repr__(self):
        return f"DO {self.start_line},{self.end_line}"


class QuitStatement(ASTNode):
    def __repr__(self):
        return "QUIT"


class ProgramLine(ASTNode):
    def __init__(self, line_number: int, statement: ASTNode):
        self.line_number = line_number
        self.statement = statement
    
    def __repr__(self):
        return f"{self.line_number}: {self.statement}"


class Parser:

    def __init__(self, tokens: List[Token]):
        self.tokens = tokens
        self.pos = 0
        self.current_token = self.tokens[self.pos] if self.tokens else None
    
    def error(self, message: str):
        if self.current_token:
            raise Exception(f"Parser error at line {self.current_token.line}: {message}")
        raise Exception(f"Parser error: {message}")
    
    def advance(self):
        self.pos += 1
        if self.pos < len(self.tokens):
            self.current_token = self.tokens[self.pos]
        else:
            self.current_token = None
    
    def expect(self, token_type: TokenType):
        if self.current_token and self.current_token.type == token_type:
            value = self.current_token.value
            self.advance()
            return value
        self.error(f"Expected {token_type.name}, got {self.current_token.type.name if self.current_token else 'EOF'}")
    
    def parse(self) -> List[ProgramLine]:
        program = []
        
        while self.current_token and self.current_token.type != TokenType.EOF:
            if self.current_token.type == TokenType.NEWLINE:
                self.advance()
                continue

            if self.current_token.type == TokenType.NUMBER:
                line_number = int(self.current_token.value)
                self.advance()
                if self.current_token and self.current_token.type == TokenType.COLON:
                    self.advance()

                statement = self.parse_statement()
                program.append(ProgramLine(line_number, statement))
            else:
                self.advance()
        
        return program
    
    def parse_statement(self) -> ASTNode:
        if not self.current_token:
            self.error("Unexpected end of input")
        
        token_type = self.current_token.type
        
        if token_type == TokenType.SET:
            return self.parse_set()
        elif token_type == TokenType.TYPE:
            return self.parse_type()
        elif token_type == TokenType.ASK:
            return self.parse_ask()
        elif token_type == TokenType.IF:
            return self.parse_if()
        elif token_type == TokenType.FOR:
            return self.parse_for()
        elif token_type == TokenType.GOTO:
            return self.parse_goto()
        elif token_type == TokenType.DO:
            return self.parse_do()
        elif token_type == TokenType.QUIT:
            return self.parse_quit()
        else:
            return self.parse_expression()

    def parse_set(self) -> SetStatement:
        self.expect(TokenType.SET)
        variable = self.parse_variable()
        self.expect(TokenType.EQUAL)
        expression = self.parse_expression()
        return SetStatement(variable, expression)

    def parse_type(self) -> TypeStatement:
        self.expect(TokenType.TYPE)
        items = []
        
        while self.current_token and self.current_token.type not in (TokenType.NEWLINE, TokenType.EOF):
            if self.current_token.type == TokenType.COMMA:
                self.advance()
                continue
            items.append(self.parse_type_item())
        
        return TypeStatement(items)

    def parse_type_item(self) -> ASTNode:
        if self.current_token.type == TokenType.EXCLAMATION:
            self.advance()
            return StringNode("\n")
        elif self.current_token.type == TokenType.STRING:
            value = self.current_token.value
            self.advance()
            return StringNode(value)
        else:
            return self.parse_expression()

    def parse_ask(self) -> AskStatement:
        self.expect(TokenType.ASK)
        variable = self.parse_variable()
        self.expect(TokenType.COMMA)
        prompt = self.expect(TokenType.STRING)
        return AskStatement(variable, prompt)

    def parse_if(self) -> IfStatement:
        self.expect(TokenType.IF)
        condition = self.parse_expression()
        
        if self.current_token.type == TokenType.DO:
            self.advance()
            action = self.parse_statement()
        elif self.current_token.type == TokenType.THEN:
            self.advance()
            line_number = int(self.expect(TokenType.NUMBER))
            action = line_number
        elif self.current_token.type == TokenType.GOTO:
            self.advance()
            line_number = int(self.expect(TokenType.NUMBER))
            action = line_number
        else:
            self.error("Expected DO, THEN, or GOTO after IF condition")
        
        return IfStatement(condition, action)

    def parse_for(self) -> ForStatement:
        self.expect(TokenType.FOR)
        variable = self.parse_variable()
        self.expect(TokenType.EQUAL)
        start = self.parse_expression()
        self.expect(TokenType.COMMA)
        end = self.parse_expression()
        
        step = None
        if self.current_token and self.current_token.type == TokenType.COMMA:
            self.advance()
            step = self.parse_expression()
        
        self.expect(TokenType.DO)
        body = self.parse_statement()
        
        return ForStatement(variable, start, end, step, body)

    def parse_goto(self) -> GotoStatement:
        self.expect(TokenType.GOTO)
        line_number = int(self.expect(TokenType.NUMBER))
        return GotoStatement(line_number)

    def parse_do(self) -> DoStatement:
        self.expect(TokenType.DO)
        start_line = int(self.expect(TokenType.NUMBER))
        self.expect(TokenType.COMMA)
        end_line = int(self.expect(TokenType.NUMBER))
        return DoStatement(start_line, end_line)

    def parse_quit(self) -> QuitStatement:
        self.expect(TokenType.QUIT)
        return QuitStatement()

    def parse_variable(self) -> VariableNode:
        if self.current_token.type != TokenType.IDENTIFIER:
            self.error("Expected identifier")
        
        name = self.current_token.value.upper()
        self.advance()
        
        index = None
        if self.current_token and self.current_token.type == TokenType.LPAREN:
            self.advance()
            index = self.parse_expression()
            self.expect(TokenType.RPAREN)
        
        return VariableNode(name, index)

    def parse_expression(self) -> ASTNode:
        return self.parse_logical_or()

    def parse_logical_or(self) -> ASTNode:
        node = self.parse_logical_and()
        
        while self.current_token and self.current_token.type in (TokenType.OR,):
            op = self.current_token.type
            self.advance()
            node = BinaryOpNode(node, op, self.parse_logical_and())
        
        return node

    def parse_logical_and(self) -> ASTNode:
        node = self.parse_comparison()
        
        while self.current_token and self.current_token.type in (TokenType.AND,):
            op = self.current_token.type
            self.advance()
            node = BinaryOpNode(node, op, self.parse_comparison())
        
        return node

    def parse_comparison(self) -> ASTNode:
        node = self.parse_additive()
        
        if self.current_token and self.current_token.type in (
            TokenType.EQUAL, TokenType.NOT_EQUAL, TokenType.LESS,
            TokenType.GREATER, TokenType.LESS_EQUAL, TokenType.GREATER_EQUAL
        ):
            op = self.current_token.type
            self.advance()
            node = BinaryOpNode(node, op, self.parse_additive())
        
        return node

    def parse_additive(self) -> ASTNode:
        node = self.parse_multiplicative()
        
        while self.current_token and self.current_token.type in (TokenType.PLUS, TokenType.MINUS):
            op = self.current_token.type
            self.advance()
            node = BinaryOpNode(node, op, self.parse_multiplicative())
        
        return node

    def parse_multiplicative(self) -> ASTNode:
        node = self.parse_power()
        
        while self.current_token and self.current_token.type in (TokenType.MULTIPLY, TokenType.DIVIDE):
            op = self.current_token.type
            self.advance()
            node = BinaryOpNode(node, op, self.parse_power())
        
        return node

    def parse_power(self) -> ASTNode:
        node = self.parse_unary()
        
        while self.current_token and self.current_token.type == TokenType.POWER:
            op = self.current_token.type
            self.advance()
            node = BinaryOpNode(node, op, self.parse_unary())
        
        return node

    def parse_unary(self) -> ASTNode:
        if self.current_token and self.current_token.type in (TokenType.MINUS, TokenType.NOT):
            op = self.current_token.type
            self.advance()
            return UnaryOpNode(op, self.parse_unary())
        
        return self.parse_primary()

    def parse_primary(self) -> ASTNode:
        if not self.current_token:
            self.error("Unexpected end of input")

        if self.current_token.type == TokenType.NUMBER:
            value = float(self.current_token.value)
            self.advance()
            return NumberNode(value)

        if self.current_token.type == TokenType.STRING:
            value = self.current_token.value
            self.advance()
            return StringNode(value)

        if self.current_token.type in (
            TokenType.FSQT, TokenType.FABS, TokenType.FEXP, TokenType.FLOG,
            TokenType.FSIN, TokenType.FCOS, TokenType.FATN, TokenType.FITR,
            TokenType.FRND, TokenType.FSTR, TokenType.FVAL, TokenType.FRAN
        ):
            func_name = self.current_token.value
            self.advance()
            self.expect(TokenType.LPAREN)
            args = []
            if self.current_token.type != TokenType.RPAREN:
                args.append(self.parse_expression())
            self.expect(TokenType.RPAREN)
            return FunctionCallNode(func_name, args)

        if self.current_token.type == TokenType.IDENTIFIER:
            return self.parse_variable()

        if self.current_token.type == TokenType.LPAREN:
            self.advance()
            node = self.parse_expression()
            self.expect(TokenType.RPAREN)
            return node
        
        self.error(f"Unexpected token: {self.current_token.type.name}")
