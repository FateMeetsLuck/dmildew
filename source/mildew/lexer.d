module mildew.lexer;

import mildew.exceptions: ScriptCompileException;

import std.ascii; // temp until unicode support
import std.container.rbtree;
import std.conv: to;
import std.format: format;

/// Position of each token
struct Position
{
    /// line and column number (should start at 1)
    int line, column;

    string toString() const 
    {
        return format("line %s, column %s", line, column);
    }

    /// determines line and column number based on char that is read
    void advance(char ch)
    {
        if(ch == '\0')
        {
            return;
        }
        else if(ch == '\n')
        {
            ++line;
            column = 1;
        }
        else
        {
            ++column;
        }
    }
}

/// Tokens that make up the program
struct Token 
{
    /// Type of token enum
    enum Type 
    {
        EOF, KEYWORD, INTEGER, DOUBLE, STRING, IDENTIFIER, 
        NOT, AND, OR, GT, GE, LT, LE,
        EQUALS, NEQUALS, STRICT_EQUALS, STRICT_NEQUALS,
        ASSIGN, PLUS_ASSIGN, DASH_ASSIGN,
        PLUS, DASH, STAR, FSLASH, PERCENT, POW, DOT,
        INC, DEC, // ++ and --
        BIT_AND, BIT_XOR, BIT_OR, BIT_NOT, BIT_LSHIFT, BIT_RSHIFT, BIT_URSHIFT,
        LPAREN, RPAREN, LBRACE, RBRACE, LBRACKET, RBRACKET, 
        SEMICOLON, COMMA, LABEL, COLON, INVALID
    }

    /// for different types of integer literals
    enum NumLiteralFlag
    {
        NONE, BINARY, OCTAL, HEXADECIMAL
    }

    /// type of token
    Type type;
    /// position where token occurs
    Position position;
    /// optional text for keywords and identifiers
    string text;
    /// optional flag for integer literals
    NumLiteralFlag numLiteralFlag = NumLiteralFlag.NONE;

    string toString() const
    {
        string str = format("[%s", type.to!string);
        if(text != null)
            str ~= "|" ~ text;
        str ~= "]";
        return str;
    }

    ///  helps print nicer nodes
    string symbol() const
    {
        final switch(type)
        {
        case Type.EOF:
            return "\0";
        case Type.KEYWORD: case Type.INTEGER: case Type.DOUBLE: case Type.STRING: case Type.IDENTIFIER:
            return text;
        case Type.NOT: return "!";
        case Type.AND: return "&&";
        case Type.OR: return "||";
        case Type.GT: return ">";
        case Type.GE: return ">=";
        case Type.LT: return "<";
        case Type.LE: return "<=";
        case Type.EQUALS: return "==";
        case Type.NEQUALS: return "!=";
        case Type.STRICT_EQUALS: return "===";
        case Type.STRICT_NEQUALS: return "!==";
        case Type.ASSIGN: return "=";
        case Type.PLUS_ASSIGN: return "+=";
        case Type.DASH_ASSIGN: return "-=";
        case Type.PLUS: return "+";
        case Type.DASH: return "-";
        case Type.STAR: return "*";
        case Type.FSLASH: return "/";
        case Type.PERCENT: return "%";
        case Type.POW: return "**";
        case Type.DOT: return ".";
        case Type.INC: return "++";
        case Type.DEC: return "--"; 
        case Type.BIT_AND: return "&";
        case Type.BIT_XOR: return "^";
        case Type.BIT_OR: return "|";
        case Type.BIT_NOT: return "~";
        case Type.BIT_LSHIFT: return "<<";
        case Type.BIT_RSHIFT: return ">>";
        case Type.BIT_URSHIFT: return ">>>";
        case Type.LPAREN: return "(";
        case Type.RPAREN: return ")";
        case Type.LBRACE: return "{";
        case Type.RBRACE: return "}";
        case Type.LBRACKET: return "[";
        case Type.RBRACKET: return "]";
        case Type.SEMICOLON: return ";";
        case Type.COMMA: return ",";
        case Type.LABEL: return text ~ ":";
        case Type.COLON: return ":";
        case Type.INVALID: return "#";
        }
    }

    /// tests if a token is a specific keyword
    bool isKeyword(in string keyword)
    {
        return (type == Type.KEYWORD && text == keyword);
    }

    /// returns true if this is an assignment operator
    bool isAssignmentOperator()
    {
        return (type == Type.ASSIGN || type == Type.PLUS_ASSIGN || type == Type.DASH_ASSIGN);
    }

    /// for use with error throwing
    static Token createInvalidToken(in Position pos, in string text="")
    {
        auto token = Token(Token.Type.INVALID, pos, text);
        return token;
    }
}

private bool startsKeywordOrIdentifier(in char ch)
{
    // TODO support unicode by converting string to dchar
    return ch.isAlpha || ch == '_' || ch == '$';
}

private bool continuesKeywordOrIdentifier(in char ch)
{
    // TODO support unicode by converting string to dchar
    return ch.isAlphaNum || ch == '_' || ch == '$';
}

/// Lexes code and returns the individual tokens
struct Lexer 
{
public:
    /// constructor takes code as text to lex
    this(string code)
    {
        _text = code;
    }

    /// return tokens from lexing a file
    Token[] tokenize()
    {
        Token[] tokens = [];
        if (_text == "")
            return tokens;
        while(_index < _text.length)
        {
            // ignore white space
            while(currentChar.isWhite())
                advanceChar();
            if(currentChar.startsKeywordOrIdentifier)
                tokens ~= makeIdKwOrLabel();
            else if(currentChar.isDigit)
                tokens ~= makeIntOrDoubleToken();
            else if(currentChar == '\'' || currentChar == '"')
                tokens ~= makeStringToken();
            else if(currentChar == '>')
                tokens ~= makeRAngleBracketToken();
            else if(currentChar == '<')
                tokens ~= makeLAngleBracketToken();
            else if(currentChar == '=')
                tokens ~= makeEqualToken();
            else if(currentChar == '!')
                tokens ~= makeNotToken();
            else if(currentChar == '&')
                tokens ~= makeAndToken();
            else if(currentChar == '|')
                tokens ~= makeOrToken();
            else if(currentChar == '+')
                tokens ~= makePlusToken();
            else if(currentChar == '-')
                tokens ~= makeDashToken();
            else if(currentChar == '*')
                tokens ~= makeStarToken();
            else if(currentChar == '/')
                tokens = handleFSlash(tokens);
            else if(currentChar == '%')
                tokens ~= Token(Token.Type.PERCENT, _position);
            else if(currentChar == '^')
                tokens ~= Token(Token.Type.BIT_XOR, _position);
            else if(currentChar == '~')
                tokens ~= Token(Token.Type.BIT_NOT, _position);
            else if(currentChar == '(')
                tokens ~= Token(Token.Type.LPAREN, _position);
            else if(currentChar == ')')
                tokens ~= Token(Token.Type.RPAREN, _position);
            else if(currentChar == '{')
                tokens ~= Token(Token.Type.LBRACE, _position);
            else if(currentChar == '}')
                tokens ~= Token(Token.Type.RBRACE, _position);
            else if(currentChar == '[')
                tokens ~= Token(Token.Type.LBRACKET, _position);
            else if(currentChar == ']')
                tokens ~= Token(Token.Type.RBRACKET, _position);
            else if(currentChar == ';')
                tokens ~= Token(Token.Type.SEMICOLON, _position);
            else if(currentChar == ',')
                tokens ~= Token(Token.Type.COMMA, _position);
            else if(currentChar == '.')
                tokens ~= Token(Token.Type.DOT, _position);
            else if(currentChar == ':')
                tokens ~= Token(Token.Type.COLON, _position);
            else if(currentChar == '\0')
                tokens ~= Token(Token.Type.EOF, _position);
            else
                throw new ScriptCompileException("Invalid character " ~ currentChar, 
                    Token.createInvalidToken(_position, [currentChar]));
            advanceChar();
        }
        return tokens;
    }

    /// Hash table of keywords. Awkward but there's no other way to do it in the stdlib
    static immutable KEYWORDS = redBlackTree(
        "true", "false", "undefined", "null",
        "var", "let", "const", 
        "if", "else", "while", "do", "for",
        "switch", "case", "default",
        "break", "continue", "return", "function",
        "new"
    );

    /// AA of look up for escape chars based on character after \
    static immutable char[char] ESCAPE_CHARS;

    shared static this()
    {
        ESCAPE_CHARS = [
            'b': '\b', 'f': '\f', 'n': '\n', 'r': '\r', 't': '\t', 'v': '\v', 
            '0': '\0', '\'': '\'', '"': '"', '\\': '\\'
        ];
    }

private:

    void advanceChar()
    {
        ++_index;
        _position.advance(currentChar());
    }

    char currentChar()
    {
        if(_index < _text.length)
            return _text[_index];
        else
            return '\0';
    }

    char peekChar()
    {
        if(_index + 1 < _text.length)
            return _text[_index + 1];
        else
            return '\0';
    }

    Token makeIdKwOrLabel()
    {
        immutable start = _index;
        immutable startpos = _position;
        advanceChar();
        while(currentChar.continuesKeywordOrIdentifier)
            advanceChar();
        auto text = _text[start.._index];
        --_index; // UGLY but IDK what else to do
        // first check for keyword, that can't be a label
        if(text in KEYWORDS)
        {
            return Token(Token.Type.KEYWORD, startpos, text);
        }
        else if(peekChar == ':')
        {
            advanceChar();
            return Token(Token.Type.LABEL, startpos, text);
        }
        else
        {
            return Token(Token.Type.IDENTIFIER, startpos, text);
        }
    }

    Token makeIntOrDoubleToken()
    {
        immutable start = _index;
        immutable startpos = _position;
        auto dotCounter = 0;
        auto eCounter = 0;
        // TODO: read first two numbers and possibly consider 0x or 0b or 0o
        while(peekChar.isDigit || peekChar == '.' || peekChar.toLower == 'e')
        {
            advanceChar();
            if(currentChar == '.')
            {
                ++dotCounter;
                if(dotCounter > 1)
                    throw new ScriptCompileException("Too many decimals in number literal", 
                        Token.createInvalidToken(_position));
            }
            else if(currentChar.toLower == 'e')
            {
                ++eCounter;
                if(eCounter > 1)
                    throw new ScriptCompileException("Numbers can only have one exponent specifier", 
                        Token.createInvalidToken(_position));
                if(peekChar == '+' || peekChar == '-')
                    advanceChar();
                if(!peekChar.isDigit)
                    throw new ScriptCompileException("Exponent specifier must be followed by number", 
                        Token.createInvalidToken(_position));
            }
        }
        auto text = _text[start.._index+1];
        if(dotCounter == 0 && eCounter == 0)
            return Token(Token.Type.INTEGER, startpos, text);
        else
            return Token(Token.Type.DOUBLE, startpos, text);
    }

    Token makeStringToken()
    {
        immutable closeQuote = currentChar;
        auto startpos = _position;
        advanceChar();
        string text = "";
        while(currentChar != closeQuote)
        {
            if(currentChar == '\0')
                throw new ScriptCompileException("Missing close quote for string literal", 
                    Token.createInvalidToken(_position, text));
            else if(currentChar == '\n')
                throw new ScriptCompileException("Line breaks inside string literal are not allowed", 
                    Token.createInvalidToken(_position, text));
            else if(currentChar == '\\')
            {
                advanceChar();
                if(currentChar in ESCAPE_CHARS)
                    text ~= ESCAPE_CHARS[currentChar];
                else
                    throw new ScriptCompileException("Unknown escape character " ~ currentChar, 
                        Token.createInvalidToken(_position));
            }
            else
                text ~= currentChar;
            advanceChar();
        }
        return Token(Token.Type.STRING, startpos, text);
    }

    Token makeRAngleBracketToken()
    {
        auto startpos = _position;
        if(peekChar == '=')
        {
            advanceChar();
            return Token(Token.Type.GE, startpos);
        }
        else if(peekChar == '>')
        {
            advanceChar();
            if(peekChar == '>')
            {
                advanceChar();
                return Token(Token.Type.BIT_URSHIFT, startpos);
            }
            else
            {
                return Token(Token.Type.BIT_RSHIFT, startpos);
            }
        }
        else
        {
            return Token(Token.Type.GT, startpos);
        }
    }

    Token makeLAngleBracketToken()
    {
        auto startpos = _position;
        if(peekChar == '=')
        {
            advanceChar();
            return Token(Token.Type.LE, startpos);
        }
        else if(peekChar == '<')
        {
            advanceChar();
            return Token(Token.Type.BIT_LSHIFT, startpos);
        }
        else
        {
            return Token(Token.Type.LT, startpos);
        }
    }

    Token makeEqualToken()
    {
        auto startpos = _position;
        if(peekChar == '=')
        {
            advanceChar();
            if(peekChar == '=')
            {
                advanceChar();
                return Token(Token.Type.STRICT_EQUALS);
            }
            else
            {
                return Token(Token.Type.EQUALS, startpos);
            }
        }
        else
        {
            return Token(Token.Type.ASSIGN, startpos);
        }
    }

    Token makeNotToken()
    {
        auto startpos = _position;
        if(peekChar == '=')
        {
            advanceChar();
            if(peekChar == '=')
            {
                advanceChar();
                return Token(Token.Type.STRICT_NEQUALS, startpos);
            }
            else
            {
                return Token(Token.Type.NEQUALS, startpos);
            }
        }
        else
        {
            return Token(Token.Type.NOT, startpos);
        }
    }

    Token makeAndToken()
    {
        auto startpos = _position;
        if(peekChar == '&')
        {
            advanceChar();
            return Token(Token.Type.AND, startpos);
        }
        else
        {
            return Token(Token.Type.BIT_AND, startpos);
        }
    }

    Token makeOrToken()
    {
        auto startpos = _position;
        if(peekChar == '|')
        {
            advanceChar();
            return Token(Token.Type.OR, startpos);
        }
        else
        {
            return Token(Token.Type.BIT_OR, startpos);
        }
    }

    Token makePlusToken()
    {
        auto startpos = _position;
        if(peekChar == '+')
        {
            advanceChar();
            return Token(Token.Type.INC, startpos);
        }
        else if(peekChar == '=')
        {
            advanceChar();
            return Token(Token.Type.PLUS_ASSIGN, startpos);
        }
        else
        {
            return Token(Token.Type.PLUS, startpos);
        }
    }

    Token makeDashToken()
    {
        auto startpos = _position;
        if(peekChar == '-')
        {
            advanceChar();
            return Token(Token.Type.DEC, startpos);
        }
        else if(peekChar == '=')
        {
            advanceChar();
            return Token(Token.Type.DASH_ASSIGN, startpos);
        }
        else
        {
            return Token(Token.Type.DASH, startpos);
        }
    }

    Token makeStarToken()
    {
        auto startpos = _position;
        if(peekChar == '*')
        {
            advanceChar();
            return Token(Token.Type.POW, startpos);
        }
        else
        {
            return Token(Token.Type.STAR, startpos);
        }
    }

    Token[] handleFSlash(Token[] tokens)
    {
        if(peekChar == '*')
        {
            advanceChar();
            while(peekChar != '\0')
            {
                if(peekChar == '*')
                {
                    advanceChar();
                    if(peekChar == '/')
                        break;
                }
                advanceChar();
            }
            advanceChar();
        }
        else if(peekChar == '/')
        {
            advanceChar();
            while(peekChar != '\n' && peekChar != '\0')
            {
                advanceChar();
            }
        }
        else
        {
            tokens ~= Token(Token.Type.FSLASH, _position);
        }

        return tokens;
    }

    Position _position = {1, 1};
    string _text;
    size_t _index = 0;
}

unittest
{
    auto lexer = Lexer("1.2 34 5.e-99 'foo' ");
    auto tokens = lexer.tokenize();
    assert(tokens[0].type == Token.Type.DOUBLE);
    assert(tokens[1].type == Token.Type.INTEGER);
    assert(tokens[2].type == Token.Type.DOUBLE);
    assert(tokens[3].type == Token.Type.STRING && tokens[3].text == "foo");
    // TODO complete unit tests of every token type
}