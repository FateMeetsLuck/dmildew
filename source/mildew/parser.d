module mildew.parser;

import std.conv: to, parse;
debug
{
    import std.stdio;
}

import mildew.exceptions: ScriptCompileException;
import mildew.lexer: Token;
import mildew.nodes;
import mildew.types: ScriptValue;

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

    /// parse a single expression which could be a LiteralNode, UnaryOpNode, or BinaryOpNode
    Node parseExpression(int parentPrecedence = 0)
    {
        Node left = null;

        immutable unOpPrec = _currentToken.unaryOpPrecedence;
        if(unOpPrec != 0 && unOpPrec >= parentPrecedence)
        {
            auto opToken =  _currentToken;
            nextToken();
            auto operand = parseExpression(unOpPrec);
            left = new UnaryOpNode(opToken, operand);
        }
        else
        {
            left = parsePrimaryExpression();
        }

        // cheap hack to force right associativity on these ops
        if(_currentToken.type == Token.Type.POW || _currentToken.isAssignmentOperator)
        {
            immutable prec = _currentToken.binaryOpPrecedence;
            auto opToken = _currentToken;
            nextToken();
            auto right = parseExpression(prec);
            if(opToken.isAssignmentOperator)
            {
                if(cast(VarAccessNode)left is null)
                    throw new ScriptCompileException("Attempt to assign to lvalue", opToken);
                left = new VarAssignmentNode(opToken, cast(VarAccessNode)left, right);
            }
            else
                left = new BinaryOpNode(opToken, left, right);
        }

        // handle left-assoc binary ops according to priority
        // (shoutout to Immo Landwerth's Minsk project for this algorithm)
        while(true)
        {
            immutable prec = _currentToken.binaryOpPrecedence;
            if(prec == 0 || prec <= parentPrecedence)
                break;
            auto opToken = _currentToken;
            nextToken();
            if(opToken.type == Token.Type.LPAREN)
            {
                // left is already the function we want to call
                auto args = parseCommaSeparatedExpressions(Token.Type.RPAREN);
                nextToken(); // eat ')' and it is complete
                left = new FunctionCallNode(left, args);
            }
            else 
            {
                auto right = parseExpression(prec);
                left = new BinaryOpNode(opToken, left, right);
            }
        }

        return left;
    }

    Node parsePrimaryExpression()
    {
        Node left = null;
        switch(_currentToken.type)
        {
            case Token.Type.LPAREN:
                nextToken();
                left = parseExpression();
                if(_currentToken.type != Token.Type.RPAREN)
                    throw new ScriptCompileException("Missing ')' in primary expression", _currentToken);
                nextToken();
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
                    left = new LiteralNode(_currentToken, ScriptValue(to!bool(_currentToken.text)));
                else if(_currentToken.text == "null")
                    left = new LiteralNode(_currentToken, ScriptValue(null));
                else if(_currentToken.text == "undefined")
                    left = new LiteralNode(_currentToken, ScriptValue.UNDEFINED);
                else
                    throw new ScriptCompileException("Unexpected keyword in primary expression", _currentToken);
                nextToken();
                break;
                // TODO function
            case Token.Type.IDENTIFIER:
                left = new VarAccessNode(_currentToken);
                nextToken();
                break;
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
        // make sure all expressions are VarAccessNode or VarAssignmentNode
        foreach(expression; expressions)
        {
            if(cast(VarAccessNode)expression is null && cast(VarAssignmentNode)expression is null)
            {
                throw new ScriptCompileException("Invalid variable declaration " 
                    ~ typeid(expression).toString ~ " " ~ expression.toString, specifier);
            }
            else if(auto ass = cast(VarAssignmentNode)expression)
            {
                if(ass.assignOp.type != Token.Type.ASSIGN)
                    throw new ScriptCompileException("Invalid assignment operator in declaration", ass.assignOp);
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