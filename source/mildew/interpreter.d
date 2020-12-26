module mildew.interpreter;

import mildew.context;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token, Lexer;
import mildew.nodes;
import mildew.parser;
import mildew.types: ScriptValue, NativeFunction, NativeDelegate, 
                     NativeFunctionError, ScriptFunction, ScriptObject;

/// public interface for language
class Interpreter
{
public:

    /// constructor
    this()
    {
        _globalContext = new Context(null, "global");
        _currentContext = _globalContext;
        _nativeFunctionDotCall = new ScriptFunction("Function.call", &native_Function_call);
    }

    /// initializes the Mildew standard library
    void initializeStdlib()
    {
        import mildew.stdlib.object: initializeObjectLibrary;
        import mildew.stdlib.console: initializeConsoleLibrary;
        import mildew.stdlib.math: initializeMathLibrary;
        initializeObjectLibrary(this);
        initializeConsoleLibrary(this);
        initializeMathLibrary(this);
    }

    /// evaluates a list of statements in the code. void for now
    ScriptValue evaluateStatements(in string code)
    {
        debug import std.stdio: writeln;

        auto lexer = Lexer(code);
        auto tokens = lexer.tokenize();
        auto parser = Parser(tokens);
        debug writeln(tokens);
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
        else if(auto onode = cast(ObjectLiteralNode)node)
            result = visitObjectLiteralNode(onode);
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
        else if(auto mnode = cast(MemberAccessNode)node)
            result = visitMemberAccessNode(mnode);
        else if(auto nnode = cast(NewExpressionNode)node)
            result = visitNewExpressionNode(nnode);
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

    VisitResult visitObjectLiteralNode(ObjectLiteralNode node)
    {
        if(node.keys.length != node.values.length)
            throw new Exception("Error with object literal node");
        ScriptValue[] values = [];
        VisitResult vr;
        foreach(valueNode ; node.values)
        {
            vr = visitNode(valueNode);
            if(vr.exception !is null)
                return vr;
            values ~= vr.value;
        }
        auto obj = new ScriptObject("", null, null);
        for(size_t i = 0; i < node.keys.length; ++i)
        {
            obj[node.keys[i]] = values[i];
        }
        vr.value = obj;
        return vr;
    }

    VisitResult visitUnaryOpNode(UnaryOpNode node)
    {
        // TODO handle ++, -- if operandNode is a VarAccessNode
        auto vr = visitNode(node.operandNode);
        if(vr.exception !is null)
            return vr;
        auto value = vr.value;
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
                if(node.opToken.isKeyword("typeof"))
                    return VisitResult(value.typeToString());
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
            debug writeln("Unable to access var " ~ node.varToken.text);
            return visitResult;
        }
    }

    VisitResult handleAssignment(Token assignToken, Node left, Node right)
    {
        debug import std.stdio: writefln;
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
            // we also want to set anonymous function names if they are stored in a regular variable
        }
        // if it is an array index node, it has to return a valid pointer
        else if(auto ain = cast(ArrayIndexNode)left) 
        {
            debug writefln("AIN: left=%s, right=%s", left, right);
            vResult = visitNode(left);
            if(vResult.varPointer == null)
            {
                // vResult.exception = new ScriptRuntimeException("Cannot assign values to this array index");
                // return vResult;
                return handleArrayIndexAssign(assignToken, ain, value);
            }
            debug writefln(" PTR=%x", vResult.varPointer);
            varRef = vResult.varPointer;
            // else we have a valid pointer
        }
        else if(auto man = cast(MemberAccessNode)left)
        {
            return handleDotAssignment(assignToken, man, value);
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
        if(varRef.type == ScriptValue.Type.FUNCTION)
        {
            auto func = varRef.toValue!ScriptFunction;
            if(func.functionName == "<anonymous function>")
                func.functionName = left.toString;            
        }
        return vResult;
    }

    VisitResult handleArrayIndexAssign(Token opToken, ArrayIndexNode ain, ScriptValue value)
    {
        VisitResult vr;
        vr = visitNode(ain.objectNode);
        if(vr.exception !is null)
            return vr;
        if(vr.value.isObject)
        {
            auto obj = vr.value.toValue!(ScriptObject);
            vr = visitNode(ain.indexValueNode);
            if(vr.exception !is null)
                return vr;
            auto index = vr.value.toString;
            switch(opToken.type)
            {
                case Token.Type.PLUS_ASSIGN:
                    obj[index] = obj[index] + value;
                    break;
                case Token.Type.DASH_ASSIGN:
                    obj[index] = obj[index] - value;
                    break;
                case Token.Type.ASSIGN:
                    obj[index] = value;
                    break;
                default:
                    throw new Exception("Something has gone terrible wrong");
            }
            vr.value = value;
        }
        else 
        {
            vr.exception = new ScriptRuntimeException("Cannot assign to index of non-object");
        }
        return vr;
    }

    VisitResult handleDotAssignment(Token op, MemberAccessNode man, ScriptValue value)
    {
        // pull an object/function out of man's left hand side
        VisitResult vr = visitNode(man.objectNode);
        if(vr.exception !is null)
            return vr;
        if(vr.value.type != ScriptValue.Type.FUNCTION && vr.value.type != ScriptValue.Type.OBJECT)
        {
            vr.exception = new ScriptRuntimeException("Invalid left hand side of dot operator");
            return vr;
        }
        // get the index from right hand side
        auto van = cast(VarAccessNode)man.memberNode;
        if(van is null)
        {
            vr.exception = new ScriptRuntimeException("Invalid right hand side of dot operator");
            return vr;
        }
        auto index = van.varToken.text;

        if(vr.value.isObject)
        {
            auto obj = vr.value.toValue!ScriptObject;

            switch(op.type)
            {
                case Token.Type.PLUS_ASSIGN:
                    obj[index] = obj[index] + value;
                    break;
                case Token.Type.DASH_ASSIGN:
                    obj[index] = obj[index] - value;
                    break;
                case Token.Type.ASSIGN:
                    obj[index] = value;
                    break;
                default:
                    throw new Exception("Something has gone terrible wrong");
            }
            vr.value = obj[index];
            if(vr.value.type == ScriptValue.Type.FUNCTION)
            {
                auto func = vr.value.toValue!ScriptFunction;
                if(func.functionName == "<anonymous function>")
                    func.functionName = man.toString();
            }
        }
        return vr;
    }

    VisitResult visitFunctionCallNode(FunctionCallNode node, 
            bool returnThis = false)
    {
        debug import std.stdio: writefln;

        ScriptValue thisObj;
        if(auto man = cast(MemberAccessNode)node.functionToCall)
        {
            thisObj = visitNode(man.objectNode).value;
        }

        auto fnVR = visitNode(node.functionToCall);
        if(fnVR.exception !is null)
            return fnVR;
        auto fnToCall = fnVR.value;
        if(fnToCall.type == ScriptValue.Type.FUNCTION)
        {
            ScriptValue[] args;
            VisitResult vr = convertExpressionsToArgs(node.expressionArgs, args);
            if(vr.exception !is null)
                return vr;
            auto fn = fnToCall.toValue!ScriptFunction;
            vr = callFunction(fn, thisObj, args, returnThis);
            return vr;
        }
        else 
        {
            auto finalVR = VisitResult(ScriptValue.UNDEFINED);
            finalVR.exception = new ScriptRuntimeException("Unable to call non function " ~ fnToCall.toString);
            return finalVR;
        }
    }

    VisitResult convertExpressionsToArgs(Node[] expressions, ref ScriptValue[] values)
    {
        values = [];
        VisitResult vr;
        foreach(expression ; expressions)
        {
            vr = visitNode(expression);
            if(vr.exception !is null)
            {
                values = [];
                return vr;
            }
            values ~= vr.value;
        }
        return vr;
    }

    VisitResult callFunction(ScriptFunction fn, ScriptValue thisObj, ScriptValue[] argVals, 
            bool returnThis = false)
    {
        VisitResult vr;
        if(returnThis)
            thisObj = new ScriptObject(fn.functionName, fn.prototype, null);
        if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
        {
            _currentContext = new Context(_currentContext, fn.functionName);
            // push args by name as locals
            for(size_t i=0; i < fn.argNames.length; ++i)
                _currentContext.forceSetVarOrConst(fn.argNames[i], argVals[i], false);
            _currentContext.forceSetVarOrConst("this", thisObj, true);
            foreach(statement ; fn.statementNodes)
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
            if(returnThis)
            {
                bool _; // @suppress(dscanner.suspicious.unmodified)
                vr.value = *(_currentContext.lookupVariableOrConst("this", _));
            }
            _currentContext = _currentContext.parent;
            return vr;                           
        }
        else 
        {
            ScriptValue returnValue;
            NativeFunctionError nfe = NativeFunctionError.NO_ERROR;
            if(fn.type == ScriptFunction.Type.NATIVE_FUNCTION)
            {
                auto nativefn = fn.nativeFunction;
                returnValue = nativefn(_currentContext, &thisObj, argVals, nfe);
            }
            else // delegate
            {
                auto nativedg = fn.nativeDelegate;
                returnValue = nativedg(_currentContext, &thisObj, argVals, nfe);
            }
            if(returnThis)
                vr.value = thisObj;
            else 
                vr.value = returnValue;
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
                    vr.exception = new ScriptRuntimeException(vr.value.toString);
                    break;
            }
            // finally return the result
            return vr;               
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
        auto objToIndex = vr.value;
        if(objToIndex.type == ScriptValue.Type.ARRAY || objToIndex.type == ScriptValue.Type.STRING)
        {
            if(!indexSV.isNumber)
            {
                vr.exception = new ScriptRuntimeException("Array index must be a number");
                return vr;
            }
            immutable index = indexSV.toValue!long;
            if(objToIndex.type == ScriptValue.Type.ARRAY)
            {
                auto rawArray = objToIndex.toValue!(ScriptValue[]);
                if(index < 0 || index >= rawArray.length)
                {
                    vr.exception = new ScriptRuntimeException("Out of bounds array access");
                    return vr;
                }
                vr.value = rawArray[index];
                vr.varPointer = &rawArray[index];
            }
            else 
            {
                auto rawString = objToIndex.toString();
                if(index < 0 || index >= rawString.length)
                {
                    vr.exception = new ScriptRuntimeException("Out of bounds string access");
                    return vr;
                }
                vr.value = ScriptValue( [ rawString[index] ]);
            }
        }
        else if(objToIndex.isObject)
        {
            immutable memberName = indexSV.toString;
            auto obj = objToIndex.toValue!ScriptObject;
            vr.value = obj[memberName];
            vr.varPointer = null;
        }
        else 
        {
            vr = VisitResult(ScriptValue.UNDEFINED);
            vr.exception = new ScriptRuntimeException("Cannot index non array " ~ objToIndex.toString);
        }
        return vr;
    }

    // this can only be used to retrieve values not for assignment
    VisitResult visitMemberAccessNode(MemberAccessNode node)
    {
        // retrieve ScriptValue that is an object or function from left node
        VisitResult vr = visitNode(node.objectNode);
        if(vr.exception !is null)
            return vr;
        // get the member name from the right node which must be var acess
        auto van = cast(VarAccessNode)node.memberNode;
        if(van is null)
        {
            vr.exception = new ScriptRuntimeException("Invalid member name " ~ node.memberNode.toString);
            return vr;
        }

        if(vr.value.type == ScriptValue.Type.FUNCTION || vr.value.type == ScriptValue.Type.OBJECT)
        {
            auto obj = vr.value.toValue!ScriptObject;
            // special case with Function["call"]
            if(van.varToken.text == "call" && vr.value.type == ScriptValue.Type.FUNCTION)
                vr.value = _nativeFunctionDotCall;
            else
                vr.value = obj[van.varToken.text];
        }
        else if(vr.value.type == ScriptValue.Type.ARRAY)
        {
            immutable arrayValue = cast(immutable(ScriptValue[]))vr.value.toValue!(ScriptValue[]);
            if(van.varToken.text == "length")
                vr.value = arrayValue.length;
            else 
                vr.value = ScriptValue.UNDEFINED;            
        }
        else if(vr.value.type == ScriptValue.Type.STRING)
        {
            immutable stringValue = vr.value.toString;
            if(van.varToken.text == "length")
                vr.value = stringValue.length;
            else 
                vr.value = ScriptValue.UNDEFINED;
        }
        else 
        {
            vr.exception = new ScriptRuntimeException("Unable to access member of non-object");
        }
        return vr;
    }

    VisitResult visitNewExpressionNode(NewExpressionNode node)
    {
        auto fnCall = cast(FunctionCallNode)node.functionCallExpression;
        if(fnCall is null) // shouldn't happen because the parser is supposed to check
            throw new Exception("Invalid new expression " ~ node.functionCallExpression.toString);
        auto vr = visitFunctionCallNode(fnCall, true);
        return vr;
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
        else if(auto fonode = cast(ForOfStatementNode)node)
            vr = visitForOfStatementNode(fonode);
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

    VisitResult visitForOfStatementNode(ForOfStatementNode node)
    {
        auto vr = visitNode(node.objectToIterateNode);
        // make sure this is iterable
        if(vr.exception !is null)
        {
            return vr;
        }
        
        if(vr.value.isObject)
        {
            auto obj = vr.value.toValue!ScriptObject;
            // first value is key, second value is value if there
            foreach(key, val; obj.members)
            {
                _currentContext = new Context(_currentContext);
                _currentContext.declareVariableOrConst(node.varAccessNodes[0].varToken.text,
                    ScriptValue(key), node.qualifierToken.text == "const" ? true: false);
                if(node.varAccessNodes.length > 1)
                    _currentContext.declareVariableOrConst(node.varAccessNodes[1].varToken.text,
                        ScriptValue(val), node.qualifierToken.text == "const" ? true: false);
                vr = visitStatementNode(node.bodyNode);              
                _currentContext = _currentContext.parent;
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
        else if(vr.value.type == ScriptValue.Type.ARRAY)
        {
            auto arr = vr.value.toValue!(ScriptValue[]);
            for(size_t i = 0; i < arr.length; ++i)
            {
                _currentContext = new Context(_currentContext);
                // if one var access node, then value, otherwise index then value
                if(node.varAccessNodes.length == 1)
                {
                    _currentContext.declareVariableOrConst(node.varAccessNodes[0].varToken.text,
                        arr[i], node.qualifierToken.text == "const"? true: false);
                }
                else 
                {
                    _currentContext.declareVariableOrConst(node.varAccessNodes[0].varToken.text,
                        ScriptValue(i), node.qualifierToken.text == "const"? true: false);
                    _currentContext.declareVariableOrConst(node.varAccessNodes[1].varToken.text,
                        arr[i], node.qualifierToken.text == "const"? true: false);
                }
                vr = visitStatementNode(node.bodyNode);
                _currentContext = _currentContext.parent;
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
            vr.exception = new ScriptRuntimeException("Cannot iterate over " ~ node.objectToIterateNode.toString);
        }

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
        auto func = new ScriptFunction(node.name, node.argNames, node.statementNodes);
        immutable okToDeclare = _currentContext.declareVariableOrConst(node.name, ScriptValue(func), false);
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
        debug writefln("The result of the expression statement is %s", vr.value);
        vr.value = ScriptValue.UNDEFINED; // they should never return a result
        return vr;
    }

    ScriptValue native_Function_call(Context c, ScriptValue* thisIsFn, ScriptValue[] args, ref NativeFunctionError nfe)
    {
        // minimum args is 1 because first arg is the this to use
        if(args.length < 1)
        {
            nfe = NativeFunctionError.WRONG_NUMBER_OF_ARGS;
            return ScriptValue.UNDEFINED;
        }
        // get the function
        if(thisIsFn.type != ScriptValue.Type.FUNCTION)
        {
            nfe = NativeFunctionError.WRONG_TYPE_OF_ARG;
            return ScriptValue.UNDEFINED;
        }
        auto fn = thisIsFn.toValue!ScriptFunction;
        // set up the "this" to use
        auto thisToUse = args[0];
        // now send the remainder of the args to a called function with this setup
        args = args[1..$];
        auto vr = callFunction(fn, thisToUse, args, false);
        if(vr.exception !is null)
        {
            nfe = NativeFunctionError.RETURN_VALUE_IS_EXCEPTION;
            return ScriptValue(vr.exception.message);
        }
        return vr.value;
    }

    ScriptValue _nativeFunctionDotCall;
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