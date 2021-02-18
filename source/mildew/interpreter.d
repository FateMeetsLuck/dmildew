/**
This module implements the Interpreter class, the main class used by host applications to run scripts

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
module mildew.interpreter;

import std.typecons;
import std.variant;

import mildew.compiler;
import mildew.environment;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token, Lexer;
import mildew.nodes;
import mildew.parser;
import mildew.types;
import mildew.visitors;
import mildew.vm;

/**
 * This is the main interface for the host application to interact with scripts. It can run scripts in
 * interpreted mode by walking the syntax tree (deprecated), or if given the useVM option, can run a compiler to
 * compile scripts into bytecode which is then executed by a VirtualMachine. Note that interpreted mode
 * is deprecated.
 */
class Interpreter : INodeVisitor
{
public:

    /**
     * Constructs a new Interpreter with a global environment. Note that all calls to evaluate
     * run in a new environment below the global environment. This allows keywords such as let and const
     * to not pollute the global namespace. However, scripts can use var to declare variables that
     * are global.
     * Params:
     *  useVM = whether or not compilation to bytecode and the VM should be used instead of tree walking.
     *  printVMDebugInfo = if useVM is true, this option prints very verbose data while executing bytecode.
     */
    this(bool useVM = false, bool printVMDebugInfo = true)
    {
        _globalEnvironment = new Environment(this);
        _currentEnvironment = _globalEnvironment;
        if(useVM)
        {
            _compiler = new Compiler();
            _printVMDebugInfo = printVMDebugInfo;
            _vm = new VirtualMachine(_globalEnvironment);
        }
    }

    /**
     * Initializes the Mildew standard library, such as Object, Math, and console namespaces. This
     * is optional and is not called by the constructor. For a script to use these methods such as
     * console.log this must be called first. It is also possible to only call specific
     * initialize*Library functions and/or force set globals from them to UNDEFINED.
     */
    void initializeStdlib()
    {
        import mildew.types.bindings: initializeTypesLibrary;
        import mildew.stdlib.global: initializeGlobalLibrary;
        import mildew.stdlib.console: initializeConsoleLibrary;
        import mildew.stdlib.date: initializeDateLibrary;
        import mildew.stdlib.generator: initializeGeneratorLibrary;
        import mildew.stdlib.math: initializeMathLibrary;
        import mildew.stdlib.regexp: initializeRegExpLibrary;
        import mildew.stdlib.system: initializeSystemLib;
        initializeTypesLibrary(this);
        initializeGlobalLibrary(this);
        initializeConsoleLibrary(this);
        initializeDateLibrary(this);
        initializeGeneratorLibrary(this);
        initializeMathLibrary(this);
        initializeRegExpLibrary(this);
        initializeSystemLib(this);
    }

    /**
     * Calls a script function. Can throw ScriptRuntimeException.
     */
    deprecated ScriptAny callFunction(ScriptFunction func, ScriptAny thisObj, ScriptAny[] args, bool useVM=false)
    {
        auto vr = callFn(func, thisObj, args, false, useVM);
        if(vr.exception)
            throw vr.exception;
        return vr.result;
    }

    /**
     * This is the main entry point for evaluating a script program. If the useVM option was set in the
     * constructor, bytecode compilation and execution will be used, otherwise tree walking.
     * Params:
     *  code = This is the source code of a script to be executed.
     *  printDisasm = If VM mode is set, print the disassembly of bytecode before running if true.
     * Returns:
     *  If the script has a return statement with an expression, this value will be the result of that expression
     *  otherwise it will be ScriptAny.UNDEFINED
     */
    ScriptAny evaluate(in string code, bool printDisasm=false)
    {
        if(_compiler is null)
        {
            auto lexer = Lexer(code);
            auto tokens = lexer.tokenize();
            auto parser = Parser(tokens);
            auto programBlock = parser.parseProgram();
            auto vr = programBlock.accept(this).get!VisitResult;
            if(vr.exception !is null)
                throw vr.exception;
            if(vr.returnFlag)
                return vr.result;
            return ScriptAny.UNDEFINED;
        }
        else
        {
            auto chunk = _compiler.compile(code);
            if(printDisasm)
                _vm.printChunk(chunk, true);

            return _vm.run(chunk, _printVMDebugInfo);
        }
    }

    /**
     * Evaluates a file that can be either binary bytecode or textual source code.
     * Params:
     *  pathName = the location of the code file in the file system.
     * Returns:
     *  The result of evaluating the file, undefined if no return statement.
     */
    ScriptAny evaluateFile(in string pathName, bool printDisasm=false)
    {
        import std.stdio: File, writefln;
        import mildew.util.encode: decode;

        File inputFile = File(pathName, "rb");
        auto raw = new ubyte[inputFile.size];
        raw = inputFile.rawRead(raw);
        if(raw.length > 0 && raw[0] == 0x01)
        {
            if(_vm is null)
                throw new ScriptRuntimeException("This file can only be run in VM mode");
            auto chunk = Chunk.deserialize(raw);
            if(printDisasm)
                _vm.printChunk(chunk);
            return _vm.run(chunk, _printVMDebugInfo);
        }
        else
        {
            auto source = cast(string)raw;
            return evaluate(source, printDisasm);
        }
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
        _globalEnvironment.forceSetVarOrConst(name, ScriptAny(value), isConst);
    }

    /**
     * Unsets a variable or constant in the global environment. Used by host applications to remove
     * items that were loaded by the standard library load functions. Specific functions of
     * script classes can be removed by modifying the "prototype" field of their constructor.
     */
    void forceUnsetGlobal(in string name)
    {
        _globalEnvironment.forceRemoveVarOrConst(name);
    }

    /// whether or not debug info should be printed between each VM instruction
    bool printVMDebugInfo() const 
    {
        return _printVMDebugInfo;
    }
	
    /// whether or not VM option was set when created
    bool usingVM() const 
    {
        return _vm !is null;
    }

// The next functions are internal and deprecated and only public due to D language constraints.

	/// extract a VisitResult from a LiteralNode
	deprecated Variant visitLiteralNode(LiteralNode lnode)
	{
		return Variant(VisitResult(lnode.value));
	}
	
    /// handles function literals
    deprecated Variant visitFunctionLiteralNode(FunctionLiteralNode flnode)
    {
        auto func = new ScriptFunction("<anonymous function>", flnode.argList, flnode.statements, _currentEnvironment);
        return Variant(VisitResult(ScriptAny(func)));
    }

    /// handle lambda
    deprecated Variant visitLambdaNode(LambdaNode lnode)
    {
        FunctionLiteralNode flnode;
        if(lnode.returnExpression)
        {
            flnode = new FunctionLiteralNode(lnode.argList, [
                    new ReturnStatementNode(lnode.arrowToken.position.line, lnode.returnExpression)
                ], "<lambda>", false);
        }
        else
        {
            flnode = new FunctionLiteralNode(lnode.argList, lnode.statements, "<lambda>", false);
        }
        return flnode.accept(this);
    }

    /// handle template literal nodes
    deprecated Variant visitTemplateStringNode(TemplateStringNode tsnode)
    {
        VisitResult vr;
        string result = "";
        foreach(node ; tsnode.nodes)
        {
            vr = node.accept(this).get!VisitResult;
            if(vr.exception)
                return Variant(vr);
            result ~= vr.result.toString();
        }
        return Variant(VisitResult(result));
    }

	/// return an array from an array literal node
	deprecated Variant visitArrayLiteralNode(ArrayLiteralNode alnode)
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
	deprecated Variant visitObjectLiteralNode(ObjectLiteralNode olnode)
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
        auto obj = new ScriptObject("object", null, null);
        for(size_t i = 0; i < olnode.keys.length; ++i)
        {
            obj.assignField(olnode.keys[i], vals[i]);
        }
        vr.result = obj;
        return Variant(vr);
	}
	
    /// handle class literals
	deprecated Variant visitClassLiteralNode(ClassLiteralNode clnode)
	{
		VisitResult vr;

        try 
        {
            vr.result = clnode.classDefinition.create(_currentEnvironment);
        }
        catch(ScriptRuntimeException ex)
        {
            vr.exception = ex;
        }
		        
        return Variant(vr);
	}
	
	/// processes binary operations including assignment
	deprecated Variant visitBinaryOpNode(BinaryOpNode bonode)
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
	deprecated Variant visitUnaryOpNode(UnaryOpNode uonode)
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
	deprecated Variant visitPostfixOpNode(PostfixOpNode ponode)
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
	deprecated Variant visitTerniaryOpNode(TerniaryOpNode tonode)
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
	deprecated Variant visitVarAccessNode(VarAccessNode vanode)
	{
		VisitResult vr;
        vr.accessType = VisitResult.AccessType.VAR_ACCESS;
        vr.memberOrVarToAccess = vanode.varToken.text;
        bool _; // @suppress(dscanner.suspicious.unmodified)
        immutable ptr = cast(immutable)_currentEnvironment.lookupVariableOrConst(vanode.varToken.text, _);
        if(ptr == null)
            vr.exception = new ScriptRuntimeException("Undefined variable lookup " ~ vanode.varToken.text);
        else
            vr.result = *ptr;
        return Variant(vr);
	}

    /// handles function calls
	deprecated Variant visitFunctionCallNode(FunctionCallNode fcnode)
	{
        ScriptAny thisObj;
        auto vr = fcnode.functionToCall.accept(this).get!VisitResult;

        if(cast(SuperNode)fcnode.functionToCall)
        {
            vr.result = vr.result["constructor"];
        }

        if(vr.exception !is null)
            return Variant(vr);

        // if not a new expression pull this
        if(!fcnode.returnThis)
        {
            if(vr.accessType == VisitResult.AccessType.OBJECT_ACCESS)
            {
                auto man = cast(MemberAccessNode)fcnode.functionToCall;
                if(cast(SuperNode)man.objectNode)
                    thisObj = getLocalThis();
                else
                    thisObj = vr.objectToAccess;
            }
            else if(vr.accessType == VisitResult.AccessType.ARRAY_ACCESS)
            {
                auto ain = cast(ArrayIndexNode)fcnode.functionToCall;
                if(cast(SuperNode)ain.objectNode)
                    thisObj = getLocalThis();
                else
                    thisObj = vr.objectToAccess;
            }
            else
            {
                thisObj = getLocalThis();
            }
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
	deprecated Variant visitArrayIndexNode(ArrayIndexNode ainode)
	{
        import std.utf: UTFException;

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
                auto str = asString.toString();
                if(indexAsNum >= str.length)
                    vr.result = ScriptAny.UNDEFINED;
                else
                {
                    try 
                    {
                        vr.result = ScriptAny([ str[indexAsNum] ]);
                    }
                    catch(UTFException)
                    {
                        vr.result = ScriptAny.UNDEFINED;
                    }
                }
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
	deprecated Variant visitMemberAccessNode(MemberAccessNode manode)
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
            VisitResult gvr;
            gvr = getObjectProperty(obj, memberName);
            if(gvr.exception !is null)
                return Variant(gvr);
            vr.result = gvr.result;
        }
        else
            vr.result = objVR.result.lookupField(memberName);
        return Variant(vr);
	}
	
    /// handles new expression
	deprecated Variant visitNewExpressionNode(NewExpressionNode nenode)
	{
		// fce should be a valid function call with its returnThis flag already set by the parser
        auto vr = nenode.functionCallExpression.accept(this);
        return vr; // caller will check for any exceptions.
	}

    /// this should only be directly visited when used by itself
    deprecated Variant visitSuperNode(SuperNode snode)
    {
        auto thisObj = getLocalThis;
        return Variant(VisitResult(thisObj["__super__"]));
    }
	
    /// handles var, let, and const declarations
	deprecated Variant visitVarDeclarationStatementNode(VarDeclarationStatementNode vdsnode)
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
	deprecated Variant visitBlockStatementNode(BlockStatementNode bsnode)
	{
        Environment oldEnvironment = _currentEnvironment; // @suppress(dscanner.suspicious.unmodified)
		_currentEnvironment = new Environment(_currentEnvironment, "<scope>");
        auto result = VisitResult(ScriptAny.UNDEFINED);
        foreach(statement ; bsnode.statementNodes)
        {
            result = statement.accept(this).get!VisitResult;
            if(result.returnFlag || result.breakFlag || result.continueFlag || result.exception !is null)
            {
                if(result.exception)
                    result.exception.scriptTraceback ~= tuple(statement.line, statement.toString());
                break;
            }
        }   
        _currentEnvironment = oldEnvironment;
        return Variant(result);
	}
	
    /// handles if statements
	deprecated Variant visitIfStatementNode(IfStatementNode isnode)
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
	deprecated Variant visitSwitchStatementNode(SwitchStatementNode ssnode)
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
	deprecated Variant visitWhileStatementNode(WhileStatementNode wsnode)
	{
		if(wsnode.label != "")
            _currentEnvironment.insertLabel(wsnode.label);
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
                    if(_currentEnvironment.labelExists(vr.labelName))
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
                    if(_currentEnvironment.labelExists(vr.labelName))
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
            _currentEnvironment.removeLabelFromCurrent(wsnode.label);
        return Variant(vr);
	}
	
    /// handles do-while statement
	deprecated Variant visitDoWhileStatementNode(DoWhileStatementNode dwsnode)
	{
		auto vr = VisitResult(ScriptAny.UNDEFINED);
        if(dwsnode.label != "")
            _currentEnvironment.insertLabel(dwsnode.label);
        do 
        {
            vr = dwsnode.bodyNode.accept(this).get!VisitResult;
            if(vr.breakFlag)
            {
                if(vr.labelName == "")
                    vr.breakFlag = false;
                else
                {
                    if(_currentEnvironment.labelExists(vr.labelName))
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
                    if(_currentEnvironment.labelExists(vr.labelName))
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
            _currentEnvironment.removeLabelFromCurrent(dwsnode.label);
        return Variant(vr);
	}
	
    /// handles for(;;) statements
	deprecated Variant visitForStatementNode(ForStatementNode fsnode)
	{
        Environment oldEnvironment = _currentEnvironment; // @suppress(dscanner.suspicious.unmodified)
		_currentEnvironment = new Environment(_currentEnvironment, "<outer_for_loop>");
        if(fsnode.label != "")
            _currentEnvironment.insertLabel(fsnode.label);
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
                        if(_currentEnvironment.labelExists(vr.labelName))
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
                        if(_currentEnvironment.labelExists(vr.labelName))
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
            _currentEnvironment.removeLabelFromCurrent(fsnode.label);
        _currentEnvironment = oldEnvironment;
        return Variant(vr);
	}
	
    /// handles for-of (and for-in) loops. TODO rewrite with iterators and implement string
	deprecated Variant visitForOfStatementNode(ForOfStatementNode fosnode)
	{
		auto vr = fosnode.objectToIterateNode.accept(this).get!VisitResult;
        // make sure this is iterable
        if(vr.exception !is null)
            return Variant(vr);

        if(fosnode.label != "")
            _currentEnvironment.insertLabel(fosnode.label);

        // FOR NOW no distinguish "of" and "in"
        if(vr.result.type == ScriptAny.Type.ARRAY)
        {
            auto arr = vr.result.toValue!(ScriptAny[]);
            for(size_t i = 0; i < arr.length; ++i)
            {
                // TODO optimize this to reassign variables instead of creating new environments each iteration
                auto oldEnvironment = _currentEnvironment; // @suppress(dscanner.suspicious.unmodified)
                _currentEnvironment = new Environment(_currentEnvironment, "<for_of_loop>");
                // if one var access node, then value, otherwise index then value
                if(fosnode.varAccessNodes.length == 1)
                {
                    _currentEnvironment.declareVariableOrConst(fosnode.varAccessNodes[0].varToken.text,
                        arr[i], fosnode.qualifierToken.text == "const"? true: false);
                }
                else 
                {
                    _currentEnvironment.declareVariableOrConst(fosnode.varAccessNodes[0].varToken.text,
                        ScriptAny(i), fosnode.qualifierToken.text == "const"? true: false);
                    _currentEnvironment.declareVariableOrConst(fosnode.varAccessNodes[1].varToken.text,
                        arr[i], fosnode.qualifierToken.text == "const"? true: false);
                }
                vr = fosnode.bodyNode.accept(this).get!VisitResult;
                _currentEnvironment = oldEnvironment;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(_currentEnvironment.labelExists(vr.labelName))
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
                        if(_currentEnvironment.labelExists(vr.labelName))
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
                auto oldEnvironment = _currentEnvironment; // @suppress(dscanner.suspicious.unmodified)
                _currentEnvironment = new Environment(_currentEnvironment, "<for_of_loop>");
                _currentEnvironment.declareVariableOrConst(fosnode.varAccessNodes[0].varToken.text,
                    ScriptAny(key), fosnode.qualifierToken.text == "const" ? true: false);
                if(fosnode.varAccessNodes.length > 1)
                    _currentEnvironment.declareVariableOrConst(fosnode.varAccessNodes[1].varToken.text,
                        ScriptAny(val), fosnode.qualifierToken.text == "const" ? true: false);
                vr = fosnode.bodyNode.accept(this).get!VisitResult;              
                _currentEnvironment = oldEnvironment;
                if(vr.breakFlag)
                {
                    if(vr.labelName == "")
                        vr.breakFlag = false;
                    else
                    {
                        if(_currentEnvironment.labelExists(vr.labelName))
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
                        if(_currentEnvironment.labelExists(vr.labelName))
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
            _currentEnvironment.removeLabelFromCurrent(fosnode.label);

        return Variant(vr);
	}
	
    /// handle break statements
	deprecated Variant visitBreakStatementNode(BreakStatementNode bsnode)
	{
		auto vr = VisitResult(ScriptAny.UNDEFINED);
        vr.breakFlag = true;
        vr.labelName = bsnode.label;
        return Variant(vr);
	}
	
    /// handle continue statements
	deprecated Variant visitContinueStatementNode(ContinueStatementNode csnode)
	{
        auto vr = VisitResult(ScriptAny.UNDEFINED);
        vr.continueFlag = true;
        vr.labelName = csnode.label;
        return Variant(vr);
	}
	
    /// handles return statements
	deprecated Variant visitReturnStatementNode(ReturnStatementNode rsnode)
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
	deprecated Variant visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode fdsnode)
	{
		auto func = new ScriptFunction(fdsnode.name, fdsnode.argNames, fdsnode.statementNodes, _currentEnvironment);
        immutable okToDeclare = _currentEnvironment.declareVariableOrConst(fdsnode.name, ScriptAny(func), false);
        VisitResult vr = VisitResult(ScriptAny.UNDEFINED);
        if(!okToDeclare)
        {
            vr.exception = new ScriptRuntimeException("Cannot redeclare variable or const " ~ fdsnode.name 
                ~ " with a function declaration");
        }
        return Variant(vr);
	}
	
    /// handles throw statements
	deprecated Variant visitThrowStatementNode(ThrowStatementNode tsnode)
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
	deprecated Variant visitTryCatchBlockStatementNode(TryCatchBlockStatementNode tcbsnode)
	{
		auto vr = tcbsnode.tryBlockNode.accept(this).get!VisitResult;
        // if there was an exception we need to start a new environment and set it as a local variable
        if(vr.exception !is null && tcbsnode.catchBlockNode !is null)
        {
            auto oldEnvironment = _currentEnvironment; // @suppress(dscanner.suspicious.unmodified)
            _currentEnvironment = new Environment(_currentEnvironment, "<catch>");
            if(vr.exception.thrownValue != ScriptAny.UNDEFINED)
                _currentEnvironment.forceSetVarOrConst(tcbsnode.exceptionName, vr.exception.thrownValue, false);
            else 
                _currentEnvironment.forceSetVarOrConst(tcbsnode.exceptionName, ScriptAny(vr.exception.message), false);
            vr.exception = null;
            // if another exception is thrown in the catch block, it will propagate through this return value
            vr = tcbsnode.catchBlockNode.accept(this).get!VisitResult;
            _currentEnvironment = oldEnvironment;
        }
        if(tcbsnode.finallyBlockNode)
        {
            auto finVR = tcbsnode.finallyBlockNode.accept(this).get!VisitResult;
            if(finVR.exception)
                return Variant(finVR);
        }
        return Variant(vr);
	}
	
    /// handle delete statement
	deprecated Variant visitDeleteStatementNode(DeleteStatementNode dsnode)
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
	deprecated Variant visitClassDeclarationStatementNode(ClassDeclarationStatementNode cdsnode)
	{
		VisitResult vr;
        // generate class
        try 
        {
            vr.result = cdsnode.classDefinition.create(_currentEnvironment);
        }
        catch (ScriptRuntimeException ex)
        {
            vr.exception = ex;
            return Variant(vr);
        }
        auto ctor = vr.result;
        // first try to assign the constructor as a local function
        immutable ok = _currentEnvironment.declareVariableOrConst(cdsnode.classDefinition.className, 
                ctor, false);
        if(!ok)
        {
            vr.exception = new ScriptRuntimeException("Class declaration " ~ cdsnode.classDefinition.className 
                ~ " may not overwrite local variable or const");
            return Variant(vr);
        }
		
        return Variant(VisitResult(ScriptAny.UNDEFINED)); // everything was ok
	}
	
    /// handle expression statements
	deprecated Variant visitExpressionStatementNode(ExpressionStatementNode esnode)
	{
		VisitResult vr;
        if(esnode.expressionNode !is null)
            vr = esnode.expressionNode.accept(this).get!VisitResult;
        vr.result = ScriptAny.UNDEFINED; // they should never return a result
        return Variant(vr); // caller will handle any exception
	}

    /// Virtual machine property, may be null
    VirtualMachine vm() { return _vm; }
	
package:
	/// holds information from visiting nodes TODO redesign this as a union
	deprecated struct VisitResult
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

    deprecated VisitResult callFn(ScriptFunction func, ScriptAny thisObj, ScriptAny[] args, 
                       bool returnThis = false, bool useVM = false)
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
			auto prevEnvironment = _currentEnvironment; // @suppress(dscanner.suspicious.unmodified)
			_currentEnvironment = new Environment(func.closure, func.functionName);
			// set args as locals
			for(size_t i = 0; i < func.argNames.length; ++i)
			{
				if(i < args.length)
					_currentEnvironment.forceSetVarOrConst(func.argNames[i], args[i], false);
				else
					_currentEnvironment.forceSetVarOrConst(func.argNames[i], ScriptAny.UNDEFINED, false);
			}
			// put all arguments inside "arguments" local
			_currentEnvironment.forceSetVarOrConst("arguments", ScriptAny(args), false);
			// set up "this" local
			_currentEnvironment.forceSetVarOrConst("this", thisObj, true);
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
						vr.exception.scriptTraceback ~= tuple(statement.line, statement.toString());
					vr.returnFlag = false;
					break;
				}
			}
			if(returnThis)
			{
				bool _; // @suppress(dscanner.suspicious.unmodified)
				immutable thisPtr = cast(immutable)_currentEnvironment.lookupVariableOrConst("this", _);
				if(thisPtr != null)
					vr.result = *thisPtr;
			}
			_currentEnvironment = prevEnvironment;
			return vr;
		}
		else 
		{
			ScriptAny returnValue;
			auto nfe = NativeFunctionError.NO_ERROR;
			if(func.type == ScriptFunction.Type.NATIVE_FUNCTION)
			{
				auto nativefn = func.nativeFunction;
				returnValue = nativefn(_currentEnvironment, &thisObj, args, nfe);
			}
			else
			{
				auto nativedg = func.nativeDelegate;
				returnValue = nativedg(_currentEnvironment, &thisObj, args, nfe);
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

	deprecated VisitResult convertExpressionsToArgs(ExpressionNode[] exprs, out ScriptAny[] args)
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

    deprecated ScriptAny getLocalThis()
    {
        bool _; // @suppress(dscanner.suspicious.unmodified)
        if(!_currentEnvironment.variableOrConstExists("this"))
            return ScriptAny.UNDEFINED;
        auto thisObj = *(_currentEnvironment.lookupVariableOrConst("this", _));
        return thisObj;
    }

	deprecated VisitResult getObjectProperty(ScriptObject obj, in string propName)
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

	deprecated VisitResult handleArrayReassignment(Token opToken, ScriptAny arr, size_t index, ScriptAny value)
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

	deprecated VisitResult handleObjectReassignment(Token opToken, ScriptAny objToAccess, in string index, ScriptAny value)
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

	deprecated VisitResult handleVarDeclaration(in string qual, in string varName, ScriptAny value)
	{
		VisitResult vr;
		bool ok = false;
		string msg = "";
		if(qual == "var")
		{
			ok = _globalEnvironment.declareVariableOrConst(varName, value, false);
			if(!ok)
				msg = "Unable to redeclare global " ~ varName;
		}
		else if(qual == "let")
		{
			ok = _currentEnvironment.declareVariableOrConst(varName, value, false);
			if(!ok)
				msg = "Unable to redeclare local variable " ~ varName;
		}
		else if(qual == "const")
		{
			ok = _currentEnvironment.declareVariableOrConst(varName, value, true);
			if(!ok)
				msg = "Unable to redeclare local const " ~ varName;
		}
		if(!ok)
			vr.exception = new ScriptRuntimeException(msg);
		return vr;
	}

	deprecated VisitResult handleVarReassignment(Token opToken, in string varName, ScriptAny value)
	{
		bool isConst; // @suppress(dscanner.suspicious.unmodified)
		auto ptr = _currentEnvironment.lookupVariableOrConst(varName, isConst);
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

	deprecated VisitResult setObjectProperty(ScriptObject obj, string propName, ScriptAny value)
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

    Compiler _compiler;
    bool _printVMDebugInfo;
    VirtualMachine _vm;
    Environment _globalEnvironment;
    Environment _currentEnvironment;
}

