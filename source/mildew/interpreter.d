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
     *  printDisasm = If this is set to true, bytecode disassembly of each program will be printed before execution.
     *  printSteps = If this is set to true, detailed step by step execution of bytecode in the VM will be printed.
     */
    this(bool printDisasm = false, bool printSteps = false)
    {
        _globalEnvironment = new Environment(this);
        _compiler = new Compiler();
        _vm = new VirtualMachine(_globalEnvironment, printDisasm, printSteps);
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
        import mildew.stdlib.buffers: initializeBuffersLibrary;
        import mildew.stdlib.console: initializeConsoleLibrary;
        import mildew.stdlib.date: initializeDateLibrary;
        import mildew.stdlib.generator: initializeGeneratorLibrary;
        import mildew.stdlib.json: initializeJSONLibrary;
        import mildew.stdlib.map: initializeMapLibrary;
        import mildew.stdlib.math: initializeMathLibrary;
        import mildew.stdlib.regexp: initializeRegExpLibrary;
        import mildew.stdlib.system: initializeSystemLib;
        import mildew.stdlib.xmlhttprequest: initializeXMLHttpRequestLibrary;
        initializeTypesLibrary(this);
        initializeGlobalLibrary(this);
        initializeBuffersLibrary(this);
        initializeConsoleLibrary(this);
        initializeDateLibrary(this);
        initializeGeneratorLibrary(this);
        initializeJSONLibrary(this);
        initializeMapLibrary(this);
        initializeMathLibrary(this);
        initializeRegExpLibrary(this);
        initializeSystemLib(this);
        initializeXMLHttpRequestLibrary(this);
    }

    /**
     * This is the main entry point for evaluating a script program.
     * Params:
     *  code = This is the source code of a script to be executed.
     *  program = The optional name of the program, defaults to "<program>"
     * Returns:
     *  If the script has a return statement with an expression, this value will be the result of that expression
     *  otherwise it will be ScriptAny.UNDEFINED
     */
    ScriptAny evaluate(in string code, string name="<program>")
    {
        // TODO: evaluate should run all compiled chunks as a function call with module and exports
        // parameters.
        auto program = _compiler.compile(code, name);

        return _vm.runProgram(program, []);
    }

    /**
     * Evaluates a file that can be either binary bytecode or textual source code.
     * Params:
     *  pathName = the location of the code file in the file system.
     * Returns:
     *  The result of evaluating the file, undefined if no return statement.
     */
    ScriptAny evaluateFile(in string pathName)
    {
        // TODO if fromScript is true, module and exports parameter that can be checked
        // and made the return value
        import std.stdio: File, writefln;
        import mildew.util.encode: decode;

        File inputFile = File(pathName, "rb");
        auto raw = new ubyte[inputFile.size];
        if(inputFile.size == 0)
            return ScriptAny.UNDEFINED;
        raw = inputFile.rawRead(raw);
        if(raw.length > 0 && raw[0] == 0x01)
        {
            auto program = Program.deserialize(raw, pathName);
            return _vm.runProgram(program, []);
        }
        else
        {
            auto source = cast(string)raw;
            return evaluate(source, pathName);
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

    /**
     * Run the VM queued fibers. This API is still a work in progress.
     */
    void runVMFibers()
    {
        _vm.runFibersToCompletion();
    }

    // TODO function to run one cycle of fibers once VM implements it

    /// Gets the VirtualMachine instance of this Interpreter
    VirtualMachine vm() { return _vm; }

private:

    // TODO a registry to keep track of loaded/run files. 

    Compiler _compiler;
    VirtualMachine _vm;
    Environment _globalEnvironment;
}

