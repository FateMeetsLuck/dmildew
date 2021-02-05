/**
 * This module implements the Interpreter class, the main class used by host applications to run scripts
 */
module mildew.interpreter;

import std.variant;

import mildew.context;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token, Lexer;
import mildew.nodes;
import mildew.parser;
import mildew.types;
import mildew.visitors;

/**
 * This is the main interface for the host application to interact with scripts.
 */
class Interpreter : INodeVisitor
{
public:

    /**
     * Constructs a new Interpreter with a global context. Note that all calls to evaluate
     * run in a new context below the global context. This allows keywords such as let and const
     * to not pollute the global namespace. However, scripts can use var to declare variables that
     * are global.
     */
    this()
    {
        _globalContext = new Context(this);
        _currentContext = _globalContext;
    }

    /**
     * Initializes the Mildew standard library, such as Object, Math, and console namespaces. This
     * is optional and is not called by the constructor. For a script to use these methods this
     * must be called first.
     */
    void initializeStdlib()
    {
        import mildew.types.bindings: initializeTypesLibrary;
        import mildew.stdlib.global: initializeGlobalLibrary;
        import mildew.stdlib.console: initializeConsoleLibrary;
        import mildew.stdlib.date: initializeDateLibrary;
        import mildew.stdlib.math: initializeMathLibrary;
        initializeTypesLibrary(this);
        initializeGlobalLibrary(this);
        initializeConsoleLibrary(this);
        initializeDateLibrary(this);
        initializeMathLibrary(this);
    }

    /**
     * Calls a script function. Can throw ScriptRuntimeException.
     */
    ScriptAny callFunction(ScriptFunction func, ScriptAny thisObj, ScriptAny[] args)
    {
        auto vr = callFn(func, thisObj, args, false);
        if(vr.exception)
            throw vr.exception;
        return vr.result;
    }

    /**
     * This is the main entry point for evaluating a script program.
     * Params:
     *  code = This is the code of a script to be executed.
     * Returns:
     *  If the script has a return statement with an expression, this value will be the result of that expression
     *  otherwise it will be ScriptAny.UNDEFINED
     */
    ScriptAny evaluate(in string code)
    {
        debug import std.stdio: writeln;

        auto lexer = Lexer(code);
        auto tokens = lexer.tokenize();
        auto parser = Parser(tokens);
        // debug writeln(tokens);
        auto programBlock = parser.parseProgram();
        auto vr = programBlock.accept(this).get!VisitResult;
        if(vr.exception !is null)
            throw vr.exception;
        if(vr.returnFlag)
            return vr.result;
        return ScriptAny.UNDEFINED;
    }

    // TODO: Read script from file

    // TODO: Create an evaluate function with default exception handling with file name info

    /**
     * Sets a global variable or constant without checking whether or not the variable or const was already
     * declared. This is used by host applications to define custom functions or objects.
     * Params:
     *  name = The name of the variable.
     *  value = The value the variable should be set to.
     *  isConst = Whether or not the script can overwrite the global.
     */
    void forceSetGlobal(T)(in string name, T value, bool isConst=false)
    {
        _globalContext.forceSetVarOrConst(name, ScriptAny(value), isConst);
    }

    /**
     * Unsets a variable or constant in the global context. Used by host applications to remove
     * items that were loaded by the standard library load functions.
     */
    void forceUnsetGlobal(in string name)
    {
        _globalContext.forceRemoveVarOrConst(name);
    }
	
	/// extract a VisitResult from a LiteralNode
	Variant visitLiteralNode(LiteralNode lnode)
	{
		import mildew.exceptions: ScriptCompileException;
		import mildew.parser: Parser;
		import mildew.lexer: Lexer;

		if(lnode.literalToken.literalFlag == Token.LiteralFlag.TEMPLATE_STRING)
		{
			size_t currentStart = 0;
            size_t endLast;
            bool addToParseString = false;
            string result;
            string stringToParse;
            for(size_t index = 0; index < lnode.literalToken.text.length; ++index)
            {
                if(lnode.literalToken.text[index] == '$')
                {
                    if(index < lnode.literalToken.text.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                    {
                        if(lnode.literalToken.text[index+1] == '{')
                        {
                            addToParseString = true;
                            index += 1;
                        }
                        else
                        {
                            if(addToParseString)
                                stringToParse ~= lnode.literalToken.text[index];
                            else
                                endLast = index + 1;
                        }
                    }
                    else 
                    {
                        if(addToParseString)
                            stringToParse ~= lnode.literalToken.text[index];
                        else
                            endLast = index + 1; 
                    }
                }
                else if(lnode.literalToken.text[index] == '}' && addToParseString)
                {
                    result ~= lnode.literalToken.text[currentStart .. endLast];
                    auto lexer = Lexer(stringToParse);
                    auto parser = Parser(lexer.tokenize());
                    ExpressionNode expressionNode;
                    VisitResult vr;
                    try 
                    {
                        expressionNode = parser.parseExpression();
                    }
                    catch(ScriptCompileException ex)
                    {
                        vr.exception = new ScriptRuntimeException(ex.msg);
                        return Variant(vr);
                    }
                    vr = expressionNode.accept(this).get!VisitResult;
                    if(vr.exception !is null)
                        return Variant(vr);
                    result ~= vr.result.toString();
                    addToParseString = false;
                    currentStart = index+1;
                    stringToParse = "";
                }
                else
                {
                    if(addToParseString)
                        stringToParse ~= lnode.literalToken.text[index];
                    else
                        endLast = index + 1;
                }
            }
            if(addToParseString)
            {
                VisitResult vr;
                vr.exception = new ScriptRuntimeException("Unclosed template string expression");
                return Variant(vr);
            }
            if(currentStart < lnode.literalToken.text.length)
                result ~= lnode.literalToken.text[currentStart .. endLast];
            return Variant(VisitResult(result));
		}
		else
		{
			if(lnode.value.type == ScriptAny.Type.FUNCTION)
			{
				auto fn = lnode.value.toValue!ScriptFunction;
				fn.closure = _currentContext;
			}
			return Variant(VisitResult(lnode.value));
		}
	}
	
	/// return an array from an array literal node
	Variant visitArrayLiteralNode(ArrayLiteralNode alnode)
	{
		VisitResult vr;
        ScriptAny[] values = [];
        foreach(expression ; alnode.valueNodes)
        {
            vr = expression.accept(this).get!VisitResult;
            if(vr.exception !is null)
                return Variant(vr);
            values ~= vr.result;
        }
        vr.result = values;
        return Variant(vr);     
	}
	
	/// generates object from object literal node
	Variant visitObjectLiteralNode(ObjectLiteralNode olnode)
	{
		if(olnode.keys.length != olnode.valueNodes.length)
            throw new Exception("Error with object literal node");
        ScriptAny[] vals = [];
        VisitResult vr;
        foreach(valueNode ; olnode.valueNodes)
        {
            vr = valueNode.accept(this).get!VisitResult;
            if(vr.exception !is null)
                return Variant(vr);
            vals ~= vr.result;
        }
        auto obj = new ScriptObject("", null, null);
        for(size_t i = 0; i < olnode.keys.length; ++i)
        {
            obj.assignField(olnode.keys[i], vals[i]);
        }
        vr.result = obj;
        return Variant(vr);
	}
	
    /// handle class literals
	Variant visitClassLiteralNode(ClassLiteralNode clnode)
	{
		VisitResult vr;

		// set constructor closure because parser couldn't set it
		clnode.constructorFn.closure = _currentContext;
        // fill in the function.prototype with the methods and set the closure context because the parser couldn't
        for(size_t i = 0; i < clnode.methodNames.length; ++i) 
		{
            clnode.constructorFn["prototype"][clnode.methodNames[i]] = ScriptAny(clnode.methods[i]);
			clnode.methods[i].closure = _currentContext;
		}
        // fill in any get properties and set closures
        for(size_t i = 0; i < clnode.getterNames.length; ++i)
		{
            clnode.constructorFn["prototype"].addGetterProperty(clnode.getterNames[i], clnode.getters[i]);
			clnode.getters[i].closure = _currentContext;
		}
        // fill in any set properties and set closures
        for(size_t i = 0; i < clnode.setterNames.length; ++i)
		{
            clnode.constructorFn["prototype"].addSetterProperty(clnode.setterNames[i], clnode.setters[i]);
			clnode.setters[i].closure = _currentContext;
		}
		// static methods are assigned directly to the constructor itself
		for(size_t i=0; i < clnode.staticMethodNames.length; ++i)
		{
			clnode.constructorFn[clnode.staticMethodNames[i]] = ScriptAny(clnode.staticMethods[i]);
			clnode.staticMethods[i].closure = _currentContext;
		}

        if(clnode.baseClassNode !is null)
        {
            vr = clnode.baseClassNode.accept(this).get!VisitResult;
            if(vr.exception !is null)
                return Variant(vr);
            if(vr.result.type != ScriptAny.Type.FUNCTION)
            {
                vr.exception = new ScriptRuntimeException("Only classes can be extended");
                return Variant(vr);
            }   
            auto baseClassConstructor = vr.result.toValue!ScriptFunction;
            auto constructorPrototype = clnode.constructorFn["prototype"].toValue!ScriptObject;
            // if the base class constructor's "prototype" is null or non-object, it won't work anyway
            // NOTE that ["prototype"] and .prototype are completely unrelated
            constructorPrototype.prototype = baseClassConstructor["prototype"].toValue!ScriptObject;
            // set the constructor's __proto__ to the base class so that static methods are inherited
            // and the Function.call look up should still work
            clnode.constructorFn.prototype = baseClassConstructor;
        }
        vr.result = clnode.constructorFn;
        return Variant(vr);
	}
	
	/// processes binary operations including assignment
	Variant visitBinaryOpNode(BinaryOpNode bonode)
	{
		import std.conv: to;

        auto lhsResult = bonode.leftNode.accept(this).get!VisitResult;
        auto rhsResult = bonode.rightNode.accept(this).get!VisitResult;

        if(lhsResult.exception !is null)
            return Variant(lhsResult);
        if(rhsResult.exception !is null)
            return Variant(rhsResult);

        VisitResult finalResult;

        if(bonode.opToken.isAssignmentOperator)
        {
            // if an anonymous class or function is being assigned we need to update its name
            if(rhsResult.result.type == ScriptAny.Type.FUNCTION)
            {
                auto func = rhsResult.result.toValue!ScriptFunction;
                if(func.functionName == "<anonymous function>" || func.functionName == "<anonymous class>")
                    func.functionName = bonode.leftNode.toString;
            }
            final switch(lhsResult.accessType)
            {
            case VisitResult.AccessType.NO_ACCESS:
                finalResult.exception = new ScriptRuntimeException("Invalid left hand assignment");
                return Variant(finalResult);
            case VisitResult.AccessType.VAR_ACCESS:
                return Variant(handleVarReassignment(bonode.opToken, lhsResult.memberOrVarToAccess, rhsResult.result));
            case VisitResult.AccessType.ARRAY_ACCESS:
                return Variant(handleArrayReassignment(bonode.opToken, lhsResult.objectToAccess, 
                        lhsResult.indexToAccess, rhsResult.result));
            case VisitResult.AccessType.OBJECT_ACCESS:
                return Variant(handleObjectReassignment(bonode.opToken, lhsResult.objectToAccess, 
				        lhsResult.memberOrVarToAccess, rhsResult.result));
            }
        }

        auto lhs = lhsResult.result;
        auto rhs = rhsResult.result;

        switch(bonode.opToken.type)
        {
        case Token.Type.POW:
            return Variant(VisitResult(lhs ^^ rhs));
        case Token.Type.STAR:
            return Variant(VisitResult(lhs * rhs));
        case Token.Type.FSLASH:
            return Variant(VisitResult(lhs / rhs));
        case Token.Type.PERCENT:
            return Variant(VisitResult(lhs % rhs));
        case Token.Type.PLUS:
            return Variant(VisitResult(lhs + rhs));
        case Token.Type.DASH:
            return Variant(VisitResult(lhs - rhs));
        case Token.Type.BIT_LSHIFT:
            return Variant(VisitResult(lhs << rhs));
        case Token.Type.BIT_RSHIFT:
            return Variant(VisitResult(lhs >> rhs));
        case Token.Type.BIT_URSHIFT:
            return Variant(VisitResult(lhs >>> rhs));
        case Token.Type.GT:
            return Variant(VisitResult(lhs > rhs));
        case Token.Type.GE:
            return Variant(VisitResult(lhs >= rhs));
        case Token.Type.LT:
            return Variant(VisitResult(lhs < rhs));
        case Token.Type.LE:
            return Variant(VisitResult(lhs <= rhs));
        case Token.Type.EQUALS:
            return Variant(VisitResult(lhs == rhs));
        case Token.Type.NEQUALS:
            return Variant(VisitResult(lhs != rhs));
        case Token.Type.STRICT_EQUALS:
            return Variant(VisitResult(lhs.strictEquals(rhs)));
        case Token.Type.STRICT_NEQUALS:
            return Variant(VisitResult(!lhs.strictEquals(rhs)));
        case Token.Type.BIT_AND:
            return Variant(VisitResult(lhs & rhs));
        case Token.Type.BIT_XOR:
            return Variant(VisitResult(lhs ^ rhs));
        case Token.Type.BIT_OR:
            return Variant(VisitResult(lhs | rhs));
        case Token.Type.AND:
            return Variant(VisitResult(lhs && rhs));
        case Token.Type.OR:
            return Variant(VisitResult(lhs.orOp(rhs)));
        default:
            if(bonode.opToken.isKeyword("instanceof"))
            {
                if(!lhs.isObject)
                    return Variant(VisitResult(false));
                if(rhs.type != ScriptAny.Type.FUNCTION)
                    return Variant(VisitResult(false));
                auto lhsObj = lhs.toValue!ScriptObject; // @suppress(dscanner.suspicious.unmodified)
                auto rhsFunc = rhs.toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)
                auto proto = lhsObj.prototype;
                while(proto !is null)
                {
                    if(proto["constructor"].toValue!ScriptFunction is rhsFunc)
                        return Variant(VisitResult(true));
                    proto = proto.prototype;
                }
                return Variant(VisitResult(false));
            }
            else
                throw new Exception("Forgot to implement missing binary operator " 
                    ~ bonode.opToken.type.to!string ~ " for " ~ this.toString());
        }
	}
	
    /// returns a value from a unary operation
	Variant visitUnaryOpNode(UnaryOpNode uonode)
	{
		auto vr = uonode.operandNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);
        auto value = vr.result;
        int incOrDec = 0;
        switch(uonode.opToken.type)
        {
        case Token.Type.BIT_NOT:
            return Variant(VisitResult(~value));
        case Token.Type.NOT:
            return Variant(VisitResult(!value));
        case Token.Type.PLUS:
            return Variant(VisitResult(value));
        case Token.Type.DASH:
            return Variant(VisitResult(-value));
        case Token.Type.DEC:
            incOrDec = -1;
            break;
        case Token.Type.INC:
            incOrDec = 1;
            break;
        default:
            if(uonode.opToken.isKeyword("typeof"))
                return Variant(VisitResult(value.typeToString()));
            return Variant(VisitResult(ScriptAny.UNDEFINED));
        }

        if(incOrDec != 0)
        {
            // TODO: fix this to allow constructs such as ++foo++
            if(vr.accessType == VisitResult.AccessType.VAR_ACCESS)
                return Variant(handleVarReassignment(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                        vr.memberOrVarToAccess, ScriptAny(incOrDec)));
            else if(vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
                return Variant(handleArrayReassignment(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                        vr.objectToAccess, vr.indexToAccess, ScriptAny(incOrDec)));
            else if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS)
                return Variant(handleObjectReassignment(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                        vr.objectToAccess, vr.memberOrVarToAccess, ScriptAny(incOrDec)));
            else
                vr.exception = new ScriptRuntimeException("Invalid operand for " ~ uonode.opToken.symbol);
        }
        return Variant(vr);
	}
	
    /// handle constructs such as i++ and i--
	Variant visitPostfixOpNode(PostfixOpNode ponode)
	{
		// first get the operand's original value that will be returned
        VisitResult vr = ponode.operandNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);
        auto incOrDec = 0;
        if(ponode.opToken.type == Token.Type.INC)
            incOrDec = 1;
        else if(ponode.opToken.type == Token.Type.DEC)
            incOrDec = -1;
        else
            throw new Exception("Impossible parse state: invalid postfix operator");
        // now perform an increment or decrement assignment based on object access type
        VisitResult errVR;
        if(vr.accessType == VisitResult.AccessType.VAR_ACCESS)
            errVR = handleVarReassignment(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                vr.memberOrVarToAccess, ScriptAny(incOrDec));
        else if(vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
            errVR = handleArrayReassignment(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                vr.objectToAccess, vr.indexToAccess, ScriptAny(incOrDec));
        else if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS)
            errVR = handleObjectReassignment(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                vr.objectToAccess, vr.memberOrVarToAccess, ScriptAny(incOrDec));
        else
            vr.exception = new ScriptRuntimeException("Invalid post operand for " ~ ponode.opToken.symbol);
        if(errVR.exception !is null)
            return Variant(errVR);
        return Variant(vr);
	}
	
    /// handles : ? operator
	Variant visitTerniaryOpNode(TerniaryOpNode tonode)
	{
		// first evaluate the condition
        auto vr = tonode.conditionNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);
        if(vr.result)
            vr = tonode.onTrueNode.accept(this).get!VisitResult;
        else
            vr = tonode.onFalseNode.accept(this).get!VisitResult;
        return Variant(vr);
	}
	
    /// handles variable access
	Variant visitVarAccessNode(VarAccessNode vanode)
	{
		VisitResult vr;
        vr.accessType = VisitResult.AccessType.VAR_ACCESS;
        vr.memberOrVarToAccess = vanode.varToken.text;
        bool _; // @suppress(dscanner.suspicious.unmodified)
        immutable ptr = cast(immutable)_currentContext.lookupVariableOrConst(vanode.varToken.text, _);
        if(ptr == null)
            vr.exception = new ScriptRuntimeException("Undefined variable lookup " ~ vanode.varToken.text);
        else
            vr.result = *ptr;
        return Variant(vr);
	}
	
    /// handles function calls
	Variant visitFunctionCallNode(FunctionCallNode fcnode)
	{
        ScriptAny thisObj;
        auto vr = fcnode.functionToCall.accept(this).get!VisitResult;

        if(vr.exception !is null)
            return Variant(vr);

		// the "this" is the left hand of dot operation
        if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS 
            || vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
        {
            thisObj = vr.objectToAccess;
        }
		// or it is local "this" if exists
		else if(_currentContext.variableOrConstExists("this"))
		{
			bool _; // @suppress(dscanner.suspicious.unmodified)
			thisObj = *(_currentContext.lookupVariableOrConst("this", _));
		}

        auto fnToCall = vr.result;
        if(fnToCall.type == ScriptAny.Type.FUNCTION)
        {
            ScriptAny[] args;
            vr = convertExpressionsToArgs(fcnode.expressionArgs, args);
            if(vr.exception !is null)
                return Variant(vr);
            auto fn = fnToCall.toValue!ScriptFunction;
            vr = callFn(fn, thisObj, args, fcnode.returnThis);
            return Variant(vr);
        }
        else 
        {
            vr.result = ScriptAny.UNDEFINED;
            vr.exception = new ScriptRuntimeException("Unable to call non function " ~ fnToCall.toString);
            return Variant(vr);
        }
	}
	
    /// handle array index
	Variant visitArrayIndexNode(ArrayIndexNode ainode)
	{
		VisitResult vr = ainode.indexValueNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);
        auto index = vr.result;
        auto objVR = ainode.objectNode.accept(this).get!VisitResult;
        if(objVR.exception !is null)
            return Variant(objVR);

        // also need to validate that the object can be accessed
        if(!objVR.result.isObject)
        {
            vr.exception = new ScriptRuntimeException("Cannot index value " ~ objVR.result.toString);
            return Variant(vr);
        }

        if(index.type == ScriptAny.Type.STRING)
        {
            // we have to be accessing an object or trying to
            auto indexAsStr = index.toString();
            vr.accessType = VisitResult.AccessType.OBJECT_ACCESS;
            vr.memberOrVarToAccess = index.toString();
            vr.objectToAccess = objVR.result;
            vr.result = vr.objectToAccess.lookupField(indexAsStr);
        }
        else if(index.isNumber)
        {
            auto indexAsNum = index.toValue!size_t;
            vr.accessType = VisitResult.AccessType.ARRAY_ACCESS;
            vr.indexToAccess = indexAsNum;
            vr.objectToAccess = objVR.result;
            if(auto asString = objVR.result.toValue!ScriptString)
            {
                // TODO catch the UTFException and just return whatever
                auto wstr = asString.getWString();
                if(indexAsNum >= wstr.length)
                    vr.result = ScriptAny.UNDEFINED;
                else
                    vr.result = ScriptAny(cast(wstring)([ wstr[indexAsNum] ]));
            }
            else if(auto asArray = objVR.result.toValue!ScriptArray)
            {
                if(indexAsNum >= asArray.array.length)
                    vr.result = ScriptAny.UNDEFINED;
                else
                    vr.result = asArray.array[indexAsNum];
            }
            else
            {
                vr.exception = new ScriptRuntimeException("Attempt to index a non-string or non-array");
            }
        }
        else
        {
            vr.exception = new ScriptRuntimeException("Invalid index type for array or object access");
        }
        return Variant(vr);
	}
	
    /// handle dot operator
	Variant visitMemberAccessNode(MemberAccessNode manode)
	{
        VisitResult vr;
        string memberName = "";
        if(auto van = cast(VarAccessNode)manode.memberNode)
        {
            memberName = van.varToken.text;
        }
        else
        {
            vr.exception = new ScriptRuntimeException("Invalid operand for object member access");
            return Variant(vr);
        }

        auto objVR = manode.objectNode.accept(this).get!VisitResult;
        if(objVR.exception !is null)
            return Variant(objVR);
        // validate that objVR.result is of type object so that it can even be accessed
        if(!objVR.result.isObject)
        {
            vr.exception = new ScriptRuntimeException("Cannot access non-object " 
                ~ objVR.result.toString() ~ ": " ~ this.toString());
            return Variant(vr);
        }

        // set the fields
        vr.accessType = VisitResult.AccessType.OBJECT_ACCESS;
        vr.objectToAccess = objVR.result;
        vr.memberOrVarToAccess = memberName;
        // if this is a get property we need to use the getter otherwise we lookup field
        auto obj = vr.objectToAccess.toValue!ScriptObject;
        if(obj.hasGetter(memberName))
        {
            auto gvr = getObjectProperty(obj, memberName);
            if(gvr.exception !is null)
                return Variant(gvr);
            vr.result = gvr.result;
        }
        else
            vr.result = objVR.result.lookupField(memberName);
        return Variant(vr);
	}
	
    /// handles new expression
	Variant visitNewExpressionNode(NewExpressionNode nenode)
	{
		// fce should be a valid function call with its returnThis flag already set by the parser
        auto vr = nenode.functionCallExpression.accept(this);
        return vr; // caller will check for any exceptions.
	}
	
    /// handles var, let, and const declarations
	Variant visitVarDeclarationStatementNode(VarDeclarationStatementNode vdsnode)
	{
		VisitResult visitResult;
        foreach(varNode; vdsnode.varAccessOrAssignmentNodes)
        {
            if(auto v = cast(VarAccessNode)varNode)
            {
                auto varName = v.varToken.text;
                visitResult = handleVarDeclaration(vdsnode.qualifier.text, varName, ScriptAny.UNDEFINED);
                if(visitResult.exception !is null)
                    return Variant(visitResult);
            }
            else if(auto binNode = cast(BinaryOpNode)varNode)
            {
                // auto binNode = cast(BinaryOpNode)varNode;
                visitResult = binNode.rightNode.accept(this).get!VisitResult;
                if(visitResult.exception !is null)
                    return Variant(visitResult);
                auto valueToAssign = visitResult.result;
                // we checked this before so should be safe
                if(auto van = cast(VarAccessNode)(binNode.leftNode))
                {
                    auto varName = van.varToken.text;
                    visitResult = handleVarDeclaration(vdsnode.qualifier.text, varName, valueToAssign);
                    if(visitResult.exception !is null)
                        return Variant(visitResult);
                    // success so make sure anon function name matches
                    if(valueToAssign.type == ScriptAny.Type.FUNCTION)
                    {
                        auto func = valueToAssign.toValue!ScriptFunction;
                        if(func.functionName == "<anonymous function>" || func.functionName == "<anonymous class>")
                            func.functionName = varName;
                    }
                }
            }
            else 
                throw new Exception("Invalid declaration got past the parser");
        }
        return Variant(VisitResult(ScriptAny.UNDEFINED));
	}
	
    /// handles {block} statement
	Variant visitBlockStatementNode(BlockStatementNode bsnode)
	{
        Context oldContext = _currentContext; // @suppress(dscanner.suspicious.unmodified)
		_currentContext = new Context(_currentContext, "<scope>");
        auto result = VisitResult(ScriptAny.UNDEFINED);
        foreach(statement ; bsnode.statementNodes)
        {
            result = statement.accept(this).get!VisitResult;
            if(result.returnFlag || result.breakFlag || result.continueFlag || result.exception !is null)
            {
                if(result.exception)
                    result.exception.scriptTraceback ~= statement;
                break;
            }
        }   
        _currentContext = oldContext;
        return Variant(result);
	}
	
    /// handles if statements
	Variant visitIfStatementNode(IfStatementNode isnode)
	{
		auto vr = isnode.conditionNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);

        if(vr.result)
        {
            vr = isnode.onTrueStatement.accept(this).get!VisitResult;
        }
        else 
        {
            if(isnode.onFalseStatement !is null)
                vr = isnode.onFalseStatement.accept(this).get!VisitResult;
        }
        return Variant(vr);
	}
	
    /// handles switch case statements
	Variant visitSwitchStatementNode(SwitchStatementNode ssnode)
	{
		auto vr = ssnode.expressionNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);
        size_t jumpStatement = ssnode.switchBody.defaultStatementID;
        if(vr.result in ssnode.switchBody.jumpTable)
        {
            jumpStatement = ssnode.switchBody.jumpTable[vr.result];
        }
        if(jumpStatement < ssnode.switchBody.statementNodes.length)
        {
            for(size_t i = jumpStatement; i < ssnode.switchBody.statementNodes.length; ++i)
            {
                vr = ssnode.switchBody.statementNodes[i].accept(this).get!VisitResult;
                if(vr.returnFlag || vr.continueFlag || vr.breakFlag || vr.exception !is null)
                    return Variant(vr);
            }
        }
        return Variant(vr);
	}
	
    /// handles while statements
	Variant visitWhileStatementNode(WhileStatementNode wsnode)
	{
		if(wsnode.label != "")
            _currentContext.insertLabel(wsnode.label);
        auto vr = wsnode.conditionNode.accept(this).get!VisitResult;
        while(vr.result && vr.exception is null)
        {
            vr = wsnode.bodyNode.accept(this).get!VisitResult;
            if(vr.breakFlag)
            {
                if(vr.labelName == "")
                    vr.breakFlag = false;
                else
                {
                    if(_currentContext.labelExists(vr.labelName))
                    {
                        if(wsnode.label == vr.labelName)
                            vr.breakFlag = false;
                    }
                    else 
                        vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                }
                break;
            }
            if(vr.continueFlag)
            {
                if(vr.labelName == "")
                    vr.continueFlag = false;
                else
                {
                    if(_currentContext.labelExists(vr.labelName))
                    {
                        if(wsnode.label == vr.labelName)
                            vr.continueFlag = false;
                        else
                            break;
                    }
                    else
                    {
                        vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                        break;
                    }
                }
            }
            if(vr.exception !is null || vr.returnFlag)
                break;
            vr = wsnode.conditionNode.accept(this).get!VisitResult;
        }
        if(wsnode.label != "")
            _currentContext.removeLabelFromCurrent(wsnode.label);
        return Variant(vr);
	}
	
    /// handles do-while statement
	Variant visitDoWhileStatementNode(DoWhileStatementNode dwsnode)
	{
		auto vr = VisitResult(ScriptAny.UNDEFINED);
        if(dwsnode.label != "")
            _currentContext.insertLabel(dwsnode.label);
        do 
        {
            vr = dwsnode.bodyNode.accept(this).get!VisitResult;
            if(vr.breakFlag)
            {
                if(vr.labelName == "")
                    vr.breakFlag = false;
                else
                {
                    if(_currentContext.labelExists(vr.labelName))
                    {
                        if(dwsnode.label == vr.labelName)
                            vr.breakFlag = false;
                    }
                    else 
                        vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                }
                break;
            }
            if(vr.continueFlag)
            {
                if(vr.labelName == "")
                    vr.continueFlag = false;
                else
                {
                    if(_currentContext.labelExists(vr.labelName))
                    {
                        if(dwsnode.label == vr.labelName)
                            vr.continueFlag = false;
                        else
                            break;
                    }
                    else
                    {
                        vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                        break;
                    }
                }
            }
            if(vr.exception !is null || vr.returnFlag)
                break; 
            vr = dwsnode.conditionNode.accept(this).get!VisitResult;
        }
        while(vr.result && vr.exception is null);
        if(dwsnode.label != "")
            _currentContext.removeLabelFromCurrent(dwsnode.label);
        return Variant(vr);
	}
	
    /// handles for(;;) statements
	Variant visitForStatementNode(ForStatementNode fsnode)
	{
        Context oldContext = _currentContext; // @suppress(dscanner.suspicious.unmodified)
		_currentContext = new Context(_currentContext, "<outer_for_loop>");
        if(fsnode.label != "")
            _currentContext.insertLabel(fsnode.label);
        auto vr = VisitResult(ScriptAny.UNDEFINED);
        if(fsnode.varDeclarationStatement !is null)
            vr = fsnode.varDeclarationStatement.accept(this).get!VisitResult;
        if(vr.exception is null)
        {
            vr = fsnode.conditionNode.accept(this).get!VisitResult;
            while(vr.result && vr.exception is null)
            {
                vr = fsnode.bodyNode.accept(this).get!VisitResult;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(_currentContext.labelExists(vr.labelName))
                        {
                            if(fsnode.label == vr.labelName)
                                vr.breakFlag = false;
                        }
                        else 
                            vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                    }
                    break;
                }
                if(vr.continueFlag)
                {
                    if(vr.labelName == "")
                        vr.continueFlag = false;
                    else
                    {
                        if(_currentContext.labelExists(vr.labelName))
                        {
                            if(fsnode.label == vr.labelName)
                                vr.continueFlag = false;
                            else
                                break;
                        }
                        else
                        {
                            vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                            break;
                        }
                    }
                }
                if(vr.exception !is null || vr.returnFlag)
                    break; 
                vr = fsnode.incrementNode.accept(this).get!VisitResult;
                if(vr.exception !is null)
                    break;
                vr = fsnode.conditionNode.accept(this).get!VisitResult;
            }
        }
        if(fsnode.label != "")
            _currentContext.removeLabelFromCurrent(fsnode.label);
        _currentContext = oldContext;
        return Variant(vr);
	}
	
    /// handles for-of (and for-in) loops
	Variant visitForOfStatementNode(ForOfStatementNode fosnode)
	{
		auto vr = fosnode.objectToIterateNode.accept(this).get!VisitResult;
        // make sure this is iterable
        if(vr.exception !is null)
            return Variant(vr);

        if(fosnode.label != "")
            _currentContext.insertLabel(fosnode.label);

        if(vr.result.type == ScriptAny.Type.ARRAY)
        {
            auto arr = vr.result.toValue!(ScriptAny[]);
            for(size_t i = 0; i < arr.length; ++i)
            {
                // TODO optimize this to reassign variables instead of creating new contexts each iteration
                auto oldContext = _currentContext; // @suppress(dscanner.suspicious.unmodified)
                _currentContext = new Context(_currentContext, "<for_of_loop>");
                // if one var access node, then value, otherwise index then value
                if(fosnode.varAccessNodes.length == 1)
                {
                    _currentContext.declareVariableOrConst(fosnode.varAccessNodes[0].varToken.text,
                        arr[i], fosnode.qualifierToken.text == "const"? true: false);
                }
                else 
                {
                    _currentContext.declareVariableOrConst(fosnode.varAccessNodes[0].varToken.text,
                        ScriptAny(i), fosnode.qualifierToken.text == "const"? true: false);
                    _currentContext.declareVariableOrConst(fosnode.varAccessNodes[1].varToken.text,
                        arr[i], fosnode.qualifierToken.text == "const"? true: false);
                }
                vr = fosnode.bodyNode.accept(this).get!VisitResult;
                _currentContext = oldContext;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(_currentContext.labelExists(vr.labelName))
                        {
                            if(fosnode.label == vr.labelName)
                                vr.breakFlag = false;
                        }
                        else 
                            vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                    }
                    break;
                }
                if(vr.continueFlag)
                {
                    if(vr.labelName == "")
                        vr.continueFlag = false;
                    else
                    {
                        if(_currentContext.labelExists(vr.labelName))
                        {
                            if(fosnode.label == vr.labelName)
                                vr.continueFlag = false;
                            else
                                break;
                        }
                        else
                        {
                            vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                            break;
                        }
                    }
                }
                if(vr.exception !is null || vr.returnFlag)
                    break;
            }
        }
        else if(vr.result.isObject)
        {
            auto obj = vr.result.toValue!ScriptObject;
            // first value is key, second value is value if there
            foreach(key, val; obj.dictionary)
            {
                // TODO optimize this to reassign variables instead of creating new ones each iteration
                auto oldContext = _currentContext; // @suppress(dscanner.suspicious.unmodified)
                _currentContext = new Context(_currentContext, "<for_of_loop>");
                _currentContext.declareVariableOrConst(fosnode.varAccessNodes[0].varToken.text,
                    ScriptAny(key), fosnode.qualifierToken.text == "const" ? true: false);
                if(fosnode.varAccessNodes.length > 1)
                    _currentContext.declareVariableOrConst(fosnode.varAccessNodes[1].varToken.text,
                        ScriptAny(val), fosnode.qualifierToken.text == "const" ? true: false);
                vr = fosnode.bodyNode.accept(this).get!VisitResult;              
                _currentContext = oldContext;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(_currentContext.labelExists(vr.labelName))
                        {
                            if(fosnode.label == vr.labelName)
                                vr.breakFlag = false;
                        }
                        else 
                            vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                    }
                    break;
                }
                if(vr.continueFlag)
                {
                    if(vr.labelName == "")
                        vr.continueFlag = false;
                    else
                    {
                        if(_currentContext.labelExists(vr.labelName))
                        {
                            if(fosnode.label == vr.labelName)
                                vr.continueFlag = false;
                            else
                                break;
                        }
                        else
                        {
                            vr.exception = new ScriptRuntimeException("Label " ~ vr.labelName ~ " doesn't exist");
                            break;
                        }
                    }
                }
                if(vr.exception !is null || vr.returnFlag)
                    break; 
                if(vr.exception !is null)
                    break;
            }
        }

        else 
        {
            vr.exception = new ScriptRuntimeException("Cannot iterate over " ~ fosnode.objectToIterateNode.toString);
        }

        if(fosnode.label != "")
            _currentContext.removeLabelFromCurrent(fosnode.label);

        return Variant(vr);
	}
	
    /// handle break statements
	Variant visitBreakStatementNode(BreakStatementNode bsnode)
	{
		auto vr = VisitResult(ScriptAny.UNDEFINED);
        vr.breakFlag = true;
        vr.labelName = bsnode.label;
        return Variant(vr);
	}
	
    /// handle continue statements
	Variant visitContinueStatementNode(ContinueStatementNode csnode)
	{
        auto vr = VisitResult(ScriptAny.UNDEFINED);
        vr.continueFlag = true;
        vr.labelName = csnode.label;
        return Variant(vr);
	}
	
    /// handles return statements
	Variant visitReturnStatementNode(ReturnStatementNode rsnode)
	{
		VisitResult vr = VisitResult(ScriptAny.UNDEFINED);
        if(rsnode.expressionNode !is null)
        {
            vr = rsnode.expressionNode.accept(this).get!VisitResult;
            if(vr.exception !is null)
            {
                return Variant(vr);
            }
        }
        vr.returnFlag = true;
        return Variant(vr);
	}
	
    /// handle function declarations
	Variant visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode fdsnode)
	{
		auto func = new ScriptFunction(fdsnode.name, fdsnode.argNames, fdsnode.statementNodes, _currentContext);
        immutable okToDeclare = _currentContext.declareVariableOrConst(fdsnode.name, ScriptAny(func), false);
        VisitResult vr = VisitResult(ScriptAny.UNDEFINED);
        if(!okToDeclare)
        {
            vr.exception = new ScriptRuntimeException("Cannot redeclare variable or const " ~ fdsnode.name 
                ~ " with a function declaration");
        }
        return Variant(vr);
	}
	
    /// handles throw statements
	Variant visitThrowStatementNode(ThrowStatementNode tsnode)
	{
		auto vr = tsnode.expressionNode.accept(this).get!VisitResult;
        if(vr.exception !is null)
        {
            return Variant(vr);
        }
        vr.exception = new ScriptRuntimeException("Uncaught script exception");
        vr.exception.thrownValue = vr.result;
        vr.result = ScriptAny.UNDEFINED;
        return Variant(vr);
	}
	
    /// handle try catch block statements
	Variant visitTryCatchBlockStatementNode(TryCatchBlockStatementNode tcbsnode)
	{
		auto vr = tcbsnode.tryBlockNode.accept(this).get!VisitResult;
        // if there was an exception we need to start a new context and set it as a local variable
        if(vr.exception !is null)
        {
            auto oldContext = _currentContext; // @suppress(dscanner.suspicious.unmodified)
            _currentContext = new Context(_currentContext, "<catch>");
            if(vr.exception.thrownValue != ScriptAny.UNDEFINED)
                _currentContext.forceSetVarOrConst(tcbsnode.exceptionName, vr.exception.thrownValue, false);
            else 
                _currentContext.forceSetVarOrConst(tcbsnode.exceptionName, ScriptAny(vr.exception.message), false);
            vr.exception = null;
            // if another exception is thrown in the catch block, it will propagate through this return value
            vr = tcbsnode.catchBlockNode.accept(this).get!VisitResult;
            _currentContext = oldContext;
        }
        return Variant(vr);
	}
	
    /// handle delete statement
	Variant visitDeleteStatementNode(DeleteStatementNode dsnode)
	{
		auto vr = dsnode.memberAccessOrArrayIndexNode.accept(this).get!VisitResult;
        // TODO handle array
        if(vr.accessType != VisitResult.AccessType.OBJECT_ACCESS)
        {
            vr.exception = new ScriptRuntimeException("Invalid operand for delete operator");
            return Variant(vr);
        }
        if(vr.objectToAccess.isObject)
        {
            auto obj = vr.objectToAccess.toValue!ScriptObject;
            obj.dictionary.remove(vr.memberOrVarToAccess);
        }
        vr.result = ScriptAny.UNDEFINED;
        return Variant(vr);
	}
	
    /// handle class declaration
	Variant visitClassDeclarationStatementNode(ClassDeclarationStatementNode cdsnode)
	{
		VisitResult vr;
        // first try to assign the constructor as a local function
        immutable ok = _currentContext.declareVariableOrConst(cdsnode.className, ScriptAny(cdsnode.constructor), false);
        if(!ok)
        {
            vr.exception = new ScriptRuntimeException("Class declaration " ~ cdsnode.className 
                ~ " may not overwrite local variable or const");
            return Variant(vr);
        }
		// set constructor closure because parser couldn't set it
		cdsnode.constructor.closure = _currentContext;
        // fill in the function.prototype with the methods and set the closure context because the parser couldn't
        for(size_t i = 0; i < cdsnode.methodNames.length; ++i) 
		{
            cdsnode.constructor["prototype"][cdsnode.methodNames[i]] = ScriptAny(cdsnode.methods[i]);
			cdsnode.methods[i].closure = _currentContext;
		}
        // fill in any get properties and set closures
        for(size_t i = 0; i < cdsnode.getMethodNames.length; ++i)
		{
            cdsnode.constructor["prototype"].addGetterProperty(cdsnode.getMethodNames[i], cdsnode.getMethods[i]);
			cdsnode.getMethods[i].closure = _currentContext;
		}
        // fill in any set properties and set closures
        for(size_t i = 0; i < cdsnode.setMethodNames.length; ++i)
		{
            cdsnode.constructor["prototype"].addSetterProperty(cdsnode.setMethodNames[i], cdsnode.setMethods[i]);
			cdsnode.setMethods[i].closure = _currentContext;
		}
		// static methods are assigned directly to the constructor itself
		for(size_t i=0; i < cdsnode.staticMethodNames.length; ++i)
		{
			cdsnode.constructor[cdsnode.staticMethodNames[i]] = ScriptAny(cdsnode.staticMethods[i]);
			cdsnode.staticMethods[i].closure = _currentContext;
		}
        // if there is a base class, we must set the class's prototype's __proto__ to the base class's prototype
        if(cdsnode.baseClass !is null)
        {
            vr = cdsnode.baseClass.accept(this).get!VisitResult;
            if(vr.exception !is null)
                return Variant(vr);
            if(vr.result.type != ScriptAny.Type.FUNCTION)
            {
                // TODO also check that it is a constructor?
                vr.exception = new ScriptRuntimeException("Only classes can be extended");
                return Variant(vr);
            }   
            auto baseClassConstructor = vr.result.toValue!ScriptFunction;
            auto constructorPrototype = cdsnode.constructor["prototype"].toValue!ScriptObject;
            // if the base class constructor's "prototype" is null or non-object, it won't work anyway
            // NOTE that ["prototype"] and .prototype are completely unrelated
            constructorPrototype.prototype = baseClassConstructor["prototype"].toValue!ScriptObject;
            // set the constructor's __proto__ to the base class so that static methods are inherited
            // and the Function.call look up should still work
            cdsnode.constructor.prototype = baseClassConstructor;
        }
        vr.result = ScriptAny.UNDEFINED;
        return Variant(vr);
	}
	
    /// handle super constructor calls TODO use super as reference to base class with correct "this"
	Variant visitSuperCallStatementNode(SuperCallStatementNode scsnode)
	{
        auto vr = scsnode.classConstructorToCall.accept(this).get!VisitResult;
        if(vr.exception !is null)
            return Variant(vr);
        if(vr.result.type != ScriptAny.Type.FUNCTION)
        {
            vr.exception = new ScriptRuntimeException("Invalid super call");
            return Variant(vr);
        }
        auto fn = vr.result.toValue!ScriptFunction;
        // get the args
        ScriptAny[] args = [];
        foreach(expression ; scsnode.argExpressionNodes)
        {
            vr = expression.accept(this).get!VisitResult;
            if(vr.exception !is null)
                return Variant(vr);
            args ~= vr.result;
        }
        // get the "this" out of the context
        bool dontCare; // @suppress(dscanner.suspicious.unmodified)
        auto thisObjPtr = _currentContext.lookupVariableOrConst("this", dontCare);
        if(thisObjPtr == null)
        {
            vr.exception = new ScriptRuntimeException("Invalid `this` object in super call");
            return Variant(vr);
        }
        // TODO return values in constructors with expressions are invalid
        vr = callFn(fn, *thisObjPtr, args, false);
        return Variant(vr);
	}
	
    /// handle expression statements
	Variant visitExpressionStatementNode(ExpressionStatementNode esnode)
	{
		VisitResult vr;
        if(esnode.expressionNode !is null)
            vr = esnode.expressionNode.accept(this).get!VisitResult;
        vr.result = ScriptAny.UNDEFINED; // they should never return a result
        return Variant(vr); // caller will handle any exception
	}
	
package:
	/// holds information from visiting nodes TODO redesign this as a union
	struct VisitResult
	{
		enum AccessType { NO_ACCESS=0, VAR_ACCESS, ARRAY_ACCESS, OBJECT_ACCESS }

		this(T)(T val)
		{
			result = ScriptAny(val);
		}

		this(T : ScriptAny)(T val)
		{
			result = val;
		}

		ScriptAny result;

		AccessType accessType;
		ScriptAny objectToAccess;
		string memberOrVarToAccess;
		size_t indexToAccess;

		bool returnFlag, breakFlag, continueFlag;
		string labelName;
		ScriptRuntimeException exception;
	}

private:

    VisitResult callFn(ScriptFunction func, ScriptAny thisObj, ScriptAny[] args, bool returnThis = false)
	{
		VisitResult vr;
		if(returnThis)
		{
			if(!thisObj.isObject)
				thisObj = new ScriptObject(func.functionName, func["prototype"].toValue!ScriptObject, null);
		}
		// handle script functions
		if(func.type == ScriptFunction.Type.SCRIPT_FUNCTION)
		{
			auto prevContext = _currentContext; // @suppress(dscanner.suspicious.unmodified)
			_currentContext = new Context(func.closure, func.functionName);
			// set args as locals
			for(size_t i = 0; i < func.argNames.length; ++i)
			{
				if(i < args.length)
					_currentContext.forceSetVarOrConst(func.argNames[i], args[i], false);
				else
					_currentContext.forceSetVarOrConst(func.argNames[i], ScriptAny.UNDEFINED, false);
			}
			// put all arguments inside "arguments" local
			_currentContext.forceSetVarOrConst("arguments", ScriptAny(args), false);
			// set up "this" local
			_currentContext.forceSetVarOrConst("this", thisObj, true);
			foreach(statement ; func.statementNodes)
			{
				vr = statement.accept(this).get!VisitResult;
				if(vr.breakFlag) // TODO add enum stack to parser to prevent validation of breaks inside functions without loop
					vr.breakFlag = false;
				if(vr.continueFlag) // likewise
					vr.continueFlag = false;
				if(vr.returnFlag || vr.exception !is null)
				{
					if(vr.exception !is null)
						vr.exception.scriptTraceback ~= statement;
					vr.returnFlag = false;
					break;
				}
			}
			if(returnThis)
			{
				bool _; // @suppress(dscanner.suspicious.unmodified)
				immutable thisPtr = cast(immutable)_currentContext.lookupVariableOrConst("this", _);
				if(thisPtr != null)
					vr.result = *thisPtr;
			}
			_currentContext = prevContext;
			return vr;
		}
		else 
		{
			ScriptAny returnValue;
			auto nfe = NativeFunctionError.NO_ERROR;
			if(func.type == ScriptFunction.Type.NATIVE_FUNCTION)
			{
				auto nativefn = func.nativeFunction;
				returnValue = nativefn(_currentContext, &thisObj, args, nfe);
			}
			else
			{
				auto nativedg = func.nativeDelegate;
				returnValue = nativedg(_currentContext, &thisObj, args, nfe);
			}
			if(returnThis)
				vr.result = thisObj;
			else
				vr.result = returnValue;
			// check NFE
			final switch(nfe)
			{
			case NativeFunctionError.NO_ERROR:
				break;
			case NativeFunctionError.WRONG_NUMBER_OF_ARGS:
				vr.exception = new ScriptRuntimeException("Incorrect number of args to native method or function");
				break;
			case NativeFunctionError.WRONG_TYPE_OF_ARG:
				vr.exception = new ScriptRuntimeException("Wrong argument type to native method or function");
				break;
			case NativeFunctionError.RETURN_VALUE_IS_EXCEPTION:
				vr.exception = new ScriptRuntimeException(returnValue.toString());
				break;
			}

			return vr;
		}
	}

	VisitResult convertExpressionsToArgs(ExpressionNode[] exprs, out ScriptAny[] args)
	{
		args = [];
		VisitResult vr;
		foreach(expr ; exprs)
		{
			vr = expr.accept(this).get!VisitResult;
			if(vr.exception !is null)
			{
				args = [];
				return vr;
			}
			args ~= vr.result;
		}
		return vr;
	}

	VisitResult getObjectProperty(ScriptObject obj, in string propName)
	{
		VisitResult vr;
		ScriptObject objToSearch = obj;
		while(objToSearch !is null)
		{
			if(propName in objToSearch.getters)
			{
				vr = callFn(objToSearch.getters[propName], ScriptAny(obj), [], false);
				return vr;
			}
			objToSearch = objToSearch.prototype;
		}
		vr.exception = new ScriptRuntimeException("Object " ~ obj.toString() ~ " has no get property `" ~ propName ~ "`");
		return vr;
	}

	VisitResult handleArrayReassignment(Token opToken, ScriptAny arr, size_t index, ScriptAny value)
	{
		VisitResult vr;
		if(arr.type != ScriptAny.Type.ARRAY)
		{
			vr.exception = new ScriptRuntimeException("Cannot assign to index of non-array");
			return vr;
		}
		auto scriptArray = arr.toValue!ScriptArray;
		if(index >= scriptArray.length)
		{
			vr.exception = new ScriptRuntimeException("Out of bounds array assignment");
			return vr;
		}

		switch(opToken.type)
		{
		case Token.Type.ASSIGN:
			scriptArray.array[index] = value;
			break;
		case Token.Type.PLUS_ASSIGN:
			scriptArray.array[index] = scriptArray.array[index] + value;
			break;
		case Token.Type.DASH_ASSIGN:
			scriptArray.array[index] = scriptArray.array[index] - value;
			break;
		default:
			throw new Exception("Unhandled assignment operator");
		}
		vr.result = scriptArray.array[index];
		return vr;
	}

	VisitResult handleObjectReassignment(Token opToken, ScriptAny objToAccess, in string index, ScriptAny value)
	{
		VisitResult vr;
		if(!objToAccess.isObject)
		{
			vr.exception = new ScriptRuntimeException("Cannot index non-object");
			return vr;
		}
		auto obj = objToAccess.toValue!ScriptObject;
		// we may need the original value
		ScriptAny originalValue, newValue;
		if(obj.hasGetter(index))
		{
			// if getter with no setter this is an error
			if(!obj.hasSetter(index))
			{
				vr.exception = new ScriptRuntimeException("Object " ~ obj.toString() ~ " has no set property `" ~ index ~ "`");
				return vr;
			}
			vr = getObjectProperty(obj, index);
			if(vr.exception !is null)
				return vr;
			originalValue = vr.result;
		}
		else
		{
			originalValue = obj[index];
		}

		switch(opToken.type)
		{
		case Token.Type.ASSIGN:
			newValue = value;
			break;
		case Token.Type.PLUS_ASSIGN:
			newValue = originalValue + value;
			break;
		case Token.Type.DASH_ASSIGN:
			newValue = originalValue - value;
			break;
		default:
			throw new Exception("Unhandled assignment operator");
		}
		if(obj.hasSetter(index))
		{
			setObjectProperty(obj, index, newValue);
			if(obj.hasGetter(index))
				vr.result = newValue;
		}
		else
		{
			obj.assignField(index, newValue);
			vr.result = newValue;
		}
		return vr;
	}

	VisitResult handleVarDeclaration(in string qual, in string varName, ScriptAny value)
	{
		VisitResult vr;
		bool ok = false;
		string msg = "";
		if(qual == "var")
		{
			ok = _globalContext.declareVariableOrConst(varName, value, false);
			if(!ok)
				msg = "Unable to redeclare global " ~ varName;
		}
		else if(qual == "let")
		{
			ok = _currentContext.declareVariableOrConst(varName, value, false);
			if(!ok)
				msg = "Unable to redeclare local variable " ~ varName;
		}
		else if(qual == "const")
		{
			ok = _currentContext.declareVariableOrConst(varName, value, true);
			if(!ok)
				msg = "Unable to redeclare local const " ~ varName;
		}
		if(!ok)
			vr.exception = new ScriptRuntimeException(msg);
		return vr;
	}

	VisitResult handleVarReassignment(Token opToken, in string varName, ScriptAny value)
	{
		bool isConst; // @suppress(dscanner.suspicious.unmodified)
		auto ptr = _currentContext.lookupVariableOrConst(varName, isConst);
		VisitResult vr;
		if(isConst)
			vr.exception = new ScriptRuntimeException("Unable to reassign const " ~ varName);
		else if(ptr == null)
			vr.exception = new ScriptRuntimeException("Unable to reassign undefined variable " ~ varName);
		
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
			throw new Exception("Unhandled reassignment operator");
		}
		vr.result = *ptr;
		return vr;
	}

	VisitResult setObjectProperty(ScriptObject obj, string propName, ScriptAny value)
	{
		VisitResult vr;
        auto objectToSearch = obj;
        while(objectToSearch !is null)
        {
            if(propName in objectToSearch.setters)
			{
				vr = callFn(objectToSearch.setters[propName], ScriptAny(obj), [value], false);
				return vr;
			}
            objectToSearch = objectToSearch.prototype;
        }
		vr.exception = new ScriptRuntimeException("Object " ~ obj.toString() ~ " has no set property `" ~ propName ~ "`");
        return vr;
	}

    Context _globalContext;
    Context _currentContext;
}

