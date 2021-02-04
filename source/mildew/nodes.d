/**
 * This module implements the Node subclasses, which are used internally as a syntax tree.
 */
module mildew.nodes;

import std.format: format;

import mildew.context: Context;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token;
import mildew.types;

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
    this(Token token, ScriptAny val)
    {
        literalToken = token;
        value = val;
    }

    override string toString() const
    {
        if(value.type == ScriptAny.Type.STRING)
            return "\"" ~ literalToken.text ~ "\"";
        else
            return literalToken.text;
    }

    override VisitResult visit(Context c)
    {
        import mildew.exceptions: ScriptCompileException;
        import mildew.parser: Parser;
        import mildew.lexer: Lexer;

        // we have to handle `` strings here
        // this probably needs to be re-written with easy string building
        if(literalToken.literalFlag == Token.LiteralFlag.TEMPLATE_STRING)
        {
            size_t currentStart = 0;
            size_t endLast;
            bool addToParseString = false;
            string result;
            string stringToParse;
            for(size_t index = 0; index < literalToken.text.length; ++index)
            {
                if(literalToken.text[index] == '$')
                {
                    if(index < literalToken.text.length - 1) // @suppress(dscanner.suspicious.length_subtraction)
                    {
                        if(literalToken.text[index+1] == '{')
                        {
                            addToParseString = true;
                            index += 1;
                        }
                        else
                        {
                            if(addToParseString)
                                stringToParse ~= literalToken.text[index];
                            else
                                endLast = index + 1;
                        }
                    }
                    else 
                    {
                        if(addToParseString)
                            stringToParse ~= literalToken.text[index];
                        else
                            endLast = index + 1; 
                    }
                }
                else if(literalToken.text[index] == '}' && addToParseString)
                {
                    result ~= literalToken.text[currentStart .. endLast];
                    auto lexer = Lexer(stringToParse);
                    auto parser = Parser(lexer.tokenize());
                    Node expressionNode;
                    VisitResult vr;
                    try 
                    {
                        expressionNode = parser.parseExpression();
                    }
                    catch(ScriptCompileException ex)
                    {
                        vr.exception = new ScriptRuntimeException(ex.msg);
                        return vr;
                    }
                    vr = expressionNode.visit(c);
                    if(vr.exception !is null)
                        return vr;
                    result ~= vr.result.toString();
                    addToParseString = false;
                    currentStart = index+1;
                    stringToParse = "";
                }
                else
                {
                    if(addToParseString)
                        stringToParse ~= literalToken.text[index];
                    else
                        endLast = index + 1;
                }
            }
            if(addToParseString)
            {
                VisitResult vr;
                vr.exception = new ScriptRuntimeException("Unclosed template string expression");
                return vr;
            }
            if(currentStart < literalToken.text.length)
                result ~= literalToken.text[currentStart .. endLast];
            return VisitResult(result);

        }
        else 
        {
			// if it is a function literal we have to set the context here
			if(value.type == ScriptAny.Type.FUNCTION)
			{
				auto fn = value.toValue!ScriptFunction;
				fn.closure = c;
			}
            // parser handles other Lflags
            return VisitResult(value);
        }
    }

    Token literalToken;
    ScriptAny value;
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
        ScriptAny[] values = [];
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
        ScriptAny[] vals = [];
        VisitResult vr;
        foreach(valueNode ; valueNodes)
        {
            vr = valueNode.visit(c);
            if(vr.exception !is null)
                return vr;
            vals ~= vr.result;
        }
        auto obj = new ScriptObject("", null, null);
        for(size_t i = 0; i < keys.length; ++i)
        {
            obj.assignField(keys[i], vals[i]);
        }
        vr.result = obj;
        return vr;
    }

    string[] keys;
    Node[] valueNodes;
}

class ClassLiteralNode : Node 
{
    this(ScriptFunction cfn, string[] mnames, ScriptFunction[] ms, string[] gnames, ScriptFunction[] gs, 
			string[] snames, ScriptFunction[] ss, string[] statNames, ScriptFunction[] statics, Node baseClass)
    {
        constructorFn = cfn;
		methodNames = mnames;
		methods = ms;
		assert(methodNames.length == methods.length);
		getterNames = gnames;
		getters = gs;
		assert(getterNames.length == getters.length);
		setterNames = snames;
		setters = ss;
		assert(setterNames.length == setters.length);
		staticMethodNames = statNames;
		staticMethods = statics;
		assert(staticMethodNames.length == staticMethods.length);
        baseClassNode = baseClass;
    }

    override string toString() const 
    {
        auto str = "class";
        if(baseClassNode !is null)
            str ~= " extends " ~ baseClassNode.toString();
        return str;
    }

    override VisitResult visit(Context context)
    {
        VisitResult vr;

		// set constructor closure because parser couldn't set it
		constructorFn.closure = context;
        // fill in the function.prototype with the methods and set the closure context because the parser couldn't
        for(size_t i = 0; i < methodNames.length; ++i) 
		{
            constructorFn["prototype"][methodNames[i]] = ScriptAny(methods[i]);
			methods[i].closure = context;
		}
        // fill in any get properties and set closures
        for(size_t i = 0; i < getterNames.length; ++i)
		{
            constructorFn["prototype"].addGetterProperty(getterNames[i], getters[i]);
			getters[i].closure = context;
		}
        // fill in any set properties and set closures
        for(size_t i = 0; i < setterNames.length; ++i)
		{
            constructorFn["prototype"].addSetterProperty(setterNames[i], setters[i]);
			setters[i].closure = context;
		}
		// static methods are assigned directly to the constructor itself
		for(size_t i=0; i < staticMethodNames.length; ++i)
		{
			constructorFn[staticMethodNames[i]] = ScriptAny(staticMethods[i]);
			staticMethods[i].closure = context;
		}

        if(baseClassNode !is null)
        {
            vr = baseClassNode.visit(context);
            if(vr.exception !is null)
                return vr;
            if(vr.result.type != ScriptAny.Type.FUNCTION)
            {
                vr.exception = new ScriptRuntimeException("Only classes can be extended");
                return vr;
            }   
            auto baseClassConstructor = vr.result.toValue!ScriptFunction;
            auto constructorPrototype = constructorFn["prototype"].toValue!ScriptObject;
            // if the base class constructor's "prototype" is null or non-object, it won't work anyway
            // NOTE that ["prototype"] and .prototype are completely unrelated
            constructorPrototype.prototype = baseClassConstructor["prototype"].toValue!ScriptObject;
            // set the constructor's __proto__ to the base class so that static methods are inherited
            // and the Function.call look up should still work
            constructorFn.prototype = baseClassConstructor;
        }
        vr.result = constructorFn;
        return vr;        
    }

    ScriptFunction constructorFn;
	string[] methodNames;
	ScriptFunction[] methods;
	string[] getterNames;
	ScriptFunction[] getters;
	string[] setterNames;
	ScriptFunction[] setters;
	string[] staticMethodNames;
	ScriptFunction[] staticMethods;
	Node baseClassNode;
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
            // if an anonymous class or function is being assigned we need to update its name
            if(rhsResult.result.type == ScriptAny.Type.FUNCTION)
            {
                auto func = rhsResult.result.toValue!ScriptFunction;
                if(func.functionName == "<anonymous function>" || func.functionName == "<anonymous class>")
                    func.functionName = leftNode.toString;
            }
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
            case Token.Type.AND:
                return VisitResult(lhs && rhs);
            case Token.Type.OR:
                return VisitResult(lhs.orOp(rhs));
            default:
                if(opToken.isKeyword("instanceof"))
                {
                    if(!lhs.isObject)
                        return VisitResult(false);
                    if(rhs.type != ScriptAny.Type.FUNCTION)
                        return VisitResult(false);
                    auto lhsObj = lhs.toValue!ScriptObject; // @suppress(dscanner.suspicious.unmodified)
                    auto rhsFunc = rhs.toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)
                    auto proto = lhsObj.prototype;
                    while(proto !is null)
                    {
                        if(proto["constructor"].toValue!ScriptFunction is rhsFunc)
                            return VisitResult(true);
                        proto = proto.prototype;
                    }
                    return VisitResult(false);
                }
                else
                    throw new Exception("Forgot to implement missing binary operator " 
                        ~ opToken.type.to!string ~ " for " ~ this.toString());
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
        int incOrDec = 0;
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
            case Token.Type.DEC:
                incOrDec = -1;
                break;
            case Token.Type.INC:
                incOrDec = 1;
                break;
            default:
                if(opToken.isKeyword("typeof"))
                    return VisitResult(value.typeToString());
                return VisitResult(ScriptAny.UNDEFINED);
        }

        if(incOrDec != 0)
        {
            // TODO: fix this to allow constructs such as ++foo++
            if(vr.accessType == VisitResult.AccessType.VAR_ACCESS)
                return handleVarReassignment(c, Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                    vr.memberOrVarToAccess, ScriptAny(incOrDec));
            else if(vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
                return handleArrayReassignment(c, Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                    vr.objectToAccess, vr.indexToAccess, ScriptAny(incOrDec));
            else if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS)
                return handleObjectReassignment(c, Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                    vr.objectToAccess, vr.memberOrVarToAccess, ScriptAny(incOrDec));
            else
                vr.exception = new ScriptRuntimeException("Invalid operand for " ~ opToken.symbol);
        }
        return vr;
    }

    Token opToken;
    Node operandNode;
}

class PostfixOpNode : Node 
{
    this(Token op, Node node)
    {
        opToken = op;
        operandNode = node;
    }

    override VisitResult visit(Context c)
    {
        // first get the operand's original value that will be returned
        VisitResult vr = operandNode.visit(c);
        if(vr.exception !is null)
            return vr;
        auto incOrDec = 0;
        if(opToken.type == Token.Type.INC)
            incOrDec = 1;
        else if(opToken.type == Token.Type.DEC)
            incOrDec = -1;
        else
            throw new Exception("Invalid postfix operator got past the parser");
        // now perform an increment or decrement assignment based on object access type
        VisitResult errVR;
        if(vr.accessType == VisitResult.AccessType.VAR_ACCESS)
            errVR = handleVarReassignment(c, Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                vr.memberOrVarToAccess, ScriptAny(incOrDec));
        else if(vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
            errVR = handleArrayReassignment(c, Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                vr.objectToAccess, vr.indexToAccess, ScriptAny(incOrDec));
        else if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS)
            errVR = handleObjectReassignment(c, Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                vr.objectToAccess, vr.memberOrVarToAccess, ScriptAny(incOrDec));
        else
            vr.exception = new ScriptRuntimeException("Invalid post operand for " ~ opToken.symbol);
        if(errVR.exception !is null)
            return errVR;
        return vr;
    }

    override string toString() const 
    {
        return operandNode.toString() ~ opToken.symbol;
    }

    Token opToken;
    Node operandNode;
}

class TerniaryOpNode : Node 
{
    this(Node cond, Node onTrue, Node onFalse)
    {
        conditionNode = cond;
        onTrueNode = onTrue;
        onFalseNode = onFalse;
    }

    override string toString() const 
    {
        return conditionNode.toString() ~ "? " ~ onTrueNode.toString() ~ " : " ~ onFalseNode.toString();
    }

    override VisitResult visit(Context c)
    {
        // first evaluate the condition
        auto vr = conditionNode.visit(c);
        if(vr.exception !is null)
            return vr;
        if(vr.result)
        {
            vr = onTrueNode.visit(c);
        }
        else
        {
            vr = onFalseNode.visit(c);
        }
        return vr;
    }

    Node conditionNode;
    Node onTrueNode;
    Node onFalseNode;
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
        ScriptAny thisObj; // TODO get the possible global "this" object
        auto vr = functionToCall.visit(c);

        if(vr.exception !is null)
            return vr;

        if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS 
            || vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
        {
            thisObj = vr.objectToAccess;
        }

        auto fnToCall = vr.result;
        if(fnToCall.type == ScriptAny.Type.FUNCTION)
        {
            ScriptAny[] args;
            vr = convertExpressionsToArgs(c, expressionArgs, args);
            if(vr.exception !is null)
                return vr;
            auto fn = fnToCall.toValue!ScriptFunction;
            vr = callFunction(c, fn, thisObj, args, returnThis);
            return vr;
        }
        else 
        {
            vr.result = ScriptAny.UNDEFINED;
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

        // also need to validate that the object can be accessed
        if(!objVR.result.isObject)
        {
            vr.exception = new ScriptRuntimeException("Cannot index value " ~ objVR.result.toString);
            return vr;
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
                    vr.result = ScriptAny([ wstr[indexAsNum] ]);
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
        // validate that objVR.result is of type object so that it can even be accessed
        if(!objVR.result.isObject)
        {
            vr.exception = new ScriptRuntimeException("Cannot access non-object " 
                ~ objVR.result.toString() ~ ": " ~ this.toString());
            return vr;
        }

        // set the fields
        vr.accessType = VisitResult.AccessType.OBJECT_ACCESS;
        vr.objectToAccess = objVR.result;
        vr.memberOrVarToAccess = memberName;
        // if this is a get property we need to use the getter otherwise we lookup field
        auto obj = vr.objectToAccess.toValue!ScriptObject;
        if(obj.hasGetter(memberName))
        {
            auto gvr = obj.lookupProperty(c, memberName);
            if(gvr.exception !is null)
                return gvr;
            vr.result = gvr.result;
        }
        else
            vr.result = objVR.result.lookupField(memberName);
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
                auto varName = v.varToken.text;
                visitResult = handleVarDeclaration(context, qualifier.text, varName, ScriptAny.UNDEFINED);
                if(visitResult.exception !is null)
                {
                    visitResult.exception.scriptTraceback ~= this;
                    return visitResult;
                }
            }
            else if(auto binNode = cast(BinaryOpNode)varNode)
            {
                // auto binNode = cast(BinaryOpNode)varNode;
                visitResult = binNode.rightNode.visit(context);
                if(visitResult.exception !is null)
                    return visitResult;
                auto valueToAssign = visitResult.result;
                // we checked this before so should be safe
                if(auto van = cast(VarAccessNode)(binNode.leftNode))
                {
                    auto varName = van.varToken.text;
                    visitResult = handleVarDeclaration(context, qualifier.text, varName, valueToAssign);
                    if(visitResult.exception !is null)
                    {
                        visitResult.exception.scriptTraceback ~= this;
                        return visitResult;
                    }
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
        return VisitResult(ScriptAny.UNDEFINED);
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
        auto result = VisitResult(ScriptAny.UNDEFINED);
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

class SwitchStatementNode : StatementNode
{
    this(size_t lineNo, Node expr, SwitchBody sbody)
    {
        super(lineNo);
        expressionNode = expr;
        switchBody = sbody;
    }

    override VisitResult visit(Context c)
    {
        auto vr = expressionNode.visit(c);
        if(vr.exception !is null)
            return vr;
        size_t jumpStatement = switchBody.defaultStatementID;
        if(vr.result in switchBody.jumpTable)
        {
            jumpStatement = switchBody.jumpTable[vr.result];
        }
        if(jumpStatement < switchBody.statementNodes.length)
        {
            for(size_t i = jumpStatement; i < switchBody.statementNodes.length; ++i)
            {
                vr = switchBody.statementNodes[i].visit(c);
                if(vr.returnFlag || vr.continueFlag || vr.breakFlag || vr.exception !is null)
                    return vr;
            }
        }
        return vr;
    }

    Node expressionNode; // expression to test
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
    this(size_t lineNo, Node condition, StatementNode bnode, string lbl = "")
    {
        super(lineNo);
        conditionNode = condition;
        bodyNode = bnode;
        label = lbl;
    }

    override string toString() const
    {
        auto str = "while(" ~ conditionNode.toString() ~ ") ";
        str ~= bodyNode.toString();
        return str;
    }

    override VisitResult visit(Context c)
    {
        if(label != "")
            c.insertLabel(label);
        auto vr = conditionNode.visit(c);
        while(vr.result && vr.exception is null)
        {
            vr = bodyNode.visit(c);
            if(vr.breakFlag)
            {
                if(vr.labelName == "")
                    vr.breakFlag = false;
                else
                {
                    if(c.labelExists(vr.labelName))
                    {
                        if(label == vr.labelName)
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
                    if(c.labelExists(vr.labelName))
                    {
                        if(label == vr.labelName)
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
            vr = conditionNode.visit(c);
        }
        if(label != "")
            c.removeLabelFromCurrent(label);
        return vr;
    }

    Node conditionNode;
    StatementNode bodyNode;
    string label;
}

class DoWhileStatementNode : StatementNode
{
    this(size_t lineNo, StatementNode bnode, Node condition, string lbl="")
    {
        super(lineNo);
        bodyNode = bnode;
        conditionNode = condition;
        label = lbl;
    }

    override string toString() const
    {
        auto str = "do " ~ bodyNode.toString() ~ " while("
            ~ conditionNode.toString() ~ ")";
        return str;
    }

    override VisitResult visit(Context c)
    {
        auto vr = VisitResult(ScriptAny.UNDEFINED);
        if(label != "")
            c.insertLabel(label);
        do 
        {
            vr = bodyNode.visit(c);
            if(vr.breakFlag)
            {
                if(vr.labelName == "")
                    vr.breakFlag = false;
                else
                {
                    if(c.labelExists(vr.labelName))
                    {
                        if(label == vr.labelName)
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
                    if(c.labelExists(vr.labelName))
                    {
                        if(label == vr.labelName)
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
            vr = conditionNode.visit(c);
        }
        while(vr.result && vr.exception is null);
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        if(label != "")
            c.removeLabelFromCurrent(label);
        return vr;
    }

    StatementNode bodyNode;
    Node conditionNode;
    string label;
}

class ForStatementNode : StatementNode
{
    this(size_t lineNo, VarDeclarationStatementNode decl, Node condition, Node increment, 
         StatementNode bnode, string lbl="")
    {
        super(lineNo);
        varDeclarationStatement = decl;
        conditionNode = condition;
        incrementNode = increment;
        bodyNode = bnode;
        label = lbl;
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
        if(label != "")
            context.insertLabel(label);
        auto vr = VisitResult(ScriptAny.UNDEFINED);
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
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(context.labelExists(vr.labelName))
                        {
                            if(label == vr.labelName)
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
                        if(context.labelExists(vr.labelName))
                        {
                            if(label == vr.labelName)
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
                vr = incrementNode.visit(context);
                if(vr.exception !is null)
                    break;
                vr = conditionNode.visit(context);
            }
        }
        if(label != "")
            context.removeLabelFromCurrent(label);
        context = context.parent;
        if(vr.exception !is null)
            vr.exception.scriptTraceback ~= this;
        return vr;
    }

    VarDeclarationStatementNode varDeclarationStatement;
    Node conditionNode;
    Node incrementNode;
    StatementNode bodyNode;
    string label;
}

// for of can't do let {a,b} but it can do let a,b and be used the same as for in in JS
class ForOfStatementNode : StatementNode
{
    this(size_t lineNo, Token qual, VarAccessNode[] vans, Node obj, StatementNode bnode, string lbl="")
    {
        super(lineNo);
        qualifierToken = qual;
        varAccessNodes = vans;
        objectToIterateNode = obj;
        bodyNode = bnode;
        label = lbl;
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

        if(label != "")
            context.insertLabel(label);

        if(vr.result.type == ScriptAny.Type.ARRAY)
        {
            auto arr = vr.result.toValue!(ScriptAny[]);
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
                        ScriptAny(i), qualifierToken.text == "const"? true: false);
                    context.declareVariableOrConst(varAccessNodes[1].varToken.text,
                        arr[i], qualifierToken.text == "const"? true: false);
                }
                vr = bodyNode.visit(context);
                context = context.parent;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(context.labelExists(vr.labelName))
                        {
                            if(label == vr.labelName)
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
                        if(context.labelExists(vr.labelName))
                        {
                            if(label == vr.labelName)
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
                context = new Context(context, "<for_of_loop>");
                context.declareVariableOrConst(varAccessNodes[0].varToken.text,
                    ScriptAny(key), qualifierToken.text == "const" ? true: false);
                if(varAccessNodes.length > 1)
                    context.declareVariableOrConst(varAccessNodes[1].varToken.text,
                        ScriptAny(val), qualifierToken.text == "const" ? true: false);
                vr = bodyNode.visit(context);              
                context = context.parent;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(context.labelExists(vr.labelName))
                        {
                            if(label == vr.labelName)
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
                        if(context.labelExists(vr.labelName))
                        {
                            if(label == vr.labelName)
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
            vr.exception = new ScriptRuntimeException("Cannot iterate over " ~ objectToIterateNode.toString);
        }

        if(label != "")
            context.removeLabelFromCurrent(label);

        return vr;
    }

    Token qualifierToken;
    VarAccessNode[] varAccessNodes;
    Node objectToIterateNode;
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

    override string toString() const
    {
        return "break " ~ label ~ ";";
    }

    override VisitResult visit(Context c)
    {
        auto vr = VisitResult(ScriptAny.UNDEFINED);
        vr.breakFlag = true;
        vr.labelName = label;
        return vr;
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

    override string toString() const
    {
        return "continue " ~ label ~ ";";
    }

    override VisitResult visit(Context c)
    {
        auto vr = VisitResult(ScriptAny.UNDEFINED);
        vr.continueFlag = true;
        vr.labelName = label;
        return vr;
    }

    string label;
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
        VisitResult vr = VisitResult(ScriptAny.UNDEFINED);
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
        auto func = new ScriptFunction(name, argNames, statementNodes, c);
        immutable okToDeclare = c.declareVariableOrConst(name, ScriptAny(func), false);
        VisitResult vr = VisitResult(ScriptAny.UNDEFINED);
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
        vr.exception.scriptTraceback ~= this;
        vr.result = ScriptAny.UNDEFINED;
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
            if(vr.exception.thrownValue != ScriptAny.UNDEFINED)
                context.forceSetVarOrConst(exceptionName, vr.exception.thrownValue, false);
            else 
                context.forceSetVarOrConst(exceptionName, ScriptAny(vr.exception.message), false);
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
            obj.dictionary.remove(vr.memberOrVarToAccess);
        }
        vr.result = ScriptAny.UNDEFINED;
        return vr;
    }

    Node memberAccessOrArrayIndexNode;
}

class ClassDeclarationStatementNode : StatementNode
{
    this(size_t lineNo, string name, ScriptFunction con, string[] mnames, ScriptFunction[] ms, 
         string[] gnames, ScriptFunction[] getters, string[] snames, ScriptFunction[] setters,
		 string[] sfnNames, ScriptFunction[] staticMs, 
         Node bc = null)
    {
        super(lineNo);
        className = name;
        constructor = con; // can't be null must at least be ScriptFunction.emptyFunction("NameOfClass")
        methodNames = mnames;
        methods = ms;
        assert(methodNames.length == methods.length);
        getMethodNames = gnames;
        getMethods = getters;
        assert(getMethodNames.length == getMethods.length);
        setMethodNames = snames;
        setMethods = setters;
        assert(setMethodNames.length == setMethods.length);
		staticMethodNames = sfnNames;
		staticMethods = staticMs;
		assert(staticMethodNames.length == staticMethods.length);
        baseClass = bc;
    }

    override VisitResult visit(Context context)
    {
        VisitResult vr;
        // first try to assign the constructor as a local function
        immutable ok = context.declareVariableOrConst(className, ScriptAny(constructor), false);
        if(!ok)
        {
            vr.exception = new ScriptRuntimeException("Class declaration " ~ className 
                ~ " may not overwrite local variable or const");
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
		// set constructor closure because parser couldn't set it
		constructor.closure = context;
        // fill in the function.prototype with the methods and set the closure context because the parser couldn't
        for(size_t i = 0; i < methodNames.length; ++i) 
		{
            constructor["prototype"][methodNames[i]] = ScriptAny(methods[i]);
			methods[i].closure = context;
		}
        // fill in any get properties and set closures
        for(size_t i = 0; i < getMethodNames.length; ++i)
		{
            constructor["prototype"].addGetterProperty(getMethodNames[i], getMethods[i]);
			getMethods[i].closure = context;
		}
        // fill in any set properties and set closures
        for(size_t i = 0; i < setMethodNames.length; ++i)
		{
            constructor["prototype"].addSetterProperty(setMethodNames[i], setMethods[i]);
			setMethods[i].closure = context;
		}
		// static methods are assigned directly to the constructor itself
		for(size_t i=0; i < staticMethodNames.length; ++i)
		{
			constructor[staticMethodNames[i]] = ScriptAny(staticMethods[i]);
			staticMethods[i].closure = context;
		}
        // if there is a base class, we must set the class's prototype's __proto__ to the base class's prototype
        if(baseClass !is null)
        {
            vr = baseClass.visit(context);
            if(vr.exception !is null)
                return vr;
            if(vr.result.type != ScriptAny.Type.FUNCTION)
            {
                vr.exception = new ScriptRuntimeException("Only classes can be extended");
                vr.exception.scriptTraceback ~= this;
                return vr;
            }   
            auto baseClassConstructor = vr.result.toValue!ScriptFunction;
            auto constructorPrototype = constructor["prototype"].toValue!ScriptObject;
            // if the base class constructor's "prototype" is null or non-object, it won't work anyway
            // NOTE that ["prototype"] and .prototype are completely unrelated
            constructorPrototype.prototype = baseClassConstructor["prototype"].toValue!ScriptObject;
            // set the constructor's __proto__ to the base class so that static methods are inherited
            // and the Function.call look up should still work
            constructor.prototype = baseClassConstructor;
        }
        vr.result = ScriptAny.UNDEFINED;
        return vr;
    }

    string className;
    ScriptFunction constructor;
    string[] methodNames;
    ScriptFunction[] methods;
    string[] getMethodNames;
    ScriptFunction[] getMethods;
    string[] setMethodNames;
    ScriptFunction[] setMethods;
	string[] staticMethodNames;
	ScriptFunction[] staticMethods;
    Node baseClass; // should be an expression that returns a constructor function
}

class SuperCallStatementNode : StatementNode
{
    this(size_t lineNo, Node ctc, Node[] args)
    {
        super(lineNo);
        classConstructorToCall = ctc; // Cannot be null or something wrong with parser
        argExpressionNodes = args;
    }

    override VisitResult visit(Context c)
    {
        auto vr = classConstructorToCall.visit(c);
        if(vr.exception !is null)
            return vr;
        if(vr.result.type != ScriptAny.Type.FUNCTION)
        {
            vr.exception = new ScriptRuntimeException("Invalid super call");
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
        auto fn = vr.result.toValue!ScriptFunction;
        // get the args
        ScriptAny[] args = [];
        foreach(expression ; argExpressionNodes)
        {
            vr = expression.visit(c);
            if(vr.exception !is null)
                return vr;
            args ~= vr.result;
        }
        // get the "this" out of the context
        bool dontCare; // @suppress(dscanner.suspicious.unmodified)
        auto thisObjPtr = c.lookupVariableOrConst("this", dontCare);
        if(thisObjPtr == null)
        {
            vr.exception = new ScriptRuntimeException("Invalid `this` object in super call");
            vr.exception.scriptTraceback ~= this;
            return vr;
        }
        vr = fn.call(c, *thisObjPtr, args, false);
        return vr;
    }

    Node classConstructorToCall; // should always evaluate to a function
    Node[] argExpressionNodes;
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
        vr.result = ScriptAny.UNDEFINED; // they should never return a result
        return vr; // caller will handle any exception
    }

    Node expressionNode;
}

VisitResult handleVarReassignment(Context c, Token opToken, string varToAccess, ScriptAny value)
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

VisitResult handleArrayReassignment(Context c, Token opToken, ScriptAny arr, 
                                    size_t index, ScriptAny value)
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
        // TODO expand the array instead
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
            throw new Exception("Something has gone terribly wrong");
    }
    vr.result = scriptArray.array[index];
    return vr;
}

VisitResult handleObjectReassignment(Context c, Token opToken, ScriptAny objectToAccess, string index, 
                                    ScriptAny value)
{
    VisitResult vr;
    if(!objectToAccess.isObject)
    {
        vr.exception = new ScriptRuntimeException("Cannot index non-object");
        return vr;
    }

    auto obj = objectToAccess.toValue!ScriptObject;
    immutable hasSetter = obj.hasSetter(index);
    ScriptAny originalValue;
    if(obj.hasGetter(index))
    {
        // it also has to have the same setter for this assignment to be valid
        if(!obj.hasSetter(index))
        {
            vr.exception = new ScriptRuntimeException("Object has no setter " ~ index);
            return vr;
        }
        vr = obj.lookupProperty(c, index);
        if(vr.exception !is null)
            return vr;
        originalValue = vr.result;
    }
    else
    {
        originalValue = obj.lookupField(index);
    }

    switch(opToken.type)
    {
        case Token.Type.ASSIGN:
            if(hasSetter)
                obj.assignProperty(c, index, value);
            else
                obj.assignField(index, value);
            break;
        case Token.Type.PLUS_ASSIGN:
            if(hasSetter)
                obj.assignProperty(c, index, originalValue + value);
            else
                obj.assignField(index, originalValue + value);
            break;
        case Token.Type.DASH_ASSIGN:
            if(hasSetter)
                obj.assignProperty(c, index, originalValue - value);
            else
                obj.assignField(index, originalValue - value);
            break;
        default:
            throw new Exception("Something has gone terribly wrong");
    }
    vr.result = obj.lookupField(index);
    return vr;
}

VisitResult handleVarDeclaration(Context c, in string qual, in string varName, ScriptAny value)
{
    VisitResult vr;
    bool ok = false;
    string msg = "";
    if(qual == "var")
    {
        ok = c.getGlobalContext.declareVariableOrConst(varName, value, false);
        if(!ok)
            msg = "Unable to redeclare global " ~ varName;
    }
    else if(qual == "let")
    {
        ok = c.declareVariableOrConst(varName, value, false);
        if(!ok)
            msg = "Unable to redeclare local variable " ~ varName;
    }
    else if(qual == "const")
    {
        ok = c.declareVariableOrConst(varName, value, true);
        if(!ok)
            msg = "Unable to redeclare local const " ~ varName;
    }
    if(!ok)
        vr.exception = new ScriptRuntimeException(msg);
    return vr;
}

VisitResult convertExpressionsToArgs(Context c, Node[] expressions, out ScriptAny[] args)
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

VisitResult callFunction(Context context, ScriptFunction fn, ScriptAny thisObj, 
                         ScriptAny[] args, bool returnThis = false)
{
    import mildew.types : NativeFunctionError;
    import std.algorithm: min;

    VisitResult vr;
    if(returnThis)
    {
        if(!thisObj.isObject)
            thisObj = new ScriptObject(fn.functionName, fn["prototype"].toValue!ScriptObject, null);
    }
    if(fn.type == ScriptFunction.Type.SCRIPT_FUNCTION)
    {
		context = new Context(fn.closure, fn.functionName);
        // context = new Context(context, fn.functionName);
        // push args by name as locals
        for(size_t i=0; i < fn.argNames.length; ++i)
        {
            if(i < args.length)
                context.forceSetVarOrConst(fn.argNames[i], args[i], false);
            else // if an argument wasn't sent ensure it is defined as undefined at least
                context.forceSetVarOrConst(fn.argNames[i], ScriptAny.UNDEFINED, false);
        }
        // put all arguments in an array called arguments
        context.forceSetVarOrConst("arguments", ScriptAny(args), false);
        // set up "this"
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
                if(vr.exception !is null)
                    vr.exception.scriptTraceback ~= statement;
                vr.returnFlag = false;
                break;
            }
        }
        if(returnThis)
        {
            bool _; // @suppress(dscanner.suspicious.unmodified)
            immutable thisPtr = cast(immutable)context.lookupVariableOrConst("this", _);
            if(thisPtr != null)
                vr.result = *thisPtr;
        }
        context = context.parent;
        return vr;                           
    }
    else 
    {
        ScriptAny returnValue;
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
                vr.exception = new ScriptRuntimeException(returnValue.toString());
                break;
        }
        // finally return the result
        return vr;               
    }
}

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