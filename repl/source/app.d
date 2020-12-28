/**
 * This module contains the main function for the REPL. It also runs script files.
 */
module app;

import std.file: readText;
import std.stdio;
import std.string: strip;

import arsd.terminal;

import mildew.context;
import mildew.exceptions;
import mildew.interpreter;
import mildew.lexer;
import mildew.parser;
import mildew.types;

/**
 * This runs a script program and prints the appropriate error message when a script exception is caught.
 */
void evaluateWithErrorChecking(Interpreter interpreter, in string code, in string fileName = "<stdin>")
{
    try 
    {
        auto result = interpreter.evaluate(code);
        writeln("The program successfully returned " ~ result.toString);
    }
    catch(ScriptCompileException ex)
    {
        writeln("In file " ~ fileName);
        writefln("%s", ex);
    }
    catch(ScriptRuntimeException ex)
    {
        writeln("In file " ~ fileName);
        writefln("%s", ex);
        if(ex.thrownValue.type != ScriptAny.Type.UNDEFINED)
            writefln("Value thrown: %s", ex.thrownValue);
    }
}

/**
 * Main function for the REPL or interpreter. If no command line arguments are specified, it enters
 * interactive REPL mode, otherwise it attempts to execute the first argument as a script file.
 */
int main(string[] args)
{
    auto terminal = Terminal(ConsoleOutputType.linear);
    auto interpreter = new Interpreter();
    interpreter.initializeStdlib();

    if(args.length > 1)
    {
        immutable fileName = args[1];
        auto code = readText(fileName);
        evaluateWithErrorChecking(interpreter, code, fileName);
    }    
    else
    {
        while(true)
        {
            try 
            {
                string input = strip(terminal.getline("mildew> "));
                writeln();
                if(input == "#exit" || input == "")
                    break;
                while(input.length > 0 && input[$-1]=='\\')
                {
                    input = input[0..$-1];
                    input ~= "\n" ~ strip(terminal.getline(">>> "));
                    writeln();
                }
                evaluateWithErrorChecking(interpreter, input);
            }
            catch(UserInterruptionException ex)
            {
                break;
            }
        }
        writeln("");
    }
    return 0;
}
