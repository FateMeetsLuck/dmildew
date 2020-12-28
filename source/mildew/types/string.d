module mildew.types.string;

import mildew.types.object;

/**
 * Encapsulates a UTF-8 string.
 */
class ScriptString : ScriptObject
{
public:
    /**
     * Constructs a new ScriptString out of a UTF-8 D string
     */
    this(in string str)
    {
        // TODO prototype
        super("String", null, null);
        _string = str;
    }

    /**
     * Returns the actual D string contained
     */
    override string toString() const
    {
        return _string;
    }

private:
    string _string;
}