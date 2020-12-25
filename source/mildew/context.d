module mildew.context;

import mildew.types;

private alias VariableTable = ScriptValue[string];

/// holds context for variables and consts
class Context
{
public:
    /// constructor
    this(Context par = null, in string nam = "<context>")
    {
        _parent = par;
        _name = nam;
    }

    /**
     Attempts to look up existing variable or const throughout the stack. If found, returns a pointer to the variable
     location, and if it is const, sets isConst to true. Note, this pointer should not be stored by native functions
     because the variable table may be modified between function calls.
     */
    ScriptValue* lookupVariableOrConst(in string name, out bool isConst)
    {
        auto context = this;
        while(context !is null)
        {
            if(name in context._varTable)
            {
                isConst = false;
                return (name in context._varTable);
            }
            if(name in context._constTable)
            {
                isConst = true;
                return (name in context._constTable);
            }
            context = context._parent;
        }
        isConst = false;
        return null; // found nothing
    }

    /// removes a variable from the context chain if it exists
    void unsetVariable(in string name)
    {
        auto context = this;
        while(context !is null)
        {
            if(name in context._varTable)
            {
                context._varTable.remove(name);
                return;
            }
            context = context._parent;
        }
    }

    /// attempt to declare and assign a new variable in the current context. Returns false if already exists
    bool declareVariableOrConst(in string nam, ScriptValue value, in bool isConst)
    {
        if(nam in _varTable || nam in _constTable)
            return false;
        
        if(isConst)
        {
            _constTable[nam] = value;
        }
        else
        {
            _varTable[nam] = value;
        }
        return true;
    }

    /// searches context stack for a const or variable and returns true if it exists else false
    bool variableOrConstExists(in string name)
    {
        auto context = this;
        while(context !is null)
        {
            if(name in context._varTable)
                return true;
            if(name in context._constTable)
                return true;
            context = context._parent;
        }
        return false;
    }

    /**
     Attempts to reassign a variable anywhere in the stack and returns a pointer to the variable or null
     if the variable doesn't exist or is const. If the failure is due to const, failedBecauseConst is
     set to true. Note: this pointer should not be stored by native functions due to modifications
     to the variable table that may invalidate it and result in undefined behavior.
     */
    ScriptValue* reassignVariable(in string name, ScriptValue newValue, out bool failedBecauseConst)
    {
        bool isConst; // @suppress(dscanner.suspicious.unmodified)
        auto scriptValuePtr = lookupVariableOrConst(name, isConst);
        if(scriptValuePtr == null)
        {
            failedBecauseConst = false;
            return null;
        }
        if(isConst)
        {
            failedBecauseConst = true;
            return null;
        }
        *scriptValuePtr = newValue;
        failedBecauseConst = false;
        return scriptValuePtr;
    }

    /// force sets a variable or constant. should only be used by host application
    void forceSetVarOrConst(in string name, ScriptValue value, bool isConst)
    {
        if(isConst)
        {
            _constTable[name] = value;
        }
        else
        {
            _varTable[name] = value;
        }
    }

    /// returns the parent property
    Context parent()
    {
        return _parent;
    }

    /// returns the name property
    string name() const
    {
        return _name;
    }

    override string toString() const
    {
        return "Context: " ~ _name;
    }

private:
    /// parent context. null if this is the global context
    Context _parent;
    /// name of context
    string _name;
    /// holds variables
    VariableTable _varTable;
    /// holds consts, which can be shadowed by other consts or lets
    VariableTable _constTable;
}