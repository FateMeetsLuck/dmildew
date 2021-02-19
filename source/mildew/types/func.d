/**
This module implements the ScriptFunction class, which holds script defined functions as well as native D
functions or delegates with the correct signature.

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
module mildew.types.func;

import mildew.environment: Environment;
import mildew.compiler;
import mildew.types.any: ScriptAny;
import mildew.types.object: ScriptObject;
import mildew.vm;

/** 
 * When a native function or delegate encounters an error with the arguments sent,
 * the last reference parameter should be set to the appropriate enum value.
 * A specific exception can be thrown by setting the flag to RETURN_VALUE_IS_EXCEPTION and
 * returning a string.
 * If an exception is thrown directly inside a native function, the user will not be able to
 * see a traceback of the script source code lines where the error occurred.
 */
enum NativeFunctionError 
{
    NO_ERROR = 0,
    WRONG_NUMBER_OF_ARGS,
    WRONG_TYPE_OF_ARG,
    RETURN_VALUE_IS_EXCEPTION
}

/// native function signature to be usable by scripting language
alias NativeFunction = ScriptAny function(Environment, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);
/// native delegate signature to be usable by scripting language
alias NativeDelegate = ScriptAny delegate(Environment, ScriptAny* thisObj, ScriptAny[] args, ref NativeFunctionError);

/**
 * This class encapsulates all types of script functions including native D functions and delegates. A
 * native function must first be wrapped in this class before it can be given to a ScriptAny assignment.
 * When an object is created with "new FunctionName()" its __proto__ is assigned to the function's "prototype"
 * field. This allows OOP in the scripting language and is analogous to JavaScript.
 */
class ScriptFunction : ScriptObject
{
    import mildew.nodes: StatementNode;
    import mildew.interpreter: Interpreter;
public:
    /// The type of function held by the object
    enum Type { SCRIPT_FUNCTION, NATIVE_FUNCTION, NATIVE_DELEGATE }

    /**
     * Constructs a new ScriptFunction out of a native D function.
     * Params:
     *  fname = The name of the function.
     *  nfunc = The address of the native function. See NativeFunction alias for correct signature
     *  isClass = Whether or not this function is a constructor. This information is used when printing
     */
    this(string fname, NativeFunction nfunc, bool isClass = false)
    {
        immutable tname = isClass? "class" : "function";
        import mildew.types.bindings: getFunctionPrototype;
        super(tname, getFunctionPrototype, null);
        _functionName = fname;
		_isClass = isClass;
        initializePrototypeProperty();
        _type = Type.NATIVE_FUNCTION;
        _nativeFunction = nfunc;
    }

    /**
     * Constructs a new ScriptFunction out of a native D delegate.
     * Params:
     *  fname = The name of the function.
     *  nfunc = The address of the native delegate. See NativeDelegate alias for correct signature
     *  isClass = Whether or not this function is a constructor. This information is used when printing
     */
    this(string fname, NativeDelegate ndele, bool isClass = false)
    {
        immutable tname = isClass? "class" : "function";
        import mildew.types.bindings: getFunctionPrototype;
        super(tname, getFunctionPrototype, null);
        _functionName = fname;
		_isClass = isClass;
        initializePrototypeProperty();
        _type = Type.NATIVE_DELEGATE;
        _nativeDelegate = ndele;
    }

    /**
     * Check if an object is an instance of a "class" constructor
     */
    static bool isInstanceOf(ScriptObject obj, ScriptFunction clazz)
    {
        if(obj is null || clazz is null)
            return false;
        auto proto = obj.prototype;
        while(proto !is null)
        {
            if(proto["constructor"].toValue!ScriptFunction is clazz)
                return true;
            proto = proto.prototype;
        }
        return false;
    }

    /**
     * Binds a specific this to be used no matter what. Internal users of ScriptFunction such as
     * mildew.vm.virtualmachine.VirtualMachine must manually check the boundThis property and set this up.
     * Unbinding is done by passing UNDEFINED as the parameter.
     */
    void bind(ScriptAny thisObj)
    {
        _boundThis = thisObj;
    }

    /// Returns a string representing the type and name.
    override string toString() const
    {
        return name ~ " " ~ _functionName;
    }

    /// Returns the type of function stored, such as native function, delegate, or script function
    auto type() const { return _type; }
    /// Returns the name of the function
    auto functionName() const { return _functionName; }
    /// Property argNames. Note: native functions do not have this.
    auto argNames() { return _argNames; }
    /// Compiled form cached
    ubyte[] compiled() { return _compiled; }
    /// bound this property. change with bind()
    ScriptAny boundThis() { return _boundThis; }
    /// isGenerator property. used by various pieces
    bool isGenerator() const { return _isGenerator; }

    int opCmp(const ScriptFunction other) const
    {
        if(_type != other._type)
            return cast(int)_type - cast(int)other._type;

        if(_functionName < other._functionName)
            return -1;
        else if(_functionName > other._functionName)
            return 1;

        if(_isClass && !other._isClass)
            return 1;
        else if(!_isClass && other._isClass)
            return -1;
        
        if(_type == Type.SCRIPT_FUNCTION)
        {
            if(_compiled.length != other._compiled.length)
            {
                if(_compiled.length > other._compiled.length)
                    return 1;
                else if(_compiled.length < other._compiled.length)
                    return -1;
            }
            else if(_compiled > other._compiled)
                return 1;
            else if(_compiled < other._compiled)
                return -1;
            else if(_compiled.length == 0)
            {
                if(_argNames > other._argNames)
                    return 1;
                else if(_argNames < other._argNames)
                    return -1;

                if(_statementNodes > other._statementNodes)
                    return 1;
                else if(_statementNodes < other._statementNodes)
                    return -1;
            }
        }
        else if(_type == Type.NATIVE_DELEGATE)
        {
            if(_nativeDelegate > other._nativeDelegate)
                return 1;
            else if(_nativeDelegate < other._nativeDelegate)
                return -1;
        }
        else if(_type == Type.NATIVE_FUNCTION)
        {
            if(_nativeFunction > other._nativeFunction)
                return 1;
            else if(_nativeFunction < other._nativeFunction)
                return -1;
        }
        return 0;
    }

    override size_t toHash() const @safe nothrow
    {
        if(_compiled.length > 0)
        {
            return typeid(_compiled).getHash(&_compiled);
        }
        // lacking but not sure what else to do
        return typeid(_functionName).getHash(&_functionName);
    }

    bool opEquals(ScriptFunction other) const
    {
        return opCmp(other) == 0;
    }

    /// ct property
    ConstTable constTable() { return _constTable; }
    /// ct property
    ConstTable constTable(ConstTable ct) { return _constTable = ct; }

package(mildew):

    /**
     * Constructor for functions created from compilation of statements.
     */
    this(string fnname, string[] args, ubyte[] bc, bool isClass = false, bool isGenerator = false, ConstTable ct = null)
    {
        import mildew.types.bindings: getFunctionPrototype;
        immutable tname = isClass? "class" : "function";
        super(tname, getFunctionPrototype(), null);
        _functionName = fnname;
        _argNames = args;
        _compiled = bc;
        _isClass = isClass;
        _isGenerator = isGenerator;
        _constTable = ct;
        initializePrototypeProperty();
        _type = Type.SCRIPT_FUNCTION;
    }

    /**
     * Method to copy fresh compiled functions with the correct environment
     */
    ScriptFunction copyCompiled(Environment env)
    {
        auto newFunc = new ScriptFunction(_functionName, _argNames, _compiled, _isClass, _isGenerator, _constTable);
        newFunc._closure = env;
        return newFunc;
    }

    // must check type before using these properties or one gets an exception

    /// get the native function ONLY if it is one
    auto nativeFunction()
    {
        if(_type == Type.NATIVE_FUNCTION)
            return _nativeFunction;
        else
            throw new Exception("This is not a native function");
    }

    /// get the delegate only if it is one
    auto nativeDelegate()
    {
        if(_type == Type.NATIVE_DELEGATE)
            return _nativeDelegate;
        else
            throw new Exception("This is not a native delegate");
    }

    /// Sets the function name
    auto functionName(in string fnName) { return _functionName = fnName; }

    /// Property statementNodes
    auto statementNodes() { return _statementNodes; }

	/// Property get closure
	auto closure() { return _closure; }

    /// Property isClass
    auto isClass() const { return _isClass; }

    /// used by the parser for missing constructors in classes that don't extend
    static deprecated ScriptFunction emptyFunction(in string name, bool isClass)
    {
        return new ScriptFunction(name, &native_EMPTY_FUNCTION, isClass);
    }

private:
    Type _type;
    string _functionName;
    string[] _argNames;
    StatementNode[] _statementNodes;
    ScriptAny _boundThis;
	Environment _closure = null;
	bool _isClass = false;
    bool _isGenerator = false;
    ConstTable _constTable;
    union 
    {
        NativeFunction _nativeFunction;
        NativeDelegate _nativeDelegate;
    }

    void initializePrototypeProperty()
    {
        _dictionary["prototype"] = ScriptAny(new ScriptObject("Object", null));
        _dictionary["prototype"]["constructor"] = ScriptAny(this);
    }

    ubyte[] _compiled;

}

deprecated private ScriptAny native_EMPTY_FUNCTION(Environment e, ScriptAny* thisObj, ScriptAny[] args, 
                                        ref NativeFunctionError nfe)
{
    return ScriptAny.UNDEFINED;
}

