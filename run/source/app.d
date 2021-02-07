/**
 * This module contains the main function for the REPL. It also runs script files.
 */
module app;

import std.file: readText, FileException;
import std.getopt;
import std.stdio;
import std.string: strip;

import arsd.terminal;

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
        stderr.writeln("In file " ~ fileName);
        stderr.writefln("%s", ex);
    }
    catch(ScriptRuntimeException ex)
    {
        stderr.writeln("In file " ~ fileName);
        stderr.writefln("%s", ex);
        if(ex.thrownValue.type != ScriptAny.Type.UNDEFINED)
            stderr.writefln("Value thrown: %s", ex.thrownValue);
    }
    catch(Exception ex)
    {
        stderr.writeln(ex.msg);
    }
}

private void printUsage()
{
    stderr.writeln("Usage: dmildew_run <scriptfile> [options]");
    stderr.writeln("       dmildew_run [options]");
    stderr.writeln("Options: -usevm : Use bytecode generation instead of tree walker (experimental)");
    stderr.writeln("         -h     : Print this usage message");
}

/**
 * Main function for the REPL or interpreter. If no command line arguments are specified, it enters
 * interactive REPL mode, otherwise it attempts to execute the first argument as a script file.
 */
int main(string[] args)
{
    auto terminal = Terminal(ConsoleOutputType.linear);
    bool useVM = false;

    try 
    {
        auto options = cast(immutable)getopt(args, "usevm", &useVM);
        if(options.helpWanted) 
        {
            printUsage();
            return 1;
        }
    }
    catch(Exception ex)
    {
        printUsage();
        return 64;
    }

    auto interpreter = new Interpreter(useVM);
    interpreter.initializeStdlib();

    if(args.length > 1)
    {
        immutable fileName = args[1];
        try 
        {
            auto code = readText(fileName);
            evaluateWithErrorChecking(interpreter, code, fileName);
        }
        catch(FileException fex)
        {
            stderr.writeln("Could not read file: " ~ fileName);
            return 66;
        }
    }    
    else
    {
        while(true)
        {
            try 
            {
                string input = strip(terminal.getline("mildew> "));
                if(input == "#exit" || input == "")
                    break;
                while(input.length > 0 && input[$-1]=='\\')
                {
                    input = input[0..$-1];
                    input ~= "\n" ~ strip(terminal.getline(">>> "));
                }
                writeln();
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
