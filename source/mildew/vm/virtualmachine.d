/**
This module implements the VirtualMachine that executes compiled bytecode.

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
module mildew.vm.virtualmachine;

import core.sync.semaphore;
import core.thread.fiber;
import std.concurrency;
import std.container: SList;
import std.conv: to;
import std.parallelism;
import std.stdio;
import std.string;
import std.typecons;

import mildew.environment;
import mildew.exceptions;
import mildew.stdlib.buffers;
import mildew.stdlib.generator;
import mildew.stdlib.map;
import mildew.stdlib.regexp;
import mildew.types;
import mildew.util.encode;
import mildew.util.regex: extract;
import mildew.util.stack;
import mildew.vm.consttable;
import mildew.vm.debuginfo;
import mildew.vm.program;
import mildew.vm.fiber;

/// 8-bit opcodes
enum OpCode : ubyte 
{
    NOP, // nop() -> ip += 1
    CONST, // const(uint) : load a const by index from the const table
    CONST_0, // const0() : load long(0) on to stack
    CONST_1, // const1() : push 1 to the stack
    CONST_N1, // constN1() : push -1 to the stack
    PUSH, // push(int) : push a stack value, can start at -1
    POP, // pop() : remove exactly one value from stack
    POPN, // pop(uint) : remove n values from stack
    SET, // set(uint) : set index of stack to value at top without popping stack
    STACK, // stack(uint) : push n number of undefines to stack
    STACK_1, // stack1() : push one undefined to stack
    ARRAY, // array(uint) : pops n items to create array and pushes to top
    OBJECT, // array(uint) : create an object from key-value pairs starting with stack[-n] so n must be even
    CLASS, // class(ubyte,ubyte,ubyte,ubyte) : first arg is how many normal method pairs, second arg is how many getters,
            // third arg is how many setter pairs, 4th arg is static method pairs, and at stack[-1] base class.
            // the finalized class constructor is pushed after all those values are popped. String group before method group
            // stack[-2] is constructor
    REGEX, // creates a regex from a string at stack[-1] such as /foo/g
    ITER, // pushes a function that returns {value:..., done:bool} performed on pop()
    DEL, // delete member stack[-1]:string from object stack[2]. pops 2
    NEW, // similar to call(uint) except only func, arg1, arg2, etc.
    THIS, // pushes local "this" or undefined if not found
    OPENSCOPE, // openscope() : open an environment scope
    CLOSESCOPE, // closescope() : close an environment scope
    DECLVAR, // declvar(uint) : declare pop() to a global described by a const string
    DECLLET, // decllet(uint) : declare pop() to a local described by a const string
    DECLCONST, // declconst(uint) : declare pop() as stack[-2] to a local const described by a const
    GETVAR, // getvar(uint) : push variable described by const table string on to stack
    SETVAR, // setvar(uint) : store top() in variable described by const table index string leave value on top
    OBJGET, // objget() : retrieves stack[-2][stack[-1]], popping 2 and pushing 1
    OBJSET, // objset() : sets stack[-3][stack[-2]] to stack[-1], pops 3 and pushes the value that was set
    CALL, // call(uint) : stack should be this, func, arg1, arg2, arg3 and arg would be 3
    JMPFALSE, // jmpfalse(int) : relative jump
    JMP,  // jmp(int) -> : relative jump
    SWITCH, // switch(uint) -> arg=abs jmp, stack[-2] jmp table stack[-1] value to test
    GOTO, // goto(uint, ubyte) : absolute ip. second param is number of scopes to subtract
    THROW, // throw() : throws pop() as a script runtime exception
    RETHROW, // rethrow() : rethrow the exception flag, should only be generated with try-finally
    TRY, // try(uint) : parameter is ip to goto for catch (or sometimes finally if finally only)
    ENDTRY, // pop unconsumed try-entry from try-entry list
    LOADEXC, // loads the current exception on to stack, either message or thrown value
    
    // special ops
    CONCAT, // concat(uint) : concat N elements on stack and push resulting string

    // binary and unary and terniary ops
    BITNOT, // bitwise not
    NOT, // not top()
    NEGATE, // negate top()
    TYPEOF, // typeof operator
    INSTANCEOF, // instanceof operator
    POW, // exponent operation
    MUL, // multiplication
    DIV, // division
    MOD, // modulo
    ADD, // add() : adds stack[-2,-1], pops 2, push 1
    SUB, // minus
    BITLSH, // bit shift left top
    BITRSH, // bit shift right top
    BITURSH, // bit shift right unsigned
    LT, // less than
    LE, // less than or equal
    GT, // greater than
    GE, // greater than or equal
    EQUALS, // equals
    NEQUALS, // !equals
    STREQUALS, // strict equals (===)
    NSTREQUALS, // not strict equals (!==)
    BITAND, // bitwise and
    BITOR, // bitwise or
    BITXOR, // bitwise xor

    RETURN, // return from a function, should leave exactly one value on stack
    HALT, // completely stop the vm
}

alias OpCodeFunction = size_t function(VirtualMachine, const ubyte[] chunk, size_t ip);

private ScriptAny getLocalThis(Environment env)
{
    bool _; // @suppress(dscanner.suspicious.unmodified)
    auto thisPtr = env.lookupVariableOrConst("this", _);
    if(thisPtr == null)
        return ScriptAny.UNDEFINED;
    else
        return *thisPtr;
}

/**
 * Attempts to recover from or throw a ScriptRuntimeException. Returns an instruction pointer to the nearest
 * catch if on the current stack frame, and failing that, throws the exception.
 * Params:
 *  message = The message of the exception
 *  vm = The VirtualMachine associated with the exception
 *  chunk = The bytecode currently being executed
 *  ip = The current instruction pointer
 *  thrownValue = (Optional) If a ScriptAny is being thrown, this is the value
 *  rethrow = (Optional) If the exception is being rethrown, the value should be vm._exc
 * Returns:
 *  The instruction pointer pointing to the nearest catch block. If none exists, the exception is thrown instead
 *  of returning.
 */
private size_t throwRuntimeError(in string message, VirtualMachine vm, const ubyte[] chunk, 
                            size_t ip, ScriptAny thrownValue = ScriptAny.UNDEFINED, 
                            ScriptRuntimeException rethrow = null)
{
    if(rethrow)
        vm._exc = rethrow;
    else
        vm._exc = new ScriptRuntimeException(message);
    
    if(thrownValue != ScriptAny.UNDEFINED)
        vm._exc.thrownValue = thrownValue;
    // unwind stack starting with current
    if(chunk && vm._latestDebugMap && chunk in vm._latestDebugMap)
    {
        // TODO fix error reporting
        immutable lineNum = vm._latestDebugMap[chunk].getLineNumber(ip);
        vm._exc.scriptTraceback ~= tuple(lineNum, vm._latestDebugMap[chunk].getSourceLine(lineNum));
    }
    // consume latest try-data entry if available
    if(vm._tryData.length > 0)
    {
        immutable tryData = vm._tryData[$-1];
        vm._tryData = vm._tryData[0..$-1];
        immutable depthToReduce = vm._environment.depth - tryData.depth;
        for(int i = 0; i < depthToReduce; ++i)
            vm._environment = vm._environment.parent;
        vm._stack.size = tryData.stackSize;
        return tryData.catchGoto;
    }
    // Generators will set parent VM exception flag. This is checked in opCall
    throw vm._exc;
}

/// Similar to the above function except directly throws because there are no try-data blocks in native code
private void throwNativeRuntimeError(string reason, VirtualMachine vm, ScriptAny thrownValue = ScriptAny.UNDEFINED)
{
    vm._exc = new ScriptRuntimeException(reason);
    if(thrownValue != ScriptAny.UNDEFINED)
        vm._exc.thrownValue = thrownValue;
    throw vm._exc;
}

private string opCodeToString(const OpCode op)
{
    return op.to!string().toLower();
}

pragma(inline, true)
private size_t opNop(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    return ip + 1;
}

pragma(inline, true)
private size_t opConst(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable constID = decode!uint(chunk[ip + 1..$]);
    auto value = vm._latestConstTable.get(constID);
    if(value.type == ScriptAny.Type.FUNCTION)
        value = value.toValue!ScriptFunction().copyCompiled(vm._environment);
    vm._stack.push(value);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opConst0(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.push(ScriptAny(0));
    return ip + 1;
}

pragma(inline, true)
private size_t opConst1(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.push(ScriptAny(1));
    return ip + 1;
}

pragma(inline, true)
private size_t opPush(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable index = decode!int(chunk[ip + 1..$]);
    if(index < 0)
        vm._stack.push(vm._stack.array[$ + index]);
    else
        vm._stack.push(vm._stack.array[index]);
    return ip + 1 + int.sizeof;
}

pragma(inline, true)
private size_t opPop(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._lastValuePopped = vm._stack.pop();
    return ip + 1;
}

pragma(inline, true)
private size_t opPopN(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable amount = decode!uint(chunk[ip + 1..$]);
    vm._stack.pop(amount);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opSet(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable index = decode!uint(chunk[ip + 1..$]);
    vm._stack.array[index] = vm._stack.array[$-1];
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opStack(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable n = decode!uint(chunk[ip + 1..$]);
    ScriptAny[] undefineds = new ScriptAny[n];
    vm._stack.push(undefineds);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opStack1(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.push(ScriptAny.UNDEFINED);
    return ip + 1;
}

pragma(inline, true)
private size_t opArray(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable n = decode!uint(chunk[ip + 1..$]);
    auto arr = vm._stack.pop(n);
    vm._stack.push(ScriptAny(arr));
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opObject(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable n = decode!uint(chunk[ip + 1..$]) * 2;
    auto pairList = vm._stack.pop(n);
    auto obj = new ScriptObject("object", null, null);
    for(uint i = 0; i < n; i += 2)
        obj[pairList[i].toString()] = pairList[i+1];
    vm._stack.push(ScriptAny(obj));
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opClass(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable numMethods = decode!ubyte(chunk[ip + 1..$]);
    immutable numGetters = decode!ubyte(chunk[ip + 2..$]);
    immutable numSetters = decode!ubyte(chunk[ip + 3..$]);
    immutable numStatics = decode!ubyte(chunk[ip + 4..$]);
    auto baseClass = vm._stack.pop();
    auto ctor = vm._stack.pop(); // @suppress(dscanner.suspicious.unmodified)
    auto statics = vm._stack.pop(numStatics);
    auto staticNames = vm._stack.pop(numStatics);
    auto setters = vm._stack.pop(numSetters);
    auto setterNames = vm._stack.pop(numSetters);
    auto getters = vm._stack.pop(numGetters);
    auto getterNames = vm._stack.pop(numGetters);
    auto methods = vm._stack.pop(numMethods);
    auto methodNames = vm._stack.pop(numMethods);

    auto constructor = ctor.toValue!ScriptFunction;
    if(constructor is null)
        throw new VMException("Malformed class instruction: invalid constructor", ip, OpCode.CLASS);

    for(auto i = 0; i < numMethods; ++i)
    {
        auto method = methods[i].toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)
        if(method is null)
            throw new VMException("Malformed class instruction: invalid method", ip, OpCode.CLASS);
        constructor["prototype"][methodNames[i].toString] = method;
    }

    for(auto i = 0; i < numGetters; ++i)
    {
        auto getter = getters[i].toValue!ScriptFunction;
        if(getter is null)
            throw new VMException("Malformed class instruction: invalid get property", ip, OpCode.CLASS);
        constructor["prototype"].addGetterProperty(getterNames[i].toString(), getter);
    }

    for(auto i = 0; i < numSetters; ++i)
    {
        auto setter = setters[i].toValue!ScriptFunction;
        if(setter is null)
            throw new VMException("Malformed class instruction: invalid set property", ip, OpCode.CLASS);
        constructor["prototype"].addSetterProperty(setterNames[i].toString(), setter);
    }

    for(auto i = 0; i < numStatics; ++i)
    {
        constructor[staticNames[i].toString()] = statics[i];
    }

    if(baseClass)
    {
        auto baseClassCtor = baseClass.toValue!ScriptFunction;
        if(baseClassCtor is null)
            return throwRuntimeError("Invalid base class " ~ baseClass.toString(), vm, chunk, ip);
        auto ctorPrototype = constructor["prototype"].toValue!ScriptObject;
        ctorPrototype.prototype = baseClassCtor["prototype"].toValue!ScriptObject;
        constructor.prototype = baseClassCtor;
    }

    // push the resulting modified constructor
    vm._stack.push(ScriptAny(constructor));

    return ip + 1 + 4 * ubyte.sizeof;
}

pragma(inline, true)
private size_t opRegex(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto regexString = vm._stack.pop().toString();
    auto parts = extract(regexString);
    auto regexResult = ScriptAny(new ScriptObject("RegExp", getRegExpProto, new ScriptRegExp(parts[0], parts[1])));
    vm._stack.push(regexResult);
    return ip + 1;
}

private template BufferGenerator(A)
{

}

pragma(inline, true)
private size_t opIter(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto objToIterate = vm._stack.pop();
    // can be a string, array, or object
    // FUTURE: a Generator returned by a Generator function
    if(!(objToIterate.isObject))
        return throwRuntimeError("Cannot iterate over non-object " ~ objToIterate.toString, vm, chunk, ip);
    if(objToIterate.type == ScriptAny.Type.STRING)
    {
        immutable elements = objToIterate.toValue!string;
        auto generator = new Generator!(Tuple!(size_t,dstring))({
            size_t indexCounter = 0;
            foreach(dchar ele ; elements)
            {
                ++indexCounter;
                yield(tuple(indexCounter-1,ele.to!dstring));
            }
        });
        vm._stack.push(ScriptAny(new ScriptFunction("next", 
            delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError){
                auto retVal = new ScriptObject("iteration", null, null);
                if(generator.empty)
                {
                    retVal.assignField("done", ScriptAny(true));
                }
                else 
                {
                    auto result = generator.front();
                    retVal.assignField("key", ScriptAny(result[0]));
                    retVal.assignField("value", ScriptAny(result[1]));
                    generator.popFront();
                }
                return ScriptAny(retVal);
            }, 
            false)));
    }
    else if(objToIterate.type == ScriptAny.Type.ARRAY)
    {
        auto elements = objToIterate.toValue!(ScriptAny[]); // @suppress(dscanner.suspicious.unmodified)
        auto generator = new Generator!(Tuple!(size_t, ScriptAny))({
            size_t indexCounter = 0;
            foreach(item ; elements)
            {
                ++indexCounter;
                yield(tuple(indexCounter-1, item));
            }
        });
        vm._stack.push(ScriptAny(new ScriptFunction("next",
            delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError) {
                auto retVal = new ScriptObject("iteration", null, null);
                if(generator.empty)
                {
                    retVal.assignField("done", ScriptAny(true));
                }
                else 
                {
                    auto result = generator.front();
                    retVal.assignField("key", ScriptAny(result[0]));
                    retVal.assignField("value", ScriptAny(result[1]));
                    generator.popFront();
                }
                return ScriptAny(retVal);
            })));
    }
    else if(objToIterate.isNativeObjectType!AbstractArrayBuffer)
    {
        auto aab = objToIterate.toNativeObject!AbstractArrayBuffer; // @suppress(dscanner.suspicious.unmodified)
        if(!aab.isView)
            return throwRuntimeError("Cannot iterate over ArrayBuffer, must convert to view", vm, chunk, ip);
        string PRODUCE_GENERATOR(A)()
        {
            import std.format: format;
            return format(q{
            {
                auto a = cast(%1$s)aab;
                auto generator = new Generator!(Tuple!(size_t, ScriptAny))({
                    size_t indexCounter = 0;
                    foreach(element ; a.data)
                    {
                        yield(tuple(indexCounter, ScriptAny(element)));
                        ++indexCounter;
                    }
                });
                vm._stack.push(ScriptAny(new ScriptFunction("next", 
                delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError){
                    auto retVal = new ScriptObject("iteration", null);
                    if(generator.empty)
                    {
                        retVal.assignField("done", ScriptAny(true));
                    }
                    else
                    {
                        auto result = generator.front();
                        retVal.assignField("key", ScriptAny(result[0]));
                        retVal.assignField("value", ScriptAny(result[1]));
                        generator.popFront();
                    }
                    return ScriptAny(retVal);
                })));
            }
            }, A.stringof);
        }
        final switch(aab.type)
        {
        case AbstractArrayBuffer.Type.ARRAY_BUFFER:
            break; // already handled
        case AbstractArrayBuffer.Type.INT8_ARRAY:
            mixin(PRODUCE_GENERATOR!Int8Array);
            break;
        case AbstractArrayBuffer.Type.UINT8_ARRAY:
            mixin(PRODUCE_GENERATOR!Uint8Array);
            break;
        case AbstractArrayBuffer.Type.INT16_ARRAY:
            mixin(PRODUCE_GENERATOR!Int16Array);
            break;
        case AbstractArrayBuffer.Type.UINT16_ARRAY:
            mixin(PRODUCE_GENERATOR!Uint16Array);
            break;
        case AbstractArrayBuffer.Type.INT32_ARRAY:
            mixin(PRODUCE_GENERATOR!Int32Array);
            break;
        case AbstractArrayBuffer.Type.UINT32_ARRAY:
            mixin(PRODUCE_GENERATOR!Uint32Array);
            break;
        case AbstractArrayBuffer.Type.FLOAT32_ARRAY:
            mixin(PRODUCE_GENERATOR!Float32Array);
            break;
        case AbstractArrayBuffer.Type.FLOAT64_ARRAY:
            mixin(PRODUCE_GENERATOR!Float64Array);
            break;
        case AbstractArrayBuffer.Type.BIGINT64_ARRAY:
            mixin(PRODUCE_GENERATOR!BigInt64Array);
            break;
        case AbstractArrayBuffer.Type.BIGUINT64_ARRAY:
            mixin(PRODUCE_GENERATOR!BigUint64Array);
            break;
        }

        
    }
    else if(objToIterate.isObject)
    {
        if(objToIterate.isNativeObjectType!ScriptGenerator)
        {
            auto func = new ScriptFunction("next", &native_Generator_next, false);
            func.bind(objToIterate);
            vm._stack.push(ScriptAny(func));
        }
        else if(objToIterate.isNativeObjectType!ScriptMap)
        {
            auto map = objToIterate.toNativeObject!ScriptMap;
            auto generator = new Generator!(Tuple!(ScriptAny, ScriptAny))({
                foreach(key, value ; map.entries)
                    yield(tuple(key, value));
            });
            vm._stack.push(ScriptAny(new ScriptFunction("next",
                delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError) {
                    auto retVal = new ScriptObject("iteration", null, null);
                    if(generator.empty)
                    {
                        retVal.assignField("done", ScriptAny(true));
                    }
                    else
                    {
                        auto result = generator.front();
                        retVal.assignField("key", result[0]);
                        retVal.assignField("value", result[1]);
                        generator.popFront();
                    }
                    return ScriptAny(retVal);
                }
            )));
        }
        else
        {
            auto obj = objToIterate.toValue!ScriptObject;
            auto generator = new Generator!(Tuple!(string, ScriptAny))({
                foreach(k, v ; obj.dictionary)
                    yield(tuple(k,v));
            });
            vm._stack.push(ScriptAny(new ScriptFunction("next", 
                delegate ScriptAny(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError){
                    auto retVal = new ScriptObject("iteration", null, null);
                    if(generator.empty)
                    {
                        retVal.assignField("done", ScriptAny(true));
                    }
                    else
                    {
                        auto result = generator.front();
                        retVal.assignField("key", ScriptAny(result[0]));
                        retVal.assignField("value", result[1]);
                        generator.popFront();
                    }
                    return ScriptAny(retVal);
            })));
        }
    }
    return ip + 1;
}

pragma(inline, true)
private size_t opDel(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto memberToDelete = vm._stack.pop().toString();
    auto objToDelete = vm._stack.pop();
    auto obj = objToDelete.toValue!ScriptObject;
    if(obj is null)
        return throwRuntimeError("Cannot delete member of non-object " ~ objToDelete.toString,
            vm, chunk, ip);
    obj.dictionary.remove(memberToDelete);
    return ip + 1;
}

pragma(inline, true)
private size_t opNew(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable n = decode!uint(chunk[ip + 1..$]) + 1;
    auto callInfo = vm._stack.pop(n);
    auto funcAny = callInfo[0];
    auto args = callInfo[1..$];

    if(funcAny.type != ScriptAny.Type.FUNCTION)
        return throwRuntimeError("Unable to instantiate new object from non-function " ~ funcAny.toString(), 
            vm, chunk, ip);
    auto func = funcAny.toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)

    ScriptAny thisObj = new ScriptObject(func.functionName, func["prototype"].toValue!ScriptObject, null);

    try 
    {
        ScriptAny[string] values;
        values["__new"] = ScriptAny(true);
        auto newObject = vm.runFunction(func, thisObj, args, values);
        vm._stack.push(newObject);
    }
    catch(ScriptRuntimeException ex)
    {
        return throwRuntimeError(null, vm, chunk, ip, ex.thrownValue, ex);
    }

    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opThis(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    bool _; // @suppress(dscanner.suspicious.unmodified)
    auto thisPtr = vm._environment.lookupVariableOrConst("this", _);
    if(thisPtr == null)
        vm._stack.push(ScriptAny.UNDEFINED);
    else
        vm._stack.push(*thisPtr);
    return ip + 1;
}

pragma(inline, true)
private size_t opOpenScope(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._environment = new Environment(vm._environment);
    // debug writefln("Opening environment from parent %s", vm._environment.parent);
    // debug writefln("VM{ environment depth=%s", vm._environment.depth);
    return ip + 1;
}

pragma(inline, true)
private size_t opCloseScope(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._environment = vm._environment.parent;
    // debug writefln("Closing environment: %s", vm._environment);
    // debug writefln("VM} environment depth=%s", vm._environment.depth);
    return ip + 1;
}

pragma(inline, true)
private size_t opDeclVar(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto constID = decode!uint(chunk[ip + 1..$]);
    auto varName = vm._latestConstTable.get(constID).toString();
    auto value = vm._stack.pop();
    immutable ok = vm._globals.declareVariableOrConst(varName, value, false);
    if(!ok)
        return throwRuntimeError("Cannot redeclare global " ~ varName, vm, chunk, ip);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opDeclLet(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto constID = decode!uint(chunk[ip + 1..$]);
    auto varName = vm._latestConstTable.get(constID).toString();
    auto value = vm._stack.pop();
    immutable ok = vm._environment.declareVariableOrConst(varName, value, false);
    if(!ok)
        return throwRuntimeError("Cannot redeclare local " ~ varName, vm, chunk, ip);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opDeclConst(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto constID = decode!uint(chunk[ip + 1..$]);
    auto varName = vm._latestConstTable.get(constID).toString();
    auto value = vm._stack.pop();
    immutable ok = vm._environment.declareVariableOrConst(varName, value, true);
    if(!ok)
        return throwRuntimeError("Cannot redeclare const " ~ varName, vm, chunk, ip);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opGetVar(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto constID = decode!uint(chunk[ip + 1..$]);   
    auto varName = vm._latestConstTable.get(constID).toString();
    bool isConst; // @suppress(dscanner.suspicious.unmodified)
    auto valuePtr = vm._environment.lookupVariableOrConst(varName, isConst);
    if(valuePtr == null)
        return throwRuntimeError("Variable lookup failed: " ~ varName, vm, chunk, ip);
    vm._stack.push(*valuePtr);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opSetVar(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto constID = decode!uint(chunk[ip + 1..$]);
    auto varName = vm._latestConstTable.get(constID).toString();
    bool isConst; // @suppress(dscanner.suspicious.unmodified)
    auto varPtr = vm._environment.lookupVariableOrConst(varName, isConst);
    if(varPtr == null)
    {
        // maybe someday this will be the only way to declare globals
        return throwRuntimeError("Cannot assign to undefined variable: " ~ varName, vm, chunk, ip);
    }
    auto value = vm._stack.peek(); // @suppress(dscanner.suspicious.unmodified)
    if(value == ScriptAny.UNDEFINED)
        vm._environment.unsetVariable(varName);
    else
        *varPtr = value;
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opObjGet(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    import std.utf: UTFException;

    auto objToAccess = vm._stack.array[$-2];
    auto field = vm._stack.array[$-1]; // @suppress(dscanner.suspicious.unmodified)
    vm._stack.pop(2);
    // TODO handle getters
    // if field is integer it is array access
    if(field.isNumber 
      && (objToAccess.type == ScriptAny.Type.ARRAY || objToAccess.type == ScriptAny.Type.STRING
        || objToAccess.isNativeObjectType!AbstractArrayBuffer))
    {
        auto index = field.toValue!long;
        if(objToAccess.type == ScriptAny.Type.ARRAY)
        {
            auto arr = objToAccess.toValue!(ScriptAny[]);
            if(index < 0)
                index = arr.length + index;
            if(index < 0 || index >= arr.length)
                return throwRuntimeError("Out of bounds array access", vm, chunk, ip);
            vm._stack.push(arr[index]);
        }
        else if(objToAccess.type == ScriptAny.Type.STRING)
        {
            auto str = objToAccess.toValue!(ScriptString)().toString();
            if(index < 0)
                index = str.length + index;
            if(index < 0 || index >= str.length)
                return throwRuntimeError("Out of bounds string access", vm, chunk, ip);
            try 
            {
                vm._stack.push(ScriptAny([str[index]]));
            }
            catch(UTFException)
            {
                vm._stack.push(ScriptAny.UNDEFINED);
            }
        }
        else
        {
            auto aab = objToAccess.toNativeObject!AbstractArrayBuffer;
            immutable realIndex = aab.getIndex(index);
            if(!aab.isView)
                return throwRuntimeError("ArrayBuffer cannot be indexed directly, convert to view",
                    vm, chunk, ip);
            if(realIndex == -1)
                return throwRuntimeError("Buffer out of bounds array index", vm, chunk, ip);
            final switch(aab.type)
            {
            case AbstractArrayBuffer.Type.ARRAY_BUFFER:
                break; // already handled
            case AbstractArrayBuffer.Type.INT8_ARRAY:
                vm._stack.push(ScriptAny((cast(Int8Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.UINT8_ARRAY:
                vm._stack.push(ScriptAny((cast(Uint8Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.INT16_ARRAY:
                vm._stack.push(ScriptAny((cast(Int16Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.UINT16_ARRAY:
                vm._stack.push(ScriptAny((cast(Uint16Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.INT32_ARRAY:
                vm._stack.push(ScriptAny((cast(Int32Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.UINT32_ARRAY:
                vm._stack.push(ScriptAny((cast(Uint32Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.FLOAT32_ARRAY:
                vm._stack.push(ScriptAny((cast(Float32Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.FLOAT64_ARRAY:
                vm._stack.push(ScriptAny((cast(Float64Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.BIGINT64_ARRAY:
                vm._stack.push(ScriptAny((cast(BigInt64Array)aab).data[realIndex]));
                break;
            case AbstractArrayBuffer.Type.BIGUINT64_ARRAY:
                vm._stack.push(ScriptAny((cast(BigUint64Array)aab).data[realIndex]));
                break;
            }
        }
    }
    else // else object field or property access
    {
        auto index = field.toString();
        if(objToAccess.isObject)
        {
            auto obj = objToAccess.toValue!ScriptObject; // @suppress(dscanner.suspicious.unmodified)
            auto getter = obj.findGetter(index);
            if(getter)
            {
                // this might be a super property call
                auto thisObj = getLocalThis(vm._environment);
                ScriptAny retVal;
                try 
                {
                    if(ScriptFunction.isInstanceOf(thisObj.toValue!ScriptObject, 
                    objToAccess["constructor"].toValue!ScriptFunction))
                    {
                        retVal = vm.runFunction(getter, thisObj, []);
                    }
                    else
                    {
                        retVal = vm.runFunction(getter, objToAccess, []);
                    }
                    vm._stack.push(retVal);
                }
                catch(ScriptRuntimeException ex)
                {
                    return throwRuntimeError(null, vm, chunk, ip, ex.thrownValue, ex);
                }
            }
            else
                vm._stack.push(objToAccess[index]);
        }
        else
            return throwRuntimeError("Unable to access member " ~ index ~ " of non-object " ~ objToAccess.toString(),
                    vm, chunk, ip);
    }
    return ip + 1;
}

pragma(inline, true)
private size_t opObjSet(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto objToAccess = vm._stack.array[$-3];
    auto fieldToAssign = vm._stack.array[$-2]; // @suppress(dscanner.suspicious.unmodified)
    auto value = vm._stack.array[$-1];
    vm._stack.pop(3);
    if(fieldToAssign.isNumber 
      && (objToAccess.type == ScriptAny.Type.ARRAY || objToAccess.type == ScriptAny.Type.STRING
        || objToAccess.isNativeObjectType!AbstractArrayBuffer))
    {
        auto index = fieldToAssign.toValue!long;
        if(objToAccess.type == ScriptAny.Type.ARRAY)
        {
            auto arr = objToAccess.toValue!(ScriptAny[]);
            if(index < 0)
                index = arr.length + index;
            if(index < 0 || index >= arr.length)
                return throwRuntimeError("Out of bounds array assignment", vm, chunk, ip);
            arr[index] = value;
            vm._stack.push(value);
        }
        else if(objToAccess.type == ScriptAny.Type.STRING)
        {
            return throwRuntimeError("Cannot assign index to strings", vm, chunk, ip);
        }
        else 
        {
            auto aab = objToAccess.toNativeObject!AbstractArrayBuffer;
            index = aab.getIndex(index);
            if(!aab.isView)
                return throwRuntimeError("ArrayBuffer must be converted to view", vm, chunk, ip);
                    else
            if(index == -1)
                return throwRuntimeError("Buffer out of bounds array index", vm, chunk, ip);
            final switch(aab.type)
            {
            case AbstractArrayBuffer.Type.ARRAY_BUFFER:
                break; // already handled
            case AbstractArrayBuffer.Type.INT8_ARRAY:
                vm._stack.push(ScriptAny((cast(Int8Array)aab).data[index] = value.toValue!byte));
                break;
            case AbstractArrayBuffer.Type.UINT8_ARRAY:
                vm._stack.push(ScriptAny((cast(Uint8Array)aab).data[index] = value.toValue!ubyte));
                break;
            case AbstractArrayBuffer.Type.INT16_ARRAY:
                vm._stack.push(ScriptAny((cast(Int16Array)aab).data[index] = value.toValue!short));
                break;
            case AbstractArrayBuffer.Type.UINT16_ARRAY:
                vm._stack.push(ScriptAny((cast(Uint16Array)aab).data[index] = value.toValue!ushort));
                break;
            case AbstractArrayBuffer.Type.INT32_ARRAY:
                vm._stack.push(ScriptAny((cast(Int32Array)aab).data[index] = value.toValue!int));
                break;
            case AbstractArrayBuffer.Type.UINT32_ARRAY:
                vm._stack.push(ScriptAny((cast(Uint32Array)aab).data[index] = value.toValue!uint));
                break;
            case AbstractArrayBuffer.Type.FLOAT32_ARRAY:
                vm._stack.push(ScriptAny((cast(Float32Array)aab).data[index] = value.toValue!float));
                break;
            case AbstractArrayBuffer.Type.FLOAT64_ARRAY:
                vm._stack.push(ScriptAny((cast(Float64Array)aab).data[index] = value.toValue!double));
                break;
            case AbstractArrayBuffer.Type.BIGINT64_ARRAY:
                vm._stack.push(ScriptAny((cast(BigInt64Array)aab).data[index] = value.toValue!long));
                break;
            case AbstractArrayBuffer.Type.BIGUINT64_ARRAY:
                vm._stack.push(ScriptAny((cast(BigUint64Array)aab).data[index] = value.toValue!ulong));
                break;
            }
        }
    }
    else
    {
        auto index = fieldToAssign.toValue!string;
        if(!objToAccess.isObject)
            return throwRuntimeError("Unable to assign member " ~ index ~ " of non-object " 
                ~ objToAccess.toString(), vm, chunk, ip);
        auto obj = objToAccess.toValue!ScriptObject; // @suppress(dscanner.suspicious.unmodified)
        auto setter = obj.findSetter(index);
        if(setter)
        {
            auto thisObj = getLocalThis(vm._environment);
            immutable isSuperProp = ScriptFunction.isInstanceOf(thisObj.toValue!ScriptObject, 
                    objToAccess["constructor"].toValue!ScriptFunction);
            try 
            {
                if(isSuperProp)
                    vm.runFunction(setter, thisObj, [value]);
                else
                    vm.runFunction(setter, objToAccess, [value]);
                // if getter push that or else undefined
                auto getter = obj.findGetter(index);
                if(getter)
                {
                    if(isSuperProp)
                        vm._stack.push(vm.runFunction(getter, thisObj, []));
                    else
                        vm._stack.push(vm.runFunction(getter, objToAccess, []));
                }
                else
                {
                    vm._stack.push(ScriptAny.UNDEFINED);
                }
            }
            catch(ScriptRuntimeException ex)
            {
                return throwRuntimeError(null, vm, chunk, ip, ex.thrownValue, ex);
            }
        }
        else
        {
            if(obj.hasGetter(index))
                return throwRuntimeError("Object " ~ obj.toString() ~ " has getter for property "
                    ~ index ~ " but no setter.", vm, chunk, ip);
            objToAccess[index] = value;
            vm._stack.push(value);
        }
    }
    return ip + 1;
}

pragma(inline, true)
private size_t opCall(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable n = decode!uint(chunk[ip + 1..$]) + 2;
    if(vm._stack.size < n)
    {
        vm.printStack();
        throw new VMException("opCall failure, stack < " ~ n.to!string, ip, OpCode.CALL);
    }
    auto callInfo = vm._stack.pop(n);
    auto thisObj = callInfo[0]; // @suppress(dscanner.suspicious.unmodified)
    auto funcAny = callInfo[1];
    auto args = callInfo[2..$];
    if(funcAny.type != ScriptAny.Type.FUNCTION)
        return throwRuntimeError("Unable to call non-function " ~ funcAny.toString(), vm, chunk, ip);
    auto func = funcAny.toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)
    if(func.isGenerator)
    {
        ScriptObject newGen = new ScriptObject("Generator", getGeneratorPrototype,
            new ScriptGenerator(vm._environment, func, args, thisObj));
        vm._stack.push(ScriptAny(newGen));
        return ip + 1 + uint.sizeof;
    }

    try 
    {
        vm._stack.push(vm.runFunction(func, thisObj, args, null));
        if(vm._exc) // flag could be set by Generator
            return throwRuntimeError(null, vm, chunk, ip, vm._exc.thrownValue, vm._exc);
    }
    catch(ScriptRuntimeException ex)
    {
        return throwRuntimeError(null, vm, chunk, ip, ex.thrownValue, ex);
    }

    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opJmpFalse(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable jmpAmount = decode!int(chunk[ip + 1..$]);
    immutable shouldJump = vm._stack.pop();
    if(!shouldJump)
        return ip + jmpAmount;
    else
        return ip + 1 + int.sizeof;
}

pragma(inline, true)
private size_t opJmp(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable jmpAmount = decode!int(chunk[ip + 1..$]);
    return ip + jmpAmount;
}

pragma(inline, true)
private size_t opSwitch(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable relAbsJmp = decode!uint(chunk[ip + 1..$]);
    auto valueToTest = vm._stack.pop();
    auto jumpTableArray = vm._stack.pop();
    // build the jump table out of the entries
    if(jumpTableArray.type != ScriptAny.Type.ARRAY)
        throw new VMException("Invalid jump table", ip, OpCode.SWITCH);
    int[ScriptAny] jmpTable;
    foreach(entry ; jumpTableArray.toValue!(ScriptAny[]))
    {
        if(entry.type != ScriptAny.Type.ARRAY)
            throw new VMException("Invalid jump table entry", ip, OpCode.SWITCH);
        auto entryArray = entry.toValue!(ScriptAny[]);
        if(entryArray.length < 2)
            throw new VMException("Invalid jump table entry size", ip, OpCode.SWITCH);
        jmpTable[entryArray[0]] = entryArray[1].toValue!int;
    }
    if(valueToTest in jmpTable)
        return jmpTable[valueToTest];
    else
        return relAbsJmp;
}

pragma(inline, true)
private size_t opGoto(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable address = decode!uint(chunk[ip + 1..$]);
    immutable depth = decode!ubyte(chunk[ip+1+uint.sizeof..$]);
    for(ubyte i = 0; i < depth; ++i)
    {
        vm._environment = vm._environment.parent;
    }
    return address;
}

pragma(inline, true)
private size_t opThrow(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto valToThrow = vm._stack.pop();
    return throwRuntimeError("Uncaught script exception", vm, chunk, ip, valToThrow);
}

pragma(inline, true)
private size_t opRethrow(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    if(vm._exc)
        return throwRuntimeError(vm._exc.msg, vm, chunk, ip, vm._exc.thrownValue, vm._exc);
    return ip + 1;
}

pragma(inline, true)
private size_t opTry(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable catchGoto = decode!uint(chunk[ip + 1..$]);
    immutable depth = cast(int)vm._environment.depth();
    vm._tryData ~= VirtualMachine.TryData(depth, vm._stack.size, catchGoto);
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opEndTry(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._tryData = vm._tryData[0..$-1];
    return ip + 1;
}

pragma(inline, true)
private size_t opLoadExc(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    if(vm._exc is null)
        throw new VMException("An exception was never thrown", ip, OpCode.LOADEXC);
    if(vm._exc.thrownValue != ScriptAny.UNDEFINED)
        vm._stack.push(vm._exc.thrownValue);
    else
        vm._stack.push(ScriptAny(vm._exc.msg));
    vm._exc = null; // once loaded by a catch block it should be cleared
    return ip + 1;
}

pragma(inline, true)
private size_t opConcat(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    immutable n = decode!uint(chunk[ip + 1..$]);
    string result = "";
    auto values = vm._stack.pop(n);
    foreach(value ; values)
        result ~= value.toString();
    vm._stack.push(ScriptAny(result));
    return ip + 1 + uint.sizeof;
}

pragma(inline, true)
private size_t opBitNot(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.array[$-1] = ~vm._stack.array[$-1];
    return ip + 1;
}

pragma(inline, true)
private size_t opNot(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.array[$-1] = ScriptAny(!vm._stack.array[$-1]);
    return ip + 1;
}

pragma(inline, true)
private size_t opNegate(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.array[$-1] = -vm._stack.array[$-1];
    return ip + 1;
}

pragma(inline, true)
private size_t opTypeof(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stack.array[$-1] = ScriptAny(vm._stack.array[$-1].typeToString());
    return ip + 1;
}

pragma(inline, true)
private size_t opInstanceOf(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto operands = vm._stack.pop(2);
    if(!operands[0].isObject)
        vm._stack.push(ScriptAny(false));
    else if(operands[1].type != ScriptAny.Type.FUNCTION)
        vm._stack.push(ScriptAny(false));
    else
    {
        auto lhsObj = operands[0].toValue!ScriptObject; // @suppress(dscanner.suspicious.unmodified)
        auto rhsFunc = operands[1].toValue!ScriptFunction; // @suppress(dscanner.suspicious.unmodified)
        auto proto = lhsObj.prototype;
        while(proto !is null)
        {
            if(proto["constructor"].toValue!ScriptFunction is rhsFunc)
            {
                vm._stack.push(ScriptAny(true));
                return ip + 1;
            }
            proto = proto.prototype;
        }
    }
    vm._stack.push(ScriptAny(false));
    return ip + 1;
}

private string DEFINE_BIN_OP(string name, string op)()
{
    import std.format: format;
    return format(q{
pragma(inline, true)
private size_t %1$s(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto operands = vm._stack.pop(2);
    vm._stack.push(operands[0] %2$s operands[1]);
    return ip + 1;
}
    }, name, op);
}

mixin(DEFINE_BIN_OP!("opPow", "^^"));
mixin(DEFINE_BIN_OP!("opMul", "*"));
mixin(DEFINE_BIN_OP!("opDiv", "/"));
mixin(DEFINE_BIN_OP!("opMod", "%"));
mixin(DEFINE_BIN_OP!("opAdd", "+"));
mixin(DEFINE_BIN_OP!("opSub", "-"));
mixin(DEFINE_BIN_OP!("opBitRSh", ">>"));
mixin(DEFINE_BIN_OP!("opBitURSh", ">>>"));
mixin(DEFINE_BIN_OP!("opBitLSh", "<<"));

private string DEFINE_BIN_BOOL_OP(string name, string op)()
{
    import std.format: format;
    return format(q{
pragma(inline, true)
private size_t %1$s(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto operands = vm._stack.pop(2);
    vm._stack.push(ScriptAny(operands[0] %2$s operands[1]));
    return ip + 1;
}
    }, name, op);
}

mixin(DEFINE_BIN_BOOL_OP!("opLT", "<"));
mixin(DEFINE_BIN_BOOL_OP!("opLE", "<="));
mixin(DEFINE_BIN_BOOL_OP!("opGT", ">"));
mixin(DEFINE_BIN_BOOL_OP!("opGE", ">="));
mixin(DEFINE_BIN_BOOL_OP!("opEQ", "=="));
mixin(DEFINE_BIN_BOOL_OP!("opNEQ", "!="));

pragma(inline, true)
private size_t opStrictEquals(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto operands = vm._stack.pop(2);
    vm._stack.push(ScriptAny(operands[0].strictEquals(operands[1])));
    return ip + 1;
}

pragma(inline, true)
private size_t opNotStrictEquals(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    auto operands = vm._stack.pop(2);
    vm._stack.push(ScriptAny(!operands[0].strictEquals(operands[1])));
    return ip + 1;
}


mixin(DEFINE_BIN_OP!("opBitAnd", "&"));
mixin(DEFINE_BIN_OP!("opBitOr", "|"));
mixin(DEFINE_BIN_OP!("opBitXor", "^"));

pragma(inline, true)
private size_t opReturn(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    throw new VMException("opReturn should never be called directly", ip, OpCode.RETURN);
}

pragma(inline, true)
private size_t opHalt(VirtualMachine vm, const ubyte[] chunk, size_t ip)
{
    vm._stopped = true;
    return ip + 1;
}

/**
 * This class implements a virtual machine that runs Chunks of bytecode. This class is not thread
 * safe and a copy() of the VM should be instantiated to run scripts in multiple threads. The
 * Environments are shallow copied and not guaranteed to be thread safe either.
 */
class VirtualMachine
{
    /// ctor
    this(Environment globalEnv, bool printDisasm = false, bool printSteps = false)
    {
        _environment = globalEnv;
        _globals = globalEnv;
        _printDisassembly = printDisasm;
        _printSteps = printSteps;
        _ops[] = &opNop;
        _ops[OpCode.CONST] = &opConst;
        _ops[OpCode.CONST_0] = &opConst0;
        _ops[OpCode.CONST_1] = &opConst1;
        _ops[OpCode.PUSH] = &opPush;
        _ops[OpCode.POP] = &opPop;
        _ops[OpCode.POPN] = &opPopN;
        _ops[OpCode.SET] = &opSet;
        _ops[OpCode.STACK] = &opStack;
        _ops[OpCode.STACK_1] = &opStack1;
        _ops[OpCode.ARRAY] = &opArray;
        _ops[OpCode.OBJECT] = &opObject;
        _ops[OpCode.CLASS] = &opClass;
        _ops[OpCode.REGEX] = &opRegex;
        _ops[OpCode.ITER] = &opIter;
        _ops[OpCode.DEL] = &opDel;
        _ops[OpCode.NEW] = &opNew;
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
        _ops[OpCode.SWITCH] = &opSwitch;
        _ops[OpCode.GOTO] = &opGoto;
        _ops[OpCode.THROW] = &opThrow;
        _ops[OpCode.RETHROW] = &opRethrow;
        _ops[OpCode.TRY] = &opTry;
        _ops[OpCode.ENDTRY] = &opEndTry;
        _ops[OpCode.LOADEXC] = &opLoadExc;
        _ops[OpCode.CONCAT] = &opConcat;
        _ops[OpCode.BITNOT] = &opBitNot;
        _ops[OpCode.NOT] = &opNot;
        _ops[OpCode.NEGATE] = &opNegate;
        _ops[OpCode.TYPEOF] = &opTypeof;
        _ops[OpCode.INSTANCEOF] = &opInstanceOf;
        _ops[OpCode.POW] = &opPow;
        _ops[OpCode.MUL] = &opMul;
        _ops[OpCode.DIV] = &opDiv;
        _ops[OpCode.MOD] = &opMod;
        _ops[OpCode.ADD] = &opAdd;
        _ops[OpCode.SUB] = &opSub;
        _ops[OpCode.BITRSH] = &opBitRSh;
        _ops[OpCode.BITURSH] = &opBitURSh;
        _ops[OpCode.BITLSH] = &opBitLSh;
        _ops[OpCode.LT] = &opLT;
        _ops[OpCode.LE] = &opLE;
        _ops[OpCode.GT] = &opGT;
        _ops[OpCode.GE] = &opGE;
        _ops[OpCode.EQUALS] = &opEQ;
        _ops[OpCode.NEQUALS] = &opNEQ;
        _ops[OpCode.STREQUALS] = &opStrictEquals;
        _ops[OpCode.NSTREQUALS] = &opNotStrictEquals;
        _ops[OpCode.BITAND] = &opBitAnd;
        _ops[OpCode.BITOR] = &opBitOr;
        _ops[OpCode.BITXOR] = &opBitXor;
        _ops[OpCode.RETURN] = &opReturn;
        _ops[OpCode.HALT] = &opHalt;
        _stack.reserve(64); // TODO tweak this number as necessary
    }

    /// Sets the exception flag of the VM. This is checked after each opCall for Generators
    package(mildew) void setException(ScriptRuntimeException ex)
    {
        _exc = ex;
    }

    /// print a program instruction by instruction, using the const table to indicate values
    void printProgram(Program program, bool printConstTable=false)
    {
        if(printConstTable)
        {
            writeln("===== CONST TABLE =====");
            foreach(index, value ; program.constTable)
            {
                writef("#%s: ", index);
                if(value.type == ScriptAny.Type.FUNCTION)
                {
                    auto fn = value.toValue!ScriptFunction;
                    writeln("<function> " ~ fn.functionName);
                    auto funcProgram = new Program(program.constTable, fn);
                    printProgram(funcProgram, false);
                }
                else
                {
                    write("<" ~ value.typeToString() ~ "> ");
                    if(value.toString().length < 100)
                        writeln(value.toString());
                    else
                        writeln();
                }
            }
        }
        if(printConstTable)
            writeln("===== DISASSEMBLY =====");
        size_t ip = 0;
        while(ip < program.mainFunction.compiled.length)
        {
            auto op = cast(OpCode)program.mainFunction.compiled[ip];
            printInstruction(ip, program.mainFunction.compiled);
            switch(op)
            {
            case OpCode.NOP:
                ++ip;
                break;
            case OpCode.CONST:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.CONST_0:
            case OpCode.CONST_1:
                ++ip;
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
            case OpCode.STACK:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.STACK_1:
                ++ip;
                break;
            case OpCode.ARRAY:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.OBJECT:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.CLASS:
                ip += 1 + 4 * ubyte.sizeof;
                break;
            case OpCode.ITER:
            case OpCode.DEL:
                ++ip;
                break;
            case OpCode.NEW:
                ip += 1 + uint.sizeof;
                break;
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
            case OpCode.SWITCH:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.GOTO:
                ip += 1 + uint.sizeof + ubyte.sizeof;
                break;
            case OpCode.THROW:
            case OpCode.RETHROW:
                ++ip;
                break;
            case OpCode.TRY:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.ENDTRY:
            case OpCode.LOADEXC:
                ++ip;
                break;
            case OpCode.CONCAT:
                ip += 1 + uint.sizeof;
                break;
            case OpCode.BITNOT:
            case OpCode.NOT:
            case OpCode.NEGATE:
            case OpCode.TYPEOF:
            case OpCode.INSTANCEOF:
            case OpCode.POW:
            case OpCode.MUL:
            case OpCode.DIV:
            case OpCode.MOD:
            case OpCode.ADD:
            case OpCode.SUB:
            case OpCode.LT:
            case OpCode.LE:
            case OpCode.GT:
            case OpCode.GE:
            case OpCode.EQUALS:
            case OpCode.NEQUALS:
            case OpCode.STREQUALS:
            case OpCode.NSTREQUALS:
            case OpCode.BITAND:
            case OpCode.BITOR:
            case OpCode.BITXOR:
                ++ip;
                break;
            case OpCode.RETURN:
            case OpCode.HALT:
                ++ip;
                break;
            default:
                ++ip;
            }
        }
        writeln("=======================");
    }

    /// prints an individual instruction without moving the ip
    void printInstruction(in size_t ip, const ubyte[] chunk)
    {
        auto op = cast(OpCode)chunk[ip];
        switch(op)
        {
        case OpCode.NOP:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.CONST: {
            immutable constID = decode!uint(chunk[ip + 1..$]);
            printInstructionWithConstID(ip, op, constID, _latestConstTable);
            break;
        }
        case OpCode.CONST_0:
        case OpCode.CONST_1:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.PUSH: {
            immutable index = decode!int(chunk[ip + 1..$]);
            writefln("%05d: %s index=%s", ip, op.opCodeToString, index);
            break;
        }
        case OpCode.POP:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.POPN: {
            immutable amount = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s amount=%s", ip, op.opCodeToString, amount);
            break;
        }
        case OpCode.SET: {
            immutable index = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s index=%s", ip, op.opCodeToString, index);
            break;
        }
        case OpCode.STACK: {
            immutable n = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s n=%s", ip, op.opCodeToString, n);
            break;
        }
        case OpCode.STACK_1:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.ARRAY: {
            immutable n = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s n=%s", ip, op.opCodeToString, n);
            break;
        }
        case OpCode.OBJECT: {
            immutable n = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s n=%s", ip, op.opCodeToString, n);
            break;
        }
        case OpCode.CLASS: {
            immutable numMethods = decode!ubyte(chunk[ip + 1..$]);
            immutable numGetters = decode!ubyte(chunk[ip + 2..$]);
            immutable numSetters = decode!ubyte(chunk[ip + 3..$]);
            immutable numStatics = decode!ubyte(chunk[ip + 4..$]);
            writefln("%05d: %s %s,%s,%s,%s", ip, op.opCodeToString, numMethods, numGetters, numSetters, numStatics);
            break;
        }
        case OpCode.ITER:
        case OpCode.DEL:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.NEW: {
            immutable args = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s args=%s", ip, op.opCodeToString, args);
            break;
        }
        case OpCode.THIS:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.OPENSCOPE:
        case OpCode.CLOSESCOPE:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.DECLVAR: 
        case OpCode.DECLLET:
        case OpCode.DECLCONST: {
            immutable constID = decode!uint(chunk[ip + 1..$]);
            printInstructionWithConstID(ip, op, constID, _latestConstTable);
            break;
        }
        case OpCode.GETVAR:
        case OpCode.SETVAR: {
            immutable constID = decode!uint(chunk[ip + 1..$]);
            printInstructionWithConstID(ip, op, constID, _latestConstTable);
            break;
        }
        case OpCode.OBJSET:
        case OpCode.OBJGET:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.CALL: {
            immutable args = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s args=%s", ip, op.opCodeToString, args);
            break;
        }
        case OpCode.JMPFALSE: 
        case OpCode.JMP: {
            immutable jump = decode!int(chunk[ip + 1..$]);
            writefln("%05d: %s jump=%s", ip, op.opCodeToString, jump);
            break;
        }
        case OpCode.SWITCH: {
            immutable def = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s default=%s", ip, op.opCodeToString, def);
            break;
        }
        case OpCode.GOTO: {
            immutable instruction = decode!uint(chunk[ip + 1..$]);
            immutable depth = decode!ubyte(chunk[ip + 1 + uint.sizeof..$]);
            writefln("%05d: %s instruction=%s, depth=%s", ip, op.opCodeToString, instruction, depth);
            break;
        }
        case OpCode.THROW:
        case OpCode.RETHROW:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.TRY: {
            immutable catchGoto = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s catch=%s", ip, op.opCodeToString, catchGoto);
            break;
        }
        case OpCode.ENDTRY:
        case OpCode.LOADEXC:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.CONCAT: {
            immutable n = decode!uint(chunk[ip + 1..$]);
            writefln("%05d: %s n=%s", ip, op.opCodeToString, n);
            break;
        }
        case OpCode.BITNOT:
        case OpCode.NOT:
        case OpCode.NEGATE:
        case OpCode.TYPEOF:
        case OpCode.INSTANCEOF:
        case OpCode.POW:
        case OpCode.MUL:
        case OpCode.DIV:
        case OpCode.MOD:
        case OpCode.ADD:
        case OpCode.SUB:
        case OpCode.LT:
        case OpCode.LE:
        case OpCode.GT:
        case OpCode.GE:
        case OpCode.EQUALS:
        case OpCode.NEQUALS:
        case OpCode.STREQUALS:
        case OpCode.NSTREQUALS:
        case OpCode.BITAND:
        case OpCode.BITOR:
        case OpCode.BITXOR:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        case OpCode.RETURN:
        case OpCode.HALT:
            writefln("%05d: %s", ip, op.opCodeToString);
            break;
        default:
            writefln("%05d: ??? (%s)", ip, cast(ubyte)op);
        }  
    }

    /// print the current contents of the stack
    void printStack()
    {
        write("Stack: [");
        for(size_t i = 0; i < _stack.size; ++i)
        {
            if(_stack.array[i].type == ScriptAny.Type.STRING)
            {
                auto str = _stack.array[i].toString();
                if(str.length < 100)
                    write("\"" ~ str ~ "\"");
                else
                    write("[string too long to display]");
            }
            else if(_stack.array[i].type == ScriptAny.Type.ARRAY)
            {
                immutable arrLen = _stack.array[i].toValue!(ScriptAny[]).length;
                if(arrLen < 100)
                    write(_stack.array[i].toString());
                else
                    write("[array too long to display]");
            }
            else
            {
                write(_stack.array[i].toString());
            }
            if(i < _stack.size - 1)
                write(", ");
        }
        writeln("]");
    }

    /// Runs a compiled program
    ScriptAny runProgram(Program program, ScriptAny[] args)
    {
        _exc = null;
        _stopped = false;
        auto prevConstTable = _latestConstTable; // @suppress(dscanner.suspicious.unmodified)
        _latestConstTable = program.constTable;
        auto prevDebugMap = _latestDebugMap; // @suppress(dscanner.suspicious.unmodified)
        _latestDebugMap = program.debugMap;
        auto oldEnv = _environment; // @suppress(dscanner.suspicious.unmodified)
        _environment = new Environment(_environment, program.mainFunction.functionName);
        debug if(_printDisassembly)
            printProgram(program, true);
        try 
        {
            return runFunction(program.mainFunction, ScriptAny.UNDEFINED, args, null);
        }
        finally 
        {
            // leave them non-null for async loop
            if(prevConstTable)
                _latestConstTable = prevConstTable;
            if(prevDebugMap)
                _latestDebugMap = prevDebugMap;
            _environment = oldEnv;
        }
    }

    /**
     * This method provides a common interface for calling any ScriptFunction under the same
     * compilation unit as the initial program. It should not be used to run "foreign" functions
     * with a different const table. Use runProgram for that. This method may throw ScriptRuntimeException. Such
     * an exception is caught at opNew and opCall boundaries and propagated or caught by the script.
     * Params:
     *  func = The function to be run.
     *  thisObj = The "this" object to be used.
     *  args = The arguments to be passed to the function. If this is a SCRIPT_FUNCTION the arguments
     *         will be set up by this method.
     *  contextValues = Special meaning variables that are added to the SCRIPT_FUNCTION environment. For example,
     *      \_\_new:true means that a modified thisObj will be returned. \_\_yield\_\_:yieldFunc is used for Generator
     *      functions.
     * Returns:
     *   The return value of the function if an exception is not thrown in most cases (see contextValues).
     */
    ScriptAny runFunction(ScriptFunction func, ScriptAny thisObj, ScriptAny[] args, 
                          ScriptAny[string] contextValues=null)
    {
        ScriptAny retVal;
        NativeFunctionError nfe = NativeFunctionError.NO_ERROR;
        if(func.boundThis != ScriptAny.UNDEFINED)
            thisObj = func.boundThis;
        final switch(func.type)
        {
        case ScriptFunction.Type.SCRIPT_FUNCTION: {
            auto oldEnv = _environment; // @suppress(dscanner.suspicious.unmodified)
            _environment = func.closure is null ? 
                new Environment(_environment, func.functionName) :
                new Environment(func.closure, func.functionName);
            auto oldTrys = _tryData; // @suppress(dscanner.suspicious.unmodified)
            _tryData = [];
            immutable oldStack = _stack.size();
            _environment.forceSetVarOrConst("this", thisObj, false);
            _environment.forceSetVarOrConst("arguments", ScriptAny(args), false);
            for(size_t i = 0; i < func.argNames.length; ++i)
            {
                if(i < args.length)
                    _environment.forceSetVarOrConst(func.argNames[i], args[i], false);
                else
                    _environment.forceSetVarOrConst(func.argNames[i], ScriptAny.UNDEFINED, false);
            }
            foreach(name, value ; contextValues)
                _environment.forceSetVarOrConst(name, value, true);
            try 
            {
                retVal = runBytecode(func.compiled);
                if("__new" in contextValues)
                    return thisObj;
                else
                    return retVal;
            }
            finally 
            {
                _environment = oldEnv;
                _tryData = oldTrys;
                _stack.size = oldStack;
            }
        }
        case ScriptFunction.Type.NATIVE_FUNCTION:
            retVal = func.nativeFunction()(_environment, &thisObj, args, nfe);
            break;
        case ScriptFunction.Type.NATIVE_DELEGATE:
            retVal = func.nativeDelegate()(_environment, &thisObj, args, nfe);
            break;
        }

        final switch(nfe)
        {
        case NativeFunctionError.NO_ERROR:
            break;
        case NativeFunctionError.WRONG_NUMBER_OF_ARGS:
            throwNativeRuntimeError("Wrong number of arguments to " ~ func.functionName, this);
            break;
        case NativeFunctionError.WRONG_TYPE_OF_ARG:
            throwNativeRuntimeError("Wrong type of argument to " ~ func.functionName, this);
            break;
        case NativeFunctionError.RETURN_VALUE_IS_EXCEPTION:
            throwNativeRuntimeError("Native exception", this, retVal);
        }
        if("__new" in contextValues)
            return thisObj;
        else
            return retVal;
    }

    private ScriptAny runBytecode(const ubyte[] chunk)
    {
        size_t ip = 0;
        ubyte op;
        while(ip < chunk.length && !_stopped)
        {
            op = chunk[ip];
            if(op == OpCode.RETURN)
                return _stack.pop();
            if(_printSteps)
                printInstruction(ip, chunk);
            ip = _ops[op](this, chunk, ip);
            if(_printSteps)
                printStack();
        }
        debug writeln("Warning: missing return op");
        return ScriptAny.UNDEFINED;
    }

    /**
     * For coroutines (and in the future threads.)
     */
    VirtualMachine copy(bool copyStack = false)
    {
        auto vm = new VirtualMachine(_globals, _printDisassembly, _printSteps);
        vm._environment = _environment;
        vm._latestConstTable = _latestConstTable;
        if(copyStack)
            vm._stack = _stack;
        return vm;
    }

    /// Get the last value from opPop
    ScriptAny lastValuePopped() 
    {
        auto retVal = _lastValuePopped; 
        _lastValuePopped = ScriptAny.UNDEFINED; // to avoid memory leaks
        return retVal; 
    }

    /// Queue a fiber last.
    ScriptObject addFiber(string name, ScriptFunction func, ScriptAny thisToUse, ScriptAny[] args)
    {
        auto fiber = new ScriptFiber(name, this, func, thisToUse, args);
        // _fibersQueued.insert(fiber);
        _fibersQueued.insertAfter(_fibersQueued[], fiber);
        return new ScriptObject(name, null, fiber);
    }

    /// Add fiber to front.
    ScriptObject addFiberFirst(string name, ScriptFunction func, ScriptAny thisToUse, ScriptAny[] args)
    {
        auto fiber = new ScriptFiber(name, this, func, thisToUse, args);
        _fibersQueued.insertFront(fiber);
        return new ScriptObject(name, null, fiber);
    }

    /**
     * Removes a ScriptFiber from the queue
     * Params:
     *  fiber = The ScriptFiber to remove. This is an object returned by async
     * Returns:
     *  Whether or not the fiber was successfully removed.
     */
    bool removeFiber(ScriptFiber fiber)
    {
        return _fibersQueued.linearRemoveElement(fiber);
    }

    // TODO await functionality for running a specific fiber to completion and waiting on it

    /**
     * Runs the queued fibers repeatedly until they are done. This is called by Interpreter.runVMFibers
     */
    void runFibersToCompletion()
    {
        _gSync = new Semaphore;
        
        while(!_fibersQueued.empty)
        {
            auto fibersRunning = _fibersQueued;
            _fibersQueued = SList!ScriptFiber();
            foreach(fiber ; fibersRunning)
            {
                fiber.call();
                if(_exc)
                {
                    foreach(fib ; fibersRunning)
                    {
                        if(fiber != fib)
                            _fibersQueued.insert(fib);
                    }
                    break;
                }        
                if(fiber.state != Fiber.State.TERM)
                    _fibersQueued.insert(fiber);
            }

            if(_gWaitingOnThreads > 0)
                _gSync.wait();
            if(_exc)
                break;
        }
        if(_exc)
            throw _exc;
    }

    // TODO: runFibersOnce for game event loops

    /// Whether or not there is an exception flag set
    bool hasException() const { return _exc !is null; }

private:

    struct TryData
    {
        int depth;
        size_t stackSize;
        uint catchGoto;
    }

    void printInstructionWithConstID(size_t ip, OpCode op, uint constID, ConstTable ct)
    {
        if(ct.get(constID).toString().length < 100)
            writefln("%05d: %s #%s // <%s> %s", 
                ip, op.opCodeToString, constID, ct.get(constID).typeToString(),
                ct.get(constID));
        else
            writefln("%05d: %s #%s // <%s>", 
                ip, op.opCodeToString, constID, ct.get(constID).typeToString());
    }

    DebugMap _latestDebugMap;
    ConstTable _latestConstTable;
    ScriptRuntimeException _exc; // exception flag
    Environment _environment;
    Environment _globals;
    OpCodeFunction[ubyte.max + 1] _ops;
    Stack!ScriptAny _stack;
    TryData[] _tryData; // latest
    ScriptAny _lastValuePopped;
    // async stuff
    SList!ScriptFiber _fibersQueued = SList!ScriptFiber();
    size_t _gWaitingOnThreads = 0;
    __gshared Semaphore _gSync;

    // bytecode debugging
    bool _printDisassembly;
    bool _printSteps;

    /// stops the machine
    bool _stopped;
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
        return msg ~ " at instruction " ~ format("%x", ip) ~ " (" ~ opcode.opCodeToString ~ ")";
    }

    size_t ip;
    OpCode opcode;
}

unittest
{
    auto vm = new VirtualMachine(new Environment(null, "<global>"));
    vm = vm.copy();
    ubyte[] chunk;
    auto constTable = new ConstTable();

    ubyte[] getConst(T)(T value)
    {
        return encode(constTable.addValueUint(ScriptAny(value)));
    }

    ScriptAny native_tpropGet(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
    {
        writeln("in native_tpropGet");
        return ScriptAny(1000);
    }

    ScriptAny native_tpropSet(Environment env, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError nfe)
    {
        writeln("Setting value to " ~ args[0].toString);
        return ScriptAny.UNDEFINED;
    }

    /*

    */
    auto testObj = new ScriptObject("test", null, null);
    testObj.addGetterProperty("tprop", new ScriptFunction("tpropGet", &native_tpropGet));
    testObj.addSetterProperty("tprop", new ScriptFunction("tpropSet", &native_tpropSet));

    chunk ~= OpCode.CONST ~ getConst(testObj);
    chunk ~= OpCode.CONST ~ getConst("tprop");
    chunk ~= OpCode.OBJGET;
    chunk ~= OpCode.CONST ~ getConst(testObj);
    chunk ~= OpCode.CONST ~ getConst("tprop");
    chunk ~= OpCode.CONST_1;
    chunk ~= OpCode.OBJSET;

    auto program = new Program(constTable, new ScriptFunction("<test>", [], chunk));

    vm.runProgram(program, []);
}