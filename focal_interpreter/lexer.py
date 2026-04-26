
import re
from enum import Enum
from typing import List, Optional


class TokenType(Enum):
    NUMBER = "NUMBER"
    STRING = "STRING"
    IDENTIFIER = "IDENTIFIER"

    PLUS = "PLUS"
    MINUS = "MINUS"
    MULTIPLY = "MULTIPLY"
    DIVIDE = "DIVIDE"
    POWER = "POWER"

    EQUAL = "EQUAL"
    NOT_EQUAL = "NOT_EQUAL"
    LESS = "LESS"
    GREATER = "GREATER"
    LESS_EQUAL = "LESS_EQUAL"
    GREATER_EQUAL = "GREATER_EQUAL"

    AND = "AND"
    OR = "OR"
    NOT = "NOT"

    LPAREN = "LPAREN"
    RPAREN = "RPAREN"
    COMMA = "COMMA"
    COLON = "COLON"
    EXCLAMATION = "EXCLAMATION"

    SET = "SET"
    TYPE = "TYPE"
    ASK = "ASK"
    IF = "IF"
    FOR = "FOR"
    DO = "DO"
    GOTO = "GOTO"
    QUIT = "QUIT"
    RETURN = "RETURN"
    THEN = "THEN"

    FSQT = "FSQT"
    FABS = "FABS"
    FEXP = "FEXP"
    FLOG = "FLOG"
    FSIN = "FSIN"
    FCOS = "FCOS"
    FATN = "FATN"
    FITR = "FITR"
    FRND = "FRND"
    FSTR = "FSTR"
    FVAL = "FVAL"
    FRAN = "FRAN"

    NEWLINE = "NEWLINE"
    EOF = "EOF"
    COMMENT = "COMMENT"


class Token:
    def __init__(self, type: TokenType, value: str, line: int = 0, column: int = 0):
        self.type = type
        self.value = value
        self.line = line
        self.column = column
    
    def __repr__(self):
        return f"Token({self.type.name}, {self.value!r}, line={self.line})"


class Lexer:

    KEYWORDS = {
        'SET': TokenType.SET,
        'TYPE': TokenType.TYPE,
        'ASK': TokenType.ASK,
        'IF': TokenType.IF,
        'FOR': TokenType.FOR,
        'DO': TokenType.DO,
        'GOTO': TokenType.GOTO,
        'QUIT': TokenType.QUIT,
        'RETURN': TokenType.RETURN,
        'THEN': TokenType.THEN,
        'AND': TokenType.AND,
        'OR': TokenType.OR,
        'NOT': TokenType.NOT,
    }

    FUNCTIONS = {
        'FSQT': TokenType.FSQT,
        'FABS': TokenType.FABS,
        'FEXP': TokenType.FEXP,
        'FLOG': TokenType.FLOG,
        'FSIN': TokenType.FSIN,
        'FCOS': TokenType.FCOS,
        'FATN': TokenType.FATN,
        'FITR': TokenType.FITR,
        'FRND': TokenType.FRND,
        'FSTR': TokenType.FSTR,
        'FVAL': TokenType.FVAL,
        'FRAN': TokenType.FRAN,
    }
    
    def __init__(self, text: str):
        self.text = text
        self.pos = 0
        self.line = 1
        self.column = 1
        self.current_char = self.text[self.pos] if self.pos < len(self.text) else None
        self.at_line_start = True
    
    def error(self, message: str):
        raise Exception(f"Lexer error at line {self.line}, column {self.column}: {message}")
    
    def advance(self):
        if self.current_char == '\n':
            self.line += 1
            self.column = 1
            self.at_line_start = True
        else:
            self.column += 1
        
        self.pos += 1
        if self.pos >= len(self.text):
            self.current_char = None
        else:
            self.current_char = self.text[self.pos]
    
    def skip_whitespace(self):
        while self.current_char is not None and self.current_char.isspace() and self.current_char != '\n':
            self.advance()
    
    def skip_comment(self):
        while self.current_char is not None and self.current_char != '\n':
            self.advance()

    def read_number(self) -> str:
        result = ''
        has_dot = False
        
        while self.current_char is not None and (self.current_char.isdigit() or self.current_char == '.'):
            if self.current_char == '.':
                if has_dot:
                    break
                has_dot = True
            result += self.current_char
            self.advance()

        if self.current_char and self.current_char.upper() == 'E':
            result += self.current_char
            self.advance()
            if self.current_char in ('+', '-'):
                result += self.current_char
                self.advance()
            while self.current_char is not None and self.current_char.isdigit():
                result += self.current_char
                self.advance()
        
        return result

    def read_string(self) -> str:
        result = ''
        self.advance()

        while self.current_char is not None and self.current_char != '"':
            if self.current_char == '\\':
                self.advance()
                if self.current_char == 'n':
                    result += '\n'
                elif self.current_char == 't':
                    result += '\t'
                elif self.current_char == '\\':
                    result += '\\'
                elif self.current_char == '"':
                    result += '"'
                else:
                    result += self.current_char
            else:
                result += self.current_char
            self.advance()
        
        if self.current_char != '"':
            self.error("Unterminated string")

        self.advance()
        return result

    def read_identifier(self) -> str:
        result = ''
        while self.current_char is not None and (self.current_char.isalnum() or self.current_char == '_'):
            result += self.current_char
            self.advance()
        return result
    
    def peek(self, offset: int = 1) -> Optional[str]:
        pos = self.pos + offset
        if pos >= len(self.text):
            return None
        return self.text[pos]

    def tokenize(self) -> List[Token]:
        tokens = []
        
        while self.current_char is not None:
            if self.current_char.isspace():
                if self.current_char == '\n':
                    tokens.append(Token(TokenType.NEWLINE, '\n', self.line, self.column))
                self.advance()
                continue

            if self.current_char == ';' or (self.current_char == '*' and self.at_line_start):
                self.skip_comment()
                continue

            if self.current_char.isdigit() or (self.current_char == '.' and self.peek() and self.peek().isdigit()):
                start_line = self.line
                start_col = self.column
                value = self.read_number()
                tokens.append(Token(TokenType.NUMBER, value, start_line, start_col))
                self.at_line_start = False
                continue

            if self.current_char == '"':
                start_line = self.line
                start_col = self.column
                value = self.read_string()
                tokens.append(Token(TokenType.STRING, value, start_line, start_col))
                self.at_line_start = False
                continue

            if self.current_char == '<':
                start_line = self.line
                start_col = self.column
                self.advance()
                if self.current_char == '>':
                    self.advance()
                    tokens.append(Token(TokenType.NOT_EQUAL, '<>', start_line, start_col))
                elif self.current_char == '=':
                    self.advance()
                    tokens.append(Token(TokenType.LESS_EQUAL, '<=', start_line, start_col))
                else:
                    tokens.append(Token(TokenType.LESS, '<', start_line, start_col))
                self.at_line_start = False
                continue
            
            if self.current_char == '>':
                start_line = self.line
                start_col = self.column
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    tokens.append(Token(TokenType.GREATER_EQUAL, '>=', start_line, start_col))
                else:
                    tokens.append(Token(TokenType.GREATER, '>', start_line, start_col))
                self.at_line_start = False
                continue
            
            if self.current_char == '=':
                start_line = self.line
                start_col = self.column
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    tokens.append(Token(TokenType.EQUAL, '==', start_line, start_col))
                else:
                    tokens.append(Token(TokenType.EQUAL, '=', start_line, start_col))
                self.at_line_start = False
                continue
            
            if self.current_char == '!':
                start_line = self.line
                start_col = self.column
                self.advance()
                if self.current_char == '=':
                    self.advance()
                    tokens.append(Token(TokenType.NOT_EQUAL, '!=', start_line, start_col))
                else:
                    tokens.append(Token(TokenType.EXCLAMATION, '!', start_line, start_col))
                self.at_line_start = False
                continue

            if self.current_char == '+':
                tokens.append(Token(TokenType.PLUS, '+', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == '-':
                tokens.append(Token(TokenType.MINUS, '-', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == '*':
                start_line = self.line
                start_col = self.column
                self.advance()
                if self.current_char == '*':
                    self.advance()
                    tokens.append(Token(TokenType.POWER, '**', start_line, start_col))
                else:
                    tokens.append(Token(TokenType.MULTIPLY, '*', start_line, start_col))
                self.at_line_start = False
                continue
            
            if self.current_char == '/':
                tokens.append(Token(TokenType.DIVIDE, '/', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == '^':
                tokens.append(Token(TokenType.POWER, '^', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue

            if self.current_char == '(':
                tokens.append(Token(TokenType.LPAREN, '(', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == ')':
                tokens.append(Token(TokenType.RPAREN, ')', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == ',':
                tokens.append(Token(TokenType.COMMA, ',', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == ':':
                tokens.append(Token(TokenType.COLON, ':', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue

            if self.current_char == '&':
                tokens.append(Token(TokenType.AND, '&', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue
            
            if self.current_char == '~':
                tokens.append(Token(TokenType.NOT, '~', self.line, self.column))
                self.advance()
                self.at_line_start = False
                continue

            if self.current_char.isalpha() or self.current_char == '_':
                start_line = self.line
                start_col = self.column
                identifier = self.read_identifier()

                if identifier.upper() in self.KEYWORDS:
                    tokens.append(Token(self.KEYWORDS[identifier.upper()], identifier.upper(), start_line, start_col))
                elif identifier.upper() in self.FUNCTIONS:
                    tokens.append(Token(self.FUNCTIONS[identifier.upper()], identifier.upper(), start_line, start_col))
                else:
                    tokens.append(Token(TokenType.IDENTIFIER, identifier, start_line, start_col))
                self.at_line_start = False
                continue

            self.error(f"Unexpected character: {self.current_char!r}")
        
        tokens.append(Token(TokenType.EOF, '', self.line, self.column))
        return tokens
