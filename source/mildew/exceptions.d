/**
This module implements the exception classes that can be thrown by the script. These should be
caught and printed to provide meaningful information about why an exception was thrown while
parsing, compiling, or executing a script.

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
module mildew.exceptions;

import std.typecons;

import mildew.lexer: Token;

/**
 * This exception is thrown by the Lexer and Parser when an error occurs during tokenizing or parsing.
 */
class ScriptCompileException : Exception
{
    /**
     * Constructor. Token may be invalid when thrown by the Lexer.
     */
    this(string msg, Token tok, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        token = tok;
    }

    /**
     * Returns a string that represents the error message and the token and the location of the token where
     * the error occurred.
     */
    override string toString() const
    {
        import std.format: format;
        return format("ScriptCompileException: %s at token %s at %s", msg, token, token.position);
    }

    /**
     * The offending token. This may have an invalid position field depending on why the error was thrown.
     */
    Token token;
}

/**
 * This exception is only thrown once a traceback of lines is collected from the script source code
 * and there are no surrounding try-catch blocks around where the exception occurred. Native bindings
 * may either throw this directly (if called from a script) or set the NativeFunctionError flag
 */
class ScriptRuntimeException : Exception
{
    import mildew.nodes: StatementNode;
    import mildew.types.any: ScriptAny;
    
    /// Constructor
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }

    /// Returns a string containing the script code traceback as well as exception message.
    override string toString() const
    {
        import std.conv: to;

        string str = "ScriptRuntimeException: " ~ msg;
        foreach(tb ; scriptTraceback)
        {
            str ~= "\n at line " ~ tb[0].to!string ~ ":" ~ tb[1];
        }
        return str;
    }

    /// A chain of statements where the exception occurred
    Tuple!(immutable size_t, string)[] scriptTraceback;
    /// If it is thrown by a script, this is the value that was thrown
    ScriptAny thrownValue = ScriptAny.UNDEFINED; 
}
