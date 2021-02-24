/**
This module implements the Parser struct, which generates Nodes from tokens. The resulting syntax tree
is processed by the Compiler.

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
import mildew.util.stack;

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
        case Token.Type.POW_ASSIGN:
        case Token.Type.STAR_ASSIGN:
        case Token.Type.FSLASH_ASSIGN:
        case Token.Type.PERCENT_ASSIGN:
        case Token.Type.PLUS_ASSIGN:
        case Token.Type.DASH_ASSIGN:
        case Token.Type.BAND_ASSIGN:
        case Token.Type.BXOR_ASSIGN:
        case Token.Type.BOR_ASSIGN:
        case Token.Type.BLS_ASSIGN:
        case Token.Type.BRS_ASSIGN:
        case Token.Type.BURS_ASSIGN:
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
        case Token.Type.POW_ASSIGN:
        case Token.Type.STAR_ASSIGN:
        case Token.Type.FSLASH_ASSIGN:
        case Token.Type.PERCENT_ASSIGN:
        case Token.Type.PLUS_ASSIGN:
        case Token.Type.DASH_ASSIGN:
        case Token.Type.BAND_ASSIGN:
        case Token.Type.BXOR_ASSIGN:
        case Token.Type.BOR_ASSIGN:
        case Token.Type.BLS_ASSIGN:
        case Token.Type.BRS_ASSIGN:
        case Token.Type.BURS_ASSIGN:
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
     * The main starting point. Also the "program" grammar rule. This method generates a block statement
     * node where the interpreter iterates through each statement and executes it.
     */
    BlockStatementNode parseProgram()
    {
        immutable lineNo = _currentToken.position.line;
        _functionContextStack.push(FunctionContext(FunctionContextType.NORMAL, 0, 0, []));
        auto statements = parseStatements(Token.Type.EOF);
        _functionContextStack.pop();
        assert(_functionContextStack.size == 0, "Sanity check failed: _functionContextStack");
        return new BlockStatementNode(lineNo, statements);
    }

package:

    /// parse a single expression. See https://eli.thegreenplace.net/2012/08/02/parsing-expressions-by-precedence-climbing
    /// for algorithm.
    ExpressionNode parseExpression(int minPrec = 1)
    {      
        ExpressionNode primaryLeft = null;

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
                    if(!cast(VarAccessNode)right)
                        throw new ScriptCompileException("Right hand side of `.` operator must be identifier", opToken);
                    if(cast(VarAccessNode)right is null)
                        throw new ScriptCompileException("Object members must be valid identifiers", _currentToken);
                    if(unOpPrec != 0 && prec > unOpPrec)
                    {
                        auto uon = cast(UnaryOpNode)primaryLeft;
                        primaryLeft = new UnaryOpNode(uon.opToken, 
                                new MemberAccessNode(uon.operandNode, opToken, right));
                    }
                    else
                        primaryLeft = new MemberAccessNode(primaryLeft, opToken, right);
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
                    ExpressionNode primaryRight = parseExpression(nextMinPrec);
                    // catch invalid assignments
                    if(opToken.isAssignmentOperator)
                    {
                        if(!(cast(VarAccessNode)primaryLeft 
                          || cast(MemberAccessNode)primaryLeft 
                          || cast(ArrayIndexNode)primaryLeft))
                        {
                            throw new ScriptCompileException("Invalid left hand operand for assignment "
                                    ~ primaryLeft.toString(), opToken);
                        }
                    }
                    primaryLeft = new BinaryOpNode(opToken, primaryLeft, primaryRight);
                }
            }
        }

        return primaryLeft;
    }

private:

    // very weird way of doing things but it works, may need rework to allow undefined to be a case
    ScriptAny evaluateCTFE(ExpressionNode expr)
    {
        import mildew.environment: Environment;
        import mildew.compiler: Compiler;
        import mildew.vm.program: Program;
        import mildew.vm.virtualmachine: VirtualMachine;
        auto ret = new ReturnStatementNode(0, expr);
        auto compiler = new Compiler();
        auto program = compiler.compile([ret]);
        auto vm = new VirtualMachine(new Environment(null, "<ctfe>"));
        try 
        {
            return vm.runProgram(program, []);
        }
        catch(Exception ex)
        {
            return ScriptAny.UNDEFINED;
        }
    }

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
            if(_functionContextStack.top.loopStack == 0 && _functionContextStack.top.switchStack == 0)
                throw new ScriptCompileException("Break statements only allowed in loops or switch-case bodies", 
                    _currentToken);
            nextToken();
            string label = "";
            if(_currentToken.type == Token.Type.IDENTIFIER)
            {
                label = _currentToken.text;
                bool valid = false;
                // label must exist on stack
                for(size_t i = _functionContextStack.top.labelStack.length; i > 0; --i)
                {
                    if(_functionContextStack.top.labelStack[i-1] == label)
                    {
                        valid = true;
                        break;
                    }
                }
                if(!valid)
                    throw new ScriptCompileException("Break label does not refer to valid label", _currentToken);
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
            if(_functionContextStack.top.loopStack == 0)
                throw new ScriptCompileException("Continue statements only allowed in loops", _currentToken);
            nextToken();
            string label = "";
            if(_currentToken.type == Token.Type.IDENTIFIER)
            {
                label = _currentToken.text;
                bool valid = false;
                for(size_t i = _functionContextStack.top.labelStack.length; i > 0; --i)
                {
                    if(_functionContextStack.top.labelStack[i-1] == label)
                    {
                        valid = true;
                        break;
                    }
                }
                if(!valid)
                    throw new ScriptCompileException("Continue label does not refer to valid label", _currentToken);
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
            ExpressionNode expression = null;
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
            immutable delToken = _currentToken;
            nextToken();
            auto tok = _currentToken;
            auto expression = parseExpression();
            if(cast(MemberAccessNode)expression is null && cast(ArrayIndexNode)expression is null)
                throw new ScriptCompileException("Invalid operand for delete operation", tok);
            statement = new DeleteStatementNode(lineNumber, delToken, expression);
        }
        else if(_currentToken.isKeyword("class"))
        {
            statement = parseClassDeclaration();
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

    ExpressionNode parsePrimaryExpression()
    {
        import std.conv: to, ConvException;

        ExpressionNode left = null;
        switch(_currentToken.type)
        {
            case Token.Type.LPAREN: {
                // first check if this is a lambda
                auto lookahead = peekTokens(3);
                if((lookahead[1].type == Token.Type.COMMA ||
                   lookahead[1].type == Token.Type.ARROW ||
                   lookahead[2].type == Token.Type.ARROW) && lookahead[0].type != Token.Type.LPAREN)
                {
                    left = parseLambda(true);
                }
                else
                {
                    nextToken();
                    left = parseExpression();
                    if(_currentToken.type != Token.Type.RPAREN)
                        throw new ScriptCompileException("Missing ')' in primary expression", _currentToken);
                    nextToken();
                }
                break;
            }
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
                if(_currentToken.literalFlag != Token.LiteralFlag.TEMPLATE_STRING)
                    left = new LiteralNode(_currentToken, ScriptAny(_currentToken.text));
                else
                    left = parseTemplateStringNode();
                nextToken();
                break;
            case Token.Type.REGEX:
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
                    bool isGenerator = false;
                    immutable token = _currentToken;
                    nextToken();
                    if(_currentToken.type == Token.Type.STAR)
                    {
                        isGenerator = true;
                        nextToken();
                    }

                    string optionalName = "";
                    if(_currentToken.type == Token.Type.IDENTIFIER)
                    {
                        optionalName = _currentToken.text;
                        nextToken();
                    }

                    if(_currentToken.type != Token.Type.LPAREN)
                        throw new ScriptCompileException("Argument list expected after anonymous function", 
                            _currentToken);
                    nextToken();
                    string[] argNames = [];
                    ExpressionNode[] defaultArgs;
                    argNames = parseArgumentList(defaultArgs);
                    nextToken(); // eat the )
                    if(_currentToken.type != Token.Type.LBRACE)
                        throw new ScriptCompileException("Expected '{' before anonymous function body", _currentToken);
                    nextToken(); // eat the {
                    _functionContextStack.push(FunctionContext(
                        isGenerator? FunctionContextType.GENERATOR : FunctionContextType.NORMAL, 
                        0, 0, []));
                    auto statements = parseStatements(Token.Type.RBRACE);
                    _functionContextStack.pop();
                    nextToken();
                    // auto func = new ScriptFunction(name, argNames, statements, null);
                    left = new FunctionLiteralNode(token, argNames, defaultArgs, statements, optionalName, 
                            false, isGenerator);
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
                else if(_currentToken.text == "super")
                {
                    immutable stoken = _currentToken;
                    if(_baseClassStack.length < 1)
                        throw new ScriptCompileException("Super expression only allowed in derived classes", stoken);
                    left = new SuperNode(stoken, _baseClassStack[$-1]);
                    nextToken();
                }
                else if(_currentToken.text == "yield")
                {
                    // check context stack
                    if(_functionContextStack.top.fct != FunctionContextType.GENERATOR)
                        throw new ScriptCompileException("Yield may only be used in Generator functions", 
                            _currentToken);
                    
                    immutable ytoken = _currentToken;
                    nextToken();
                    ExpressionNode expr;
                    if(_currentToken.type != Token.Type.RBRACE && _currentToken.type != Token.Type.SEMICOLON)
                        expr = parseExpression();
                    left = new YieldNode(ytoken, expr);
                }
                else
                    throw new ScriptCompileException("Unexpected keyword in primary expression", _currentToken);
                break;
                // TODO function
            case Token.Type.IDENTIFIER: {
                immutable lookahead = peekToken();
                if(lookahead.type == Token.Type.ARROW)
                {
                    left = parseLambda(false);
                }
                else
                {
                    left = new VarAccessNode(_currentToken);
                    nextToken();
                }
                break;
            }
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
    
    // TODO optimize this to use indexing instead of string building.
    TemplateStringNode parseTemplateStringNode()
    {
        import mildew.lexer: Lexer;

        enum TSState { LIT, EXPR }

        size_t textIndex;
        string currentExpr = "";
        string currentLiteral = "";
        ExpressionNode[] nodes;
        TSState state = TSState.LIT;

        string peekTwo(in string text, size_t i)
        {
            immutable char first = i >= text.length ? '\0' : text[i];
            immutable char second = i+1 >= text.length ? '\0' : text[i+1];
            return cast(string)[first,second];
        }

        while(textIndex < _currentToken.text.length)
        {
            if(state == TSState.LIT)
            {
                if(peekTwo(_currentToken.text, textIndex) == "${")
                {
                    currentExpr = "";
                    textIndex += 2;
                    state = TSState.EXPR;
                    if(currentLiteral.length > 0)
                        nodes ~= new LiteralNode(_currentToken, ScriptAny(currentLiteral));
                }
                else
                {
                    currentLiteral ~= _currentToken.text[textIndex++];
                }
            }
            else
            {
                if(_currentToken.text[textIndex] == '}')
                {
                    currentLiteral = "";
                    textIndex++;
                    state = TSState.LIT;
                    if(currentExpr.length > 0)
                    {
                        auto lexer = Lexer(currentExpr);
                        auto tokens = lexer.tokenize();
                        auto parser = Parser(tokens);
                        nodes ~= parser.parseExpression();
                        if(parser._currentToken.type != Token.Type.EOF)
                        {
                            parser._currentToken.position = _currentToken.position;
                            throw new ScriptCompileException("Unexpected token in template expression", 
                                    parser._currentToken);
                        }
                    }
                }
                else
                {
                    currentExpr ~= _currentToken.text[textIndex++];
                }
            }
        }
        if(state == TSState.EXPR)
            throw new ScriptCompileException("Unclosed template expression", _currentToken);
        if(currentLiteral.length > 0)
            nodes ~= new LiteralNode(_currentToken, ScriptAny(currentLiteral));
        return new TemplateStringNode(nodes);
    }

    /// after class ? extend base this can begin
    ClassDefinition parseClassDefinition(Token classToken, string className, ExpressionNode baseClass)
    {
        if(_currentToken.type != Token.Type.LBRACE)
            throw new ScriptCompileException("Expected '{' after class", _currentToken);
        nextToken();
        FunctionLiteralNode constructor;
        string[] methodNames;
        FunctionLiteralNode[] methods;
        string[] getMethodNames;
        FunctionLiteralNode[] getMethods;
        string[] setMethodNames;
        FunctionLiteralNode[] setMethods;
        string[] staticMethodNames;
        FunctionLiteralNode[] staticMethods;
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
            immutable idToken = _currentToken;
            if(_currentToken.type != Token.Type.IDENTIFIER)
                throw new ScriptCompileException("Method names must be valid identifiers", _currentToken);
            currentMethodName = _currentToken.text;
            nextToken();
            // then a (
            if(_currentToken.type != Token.Type.LPAREN)
                throw new ScriptCompileException("Expected '(' after method name", _currentToken);
            nextToken(); // eat the (
            string[] argNames;
            ExpressionNode[] defaultArgs;
            argNames = parseArgumentList(defaultArgs);
            nextToken(); // eat the )
            // then a {
            if(_currentToken.type != Token.Type.LBRACE)
                throw new ScriptCompileException("Method bodies must begin with '{'", _currentToken);
            nextToken();
            if(currentMethodName != "constructor")
                _functionContextStack.push(FunctionContext(FunctionContextType.METHOD, 0, 0, []));
            else
                _functionContextStack.push(FunctionContext(FunctionContextType.CONSTRUCTOR, 0, 0, []));
            auto statements = parseStatements(Token.Type.RBRACE);
            _functionContextStack.pop();
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
                        if(auto exprStmt = cast(ExpressionStatementNode)stmt)
                        {
                            if(auto fcn = cast(FunctionCallNode)exprStmt.expressionNode)
                            {
                                if(auto supernode = cast(SuperNode)fcn.functionToCall)
                                    numSupers++;
                            }
                        }
                    }
                    if(numSupers != 1)
                        throw new ScriptCompileException("Derived class constructors must have one super call", 
                                classToken);
                }
                constructor = new FunctionLiteralNode(idToken, argNames, defaultArgs, statements, className, true);
            }
            else // it's a normal method or getter/setter
            {
                if(ptype == PropertyType.NONE)
                {
                    auto trueName = currentMethodName;
                    if(className != "<anonymous class>" && className != "")
                        trueName = className ~ ".prototype." ~ currentMethodName;
                    methods ~= new FunctionLiteralNode(idToken, argNames, defaultArgs, statements, trueName);
                    methodNames ~= currentMethodName;
                }
                else if(ptype == PropertyType.GET)
                {
                    getMethods ~= new FunctionLiteralNode(idToken, argNames, defaultArgs, statements, 
                            currentMethodName);
                    getMethodNames ~= currentMethodName;                    
                }
                else if(ptype == PropertyType.SET)
                {
                    setMethods ~= new FunctionLiteralNode(idToken, argNames, defaultArgs, statements, 
                            currentMethodName);
                    setMethodNames ~= currentMethodName;                    
                }
                else if(ptype == PropertyType.STATIC)
                {
                    auto trueName = currentMethodName;
                    if(className != "<anonymous class>" && className != "")
                        trueName = className ~ "." ~ currentMethodName;
                    staticMethods ~= new FunctionLiteralNode(idToken, argNames, defaultArgs, statements, trueName);
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

        if(constructor is null)
        {
            // probably should enforce required super when base class exists
            constructor = new FunctionLiteralNode(classToken, [], [], [], className, true);
        }

        if(baseClass !is null)
            _baseClassStack = _baseClassStack[0..$-1];
       	return new ClassDefinition(className, constructor, methodNames, methods, getMethodNames, getMethods, 
	   		setMethodNames, setMethods, staticMethodNames, staticMethods, baseClass);
    }

    ClassLiteralNode parseClassExpression()
    {
        immutable classToken = _currentToken;
        nextToken();
        string className = "<anonymous class>";
        if(_currentToken.type == Token.Type.IDENTIFIER)
        {
            className = _currentToken.text;
            nextToken();
        }
        ExpressionNode baseClass = null;
        if(_currentToken.isKeyword("extends"))
        {
            nextToken();
            baseClass = parseExpression(); // let's hope this is an expression that results in a ScriptFunction value
            _baseClassStack ~= baseClass;
        }
        auto classDef = parseClassDefinition(classToken, className, baseClass);
        return new ClassLiteralNode(classToken, classDef);
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
        // auto expressions = parseCommaSeparatedExpressions(Token.Type.SEMICOLON);
        ExpressionNode[] expressions;
        while(_currentToken.type != Token.Type.SEMICOLON && _currentToken.type != Token.Type.EOF 
          && !_currentToken.isIdentifier("of") && !_currentToken.isKeyword("in"))
        {
            if(_currentToken.type == Token.Type.IDENTIFIER)
            {
                auto varName = _currentToken.text;
                nextToken();
                if(_currentToken.type == Token.Type.ASSIGN)
                {
                    nextToken();
                    auto assignment = parseExpression();
                    expressions ~= new BinaryOpNode(Token.createFakeToken(Token.Type.ASSIGN, "="), 
                        new VarAccessNode(Token.createFakeToken(Token.Type.IDENTIFIER, varName)),
                        assignment);
                }
                else
                {
                    expressions ~= new VarAccessNode(Token.createFakeToken(Token.Type.IDENTIFIER, varName));
                }
            }
            else if(_currentToken.type == Token.Type.LBRACE || _currentToken.type == Token.Type.LBRACKET)
            {
                immutable isObj = _currentToken.type == Token.Type.LBRACE;
                immutable endTokenType = isObj ? Token.Type.RBRACE : Token.Type.RBRACKET;
                nextToken();
                string[] names;
                string remainderName;
                while(_currentToken.type != endTokenType && _currentToken.type != Token.Type.EOF)
                {
                    if(_currentToken.type == Token.Type.TDOT)
                    {
                        nextToken();
                        if(_currentToken.type != Token.Type.IDENTIFIER)
                            throw new ScriptCompileException("Remainder must be identifier", _currentToken);
                        if(remainderName != "")
                            throw new ScriptCompileException("Only one remainder allowed", _currentToken);
                        remainderName = _currentToken.text;
                    }
                    else if(_currentToken.type == Token.Type.IDENTIFIER)
                    {
                        auto currentName = _currentToken.text;
                        names ~= currentName;
                    }
                    nextToken();
                    if(_currentToken.type == Token.Type.COMMA)
                        nextToken(); // eat the ,
                    else if(_currentToken.type != endTokenType && _currentToken.type != Token.Type.EOF)
                        throw new ScriptCompileException("Destructuring variable names must be separated by comma",
                            _currentToken);
                }
                if(names.length == 0 && remainderName == "")
                    throw new ScriptCompileException("Destructuring declaration cannot be empty", _currentToken);
                nextToken(); // eat the } or ]
                if(_currentToken.type != Token.Type.ASSIGN)
                    throw new ScriptCompileException("Destructuring declarations must be assignments", _currentToken);
                immutable assignToken = _currentToken;
                nextToken(); // eat the =
                auto assignment = parseExpression();
                expressions ~= new BinaryOpNode(assignToken, new DestructureTargetNode(names, remainderName, isObj),
                    assignment);
            }

            if(_currentToken.type == Token.Type.COMMA)
            {
                nextToken();
            }
            else if(_currentToken.type != Token.Type.SEMICOLON && _currentToken.type != Token.Type.EOF
                && !_currentToken.isIdentifier("of") && !_currentToken.isKeyword("in"))
            {
                throw new ScriptCompileException("Expected ',' between variable declarations (or missing ';')", 
                    _currentToken);
            }
        }
        // make sure all expressions are valid BinaryOpNodes or VarAccessNodes
        foreach(expression; expressions)
        {
            if(auto node = cast(BinaryOpNode)expression)
            {
                if(!(cast(VarAccessNode)node.leftNode || cast(DestructureTargetNode)node.leftNode))
                    throw new ScriptCompileException("Invalid assignment node", _currentToken);
                if(node.opToken.type != Token.Type.ASSIGN)
                    throw new ScriptCompileException("Invalid assignment statement", node.opToken);
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
            _functionContextStack.top.labelStack ~= label;
            nextToken();
        }
        StatementNode statement;
        if(_currentToken.isKeyword("while"))
        {
            ++_functionContextStack.top.loopStack;
            statement = parseWhileStatement(label);
            --_functionContextStack.top.loopStack;
        }
        // check for do-while statement TODO check for label
        else if(_currentToken.isKeyword("do"))
        {
            ++_functionContextStack.top.loopStack;
            statement = parseDoWhileStatement(label);
            --_functionContextStack.top.loopStack;
        }
        // check for for loop TODO check label
        else if(_currentToken.isKeyword("for"))
        {
            ++_functionContextStack.top.loopStack;
            statement = parseForStatement(label);
            --_functionContextStack.top.loopStack;
        }
        if(label != "")
        {
            _functionContextStack.top.labelStack = _functionContextStack.top.labelStack[0..$-1];
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
        if(_currentToken.isKeyword("in") || _currentToken.isIdentifier("of"))
        {
            immutable ofInToken = _currentToken;
            // first we need to validate the VarDeclarationStatementNode to make sure it only consists
            // of let or const and VarAccessNodes
            if(decl is null)
                throw new ScriptCompileException("Invalid for in statement", _currentToken);
            Token qualifier;
            VarAccessNode[] vans;
            if(decl.qualifier.text != "const" && decl.qualifier.text != "let")
                throw new ScriptCompileException("Global variable declaration invalid in for in statement",
                    decl.qualifier);
            int vanCount = 0;
            foreach(va ; decl.varAccessOrAssignmentNodes)
            {
                auto valid = cast(VarAccessNode)va;
                if(valid is null)
                    throw new ScriptCompileException("Invalid variable declaration in for in statement", 
                        _currentToken);
                vans ~= valid;
                ++vanCount;
            }
            if(vanCount > 2)
                throw new ScriptCompileException("For in loops may only have one or two variable declarations", 
                        _currentToken);
            nextToken();
            auto objToIterateExpr = parseExpression();
            if(_currentToken.type != Token.Type.RPAREN)
                throw new ScriptCompileException("Expected ')' after array or object", _currentToken);
            nextToken();
            auto bodyStatement = parseStatement();
            return new ForOfStatementNode(lineNumber, qualifier, ofInToken, vans, objToIterateExpr, 
                    bodyStatement, label);
        }
        else if(_currentToken.type == Token.Type.SEMICOLON)
        {
            nextToken();
            ExpressionNode condition = null;
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
            ExpressionNode increment = null;
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
        bool isGenerator = false;
        nextToken(); // eat the function keyword

        if(_currentToken.type == Token.Type.STAR)
        {
            isGenerator = true;
            nextToken();
        }

        if(_currentToken.type != Token.Type.IDENTIFIER)
            throw new ScriptCompileException("Expected identifier after function keyword", _currentToken);
        string name = _currentToken.text;
        nextToken();

        if(_currentToken.type == Token.Type.STAR)
        {
            if(isGenerator)
                throw new ScriptCompileException("Only one asterisk allowed to described Generators", _currentToken);
            isGenerator = true;
            nextToken();
        }
        
        if(_currentToken.type != Token.Type.LPAREN)
            throw new ScriptCompileException("Expected '(' after function name", _currentToken);
        nextToken(); // eat the (
        string[] argNames = [];
        ExpressionNode[] defaultArgs;
        argNames = parseArgumentList(defaultArgs);
        nextToken(); // eat the )

        // make sure there are no duplicate parameter names
        if(argNames.uniq.count != argNames.length)
            throw new ScriptCompileException("Function argument names must be unique", _currentToken);

        if(_currentToken.type != Token.Type.LBRACE)
            throw new ScriptCompileException("Function definition must begin with '{'", _currentToken);
        nextToken();
        _functionContextStack.push(FunctionContext(
            isGenerator? FunctionContextType.GENERATOR: FunctionContextType.NORMAL, 
            0, 0, []));
        auto statements = parseStatements(Token.Type.RBRACE);
        _functionContextStack.pop();
        nextToken(); // eat the }
        return new FunctionDeclarationStatementNode(lineNumber, name, argNames, defaultArgs, statements, isGenerator);
    }

    TryCatchBlockStatementNode parseTryCatchBlockStatement()
    {
        immutable lineNumber = _currentToken.position.line;
        auto tryToken = _currentToken;
        nextToken(); // eat the 'try'
        auto tryBlock = parseStatement();
        StatementNode catchBlock = null;
        StatementNode finallyBlock = null;
        auto name = "";
        if(_currentToken.isKeyword("catch"))
        {
            nextToken(); // eat the catch
            if(_currentToken.type == Token.Type.LPAREN)
            {
                nextToken(); // eat (
                if(_currentToken.type != Token.Type.IDENTIFIER)
                    throw new ScriptCompileException("Name of exception required after '('", _currentToken);
                name = _currentToken.text;
                nextToken();
                if(_currentToken.type != Token.Type.RPAREN)
                    throw new ScriptCompileException("')' required after exception name", _currentToken);
                nextToken();
            }
            catchBlock = parseStatement();
        }
        if(_currentToken.isKeyword("finally"))
        {
            nextToken();
            finallyBlock = parseStatement();
        }
        // can't be missing both catch and finally
        if(catchBlock is null && finallyBlock is null)
            throw new ScriptCompileException("Try-catch blocks must have catch and/or finally block", tryToken);
        return new TryCatchBlockStatementNode(lineNumber, tryBlock, name, catchBlock, finallyBlock);
    }

    ObjectLiteralNode parseObjectLiteral()
    {
        nextToken(); // eat the {
        string[] keys = [];
        ExpressionNode[] valueExpressions = [];
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
        ExpressionNode baseClass = null;
        if(_currentToken.isKeyword("extends"))
        {
            nextToken();
            baseClass = parseExpression(); // let's hope this is an expression that results in a ScriptFunction value
            _baseClassStack ~= baseClass;
        }
        auto classDef = parseClassDefinition(classToken, className, baseClass);
        return new ClassDeclarationStatementNode(lineNumber, classToken, classDef);
    }

    SwitchStatementNode parseSwitchStatement() 
    {
        ++_functionContextStack.top.switchStack;
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
                /*auto vr = caseExpression.accept(interpreter).get!(Interpreter.VisitResult);
                if(vr.exception !is null || vr.result == ScriptAny.UNDEFINED)
                    throw new ScriptCompileException("Case expression must be determined at compile time", switchToken);
                */
                auto result = evaluateCTFE(caseExpression);
                if(result == ScriptAny.UNDEFINED)
                    throw new ScriptCompileException(
                        "Case expression must be determined at compile time and cannot be undefined", 
                        switchToken);
                if(_currentToken.type != Token.Type.COLON)
                    throw new ScriptCompileException("Expected ':' after case expression", _currentToken);
                nextToken();
                if(result in jumpTable)
                    throw new ScriptCompileException("Duplicate case entries not allowed", switchToken);
                jumpTable[result] = statementCounter;
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
        --_functionContextStack.top.switchStack;
        return new SwitchStatementNode(lineNumber, expression, new SwitchBody(statementNodes, defaultStatementID, 
            jumpTable));
    }

    LambdaNode parseLambda(bool hasParentheses)
    {
        string[] argList;
        ExpressionNode[] defaultArgs;
        if(hasParentheses)
        {
            nextToken(); // eat the (
            argList = parseArgumentList(defaultArgs);
            nextToken(); // eat the )
        }
        else
        {
            if(_currentToken.type != Token.Type.IDENTIFIER)
                throw new ScriptCompileException("Lambda argument name must be valid identifier", _currentToken);
            argList ~= _currentToken.text;
            nextToken();
        }
        // make sure arrow
        if(_currentToken.type != Token.Type.ARROW)
            throw new ScriptCompileException("Arrow expected after lambda argument list", _currentToken);
        auto arrow = _currentToken;
        nextToken();
        // either a single expression, or body marked by {
        if(_currentToken.type == Token.Type.LBRACE)
        {
            nextToken(); // eat the {
            auto stmts = parseStatements(Token.Type.RBRACE);
            nextToken(); // eat the }
            return new LambdaNode(arrow, argList, defaultArgs, stmts);
        }
        else
        {
            auto expr = parseExpression();
            return new LambdaNode(arrow, argList, defaultArgs, expr);
        }
    }

    ExpressionNode[] parseCommaSeparatedExpressions(in Token.Type stop)
    {
        ExpressionNode[] expressions;

        while(_currentToken.type != stop && _currentToken.type != Token.Type.EOF && !_currentToken.isIdentifier("of")
          && !_currentToken.isKeyword("in"))
        {
            auto expression = parseExpression();
            expressions ~= expression;
            if(_currentToken.type == Token.Type.COMMA)
                nextToken();
            else if(_currentToken.type != stop 
              && !_currentToken.isIdentifier("of")
              && !_currentToken.isKeyword("in"))
                throw new ScriptCompileException("Comma separated list items must be separated by ','" 
                    ~ " (or missing '" ~ Token.createFakeToken(stop, "").symbol ~ "')", 
                    _currentToken);
        }

        return expressions;
    }

    string[] parseArgumentList(out ExpressionNode[] defaultArgs)
    {
        string[] argList;
        defaultArgs = [];
        while(_currentToken.type != Token.Type.RPAREN && _currentToken.type != Token.Type.EOF)
        {
            if(_currentToken.type != Token.Type.IDENTIFIER)
                throw new ScriptCompileException("Argument name must be identifier", _currentToken);
            argList ~= _currentToken.text;
            nextToken(); // eat the identifier

            if(_currentToken.type == Token.Type.ASSIGN)
            {
                nextToken(); // eat =
                defaultArgs ~= parseExpression();
            }
            else if(defaultArgs.length != 0)
            {
                throw new ScriptCompileException("Default arguments must be last arguments", _currentToken);
            }

            if(_currentToken.type == Token.Type.COMMA)
                nextToken(); // eat ,
            else if(_currentToken.type != Token.Type.RPAREN)
                throw new ScriptCompileException("Argument names must be separated by comma", _currentToken);
        }
        return argList;
    }

    void nextToken()
    {
        if(_tokenIndex >= _tokens.length)
            _currentToken = Token(Token.Type.EOF);
        else
            _currentToken = _tokens[_tokenIndex++];
    }

    void putbackToken()
    {
        if(_tokenIndex > 0)
            _currentToken = _tokens[--_tokenIndex];
    }

    Token peekToken()
    {
        return peekTokens(1)[0];
    }

    Token[] peekTokens(int numToPeek)
    {
        Token[] list;
        for(size_t i = _tokenIndex; i < _tokenIndex+numToPeek; ++i)
        {
            if(i < _tokens.length)
                list ~= _tokens[i];
            else
                list ~= Token.createFakeToken(Token.Type.EOF, "");
        }
        return list;
    }

    enum FunctionContextType {NORMAL, CONSTRUCTOR, METHOD, GENERATOR}

    struct FunctionContext
    {
        FunctionContextType fct;
        int loopStack;
        int switchStack;
        string[] labelStack;
    }

    Token[] _tokens;
    size_t _tokenIndex = 0;
    Token _currentToken;
    Stack!FunctionContext _functionContextStack;
    ExpressionNode[] _baseClassStack; // in case we have nested class declarations
}