/**
 * This module implements the Context class.
 */
module mildew.context;

import std.container.rbtree;

import mildew.types.any;

private alias VariableTable = ScriptAny[string];

/**
 * Holds the variables and consts of a script stack frame. The global context can be accessed by
 * climbing the Context.parent chain until reaching the Context whose parent is null. This allows
 * native functions to define local and global variables. Note that calling a native function does
 * not create a stack frame so one could write a native function that adds local variables to the
 * stack frame where it was called.
 */
class Context
{
public:
    /**
     * Constructs a new Context.
     * Params:
     *  par = The parent context, which should be null when the global context is created
     *  nam = The name of the context. When script functions are called this is set to the name
     *        of the function being called.
     */
    this(Context par = null, in string nam = "<context>")
    {
        _parent = par;
        _name = nam;
    }

    /**
     * Attempts to look up existing variable or const throughout the stack. If found, returns a pointer to the 
     * variable location, and if it is const, sets isConst to true. Note, this pointer should not be stored by 
     * native functions because the variable table may be modified between function calls.
     * Params:
     *  name = The name of the variable to look up.
     *  isConst = Whether or not the found variable is constant. Will remain false if variable is not found
     * Returns:
     *  A pointer to the located variable, or null if the variable was not found. If this value is needed for later
     *  the caller should make a copy of the variable immediately.
     */
    ScriptAny* lookupVariableOrConst(in string name, out bool isConst)
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

    /**
     * Removes a variable from anywhere on the Context stack it is located. This function cannot
     * be used to unset consts.
     * Params:
     *  name = The name of the variable.
     */
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

    /** 
     * Attempt to declare and assign a new variable in the current context. Returns false if it already exists.
     * Params:
     *  nam = the name of the variable to set.
     *  value = the initial value of the variable. This can be ScriptAny.UNDEFINED
     *  isConst = whether or not the variable was declared as a const
     * Returns:
     *  True if the declaration was successful, otherwise false.
     */
    bool declareVariableOrConst(in string nam, ScriptAny value, in bool isConst)
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

    /**
     * Searches the entire Context stack for a variable starting with the current context and climbing the parent
     * chain.
     * Params:
     *  name = The name of the variable to look for.
     * Returns:
     *  True if the variable is found, otherwise false.
     */
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
     * Attempts to reassign a variable anywhere in the stack and returns a pointer to the variable or null
     * if the variable doesn't exist or is const. If the failure is due to const, failedBecauseConst is
     * set to true. Note: this pointer should not be stored by native functions due to modifications
     * to the variable table that may invalidate it and result in undefined behavior.
     * Params:
     *  name = The name of the variable to reassign.
     *  newValue = The value to assign. If this is undefined and the variable isn't const, the variable
     *             will be deleted from the table where it is found.
     *  failedBecauseConst = If the reassignment fails due to the variable being a const, this is set to true
     * Returns:
     *  A pointer to the variable in the table where it is found, or null if it was const or not located.
     */
    ScriptAny* reassignVariable(in string name, ScriptAny newValue, out bool failedBecauseConst)
    {
        bool isConst; // @suppress(dscanner.suspicious.unmodified)
        auto scriptAnyPtr = lookupVariableOrConst(name, isConst);
        if(scriptAnyPtr == null)
        {
            failedBecauseConst = false;
            return null;
        }
        if(isConst)
        {
            failedBecauseConst = true;
            return null;
        }
        *scriptAnyPtr = newValue;
        failedBecauseConst = false;
        return scriptAnyPtr;
    }

    /**
     * Force sets a variable or const no matter if the variable was declared already or is const. This is
     * used by the host application to set globals or locals.
     * Params:
     *  name = The name of the variable or const
     *  value = The value of the variable
     *  isConst = Whether or not the variable should be considered const and unable to be overwritten by the script
     */
    void forceSetVarOrConst(in string name, ScriptAny value, bool isConst)
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

    /**
     * Forces the removal of a const or variable in the current context.
     */
    void forceRemoveVarOrConst(in string name)
    {
        if(name in _constTable)
            _constTable.remove(name);
        if(name in _varTable)
            _varTable.remove(name);
    }

    /// climb context stack until finding one without a parent
    Context getGlobalContext()
    {
        Context c = this;
        while(c._parent !is null)
        {
            c = c._parent;
        }
        return c;
    }

    /// inserts a label into the list of valid labels
    void insertLabel(string label)
    {
        _labelList.insert(label);
    }

    /// checks context stack for a label
    bool labelExists(string label)
    {
        auto context = this;
        while(context !is null)
        {
            if(label in context._labelList)
                return true;
            context = context._parent;
        }
        return false;
    }

    /// removes a label from the existing context
    void removeLabelFromCurrent(string label)
    {
        _labelList.removeKey(label);
    }

    /// returns the parent property
    Context parent()
    {
        return _parent;
    }

    /// returns the name property of the Context
    string name() const
    {
        return _name;
    }

    /// Returns a string representing the type and name
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
    /// holds a list of labels
    auto _labelList = new RedBlackTree!string;
}