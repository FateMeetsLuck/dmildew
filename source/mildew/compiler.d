module mildew.compiler;

import std.variant;

import mildew.exceptions;
import mildew.lexer;
import mildew.parser;
import mildew.nodes;
import mildew.types;
import mildew.util.encode;
import mildew.visitors;
import mildew.vm.chunk;
import mildew.vm.consttable;
import mildew.vm.virtualmachine;

private enum BREAKLOOP_CODE = uint.max;
private enum BREAKSWITCH_CODE = uint.max - 1;
private enum CONTINUE_CODE = uint.max - 2;

/// Compiles code into chunks
class Compiler : INodeVisitor
{
public:

    /// compile code into chunk usable by vm
    Chunk compile(string source)
    {
        _chunk = new Chunk();
        _data = CompilationData.init;
        auto lexer = Lexer(source);
        auto parser = Parser(lexer.tokenize());
        // for now just expressions
        auto block = parser.parseProgram();
        block.accept(this);
        Chunk send = _chunk;
        _chunk = null; // ensure node functions cannot be used by outsiders at all
        return send;
    }

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
        throwUnimplemented(flnode);
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
        _chunk.bytecode ~= OpCode.OBJECT;
        return Variant(null);
    }

    /// TODO
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
            throwUnimplemented(bonode);
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
        uonode.operandNode.accept(this);
        switch(uonode.opToken.type)
        {
        case Token.Type.BIT_NOT:
            _chunk.bytecode ~= OpCode.BITNOT;
            break;
        case Token.Type.NOT:
            _chunk.bytecode ~= OpCode.NOT;
            break;
        case Token.Type.DASH:
            _chunk.bytecode ~= OpCode.NEGATE;
            break;
        case Token.Type.PLUS:
            break;
        default:
            if(uonode.opToken.isKeyword("typeof"))
                _chunk.bytecode ~= OpCode.TYPEOF;
            else
                throw new Exception("Uncaught parser error: " ~ uonode.toString());
        }
        return Variant(null);
    }

    /// TODO
	Variant visitPostfixOpNode(PostfixOpNode ponode)
    {
        // at least check if operand is valid
        if(!nodeIsAssignable(ponode.operandNode))
            throw new ScriptCompileException("Invalid operand for postfix operator", ponode.opToken);
        throwUnimplemented(ponode);
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

    /// TODO
	Variant visitFunctionCallNode(FunctionCallNode fcnode)
    {
        throwUnimplemented(fcnode);
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
        manode.memberNode.accept(this);
        _chunk.bytecode ~= OpCode.OBJGET;
        return Variant(null);
    }

    /// handle new operator. visitFunctionCallExpression will handle returnThis field
	Variant visitNewExpressionNode(NewExpressionNode nenode)
    {
        nenode.functionCallExpression.accept(this);
        return Variant(null);
    }
    
    /// TODO
    Variant visitVarDeclarationStatementNode(VarDeclarationStatementNode vdsnode)
    {
        throwUnimplemented(vdsnode);
        return Variant(null);
    }

    /// handle {} braces
	Variant visitBlockStatementNode(BlockStatementNode bsnode)
    {
        ++_data.depthCounter;
        _chunk.bytecode ~= OpCode.OPENSCOPE;
        foreach(stmt ; bsnode.statementNodes)
            stmt.accept(this);
        _chunk.bytecode ~= OpCode.CLOSESCOPE;
        --_data.depthCounter;
        return Variant(null);
    }

    /// TODO
	Variant visitIfStatementNode(IfStatementNode isnode)
    {
        throwUnimplemented(isnode);
        return Variant(null);
    }

    /// TODO
	Variant visitSwitchStatementNode(SwitchStatementNode ssnode)
    {
        throwUnimplemented(ssnode);
        return Variant(null);
    }

    /// TODO
	Variant visitWhileStatementNode(WhileStatementNode wsnode)
    {
        throwUnimplemented(wsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitDoWhileStatementNode(DoWhileStatementNode dwsnode)
    {
        throwUnimplemented(dwsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitForStatementNode(ForStatementNode fsnode)
    {
        throwUnimplemented(fsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitForOfStatementNode(ForOfStatementNode fosnode)
    {
        throwUnimplemented(fosnode);
        return Variant(null);
    }

    /// TODO
	Variant visitBreakStatementNode(BreakStatementNode bsnode)
    {
        throwUnimplemented(bsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitContinueStatementNode(ContinueStatementNode csnode)
    {
        throwUnimplemented(csnode);
        return Variant(null);
    }

    /// TODO
	Variant visitReturnStatementNode(ReturnStatementNode rsnode)
    {
        throwUnimplemented(rsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitFunctionDeclarationStatementNode(FunctionDeclarationStatementNode fdsnode)
    {
        throwUnimplemented(fdsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitThrowStatementNode(ThrowStatementNode tsnode)
    {
        throwUnimplemented(tsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitTryCatchBlockStatementNode(TryCatchBlockStatementNode tcbsnode)
    {
        throwUnimplemented(tcbsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitDeleteStatementNode(DeleteStatementNode dsnode)
    {
        throwUnimplemented(dsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitClassDeclarationStatementNode(ClassDeclarationStatementNode cdsnode)
    {
        throwUnimplemented(cdsnode);
        return Variant(null);
    }

    /// TODO
	Variant visitSuperCallStatementNode(SuperCallStatementNode scsnode)
    {
        throwUnimplemented(scsnode);
        return Variant(null);
    }

    /// handle expression statements
	Variant visitExpressionStatementNode(ExpressionStatementNode esnode)
    {
        esnode.expressionNode.accept(this);
        _chunk.bytecode ~= OpCode.POP;
        return Variant(null);
    }

private:
    ubyte[] encodeConst(T)(T value)
    {
        return encode(_chunk.constTable.addValueUint(ScriptAny(value)));
    }

    ubyte[] encodeConst(T : ScriptAny)(T value)
    {
        return encode(_chunk.constTable.addValueUint(value));
    }

    void throwUnimplemented(ExpressionNode expr)
    {
        throw new Exception("Unimplemented: " ~ expr.toString());
    }

    void throwUnimplemented(StatementNode stmt)
    {
        throw new Exception("Unimplemented: " ~ stmt.toString());
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

    /// the chunk being compiled
    Chunk _chunk;

    struct CompilationData
    {
        /// environment depth counter
        int depthCounter;
    }

    CompilationData _data;
}

unittest
{
    import mildew.environment: Environment;
    auto compiler = new Compiler();
    auto chunk = compiler.compile("5 == 5 ? 'ass' : 'titties';");
    auto vm = new VirtualMachine(new Environment(null, "<global>"));
    vm.printChunk(chunk);
    vm.run(chunk);
}