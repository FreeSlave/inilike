/**
 * Exception classes used in the library.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2017
 * License:
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also:
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.exception;

///Base class for ini-like format errors.
class IniLikeException : Exception
{
    ///
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
    }
}

/**
 * Exception thrown on error related to the group.
 */
class IniLikeGroupException : Exception
{
    ///
    this(string msg, string groupName, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _group = groupName;
    }

    /**
     * Name of group where error occured.
     */
    @nogc @safe string groupName() const nothrow pure {
        return _group;
    }

private:
    string _group;
}

/**
 * Exception thrown when trying to set invalid key or value.
 */
class IniLikeEntryException : IniLikeGroupException
{
    this(string msg, string group, string key, string value, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, group, file, line, next);
        _key = key;
        _value = value;
    }

    /**
     * The key the value associated with.
     */
    @nogc @safe string key() const nothrow pure {
        return _key;
    }

    /**
     * The value associated with key.
     */
    @nogc @safe string value() const nothrow pure {
        return _value;
    }

private:
    string _key;
    string _value;
}

/**
 * Exception thrown on the ini-like file read error.
 */
class IniLikeReadException : IniLikeException
{
    /**
     * Create $(D IniLikeReadException) with msg, lineNumber and fileName.
     */
    this(string msg, size_t lineNumber, string fileName = null, IniLikeEntryException entryException = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _lineNumber = lineNumber;
        _fileName = fileName;
        _entryException = entryException;
    }

    /**
     * Number of line in the file where the exception occured, starting from 1.
     * 0 means that error is not bound to any existing line, but instead relate to file at whole (e.g. required group or key is missing).
     * Don't confuse with $(B line) property of $(B Throwable).
     */
    @nogc @safe size_t lineNumber() const nothrow pure {
        return _lineNumber;
    }

    /**
     * Number of line in the file where the exception occured, starting from 0.
     * Don't confuse with $(B line) property of $(B Throwable).
     */
    @nogc @safe size_t lineIndex() const nothrow pure {
        return _lineNumber ? _lineNumber - 1 : 0;
    }

    /**
     * Name of ini-like file where error occured.
     * Can be empty if fileName was not given upon $(D IniLikeFile) creating.
     * Don't confuse with $(B file) property of $(B Throwable).
     */
    @nogc @safe string fileName() const nothrow pure {
        return _fileName;
    }

    /**
     * Original $(D IniLikeEntryException) which caused this error.
     * This will have the same msg.
     * Returns: $(D IniLikeEntryException) object or null if the cause of error was something else.
     */
    @nogc @safe IniLikeEntryException entryException() nothrow pure {
        return _entryException;
    }

private:
    size_t _lineNumber;
    string _fileName;
    IniLikeEntryException _entryException;
}
