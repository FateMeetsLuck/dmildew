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

import mildew.compiler;
import mildew.environment;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token, Lexer;
import mildew.nodes;
import mildew.parser;
import mildew.types;
import mildew.vm;

/**
 * This is the main interface for the host application to interact with scripts.
 */
class Interpreter
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
    this(bool printVMDebugInfo = true)
    {
        _globalEnvironment = new Environment(this);
        _compiler = new Compiler();
        _printVMDebugInfo = printVMDebugInfo;
        _vm = new VirtualMachine(_globalEnvironment);
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
     * This is the main entry point for evaluating a script program. If the useVM option was set in the
     * constructor, bytecode compilation and execution will be used, otherwise tree walking.
     * Params:
     *  code = This is the source code of a script to be executed.
     *  printDisasm = If VM mode is set, print the disassembly of bytecode before running if true.
     * Returns:
     *  If the script has a return statement with an expression, this value will be the result of that expression
     *  otherwise it will be ScriptAny.UNDEFINED
     */
    ScriptAny evaluate(in string code, bool printDisasm=false, bool fromScript=false)
    {
        auto chunk = _compiler.compile(code);
        if(printDisasm)
            _vm.printChunk(chunk, true);

        if(fromScript)
        {
            auto func = new ScriptFunction("chunk", [], chunk.bytecode, false, false, chunk.constTable);
            func = func.copyCompiled(_globalEnvironment);
            return _vm.runFunction(func, ScriptAny.UNDEFINED, []);
        }
        else
        {
            return _vm.run(chunk, _printVMDebugInfo);
        }
    }

    /**
     * Evaluates a file that can be either binary bytecode or textual source code.
     * Params:
     *  pathName = the location of the code file in the file system.
     *  printDisasm = Whether or not bytecode disassembly should be printed before running
     *  fromScript = This should be left to false and is used internally
     * Returns:
     *  The result of evaluating the file, undefined if no return statement.
     */
    ScriptAny evaluateFile(in string pathName, bool printDisasm=false, bool fromScript=false)
    {
        import std.stdio: File, writefln;
        import mildew.util.encode: decode;

        File inputFile = File(pathName, "rb");
        auto raw = new ubyte[inputFile.size];
        raw = inputFile.rawRead(raw);
        if(raw.length > 0 && raw[0] == 0x01)
        {
            auto chunk = Chunk.deserialize(raw);
            if(printDisasm)
                _vm.printChunk(chunk);
            if(fromScript)
            {
                auto func = new ScriptFunction(pathName, [], chunk.bytecode, false, false, chunk.constTable);
                func = func.copyCompiled(_globalEnvironment);
                return _vm.runFunction(func, ScriptAny.UNDEFINED, []);
            }
            else
            {
                return _vm.run(chunk, _printVMDebugInfo);
            }
        }
        else
        {
            auto source = cast(string)raw;
            return evaluate(source, printDisasm, fromScript);
        }
    }

    // TODO: Create an evaluate function with default exception handling with file name info

    /**
     * Sets a global variable or constant without checking whether or not the variable or const was already
     * declared. This is used by host applications to define custom functions or objects.
     * Params:
     *  name = The name of the global variable.
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
     * Params:
     *  name = The name of the global variable to unset
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

    /// Virtual machine property should never at any point be null
    VirtualMachine vm() { return _vm; }

private:

    Compiler _compiler;
    bool _printVMDebugInfo;
    VirtualMachine _vm;
    Environment _globalEnvironment;
}

