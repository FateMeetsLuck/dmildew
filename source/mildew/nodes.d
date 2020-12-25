module mildew.nodes;

import std.format: format;

import mildew.lexer: Token;
import mildew.types: ScriptValue;

package:

/// root class of expression nodes
abstract class Node
{
    // have to override here for subclasses' override to work
    override string toString() const
    {
        assert(false, "This should never be called as it is virtual");
    }
}

class BinaryOpNode : Node
{
    this(Token op, Node left, Node right)
    {
        opToken = op;
        leftNode = left;
        rightNode = right;
    }

    override string toString() const
    {
        return format("BinaryOpNode: (%s %s %s)", leftNode, opToken, rightNode);
    }

    Token opToken;
    Node leftNode;
    Node rightNode;
}

class UnaryOpNode : Node
{
    this(Token op, Node operand)
    {
        opToken = op;
        operandNode = operand;
    }

    override string toString() const
    {
        return format("(%s %s)", opToken, operandNode);
    }

    Token opToken;
    Node operandNode;
}

class LiteralNode : Node 
{
    this(Token token, ScriptValue val)
    {
        literalToken = token;
        value = val;
    }

    override string toString() const
    {
        return value.toString();
    }

    Token literalToken;
    ScriptValue value;
}

class ArrayLiteralNode : Node 
{
    this(Node[] values)
    {
        valueNodes = values;
    }

    override string toString() const
    {
        return format("%s", valueNodes);
    }

    Node[] valueNodes;
}

class VarAccessNode : Node
{
    this(Token token)
    {
        varToken = token;
    }

    override string toString() const
    {
        return format("VarAccessNode %s", varToken.text);
    }

    Token varToken;
}

class FunctionCallNode : Node
{
    this(Node fn, Node[] args)
    {
        functionToCall = fn;
        expressionArgs = args;
    }

    override string toString() const
    {
        auto str = "FunctionCallNode " ~ functionToCall.toString ~ "(";
        for(size_t i = 0; i < expressionArgs.length; ++i)
        {
            str ~= expressionArgs[i].toString;
            if(i < expressionArgs.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                str ~= ", ";
        }
        str ~= ")";
        return str;
    }

    Node functionToCall;
    // todo handle "this", the object that calls
    Node[] expressionArgs;
}

// when [] operator is used
class ArrayIndexNode : Node 
{
    this(Node obj, Node index)
    {
        objectNode = obj;
        indexValueNode = index;
    }    

    override string toString() const
    {
        return objectNode.toString() ~ "[" ~ indexValueNode.toString() ~ "]";
    }

    Node objectNode;
    Node indexValueNode;
}

// when . is used. We will need helper functions to get the this and handle =
class MemberAccessNode : Node 
{
    this(Node obj, Node member)
    {
        objectNode = obj;
        memberNode = member;
    }

    override string toString() const
    {
        return objectNode.toString() ~ "." ~ memberNode.toString();
    }

    Node objectNode;
    Node memberNode;
}

/// root class of all statement nodes
abstract class StatementNode
{
    this(size_t lineNo)
    {
        line = lineNo;
    }

    override string toString() const
    {
        assert(false, "This method is virtual and should never be called directly");
    }

    size_t line;
}

class VarDeclarationStatementNode : StatementNode
{
    this(Token qual, Node[] nodes)
    {
        super(qual.position.line);
        qualifier = qual;
        varAccessOrAssignmentNodes = nodes;
    }

    override string toString() const
    {
        string str = qualifier.text ~ " ";
        for(size_t i = 0; i < varAccessOrAssignmentNodes.length; ++i)
        {
            str ~= varAccessOrAssignmentNodes[i].toString();
            if(i < varAccessOrAssignmentNodes.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                str ~= ", ";
        }
        return str;
    }

    Token qualifier; // must be var, let, or const
    Node[] varAccessOrAssignmentNodes; // must be VarAccessNode or VarAssignmentNode. should be validated by parser
}

class BlockStatementNode: StatementNode
{
    this(size_t lineNo, StatementNode[] statements)
    {
        super(lineNo);
        statementNodes = statements;
    }

    override string toString() const
    {
        string str = "{\n";
        foreach(st ; statementNodes)
        {
            str ~= st.toString ~ "\n";
        }
        str ~= "}";
        return str;
    }

    StatementNode[] statementNodes;
}

class IfStatementNode : StatementNode
{
    this(size_t lineNo, Node condition, StatementNode onTrue, StatementNode onFalse=null)
    {
        super(lineNo);
        conditionNode = condition;
        onTrueStatement = onTrue;
        onFalseStatement = onFalse;
    }

    override string toString() const
    {
        auto str = "if(" ~ conditionNode.toString() ~ ") ";
        str ~= onTrueStatement.toString();
        if(onFalseStatement !is null)
            str ~= " else " ~ onFalseStatement.toString();
        return str;
    }

    Node conditionNode;
    StatementNode onTrueStatement, onFalseStatement;
}

class WhileStatementNode : StatementNode
{
    this(size_t lineNo, Node condition, StatementNode bnode)
    {
        super(lineNo);
        conditionNode = condition;
        bodyNode = bnode;
    }

    override string toString() const
    {
        auto str = "while(" ~ conditionNode.toString() ~ ") ";
        str ~= bodyNode.toString();
        return str;
    }

    Node conditionNode;
    StatementNode bodyNode;
}

class DoWhileStatementNode : StatementNode
{
    this(size_t lineNo, StatementNode bnode, Node condition)
    {
        super(lineNo);
        bodyNode = bnode;
        conditionNode = condition;
    }

    override string toString() const
    {
        auto str = "do " ~ bodyNode.toString() ~ " while("
            ~ conditionNode.toString() ~ ")";
        return str;
    }

    StatementNode bodyNode;
    Node conditionNode;
}

class ForStatementNode : StatementNode
{
    this(size_t lineNo, VarDeclarationStatementNode decl, Node condition, Node increment, StatementNode bnode)
    {
        super(lineNo);
        varDeclarationStatement = decl;
        conditionNode = condition;
        incrementNode = increment;
        bodyNode = bnode;
    }

    override string toString() const
    {
        auto decl = "";
        if(varDeclarationStatement !is null)
            decl = varDeclarationStatement.toString();
        auto str = "for(" ~ decl ~ ";" ~ conditionNode.toString() 
            ~ ";" ~ incrementNode.toString() ~ ") " ~ bodyNode.toString();
        return str;
    }

    VarDeclarationStatementNode varDeclarationStatement;
    Node conditionNode;
    Node incrementNode;
    StatementNode bodyNode;
}

class BreakStatementNode : StatementNode
{
    this(size_t lineNo)
    {
        super(lineNo);
    }

    override string toString() const
    {
        return "break statement";
    }
}

class ContinueStatementNode : StatementNode
{
    this(size_t lineNo)
    {
        super(lineNo);
    }

    override string toString() const
    {
        return "continue statement";
    }
}

class ReturnStatementNode : StatementNode
{
    this(size_t lineNo, Node expr = null)
    {
        super(lineNo);
        expressionNode = expr;
    }

    override string toString() const
    {
        auto str = "return ";
        if(expressionNode !is null)
            str ~= expressionNode.toString;
        return str;
    }

    Node expressionNode;
}

class FunctionDeclarationStatementNode : StatementNode
{
    this(size_t lineNo, string n, string[] args, StatementNode[] statements)
    {
        super(lineNo);
        name = n;
        argNames = args;
        statementNodes = statements;
    }

    override string toString() const
    {
        auto str = "function " ~ name ~ "(";
        for(int i = 0; i < argNames.length; ++i)
        {
            str ~= argNames[i];
            if(i < argNames.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                str ~= ", ";
        }
        str ~= ") {";
        foreach(st ; statementNodes)
            str ~= "\t" ~ st.toString;
        str ~= "}";
        return str;
    }

    string name;
    string[] argNames;
    StatementNode[] statementNodes;
}

class ExpressionStatementNode: StatementNode
{
    this(size_t lineNo, Node expression)
    {
        super(lineNo);
        expressionNode = expression;
    }

    override string toString() const
    {
        if(expressionNode is null)
            return "empty statement";
        return "expression statement: " ~ expressionNode.toString();
    }

    Node expressionNode;
}