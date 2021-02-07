/**
 * This module implements Stack
 */
module mildew.util.stack;

/// Stack data structure wrapper around D arrays
struct Stack(T)
{
public:
    /// push an item to the stack
    size_t push(T item)
    {
        _data ~= item;
        return _data.length - 1;
    }
    /// pushes multiple items to the stack such that the last element is on the top
    void push(T[] items)
    {
        _data ~= items;
    }
    /// pops one item from the stack
    auto pop()
    {
        auto item = _data[$-1];
        _data = _data[0..$-1];
        return item;
    }
    /// pops multiple items from the stack
    auto pop(size_t n)
    {
        auto items = _data[$-n..$];
        _data = _data[0..$-n];
        return items;
    }
    /// peek element at the top of array
    auto peek()
    {
        return _data[$-1];
    }
    /// number of stack elements
    auto size()
    {
        return _data.length;
    }
    /// direct access to array
    auto array() { return _data; }
private:
    T[] _data;
}
