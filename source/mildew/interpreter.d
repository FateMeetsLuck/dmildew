/**
 * This module implements the Interpreter class, the main class used by host applications to run scripts
 */
module mildew.interpreter;

import mildew.context;
import mildew.exceptions: ScriptRuntimeException;
import mildew.lexer: Token, Lexer;
import mildew.nodes;
import mildew.parser;
import mildew.types.any: ScriptAny;

/**
 * This is the main interface for the host application to interface with scripts.
 */
class Interpreter
{
public:

    /**
     * Constructs a new Interpreter with a global context. Also sets up the hidden "call" method
     * of all created functions so that any function object can be called with an arbitrary "this"
     * object.
     */
    this()
    {
        _globalContext = new Context(null, "global");
        _currentContext = _globalContext;
    }

    /**
     * Initializes the Mildew standard library, such as Object, Math, and console namespaces. This
     * is optional and is not called by the constructor. For a script to use these methods this
     * must be called first.
     */
    void initializeStdlib()
    {
        import mildew.stdlib.object: initializeObjectLibrary;
        import mildew.stdlib.console: initializeConsoleLibrary;
        import mildew.stdlib.math: initializeMathLibrary;
        initializeObjectLibrary(this);
        initializeConsoleLibrary(this);
        initializeMathLibrary(this);
    }

    /**
     * This is the main entry point for evaluating a script program.
     * Params:
     *  code = This is the code of a script to be executed.
     */
    ScriptAny evaluate(in string code)
    {
        debug import std.stdio: writeln;

        auto lexer = Lexer(code);
        auto tokens = lexer.tokenize();
        auto parser = Parser(tokens);
        // debug writeln(tokens);
        auto programBlock = parser.parseProgram();
        auto vr = programBlock.visit(_currentContext); // @suppress(dscanner.suspicious.unmodified)
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

private:

    Context _globalContext;
    Context _currentContext;
}

