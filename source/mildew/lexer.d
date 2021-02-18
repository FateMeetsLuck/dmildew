/**
This module implements the Token and Lexer structs

────────────────────────────────────────────────────────────────────────────────

Copyright (C) 2021 pillager86.rf.gd

This program is free software: you can redistribute it and/or modify it under 
the terms of the GNU General Public License as published by the Free Software 
Foundation, either version 3 of the License, or (at your option) any later 
version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY
WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A
PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with 
this program.  If not, see <https://www.gnu.org/licenses/>.
*/
module mildew.lexer;

import mildew.exceptions: ScriptCompileException;
import mildew.util.regex;

import std.ascii; // temp until unicode support
import std.container.rbtree;
import std.conv: to;
import std.format: format;
import std.utf: encode;

/**
 * This struct represents the line and column number of a token, starting at 1.
 */
struct Position
{
    /// Line and column number.
    int line, column;

    /// Returns a string representing the line and column number
    string toString() const 
    {
        return format("line %s, column %s", line, column);
    }

    /// Determines line and column number based on char that is read
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

/**
 * This struct represents a token, a fundamental building block of all scripts. The code of a script
 * is first separated by token so that the parser can analyze each token.
 */
struct Token 
{
    /**
     * The type of a token.
     */
    enum Type 
    {
        EOF, KEYWORD, INTEGER, DOUBLE, STRING, IDENTIFIER, REGEX,
        NOT, AND, OR, GT, GE, LT, LE,
        EQUALS, NEQUALS, STRICT_EQUALS, STRICT_NEQUALS,
        ASSIGN, PLUS_ASSIGN, DASH_ASSIGN,
        PLUS, DASH, STAR, FSLASH, PERCENT, POW, DOT,
        INC, DEC, // ++ and --
        BIT_AND, BIT_XOR, BIT_OR, BIT_NOT, BIT_LSHIFT, BIT_RSHIFT, BIT_URSHIFT,
        LPAREN, RPAREN, LBRACE, RBRACE, LBRACKET, RBRACKET, 
        SEMICOLON, COMMA, LABEL, QUESTION, COLON, ARROW,
        
        INVALID
    }

    /**
     * This enum is for literal value tokens that require special handling by the parser
     */
    enum LiteralFlag
    {
        NONE, BINARY, OCTAL, HEXADECIMAL, TEMPLATE_STRING
    }

    /// Type of token
    Type type;
    /// Position where token occurs
    Position position;
    /// Optional text for keywords and identifiers
    string text;
    /// Optional flag for integer literals.
    LiteralFlag literalFlag = LiteralFlag.NONE;

    /**
     * Returns a string representing the type of the token and the optional text if present.
     */
    string toString() const
    {
        string str = format("[%s", type.to!string);
        if(text != null)
            str ~= "|" ~ text;
        str ~= "]";
        return str;
    }

    /**
     * Returns a textual representation of the token as it was found in the original script source code.
     */
    string symbol() const
    {
        final switch(type)
        {
        case Type.EOF:
            return "\0";
        case Type.KEYWORD: case Type.INTEGER: case Type.DOUBLE: case Type.STRING: case Type.IDENTIFIER: case Type.REGEX:
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
        case Type.QUESTION: return "?";
        case Type.COLON: return ":";
        case Type.ARROW: return "=>";
        case Type.INVALID: return "#";
        }
    }

    /**
     * Returns true if a token is both a keyword and a specific keyword.
     */
    bool isKeyword(in string keyword) const
    {
        return (type == Type.KEYWORD && text == keyword);
    }

    /**
     * Checks for a specific identifier
     */
    bool isIdentifier(in string id) const 
    {
        return (type == Type.IDENTIFIER && text == id);
    }

    /**
     * Returns true if the token is an assignment operator such as =, +=, or -=, etc.
     */
    bool isAssignmentOperator()
    {
        return (type == Type.ASSIGN || type == Type.PLUS_ASSIGN || type == Type.DASH_ASSIGN);
    }

    /**
     * Generates an invalid token at the given position. This is used by the Lexer to throw
     * an exception that requires a token.
     */
    static Token createInvalidToken(in Position pos, in string text="")
    {
        auto token = Token(Token.Type.INVALID, pos, text);
        return token;
    }

    /**
     * Used by the parser
     */
    static Token createFakeToken(in Type t, in string txt)
    {
        Token tok;
        tok.type = t;
        tok.position = Position(0,0);
        tok.text = txt;
        return tok;
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

private bool charIsValidDigit(in char ch, in Token.LiteralFlag lflag)
{
    if(lflag == Token.LiteralFlag.NONE)
        return ch.isDigit || ch == '.' || ch == 'e';
    else if(lflag == Token.LiteralFlag.HEXADECIMAL)
        return ch.isDigit || (ch.toLower >= 'a' && ch.toLower <= 'f');
    else if(lflag == Token.LiteralFlag.OCTAL)
        return (ch >= '0' && ch <= '7');
    else if(lflag == Token.LiteralFlag.BINARY)
        return ch == '0' || ch == '1';
    return false;
}

/// Lexes code and returns the individual tokens
struct Lexer 
{
public:
    /// Constructor takes code as text to tokenize
    this(string code)
    {
        _text = code;
    }

    /// Returns tokens from lexing a string of code
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
                tokens ~= makeIdKwOrLabel(tokens);
            else if(currentChar.isDigit)
                tokens ~= makeIntOrDoubleToken();
            else if(currentChar == '\'' || currentChar == '"' || currentChar == '`')
                tokens ~= makeStringToken(tokens);
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
            else if(currentChar == '?')
                tokens ~= Token(Token.Type.QUESTION, _position);
            else if(currentChar == '\0')
                tokens ~= Token(Token.Type.EOF, _position);
            else
                throw new ScriptCompileException("Invalid character " ~ currentChar, 
                    Token.createInvalidToken(_position, [currentChar]));
            advanceChar();
        }
        return tokens;
    }

    /// Hash table of keywords
    static immutable KEYWORDS = redBlackTree(
        "true", "false", "undefined", "null",
        "var", "let", "const", 
        "if", "else", "while", "do", "for", "in",
        "switch", "case", "default",
        "break", "continue", "return", 
        "function", "class", "super", "extends",
        "new", "delete", "typeof", "instanceof",
        "throw", "try", "catch", "finally", 
        "yield"
    );

    /// AA of look up for escape chars based on character after \
    static immutable char[char] ESCAPE_CHARS;

    /// Initializes the associative array of escape chars
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

    bool canMakeRegex(Token[] tokens)
    {
        if(tokens.length == 0)
            return true;
        switch(tokens[$-1].type)
        {
        case Token.Type.IDENTIFIER:
        case Token.Type.INTEGER:
        case Token.Type.DOUBLE:
        case Token.Type.STRING:
        case Token.Type.RBRACKET:
        case Token.Type.RPAREN:
        case Token.Type.INC:
        case Token.Type.DEC:
            return false;
        case Token.Type.KEYWORD:
            switch(tokens[$-1].text)
            {
            case "null":
            case "true":
            case "false":
                return false;
            default:
                return true;
            }
        default:
            return true;
        }
    }

    Token makeIdKwOrLabel(Token[] tokens)
    {
        immutable start = _index;
        immutable startpos = _position;
        advanceChar();
        while(currentChar.continuesKeywordOrIdentifier)
            advanceChar();
        auto text = _text[start.._index];
        --_index; // UGLY but IDK what else to do
        // first check for keyword, that can't be a label

        // return is a special case after "."
        if(text == "return")
        {
            if(tokens.length > 0 && tokens[$-1].type == Token.Type.DOT)
                return Token(Token.Type.IDENTIFIER, startpos, text);
        }

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
        Token.LiteralFlag lflag = Token.LiteralFlag.NONE;
        if(peekChar.toLower == 'x')
        {
            lflag = Token.LiteralFlag.HEXADECIMAL;
            advanceChar();
        }
        else if(peekChar.toLower == 'o')
        {
            lflag = Token.LiteralFlag.OCTAL;
            advanceChar();
        }
        else if(peekChar.toLower == 'b')
        {
            lflag = Token.LiteralFlag.BINARY;
            advanceChar();
        }
        // if the lflag was set, the first char has to be 0
        if(lflag != Token.LiteralFlag.NONE && _text[start] != '0')
            throw new ScriptCompileException("Malformed integer literal", Token.createInvalidToken(startpos));
        
        // while(peekChar.isDigit || peekChar == '.' || peekChar.toLower == 'e')
        while(peekChar.charIsValidDigit(lflag))
        {
            advanceChar();
            if(lflag == Token.LiteralFlag.NONE)
            {
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
        }
        auto text = _text[start.._index+1];
        if(lflag != Token.LiteralFlag.NONE && text.length <= 2)
            throw new ScriptCompileException("Malformed hex/octal/binary integer", Token.createInvalidToken(startpos));
        Token resultToken;
        if(dotCounter == 0 && eCounter == 0)
            resultToken = Token(Token.Type.INTEGER, startpos, text);
        else
            resultToken = Token(Token.Type.DOUBLE, startpos, text);
        resultToken.literalFlag = lflag;
        return resultToken;
    }

    Token makeStringToken(ref Token[] previous)
    {
        immutable closeQuote = currentChar;
        auto startpos = _position;
        advanceChar();
        string text = "";
        bool escapeChars = true;
        if(previous.length >= 3)
        {
            if(previous[$-1].isIdentifier("raw") &&
               previous[$-2].type == Token.Type.DOT &&
               previous[$-3].isIdentifier("String"))
            {
                escapeChars = false;
                previous = previous[0.. $-3];
            }
        }
        Token.LiteralFlag lflag = Token.LiteralFlag.NONE;
        if(closeQuote == '`')
            lflag = Token.LiteralFlag.TEMPLATE_STRING;
        while(currentChar != closeQuote)
        {
            if(currentChar == '\0')
                throw new ScriptCompileException("Missing close quote for string literal", 
                    Token.createInvalidToken(_position, text));
            else if(currentChar == '\n' && lflag != Token.LiteralFlag.TEMPLATE_STRING)
                throw new ScriptCompileException("Line breaks inside regular string literals are not allowed", 
                    Token.createInvalidToken(_position, text));
            else if(currentChar == '\\' && escapeChars) // TODO handle \u0000 and \u00 sequences
            {
                advanceChar();
                if(currentChar in ESCAPE_CHARS)
                    text ~= ESCAPE_CHARS[currentChar];
                else if(currentChar == 'u')
                {
                    advanceChar();
                    string accum = "";
                    bool usingBraces = false;
                    int limitCounter;
                    immutable LIMIT = 4; // without the braces
                    if(currentChar == '{')
                    {
                        advanceChar();
                        usingBraces = true;
                    }
                    while(currentChar.charIsValidDigit(Token.LiteralFlag.HEXADECIMAL))
                    {
                        if(limitCounter >= LIMIT && !usingBraces)
                            break;
                        accum ~= currentChar;
                        advanceChar();
                        if(!usingBraces)
                            ++limitCounter;
                    }
                    if(currentChar == '}' && usingBraces)
                        advanceChar();
                    --_index;
                    try 
                    {
                        dchar result = cast(dchar)to!uint(accum, 16);
                        char[] buf;
                        encode(buf, result);
                        text ~= buf;
                    }
                    catch(Exception ex)
                    {
                        throw new ScriptCompileException("Invalid UTF sequence in \\u char", 
                            Token.createInvalidToken(_position, accum));
                    }
                }
                else if(currentChar == 'x')
                {
                    advanceChar();
                    string accum = "";
                    accum ~= currentChar;
                    advanceChar();
                    accum ~= currentChar;
                    try 
                    {
                        char result = cast(char)to!ubyte(accum, 16);
                        text ~= result;
                    }
                    catch(Exception ex)
                    {
                        throw new ScriptCompileException("Invalid hexadecimal number in \\x char",
                            Token.createInvalidToken(_position, accum));
                    }
                }
                else
                    throw new ScriptCompileException("Unknown escape character " ~ currentChar, 
                        Token.createInvalidToken(_position));
            }
            else
                text ~= currentChar;
            advanceChar();
        }
        auto tok = Token(Token.Type.STRING, startpos, text);
        tok.literalFlag = lflag;
        return tok;
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
        else if(peekChar == '>')
        {
            advanceChar();
            return Token(Token.Type.ARROW, startpos);
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
        else if(canMakeRegex(tokens))
        {
            string accum = "";
            auto startPos = _position;
            accum ~= currentChar;
            bool gettingFlags = false;
            advanceChar();
            while(currentChar)
            {
                if(!gettingFlags)
                {
                    if(currentChar == '\\')
                    {
                        accum ~= currentChar;
                        advanceChar();
                        if(currentChar)
                        {
                            accum ~= currentChar;
                            advanceChar();
                        }
                    }
                    else if(currentChar == '/')
                    {
                        accum ~= currentChar;
                        advanceChar();
                        gettingFlags = true;
                    }
                    else
                    {
                        accum ~= currentChar;
                        advanceChar();
                    }
                }
                else
                {
                    if(!isAlpha(currentChar))
                        break;
                    accum ~= currentChar;
                    advanceChar();
                }
            }
            --_index;
            bool valid;
            try 
            {
                auto extracted = extract(accum);
                valid = isValid(extracted[0], extracted[1]);
            }
            catch(Exception ex)
            {
                throw new ScriptCompileException("Malformed regex literal", Token.createInvalidToken(startPos, accum));
            }
            if(!valid)
                throw new ScriptCompileException("Invalid regex literal", Token.createInvalidToken(startPos, accum));
            tokens ~= Token(Token.Type.REGEX, startPos, accum);
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