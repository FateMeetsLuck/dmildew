/**
 * This module implements the expression and statement node subclasses, which are used internally as a syntax tree.
 */
module mildew.nodes;

import std.format: format;
import std.variant;

import mildew.environment: Environment;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token;
import mildew.types;
import mildew.visitors;

package:

/// handles class expression and declaration data
class ClassDefinition
{
    this(string clsname, FunctionLiteralNode ctor,
            string[] mnames, FunctionLiteralNode[] ms,
            string[] gmnames, FunctionLiteralNode[] gms,
            string[] smnames, FunctionLiteralNode[] sms,
            string[] statNames, FunctionLiteralNode[] statms,
            ExpressionNode base = null)
    {
        className = clsname;
        constructor = ctor;
        methodNames = mnames;
        methods = ms;
        assert(methodNames.length == methods.length);
        getMethodNames = gmnames;
        getMethods = gms;
        assert(getMethodNames.length == getMethods.length);
        setMethodNames = smnames;
        setMethods = sms;
        assert(setMethodNames.length == setMethods.length);
        staticMethodNames = statNames;
        staticMethods = statms;
        assert(staticMethodNames.length == staticMethods.length);
        baseClass = base;
    }

    ScriptFunction create(Environment environment)
    {
        import mildew.interpreter: Interpreter;

        ScriptFunction ctor;
        if(constructor !is null)
            ctor = new ScriptFunction(className, constructor.argList, constructor.statements, environment, true);
        else
            ctor = ScriptFunction.emptyFunction(className, true);
        // fill in the function.prototype with the methods
        for(size_t i = 0; i < methodNames.length; ++i) 
		{
            ctor["prototype"][methodNames[i]] = new ScriptFunction(methodNames[i], 
                    methods[i].argList, methods[i].statements, environment, false);
		}
        // fill in any get properties
        for(size_t i = 0; i < getMethodNames.length; ++i)
		{
            ctor["prototype"].addGetterProperty(getMethodNames[i], new ScriptFunction(
                getMethodNames[i], getMethods[i].argList, getMethods[i].statements, 
                environment, false));
		}
        // fill in any set properties
        for(size_t i = 0; i < setMethodNames.length; ++i)
		{
            ctor["prototype"].addSetterProperty(setMethodNames[i], new ScriptFunction(
                setMethodNames[i], setMethods[i].argList, setMethods[i].statements,
                environment, false));
		}
		// static methods are assigned directly to the constructor itself
		for(size_t i=0; i < staticMethodNames.length; ++i)
		{
			ctor[staticMethodNames[i]] = new ScriptFunction(staticMethodNames[i], 
                staticMethods[i].argList, staticMethods[i].statements, environment, false);
		}

        if(baseClass !is null)
        {
            immutable vr = cast(immutable)baseClass.accept(environment.interpreter).get!(Interpreter.VisitResult);
            if(vr.exception !is null)
                throw vr.exception;
            if(vr.result.type != ScriptAny.Type.FUNCTION)
            {
                throw new ScriptRuntimeException("Only classes can be extended");
            }   
            auto baseClassConstructor = vr.result.toValue!ScriptFunction;
            auto constructorPrototype = ctor["prototype"].toValue!ScriptObject;
            // if the base class constructor's "prototype" is null or non-object, it won't work anyway
            // NOTE that ["prototype"] and .prototype are completely unrelated
            constructorPrototype.prototype = baseClassConstructor["prototype"].toValue!ScriptObject;
            // set the constructor's __proto__ to the base class so that static methods are inherited
            // and the Function.call look up should still work
            ctor.prototype = baseClassConstructor;
        }
        return ctor;
    }

    override string toString() const 
    {
        string output = "class " ~ className;
        if(baseClass) output ~= " extends " ~ baseClass.toString();
        output ~= " {...}";
        return output;
    }

    string className;
    FunctionLiteralNode constructor;
    string[] methodNames;
    FunctionLiteralNode[] methods;
    string[] getMethodNames;
    FunctionLiteralNode[] getMethods;
    string[] setMethodNames;
    FunctionLiteralNode[] setMethods;
	string[] staticMethodNames;
	FunctionLiteralNode[] staticMethods;
    ExpressionNode baseClass; // should be an expression that returns a constructor function
}

/// root class of expression nodes
abstract class ExpressionNode
{
	abstract Variant accept(IExpressionVisitor visitor);

    // have to override here for subclasses' override to work
    override string toString() const
    {
        assert(false, "This should never be called as it is virtual");
    }
}

class LiteralNode : ExpressionNode 
{
    this(Token token, ScriptAny val)
    {
        literalToken = token;
        value = val;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitLiteralNode(this);
	}

    override string toString() const
    {
        if(value.type == ScriptAny.Type.STRING)
            return "\"" ~ literalToken.text ~ "\"";
        else
            return literalToken.text;
    }

    Token literalToken;
    ScriptAny value;
}

class FunctionLiteralNode : ExpressionNode
{
    this(string[] args, StatementNode[] stmts)
    {
        argList = args;
        statements = stmts;
    }

    override Variant accept(IExpressionVisitor visitor)
    {
        return visitor.visitFunctionLiteralNode(this);
    }

    override string toString() const
    {
        string output = "function(";
        for(size_t i = 0; i < argList.length; ++i)
        {
            output ~= argList[i];
            if(i < argList.length - 1)
                output ~= ", ";
        }
        output ~= "){\n";
        foreach(stmt ; statements)
        {
            output ~= "\t" ~ stmt.toString();
        }
        output ~= "\n}";
        return output;
    }

    string[] argList;
    StatementNode[] statements;
    string optionalName;
}

class TemplateStringNode : ExpressionNode
{
    this(ExpressionNode[] ns)
    {
        nodes = ns;
    }

    override Variant accept(IExpressionVisitor visitor)
    {
        return visitor.visitTemplateStringNode(this);
    }

    override string toString() const
    {
        import std.format: format;
        string output = "`";
        foreach(node ; nodes)
        {
            if(auto lit = cast(LiteralNode)node)
                output ~= lit.literalToken.text;
            else // any other expression
                output ~= format("${%s}", node.toString());
        }
        output ~= "`";
        return output;
    }

    ExpressionNode[] nodes;
}

class ArrayLiteralNode : ExpressionNode 
{
    this(ExpressionNode[] values)
    {
        valueNodes = values;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitArrayLiteralNode(this);
	}

    override string toString() const
    {
        return format("%s", valueNodes);
    }

    ExpressionNode[] valueNodes;
}

class ObjectLiteralNode : ExpressionNode 
{
    this(string[] ks, ExpressionNode[] vs)
    {
        keys = ks;
        valueNodes = vs;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitObjectLiteralNode(this);
	}

    override string toString() const
    {
        // return "(object literal node)";
        if(keys.length != valueNodes.length)
            return "{invalid_object}";
        auto result = "{";
        for(size_t i = 0; i < keys.length; ++i)
            result ~= keys[i] ~ ":" ~ valueNodes[i].toString;
        result ~= "}";
        return result;
    }

    string[] keys;
    ExpressionNode[] valueNodes;
}

class ClassLiteralNode : ExpressionNode 
{
    this(ClassDefinition cdef)
    {
        classDefinition = cdef;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitClassLiteralNode(this);
	}

    override string toString() const 
    {
        return classDefinition.toString();
    }

    ClassDefinition classDefinition;
}

class BinaryOpNode : ExpressionNode
{
    this(Token op, ExpressionNode left, ExpressionNode right)
    {
        opToken = op;
        leftNode = left;
        rightNode = right;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitBinaryOpNode(this);
	}

    override string toString() const
    {
        return format("(%s %s %s)", leftNode, opToken.symbol, rightNode);
    }

    Token opToken;
    ExpressionNode leftNode;
    ExpressionNode rightNode;
}

class UnaryOpNode : ExpressionNode
{
    this(Token op, ExpressionNode operand)
    {
        opToken = op;
        operandNode = operand;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitUnaryOpNode(this);
	}

    override string toString() const
    {
        return format("(%s %s)", opToken.symbol, operandNode);
    }

    Token opToken;
    ExpressionNode operandNode;
}

class PostfixOpNode : ExpressionNode 
{
    this(Token op, ExpressionNode node)
    {
        opToken = op;
        operandNode = node;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitPostfixOpNode(this);
	}

    override string toString() const 
    {
        return operandNode.toString() ~ opToken.symbol;
    }

    Token opToken;
    ExpressionNode operandNode;
}

class TerniaryOpNode : ExpressionNode 
{
    this(ExpressionNode cond, ExpressionNode onTrue, ExpressionNode onFalse)
    {
        conditionNode = cond;
        onTrueNode = onTrue;
        onFalseNode = onFalse;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitTerniaryOpNode(this);
	}

    override string toString() const 
    {
        return conditionNode.toString() ~ "? " ~ onTrueNode.toString() ~ " : " ~ onFalseNode.toString();
    }

    ExpressionNode conditionNode;
    ExpressionNode onTrueNode;
    ExpressionNode onFalseNode;
}

class VarAccessNode : ExpressionNode
{
    this(Token token)
    {
        varToken = token;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitVarAccessNode(this);
	}

    override string toString() const
    {
        return varToken.text;
    }

    Token varToken;
}

class FunctionCallNode : ExpressionNode
{
    this(ExpressionNode fn, ExpressionNode[] args, bool retThis=false)
    {
        functionToCall = fn;
        expressionArgs = args;
        returnThis = retThis;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitFunctionCallNode(this);
	}

    override string toString() const
    {
        auto str = functionToCall.toString ~ "(";
        for(size_t i = 0; i < expressionArgs.length; ++i)
        {
            str ~= expressionArgs[i].toString;
            if(i < expressionArgs.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                str ~= ", ";
        }
        str ~= ")";
        return str;
    }

    ExpressionNode functionToCall;
    ExpressionNode[] expressionArgs;
    bool returnThis;
}

// when [] operator is used
class ArrayIndexNode : ExpressionNode 
{
    this(ExpressionNode obj, ExpressionNode index)
    {
        objectNode = obj;
        indexValueNode = index;
    }    

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitArrayIndexNode(this);
	}

    override string toString() const
    {
        return objectNode.toString() ~ "[" ~ indexValueNode.toString() ~ "]";
    }

    ExpressionNode objectNode;
    ExpressionNode indexValueNode;
}

class MemberAccessNode : ExpressionNode 
{
    this(ExpressionNode obj, Token dt, ExpressionNode member)
    {
        objectNode = obj;
        dotToken = dt;
        memberNode = member;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitMemberAccessNode(this);
	}

    override string toString() const
    {
        return objectNode.toString() ~ "." ~ memberNode.toString();
    }

    ExpressionNode objectNode;
    Token dotToken;
    ExpressionNode memberNode;
}

class NewExpressionNode : ExpressionNode 
{
    this(ExpressionNode fn)
    {
        functionCallExpression = fn;
    }

	override Variant accept(IExpressionVisitor visitor)
	{
		return visitor.visitNewExpressionNode(this);
	}

    override string toString() const
    {
        return "new " ~ functionCallExpression.toString();
    }

    ExpressionNode functionCallExpression;
}

/// root class of all statement nodes
abstract class StatementNode
{
    this(size_t lineNo)
    {
        line = lineNo;
    }

	abstract Variant accept(IStatementVisitor visitor);

    override string toString() const
    {
        assert(false, "This method is virtual and should never be called directly");
    }

    immutable size_t line;
}

class VarDeclarationStatementNode : StatementNode
{
    this(Token qual, ExpressionNode[] nodes)
    {
        super(qual.position.line);
        qualifier = qual;
        varAccessOrAssignmentNodes = nodes;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitVarDeclarationStatementNode(this);
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
    ExpressionNode[] varAccessOrAssignmentNodes; // must be VarAccessNode or BinaryOpNode. should be validated by parser
}

class BlockStatementNode: StatementNode
{
    this(size_t lineNo, StatementNode[] statements)
    {
        super(lineNo);
        statementNodes = statements;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitBlockStatementNode(this);
	}

    override string toString() const
    {
        string str = "{\n";
        foreach(st ; statementNodes)
        {
            str ~= "  " ~ st.toString ~ "\n";
        }
        str ~= "}";
        return str;
    }

    StatementNode[] statementNodes;
}

class IfStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode condition, StatementNode onTrue, StatementNode onFalse=null)
    {
        super(lineNo);
        conditionNode = condition;
        onTrueStatement = onTrue;
        onFalseStatement = onFalse;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitIfStatementNode(this);
	}

    override string toString() const
    {
        auto str = "if(" ~ conditionNode.toString() ~ ") ";
        str ~= onTrueStatement.toString();
        if(onFalseStatement !is null)
            str ~= " else " ~ onFalseStatement.toString();
        return str;
    }

    ExpressionNode conditionNode;
    StatementNode onTrueStatement, onFalseStatement;
}

class SwitchStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode expr, SwitchBody sbody)
    {
        super(lineNo);
        expressionNode = expr;
        switchBody = sbody;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitSwitchStatementNode(this);
	}

    ExpressionNode expressionNode; // expression to test
    SwitchBody switchBody;
}

class SwitchBody
{
    this(StatementNode[] statements, size_t defaultID, size_t[ScriptAny] jumpTableID)
    {
        statementNodes = statements;
        defaultStatementID = defaultID;
        jumpTable = jumpTableID;
    }

    StatementNode[] statementNodes;
    size_t defaultStatementID; // index into statementNodes
    size_t[ScriptAny] jumpTable; // indexes into statementNodes
}

class WhileStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode condition, StatementNode bnode, string lbl = "")
    {
        super(lineNo);
        conditionNode = condition;
        bodyNode = bnode;
        label = lbl;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitWhileStatementNode(this);
	}

    override string toString() const
    {
        auto str = "while(" ~ conditionNode.toString() ~ ") ";
        str ~= bodyNode.toString();
        return str;
    }

    ExpressionNode conditionNode;
    StatementNode bodyNode;
    string label;
}

class DoWhileStatementNode : StatementNode
{
    this(size_t lineNo, StatementNode bnode, ExpressionNode condition, string lbl="")
    {
        super(lineNo);
        bodyNode = bnode;
        conditionNode = condition;
        label = lbl;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitDoWhileStatementNode(this);
	}

    override string toString() const
    {
        auto str = "do " ~ bodyNode.toString() ~ " while("
            ~ conditionNode.toString() ~ ")";
        return str;
    }

    StatementNode bodyNode;
    ExpressionNode conditionNode;
    string label;
}

class ForStatementNode : StatementNode
{
    this(size_t lineNo, VarDeclarationStatementNode decl, ExpressionNode condition, ExpressionNode increment, 
         StatementNode bnode, string lbl="")
    {
        super(lineNo);
        varDeclarationStatement = decl;
        conditionNode = condition;
        incrementNode = increment;
        bodyNode = bnode;
        label = lbl;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitForStatementNode(this);
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
    ExpressionNode conditionNode;
    ExpressionNode incrementNode;
    StatementNode bodyNode;
    string label;
}

// for of can't do let {a,b} but it can do let a,b and be used the same as for in in JS
class ForOfStatementNode : StatementNode
{
    this(size_t lineNo, Token qual, VarAccessNode[] vans, ExpressionNode obj, StatementNode bnode, string lbl="")
    {
        super(lineNo);
        qualifierToken = qual;
        varAccessNodes = vans;
        objectToIterateNode = obj;
        bodyNode = bnode;
        label = lbl;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitForOfStatementNode(this);
	}

    override string toString() const
    {
        auto str = "for(" ~ qualifierToken.text;
        for(size_t i = 0; i < varAccessNodes.length; ++i)
        {
            str ~= varAccessNodes[i].varToken.text;
            if(i < varAccessNodes.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                str ~= ", ";
        }
        str ~= " of " 
            ~ objectToIterateNode.toString() ~ ")" 
            ~ bodyNode.toString();
        return str;
    }

    Token qualifierToken;
    VarAccessNode[] varAccessNodes;
    ExpressionNode objectToIterateNode;
    StatementNode bodyNode;
    string label;
}

class BreakStatementNode : StatementNode
{
    this(size_t lineNo, string lbl="")
    {
        super(lineNo);
        label = lbl;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitBreakStatementNode(this);
	}

    override string toString() const
    {
        return "break " ~ label ~ ";";
    }

    string label;
}

class ContinueStatementNode : StatementNode
{
    this(size_t lineNo, string lbl = "")
    {
        super(lineNo);
        label = lbl;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitContinueStatementNode(this);
	}

    override string toString() const
    {
        return "continue " ~ label ~ ";";
    }

    string label;
}

class ReturnStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode expr = null)
    {
        super(lineNo);
        expressionNode = expr;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitReturnStatementNode(this);
	}

    override string toString() const
    {
        auto str = "return";
        if(expressionNode !is null)
            str ~= " " ~ expressionNode.toString;
        return str ~ ";";
    }

    ExpressionNode expressionNode;
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

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitFunctionDeclarationStatementNode(this);
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

class ThrowStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode expr)
    {
        super(lineNo);
        expressionNode = expr;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitThrowStatementNode(this);
	}

    override string toString() const
    {
        return "throw " ~ expressionNode.toString() ~ ";";
    }

    ExpressionNode expressionNode;
}

class TryCatchBlockStatementNode : StatementNode
{
    this(size_t lineNo, StatementNode tryBlock, string name, StatementNode catchBlock)
    {
        super(lineNo);
        tryBlockNode = tryBlock;
        exceptionName = name;
        catchBlockNode = catchBlock;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitTryCatchBlockStatementNode(this);
	}

    override string toString() const
    {
        return "try " ~ tryBlockNode.toString ~ " catch(" ~ exceptionName ~ ")"
            ~ catchBlockNode.toString;
    }

    StatementNode tryBlockNode;
    string exceptionName;
    StatementNode catchBlockNode;
}

class DeleteStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode accessNode)
    {
        super(lineNo);
        memberAccessOrArrayIndexNode = accessNode;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitDeleteStatementNode(this);
	}

    override string toString() const
    {
        return "delete " ~ memberAccessOrArrayIndexNode.toString ~ ";";
    }

    ExpressionNode memberAccessOrArrayIndexNode;
}

class ClassDeclarationStatementNode : StatementNode
{
    this(size_t lineNo, ClassDefinition cdef)
    {
        super(lineNo);
        classDefinition = cdef;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitClassDeclarationStatementNode(this);
	}

    ClassDefinition classDefinition;
}

class SuperCallStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode ctc, ExpressionNode[] args)
    {
        super(lineNo);
        classConstructorToCall = ctc; // Cannot be null or something wrong with parser
        argExpressionNodes = args;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitSuperCallStatementNode(this);
	}

    ExpressionNode classConstructorToCall; // should always evaluate to a function
    ExpressionNode[] argExpressionNodes;
}

class ExpressionStatementNode : StatementNode
{
    this(size_t lineNo, ExpressionNode expression)
    {
        super(lineNo);
        expressionNode = expression;
    }

	override Variant accept(IStatementVisitor visitor)
	{
		return visitor.visitExpressionStatementNode(this);
	}

    override string toString() const
    {
        if(expressionNode is null)
            return ";";
        return expressionNode.toString() ~ ";";
    }

    ExpressionNode expressionNode;
}
