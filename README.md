# DMildew

A scripting language for the D programming language inspired by Lua and JavaScript.

This is still very much a work in progress.

## Usage

The examples folder contains example scripts. It should look familiar to anyone who knows JavaScript. However, Mildew is not a full feature JavaScript implementation.

## Binding

See mildew/stdlib files for how to bind functions. Classes can be bound by wrapping the object inside a ScriptObject when constructing the new ScriptObject and retrieved from the ScriptObject. Methods can be written as free functions stored inside the bound constructor's prototype object. In the future, there might be a more trivial way to bind using D metaprogramming.

The function or delegate signature that can be wrapped inside a ScriptValue (and thus ScriptFunction) is `ScriptValue function(Context, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError);` And such a function is wrapped by `ScriptValue(new ScriptFunction("name of function", &nativeFunction))`

## Caveats

Unlike JavaScript, arrays in Mildew are primitives and can be concatenated with the '+' operator. It is not possible to reassign the length property of an array.
