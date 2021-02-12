/**
 * This module implements the compiler
 */
module mildew.compiler;

debug import std.stdio;
import std.typecons;
import std.variant;

import mildew.exceptions;
import mildew.lexer;
import mildew.parser;
import mildew.nodes;
import mildew.types;
import mildew.util.encode;
import mildew.util.stack;
import mildew.visitors;
import mildew.vm.chunk;
import mildew.vm.consttable;
import mildew.vm.debuginfo;
import mildew.vm.virtualmachine;

private enum BREAKLOOP_CODE = uint.max;
private enum BREAKSWITCH_CODE = uint.max - 1;
private enum CONTINUE_CODE = uint.max - 2;

/**
 * Implements a bytecode compiler that can be used by mildew.vm.virtualmachine. This class is not thread safe and each thread
 * must use its own Compiler instance. Only one chunk can be compiled at a time.
 */
class Compiler : INodeVisitor
{
public:

    /// thrown when a feature is missing
    class UnimplementedException : Exception
    {
        /// constructor
        this(string msg, string file=__FILE__, size_t line = __LINE__)
        {
            super(msg, file, line);
        }
    }

    /// compile code into chunk usable by vm
    Chunk compile(string source)
    {
        import std.string: splitLines;
        _currentSource = source;
        _chunk = new Chunk();
        _compDataStack.push(CompilationData.init);
        auto lexer = Lexer(source);
        auto parser = Parser(lexer.tokenize());
        _debugInfoStack.push(new DebugInfo(source));
        // for now just expressions
        auto block = parser.parseProgram();
        block.accept(this);
        destroy(block);
        Chunk send = _chunk;
        _chunk.debugMap[_chunk.bytecode.idup] = _debugInfoStack.pop();
        _chunk = null; // ensure node functions cannot be used by outsiders at all
        _compDataStack.pop();
        _currentSource = null;
        return send;
    }

// The visitNode methods are not intended for public use but are required to be public by D language constraints

    /// handle literal value node (easiest)
	Variant visitLiteralNode(LiteralNode lnode)
    {
        // want booleans to be booleans not 1
        if(lnode.value.type == ScriptAny.Type.BOOLEAN)
        {
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(lnode.value.toValue!bool);
            return Variant(null);
        }

        if(lnode.value == ScriptAny(0))
            _chunk.bytecode ~= OpCode.CONST_0;
        else if(lnode.value == ScriptAny(1))
            _chunk.bytecode ~= OpCode.CONST_1;
        else
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(lnode.value);
        return Variant(null);
    }

    /// handle function literals. The VM should create new functions with the appropriate context
    ///  when a function is loaded from the const table
    Variant visitFunctionLiteralNode(FunctionLiteralNode flnode)
    {
        auto oldChunk = _chunk.bytecode; // @suppress(dscanner.suspicious.unmodified)
        _compDataStack.push(CompilationData.init);
        _stackVariables.push(VarTable.init);
        _debugInfoStack.push(new DebugInfo(_currentSource, flnode.optionalName));
        ++_funcDepth;
        _chunk.bytecode = [];
        foreach(stmt ; flnode.statements)
            stmt.accept(this);
        // add a return undefined statement in case missing one
        _chunk.bytecode ~= OpCode.STACK_1;
        _chunk.bytecode ~= OpCode.RETURN;
        // create function
        ScriptAny func;
        if(!flnode.isClass)
            func = new ScriptFunction(
                flnode.optionalName == "" ? "<anonymous function>" : flnode.optionalName, 
                flnode.argList, _chunk.bytecode, false);
        else
            func = new ScriptFunction(
                flnode.optionalName == "" ? "<anonymous class>" : flnode.optionalName,
                flnode.argList, _chunk.bytecode, true);
        _chunk.debugMap[_chunk.bytecode.idup] = _debugInfoStack.pop();
        _chunk.bytecode = oldChunk;
        _stackVariables.pop;
        _compDataStack.pop();
        --_funcDepth;
        _chunk.bytecode ~= OpCode.CONST ~ encodeConst(func);
        return Variant(null);
    }

    /// handles template strings
    Variant visitTemplateStringNode(TemplateStringNode tsnode)
    {
        foreach(node ; tsnode.nodes)
        {
            node.accept(this);
        }
        _chunk.bytecode ~= OpCode.CONCAT ~ encode!uint(cast(uint)tsnode.nodes.length);
        return Variant(null);
    }

    /// handle array literals
	Variant visitArrayLiteralNode(ArrayLiteralNode alnode)
    {
        foreach(node ; alnode.valueNodes)
        {
            node.accept(this);
        }
        _chunk.bytecode ~= OpCode.ARRAY ~ encode!uint(cast(uint)alnode.valueNodes.length);
        return Variant(null);
    }

    /// handle object literal nodes
	Variant visitObjectLiteralNode(ObjectLiteralNode olnode)
    {
        assert(olnode.keys.length == olnode.valueNodes.length);
        for(size_t i = 0; i < olnode.keys.length; ++i)
        {
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(olnode.keys[i]);
            olnode.valueNodes[i].accept(this);            
        }
        _chunk.bytecode ~= OpCode.OBJECT ~ encode(cast(uint)olnode.keys.length);
        return Variant(null);
    }

    /// Class literals. Parser is supposed to make sure string-function pairs match up
	Variant visitClassLiteralNode(ClassLiteralNode clnode)
    {
        // first make sure the data will fit in a 5 byte instruction
        if(clnode.classDefinition.methods.length > ubyte.max
        || clnode.classDefinition.getMethods.length > ubyte.max 
        || clnode.classDefinition.setMethods.length > ubyte.max
        || clnode.classDefinition.staticMethods.length > ubyte.max)
        {
            throw new ScriptCompileException("Class attributes exceed 255", clnode.classToken);
        }

        if(clnode.classDefinition.baseClass)
            _baseClassStack ~= clnode.classDefinition.baseClass;

        // method names then their functions
        immutable ubyte numMethods = cast(ubyte)clnode.classDefinition.methods.length;
        foreach(methodName ; clnode.classDefinition.methodNames)
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(methodName);
        foreach(methodNode ; clnode.classDefinition.methods)
            methodNode.accept(this);
        
        // getter names then their functions
        immutable ubyte numGetters = cast(ubyte)clnode.classDefinition.getMethods.length;
        foreach(getName ; clnode.classDefinition.getMethodNames)
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(getName);
        foreach(getNode ; clnode.classDefinition.getMethods)
            getNode.accept(this);
        
        // setter names then their functions
        immutable ubyte numSetters = cast(ubyte)clnode.classDefinition.setMethods.length;
        foreach(setName ; clnode.classDefinition.setMethodNames)
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(setName);
        foreach(setNode ; clnode.classDefinition.setMethods)
            setNode.accept(this);
        
        // static names then their functions
        immutable ubyte numStatics = cast(ubyte)clnode.classDefinition.staticMethods.length;
        foreach(staticName ; clnode.classDefinition.staticMethodNames)
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(staticName);
        foreach(staticNode ; clnode.classDefinition.staticMethods)
            staticNode.accept(this);
        
        // constructor (parse guarantees it exists)
        clnode.classDefinition.constructor.accept(this);
        // then finally base class
        if(clnode.classDefinition.baseClass)
            clnode.classDefinition.baseClass.accept(this);
        else
            _chunk.bytecode ~= OpCode.STACK_1;

        _chunk.bytecode ~= OpCode.CLASS ~ cast(ubyte[])([numMethods, numGetters, numSetters, numStatics]);

        if(clnode.classDefinition.baseClass)
            _baseClassStack = _baseClassStack[0..$-1];

        return Variant(null);
    }

    /// handles binary operations
	Variant visitBinaryOpNode(BinaryOpNode bonode)
    {
        if(bonode.opToken.isAssignmentOperator)
        {
            auto remade = reduceAssignment(bonode);
            handleAssignment(remade.leftNode, remade.opToken, remade.rightNode);
            return Variant(null);
        }
        // push operands
        bonode.leftNode.accept(this);
        bonode.rightNode.accept(this);
        switch(bonode.opToken.type)
        {
        case Token.Type.POW:
            _chunk.bytecode ~= OpCode.POW;
            break;
        case Token.Type.STAR:
            _chunk.bytecode ~= OpCode.MUL;
            break;
        case Token.Type.FSLASH:
            _chunk.bytecode ~= OpCode.DIV;
            break;
        case Token.Type.PERCENT:
            _chunk.bytecode ~= OpCode.MOD;
            break;
        case Token.Type.PLUS:
            _chunk.bytecode ~= OpCode.ADD;
            break;
        case Token.Type.DASH:
            _chunk.bytecode ~= OpCode.SUB;
            break;
        case Token.Type.BIT_RSHIFT:
            _chunk.bytecode ~= OpCode.BITRSH;
            break;
        case Token.Type.BIT_URSHIFT:
            _chunk.bytecode ~= OpCode.BITURSH;
            break;
        case Token.Type.BIT_LSHIFT:
            _chunk.bytecode ~= OpCode.BITLSH;
            break;
        case Token.Type.LT:
            _chunk.bytecode ~= OpCode.LT;
            break;
        case Token.Type.LE:
            _chunk.bytecode ~= OpCode.LE;
            break;
        case Token.Type.GT:
            _chunk.bytecode ~= OpCode.GT;
            break;
        case Token.Type.GE:
            _chunk.bytecode ~= OpCode.GE;
            break;
        case Token.Type.EQUALS:
            _chunk.bytecode ~= OpCode.EQUALS;
            break;
        case Token.Type.NEQUALS:
            _chunk.bytecode ~= OpCode.NEQUALS;
            break;
        case Token.Type.STRICT_EQUALS:
            _chunk.bytecode ~= OpCode.STREQUALS;
            break;
        case Token.Type.STRICT_NEQUALS: // TODO add yet another OpCode as an optimization
            _chunk.bytecode ~= OpCode.STREQUALS;
            _chunk.bytecode ~= OpCode.NOT;
            break;
        case Token.Type.BIT_AND:
            _chunk.bytecode ~= OpCode.BITAND;
            break;
        case Token.Type.BIT_OR:
            _chunk.bytecode ~= OpCode.BITOR;
            break;
        case Token.Type.BIT_XOR:
            _chunk.bytecode ~= OpCode.BITXOR;
            break;
        case Token.Type.AND:
            _chunk.bytecode ~= OpCode.AND;
            break;
        case Token.Type.OR:
            _chunk.bytecode ~= OpCode.OR;
            break;
        default:
            if(bonode.opToken.isKeyword("instanceof"))
                _chunk.bytecode ~= OpCode.INSTANCEOF;
            else
                throw new Exception("Uncaught parser or compiler error: " ~ bonode.toString());
        }
        return Variant(null);
    }

    /// handle unary operations
	Variant visitUnaryOpNode(UnaryOpNode uonode)
    {
        switch(uonode.opToken.type)
        {
        case Token.Type.BIT_NOT:
            uonode.operandNode.accept(this);
            _chunk.bytecode ~= OpCode.BITNOT;
            break;
        case Token.Type.NOT:
            uonode.operandNode.accept(this);
            _chunk.bytecode ~= OpCode.NOT;
            break;
        case Token.Type.DASH:
            uonode.operandNode.accept(this);
            _chunk.bytecode ~= OpCode.NEGATE;
            break;
        case Token.Type.PLUS:
            uonode.operandNode.accept(this);
            break;
        case Token.Type.INC: {
            if(!nodeIsAssignable(uonode.operandNode))
                throw new ScriptCompileException("Invalid operand for prefix operation", uonode.opToken);
            auto assignmentNode = reduceAssignment(new BinaryOpNode(Token.createFakeToken(Token.Type.PLUS_ASSIGN,""), 
                    uonode.operandNode, 
                    new LiteralNode(Token.createFakeToken(Token.Type.INTEGER, "1"), ScriptAny(1)))
            );
            handleAssignment(assignmentNode.leftNode, assignmentNode.opToken, assignmentNode.rightNode); 
            break;        
        }
        case Token.Type.DEC:
            if(!nodeIsAssignable(uonode.operandNode))
                throw new ScriptCompileException("Invalid operand for prefix operation", uonode.opToken);
            auto assignmentNode = reduceAssignment(new BinaryOpNode(Token.createFakeToken(Token.Type.DASH_ASSIGN,""), 
                    uonode.operandNode, 
                    new LiteralNode(Token.createFakeToken(Token.Type.INTEGER, "1"), ScriptAny(1)))
            );
            handleAssignment(assignmentNode.leftNode, assignmentNode.opToken, assignmentNode.rightNode);
            break;
        default:
            uonode.operandNode.accept(this);
            if(uonode.opToken.isKeyword("typeof"))
                _chunk.bytecode ~= OpCode.TYPEOF;
            else
                throw new Exception("Uncaught parser error: " ~ uonode.toString());
        }
        return Variant(null);
    }

    /// Handle x++ and x--
	Variant visitPostfixOpNode(PostfixOpNode ponode)
    {
        if(!nodeIsAssignable(ponode.operandNode))
            throw new ScriptCompileException("Invalid operand for postfix operator", ponode.opToken);
        immutable incOrDec = ponode.opToken.type == Token.Type.INC ? 1 : -1;
        // first push the original value
        ponode.operandNode.accept(this);
        // generate an assignment
        auto assignmentNode = reduceAssignment(new BinaryOpNode(
            Token.createFakeToken(Token.Type.PLUS_ASSIGN, ""),
            ponode.operandNode,
            new LiteralNode(Token.createFakeToken(Token.Type.IDENTIFIER, "?"), ScriptAny(incOrDec))
        ));
        // process the assignment
        handleAssignment(assignmentNode.leftNode, assignmentNode.opToken, assignmentNode.rightNode);
        // pop the value of the assignment, leaving original value on stack
        _chunk.bytecode ~= OpCode.POP;
        return Variant(null);
    }

    /// handle :? operator
	Variant visitTerniaryOpNode(TerniaryOpNode tonode)
    {
        tonode.conditionNode.accept(this);
        tonode.onTrueNode.accept(this);
        tonode.onFalseNode.accept(this);
        _chunk.bytecode ~= OpCode.TERN;
        return Variant(null);
    }

    /// These should not be directly visited for assignment
	Variant visitVarAccessNode(VarAccessNode vanode)
    {
        if(varExists(vanode.varToken.text))
        {
            auto varMeta = lookupVar(vanode.varToken.text);
            if(varMeta.funcDepth == _funcDepth && varMeta.stackLocation != -1)
            {
                _chunk.bytecode ~= OpCode.PUSH ~ encode!int(varMeta.stackLocation);
                return Variant(null);
            }
        }
        _chunk.bytecode ~= OpCode.GETVAR ~ encodeConst(vanode.varToken.text);
        return Variant(null);
    }

    /// Handle function() calls
	Variant visitFunctionCallNode(FunctionCallNode fcnode)
    {
        // if returnThis is set this is an easy new op
        if(fcnode.returnThis)
        {
            fcnode.functionToCall.accept(this);
            foreach(argExpr ; fcnode.expressionArgs)
                argExpr.accept(this);
            _chunk.bytecode ~= OpCode.NEW ~ encode!uint(cast(uint)fcnode.expressionArgs.length);
            return Variant(null);
        }
        else
        {
            // if a member access then the "this" must be set to left hand side
            if(auto man = cast(MemberAccessNode)fcnode.functionToCall)
            {
                man.objectNode.accept(this); // first put object on stack
                _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1); // push it again
                auto van = cast(VarAccessNode)man.memberNode;
                if(van is null)
                    throw new ScriptCompileException("Invalid `.` operand", man.dotToken);
                _chunk.bytecode ~= OpCode.CONST ~ encodeConst(van.varToken.text);
                _chunk.bytecode ~= OpCode.OBJGET; // this places obj as this and the func on stack
            } // else if an array access same concept
            else if(auto ain = cast(ArrayIndexNode)fcnode.functionToCall)
            {
                ain.objectNode.accept(this);
                _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1); // push it again
                ain.indexValueNode.accept(this);
                _chunk.bytecode ~= OpCode.OBJGET; // now the array and function are on stack
            }
            else // either a variable or literal function, pull this and function
            {
                _chunk.bytecode ~= OpCode.THIS;
                fcnode.functionToCall.accept(this);
            }
            foreach(argExpr ; fcnode.expressionArgs)
                argExpr.accept(this);
            _chunk.bytecode ~= OpCode.CALL ~ encode!uint(cast(uint)fcnode.expressionArgs.length);
        }
        return Variant(null);
    }

    /// handle [] operator. This method cannot be used in assignment
	Variant visitArrayIndexNode(ArrayIndexNode ainode)
    {
        ainode.objectNode.accept(this);
        ainode.indexValueNode.accept(this);
        _chunk.bytecode ~= OpCode.OBJGET;
        return Variant(null);
    }

    /// handle . operator. This method cannot be used in assignment
	Variant visitMemberAccessNode(MemberAccessNode manode)
    {
        manode.objectNode.accept(this);
        // memberNode has to be a var access node for this to make any sense
        auto van = cast(VarAccessNode)manode.memberNode;
        if(van is null)
            throw new ScriptCompileException("Invalid right operand for `.` operator", manode.dotToken);
        _chunk.bytecode ~= OpCode.CONST ~ encodeConst(van.varToken.text);
        _chunk.bytecode ~= OpCode.OBJGET;
        return Variant(null);
    }

    /// handle new operator. visitFunctionCallExpression will handle returnThis field
	Variant visitNewExpressionNode(NewExpressionNode nenode)
    {
        nenode.functionCallExpression.accept(this);
        return Variant(null);
    }
    
    /// Handle var declaration
    Variant visitVarDeclarationStatementNode(VarDeclarationStatementNode vdsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, vdsnode.line);
        foreach(expr ; vdsnode.varAccessOrAssignmentNodes)
        {
            string varName = "";

            // is it a validated binop node
            if(auto bopnode = cast(BinaryOpNode)expr)
            {
                // if the right hand side is a function literal, we can rename it
                if(auto flnode = cast(FunctionLiteralNode)bopnode.rightNode)
                    flnode.optionalName = bopnode.leftNode.toString();
                else if(auto clsnode = cast(ClassLiteralNode)bopnode.rightNode)
                {
                    clsnode.classDefinition.constructor.optionalName = bopnode.leftNode.toString();
                    clsnode.classDefinition.className = bopnode.leftNode.toString();
                }
                auto van = cast(VarAccessNode)bopnode.leftNode;
                bopnode.rightNode.accept(this); // push value to stack
                varName = van.varToken.text;
            }
            else if(auto van = cast(VarAccessNode)expr)
            {
                _chunk.bytecode ~= OpCode.STACK_1; // push undefined
                varName = van.varToken.text;
            }
            else
                throw new Exception("Parser failure: " ~ vdsnode.toString());

            // make sure it's not overwriting a stack value
            if(vdsnode.qualifier.text != "var")
            {
                immutable lookup = lookupVar(varName);
                if(lookup.isDefined && lookup.stackLocation != -1)
                    throw new ScriptCompileException("Attempt to redeclare stack variable " ~ varName, 
                            vdsnode.qualifier);
                defineVar(varName, VarMetadata(true, -1, cast(int)_funcDepth, vdsnode.qualifier.text == "const"));
            }
            
            if(vdsnode.qualifier.text == "var")
                _chunk.bytecode ~= OpCode.DECLVAR ~ encodeConst(varName);
            else if(vdsnode.qualifier.text == "let")
                _chunk.bytecode ~= OpCode.DECLLET ~ encodeConst(varName);
            else if(vdsnode.qualifier.text == "const")
                _chunk.bytecode ~= OpCode.DECLCONST ~ encodeConst(varName);
            else
                throw new Exception("Catastrophic parser fail: " ~ vdsnode.toString());
        }
        return Variant(null);
    }

    /// handle {} braces
	Variant visitBlockStatementNode(BlockStatementNode bsnode)
    {
        import std.conv: to;
        _debugInfoStack.top.addLine(_chunk.bytecode.length, bsnode.line);
        // if there are no declarations at the top level the scope op can be omitted
        bool omitScope = true;
        foreach(stmt ; bsnode.statementNodes)
        {
            if(cast(VarDeclarationStatementNode)stmt
            || cast(FunctionDeclarationStatementNode)stmt 
            || cast(ClassDeclarationStatementNode)stmt)
            {
                omitScope = false;
                break;
            }
        }
        if(!omitScope)
        {
            ++_compDataStack.top.depthCounter;
            _stackVariables.push(VarTable.init);

            _chunk.bytecode ~= OpCode.OPENSCOPE;
        }
        foreach(stmt ; bsnode.statementNodes)
            stmt.accept(this);
        
        if(!omitScope)
        {
            _chunk.bytecode ~= OpCode.CLOSESCOPE;

            _stackVariables.pop();
            --_compDataStack.top.depthCounter;
        }
        return Variant(null);
    }

    /// emit if statements
	Variant visitIfStatementNode(IfStatementNode isnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, isnode.line);
        isnode.onTrueStatement = new BlockStatementNode(isnode.onTrueStatement.line, [isnode.onTrueStatement]);
        if(isnode.onFalseStatement)
            isnode.onFalseStatement = new BlockStatementNode(isnode.onFalseStatement.line, [isnode.onFalseStatement]);
        if(isnode.onFalseStatement)
        {
            if(cast(VarDeclarationStatementNode)isnode.onFalseStatement)
                isnode.onFalseStatement = new BlockStatementNode(isnode.onFalseStatement.line, 
                        [isnode.onFalseStatement]);
        }
        isnode.conditionNode.accept(this);
        auto length = cast(int)_chunk.bytecode.length;
        auto jmpFalseToPatch = genJmpFalse();
        isnode.onTrueStatement.accept(this);
        auto length2 = cast(int)_chunk.bytecode.length;
        auto jmpOverToPatch = genJmp();
        // *jmpFalseToPatch = cast(int)_chunk.bytecode.length - length;
        *cast(int*)(_chunk.bytecode.ptr + jmpFalseToPatch) = cast(int)_chunk.bytecode.length - length;
        length = cast(int)_chunk.bytecode.length;
        if(isnode.onFalseStatement !is null)
        {
            isnode.onFalseStatement.accept(this);
        }
        // *jmpOverToPatch = cast(int)_chunk.bytecode.length - length2;
        *cast(int*)(_chunk.bytecode.ptr + jmpOverToPatch) = cast(int)_chunk.bytecode.length - length2;

        return Variant(null);
    }

    /// Switch statements
	Variant visitSwitchStatementNode(SwitchStatementNode ssnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, ssnode.line);

        size_t[ScriptAny] unpatchedJumpTbl;
        size_t statementCounter = 0;        
        
        ++_compDataStack.top.loopOrSwitchStack;
        // generate unpatched jump array
        foreach(key, value ; ssnode.switchBody.jumpTable)
        {
            unpatchedJumpTbl[key] = genJmpTableEntry(key);
        }
        _chunk.bytecode ~= OpCode.ARRAY ~ encode!uint(cast(uint)ssnode.switchBody.jumpTable.length);
        // generate expression to test
        ssnode.expressionNode.accept(this);
        // generate switch statement
        immutable unpatchedSwitchParam = genSwitchStatement();
        bool patched = false;
        // generate each statement, patching along the way
        ++_compDataStack.top.depthCounter;
        _stackVariables.push(VarTable.init);
        _chunk.bytecode ~= OpCode.OPENSCOPE;
        foreach(stmt ; ssnode.switchBody.statementNodes)
        {
            uint patchData = cast(uint)_chunk.bytecode.length;
            foreach(k, v ; ssnode.switchBody.jumpTable)
            {
                if(v == statementCounter)
                {
                    immutable ptr = unpatchedJumpTbl[k];
                    _chunk.bytecode[ptr .. ptr + 4] = encodeConst(patchData)[0..4];
                }
            }
            // could also be default in which case we patch the switch
            if(statementCounter == ssnode.switchBody.defaultStatementID)
            {
                *cast(uint*)(_chunk.bytecode.ptr + unpatchedSwitchParam) = patchData;
                patched = true;
            }
            stmt.accept(this);
            ++statementCounter;
        }
        _chunk.bytecode ~= OpCode.CLOSESCOPE;
        _stackVariables.pop();
        --_compDataStack.top.depthCounter;
        immutable breakLocation = _chunk.bytecode.length;
        if(!patched)
        {
            *cast(uint*)(_chunk.bytecode.ptr + unpatchedSwitchParam) = cast(uint)breakLocation;
        }
        --_compDataStack.top.loopOrSwitchStack;

        patchBreaksAndContinues("", breakLocation, breakLocation, _compDataStack.top.depthCounter, 
                _compDataStack.top.loopOrSwitchStack);
        removePatches();

        return Variant(null);
    }

    /// Handle while loops
	Variant visitWhileStatementNode(WhileStatementNode wsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, wsnode.line);
        ++_compDataStack.top.loopOrSwitchStack;
        immutable length0 = _chunk.bytecode.length;
        immutable continueLocation = length0;
        wsnode.conditionNode.accept(this);
        immutable length1 = _chunk.bytecode.length;
        immutable jmpFalse = genJmpFalse();
        wsnode.bodyNode.accept(this);
        immutable length2 = _chunk.bytecode.length;
        immutable jmp = genJmp();
        immutable breakLocation = _chunk.bytecode.length;
        *cast(int*)(_chunk.bytecode.ptr + jmp) = -cast(int)(length2 - length0);
        *cast(int*)(_chunk.bytecode.ptr + jmpFalse) = cast(int)(_chunk.bytecode.length - length1);
        // patch gotos
        patchBreaksAndContinues(wsnode.label, breakLocation, continueLocation,
                _compDataStack.top.depthCounter, _compDataStack.top.loopOrSwitchStack);
        --_compDataStack.top.loopOrSwitchStack;
        removePatches();
        return Variant(null);
    }

    /// do-while loops
	Variant visitDoWhileStatementNode(DoWhileStatementNode dwsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, dwsnode.line);
        ++_compDataStack.top.loopOrSwitchStack;
        immutable continueLocation = _chunk.bytecode.length;
        // first emit the body for the guaranteed once run
        dwsnode.bodyNode.accept(this);
        immutable breakLocation = _chunk.bytecode.length;
        // patch the breaks or continues that may happen in the first run.
        patchBreaksAndContinues(dwsnode.label, breakLocation, continueLocation, _compDataStack.top.depthCounter,
                _compDataStack.top.loopOrSwitchStack);
        --_compDataStack.top.loopOrSwitchStack;
        removePatches();
        // reconstruct into while-loop and emit it
        auto wsnode = new WhileStatementNode(dwsnode.line, dwsnode.conditionNode, dwsnode.bodyNode, dwsnode.label);
        wsnode.accept(this);
        return Variant(null);
    }

    /// handle regular for loops
	Variant visitForStatementNode(ForStatementNode fsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, fsnode.line);
        ++_compDataStack.top.loopOrSwitchStack;
        // set up stack variables
        handleStackDeclaration(fsnode.varDeclarationStatement);
        immutable length0 = _chunk.bytecode.length;
        fsnode.conditionNode.accept(this);
        immutable length1 = _chunk.bytecode.length;
        immutable jmpFalse = genJmpFalse();
        fsnode.bodyNode.accept(this);
        immutable continueLocation = _chunk.bytecode.length;
        // increment is a single expression not a statement so we must add a pop
        fsnode.incrementNode.accept(this);
        _chunk.bytecode ~= OpCode.POP;
        immutable length2 = _chunk.bytecode.length;
        immutable jmp = genJmp();
        immutable breakLocation = _chunk.bytecode.length;
        handleStackCleanup(fsnode.varDeclarationStatement);
        // patch jmps
        *cast(int*)(_chunk.bytecode.ptr + jmpFalse) = cast(int)(breakLocation - length1);
        *cast(int*)(_chunk.bytecode.ptr + jmp) = -cast(int)(length2 - length0);
        patchBreaksAndContinues(fsnode.label, breakLocation, continueLocation, _compDataStack.top.depthCounter,
                _compDataStack.top.loopOrSwitchStack);
        --_compDataStack.top.loopOrSwitchStack;
        removePatches();
        return Variant(null);
    }

    /// TODO
	Variant visitForOfStatementNode(ForOfStatementNode fosnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, fosnode.line);
        string[] varNames;
        foreach(van ; fosnode.varAccessNodes)
            varNames ~= van.varToken.text;
        fosnode.objectToIterateNode.accept(this);
        _chunk.bytecode ~= OpCode.ITER;
        ++_stackVarCounter;
        _chunk.bytecode ~= OpCode.STACK_1;
        _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-2);
        _chunk.bytecode ~= OpCode.CALL ~ encode!uint(0);
        _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1);
        ++_stackVarCounter;
        _chunk.bytecode ~= OpCode.CONST ~ encodeConst("done");
        _chunk.bytecode ~= OpCode.OBJGET;
        _chunk.bytecode ~= OpCode.NOT;
        immutable loop = _chunk.bytecode.length;
        immutable jmpFalse = genJmpFalse();
        _chunk.bytecode ~= OpCode.OPENSCOPE;
        if(varNames.length == 1)
        {
            _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1);
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst("value");
            _chunk.bytecode ~= OpCode.OBJGET;
            _chunk.bytecode ~= (fosnode.qualifierToken.text == "let" ? OpCode.DECLLET : OpCode.DECLCONST)
                ~ encodeConst(varNames[0]);
        }
        else if(varNames.length == 2)
        {
            _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1);
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst("key");
            _chunk.bytecode ~= OpCode.OBJGET;
            _chunk.bytecode ~= (fosnode.qualifierToken.text == "let" ? OpCode.DECLLET : OpCode.DECLCONST)
                ~ encodeConst(varNames[0]);
            _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1);
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst("value");
            _chunk.bytecode ~= OpCode.OBJGET;
            _chunk.bytecode ~= (fosnode.qualifierToken.text == "let" ? OpCode.DECLLET : OpCode.DECLCONST)
                ~ encodeConst(varNames[1]);
        }
        ++_compDataStack.top.loopOrSwitchStack;
        fosnode.bodyNode.accept(this);
        immutable continueLocation = _chunk.bytecode.length;
        _chunk.bytecode ~= OpCode.POP;
        _chunk.bytecode ~= OpCode.STACK_1;
        _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-2);
        _chunk.bytecode ~= OpCode.CALL ~ encode!uint(0);
        _chunk.bytecode ~= OpCode.PUSH ~ encode!int(-1);
        _chunk.bytecode ~= OpCode.CONST ~ encodeConst("done");
        _chunk.bytecode ~= OpCode.OBJGET;
        _chunk.bytecode ~= OpCode.NOT;
        _chunk.bytecode ~= OpCode.CLOSESCOPE;
        immutable loopAgain = _chunk.bytecode.length;
        immutable jmp = genJmp();
        *cast(int*)(_chunk.bytecode.ptr + jmp) = -cast(int)(loopAgain - loop);
        immutable breakLocation = _chunk.bytecode.length;
        _chunk.bytecode ~= OpCode.CLOSESCOPE;
        immutable endLoop = _chunk.bytecode.length;
        _chunk.bytecode ~= OpCode.POPN ~ encode!uint(2);
        _stackVarCounter -= 2;
        *cast(int*)(_chunk.bytecode.ptr + jmpFalse) = cast(int)(endLoop - loop);
        patchBreaksAndContinues(fosnode.label, breakLocation, continueLocation, 
                _compDataStack.top.depthCounter, _compDataStack.top.loopOrSwitchStack);
        --_compDataStack.top.loopOrSwitchStack;
        removePatches();
        return Variant(null);
    }

    /// TODO
	Variant visitBreakStatementNode(BreakStatementNode bsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, bsnode.line);
        immutable patchLocation = _chunk.bytecode.length + 1;
        _chunk.bytecode ~= OpCode.GOTO ~ encode(uint.max) ~ cast(ubyte)0;
        _compDataStack.top.breaksToPatch ~= BreakOrContinueToPatch(bsnode.label, patchLocation,
                _compDataStack.top.depthCounter, _compDataStack.top.loopOrSwitchStack);
        return Variant(null);
    }

    /// TODO
	Variant visitContinueStatementNode(ContinueStatementNode csnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, csnode.line);
        immutable patchLocation = _chunk.bytecode.length + 1;
        _chunk.bytecode ~= OpCode.GOTO ~ encode(uint.max - 1) ~ cast(ubyte)0;
        _compDataStack.top.continuesToPatch ~= BreakOrContinueToPatch(csnode.label, patchLocation,
                _compDataStack.top.depthCounter, _compDataStack.top.loopOrSwitchStack);
        return Variant(null);
    }

    /// Return statements
	Variant visitReturnStatementNode(ReturnStatementNode rsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, rsnode.line);
        // TODO should handle escaping for-loop stack vars
        if(rsnode.expressionNode !is null)
            rsnode.expressionNode.accept(this);
        else
            _chunk.bytecode ~= OpCode.STACK_1;
        _chunk.bytecode ~= OpCode.RETURN;
        return Variant(null);
    }

    /// function declarations
	Variant visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode fdsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, fdsnode.line);
        // easy, reduce it to a let fname = function(){...} VarDeclarationStatement
        auto vdsn = new VarDeclarationStatementNode(
            fdsnode.line,
            Token.createFakeToken(Token.Type.KEYWORD, "let"), [
                new BinaryOpNode(
                    Token.createFakeToken(Token.Type.ASSIGN, ""),
                    new VarAccessNode(Token.createFakeToken(Token.Type.IDENTIFIER, fdsnode.name)),
                    new FunctionLiteralNode(
                        fdsnode.argNames, fdsnode.statementNodes, fdsnode.name
                    )
                )
            ]
        );
        vdsn.accept(this);
        return Variant(null);
    }

    /// Throw statement
	Variant visitThrowStatementNode(ThrowStatementNode tsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, tsnode.line);
        tsnode.expressionNode.accept(this);
        _chunk.bytecode ~= OpCode.THROW;
        return Variant(null);
    }

    /// Try catch
	Variant visitTryCatchBlockStatementNode(TryCatchBlockStatementNode tcbsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, tcbsnode.line);
        // emit try block
        immutable tryToPatch = genTry();
        tcbsnode.tryBlockNode.accept(this);
        _chunk.bytecode ~= OpCode.ENDTRY;
        immutable length0 = cast(int)_chunk.bytecode.length;
        immutable jmpToPatch = genJmp();
        *cast(uint*)(_chunk.bytecode.ptr + tryToPatch) = cast(uint)_chunk.bytecode.length;
        // emit catch block
        immutable omitScope = tcbsnode.exceptionName == ""? true: false;
        if(!omitScope)
        {
            ++_compDataStack.top.depthCounter;
            _stackVariables.push(VarTable.init);
            _chunk.bytecode ~= OpCode.OPENSCOPE;
        }
        if(tcbsnode.catchBlockNode)
        {
            _chunk.bytecode ~= OpCode.LOADEXC;
            if(!omitScope)
                _chunk.bytecode ~= OpCode.DECLLET ~ encodeConst(tcbsnode.exceptionName);
            else
                _chunk.bytecode ~= OpCode.POP;
            tcbsnode.catchBlockNode.accept(this);
        }
        if(!omitScope)
        {
            --_compDataStack.top.depthCounter;
            _stackVariables.pop();
            _chunk.bytecode ~= OpCode.CLOSESCOPE;
        }
        *cast(int*)(_chunk.bytecode.ptr + jmpToPatch) = cast(int)_chunk.bytecode.length - length0;
        // emit finally block
        if(tcbsnode.finallyBlockNode)
        {
            tcbsnode.finallyBlockNode.accept(this);
            if(tcbsnode.catchBlockNode is null)
                _chunk.bytecode ~= OpCode.RETHROW;
        }
        return Variant(null);
    }

    /// delete statement. can be used on ArrayIndexNode or MemberAccessNode
	Variant visitDeleteStatementNode(DeleteStatementNode dsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, dsnode.line);
        if(auto ain = cast(ArrayIndexNode)dsnode.memberAccessOrArrayIndexNode)
        {
            ain.objectNode.accept(this);
            ain.indexValueNode.accept(this);
        }
        else if(auto man = cast(MemberAccessNode)dsnode.memberAccessOrArrayIndexNode)
        {
            man.objectNode.accept(this);
            auto van = cast(VarAccessNode)man.memberNode;
            if(van is null)
                throw new Exception("Parser failure in delete statement");
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(van.varToken.text);
        }
        else
            throw new ScriptCompileException("Invalid operand to delete", dsnode.deleteToken);
        _chunk.bytecode ~= OpCode.DEL;
        return Variant(null);
    }

    /// Class declarations. Reduce to let leftHand = classExpression
	Variant visitClassDeclarationStatementNode(ClassDeclarationStatementNode cdsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, cdsnode.line);
        auto reduction = new VarDeclarationStatementNode(
            Token.createFakeToken(Token.Type.KEYWORD, "let"),
            [
                new BinaryOpNode(Token.createFakeToken(Token.Type.ASSIGN, "="),
                    new VarAccessNode(Token.createFakeToken(Token.Type.IDENTIFIER, cdsnode.classDefinition.className)),
                    new ClassLiteralNode(cdsnode.classToken, cdsnode.classDefinition))
            ]);
        reduction.accept(this);
        return Variant(null);
    }

    /// This type of node is only a call to a base class constructor
	Variant visitSuperCallStatementNode(SuperCallStatementNode scsnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, scsnode.line);
        _chunk.bytecode ~= OpCode.THIS;
        if(_baseClassStack.length == 0)
            throw new ScriptCompileException("Super call with no base class", scsnode.superToken);
        _baseClassStack[$-1].accept(this);
        foreach(arg ; scsnode.argExpressionNodes)
            arg.accept(this);
        _chunk.bytecode ~= OpCode.CALL ~ encode!uint(cast(uint)scsnode.argExpressionNodes.length);
        return Variant(null);
    }

    /// handle expression statements
	Variant visitExpressionStatementNode(ExpressionStatementNode esnode)
    {
        _debugInfoStack.top.addLine(_chunk.bytecode.length, esnode.line);
        if(esnode.expressionNode is null)
            return Variant(null);
        esnode.expressionNode.accept(this);
        _chunk.bytecode ~= OpCode.POP;
        return Variant(null);
    }

private:
    static const int UNPATCHED_JMP = 262_561_909;
    static const uint UNPATCHED_JMPENTRY = 3_735_890_861;
    static const uint UNPATCHED_TRY_GOTO = uint.max;

    size_t addStackVar(string name, bool isConst)
    {
        size_t id = _stackVarCounter++;
        defineVar(name, VarMetadata(true, cast(int)id, cast(int)_funcDepth, isConst));
        _stackVarNames ~= name;
        return id;
    }

    void defineVar(string name, VarMetadata vmeta)
    {
        _stackVariables.top[name] = vmeta;
    }

    ubyte[] encodeConst(T)(T value)
    {
        return encode(_chunk.constTable.addValueUint(ScriptAny(value)));
    }

    ubyte[] encodeConst(T : ScriptAny)(T value)
    {
        return encode(_chunk.constTable.addValueUint(value));
    }

    /// The return value MUST BE USED
    size_t genSwitchStatement()
    {
        immutable switchParam = _chunk.bytecode.length + 1;
        _chunk.bytecode ~= OpCode.SWITCH ~ encode!uint(UNPATCHED_JMPENTRY);
        return switchParam;
    }

    /// The return value MUST BE USED
    size_t genJmp()
    {
        _chunk.bytecode ~= OpCode.JMP ~ encode!int(UNPATCHED_JMP);
        return _chunk.bytecode.length - int.sizeof;
    }

    /// The return value MUST BE USED
    size_t genJmpFalse()
    {
        _chunk.bytecode ~= OpCode.JMPFALSE ~ encode!int(UNPATCHED_JMP);
        return _chunk.bytecode.length - int.sizeof;
    }

    /// The return value MUST BE USED
    size_t genJmpTableEntry(ScriptAny value)
    {
        _chunk.bytecode ~= OpCode.CONST ~ encodeConst(value);
        immutable constEntry = _chunk.bytecode.length + 1;
        _chunk.bytecode ~= OpCode.CONST ~ encode!uint(UNPATCHED_JMPENTRY);
        _chunk.bytecode ~= OpCode.ARRAY ~ encode!uint(2);
        return constEntry;
    }

    /// The return value MUST BE USED
    size_t genTry()
    {
        _chunk.bytecode ~= OpCode.TRY ~ encode!uint(uint.max);
        return _chunk.bytecode.length - uint.sizeof;
    }

    void handleAssignment(ExpressionNode leftExpr, Token opToken, ExpressionNode rightExpr)
    {
        // in case we are assigning to object access expressions
        if(auto classExpr = cast(ClassLiteralNode)rightExpr)
        {
            if(classExpr.classDefinition.className == ""
            || classExpr.classDefinition.className == "<anonymous class>")
                classExpr.classDefinition.constructor.optionalName = leftExpr.toString();
        }
        else if(auto funcLit = cast(FunctionLiteralNode)rightExpr)
        {
            if(funcLit.optionalName == "" || funcLit.optionalName == "<anonymous function>")
                funcLit.optionalName = leftExpr.toString();
        }
        if(auto van = cast(VarAccessNode)leftExpr)
        {
            rightExpr.accept(this);
            if(varExists(van.varToken.text))
            {
                bool isConst; // @suppress(dscanner.suspicious.unmodified)
                immutable varMeta = lookupVar(van.varToken.text);
                if(varMeta.stackLocation != -1)
                {
                    if(varMeta.isConst)
                        throw new ScriptCompileException("Cannot reassign stack const " ~ van.varToken.text, 
                                van.varToken);
                    _chunk.bytecode ~= OpCode.SET ~ encode!uint(cast(uint)varMeta.stackLocation);
                    return;
                }
            }
            _chunk.bytecode ~= OpCode.SETVAR ~ encodeConst(van.varToken.text);
        }
        else if(auto man = cast(MemberAccessNode)leftExpr)
        {
            man.objectNode.accept(this);
            auto van = cast(VarAccessNode)man.memberNode;
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(van.varToken.text);
            rightExpr.accept(this);
            _chunk.bytecode ~= OpCode.OBJSET;
        }
        else if(auto ain = cast(ArrayIndexNode)leftExpr)
        {
            ain.objectNode.accept(this);
            ain.indexValueNode.accept(this);
            rightExpr.accept(this);
            _chunk.bytecode ~= OpCode.OBJSET;
        }
        else
            throw new Exception("Another parser fail");
    }

    void handleStackCleanup(VarDeclarationStatementNode vdsnode)
    {
        if(vdsnode is null)
            return;
        uint numToPop = 0;
        foreach(node ; vdsnode.varAccessOrAssignmentNodes)
        {
            if(auto bopnode = cast(BinaryOpNode)node)
            {
                auto van = cast(VarAccessNode)bopnode.leftNode;
                removeStackVar(van.varToken.text);
                ++numToPop;
            }
            else if(auto van = cast(VarAccessNode)node)
            {
                removeStackVar(van.varToken.text);
                ++numToPop;
            }
        }
        if(numToPop == 1)
            _chunk.bytecode ~= OpCode.POP;
        else
            _chunk.bytecode ~= OpCode.POPN ~ encode!uint(numToPop);
        _stackVarCounter -= numToPop;
        _counterStack.pop();
        _stackVariables.pop();
        _stackVarNames = _stackVarNames[0 .. $-numToPop];
    }

    void handleStackDeclaration(VarDeclarationStatementNode vdsnode)
    {
        if(vdsnode is null)
            return;
        _stackVariables.push(VarTable.init);
        foreach(node ; vdsnode.varAccessOrAssignmentNodes)
        {
            if(auto bopnode = cast(BinaryOpNode)node)
            {
                if(bopnode.opToken.type != Token.Type.ASSIGN)
                    throw new ScriptCompileException("Invalid declaration in for loop", bopnode.opToken);
                auto van = cast(VarAccessNode)bopnode.leftNode;
                auto id = addStackVar(van.varToken.text, vdsnode.qualifier.text == "const");
                _chunk.bytecode ~= OpCode.STACK_1;
                bopnode.rightNode.accept(this);
                _chunk.bytecode ~= OpCode.SET ~ encode!int(cast(int)id);
                _chunk.bytecode ~= OpCode.POP;
            }
            else if(auto van = cast(VarAccessNode)node)
            {
                addStackVar(van.varToken.text, vdsnode.qualifier.text == "const");
                _chunk.bytecode ~= OpCode.STACK_1;
            }
            else
                throw new Exception("Not sure what happened here");
        }
        _counterStack.push(_stackVarCounter);
    }

    VarMetadata lookupVar(string name)
    {
        for(auto i = 1; i <= _stackVariables.array.length; ++i)
        {
            if(name in _stackVariables.array[$-i])
                return _stackVariables.array[$-i][name];
        }
        return VarMetadata(false, -1, 0, false);
    }

    bool nodeIsAssignable(ExpressionNode node)
    {
        if(cast(VarAccessNode)node)
            return true;
        if(cast(ArrayIndexNode)node)
            return true;
        if(cast(MemberAccessNode)node)
            return true;
        return false;
    }

    void patchBreaksAndContinues(string label, size_t breakGoto, size_t continueGoto, int depthCounter, int loopLevel)
    {
        for(size_t i = 0; i < _compDataStack.top.breaksToPatch.length; ++i)
        {
            BreakOrContinueToPatch* brk = &_compDataStack.top.breaksToPatch[i];
            if(!brk.patched)
            {
                if((brk.labelName == label) || (brk.labelName == "" && brk.loopLevel == loopLevel))
                {
                    *cast(uint*)(_chunk.bytecode.ptr + brk.gotoPatchParam) = cast(uint)breakGoto;
                    _chunk.bytecode[brk.gotoPatchParam + uint.sizeof] = cast(ubyte)(brk.depth - depthCounter);
                    brk.patched = true;
                }
            }
        }

        for(size_t i = 0; i < _compDataStack.top.continuesToPatch.length; ++i)
        {
            BreakOrContinueToPatch* cont = &_compDataStack.top.continuesToPatch[i];
            if(!cont.patched)
            {
                if((cont.labelName == label) || (cont.labelName == "" && cont.loopLevel == loopLevel))
                {
                    *cast(uint*)(_chunk.bytecode.ptr + cont.gotoPatchParam) = cast(uint)continueGoto;
                    _chunk.bytecode[cont.gotoPatchParam + uint.sizeof] = cast(ubyte)(cont.depth - depthCounter);
                    cont.patched = true;
                }
            }
        }

    }

    BinaryOpNode reduceAssignment(BinaryOpNode original)
    {
        switch(original.opToken.type)
        {
        case Token.Type.ASSIGN:
            return original; // nothing to do
        case Token.Type.PLUS_ASSIGN:
            return new BinaryOpNode(Token.createFakeToken(Token.Type.ASSIGN, ""), 
                    original.leftNode, 
                    new BinaryOpNode(Token.createFakeToken(Token.Type.PLUS,""),
                            original.leftNode, original.rightNode)
            );
        case Token.Type.DASH_ASSIGN:
            return new BinaryOpNode(Token.createFakeToken(Token.Type.ASSIGN, ""), 
                    original.leftNode, 
                    new BinaryOpNode(Token.createFakeToken(Token.Type.DASH,""),
                            original.leftNode, original.rightNode)
            );
        default:
            throw new Exception("Misuse of reduce assignment");
        }
    }

    void removePatches()
    {
        if(_compDataStack.top.loopOrSwitchStack == 0)
        {
            bool unresolved = false;
            if(_compDataStack.top.loopOrSwitchStack == 0)
            {
                foreach(brk ; _compDataStack.top.breaksToPatch)
                {
                    if(!brk.patched)
                    {
                        unresolved = true;
                        break;
                    }
                }

                foreach(cont ; _compDataStack.top.continuesToPatch)
                {
                    if(!cont.patched)
                    {
                        unresolved = true;
                        break;
                    }
                }
            }
            if(unresolved)
                throw new ScriptCompileException("Unresolvable break or continue statement", 
                        Token.createInvalidToken(Position(0,0), "break/continue"));
            _compDataStack.top.breaksToPatch = [];
            _compDataStack.top.continuesToPatch = [];
        }
    }

    /// this doesn't handle the stack counter
    void removeStackVar(string name)
    {
        _stackVariables.top.remove(name);
    }

    void throwUnimplemented(ExpressionNode expr)
    {
        throw new UnimplementedException("Unimplemented: " ~ expr.toString());
    }

    void throwUnimplemented(StatementNode stmt)
    {
        throw new UnimplementedException("Unimplemented: " ~ stmt.toString());
    }

    bool varExists(string name)
    {
        for(auto i = 1; i <= _stackVariables.array.length; ++i)
        {
            if(name in _stackVariables.array[$-i])
                return true;
        }
        return false;
    }

    struct CompilationData
    {
        /// environment depth counter
        int depthCounter;
        /// how many loops nested
        int loopOrSwitchStack = 0;
        /// list of breaks needing patched
        BreakOrContinueToPatch[] breaksToPatch;
        /// list of continues needing patched
        BreakOrContinueToPatch[] continuesToPatch;
    }

    struct BreakOrContinueToPatch
    {
        this(string lbl, size_t param, int d, int ll)
        {
            labelName = lbl;
            gotoPatchParam = param;
            depth = d;
            loopLevel = ll;
        }
        string labelName;
        size_t gotoPatchParam;
        int depth;
        int loopLevel;
        bool patched = false;
    }

    struct VarMetadata
    {
        bool isDefined;
        int stackLocation; // can be -1 for regular lookup
        int funcDepth; // how deep in function calls
        bool isConst;
    }

    alias VarTable = VarMetadata[string];

    /// when parsing a class expression or statement, if there is a base class it is added and poppped
    /// so that super expressions can be processed
    ExpressionNode[] _baseClassStack;

    /// the chunk being compiled
    Chunk _chunk;

    /// current source to send to each debugInfo
    string _currentSource;

    /// debug info stack
    Stack!DebugInfo _debugInfoStack;

    Stack!VarTable _stackVariables;
    Stack!CompilationData _compDataStack;
    /**
     * The stack is guaranteed to be empty between statements so absolute stack positions for variables
     * can be used. The var name and stack ID is stored in the environment. The stack must be manually cleaned up
     */
    size_t _stackVarCounter = 0;
    /// keep track of function depth
    size_t _funcDepth;
    /// In case of a return statement in a for loop
    Stack!size_t _counterStack;
    /// List of stack vars
    string[] _stackVarNames;
}

unittest
{
    import mildew.environment: Environment;
    auto compiler = new Compiler();
    // auto chunk = compiler.compile("5 == 5 ? 'ass' : 'titties';");
    auto vm = new VirtualMachine(new Environment(null, "<global>"));
    // vm.printChunk(chunk);
    // vm.run(chunk);
}