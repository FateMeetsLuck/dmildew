module mildew.vm.virtualmachine;

import std.conv: to;
import std.stdio;
import std.typecons;

import mildew.environment;
import mildew.exceptions;
import mildew.vm.chunk;
import mildew.vm.consttable;
import mildew.types;
import mildew.util.encode;
import mildew.util.stack;

/// 8-bit opcodes
enum OpCode : ubyte 
{
    NOP, // nop() -> ip += 1
    CONST, // const(uint) : load a const by index from the const table
    PUSH, // push(int) : push a stack value, can start at -1
    POP, // pop() : remove exactly one value from stack
    POPN, // pop(uint) : remove n values from stack
    SET, // set(uint) : set index of stack to value at top
    ARRAY, // array(uint) : pops n items to create array and pushes to top
    OBJECT, // array(uint) : create an object from key-value pairs starting with stack[-n] so n must be even
    NEW, // similar to call(uint)
    THIS, // pushes local "this" or undefined if not found
    OPENSCOPE, // openscope() : open an environment scope
    CLOSESCOPE, // closescope() : close an environment scope
    DECLVAR, // declvar(uint) : declare pop() as stack[-2] to a global described by a const
    DECLLET, // decllet(uint) : declare pop() as stack[-2] to a local described by a const
    DECLCONST, // declconst(uint) : declare pop() as stack[-2] to a local const described by a const
    GETVAR, // getvar(uint) : push variable described by const table string on to stack
    SETVAR, // setvar(uint) : store top() in variable described by const table index string leave value on top
    OBJGET, // objget() : retrieves stack[-2][stack[-1]], popping 2 and pushing 1
    OBJSET, // objset() : sets stack[-3][stack[-2]] to stack[-1], pops 3 and pushes the value that was set
    CALL, // call(uint) : stack should be this, func, arg1, arg2, arg3 and arg would be 3
    JMPFALSE, // jmpfalse(int) : relative jump
    JMP,  // jmp(int) -> : relative jump
    GOTO, // goto(uint, ubyte) : absolute ip. second param is number of scopes to subtract
    
    // binary ops
    BITNOT, // bitwise not
    NOT, // not top()
    NEGATE, // negate top()
    POW, // exponent operation
    MUL, // multiplication
    DIV, // division
    MOD, // modulo
    ADD, // add() : adds stack[-2,-1], pops 2, push 1
    MINUS, // minus
    BITRSH, // bit shift right top
    BITLSH, // bit shift left top
    LT, // less than
    LE, // less than or equal
    GT, // greater than
    GE, // greater than or equal
    EQUALS, // equals
    NEQUALS, // !equals
    BITAND, // bitwise and
    BITOR, // bitwise or
    BITXOR, // bitwise xor
    AND, // and
    OR, // or

    RETURN, // stops vm, should leave one value on stack
}

alias OpCodeFunction = size_t function(VirtualMachine, size_t, Chunk chunk);

/// helper function
private void throwRuntimeError(in string message, size_t ip, Chunk chunk)
{
    auto ex = new ScriptRuntimeException(message);
    immutable lineNum = chunk.getLineNumber(ip);
    ex.scriptTraceback ~= tuple(lineNum, chunk.getSourceLine(lineNum));
    throw ex;
}

pragma(inline)
private size_t opNop(VirtualMachine vm, size_t ip, Chunk chunk)
{
    return ip + 1;
}

pragma(inline)
private size_t opConst(VirtualMachine vm, size_t ip, Chunk chunk)
{
    // it might be necessary to copy the function when read from constant table
    // and assign its closure to whichever environment it is loaded in
    immutable constID = decode!uint(chunk.bytecode.ptr + ip + 1);
    vm._stack.push(chunk.constTable.get(constID));
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opPush(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable index = decode!int(chunk.bytecode.ptr + ip + 1);
    if(index < 0)
        vm._stack.push(vm._stack.array[$ + index]);
    else
        vm._stack.push(vm._stack.array[index]);
    return ip + 1 + int.sizeof;
}

pragma(inline)
private size_t opPop(VirtualMachine vm, size_t ip, Chunk chunk)
{
    vm._stack.pop();
    return ip + 1;
}

pragma(inline)
private size_t opPopN(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable amount = decode!uint(chunk.bytecode.ptr + ip + 1);
    vm._stack.pop(amount);
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opSet(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable index = decode!uint(chunk.bytecode.ptr + ip + 1);
    vm._stack.array[index] = vm._stack.pop();
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opArray(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable n = decode!uint(chunk.bytecode.ptr + ip + 1);
    auto arr = vm._stack.pop(n);
    vm._stack.push(ScriptAny(arr));
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opObject(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable n = decode!uint(chunk.bytecode.ptr + ip + 1);
    if(n % 2 != 0)
        throw new VMException("object arg must be even", ip, OpCode.OBJECT);
    auto pairList = vm._stack.pop(n);
    auto obj = new ScriptObject("object", null, null);
    for(uint i = 0; i < n; i += 2)
        obj[pairList[i].toString()] = pairList[i+1];
    vm._stack.push(ScriptAny(obj));
    return ip + 1 + uint.sizeof;
}

// todo new

pragma(inline)
private size_t opThis(VirtualMachine vm, size_t ip, Chunk chunk)
{
    bool _; // @suppress(dscanner.suspicious.unmodified)
    auto thisPtr = vm._environment.lookupVariableOrConst("this", _);
    if(thisPtr == null)
        vm._stack.push(ScriptAny.UNDEFINED);
    else
        vm._stack.push(*thisPtr);
    return ip + 1;
}

pragma(inline)
private size_t opOpenScope(VirtualMachine vm, size_t ip, Chunk chunk)
{
    vm._environment = new Environment(vm._environment);
    debug writefln("VM{ environment depth=%s", vm._environment.depth);
    return ip + 1;
}

pragma(inline)
private size_t opCloseScope(VirtualMachine vm, size_t ip, Chunk chunk)
{
    vm._environment = vm._environment.parent;
    debug writefln("VM} environment depth=%s", vm._environment.depth);
    return ip + 1;
}

pragma(inline)
private size_t opDeclVar(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto constID = decode!uint(chunk.bytecode.ptr + ip + 1);
    auto varName = chunk.constTable.get(constID).toString();
    auto value = vm._stack.pop();
    immutable ok = vm._globals.declareVariableOrConst(varName, value, false);
    if(!ok)
        throwRuntimeError("Cannot redeclare global " ~ varName, ip, chunk);
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opDeclLet(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto constID = decode!uint(chunk.bytecode.ptr + ip + 1);
    auto varName = chunk.constTable.get(constID).toString();
    auto value = vm._stack.pop();
    immutable ok = vm._environment.declareVariableOrConst(varName, value, false);
    if(!ok)
        throwRuntimeError("Cannot redeclare local " ~ varName, ip, chunk);
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opDeclConst(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto constID = decode!uint(chunk.bytecode.ptr + ip + 1);
    auto varName = chunk.constTable.get(constID).toString();
    auto value = vm._stack.pop();
    immutable ok = vm._environment.declareVariableOrConst(varName, value, true);
    if(!ok)
        throwRuntimeError("Cannot redeclare const " ~ varName, ip, chunk);
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opGetVar(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto constID = decode!uint(chunk.bytecode.ptr + ip + 1);
    auto varName = chunk.constTable.get(constID).toString();
    bool isConst; // @suppress(dscanner.suspicious.unmodified)
    auto valuePtr = vm._environment.lookupVariableOrConst(varName, isConst);
    if(valuePtr == null)
        throwRuntimeError("Variable lookup failed: " ~ varName, ip, chunk);
    vm._stack.push(*valuePtr);
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opSetVar(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto constID = decode!uint(chunk.bytecode.ptr + ip + 1);
    auto varName = chunk.constTable.get(constID).toString();
    bool isConst; // @suppress(dscanner.suspicious.unmodified)
    auto varPtr = vm._environment.lookupVariableOrConst(varName, isConst);
    if(varPtr == null)
        throwRuntimeError("Cannot assign to undefined variable: " ~ varName, ip, chunk);
    auto value = vm._stack.peek(); // @suppress(dscanner.suspicious.unmodified)
    if(value == ScriptAny.UNDEFINED)
        vm._environment.unsetVariable(varName);
    else
        *varPtr = value;
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opObjGet(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto objToAccess = vm._stack.array[$-2];
    auto field = vm._stack.array[$-1]; // @suppress(dscanner.suspicious.unmodified)
    vm._stack.pop(2);
    // TODO handle getters
    // if field is integer it is array access
    if(field.type == ScriptAny.Type.INTEGER)
    {
        auto index = field.toValue!long;
        if(objToAccess.type == ScriptAny.Type.ARRAY)
        {
            auto arr = objToAccess.toValue!(ScriptAny[]);
            if(index < 0)
                index = arr.length + index;
            if(index < 0 || index >= arr.length)
                throwRuntimeError("Out of bounds array access", ip, chunk);
            vm._stack.push(arr[index]);
        }
        else if(objToAccess.type == ScriptAny.Type.STRING)
        {
            auto wstr = objToAccess.toValue!(ScriptString)().getWString();
            if(index < 0)
                index = wstr.length + index;
            if(index < 0 || index >= wstr.length)
                throwRuntimeError("Out of bounds string access", ip, chunk);
            vm._stack.push(ScriptAny([wstr[index]]));
        }
        else
        {
            throwRuntimeError("Value " ~ objToAccess.toString() ~ " is not an array or string", ip, chunk);
        }
    }
    else // else object field access
    {
        auto index = field.toString();
        if(!objToAccess.isObject)
            throwRuntimeError("Unable to access members of non-object " ~ objToAccess.toString(), ip, chunk);
        // TODO check getters and run them if found
        // for now just access fields
        vm._stack.push(objToAccess[index]);
    }
    return ip + 1;
}

pragma(inline)
private size_t opObjSet(VirtualMachine vm, size_t ip, Chunk chunk)
{
    auto objToAccess = vm._stack.array[$-3];
    auto fieldToAssign = vm._stack.array[$-2]; // @suppress(dscanner.suspicious.unmodified)
    auto value = vm._stack.array[$-1];
    vm._stack.pop(3);
    if(fieldToAssign.type == ScriptAny.Type.INTEGER)
    {
        auto index = fieldToAssign.toValue!long;
        if(objToAccess.type == ScriptAny.Type.ARRAY)
        {
            auto arr = objToAccess.toValue!(ScriptAny[]);
            if(index < 0)
                index = arr.length + index;
            if(index < 0 || index >= arr.length)
                throwRuntimeError("Out of bounds array assignment", ip, chunk);
            arr[index] = value;
            vm._stack.push(value);
        }
        else
        {
            throwRuntimeError("Value " ~ objToAccess.toString() ~ " is not an array", ip, chunk);
        }
    }
    else
    {
        auto index = fieldToAssign.toValue!string;
        if(!objToAccess.isObject)
            throwRuntimeError("Unable to assign member of non-object " ~ objToAccess.toString(), ip, chunk);
        // TODO check setters, and in cases where there is a setter but no getter, undefined will be pushed
        objToAccess[index] = value;
        vm._stack.push(value);
    }
    return ip + 1;
}

pragma(inline)
private size_t opCall(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable n = decode!uint(chunk.bytecode.ptr + ip + 1) + 2;
    auto callInfo = vm._stack.pop(n);
    auto thisObj = callInfo[0]; // @suppress(dscanner.suspicious.unmodified)
    auto funcAny = callInfo[1];
    auto args = callInfo[2..$];
    NativeFunctionError nfe = NativeFunctionError.NO_ERROR;
    if(funcAny.type != ScriptAny.Type.FUNCTION)
        throwRuntimeError("Unable to call non-function " ~ funcAny.toString(), ip, chunk);
    auto func = funcAny.toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)
    if(func.type == ScriptFunction.Type.SCRIPT_FUNCTION)
    {
        throw new VMException("Calling script functions is not yet implemented", ip, OpCode.CALL);
    }
    else if(func.type == ScriptFunction.Type.NATIVE_FUNCTION)
    {
        auto nativeFunc = func.nativeFunction;
        vm._stack.push(nativeFunc(vm._environment, &thisObj, args, nfe));
    }
    else if(func.type == ScriptFunction.Type.NATIVE_DELEGATE)
    {
        auto nativeDelegate = func.nativeDelegate;
        vm._stack.push(nativeDelegate(vm._environment, &thisObj, args, nfe));
    }
    final switch(nfe)
    {
    case NativeFunctionError.NO_ERROR:
        break;
    case NativeFunctionError.RETURN_VALUE_IS_EXCEPTION:
        throwRuntimeError(vm._stack.peek().toString(), ip, chunk);
        break;
    case NativeFunctionError.WRONG_NUMBER_OF_ARGS:
        throwRuntimeError("Wrong number of arguments to native function", ip, chunk);
        break;
    case NativeFunctionError.WRONG_TYPE_OF_ARG:
        throwRuntimeError("Wrong type of argument to native function", ip, chunk);
        break;
    }
    return ip + 1 + uint.sizeof;
}

pragma(inline)
private size_t opJmpFalse(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable jmpAmount = decode!int(chunk.bytecode.ptr + ip + 1);
    immutable shouldJump = vm._stack.pop();
    if(!shouldJump)
        return ip + jmpAmount;
    else
        return ip + 1 + int.sizeof;
}

pragma(inline)
private size_t opJmp(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable jmpAmount = decode!int(chunk.bytecode.ptr + ip + 1);
    return ip + jmpAmount;
}

pragma(inline)
private size_t opGoto(VirtualMachine vm, size_t ip, Chunk chunk)
{
    immutable address = decode!uint(chunk.bytecode.ptr + ip + 1);
    return address;
}

pragma(inline)
private size_t opBitNot(VirtualMachine vm, size_t ip, Chunk chunk)
{
    vm._stack.array[$-1] = ~vm._stack.array[$-1];
    return ip + 1;
}

pragma(inline)
private size_t opNot(VirtualMachine vm, size_t ip, Chunk chunk)
{
    vm._stack.array[$-1] = ScriptAny(!vm._stack.array[$-1]);
    return ip + 1;
}

pragma(inline)
private size_t opNegate(VirtualMachine vm, size_t ip, Chunk chunk)
{
    vm._stack.array[$-1] = -vm._stack.array[$-1];
    return ip + 1;
}

pragma(inline)
private size_t opReturn(VirtualMachine vm, size_t ip, Chunk chunk)
{
    return chunk.bytecode.length; // this will stop the VM current function
}

/// implements virtual machine
class VirtualMachine
{
    /// ctor
    this(Environment globalEnv)
    {
        _environment = globalEnv;
        _globals = globalEnv;
        _ops[] = &opNop;
        _ops[OpCode.CONST] = &opConst;
        _ops[OpCode.PUSH] = &opPush;
        _ops[OpCode.POP] = &opPop;
        _ops[OpCode.POPN] = &opPopN;
        _ops[OpCode.SET] = &opSet;
        _ops[OpCode.ARRAY] = &opArray;
        _ops[OpCode.OBJECT] = &opObject;
        // TODO new
        _ops[OpCode.THIS] = &opThis;
        _ops[OpCode.OPENSCOPE] = &opOpenScope;
        _ops[OpCode.CLOSESCOPE] = &opCloseScope;
        _ops[OpCode.DECLVAR] = &opDeclVar;
        _ops[OpCode.DECLLET] = &opDeclLet;
        _ops[OpCode.DECLCONST] = &opDeclConst;
        _ops[OpCode.GETVAR] = &opGetVar;
        _ops[OpCode.SETVAR] = &opSetVar;
        _ops[OpCode.OBJGET] = &opObjGet;
        _ops[OpCode.OBJSET] = &opObjSet;
        _ops[OpCode.CALL] = &opCall;
        _ops[OpCode.JMPFALSE] = &opJmpFalse;
        _ops[OpCode.JMP] = &opJmp;
        _ops[OpCode.GOTO] = &opGoto;
        _ops[OpCode.BITNOT] = &opBitNot;
        _ops[OpCode.NOT] = &opNot;
        _ops[OpCode.NEGATE] = &opNegate;
        _ops[OpCode.RETURN] = &opReturn;
    }

    /// run a chunk of bytecode with a given const table
    void run(Chunk chunk)
    {
        size_t ip = 0;
        ubyte op;
        while(ip < chunk.bytecode.length)
        {
            op = chunk.bytecode[ip];
            debug printInstruction(ip, chunk);
            ip = _ops[op](this, ip, chunk);
            debug writefln("Stack: %s", _stack.array);
        }
    }

    /// print a chunk instruction by instruction, using the const table to indicate values
    void printChunk(Chunk chunk)
    {
        size_t ip = 0;
        while(ip < chunk.bytecode.length)
        {
            auto op = cast(OpCode)chunk.bytecode[ip];
            printInstruction(ip, chunk);
            switch(op)
            {
            case OpCode.NOP:
                ++ip;
                break;
            case OpCode.CONST:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.PUSH:
                ip += 1 + int.sizeof;
                break;
            case OpCode.POP:
                ++ip;
                break;
            case OpCode.POPN:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.SET: 
                ip += 1 + uint.sizeof;
                break;
            case OpCode.ARRAY:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.OBJECT:
                ip += 1 + uint.sizeof;
                break;
            // TODO new
            case OpCode.THIS:
                ++ip;
                break;
            case OpCode.OPENSCOPE:
                ++ip;
                break;
            case OpCode.CLOSESCOPE:
                ++ip;
                break;
            case OpCode.DECLVAR:
            case OpCode.DECLLET:
            case OpCode.DECLCONST:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.GETVAR:
            case OpCode.SETVAR:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.OBJGET:
            case OpCode.OBJSET:
                ++ip;
                break;
            case OpCode.CALL:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.JMPFALSE:
            case OpCode.JMP:
                ip += 1 + int.sizeof;
                break;
            case OpCode.GOTO:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.BITNOT:
            case OpCode.NOT:
            case OpCode.ADD:
            case OpCode.NEGATE:
                ++ip;
                break;
            case OpCode.RETURN:
                ++ip;
                break;
            default:
                ++ip;
            }
        }
    }

    private void printInstructionWithConstID(size_t ip, OpCode op, uint constID, Chunk chunk)
    {
        writefln("%05d: %s #%s // <%s> %s", 
                ip, op.to!string, constID, chunk.constTable.get(constID).typeToString(),
                chunk.constTable.get(constID));
    }

    /// prints an individual instruction without moving the ip
    void printInstruction(in size_t ip, Chunk chunk)
    {
        auto op = cast(OpCode)chunk.bytecode[ip];
        switch(op)
        {
        case OpCode.NOP:
            writefln("%05d: %s", ip, op.to!string);
            break;
        case OpCode.CONST: {
            immutable constID = decode!uint(chunk.bytecode.ptr + ip + 1);
            printInstructionWithConstID(ip, op, constID, chunk);
            break;
        }
        case OpCode.PUSH: {
            immutable index = decode!int(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s index=%s", ip, op.to!string, index);
            break;
        }
        case OpCode.POP:
            writefln("%05d: %s", ip, op.to!string);
            break;
        case OpCode.POPN: {
            immutable amount = decode!uint(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s amount=%s", ip, op.to!string, amount);
            break;
        }
        case OpCode.SET: {
            immutable index = decode!uint(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s index=%s", ip, op.to!string, index);
            break;
        }
        case OpCode.ARRAY: {
            immutable n = decode!uint(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s n=%s", ip, op.to!string, n);
            break;
        }
        case OpCode.OBJECT: {
            immutable n = decode!uint(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s n=%s", ip, op.to!string, n);
            break;
        }
        // TODO new
        case OpCode.THIS:
            writefln("%05d: %s", ip, op.to!string);
            break;
        case OpCode.OPENSCOPE:
        case OpCode.CLOSESCOPE:
            writefln("%05d: %s", ip, op.to!string);
            break;
        case OpCode.DECLVAR: 
        case OpCode.DECLLET:
        case OpCode.DECLCONST: {
            immutable constID = decode!uint(chunk.bytecode.ptr + ip + 1);
            printInstructionWithConstID(ip, op, constID, chunk);
            break;
        }
        case OpCode.GETVAR:
        case OpCode.SETVAR: {
            immutable constID = decode!uint(chunk.bytecode.ptr + ip + 1);
            printInstructionWithConstID(ip, op, constID, chunk);
            break;
        }
        case OpCode.OBJSET:
        case OpCode.OBJGET:
            writefln("%05d: %s", ip, op.to!string);
            break;
        case OpCode.CALL: {
            immutable args = decode!uint(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s args=%s", ip, op.to!string, args);
            break;
        }
        case OpCode.JMPFALSE: 
        case OpCode.JMP: {
            immutable jump = decode!int(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s jump=%s", ip, op.to!string, jump);
            break;
        }
        case OpCode.GOTO: {
            immutable instruction = decode!uint(chunk.bytecode.ptr + ip + 1);
            writefln("%05d: %s instruction=%s", ip, op.to!string, instruction);
            break;
        }
        case OpCode.BITNOT:
        case OpCode.NOT:
        case OpCode.NEGATE:
        case OpCode.ADD:
            writefln("%05d: %s", ip, op.to!string);
            break;
        case OpCode.RETURN:
            writefln("%05d: %s", ip, op.to!string);
            break;
        default:
            writefln("%05d: ??? (%s)", ip, cast(ubyte)op);
        }  
    }

private:
    Environment _environment;
    Environment _globals;
    Stack!ScriptAny _stack;
    OpCodeFunction[ubyte.max + 1] _ops;
}

class VMException : Exception
{
    this(string msg, size_t iptr, OpCode op, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        ip = iptr;
        opcode = op;
    }

    override string toString() const
    {
        import std.format: format;
        return msg ~ " at instruction " ~ format("%x", ip) ~ " (" ~ opcode.to!string ~ ")";
    }

    size_t ip;
    OpCode opcode;
}

unittest
{
    auto vm = new VirtualMachine(new Environment(null, "<global>"));
    auto chunk = new Chunk();

    ubyte[] getConst(T)(T value)
    {
        return encode(chunk.constTable.addValueUint(ScriptAny(value)));
    }

    ScriptAny native_testFunc(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
    {
        writefln("The type of this is %s", thisObj.typeToString);
        for(size_t i = 0; i < args.length; ++i)
        {
            writefln("The type of arg #%s is %s", i, args[i].typeToString);
        }
        return ScriptAny(1000);
    }

    chunk.bytecode ~= encode(OpCode.OPENSCOPE);
    chunk.bytecode ~= encode(OpCode.CONST) ~ getConst("a");
    chunk.bytecode ~= encode(OpCode.CONST) ~ getConst(69);
    chunk.bytecode ~= encode(OpCode.OBJECT) ~ encode!uint(2);
    chunk.bytecode ~= encode(OpCode.PUSH) ~ encode!int(-1);
    chunk.bytecode ~= encode(OpCode.CONST) ~ getConst("foo");
    chunk.bytecode ~= encode(OpCode.CONST) ~ getConst(420);
    chunk.bytecode ~= encode(OpCode.OBJSET);
    chunk.bytecode ~= encode(OpCode.PUSH) ~ encode!int(-2);
    chunk.bytecode ~= encode(OpCode.CONST) ~ getConst("a");
    chunk.bytecode ~= encode(OpCode.OBJGET);
    chunk.bytecode ~= encode(OpCode.CONST) ~ getConst(new ScriptFunction("testFunc", &native_testFunc));
    chunk.bytecode ~= encode(OpCode.PUSH) ~ encode!int(-1);
    chunk.bytecode ~= encode(OpCode.CALL) ~ encode!uint(1);
    chunk.bytecode ~= encode(OpCode.NEGATE);
    chunk.bytecode ~= encode(OpCode.CLOSESCOPE);

    vm.printChunk(chunk);
    vm.run(chunk);
}