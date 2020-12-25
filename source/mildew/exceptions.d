module mildew.exceptions;

import mildew.lexer: Token;

/// General compilation exception
class ScriptCompileException : Exception
{
    /// constructor
    this(string msg, Token tok, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
        token = tok;
    }

    override string toString() const
    {
        import std.format: format;
        return format("ScriptCompileException: %s at token %s at %s", msg, token, token.position);
    }

    /// Token, may be invalid but position should be usable
    Token token;
}

/// A special exception that isn't "thrown" but generated and stored in VisitResult
class ScriptRuntimeException : Exception
{
    import mildew.nodes: Node, StatementNode;
    
    /// ctor
    this(string msg, string file = __FILE__, size_t line = __LINE__)
    {
        super(msg, file, line);
    }

    override string toString() const
    {
        import std.conv: to;

        string str = "ScriptRuntimeException: " ~ msg ~ "\n";
        foreach(tb ; scriptTraceback)
        {
            str ~= " at line " ~ tb.line.to!string ~ ":" ~ tb.toString() ~ "\n";
        }
        return str;
    }

    /// a chain of statement nodes where the exception occurred
    StatementNode[] scriptTraceback;
}
