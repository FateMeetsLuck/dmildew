module mildew.interpreter;

import mildew.context;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token, Lexer;
import mildew.nodes;
import mildew.parser;
import mildew.types: ScriptValue, NativeFunction, NativeDelegate, NativeFunctionError, ScriptFunction;

/// public interface for language
class Interpreter
{
public:

    /// constructor
    this()
    {
        _globalContext = new Context(null, "global");
        _currentContext = _globalContext;
    }

    /// evaluates a list of statements in the code. void for now
    ScriptValue evaluateStatements(in string code)
    {
        debug import std.stdio: writeln;

        auto lexer = Lexer(code);
        auto tokens = lexer.tokenize();
        auto parser = Parser(tokens);
        writeln(tokens);
        auto programBlock = parser.parseProgram();
        auto vr = visitBlockStatementNode(programBlock); // @suppress(dscanner.suspicious.unmodified)
        if(vr.exception !is null)
            throw vr.exception;
        if(vr.returnFlag)
            return vr.value;
        return ScriptValue.UNDEFINED;
    }

    /// force sets a global variable or constant to some value
    void forceSetGlobal(T)(in string name, T value, bool isConst=false)
    {
        _globalContext.forceSetVarOrConst(name, ScriptValue(value), isConst);
    }

private:

    VisitResult visitNode(Node node)
    {
        auto result = VisitResult(ScriptValue.UNDEFINED);

        if(node is null)
            return result;

        if(auto lnode = cast(LiteralNode)node)
            result = visitLiteralNode(lnode);
        else if(auto anode = cast(ArrayLiteralNode)node)
            result = visitArrayLiteralNode(anode);
        else if(auto unode = cast(UnaryOpNode)node)
            result = visitUnaryOpNode(unode);
        else if(auto bnode = cast(BinaryOpNode)node)
            result = visitBinaryOpNode(bnode);
        else if(auto vnode = cast(VarAccessNode)node)
            result = visitVarAccessNode(vnode);
        else if(auto fnnode = cast(FunctionCallNode)node)
            result = visitFunctionCallNode(fnnode);
        else if(auto anode = cast(ArrayIndexNode)node)
            result = visitArrayIndexNode(anode);
        else
            throw new Exception("Unknown node type " ~ typeid(node).toString);

        return result;
    }

    // this can never generate a var pointer so no parameter
    VisitResult visitLiteralNode(LiteralNode node)
    {
        return VisitResult(node.value);
    }

    VisitResult visitArrayLiteralNode(ArrayLiteralNode node)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        ScriptValue[] values = [];
        foreach(expression ; node.valueNodes)
        {
            vr = visitNode(expression);
            if(vr.exception !is null)
                return vr;
            values ~= vr.value;
        }
        vr.value = values;
        return vr;
    }

    VisitResult visitUnaryOpNode(UnaryOpNode node)
    {
        // TODO handle ++, -- if operandNode is a VarAccessNode
        auto value = visitNode(node.operandNode).value;
        switch(node.opToken.type)
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
                // all other unary ops are undefined
                return VisitResult(ScriptValue.UNDEFINED);
        }
    }

    VisitResult visitBinaryOpNode(BinaryOpNode node)
    {
        import std.conv: to;
        // TODO handle in and instance of operators
        // for now just do math
        auto lhsResult = visitNode(node.leftNode);
        auto rhsResult = visitNode(node.rightNode);

        if(lhsResult.exception !is null)
            return lhsResult;
        if(rhsResult.exception !is null)
            return rhsResult;

        if(node.opToken.isAssignmentOperator)
            return handleAssignment(node.opToken, node.leftNode, node.rightNode);

        auto lhs = lhsResult.value;
        auto rhs = rhsResult.value;

        switch(node.opToken.type)
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
                throw new Exception("Forgot to implement missing binary operator " ~ node.opToken.type.to!string);
                // return VisitResult(ScriptValue.UNDEFINED);
        }
    }

    /// this function should only be used on VarAccessNodes when evaluating an expression.
    ///   in other situations its token value is only checked
    VisitResult visitVarAccessNode(VarAccessNode node)
    {
        debug import std.stdio: writeln;

        bool isConst; // @suppress(dscanner.suspicious.unmodified)
        auto valuePtr = _currentContext.lookupVariableOrConst(node.varToken.text, isConst);
        if(valuePtr != null)
        {
            auto visitResult = VisitResult(*valuePtr);
            visitResult.varPointer = valuePtr;
            return visitResult;
        }
        else
        {
            // throw new Exception("Attempt to access undefined variable " ~ node.varToken.text);
            auto visitResult = VisitResult(ScriptValue.UNDEFINED);
            visitResult.exception = new ScriptRuntimeException("Attempt to access undefined variable " 
                ~ node.varToken.text);
            writeln("Unable to access var " ~ node.varToken.text);
            return visitResult;
        }
    }

    VisitResult handleAssignment(Token assignToken, Node left, Node right)
    {
        // first get the value of what we're going to assign
        auto vResult = visitNode(right);
        if(vResult.exception !is null)
            return vResult;
        auto value = vResult.value;
        // if it is a VarAccessNode we need the name and to follow all reassignment rules
        ScriptValue* varRef;
        if(auto van = cast(VarAccessNode)left)
        {
            auto name = van.varToken.text;
            bool isConst; // @suppress(dscanner.suspicious.unmodified)
            varRef = _currentContext.lookupVariableOrConst(name, isConst);
            if(varRef == null)
            {
                vResult.exception = new ScriptRuntimeException("Cannot reassign undefined variable " ~ name);
                return vResult;
            }
            if(isConst) // we can't reassign this
            {
                vResult.exception = new ScriptRuntimeException("Cannot reassign const " ~ name);
                return vResult;
            }
            // else we have a valid pointer at this point
        }
        // if it is an array index node, it has to return a valid pointer
        else if(auto ain = cast(ArrayIndexNode)left) 
        {
            vResult = visitNode(left);
            if(vResult.varPointer == null)
            {
                vResult.exception = new ScriptRuntimeException("Cannot assign values to this array index");
                return vResult;
            }
            varRef = vResult.varPointer;
            // else we have a valid pointer
        }
        // TODO handle MemberAccessNode
        else // we can't assign to this left hand node
        {
            vResult.exception = new ScriptRuntimeException("Invalid reassignment");
            return vResult;
        }

        // what assignment operation is it?
        switch(assignToken.type)
        {
            case Token.Type.PLUS_ASSIGN:
                *varRef = *varRef + value;
                break;
            case Token.Type.DASH_ASSIGN:
                *varRef = *varRef - value;
                break;
            case Token.Type.ASSIGN:
                *varRef = value;
                break;
            default:
                throw new Exception("We should have never gotten here (assignment)");
        }
        vResult.value = *varRef;
        return vResult;
    }

    VisitResult visitFunctionCallNode(FunctionCallNode node)
    {
        auto fnVR = visitNode(node.functionToCall);
        if(fnVR.exception !is null)
            return fnVR;
        auto fnToCall = fnVR.value;
        if(fnToCall.type == ScriptValue.Type.NATIVE_FUNCTION || fnToCall.type == ScriptValue.Type.NATIVE_DELEGATE)
        {
            // valid function to call so gather expressions;
            auto exprVR = VisitResult(ScriptValue.UNDEFINED);
            ScriptValue[] args = [];
            NativeFunctionError nfe = NativeFunctionError.NO_ERROR;
            ScriptValue retVal = ScriptValue.UNDEFINED;
            foreach(argExpr ; node.expressionArgs)
            {
                exprVR = visitNode(argExpr);
                if(exprVR.exception !is null)
                    return exprVR;
                args ~= exprVR.value;
            }

            if(fnToCall.type == ScriptValue.Type.NATIVE_FUNCTION)
            {
                auto fn = fnToCall.toValue!NativeFunction();
                retVal = fn(_currentContext, args, nfe);
            }
            else // delegate
            {
                auto dg = fnToCall.toValue!NativeDelegate();
                retVal = dg(_currentContext, args, nfe);
            }
            VisitResult finalVR = VisitResult(retVal);
            // check for the appropriate nfe flag
            final switch(nfe)
            {
                case NativeFunctionError.NO_ERROR:
                    break; // all good
                case NativeFunctionError.WRONG_NUMBER_OF_ARGS:
                    finalVR.exception = new ScriptRuntimeException("Incorrect number of args to native method");
                    break;
                case NativeFunctionError.WRONG_TYPE_OF_ARG:
                    finalVR.exception = new ScriptRuntimeException("Wrong argument type to native method");
            }
            // finally return the result
            return finalVR;
        }
        else if(fnToCall.type == ScriptValue.Type.FUNCTION)
        {
            auto sfn = fnToCall.toValue!(ScriptFunction*);
            // valid function to call so gather expressions;
            auto vr = VisitResult(ScriptValue.UNDEFINED);
            // make sure arguments match TODO support vararg
            if(node.expressionArgs.length > sfn.argNames.length)
            {
                vr.exception = new ScriptRuntimeException("Wrong number of arguments to function " 
                    ~ sfn.name);
                return vr;
            }
            ScriptValue[] args = [];
            foreach(argExpr ; node.expressionArgs)
            {
                vr = visitNode(argExpr);
                if(vr.exception !is null)
                    return vr;
                args ~= vr.value;
            }
            _currentContext = new Context(_currentContext);
            // push args by name as locals
            for(size_t i=0; i < sfn.argNames.length; ++i)
                _currentContext.forceSetVarOrConst(sfn.argNames[i], args[i], false);
            
            foreach(statement ; sfn.statements)
            {
                vr = visitStatementNode(statement);
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
            _currentContext = _currentContext.parent;
            return vr;
        }
        else 
        {
            auto finalVR = VisitResult(ScriptValue.UNDEFINED);
            finalVR.exception = new ScriptRuntimeException("Unable to call non function " ~ fnToCall.toString);
            return finalVR;
        }
    }

    VisitResult visitArrayIndexNode(ArrayIndexNode node)
    {
        auto vr = visitNode(node.indexValueNode);
        if(vr.exception !is null)
            return vr;
        immutable indexSV = vr.value;
        vr = visitNode(node.objectNode);
        if(vr.exception !is null)
            return vr;
        auto arrayToIndex = vr.value;
        if(arrayToIndex.type == ScriptValue.Type.ARRAY)
        {
            if(!indexSV.isNumber)
            {
                vr.exception = new ScriptRuntimeException("Array index must be a number");
                return vr;
            }
            immutable index = indexSV.toValue!long;
            auto rawArray = arrayToIndex.toValue!(ScriptValue[]);
            if(index < 0 || index >= rawArray.length)
            {
                vr.exception = new ScriptRuntimeException("Out of bounds array access");
                return vr;
            }
            vr.value = rawArray[index];
            vr.varPointer = &rawArray[index];
            return vr;            
        }
        else 
        {
            vr = VisitResult(ScriptValue.UNDEFINED);
            vr.exception = new ScriptRuntimeException("Cannot index non array " ~ arrayToIndex.toString);
            return vr;            
        }
    }

    VisitResult visitStatementNode(StatementNode node)
    {
        VisitResult vr = VisitResult(ScriptValue.UNDEFINED);
        if(auto statement = cast(VarDeclarationStatementNode)node)
            vr = visitVarDeclarationStatementNode(statement);
        else if(auto statement = cast(ExpressionStatementNode)node)
            vr = visitExpressionStatementNode(statement);
        else if(auto block = cast(BlockStatementNode)node)
            vr = visitBlockStatementNode(block);
        else if(auto ifstatement = cast(IfStatementNode)node)
            vr = visitIfStatementNode(ifstatement);
        else if(auto wnode = cast(WhileStatementNode)node)
            vr = visitWhileStatementNode(wnode);
        else if(auto dwnode = cast(DoWhileStatementNode)node)
            vr = visitDoWhileStatementNode(dwnode);
        else if(auto fnode = cast(ForStatementNode)node)
            vr = visitForStatementNode(fnode);
        else if(auto bnode = cast(BreakStatementNode)node)
            vr = visitBreakStatementNode(bnode);
        else if(auto cnode = cast(ContinueStatementNode)node)
            vr = visitContinueStatementNode(cnode);
        else if(auto rnode = cast(ReturnStatementNode)node)
            vr = visitReturnStatementNode(rnode);
        else if(auto fnode = cast(FunctionDeclarationStatementNode)node)
            vr = visitFunctionDeclarationStatementNode(fnode);
        else 
            throw new Exception("Unknown StatementNode type " ~ typeid(node).toString);

        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= node;
        return vr;
    }

    VisitResult visitVarDeclarationStatementNode(VarDeclarationStatementNode node)
    {
        auto visitResult = VisitResult(ScriptValue.UNDEFINED);
        foreach(varNode; node.varAccessOrAssignmentNodes)
        {
            if(auto v = cast(VarAccessNode)varNode)
            {
                if(node.qualifier.text == "var")
                {
                    if(!_globalContext.declareVariableOrConst(v.varToken.text, ScriptValue.UNDEFINED, false))
                    {
                        // throw new Exception("Attempt to redeclare global " ~ v.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare global "
                            ~ v.varToken.text);
                        // visitResult.exception.scriptTraceback ~= node;
                        return visitResult;
                    }
                }
                else if(node.qualifier.text == "let")
                {
                    if(!_currentContext.declareVariableOrConst(v.varToken.text, ScriptValue.UNDEFINED, false))
                    {
                        // throw new Exception("Attempt to redeclare local " ~ v.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare local "
                            ~ v.varToken.text);
                        // visitResult.exception.scriptTraceback ~= node;
                        return visitResult;
                    }
                }
                else if(node.qualifier.text == "const")
                {
                    if(!_currentContext.declareVariableOrConst(v.varToken.text, ScriptValue.UNDEFINED, true))
                    {
                        // throw new Exception("Attempt to redeclare const " ~ v.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare const "
                            ~ v.varToken.text);
                        // visitResult.exception.scriptTraceback ~= node;
                        return visitResult;
                    }
                }
                else 
                    throw new Exception("Something has gone very wrong in " ~ __FUNCTION__);
            }
            else
            {
                auto binNode = cast(BinaryOpNode)varNode;
                visitResult = visitNode(binNode.rightNode);
                if(visitResult.exception !is null)
                    return visitResult;
                auto valueToAssign = visitResult.value;
                // we checked this before so should be safe
                auto van = cast(VarAccessNode)(binNode.leftNode);
                auto name = van.varToken.text;
                if(node.qualifier.text == "var")
                {
                    // global variable
                    if(!_globalContext.declareVariableOrConst(name, valueToAssign, false))
                    {
                        // throw new Exception("Attempt to redeclare global variable " ~ v.leftNode.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare global variable "
                            ~ name);
                        // visitResult.exception.scriptTraceback ~= node;
                        return visitResult;
                    }
                }
                else if(node.qualifier.text == "let")
                {
                    // local variable
                    if(!_currentContext.declareVariableOrConst(name, valueToAssign, false))
                    {
                        // throw new Exception("Attempt to redeclare local variable " ~ v.leftNode.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare local variable "
                            ~ name);
                        // visitResult.exception.scriptTraceback ~= node;
                        return visitResult;
                    }
                }
                else if(node.qualifier.text == "const")
                {
                    if(!_currentContext.declareVariableOrConst(name, valueToAssign, true))
                    {
                        // throw new Exception("Attempt to redeclare local const " ~ v.leftNode.varToken.text);
                        visitResult.exception = new ScriptRuntimeException("Attempt to redeclare local const "
                            ~ name);
                        // visitResult.exception.scriptTraceback ~= node;
                        return visitResult;
                    }           
                }
            }
        }
        return VisitResult(ScriptValue.UNDEFINED);
    }

    VisitResult visitBlockStatementNode(BlockStatementNode node)
    {
        _currentContext = new Context(_currentContext, "<scope>");
        auto result = VisitResult(ScriptValue.UNDEFINED);
        foreach(statement ; node.statementNodes)
        {
            result = visitStatementNode(statement);
            if(result.returnFlag || result.breakFlag || result.continueFlag || result.exception !is null)
                break;
            // TODO handle exception
        }   
        _currentContext = _currentContext.parent;
        return result;
    }

    VisitResult visitIfStatementNode(IfStatementNode node)
    {
        auto vr = visitNode(node.conditionNode);
        if(vr.exception !is null)
            return vr;
        if(vr.value)
        {
            vr = visitStatementNode(node.onTrueStatement);
        }
        else 
        {
            if(node.onFalseStatement !is null)
                vr = visitStatementNode(node.onFalseStatement);
        }
        return vr;
    }

    VisitResult visitWhileStatementNode(WhileStatementNode node)
    {
        auto vr = visitNode(node.conditionNode);
        while(vr.value && vr.exception is null)
        {
            vr = visitStatementNode(node.bodyNode);
            if(vr.breakFlag)
            {
                vr.breakFlag = false;
                break;
            }
            if(vr.continueFlag)
                vr.continueFlag = false;
            if(vr.exception !is null || vr.returnFlag)
                break;
            vr = visitNode(node.conditionNode);
        }
        return vr;
    }

    VisitResult visitDoWhileStatementNode(DoWhileStatementNode node)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        do 
        {
            vr = visitStatementNode(node.bodyNode);
            if(vr.breakFlag)
            {
                vr.breakFlag = false;
                break;
            }
            if(vr.continueFlag)
                vr.continueFlag = false;
            if(vr.exception !is null || vr.returnFlag)
                break; 
            vr = visitNode(node.conditionNode);
        }
        while(vr.value && vr.exception is null);
        return vr;
    }

    VisitResult visitForStatementNode(ForStatementNode node)
    {
        _currentContext = new Context(_currentContext);
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        if(node.varDeclarationStatement !is null)
            vr = visitStatementNode(node.varDeclarationStatement);
        if(vr.exception is null)
        {
            vr = visitNode(node.conditionNode);
            while(vr.value && vr.exception is null)
            {
                vr = visitStatementNode(node.bodyNode);
                if(vr.breakFlag)
                {
                    vr.breakFlag = false;
                    break;
                }
                if(vr.continueFlag)
                    vr.continueFlag = false;
                if(vr.exception !is null || vr.returnFlag)
                    break; 
                vr = visitNode(node.incrementNode);
                if(vr.exception !is null)
                    break;
                vr = visitNode(node.conditionNode);
            }
        }
        _currentContext = _currentContext.parent;
        return vr;
    }

    VisitResult visitBreakStatementNode(BreakStatementNode node)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        vr.breakFlag = true;
        return vr;
    }

    VisitResult visitContinueStatementNode(ContinueStatementNode node)
    {
        auto vr = VisitResult(ScriptValue.UNDEFINED);
        vr.continueFlag = true;
        return vr;
    }

    VisitResult visitReturnStatementNode(ReturnStatementNode node)
    {
        VisitResult vr = VisitResult(ScriptValue.UNDEFINED);
        if(node.expressionNode !is null)
        {
            vr = visitNode(node.expressionNode);
            if(vr.exception !is null)
                return vr;
        }
        vr.returnFlag = true;
        return vr;
    }

    VisitResult visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode node)
    {
        ScriptFunction* func = new ScriptFunction(node.name, node.argNames, node.statementNodes);
        immutable okToDeclare = _globalContext.declareVariableOrConst(node.name, ScriptValue(func), false);
        VisitResult vr = VisitResult(ScriptValue.UNDEFINED);
        if(!okToDeclare)
        {
            vr.exception = new ScriptRuntimeException("Cannot redeclare variable or const " ~ node.name 
                ~ " with a function declaration");
        }
        return vr;
    }

    VisitResult visitExpressionStatementNode(ExpressionStatementNode node)
    {
        debug import std.stdio: writefln;
        auto vr = visitNode(node.expressionNode);
        writefln("The result of the expression statement is %s", vr.value);
        vr.value = ScriptValue.UNDEFINED; // they should never return a result
        return vr;
    }

    Context _globalContext;
    Context _currentContext;
}

/// holds information from visiting nodes
private struct VisitResult
{
    this(T)(T val)
    {
        value = ScriptValue(val);
    }

    this(T : ScriptValue)(T val)
    {
        value = val;
    }

    string toString() const
    {
        import std.conv: to;
        return "VisitResult: value=" ~ value.toString ~ " varPointer=" ~ to!string(varPointer) 
            ~ " returnFlag=" ~ returnFlag.to!string ~ " breakFlag=" ~ breakFlag.to!string
            ~ " continueFlag=" ~ continueFlag.to!string; // add more as needed
    }

    ScriptValue value;
    ScriptValue* varPointer = null;
    bool returnFlag = false;
    bool breakFlag = false;
    bool continueFlag = false;

    ScriptRuntimeException exception = null;
}