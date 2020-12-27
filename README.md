# DMildew

A scripting language for the D programming language inspired by Lua and JavaScript.

This is still very much a work in progress.

## Usage

The examples folder contains example scripts. It should look familiar to anyone who knows JavaScript. However, Mildew is not a full feature JavaScript implementation.

This project is in its early stages so you should probably use the ~main version to get the latest bug fixes. The release tags are only so that it is usable in dub.

## Binding

See mildew/stdlib files for how to bind functions. Classes can be bound by wrapping the object inside a ScriptObject when constructing the new ScriptObject and retrieved from the ScriptObject. Methods can be written as free functions or delegates stored inside the bound constructor's prototype object. In the future, there might be a more trivial way to bind using D metaprogramming.

Binding structs can only be done by wrapping the struct inside a class and storing the class object in a ScriptObject.

The function or delegate signature that can be wrapped inside a ScriptValue (and thus ScriptFunction) is `ScriptValue function(Context, ScriptValue* thisObj, ScriptValue[] args, ref NativeFunctionError);` And such a function is wrapped by `ScriptValue(new ScriptFunction("name of function", &nativeFunction))`. This is analogous to how Lua bindings work.

## Caveats

Unlike JavaScript, arrays in Mildew are primitives and can be concatenated with the '+' operator. It is not possible to reassign the length property of an array.

This language is more strict than JavaScript. Global variables cannot be redeclared unless they are undefined by setting them to
`undefined`. Local variables cannot be redeclared in the same scope likewise. Semicolons are always required.

There are a million debug messages that should be ignored if you build it with the release flag.
