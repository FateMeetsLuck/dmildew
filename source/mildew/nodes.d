/**
 * This module implements the Node subclasses, which are used internally as a syntax tree by the Interpreter
 */
module mildew.nodes;

import std.format: format;

import mildew.context: Context;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token;
import mildew.types: ScriptValue, ScriptFunction, ScriptObject;

package:

/// root class of expression nodes
abstract class Node
{
    // have to override here for subclasses' override to work
    override string toString() const
    {
        assert(false, "This should never be called as it is virtual");
    }

    abstract VisitResult visit(Context c);
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
        if(value.type == ScriptValue.Type.STRING)
            return "\"" ~ literalToken.text ~ "\"";
        else
            return literalToken.text;
    }

    override VisitResult visit(Context c)
    {
        return VisitResult(value);
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

    override VisitResult visit(Context c)
    {
        VisitResult vr;
        ScriptValue[] values = [];
        foreach(expression ; valueNodes)
        {
            vr = expression.visit(c);
            if(vr.exception !is null)
                return vr;
            values ~= vr.result;
        }
        vr.result = values;
        return vr;        
    }

    Node[] valueNodes;
}

class ObjectLiteralNode : Node 
{
    this(string[] ks, Node[] vs)
    {
        keys = ks;
        valueNodes = vs;
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

    override VisitResult visit(Context c)
    {
        if(keys.length != valueNodes.length)
            throw new Exception("Error with object literal node");
        ScriptValue[] vals = [];
        VisitResult vr;
        foreach(valueNode ; valueNodes)
        {
            vr = valueNode.visit(c);
            if(vr.exception !is null)
                return vr;
            vals ~= vr.result;
        }
        // TODO a universal prototype for objects?
        auto obj = new ScriptObject("", null, null);
        for(size_t i = 0; i < keys.length; ++i)
        {
            obj[keys[i]] = vals[i];
        }
        vr.result = obj;
        return vr;
    }

    string[] keys;
    Node[] valueNodes;
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
        return format("(%s %s %s)", leftNode, opToken.symbol, rightNode);
    }

    override VisitResult visit(Context c)
    {
        import std.conv: to;
        // TODO handle in and instance of operators
        // for now just do math
        auto lhsResult = leftNode.visit(c);
        auto rhsResult = rightNode.visit(c);

        if(lhsResult.exception !is null)
            return lhsResult;
        if(rhsResult.exception !is null)
            return rhsResult;

        VisitResult finalResult;

        if(opToken.isAssignmentOperator)
        {
            final switch(lhsResult.accessType)
            {
                case VisitResult.AccessType.NO_ACCESS:
                    finalResult.exception = new ScriptRuntimeException("Invalid left hand assignment");
                    return finalResult;
                case VisitResult.AccessType.VAR_ACCESS:
                    return handleVarReassignment(c, opToken, lhsResult.memberOrVarToAccess, rhsResult.result);
                case VisitResult.AccessType.ARRAY_ACCESS:
                    return handleArrayReassignment(c, opToken, lhsResult.objectToAccess, lhsResult.indexToAccess, 
                        rhsResult.result);
                case VisitResult.AccessType.OBJECT_ACCESS:
                    return handleObjectReassignment(c, opToken, lhsResult.objectToAccess, lhsResult.memberOrVarToAccess, 
                        rhsResult.result);
            }
        }

        auto lhs = lhsResult.result;
        auto rhs = rhsResult.result;

        switch(opToken.type)
        {
            case Token.Type.POW:
                return VisitResult(lhs ^^ rhs);
            case Token.Type.STAR:
                return VisitResult(lhs * rhs);
            case Token.Type.FSLASH:
                return VisitResult(lhs / rhs);
            case Token.Type.PERCENT:
                return VisitResult(lhs % rhs);
            case Token.Type.PLUS:
                return VisitResult(lhs + rhs);
            case Token.Type.DASH:
                return VisitResult(lhs - rhs);
            case Token.Type.BIT_LSHIFT:
                return VisitResult(lhs << rhs);
            case Token.Type.BIT_RSHIFT:
                return VisitResult(lhs >> rhs);
            case Token.Type.BIT_URSHIFT:
                return VisitResult(lhs >>> rhs);
            case Token.Type.GT:
                return VisitResult(lhs > rhs);
            case Token.Type.GE:
                return VisitResult(lhs >= rhs);
            case Token.Type.LT:
                return VisitResult(lhs < rhs);
            case Token.Type.LE:
                return VisitResult(lhs <= rhs);
            case Token.Type.EQUALS:
                return VisitResult(lhs == rhs);
            case Token.Type.NEQUALS:
                return VisitResult(lhs != rhs);
            case Token.Type.STRICT_EQUALS:
                return VisitResult(lhs.strictEquals(rhs));
            case Token.Type.STRICT_NEQUALS:
                return VisitResult(!lhs.strictEquals(rhs));
            case Token.Type.BIT_AND:
                return VisitResult(lhs & rhs);
            case Token.Type.BIT_XOR:
                return VisitResult(lhs ^ rhs);
            case Token.Type.BIT_OR:
                return VisitResult(lhs | rhs); 
            default:
                throw new Exception("Forgot to implement missing binary operator " ~ opToken.type.to!string);
                // return VisitResult(ScriptValue.UNDEFINED);
        }
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
        return format("(%s %s)", opToken.symbol, operandNode);
    }

    override VisitResult visit(Context c)
    {
        // TODO handle ++, -- if operandNode is a VarAccessNode
        auto vr = operandNode.visit(c);
        if(vr.exception !is null)
            return vr;
        auto value = vr.result;
        switch(opToken.type)
        {
            case Token.Type.BIT_NOT:
                return VisitResult(~value);
            case Token.Type.NOT:
                return VisitResult(!value);
            case Token.Type.PLUS:
                return VisitResult(value);
            case Token.Type.DASH:
                return VisitResult(-value);
            default:
                if(opToken.isKeyword("typeof"))
                    return VisitResult(value.typeToString());
                return VisitResult(ScriptValue.UNDEFINED);
        }
    }

    Token opToken;
    Node operandNode;
}

class VarAccessNode : Node
{
    this(Token token)
    {
        varToken = token;
    }

    override string toString() const
    {
        return varToken.text;
    }

    override VisitResult visit(Context c)
    {
        VisitResult vr;
        vr.accessType = VisitResult.AccessType.VAR_ACCESS;
        vr.memberOrVarToAccess = varToken.text;
        bool _; // @suppress(dscanner.suspicious.unmodified)
        immutable ptr = cast(immutable)c.lookupVariableOrConst(varToken.text, _);
        if(ptr == null)
            vr.exception = new ScriptRuntimeException("Undefined variable lookup " ~ varToken.text);
        else
            vr.result = *ptr;
        return vr;
    }

    Token varToken;
}

class FunctionCallNode : Node
{
    this(Node fn, Node[] args, bool retThis=false)
    {
        functionToCall = fn;
        expressionArgs = args;
        returnThis = retThis;
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

    override VisitResult visit(Context c)
    {
        ScriptValue thisObj; // TODO get the possible global "this" object
        auto vr = functionToCall.visit(c);

        if(vr.exception !is null)
            return vr;

        if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS 
            || vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
        {
            thisObj = vr.objectToAccess;
        }

        auto fnToCall = vr.result;
        if(fnToCall.type == ScriptValue.Type.FUNCTION)
        {
            ScriptValue[] args;
            vr = convertExpressionsToArgs(c, expressionArgs, args);
            if(vr.exception !is null)
                return vr;
            auto fn = fnToCall.toValue!ScriptFunction;
            vr = callFunction(c, fn, thisObj, args, returnThis);
            return vr;
        }
        else 
        {
            vr.result = ScriptValue.UNDEFINED;
            vr.exception = new ScriptRuntimeException("Unable to call non function " ~ fnToCall.toString);
            return vr;
        }
    }

    Node functionToCall;
    Node[] expressionArgs;
    bool returnThis;
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

    // we must determine if it is an object access or an array access according to the type of index
    override VisitResult visit(Context c)
    {
        VisitResult vr = indexValueNode.visit(c);
        if(vr.exception !is null)
            return vr;
        auto index = vr.result;
        auto objVR = objectNode.visit(c);
        if(objVR.exception !is null)
            return objVR;

        if(index.type == ScriptValue.Type.STRING)
        {
            // we have to be accessing an object or trying to
            vr.accessType = VisitResult.AccessType.OBJECT_ACCESS;
            vr.memberOrVarToAccess = index.toString();
            vr.objectToAccess = objVR.result;
            vr.result = vr.objectToAccess[vr.memberOrVarToAccess];
        }
        else if(index.isNumber)
        {
            // we have to be accessing a string or array or trying to
            vr.accessType = VisitResult.AccessType.ARRAY_ACCESS;
            vr.indexToAccess = index.toValue!size_t;
            vr.objectToAccess = objVR.result;
            vr.result = vr.objectToAccess[vr.indexToAccess];
        }
        else
        {
            vr.exception = new ScriptRuntimeException("Invalid index type for array or object access");
        }
        return vr;
    }

    Node objectNode;
    Node indexValueNode;
}

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

    // this will always be an object access type
    override VisitResult visit(Context c)
    {
        // auto vr = memberNode.visit(c);
        VisitResult vr;
        string memberName = "";
        if(auto van = cast(VarAccessNode)memberNode)
        {
            memberName = van.varToken.text;
        }
        else
        {
            vr.exception = new ScriptRuntimeException("Invalid operand for object member access");
            return vr;
        }

        auto objVR = objectNode.visit(c);
        if(objVR.exception !is null)
            return objVR;

        // set the fields
        vr.accessType = VisitResult.AccessType.OBJECT_ACCESS;
        vr.objectToAccess = objVR.result;
        vr.memberOrVarToAccess = memberName;
        vr.result = objVR.result[memberName];
        return vr;
    }

    Node objectNode;
    Node memberNode;
}

class NewExpressionNode : Node 
{
    this(Node fn)
    {
        functionCallExpression = fn;
    }

    override string toString() const
    {
        return "new " ~ functionCallExpression.toString();
    }

    override VisitResult visit(Context c)
    {
        // fce should be a valid function call with its returnThis flag already set by the parser
        auto vr = functionCallExpression.visit(c);
        return vr; // caller will check for any exceptions.
    }

    Node functionCallExpression;
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

    abstract VisitResult visit(Context c);

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

    override VisitResult visit(Context context)
    {
        VisitResult visitResult;
        foreach(varNode; varAccessOrAssignmentNodes)
        {
            if(auto v = cast(VarAccessNode)varNode)
            {
                if(qualifier.text == "var")
                {
                    if(!context.getGlobalContext.declareVariableOrConst(v.varToken.text, 
                            ScriptValue.UNDEFINED, false))
                    {
                        // throw new Exception("Attempt to redeclare global " ~ v.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare global "
                            ~ v.varToken.text);
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }
                }
                else if(qualifier.text == "let")
                {
                    if(!context.declareVariableOrConst(v.varToken.text, ScriptValue.UNDEFINED, false))
                    {
                        // throw new Exception("Attempt to redeclare local " ~ v.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare local "
                            ~ v.varToken.text);
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }
                }
                else if(qualifier.text == "const")
                {
                    if(!context.declareVariableOrConst(v.varToken.text, ScriptValue.UNDEFINED, true))
                    {
                        // throw new Exception("Attempt to redeclare const " ~ v.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare const "
                            ~ v.varToken.text);
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }
                }
                else 
                    throw new Exception("Something has gone very wrong in " ~ __FUNCTION__);
            }
            else
            {
                auto binNode = cast(BinaryOpNode)varNode;
                visitResult = binNode.rightNode.visit(context);
                if(visitResult.exception !is null)
                    return visitResult;
                auto valueToAssign = visitResult.result;
                // we checked this before so should be safe
                auto van = cast(VarAccessNode)(binNode.leftNode);
                auto name = van.varToken.text;
                if(qualifier.text == "var")
                {
                    // global variable
                    if(!context.getGlobalContext.declareVariableOrConst(name, valueToAssign, false))
                    {
                        // throw new Exception("Attempt to redeclare global variable " ~ v.leftNode.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare global variable "
                            ~ name);
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }
                }
                else if(qualifier.text == "let")
                {
                    // local variable
                    if(!context.declareVariableOrConst(name, valueToAssign, false))
                    {
                        // throw new Exception("Attempt to redeclare local variable " ~ v.leftNode.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare local variable "
                            ~ name);
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }
                }
                else if(qualifier.text == "const")
                {
                    if(!context.declareVariableOrConst(name, valueToAssign, true))
                    {
                        // throw new Exception("Attempt to redeclare local const " ~ v.leftNode.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare local const "
                            ~ name);
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }           
                }
                // success so make sure anon function name matches
                if(valueToAssign.type == ScriptValue.Type.FUNCTION)
                {
                    auto func = valueToAssign.toValue!ScriptFunction;
                    if(func.functionName == "<anonymous function>")
                        func.functionName = van.varToken.text;
                }
            }
        }
        return VisitResult(ScriptValue.UNDEFINED);
    }

    Token qualifier; // must be var, let, or const
    Node[] varAccessOrAssignmentNodes; // must be VarAccessNode or BinaryOpNode. should be validated by parser
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
            str ~= "  " ~ st.toString ~ "\n";
        }
        str ~= "}";
        return str;
    }

    override VisitResult visit(Context context)
    {
        context = new Context(context, "<scope>");
        auto result = VisitResult(ScriptValue.UNDEFINED);
        foreach(statement ; statementNodes)
        {
            result = statement.visit(context);
            if(result.returnFlag || result.breakFlag || result.continueFlag || result.exception !is null)
                break;
        }   
        context = context.parent;
        return result;
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

    override VisitResult visit(Context c)
    {
        auto vr = conditionNode.visit(c);
        if(vr.exception !is null)
        {
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
        if(vr.result)
        {
            vr = onTrueStatement.visit(c);
        }
        else 
        {
            if(onFalseStatement !is null)
                vr = onFalseStatement.visit(c);
        }
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        return vr;
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

    override VisitResult visit(Context c)
    {
        auto vr = conditionNode.visit(c);
        while(vr.result && vr.exception is null)
        {
            vr = bodyNode.visit(c);
            if(vr.breakFlag) // TODO labels
            {
                vr.breakFlag = false;
                break;
            }
            if(vr.continueFlag)
                vr.continueFlag = false;
            if(vr.exception !is null || vr.returnFlag)
                break;
            vr = conditionNode.visit(c);
        }
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        return vr;
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

    override VisitResult visit(Context c)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        do 
        {
            vr = bodyNode.visit(c);
            if(vr.breakFlag) // TODO labels
            {
                vr.breakFlag = false;
                break;
            }
            if(vr.continueFlag)
                vr.continueFlag = false;
            if(vr.exception !is null || vr.returnFlag)
                break; 
            vr = conditionNode.visit(c);
        }
        while(vr.result && vr.exception is null);
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        return vr;
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

    override VisitResult visit(Context context)
    {
        context = new Context(context, "<outer_for_loop>");
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        if(varDeclarationStatement !is null)
            vr = varDeclarationStatement.visit(context);
        if(vr.exception is null)
        {
            vr = conditionNode.visit(context);
            while(vr.result && vr.exception is null)
            {
                vr = bodyNode.visit(context);
                if(vr.breakFlag)
                {
                    vr.breakFlag = false;
                    break;
                }
                if(vr.continueFlag)
                    vr.continueFlag = false;
                if(vr.exception !is null || vr.returnFlag)
                    break; 
                vr = incrementNode.visit(context);
                if(vr.exception !is null)
                    break;
                vr = conditionNode.visit(context);
            }
        }
        context = context.parent;
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        return vr;
    }

    VarDeclarationStatementNode varDeclarationStatement;
    Node conditionNode;
    Node incrementNode;
    StatementNode bodyNode;
}

// for of can't do let {a,b} but it can do let a,b and be used the same as for in in JS
class ForOfStatementNode : StatementNode
{
    this(size_t lineNo, Token qual, VarAccessNode[] vans, Node obj, StatementNode bnode)
    {
        super(lineNo);
        qualifierToken = qual;
        varAccessNodes = vans;
        objectToIterateNode = obj;
        bodyNode = bnode;
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

    override VisitResult visit(Context context)
    {
        auto vr = objectToIterateNode.visit(context);
        // make sure this is iterable
        if(vr.exception !is null)
        {
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
        
        if(vr.result.isObject)
        {
            auto obj = vr.result.toValue!ScriptObject;
            // first value is key, second value is value if there
            foreach(key, val; obj.members)
            {
                // TODO optimize this to reassign variables instead of creating new ones each iteration
                context = new Context(context, "<for_of_loop>");
                context.declareVariableOrConst(varAccessNodes[0].varToken.text,
                    ScriptValue(key), qualifierToken.text == "const" ? true: false);
                if(varAccessNodes.length > 1)
                    context.declareVariableOrConst(varAccessNodes[1].varToken.text,
                        ScriptValue(val), qualifierToken.text == "const" ? true: false);
                vr = bodyNode.visit(context);              
                context = context.parent;
                if(vr.breakFlag)
                {
                    vr.breakFlag = false;
                    break;
                }
                if(vr.continueFlag)
                    vr.continueFlag = false;
                if(vr.exception !is null || vr.returnFlag)
                    break; 
                if(vr.exception !is null)
                    break;  
            }
        }
        else if(vr.result.type == ScriptValue.Type.ARRAY)
        {
            auto arr = vr.result.toValue!(ScriptValue[]);
            for(size_t i = 0; i < arr.length; ++i)
            {
                // TODO optimize this to reassign variables instead of creating new contexts each iteration
                context = new Context(context, "<for_of_loop>");
                // if one var access node, then value, otherwise index then value
                if(varAccessNodes.length == 1)
                {
                    context.declareVariableOrConst(varAccessNodes[0].varToken.text,
                        arr[i], qualifierToken.text == "const"? true: false);
                }
                else 
                {
                    context.declareVariableOrConst(varAccessNodes[0].varToken.text,
                        ScriptValue(i), qualifierToken.text == "const"? true: false);
                    context.declareVariableOrConst(varAccessNodes[1].varToken.text,
                        arr[i], qualifierToken.text == "const"? true: false);
                }
                vr = bodyNode.visit(context);
                context = context.parent;
                if(vr.breakFlag)
                {
                    vr.breakFlag = false;
                    break;
                }
                if(vr.continueFlag)
                    vr.continueFlag = false;
                if(vr.exception !is null || vr.returnFlag)
                    break; 
                if(vr.exception !is null)
                    break;                 
            }
        }
        else 
        {
            vr.exception = new ScriptRuntimeException("Cannot iterate over " ~ objectToIterateNode.toString);
        }

        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;

        return vr;
    }

    Token qualifierToken;
    VarAccessNode[] varAccessNodes;
    Node objectToIterateNode;
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
        return "break;";
    }

    override VisitResult visit(Context c)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        vr.breakFlag = true;
        return vr;
    }

    // TODO add label field
}

class ContinueStatementNode : StatementNode
{
    this(size_t lineNo)
    {
        super(lineNo);
    }

    override string toString() const
    {
        return "continue;";
    }

    override VisitResult visit(Context c)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        vr.continueFlag = true;
        return vr;
    }

    // TODO add label field
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
        auto str = "return";
        if(expressionNode !is null)
            str ~= " " ~ expressionNode.toString;
        return str ~ ";";
    }

    override VisitResult visit(Context c)
    {
        VisitResult vr = VisitResult(ScriptValue.UNDEFINED);
        if(expressionNode !is null)
        {
            vr = expressionNode.visit(c);
            if(vr.exception !is null)
            {
                vr.exception.scriptTraceback ~= this;
                return vr;
            }
        }
        vr.returnFlag = true;
        return vr;
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

    override VisitResult visit(Context c)
    {
        auto func = new ScriptFunction(name, argNames, statementNodes);
        immutable okToDeclare = c.declareVariableOrConst(name, ScriptValue(func), false);
        VisitResult vr = VisitResult(ScriptValue.UNDEFINED);
        if(!okToDeclare)
        {
            vr.exception = new ScriptRuntimeException("Cannot redeclare variable or const " ~ name 
                ~ " with a function declaration");
            vr.exception.scriptTraceback ~= this;
        }
        return vr;
    }

    string name;
    string[] argNames;
    StatementNode[] statementNodes;
}

class ThrowStatementNode : StatementNode
{
    this(size_t lineNo, Node expr)
    {
        super(lineNo);
        expressionNode = expr;
    }

    override string toString() const
    {
        return "throw " ~ expressionNode.toString() ~ ";";
    }

    override VisitResult visit(Context c)
    {
        auto vr = expressionNode.visit(c);
        if(vr.exception !is null)
        {
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
        vr.exception = new ScriptRuntimeException("Uncaught script exception");
        vr.exception.thrownValue = vr.result;
        vr.result = ScriptValue.UNDEFINED;
        return vr;
    }

    Node expressionNode;
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

    override string toString() const
    {
        return "try " ~ tryBlockNode.toString ~ " catch(" ~ exceptionName ~ ")"
            ~ catchBlockNode.toString;
    }

    override VisitResult visit(Context context)
    {
        auto vr = tryBlockNode.visit(context);
        // if there was an exception we need to start a new context and set it as a local variable
        if(vr.exception !is null)
        {
            context = new Context(context);
            if(vr.exception.thrownValue != ScriptValue.UNDEFINED)
                context.forceSetVarOrConst(exceptionName, vr.exception.thrownValue, false);
            else 
                context.forceSetVarOrConst(exceptionName, ScriptValue(vr.exception.message), false);
            vr.exception = null;
            // if another exception is thrown in the catch block, it will propagate through this return value
            vr = catchBlockNode.visit(context);
            if(vr.exception !is null)
                vr.exception.scriptTraceback ~= this;
            context = context.parent;
        }
        return vr;
    }

    StatementNode tryBlockNode;
    string exceptionName;
    StatementNode catchBlockNode;
}

class DeleteStatementNode : StatementNode
{
    this(size_t lineNo, Node accessNode)
    {
        super(lineNo);
        memberAccessOrArrayIndexNode = accessNode;
    }

    override string toString() const
    {
        return "delete " ~ memberAccessOrArrayIndexNode.toString ~ ";";
    }

    override VisitResult visit(Context c)
    {
        auto vr = memberAccessOrArrayIndexNode.visit(c);
        if(vr.accessType != VisitResult.AccessType.OBJECT_ACCESS)
        {
            vr.exception = new ScriptRuntimeException("Invalid operand for delete operator");
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
        if(vr.objectToAccess.isObject)
        {
            auto obj = vr.objectToAccess.toValue!ScriptObject;
            obj.members.remove(vr.memberOrVarToAccess);
        }
        vr.result = ScriptValue.UNDEFINED;
        return vr;
    }

    Node memberAccessOrArrayIndexNode;
}

class ExpressionStatementNode : StatementNode
{
    this(size_t lineNo, Node expression)
    {
        super(lineNo);
        expressionNode = expression;
    }

    override string toString() const
    {
        if(expressionNode is null)
            return ";";
        return expressionNode.toString() ~ ";";
    }

    override VisitResult visit(Context c)
    {
        VisitResult vr;
        if(expressionNode !is null)
            vr = expressionNode.visit(c);
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        vr.result = ScriptValue.UNDEFINED; // they should never return a result
        return vr; // caller will handle any exception
    }

    Node expressionNode;
}

VisitResult handleVarReassignment(Context c, Token opToken, string varToAccess, ScriptValue value)
{
    bool isConst; // @suppress(dscanner.suspicious.unmodified)
    auto ptr = c.lookupVariableOrConst(varToAccess, isConst);
    VisitResult vr;
    if(isConst)
        vr.exception = new ScriptRuntimeException("Unable to modify const " ~ varToAccess);
    else if(ptr == null)
        vr.exception = new ScriptRuntimeException("Unable to modify undefined variable " ~ varToAccess);

    if(vr.exception)
        return vr;

    switch(opToken.type)
    {
        case Token.Type.ASSIGN:
            *ptr = value;
            break;
        case Token.Type.PLUS_ASSIGN:
            *ptr = *ptr + value;
            break;
        case Token.Type.DASH_ASSIGN:
            *ptr = *ptr - value;
            break;
        default:
            throw new Exception("Something has gone terribly wrong");
    }
    vr.result = *ptr;
    return vr;
}

VisitResult handleArrayReassignment(Context c, Token opToken, ScriptValue arr, 
                                    size_t index, ScriptValue value)
{
    VisitResult vr;
    if(arr.type != ScriptValue.Type.ARRAY)
    {
        vr.exception = new ScriptRuntimeException("Cannot index non-array");
        return vr;
    }
    if(index >= arr.length)
    {
        vr.exception = new ScriptRuntimeException("Out of bounds array assignment");
        return vr;
    }

    switch(opToken.type)
    {
        case Token.Type.ASSIGN:
            arr[index] = value;
            break;
        case Token.Type.PLUS_ASSIGN:
            arr[index] = arr[index] + value;
            break;
        case Token.Type.DASH_ASSIGN:
            arr[index] = arr[index] - value;
            break;
        default:
            throw new Exception("Something has gone terribly wrong");
    }
    vr.result = arr[index];
    return vr;
}

VisitResult handleObjectReassignment(Context c, Token opToken, ScriptValue objectToAccess, string index, 
                                    ScriptValue value)
{
    VisitResult vr;
    if(!objectToAccess.isObject)
    {
        vr.exception = new ScriptRuntimeException("Cannot index non-object");
        return vr;
    }

    switch(opToken.type)
    {
        case Token.Type.ASSIGN:
            objectToAccess[index] = value;
            break;
        case Token.Type.PLUS_ASSIGN:
            objectToAccess[index] = objectToAccess[index] + value;
            break;
        case Token.Type.DASH_ASSIGN:
            objectToAccess[index] = objectToAccess[index] - value;
            break;
        default:
            throw new Exception("Something has gone terribly wrong");
    }
    vr.result = objectToAccess[index];
    return vr;
}

VisitResult convertExpressionsToArgs(Context c, Node[] expressions, out ScriptValue[] args)
{
    args = [];
    VisitResult vr;
    foreach(expression ; expressions)
    {
        vr = expression.visit(c);
        if(vr.exception !is null)
        {
            args = [];
            return vr;
        }
        args ~= vr.result;
    }
    return vr;
}

VisitResult callFunction(Context context, ScriptFunction fn, ScriptValue thisObj, 
                         ScriptValue[] args, bool returnThis = false)
{
    import mildew.types : NativeFunctionError;

    VisitResult vr;
    if(returnThis)
        thisObj = new ScriptObject(fn.functionName, fn["prototype"].toValue!ScriptObject, null);
    if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
    {
        context = new Context(context, fn.functionName);
        // push args by name as locals
        for(size_t i=0; i < fn.argNames.length; ++i)
            context.forceSetVarOrConst(fn.argNames[i], args[i], false);
        context.forceSetVarOrConst("this", thisObj, true);
        foreach(statement ; fn.statementNodes)
        {
            vr = statement.visit(context);
            if(vr.breakFlag) // can't break out of a function
                vr.breakFlag = false;
            if(vr.continueFlag) // likewise
                vr.continueFlag = false;
            if(vr.returnFlag || vr.exception !is null)
            {
                vr.returnFlag = false;
                break;
            }
        }
        if(returnThis)
        {
            bool _; // @suppress(dscanner.suspicious.unmodified)
            vr.result = *(context.lookupVariableOrConst("this", _));
        }
        context = context.parent;
        return vr;                           
    }
    else 
    {
        ScriptValue returnValue;
        NativeFunctionError nfe = NativeFunctionError.NO_ERROR;
        if(fn.type == ScriptFunction.Type.NATIVE_FUNCTION)
        {
            auto nativefn = fn.nativeFunction;
            returnValue = nativefn(context, &thisObj, args, nfe);
        }
        else // delegate
        {
            auto nativedg = fn.nativeDelegate;
            returnValue = nativedg(context, &thisObj, args, nfe);
        }
        if(returnThis)
            vr.result = thisObj;
        else 
            vr.result = returnValue;
        // check for the appropriate nfe flag
        final switch(nfe)
        {
            case NativeFunctionError.NO_ERROR:
                break; // all good
            case NativeFunctionError.WRONG_NUMBER_OF_ARGS:
                vr.exception = new ScriptRuntimeException("Incorrect number of args to native method");
                break;
            case NativeFunctionError.WRONG_TYPE_OF_ARG:
                vr.exception = new ScriptRuntimeException("Wrong argument type to native method");
                break;
            case NativeFunctionError.RETURN_VALUE_IS_EXCEPTION:
                vr.exception = new ScriptRuntimeException(vr.result.toString);
                break;
        }
        // finally return the result
        return vr;               
    }
}

/// holds information from visiting nodes
struct VisitResult
{
    enum AccessType { NO_ACCESS=0, VAR_ACCESS, ARRAY_ACCESS, OBJECT_ACCESS }

    this(T)(T val)
    {
        result = ScriptValue(val);
    }

    this(T : ScriptValue)(T val)
    {
        result = val;
    }

    ScriptValue result;

    AccessType accessType;
    ScriptValue objectToAccess;
    string memberOrVarToAccess;
    size_t indexToAccess;

    bool returnFlag, breakFlag, continueFlag;
    string labelName;
    ScriptRuntimeException exception;
}