/**
 * This module implements the Parser struct, which generates Nodes from tokens that are used internally.
 */
module mildew.parser;

import std.conv: to, parse;
debug
{
    import std.stdio;
}

import mildew.exceptions: ScriptCompileException;
import mildew.lexer: Token;
import mildew.nodes;
import mildew.types.any: ScriptAny;
import mildew.types.func: ScriptFunction;

private int unaryOpPrecedence(Token opToken, bool isPost = false)
{
    if(opToken.isKeyword("typeof"))
    {
        if(!isPost)
            return 17;
    }

    // see grammar.txt for explanation of magic constants
    switch(opToken.type)
    {
        // TODO handle ++, -- postfix
        case Token.Type.BIT_NOT: 
        case Token.Type.NOT:
        case Token.Type.PLUS:
        case Token.Type.DASH:
            if(!isPost)
                return 17;
            else
                return 0;
        case Token.Type.INC:
        case Token.Type.DEC:
            if(isPost)
                return 18;
            else
                return 17;
        default: 
            return 0;
    }
}

private int binaryOpPrecedence(Token opToken)
{
    // TODO handle keywords in as 12 here
    if(opToken.isKeyword("instanceof"))
        return 12;

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
        case Token.Type.QUESTION:
            return 4;
        case Token.Type.ASSIGN:
        case Token.Type.PLUS_ASSIGN:
        case Token.Type.DASH_ASSIGN:
            return 3;
        default:
            return 0;
    }
    // TODO null coalesce 5,yield 2, comma 1?
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
        case Token.Type.QUESTION:
            return false;
        case Token.Type.ASSIGN:
        case Token.Type.PLUS_ASSIGN:
        case Token.Type.DASH_ASSIGN:
            return false;
        default:
            return false;
    }   
}

private bool tokenBeginsLoops(const Token tok)
{
    return tok.type == Token.Type.LABEL 
        || tok.isKeyword("while")
        || tok.isKeyword("do")
        || tok.isKeyword("for");
}

/**
 * The parser is used by the interpreter to generate a syntax tree out of tokens.
 */
struct Parser
{
    /**
     * The constructor takes all tokens so that in the future, looking ahead for specific tokens
     * can allow support for lambdas and other complex language features.
     */
    this(Token[] tokens)
    {
        _tokens = tokens;
        nextToken(); // prime
    }

    /**
     * The main starting point. Also the "program" grammar rule. The generates a block statement
     * node where the interpreter iterates through each statement and executes it.
     */
    BlockStatementNode parseProgram()
    {
        immutable lineNo = _currentToken.position.line;
        auto statements = parseStatements(Token.Type.EOF);
        return new BlockStatementNode(lineNo, statements);
    }

package:

    /// parse a single expression. See https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
    /// for algorithm.
    Node parseExpression(int minPrec = 1)
    {      
        Node primaryLeft = null;

        immutable unOpPrec = _currentToken.unaryOpPrecedence;
        if(unOpPrec > minPrec)
        {
            auto opToken = _currentToken;
            nextToken();
            primaryLeft = parsePrimaryExpression();
            primaryLeft = new UnaryOpNode(opToken, primaryLeft);
        }
        else
        {
            primaryLeft = parsePrimaryExpression();
        }

        while(_currentToken.binaryOpPrecedence >= minPrec || _currentToken.unaryOpPrecedence(true) >= minPrec)
        {
            if(_currentToken.unaryOpPrecedence(true) >= minPrec)
            {
                // writeln("We must handle postfix " ~ _currentToken.symbol ~ " for " ~ primaryLeft.toString);
                primaryLeft = new PostfixOpNode(_currentToken, primaryLeft);
                nextToken();
            }
            else 
            {
                auto opToken = _currentToken;
                immutable prec = opToken.binaryOpPrecedence;
                immutable isLeftAssoc = opToken.isBinaryOpLeftAssociative;
                immutable nextMinPrec = isLeftAssoc? prec + 1 : prec;
                nextToken();
                if(opToken.type == Token.Type.QUESTION)
                {
                    // primaryLeft is our condition node
                    auto onTrue = parseExpression();
                    if(_currentToken.type != Token.Type.COLON)
                        throw new ScriptCompileException("Expected ':' in terniary operator expression", _currentToken);
                    nextToken();
                    auto onFalse = parseExpression();
                    primaryLeft = new TerniaryOpNode(primaryLeft, onTrue, onFalse);
                }
                else if(opToken.type == Token.Type.DOT)
                {
                    auto right = parsePrimaryExpression();
                    if(cast(VarAccessNode)right is null)
                        throw new ScriptCompileException("Object members must be valid identifiers", _currentToken);
                    if(unOpPrec != 0 && prec > unOpPrec)
                    {
                        auto uon = cast(UnaryOpNode)primaryLeft;
                        primaryLeft = new UnaryOpNode(uon.opToken, new MemberAccessNode(uon.operandNode, right));
                    }
                    else
                        primaryLeft = new MemberAccessNode(primaryLeft, right);
                }
                else if(opToken.type == Token.Type.LBRACKET)
                {
                    auto index = parseExpression();
                    if(_currentToken.type != Token.Type.RBRACKET)
                        throw new ScriptCompileException("Missing ']'", _currentToken);
                    nextToken();
                    if(unOpPrec != 0 && prec > unOpPrec)
                    {
                        auto uon = cast(UnaryOpNode)primaryLeft;
                        primaryLeft = new UnaryOpNode(uon.opToken, new ArrayIndexNode(uon.operandNode, index));
                    }
                    else
                        primaryLeft = new ArrayIndexNode(primaryLeft, index);
                }
                else if(opToken.type == Token.Type.LPAREN)
                {
                    auto params = parseCommaSeparatedExpressions(Token.Type.RPAREN);
                    nextToken();
                    if(unOpPrec != 0 && prec > unOpPrec)
                    {
                        auto uon = cast(UnaryOpNode)primaryLeft;
                        primaryLeft = new UnaryOpNode(uon.opToken, new FunctionCallNode(uon.operandNode, params));
                    }
                    else
                        primaryLeft = new FunctionCallNode(primaryLeft, params);
                }
                else 
                {
                    Node primaryRight = parseExpression(nextMinPrec);
                    primaryLeft = new BinaryOpNode(opToken, primaryLeft, primaryRight);
                }
            }
        }

        return primaryLeft;
    }

private:

    /// parses a single statement
    StatementNode parseStatement()
        in { assert(_loopStack >= 0); } do
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
            // TODO: peek two tokens ahead for a ':' to indicate whether or not this is an object literal expression
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
        // check for switch
        else if(_currentToken.isKeyword("switch"))
        {
            statement = parseSwitchStatement();
        }
        // check for loops
        else if(_currentToken.tokenBeginsLoops())
        {
            statement = parseLoopStatement();
        }
        // break statement?
        else if(_currentToken.isKeyword("break"))
        {
            if(_loopStack == 0 && _switchStack == 0)
                throw new ScriptCompileException("Break statements only allowed in loops or switch-case bodies", 
                    _currentToken);
            nextToken();
            string label = "";
            if(_currentToken.type == Token.Type.IDENTIFIER)
            {
                label = _currentToken.text;
                nextToken();
            }
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after break", _currentToken);
            nextToken();
            statement = new BreakStatementNode(lineNumber, label);
        }
        // continue statement
        else if(_currentToken.isKeyword("continue"))
        {
            if(_loopStack == 0)
                throw new ScriptCompileException("Continue statements only allowed in loops", _currentToken);
            nextToken();
            string label = "";
            if(_currentToken.type == Token.Type.IDENTIFIER)
            {
                label = _currentToken.text;
                nextToken();
            }
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after continue", _currentToken);
            nextToken();
            statement = new ContinueStatementNode(lineNumber, label);
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
        else if(_currentToken.isKeyword("throw"))
        {
            nextToken();
            auto expr = parseExpression();
            if(_currentToken.type != Token.Type.SEMICOLON)
                throw new ScriptCompileException("Expected ';' after throw expression", _currentToken);
            nextToken();
            statement = new ThrowStatementNode(lineNumber, expr);
        }
        else if(_currentToken.isKeyword("try"))
        {
            statement = parseTryCatchBlockStatement();
        }
        else if(_currentToken.isKeyword("delete"))
        {
            nextToken();
            auto tok = _currentToken;
            auto expression = parseExpression();
            if(cast(MemberAccessNode)expression is null && cast(ArrayIndexNode)expression is null)
                throw new ScriptCompileException("Invalid operand for delete operation", tok);
            statement = new DeleteStatementNode(lineNumber, expression);
        }
        else if(_currentToken.isKeyword("class"))
        {
            statement = parseClassDeclaration();
        }
        else if(_currentToken.isKeyword("super"))
        {
            statement = parseSuperCallStatement();
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

    Node parsePrimaryExpression()
    {
        import std.conv: to, ConvException;

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
            case Token.Type.LBRACE:
                left = parseObjectLiteral();
                break;
            case Token.Type.DOUBLE:
                if(_currentToken.literalFlag == Token.LiteralFlag.NONE)
                    left = new LiteralNode(_currentToken, ScriptAny(to!double(_currentToken.text)));
                else
                    throw new ScriptCompileException("Malformed floating point token detected", _currentToken);
                nextToken();
                break;
            case Token.Type.INTEGER:
                try 
                {
                    if(_currentToken.literalFlag == Token.LiteralFlag.NONE)
                        left = new LiteralNode(_currentToken, ScriptAny(to!long(_currentToken.text)));
                    else if(_currentToken.literalFlag == Token.LiteralFlag.HEXADECIMAL)
                        left = new LiteralNode(_currentToken, ScriptAny(_currentToken.text[2..$].to!long(16)));
                    else if(_currentToken.literalFlag == Token.LiteralFlag.OCTAL)
                        left = new LiteralNode(_currentToken, ScriptAny(_currentToken.text[2..$].to!long(8)));
                    else if(_currentToken.literalFlag == Token.LiteralFlag.BINARY)
                        left = new LiteralNode(_currentToken, ScriptAny(_currentToken.text[2..$].to!long(2)));
                }
                catch(ConvException ex)
                {
                    throw new ScriptCompileException("Integer literal is too long", _currentToken);
                }
                nextToken();
                break;
            case Token.Type.STRING:
                left = new LiteralNode(_currentToken, ScriptAny(_currentToken.text));
                nextToken();
                break;
            case Token.Type.KEYWORD:
                if(_currentToken.text == "true" || _currentToken.text == "false")
                {
                    left = new LiteralNode(_currentToken, ScriptAny(to!bool(_currentToken.text)));
                    nextToken();
                }
                else if(_currentToken.text == "null")
                {
                    left = new LiteralNode(_currentToken, ScriptAny(null));
                    nextToken();
                }
                else if(_currentToken.text == "undefined")
                {
                    left = new LiteralNode(_currentToken, ScriptAny.UNDEFINED);
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
                    left = new LiteralNode(funcToken, ScriptAny(func));
                }
                else if(_currentToken.text == "class")
                {
                    left = parseClassExpression();
                }
                else if(_currentToken.text == "new")
                {
                    immutable newToken = _currentToken;
                    nextToken();
                    auto expression = parseExpression();
                    auto fcn = cast(FunctionCallNode)expression;
                    if(fcn is null)
                    {
                        // if this isn't a function call, turn it into one
                        fcn = new FunctionCallNode(expression, [], true);
                    }
                    fcn.returnThis = true;
                    left = new NewExpressionNode(fcn);                    
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

    ClassLiteralNode parseClassExpression()
    {
        immutable classToken = _currentToken;
        nextToken();
        immutable className = "<anonymous class>";
        Node baseClass = null;
        if(_currentToken.isKeyword("extends"))
        {
            nextToken();
            baseClass = parseExpression(); // let's hope this is an expression that results in a ScriptFunction value
            _baseClassStack ~= baseClass;
        }
        if(_currentToken.type != Token.Type.LBRACE)
            throw new ScriptCompileException("Expected '{' after class name", _currentToken);
        nextToken(); // eat the {
        ScriptFunction constructor = null;
        string[] methodNames;
        ScriptFunction[] methods;
        string[] getMethodNames;
        ScriptFunction[] getMethods;
        string[] setMethodNames;
        ScriptFunction[] setMethods;
        string[] staticMethodNames;
        ScriptFunction[] staticMethods;
        enum PropertyType { NONE, GET, SET, STATIC }
        while(_currentToken.type != Token.Type.RBRACE && _currentToken.type != Token.Type.EOF)
        {
            PropertyType ptype = PropertyType.NONE;
            string currentMethodName = "";
            // could be a get or set
            if(_currentToken.isIdentifier("get"))
            {
                ptype = PropertyType.GET;
                nextToken();
            }
            else if(_currentToken.isIdentifier("set"))
            {
                ptype = PropertyType.SET;
                nextToken();
            }
            else if(_currentToken.isIdentifier("static"))
            {
                ptype = PropertyType.STATIC;
                nextToken();
            }
            // then an identifier
            if(_currentToken.type != Token.Type.IDENTIFIER)
                throw new ScriptCompileException("Method names must be valid identifiers", _currentToken);
            currentMethodName = _currentToken.text;
            nextToken();
            // then a (
            if(_currentToken.type != Token.Type.LPAREN)
                throw new ScriptCompileException("Expected '(' after method name", _currentToken);
            nextToken();
            string[] argNames;
            while(_currentToken.type != Token.Type.RPAREN)
            {
                if(_currentToken.type != Token.Type.IDENTIFIER)
                    throw new ScriptCompileException("Method arguments must be valid identifiers", _currentToken);
                argNames ~= _currentToken.text;
                nextToken();
                if(_currentToken.type == Token.Type.COMMA)
                    nextToken();
                else if(_currentToken.type != Token.Type.RPAREN)
                    throw new ScriptCompileException("Method arguments must be separated by ','", _currentToken);
            }
            nextToken(); // eat the )
            // then a {
            if(_currentToken.type != Token.Type.LBRACE)
                throw new ScriptCompileException("Method bodies must begin with '{'", _currentToken);
            nextToken();
            auto statements = parseStatements(Token.Type.RBRACE);
            nextToken(); // eat }
            // now we have a method but if this is the constructor
            if(currentMethodName == "constructor")
            {
                if(ptype != PropertyType.NONE)
                    throw new ScriptCompileException("Get and set not allowed for constructor", classToken);
                if(constructor !is null)
                    throw new ScriptCompileException("Classes may only have one constructor", classToken);
                // if this is extending a class it MUST have ONE super call
                if(baseClass !is null)
                {
                    ulong numSupers = 0;
                    foreach(stmt ; statements)
                    {
                        if(cast(SuperCallStatementNode)stmt)
                            numSupers++;
                    }
                    if(numSupers != 1)
                        throw new ScriptCompileException("Derived class constructors must have one super call", 
                                classToken);
                }
                constructor = new ScriptFunction(className, argNames, statements, true);
            }
            else // it's a normal method or getter/setter
            {
                if(ptype == PropertyType.NONE)
                {
                    methods ~= new ScriptFunction(currentMethodName, 
                            argNames, statements, false);
                    methodNames ~= currentMethodName;
                }
                else if(ptype == PropertyType.GET)
                {
                    getMethods ~= new ScriptFunction(currentMethodName, 
                            argNames, statements, false);
                    getMethodNames ~= currentMethodName;                    
                }
                else if(ptype == PropertyType.SET)
                {
                    setMethods ~= new ScriptFunction(currentMethodName, 
                            argNames, statements, false);
                    setMethodNames ~= currentMethodName;                    
                }
                else if(ptype == PropertyType.STATIC)
                {
                    staticMethods ~= new ScriptFunction(currentMethodName, argNames, 
                            statements, false);
                    staticMethodNames ~= currentMethodName;
                }
            }
        }
        nextToken(); // eat the class body }

        // check for duplicate methods
        bool[string] mnameMap;
        foreach(mname ; methodNames)
        {
            if(mname in mnameMap)
                throw new ScriptCompileException("Duplicate methods are not allowed", classToken);
            mnameMap[mname] = true;
        }

        if(baseClass !is null)
            _baseClassStack = _baseClassStack[0..$-1];
        if(constructor is null)
            constructor = ScriptFunction.emptyFunction(className, true);
        // add all static methods to the constructor object
        for(size_t i = 0; i < staticMethods.length; ++i)
        {
            constructor[staticMethodNames[i]] = staticMethods[i];
        }
        // fill in the function.prototype with the methods
        for(size_t i = 0; i < methodNames.length; ++i)
            constructor["prototype"][methodNames[i]] = ScriptAny(methods[i]);
        // fill in any get properties
        for(size_t i = 0; i < getMethodNames.length; ++i)
            constructor["prototype"].addGetterProperty(getMethodNames[i], getMethods[i]);
        // fill in any set properties
        for(size_t i = 0; i < setMethodNames.length; ++i)
            constructor["prototype"].addSetterProperty(setMethodNames[i], setMethods[i]);
       return new ClassLiteralNode(constructor, baseClass);
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

    VarDeclarationStatementNode parseVarDeclarationStatement(bool consumeSemicolon = true)
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
        if(consumeSemicolon)
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

    StatementNode parseLoopStatement()
    {
        string label = "";
        if(_currentToken.type == Token.Type.LABEL)
        {
            label = _currentToken.text;
            nextToken();
        }
        StatementNode statement;
        if(_currentToken.isKeyword("while"))
        {
            ++_loopStack;
            statement = parseWhileStatement(label);
            --_loopStack;
        }
        // check for do-while statement TODO check for label
        else if(_currentToken.isKeyword("do"))
        {
            ++_loopStack;
            statement = parseDoWhileStatement(label);
            --_loopStack;
        }
        // check for for loop TODO check label
        else if(_currentToken.isKeyword("for"))
        {
            ++_loopStack;
            statement = parseForStatement(label);
            --_loopStack;
        }
        return statement;
    }

    WhileStatementNode parseWhileStatement(string label = "")
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
        return new WhileStatementNode(lineNumber, condition, loopBody, label);
    }

    DoWhileStatementNode parseDoWhileStatement(string label = "")
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
        return new DoWhileStatementNode(lineNumber, loopBody, condition, label);
    }

    StatementNode parseForStatement(string label = "")
    {
        immutable lineNumber = _currentToken.position.line;
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after for keyword", _currentToken);
        nextToken();
        VarDeclarationStatementNode decl = null;
        if(_currentToken.type != Token.Type.SEMICOLON)
            decl = parseVarDeclarationStatement(false);
        if(_currentToken.isKeyword("of") || _currentToken.isKeyword("in"))
        {
            // first we need to validate the VarDeclarationStatementNode to make sure it only consists
            // of let or const and VarAccessNodes
            if(decl is null)
                throw new ScriptCompileException("Invalid for of statement", _currentToken);
            Token qualifier;
            VarAccessNode[] vans;
            if(decl.qualifier.text != "const" && decl.qualifier.text != "let")
                throw new ScriptCompileException("Global variable declaration invalid in for of statement",
                    decl.qualifier);
            foreach(va ; decl.varAccessOrAssignmentNodes)
            {
                auto valid = cast(VarAccessNode)va;
                if(valid is null)
                    throw new ScriptCompileException("Invalid variable declaration in for of statement", 
                        _currentToken);
                vans ~= valid;
            }
            nextToken();
            auto objToIterateExpr = parseExpression();
            if(_currentToken.type != Token.Type.RPAREN)
                throw new ScriptCompileException("Expected ')' after array or object", _currentToken);
            nextToken();
            auto bodyStatement = parseStatement();
            return new ForOfStatementNode(lineNumber, qualifier, vans, objToIterateExpr, bodyStatement, label);
        }
        else if(_currentToken.type == Token.Type.SEMICOLON)
        {
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
                condition = new LiteralNode(_currentToken, ScriptAny(true));
            }
            nextToken();
            Node increment = null;
            if(_currentToken.type != Token.Type.RPAREN)
            {
                increment = parseExpression();
            }
            else
            {
                increment = new LiteralNode(_currentToken, ScriptAny(true));
            }
            if(_currentToken.type != Token.Type.RPAREN)
                throw new ScriptCompileException("Expected ')' before for loop body", _currentToken);
            nextToken();
            auto bodyNode = parseStatement();
            return new ForStatementNode(lineNumber, decl, condition, increment, bodyNode, label);
        }
        else
            throw new ScriptCompileException("Invalid for statement", _currentToken);
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

    TryCatchBlockStatementNode parseTryCatchBlockStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        nextToken(); // eat the 'try'
        auto tryBlock = parseStatement();
        if(!_currentToken.isKeyword("catch"))
            throw new ScriptCompileException("Catch block required after try block", _currentToken);
        nextToken(); // eat the catch
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Missing '(' after catch", _currentToken);
        nextToken(); // eat the '('
        if(_currentToken.type != Token.Type.IDENTIFIER)
            throw new ScriptCompileException("Name of exception required in catch block", _currentToken);
        auto name = _currentToken.text;
        nextToken();
        if(_currentToken.type != Token.Type.RPAREN)
            throw new ScriptCompileException("Missing ')' after exception name", _currentToken);
        nextToken(); // eat the ')'
        auto catchBlock = parseStatement();
        return new TryCatchBlockStatementNode(lineNumber, tryBlock, name, catchBlock);
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

    ClassDeclarationStatementNode parseClassDeclaration()
    {
        immutable lineNumber = _currentToken.position.line;
        immutable classToken = _currentToken;
        nextToken();
        if(_currentToken.type != Token.Type.IDENTIFIER)
            throw new ScriptCompileException("Class name must be valid identifier", _currentToken);
        auto className = _currentToken.text;
        nextToken();
        Node baseClass = null;
        if(_currentToken.isKeyword("extends"))
        {
            nextToken();
            baseClass = parseExpression(); // let's hope this is an expression that results in a ScriptFunction value
            _baseClassStack ~= baseClass;
        }
        if(_currentToken.type != Token.Type.LBRACE)
            throw new ScriptCompileException("Expected '{' after class name", _currentToken);
        nextToken(); // eat the {
        ScriptFunction constructor = null;
        string[] methodNames;
        ScriptFunction[] methods;
        string[] getMethodNames;
        ScriptFunction[] getMethods;
        string[] setMethodNames;
        ScriptFunction[] setMethods;
        string[] staticMethodNames;
        ScriptFunction[] staticMethods;
        enum PropertyType { NONE, GET, SET, STATIC }
        while(_currentToken.type != Token.Type.RBRACE && _currentToken.type != Token.Type.EOF)
        {
            PropertyType ptype = PropertyType.NONE;
            string currentMethodName = "";
            // could be a get or set
            if(_currentToken.isIdentifier("get"))
            {
                ptype = PropertyType.GET;
                nextToken();
            }
            else if(_currentToken.isIdentifier("set"))
            {
                ptype = PropertyType.SET;
                nextToken();
            }
            else if(_currentToken.isIdentifier("static"))
            {
                ptype = PropertyType.STATIC;
                nextToken();
            }
            // then an identifier
            if(_currentToken.type != Token.Type.IDENTIFIER)
                throw new ScriptCompileException("Method names must be valid identifiers", _currentToken);
            currentMethodName = _currentToken.text;
            nextToken();
            // then a (
            if(_currentToken.type != Token.Type.LPAREN)
                throw new ScriptCompileException("Expected '(' after method name", _currentToken);
            nextToken();
            string[] argNames;
            while(_currentToken.type != Token.Type.RPAREN)
            {
                if(_currentToken.type != Token.Type.IDENTIFIER)
                    throw new ScriptCompileException("Method arguments must be valid identifiers", _currentToken);
                argNames ~= _currentToken.text;
                nextToken();
                if(_currentToken.type == Token.Type.COMMA)
                    nextToken();
                else if(_currentToken.type != Token.Type.RPAREN)
                    throw new ScriptCompileException("Method arguments must be separated by ','", _currentToken);
            }
            nextToken(); // eat the )
            // then a {
            if(_currentToken.type != Token.Type.LBRACE)
                throw new ScriptCompileException("Method bodies must begin with '{'", _currentToken);
            nextToken();
            auto statements = parseStatements(Token.Type.RBRACE);
            nextToken(); // eat }
            // now we have a method but if this is the constructor
            if(currentMethodName == "constructor")
            {
                if(ptype != PropertyType.NONE)
                    throw new ScriptCompileException("Get and set not allowed for constructor", classToken);
                if(constructor !is null)
                    throw new ScriptCompileException("Classes may only have one constructor", classToken);
                // if this is extending a class it MUST have ONE super call
                if(baseClass !is null)
                {
                    ulong numSupers = 0;
                    foreach(stmt ; statements)
                    {
                        if(cast(SuperCallStatementNode)stmt)
                            numSupers++;
                    }
                    if(numSupers != 1)
                        throw new ScriptCompileException("Derived class constructors must have one super call", 
                                classToken);
                }
                constructor = new ScriptFunction(className, argNames, statements, true);
            }
            else // it's a normal method or getter/setter
            {
                if(ptype == PropertyType.NONE)
                {
                    methods ~= new ScriptFunction(className ~ ".prototype." ~ currentMethodName, 
                            argNames, statements, false);
                    methodNames ~= currentMethodName;
                }
                else if(ptype == PropertyType.GET)
                {
                    getMethods ~= new ScriptFunction(className ~ ".prototype." ~ currentMethodName, 
                            argNames, statements, false);
                    getMethodNames ~= currentMethodName;                    
                }
                else if(ptype == PropertyType.SET)
                {
                    setMethods ~= new ScriptFunction(className ~ ".prototype." ~ currentMethodName, 
                            argNames, statements, false);
                    setMethodNames ~= currentMethodName;                    
                }
                else if(ptype == PropertyType.STATIC)
                {
                    staticMethods ~= new ScriptFunction(className ~ "." ~ currentMethodName, argNames, 
                            statements, false);
                    staticMethodNames ~= currentMethodName;
                }
            }
        }
        nextToken(); // eat the class body }

        // check for duplicate methods
        bool[string] mnameMap;
        foreach(mname ; methodNames)
        {
            if(mname in mnameMap)
                throw new ScriptCompileException("Duplicate methods are not allowed", classToken);
            mnameMap[mname] = true;
        }

        if(baseClass !is null)
            _baseClassStack = _baseClassStack[0..$-1];
        if(constructor is null)
            constructor = ScriptFunction.emptyFunction(className, true);
        // add all static methods to the constructor object
        for(size_t i = 0; i < staticMethods.length; ++i)
        {
            constructor[staticMethodNames[i]] = staticMethods[i];
        }
        return new ClassDeclarationStatementNode(lineNumber, className, constructor, methodNames, methods, 
                getMethodNames, getMethods, setMethodNames, setMethods, baseClass);
    }

    SuperCallStatementNode parseSuperCallStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        if(_baseClassStack.length == 0)
            throw new ScriptCompileException("Super keyword may only be used in constructors of derived classes", 
                    _currentToken);
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Super call parameters must begin with '('", _currentToken);
        nextToken();
        auto expressions = parseCommaSeparatedExpressions(Token.Type.RPAREN);
        nextToken(); // eat the )
        if(_currentToken.type != Token.Type.SEMICOLON)
            throw new ScriptCompileException("Missing ';' at end of super statement", _currentToken);
        nextToken();
        size_t topClass = _baseClassStack.length - 1; // @suppress(dscanner.suspicious.length_subtraction)
        return new SuperCallStatementNode(lineNumber, _baseClassStack[topClass], expressions);
    }

    SwitchStatementNode parseSwitchStatement() 
        in { assert(_switchStack >= 0); } do
    {
        import mildew.nodes: VisitResult;
        import mildew.context: Context;
        ++_switchStack;
        immutable lineNumber = _currentToken.position.line;
        immutable switchToken = _currentToken;
        nextToken();
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after switch keyword", _currentToken);
        nextToken();
        auto expression = parseExpression();
        if(_currentToken.type != Token.Type.RPAREN)
            throw new ScriptCompileException("Expected ')' after switch expression", _currentToken);
        nextToken();
        if(_currentToken.type != Token.Type.LBRACE)
            throw new ScriptCompileException("Expected '{' to begin switch body", _currentToken);
        nextToken();
        bool caseStarted = false;
        size_t statementCounter = 0;
        StatementNode[] statementNodes;
        size_t defaultStatementID = size_t.max;
        size_t[ScriptAny] jumpTable;
        while(_currentToken.type != Token.Type.RBRACE)
        {
            if(_currentToken.isKeyword("case"))
            {
                nextToken();
                caseStarted = true;
                auto caseExpression = parseExpression();
                // it has to be evaluatable at compile time
                auto vr = caseExpression.visit(new Context(null, "<ctfe>"));
                if(vr.exception !is null || vr.result == ScriptAny.UNDEFINED)
                    throw new ScriptCompileException("Case expression must be determined at compile time", switchToken);
                if(_currentToken.type != Token.Type.COLON)
                    throw new ScriptCompileException("Expected ':' after case expression", _currentToken);
                nextToken();
                if(vr.result in jumpTable)
                    throw new ScriptCompileException("Duplicate case entries not allowed", switchToken);
                jumpTable[vr.result] = statementCounter;
            }
            else if(_currentToken.isKeyword("default"))
            {
                caseStarted = true;
                nextToken();
                if(_currentToken.type != Token.Type.COLON)
                    throw new ScriptCompileException("':' expected after default keyword", _currentToken);
                nextToken();
                defaultStatementID = statementCounter;
            }
            else
            {
                if(!caseStarted)
                    throw new ScriptCompileException("Case condition required before any statements", _currentToken);
                statementNodes ~= parseStatement();
                ++statementCounter;
            }
        }
        nextToken(); // consume }
        --_switchStack;
        return new SwitchStatementNode(lineNumber, expression, new SwitchBody(statementNodes, defaultStatementID, 
            jumpTable));
    }

    Node[] parseCommaSeparatedExpressions(in Token.Type stop)
    {
        Node[] expressions;

        while(_currentToken.type != stop && _currentToken.type != Token.Type.EOF && !_currentToken.isKeyword("of")
          && !_currentToken.isKeyword("in"))
        {
            auto expression = parseExpression();
            expressions ~= expression;
            if(_currentToken.type == Token.Type.COMMA)
                nextToken();
            else if(_currentToken.type != stop && !_currentToken.isKeyword("of")
              && !_currentToken.isKeyword("in"))
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
    int _loopStack = 0;
    int _switchStack = 0;
    Node[] _baseClassStack; // in case we have nested class declarations
}