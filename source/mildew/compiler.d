/**
 * This module implements the compiler
 */
module mildew.compiler;

debug import std.stdio;
import std.variant;

import mildew.environment;
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
        _chunk = new Chunk();
        _compDataStack.push(new CompilationData);
        auto lexer = Lexer(source);
        auto parser = Parser(lexer.tokenize());
        _chunk.source = splitLines(source);
        // for now just expressions
        auto block = parser.parseProgram();
        block.accept(this);
        destroy(block);
        Chunk send = _chunk;
        _chunk = null; // ensure node functions cannot be used by outsiders at all
        _compDataStack.pop();
        return send;
    }

// The visitNode methods are not intended for public use but are required to be public by D language constraints

    /// handle literal value node (easiest)
	Variant visitLiteralNode(LiteralNode lnode)
    {
        if(lnode.value == ScriptAny(1))
            _chunk.bytecode ~= OpCode.CONST_1;
        else if(lnode.value == ScriptAny(-1))
            _chunk.bytecode ~= OpCode.CONST_N1;
        else
            _chunk.bytecode ~= OpCode.CONST ~ encodeConst(lnode.value);
        return Variant(null);
    }

    /// handle function literals. The VM should create new functions with the appropriate context
    ///  when a function is loaded from the const table
    Variant visitFunctionLiteralNode(FunctionLiteralNode flnode)
    {
        auto oldChunk = _chunk.bytecode; // @suppress(dscanner.suspicious.unmodified)
        _compDataStack.push(new CompilationData);
        _chunk.bytecode = [];
        foreach(stmt ; flnode.statements)
            stmt.accept(this);
        // add a return undefined statement in case missing one
        _chunk.bytecode ~= OpCode.STACK_1;
        _chunk.bytecode ~= OpCode.RETURN;
        // create function
        ScriptAny func = new ScriptFunction(
            flnode.optionalName == "" ? "<anonymous function>" : flnode.optionalName, 
            flnode.argList, _chunk.bytecode, false);
        _chunk.bytecode = oldChunk;
        _compDataStack.pop();
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
        _chunk.bytecode ~= OpCode.OBJECT ~ encode(cast(uint)(olnode.keys.length * 2));
        return Variant(null);
    }

    /// TODO (may add class instruction or instructions to assign properties and prototypes)
	Variant visitClassLiteralNode(ClassLiteralNode clnode)
    {
        throwUnimplemented(clnode);
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
            throw new Exception("Uncaught parser error: " ~ bonode.toString());
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
        _chunk.addLine(_chunk.bytecode.length, vdsnode.line);
        foreach(expr ; vdsnode.varAccessOrAssignmentNodes)
        {
            string varName = "";
            // is it a validated binop node
            if(auto bopnode = cast(BinaryOpNode)expr)
            {
                // if the right hand side is a function literal, we can rename it
                if(auto flnode = cast(FunctionLiteralNode)bopnode.rightNode)
                    flnode.optionalName = bopnode.leftNode.toString();
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
            
            if(vdsnode.qualifier.text == "var")
                _chunk.bytecode ~= OpCode.DECLVAR ~ encodeConst(varName);
            else if(vdsnode.qualifier.text == "let")
                _chunk.bytecode ~= OpCode.DECLLET ~ encodeConst(varName);
            else if(vdsnode.qualifier.text == "const")
                _chunk.bytecode ~= OpCode.DECLCONST ~ encodeConst(varName);
            else
                throw new Exception("Catastrophic parser fail: " ~ vdsnode.toString());

            if(vdsnode.qualifier.text != "var")
                _compDataStack.top.env.forceSetVarOrConst(varName, ScriptAny(true), vdsnode.qualifier.text == "const");
        }
        return Variant(null);
    }

    /// handle {} braces
	Variant visitBlockStatementNode(BlockStatementNode bsnode)
    {
        import std.conv: to;
        _chunk.addLine(_chunk.bytecode.length, bsnode.line);
        // if there are no vardeclarations at the top level the scope op can be omitted
        bool omitScope = true;
        foreach(stmt ; bsnode.statementNodes)
        {
            if(cast(VarDeclarationStatementNode)stmt)
            {
                omitScope = false;
                break;
            }
        }
        if(!omitScope)
        {
            ++_compDataStack.top.depthCounter;
            _compDataStack.top.env = new Environment(_compDataStack.top.env, 
                    to!string(_compDataStack.top.depthCounter));

            _chunk.bytecode ~= OpCode.OPENSCOPE;
        }
        foreach(stmt ; bsnode.statementNodes)
            stmt.accept(this);
        
        if(!omitScope)
        {
            _chunk.bytecode ~= OpCode.CLOSESCOPE;

            _compDataStack.top.env = _compDataStack.top.env.parent;
            --_compDataStack.top.depthCounter;
        }
        return Variant(null);
    }

    /// emit if statements
	Variant visitIfStatementNode(IfStatementNode isnode)
    {
        // first analysis, if the if or else blocks are a var declaration, auto surround with {}
        // so that variables under if or else cannot escape
        if(cast(VarDeclarationStatementNode)isnode.onTrueStatement)
            isnode.onTrueStatement = new BlockStatementNode(isnode.onTrueStatement.line, [isnode.onTrueStatement]);
        if(isnode.onFalseStatement)
        {
            if(cast(VarDeclarationStatementNode)isnode.onFalseStatement)
                isnode.onFalseStatement = new BlockStatementNode(isnode.onFalseStatement.line, 
                        [isnode.onFalseStatement]);
        }
        _chunk.addLine(_chunk.bytecode.length, isnode.line);
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

    /// TODO
	Variant visitSwitchStatementNode(SwitchStatementNode ssnode)
    {
        _chunk.addLine(_chunk.bytecode.length, ssnode.line);
        throwUnimplemented(ssnode);
        return Variant(null);
    }

    /// Handle while loops
	Variant visitWhileStatementNode(WhileStatementNode wsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, wsnode.line);
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
        --_compDataStack.top.loopOrSwitchStack;
        *cast(int*)(_chunk.bytecode.ptr + jmp) = -cast(int)(length2 - length0);
        *cast(int*)(_chunk.bytecode.ptr + jmpFalse) = cast(int)(_chunk.bytecode.length - length1);
        // patch gotos
        patchBreaksAndContinues(wsnode.label, breakLocation, continueLocation,
                _compDataStack.top.depthCounter);
        removePatches();
        return Variant(null);
    }

    /// TODO
	Variant visitDoWhileStatementNode(DoWhileStatementNode dwsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, dwsnode.line);
        throwUnimplemented(dwsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitForStatementNode(ForStatementNode fsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, fsnode.line);
        throwUnimplemented(fsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitForOfStatementNode(ForOfStatementNode fosnode)
    {
        _chunk.addLine(_chunk.bytecode.length, fosnode.line);
        throwUnimplemented(fosnode);
        return Variant(null);
    }

    /// TODO
	Variant visitBreakStatementNode(BreakStatementNode bsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, bsnode.line);
        immutable patchLocation = _chunk.bytecode.length + 1;
        _chunk.bytecode ~= OpCode.GOTO ~ encode(uint.max) ~ cast(ubyte)0;
        _compDataStack.top.breaksToPatch ~= BreakOrContinueToPatch(bsnode.label, patchLocation,
                _compDataStack.top.depthCounter);
        return Variant(null);
    }

    /// TODO
	Variant visitContinueStatementNode(ContinueStatementNode csnode)
    {
        _chunk.addLine(_chunk.bytecode.length, csnode.line);
        throwUnimplemented(csnode);
        return Variant(null);
    }

    /// Return statements
	Variant visitReturnStatementNode(ReturnStatementNode rsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, rsnode.line);
        if(rsnode.expressionNode !is null)
            rsnode.expressionNode.accept(this);
        else
            _chunk.bytecode ~= OpCode.STACK_1;
        _chunk.bytecode ~= OpCode.RETURN;
        return Variant(null);
    }

    /// TODO
	Variant visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode fdsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, fdsnode.line);
        throwUnimplemented(fdsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitThrowStatementNode(ThrowStatementNode tsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, tsnode.line);
        throwUnimplemented(tsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitTryCatchBlockStatementNode(TryCatchBlockStatementNode tcbsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, tcbsnode.line);
        throwUnimplemented(tcbsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitDeleteStatementNode(DeleteStatementNode dsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, dsnode.line);
        throwUnimplemented(dsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitClassDeclarationStatementNode(ClassDeclarationStatementNode cdsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, cdsnode.line);
        throwUnimplemented(cdsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitSuperCallStatementNode(SuperCallStatementNode scsnode)
    {
        _chunk.addLine(_chunk.bytecode.length, scsnode.line);
        throwUnimplemented(scsnode);
        return Variant(null);
    }

    /// handle expression statements
	Variant visitExpressionStatementNode(ExpressionStatementNode esnode)
    {
        _chunk.addLine(_chunk.bytecode.length, esnode.line);
        esnode.expressionNode.accept(this);
        _chunk.bytecode ~= OpCode.POP;
        return Variant(null);
    }

private:
    enum UNPATCHED_JMP = 262_561_909;

    ubyte[] encodeConst(T)(T value)
    {
        return encode(_chunk.constTable.addValueUint(ScriptAny(value)));
    }

    ubyte[] encodeConst(T : ScriptAny)(T value)
    {
        return encode(_chunk.constTable.addValueUint(value));
    }

    /// The return value MUST BE USED
    size_t genJmpFalse()
    {
        _chunk.bytecode ~= OpCode.JMPFALSE ~ encode!int(UNPATCHED_JMP);
        return _chunk.bytecode.length - int.sizeof;
    }

    /// The return value MUST BE USED
    size_t genJmp()
    {
        _chunk.bytecode ~= OpCode.JMP ~ encode!int(UNPATCHED_JMP);
        return _chunk.bytecode.length - int.sizeof;
    }

    void handleAssignment(ExpressionNode leftExpr, Token opToken, ExpressionNode rightExpr)
    {
        // if right hand is a function without a name, assign its name to left hand
        if(auto fln = cast(FunctionLiteralNode)rightExpr)
        {
            fln.optionalName = leftExpr.toString();
        }
        if(auto van = cast(VarAccessNode)leftExpr)
        {
            rightExpr.accept(this);
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

    void patchBreaksAndContinues(string label, size_t breakGoto, size_t continueGoto, int depthCounter)
    {
        for(size_t i = 0; i < _compDataStack.top.breaksToPatch.length; ++i)
        {
            if(!_compDataStack.top.breaksToPatch[i].patched)
            {
                if(_compDataStack.top.breaksToPatch[i].labelName == label)
                {
                    *cast(uint*)(_chunk.bytecode.ptr + _compDataStack.top.breaksToPatch[i].gotoPatchParam) 
                            = cast(uint)breakGoto;
                    _chunk.bytecode[_compDataStack.top.breaksToPatch[i].gotoPatchParam + uint.sizeof] 
                            = cast(ubyte)(_compDataStack.top.breaksToPatch[i].depth - depthCounter);
                    _compDataStack.top.breaksToPatch[i].patched = true;
                }
            }
        }

        for(size_t i = 0; i < _compDataStack.top.continuesToPatch.length; ++i)
        {
            if(!_compDataStack.top.continuesToPatch[i].patched)
            {
                if(_compDataStack.top.continuesToPatch[i].labelName == label)
                {
                    *cast(uint*)(_chunk.bytecode.ptr + _compDataStack.top.continuesToPatch[i].gotoPatchParam) 
                            = cast(uint)continueGoto;
                    _chunk.bytecode[_compDataStack.top.continuesToPatch[i].gotoPatchParam + uint.sizeof] 
                            = cast(ubyte)(_compDataStack.top.continuesToPatch[i].depth - depthCounter);
                    _compDataStack.top.continuesToPatch[i].patched = true;
                }
            }
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

    void throwUnimplemented(ExpressionNode expr)
    {
        throw new UnimplementedException("Unimplemented: " ~ expr.toString());
    }

    void throwUnimplemented(StatementNode stmt)
    {
        throw new UnimplementedException("Unimplemented: " ~ stmt.toString());
    }

    /// the chunk being compiled
    Chunk _chunk;

    struct BreakOrContinueToPatch
    {
        this(string lbl, size_t param, int d)
        {
            labelName = lbl;
            gotoPatchParam = param;
            depth = d;
        }
        string labelName;
        size_t gotoPatchParam;
        int depth;
        bool patched = false;
    }

    class CompilationData
    {
        this()
        {
            env = new Environment(null, "<base>");
        }

        /// environment depth counter
        int depthCounter;
        /// uses the Environment class to handle variable resolution in the future
        Environment env;
        /// how many loops nested
        int loopOrSwitchStack = 0;
        /// list of breaks needing patched
        BreakOrContinueToPatch[] breaksToPatch;
        /// list of continues needing patched
        BreakOrContinueToPatch[] continuesToPatch;
    }

    Stack!CompilationData _compDataStack;
}

unittest
{
    import mildew.environment: Environment;
    auto compiler = new Compiler();
    auto chunk = compiler.compile("5 == 5 ? 'ass' : 'titties';");
    auto vm = new VirtualMachine(new Environment(null, "<global>"));
    vm.printChunk(chunk);
    vm.run(chunk);
    ScriptAny foo = new ScriptFunction("a", ["x", "y", "z"], cast(ubyte[])"titties yeah", false);
    ScriptAny bar = new ScriptFunction("a", ["x", "y", "z"], cast(ubyte[])"titties yeah", false);
    assert(foo == bar);
}