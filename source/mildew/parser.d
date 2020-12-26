module mildew.parser;

import std.conv: to, parse;
debug
{
    import std.stdio;
}

import mildew.exceptions: ScriptCompileException;
import mildew.lexer: Token;
import mildew.nodes;
import mildew.types: ScriptValue, ScriptObject, ScriptFunction;

private int unaryOpPrecedence(Token opToken)
{
    // see grammar.txt for explanation of magic constants
    switch(opToken.type)
    {
        // TODO handle ++, -- prefix
        case Token.Type.BIT_NOT: 
        case Token.Type.NOT:
        case Token.Type.PLUS:
        case Token.Type.DASH:
            return 17;
        default: 
            return 0;
    }
}

private int binaryOpPrecedence(Token opToken)
{
    // TODO handle keywords in and instanceof as 12 here

    // see grammar.txt for explanation of magic constants
    switch(opToken.type)
    {
        case Token.Type.LBRACKET:
        case Token.Type.DOT: 
        case Token.Type.LPAREN:
            return 20;
        case Token.Type.POW:
            return 16;
        case Token.Type.STAR: 
        case Token.Type.FSLASH: 
        case Token.Type.PERCENT:
            return 15;
        case Token.Type.PLUS: 
        case Token.Type.DASH:
            return 14;
        case Token.Type.BIT_LSHIFT: 
        case Token.Type.BIT_RSHIFT: 
        case Token.Type.BIT_URSHIFT:
            return 13;
        case Token.Type.LT: 
        case Token.Type.LE: 
        case Token.Type.GT: 
        case Token.Type.GE:
            return 12;
        case Token.Type.EQUALS: 
        case Token.Type.NEQUALS: 
        case Token.Type.STRICT_EQUALS: 
        case Token.Type.STRICT_NEQUALS:
            return 11;
        case Token.Type.BIT_AND:
            return 10;
        case Token.Type.BIT_XOR:
            return 9;
        case Token.Type.BIT_OR:
            return 8;
        case Token.Type.AND:
            return 7;
        case Token.Type.OR:
            return 6;
        case Token.Type.ASSIGN:
        case Token.Type.PLUS_ASSIGN:
        case Token.Type.DASH_ASSIGN:
            return 3;
        default:
            return 0;
    }
    // TODO null coalesce 5, terniary 4, yield 2, comma 1?
}

private bool isBinaryOpLeftAssociative(in Token opToken)
{
    switch(opToken.type)
    {
        case Token.Type.LBRACKET:
        case Token.Type.DOT: 
        case Token.Type.LPAREN:
            return true;
        case Token.Type.POW:
            return false;
        case Token.Type.STAR: 
        case Token.Type.FSLASH: 
        case Token.Type.PERCENT:
            return true;
        case Token.Type.PLUS: 
        case Token.Type.DASH:
            return true;
        case Token.Type.BIT_LSHIFT: 
        case Token.Type.BIT_RSHIFT: 
        case Token.Type.BIT_URSHIFT:
            return true;
        case Token.Type.LT: 
        case Token.Type.LE: 
        case Token.Type.GT: 
        case Token.Type.GE:
            return true;
        case Token.Type.EQUALS: 
        case Token.Type.NEQUALS: 
        case Token.Type.STRICT_EQUALS: 
        case Token.Type.STRICT_NEQUALS:
            return true;
        case Token.Type.BIT_AND:
            return true;
        case Token.Type.BIT_XOR:
            return true;
        case Token.Type.BIT_OR:
            return true;
        case Token.Type.AND:
            return true;
        case Token.Type.OR:
            return true;
        case Token.Type.ASSIGN:
        case Token.Type.PLUS_ASSIGN:
        case Token.Type.DASH_ASSIGN:
            return false;
        default:
            return false;
    }   
}

/// parser
struct Parser
{
    /// ctor
    this(Token[] tokens)
    {
        _tokens = tokens;
        nextToken(); // prime
    }

    /// program grammar rule and starting point
    BlockStatementNode parseProgram()
    {
        immutable lineNo = _currentToken.position.line;
        auto statements = parseStatements(Token.Type.EOF);
        return new BlockStatementNode(lineNo, statements);
    }

private:

    /// parses a single statement
    StatementNode parseStatement()
    {
        StatementNode statement;
        immutable lineNumber = _currentToken.position.line;
        // check for var declaration
        if(_currentToken.isKeyword("var") || _currentToken.isKeyword("let") || _currentToken.isKeyword("const"))
        {
            statement = parseVarDeclarationStatement();
        }
        // check for {} block
        else if(_currentToken.type == Token.Type.LBRACE)
        {
            nextToken();
            auto statements = parseStatements(Token.Type.RBRACE);
            nextToken();
            statement = new BlockStatementNode(lineNumber, statements);
        }
        // check for if statement
        else if(_currentToken.isKeyword("if"))
        {
            statement = parseIfStatement();
        }
        // check for while statement TODO check for label
        else if(_currentToken.isKeyword("while"))
        {
            statement = parseWhileStatement();
        }
        // check for do-while statement TODO check for label
        else if(_currentToken.isKeyword("do"))
        {
            statement = parseDoWhileStatement();
        }
        // check for for loop TODO check label
        else if(_currentToken.isKeyword("for"))
        {
            statement = parseForStatement();
        }
        // break statement?
        else if(_currentToken.isKeyword("break"))
        {
            statement = new BreakStatementNode(lineNumber);
            nextToken();
            // TODO support labels
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after break", _currentToken);
            nextToken();
        }
        // continue statement
        else if(_currentToken.isKeyword("continue"))
        {
            statement = new ContinueStatementNode(lineNumber);
            nextToken();
            // TODO support labels
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after continue", _currentToken);
            nextToken();
        }
        // return statement with optional expression
        else if(_currentToken.isKeyword("return"))
        {
            nextToken();
            Node expression = null;
            if(_currentToken.type != Token.Type.SEMICOLON)
                expression = parseExpression();
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after return", _currentToken);
            nextToken();
            statement = new ReturnStatementNode(lineNumber, expression);
        }
        else if(_currentToken.isKeyword("function"))
        {
            statement = parseFunctionDeclarationStatement();
        }
        else // for now has to be one expression followed by semicolon or EOF
        {
            if(_currentToken.type == Token.Type.SEMICOLON)
            {
                // empty statement
                statement = new ExpressionStatementNode(lineNumber, null);
                nextToken();
            }
            else 
            {
                auto expression = parseExpression();
                if(_currentToken.type != Token.Type.SEMICOLON && _currentToken.type != Token.Type.EOF)
                    throw new ScriptCompileException("Expected semicolon after expression", _currentToken);
                nextToken(); // eat semicolon
                statement = new ExpressionStatementNode(lineNumber, expression);
            }
        }
        return statement;
    }

    /// parse a single expression. See https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
    ///  for algorithm.
    Node parseExpression(int minPrec = 1)
    {
        debug import std.stdio: writeln;
        Node primaryLeft = parsePrimaryExpression();
        while(true)
        {
            auto opToken = _currentToken;
            immutable prec = opToken.binaryOpPrecedence;
            if(prec == 0)
                break;
            immutable isLeftAssoc = opToken.isBinaryOpLeftAssociative;
            immutable nextMinPrec = isLeftAssoc? prec + 1 : prec;
            nextToken();
            if(opToken.type == Token.Type.DOT)
            {
                auto right = parsePrimaryExpression();
                if(cast(VarAccessNode)right is null)
                    throw new ScriptCompileException("Object members must be valid identifiers", _currentToken);
                primaryLeft = new MemberAccessNode(primaryLeft, right);
            }
            else if(opToken.type == Token.Type.LBRACKET)
            {
                auto index = parseExpression();
                if(_currentToken.type != Token.Type.RBRACKET)
                    throw new ScriptCompileException("Missing ']'", _currentToken);
                nextToken();
                primaryLeft = new ArrayIndexNode(primaryLeft, index);
            }
            else if(opToken.type == Token.Type.LPAREN)
            {
                auto params = parseCommaSeparatedExpressions(Token.Type.RPAREN);
                nextToken();
                primaryLeft = new FunctionCallNode(primaryLeft, params);
            }
            else 
            {
                Node primaryRight = parseExpression(nextMinPrec);
                primaryLeft = new BinaryOpNode(opToken, primaryLeft, primaryRight);
            }
        }
        writeln(primaryLeft.toString());
        return primaryLeft;
    }

    Node parsePrimaryExpression()
    {
        Node left = null;
        if(_currentToken.unaryOpPrecedence > 0)
        {
            auto opToken = _currentToken;
            nextToken();
            left = parsePrimaryExpression();
            left = new UnaryOpNode(opToken, left);
            return left;
        }

        switch(_currentToken.type)
        {
            case Token.Type.LPAREN:
                nextToken();
                left = parseExpression();
                if(_currentToken.type != Token.Type.RPAREN)
                    throw new ScriptCompileException("Missing ')' in primary expression", _currentToken);
                nextToken();
                break;
            case Token.Type.LBRACE:
                left = parseObjectLiteral();
                break;
            case Token.Type.DOUBLE:
                left = new LiteralNode(_currentToken, ScriptValue(to!double(_currentToken.text)));
                nextToken();
                break;
            case Token.Type.INTEGER:
                left = new LiteralNode(_currentToken, ScriptValue(to!long(_currentToken.text)));
                nextToken();
                break;
            case Token.Type.STRING:
                left = new LiteralNode(_currentToken, ScriptValue(_currentToken.text));
                nextToken();
                break;
            case Token.Type.KEYWORD:
                if(_currentToken.text == "true" || _currentToken.text == "false")
                {
                    left = new LiteralNode(_currentToken, ScriptValue(to!bool(_currentToken.text)));
                    nextToken();
                }
                else if(_currentToken.text == "null")
                {
                    left = new LiteralNode(_currentToken, ScriptValue(null));
                    nextToken();
                }
                else if(_currentToken.text == "undefined")
                {
                    left = new LiteralNode(_currentToken, ScriptValue.UNDEFINED);
                    nextToken();
                }
                else if(_currentToken.text == "function") // function literal
                {
                    auto funcToken = _currentToken;
                    nextToken();
                    if(_currentToken.type != Token.Type.LPAREN)
                        throw new ScriptCompileException("Argument list expected after anonymous function", 
                            _currentToken);
                    nextToken();
                    auto name = "<anonymous function>";
                    string[] argNames = [];
                    while(_currentToken.type != Token.Type.RPAREN)
                    {
                        if(_currentToken.type != Token.Type.IDENTIFIER)
                            throw new ScriptCompileException("Argument list must be valid identifier", _currentToken);
                        argNames ~= _currentToken.text;
                        nextToken();
                        if(_currentToken.type == Token.Type.COMMA)
                            nextToken();
                        else if(_currentToken.type !=  Token.Type.RPAREN)
                            throw new ScriptCompileException("Missing ')' after argument list", _currentToken);
                    }
                    nextToken(); // eat the )
                    if(_currentToken.type != Token.Type.LBRACE)
                        throw new ScriptCompileException("Expected '{' before anonymous function body", _currentToken);
                    nextToken(); // eat the {
                    auto statements = parseStatements(Token.Type.RBRACE);
                    nextToken();
                    auto func = new ScriptFunction(name, argNames, statements);
                    left = new LiteralNode(funcToken, ScriptValue(func));
                }
                else if(_currentToken.text == "new")
                {
                    auto newToken = _currentToken;
                    nextToken();
                    auto expression = parseExpression();
                    if(cast(FunctionCallNode)expression is null)
                        throw new ScriptCompileException("Invalid new expression", newToken);
                    left = new NewExpressionNode(expression);                    
                }
                else
                    throw new ScriptCompileException("Unexpected keyword in primary expression", _currentToken);
                break;
                // TODO function
            case Token.Type.IDENTIFIER:
                left = new VarAccessNode(_currentToken);
                nextToken();
                break;
            case Token.Type.LBRACKET: // an array
            {
                nextToken(); // eat the [
                auto values = parseCommaSeparatedExpressions(Token.Type.RBRACKET);
                nextToken(); // eat the ]
                left = new ArrayLiteralNode(values);
                break;
            }
            default:
                throw new ScriptCompileException("Unexpected token in primary expression", _currentToken);
        }
        return left;
    }

    /// parses multiple statements until reaching stop
    StatementNode[] parseStatements(in Token.Type stop)
    {
        StatementNode[] statements;
        while(_currentToken.type != stop && _currentToken.type != Token.Type.EOF)
        {
            statements ~= parseStatement();
            // each statement parse should eat the semicolon or } so there's nothing to do here
        }
        return statements;
    }

    VarDeclarationStatementNode parseVarDeclarationStatement()
    {
        auto specifier = _currentToken;
        nextToken();
        auto expressions = parseCommaSeparatedExpressions(Token.Type.SEMICOLON);
        // make sure all expressions are valid BinaryOpNodes or VarAccessNodes
        foreach(expression; expressions)
        {
            if(auto node = cast(BinaryOpNode)expression)
            {
                if(!cast(VarAccessNode)node.leftNode)
                    throw new ScriptCompileException("Invalid assignment node", _currentToken);
            }
            else if(!cast(VarAccessNode)expression)
            {
                throw new ScriptCompileException("Invalid variable name in declaration", _currentToken);
            }
        }
        nextToken(); // eat semicolon
        return new VarDeclarationStatementNode(specifier, expressions);
    }

    IfStatementNode parseIfStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after if keyword", _currentToken);
        nextToken();
        auto condition = parseExpression();
        if(_currentToken.type != Token.Type.RPAREN)
            throw new ScriptCompileException("Expected ')' after if condition", _currentToken);
        nextToken();
        auto ifTrueStatement = parseStatement();
        StatementNode elseStatement = null;
        if(_currentToken.isKeyword("else"))
        {
            nextToken();
            elseStatement = parseStatement();
        }
        return new IfStatementNode(lineNumber, condition, ifTrueStatement, elseStatement);
    }

    WhileStatementNode parseWhileStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after while keyword", _currentToken);
        nextToken();
        auto condition = parseExpression();
        if(_currentToken.type != Token.Type.RPAREN)
            throw new ScriptCompileException("Expected ')' after while condition", _currentToken);
        nextToken();
        auto loopBody = parseStatement();
        return new WhileStatementNode(lineNumber, condition, loopBody);
    }

    DoWhileStatementNode parseDoWhileStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        nextToken();
        auto loopBody = parseStatement();
        if(!_currentToken.isKeyword("while"))
            throw new ScriptCompileException("Expected while keyword after do statement", _currentToken);
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' before do-while condition", _currentToken);
        nextToken();
        auto condition = parseExpression();
        if(_currentToken.type != Token.Type.RPAREN)
            throw new ScriptCompileException("Expected ')' after do-while condition", _currentToken);
        nextToken();
        if(_currentToken.type != Token.Type.SEMICOLON)
            throw new ScriptCompileException("Expected ';' after do-while statement", _currentToken);
        nextToken();
        return new DoWhileStatementNode(lineNumber, loopBody, condition);
    }

    ForStatementNode parseForStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after for keyword", _currentToken);
        nextToken();
        VarDeclarationStatementNode decl = null;
        if(_currentToken.type != Token.Type.SEMICOLON)
            decl = parseVarDeclarationStatement();
        else
            nextToken();
        Node condition = null;
        if(_currentToken.type != Token.Type.SEMICOLON)
        {
            condition = parseExpression();
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after for condition", _currentToken);
        }
        else
        {
            condition = new LiteralNode(_currentToken, ScriptValue(true));
        }
        nextToken();
        Node increment = null;
        if(_currentToken.type != Token.Type.RPAREN)
        {
            increment = parseExpression();
        }
        else
        {
            increment = new LiteralNode(_currentToken, ScriptValue(true));
        }
        if(_currentToken.type != Token.Type.RPAREN)
            throw new ScriptCompileException("Expected ')' before for loop body", _currentToken);
        nextToken();
        auto bodyNode = parseStatement();
        return new ForStatementNode(lineNumber, decl, condition, increment, bodyNode);
    }

    FunctionDeclarationStatementNode parseFunctionDeclarationStatement()
    {
        import std.algorithm: uniq, count;
        immutable lineNumber = _currentToken.position.line;
        nextToken();
        if(_currentToken.type != Token.Type.IDENTIFIER)
            throw new ScriptCompileException("Expected identifier after function keyword", _currentToken);
        string name = _currentToken.text;
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after function name", _currentToken);
        nextToken();
        string[] argNames = [];
        while(_currentToken.type != Token.Type.RPAREN)
        {
            if(_currentToken.type != Token.Type.IDENTIFIER)
                throw new ScriptCompileException("Function argument names must be valid identifiers", _currentToken);
            argNames ~= _currentToken.text;
            nextToken();
            if(_currentToken.type == Token.Type.COMMA)
                nextToken();
            else if(_currentToken.type != Token.Type.RPAREN)
                throw new ScriptCompileException("Function argument names must be separated by comma", _currentToken);
        }
        nextToken(); // eat the )

        // make sure there are no duplicate parameter names
        if(argNames.uniq.count != argNames.length)
            throw new ScriptCompileException("Function argument names must be unique", _currentToken);

        if(_currentToken.type != Token.Type.LBRACE)
            throw new ScriptCompileException("Function definition must begin with '{'", _currentToken);
        nextToken();
        auto statements = parseStatements(Token.Type.RBRACE);
        nextToken(); // eat the }
        return new FunctionDeclarationStatementNode(lineNumber, name, argNames, statements);
    }

    ObjectLiteralNode parseObjectLiteral()
    {
        nextToken(); // eat the {
        string[] keys = [];
        Node[] valueExpressions = [];
        while(_currentToken.type != Token.Type.RBRACE)
        {
            // first must be an identifier token or string literal token
            immutable idToken = _currentToken;
            if(_currentToken.type != Token.Type.IDENTIFIER && _currentToken.type != Token.Type.STRING
                && _currentToken.type != Token.Type.LABEL)
                throw new ScriptCompileException("Invalid key for object literal", _currentToken);
            keys ~= _currentToken.text;

            nextToken();
            // next must be a :
            if(idToken.type != Token.Type.LABEL)
            {
                if(_currentToken.type != Token.Type.COLON)
                    throw new ScriptCompileException("Expected ':' after key in object literal", _currentToken);
                nextToken();
            }
            // next can be any valid expression
            valueExpressions ~= parseExpression();
            // if next is not a comma it must be a closing brace to exit
            if(_currentToken.type == Token.Type.COMMA)
                nextToken();
            else if(_currentToken.type != Token.Type.RBRACE)
                throw new ScriptCompileException("Key value pairs must be separated by ','", _currentToken);
        }
        nextToken(); // eat the }
        if(keys.length != valueExpressions.length)
            throw new ScriptCompileException("Number of keys must match values in object literal", _currentToken);
        return new ObjectLiteralNode(keys, valueExpressions);
    }

    Node[] parseCommaSeparatedExpressions(in Token.Type stop)
    {
        Node[] expressions;

        while(_currentToken.type != stop && _currentToken.type != Token.Type.EOF)
        {
            auto expression = parseExpression();
            expressions ~= expression;
            if(_currentToken.type == Token.Type.COMMA)
                nextToken();
            else if(_currentToken.type != stop)
                throw new ScriptCompileException("Comma separated list items must be separated by ','", _currentToken);
        }

        return expressions;
    }

    void nextToken()
    {
        if(_tokenIndex >= _tokens.length)
            _currentToken = Token(Token.Type.EOF);
        else
            _currentToken = _tokens[_tokenIndex++];
    }

    Token[] _tokens;
    size_t _tokenIndex = 0;
    Token _currentToken;
    bool _inLoop = false;
}