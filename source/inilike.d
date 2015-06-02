/**
 * Reading and writing ini-like files, used in Unix systems.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov).
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification).
 */

module inilike;

private {
    import std.algorithm;
    import std.array;
    import std.conv;
    import std.exception;
    import std.file;
    import std.path;
    import std.process;
    import std.range;
    import std.stdio;
    import std.string;
    import std.traits;
    import std.typecons;
    
    static if( __VERSION__ < 2066 ) enum nogc = 1;
}

private alias LocaleTuple = Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier");
private alias KeyValueTuple = Tuple!(string, "key", string, "value");

/** Retrieve current locale probing environment variables LC_TYPE, LC_ALL and LANG (in this order)
 * Returns: locale in posix form or empty string if could not determine locale.
 * Note: currently this function caches its result.
 */
@safe string currentLocale() nothrow
{
    static string cache;
    if (cache is null) {
        try {
            cache = environment.get("LC_CTYPE", environment.get("LC_ALL", environment.get("LANG")));
        }
        catch(Exception e) {
            
        }
        if (cache is null) {
            cache = "";
        }
    }
    return cache;
}

/**
 * Make locale name based on language, country, encoding and modifier.
 * Returns: locale name in form lang_COUNTRY.ENCODING@MODIFIER
 * See_Also: parseLocaleName
 */
@safe string makeLocaleName(string lang, string country = null, string encoding = null, string modifier = null) pure nothrow
{
    return lang ~ (country.length ? "_"~country : "") ~ (encoding.length ? "."~encoding : "") ~ (modifier.length ? "@"~modifier : "");
}

/**
 * Parse locale name into the tuple of 4 values corresponding to language, country, encoding and modifier
 * Returns: Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier")
 * See_Also: makeLocaleName
 */
@nogc @trusted auto parseLocaleName(string locale) pure nothrow
{
    auto modifiderSplit = findSplit(locale, "@");
    auto modifier = modifiderSplit[2];
    
    auto encodongSplit = findSplit(modifiderSplit[0], ".");
    auto encoding = encodongSplit[2];
    
    auto countrySplit = findSplit(encodongSplit[0], "_");
    auto country = countrySplit[2];
    
    auto lang = countrySplit[0];
    
    return LocaleTuple(lang, country, encoding, modifier);
}

/**
 * Construct localized key name from key and locale.
 * Returns: localized key in form key[locale]. Automatically omits locale encoding if present.
 * Example:
----------
assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
----------
 * See_Also: separateFromLocale
 */
@safe string localizedKey(string key, string locale) pure nothrow
{
    auto t = parseLocaleName(locale);
    if (!t.encoding.empty) {
        locale = makeLocaleName(t.lang, t.country, null, t.modifier);
    }
    return key ~ "[" ~ locale ~ "]";
}

/**
 * ditto, but constructs locale name from arguments.
 * Example:
----------
assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
----------
 */
@safe string localizedKey(string key, string lang, string country, string modifier = null) pure nothrow
{
    return key ~ "[" ~ makeLocaleName(lang, country, null, modifier) ~ "]";
}

/** 
 * Separate key name into non-localized key and locale name.
 * If key is not localized returns original key and empty string.
 * Returns: tuple of key and locale name.
 * See_Also: localizedKey
 */
@nogc @trusted Tuple!(string, string) separateFromLocale(string key) pure nothrow {
    if (key.endsWith("]")) {
        auto t = key.findSplit("[");
        if (t[1].length) {
            return tuple(t[0], t[2][0..$-1]);
        }
    }
    return tuple(key, string.init);
}

/**
 * Tells whether the entry value presents true
 * Example:
-----------
assert(isTrue("true"));
assert(isTrue("1"));
assert(!isTrue("not boolean"));
-----------
 */
@nogc @safe bool isTrue(string value) pure nothrow {
    return (value == "true" || value == "1");
}

/**
 * Tells whether the entry value presents false
 * Example:
----------
assert(isFalse("false"));
assert(isFalse("0"));
assert(!isFalse("not boolean"));
----------
 */
@nogc @safe bool isFalse(string value) pure nothrow {
    return (value == "false" || value == "0");
}

/**
 * Check if the entry value can be interpreted as boolean value.
 * Example:
---------
assert(isBoolean("true"));
assert(isBoolean("1"));
assert(isBoolean("false"));
assert(isBoolean("0"));
assert(!isBoolean("not boolean"));
---------
 * See_Also: isTrue, isFalse
 */
@nogc @safe bool isBoolean(string value) pure nothrow {
    return isTrue(value) || isFalse(value);
}
/**
 * Escapes string by replacing special symbols with escaped sequences. 
 * These symbols are: '\\' (backslash), '\n' (newline), '\r' (carriage return) and '\t' (tab).
 * Note: 
 *  Currently the library stores values as they were loaded from file, i.e. escaped. 
 *  To keep things consistent you should take care about escaping the value before inserting. The library will not do it for you.
 * Returns: Escaped string.
 * Example:
----
assert("\\next\nline".escapeValue() == `\\next\nline`); // notice how the string on the right is raw.
----
 * See_Also: unescapeValue
 */
@trusted string escapeValue(string value) nothrow pure {
    return value.replace("\\", `\\`).replace("\n", `\n`).replace("\r", `\r`).replace("\t", `\t`);
}

@trusted string doUnescape(string value, in Tuple!(char, char)[] pairs) nothrow pure {
    auto toReturn = appender!string();
    
    for (size_t i = 0; i < value.length; i++) {
        if (value[i] == '\\') {
            if (i < value.length - 1) {
                char c = value[i+1];
                auto t = pairs.find!"a[0] == b[0]"(tuple(c,c));
                if (!t.empty) {
                    toReturn.put(t.front[1]);
                    i++;
                    continue;
                }
            }
        }
        toReturn.put(value[i]);
    }
    return toReturn.data;
}


/**
 * Unescapes string. You should unescape values returned by library before displaying until you want keep them as is (e.g., to allow user to edit values in escaped form).
 * Returns: Unescaped string.
 * Example:
-----
assert(`\\next\nline`.unescapeValue() == "\\next\nline"); // notice how the string on the left is raw.
----
 * See_Also: escapeValue
 */
@trusted string unescapeValue(string value) nothrow pure
{
    static immutable Tuple!(char, char)[] pairs = [
       tuple('s', ' '),
       tuple('n', '\n'),
       tuple('r', '\r'),
       tuple('t', '\t'),
       tuple('\\', '\\')
    ];
    return doUnescape(value, pairs);
}

/**
 * Represents the line from ini-like file.
 * Usually you should not use this struct directly, since it's tightly connected with internal $(B IniLikeFile) implementation.
 */
struct IniLikeLine
{
    enum Type
    {
        None = 0,
        Comment = 1,
        KeyValue = 2,
        GroupStart = 4
    }
    
    @nogc @safe static IniLikeLine fromComment(string comment) nothrow {
        return IniLikeLine(comment, null, Type.Comment);
    }
    
    @nogc @safe static IniLikeLine fromGroupName(string groupName) nothrow {
        return IniLikeLine(groupName, null, Type.GroupStart);
    }
    
    @nogc @safe static IniLikeLine fromKeyValue(string key, string value) nothrow {
        return IniLikeLine(key, value, Type.KeyValue);
    }
    
    @nogc @safe string comment() const nothrow {
        return _type == Type.Comment ? _first : null;
    }
    
    @nogc @safe string key() const nothrow {
        return _type == Type.KeyValue ? _first : null;
    }
    
    @nogc @safe string value() const nothrow {
        return _type == Type.KeyValue ? _second : null;
    }
    
    @nogc @safe string groupName() const nothrow {
        return _type == Type.GroupStart ? _first : null;
    }
    
    @nogc @safe Type type() const nothrow {
        return _type;
    }
    
    @nogc @safe void makeNone() nothrow {
        _type = Type.None;
    }
    
private:
    string _first;
    string _second;
    Type _type = Type.None;
}

/**
 * This class represents the group (section) in the .init like file. 
 * You can create and use instances of this class only in the context of $(B IniLikeFile) or its derivatives.
 * Note: keys are case-sensitive.
 */
final class IniLikeGroup
{
private:
    @nogc @safe this(string name, const IniLikeFile parent) nothrow {
        assert(parent, "logic error: no parent for IniLikeGroup");
        _name = name;
        _parent = parent;
    }
    
public:
    
    /**
     * Returns: the value associated with the key
     * Note: it's an error to access nonexistent value
     * See_Also: value
     */
    @nogc @safe string opIndex(string key) const nothrow {
        auto i = key in _indices;
        assert(_values[*i].type == IniLikeLine.Type.KeyValue);
        assert(_values[*i].key == key);
        return _values[*i].value;
    }
    
    /**
     * Insert new value or replaces the old one if value associated with key already exists.
     * Returns: inserted/updated value
     * Throws: $(B Exception) if key is not valid
     */
    @safe string opIndexAssign(string value, string key) {
        enforce(_parent.isValidKey(separateFromLocale(key)[0]), "key is invalid");
        auto pick = key in _indices;
        if (pick) {
            return (_values[*pick] = IniLikeLine.fromKeyValue(key, value)).value;
        } else {
            _indices[key] = _values.length;
            _values ~= IniLikeLine.fromKeyValue(key, value);
            return value;
        }
    }
    /**
     * Ditto, localized version.
     * See_Also: setLocalizedValue, localizedValue
     */
    @safe string opIndexAssign(string value, string key, string locale) {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    /**
     * Tell if group contains value associated with the key.
     */
    @nogc @safe bool contains(string key) const nothrow {
        return value(key) !is null;
    }
    
    /**
     * Get value by key.
     * Returns: the value associated with the key, or defaultValue if group does not contain item with this key.
     */
    @nogc @safe string value(string key, string defaultValue = null) const nothrow {
        auto pick = key in _indices;
        if (pick) {
            if(_values[*pick].type == IniLikeLine.Type.KeyValue) {
                assert(_values[*pick].key == key);
                return _values[*pick].value;
            }
        }
        return defaultValue;
    }
    
    /**
     * Perform locale matching lookup as described in $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html, Localized values for keys).
     * If locale is null it calls currentLocale to get the locale.
     * Returns: the localized value associated with key and locale, or defaultValue if group does not contain item with this key.
     * See_Also: currentLocale
     */
    @safe string localizedValue(string key, string locale = null, string defaultValue = null) const nothrow {
        if (locale is null) {
            locale = currentLocale();
        }
        
        //Any ideas how to get rid of this boilerplate and make less allocations?
        auto t = parseLocaleName(locale);
        auto lang = t.lang;
        auto country = t.country;
        auto modifier = t.modifier;
        
        if (lang.length) {
            string pick;
            if (country.length && modifier.length) {
                pick = value(localizedKey(key, locale));
                if (pick !is null) {
                    return pick;
                }
            }
            if (country.length) {
                pick = value(localizedKey(key, lang, country));
                if (pick !is null) {
                    return pick;
                }
            }
            if (modifier.length) {
                pick = value(localizedKey(key, lang, null, modifier));
                if (pick !is null) {
                    return pick;
                }
            }
            pick = value(localizedKey(key, lang, null));
            if (pick !is null) {
                return pick;
            }
        }
        
        return value(key, defaultValue);
    }
    
    /**
     * Same as localized version of opIndexAssign, but uses function syntax.
     */
    @safe void setLocalizedValue(string key, string locale, string value) {
        this[key, locale] = value;
    }
    
    /**
     * Removes entry by key. To remove localized values use localizedKey.
     */
    @safe void removeEntry(string key) nothrow {
        auto pick = key in _indices;
        if (pick) {
            _values[*pick].makeNone();
        }
    }
    
    /**
     * Iterate by Key-Value pairs.
     * Returns: range of Tuple!(string, "key", string, "value")
     */
    @nogc @safe auto byKeyValue() const nothrow {
        return _values.filter!(v => v.type == IniLikeLine.Type.KeyValue).map!(v => KeyValueTuple(v.key, v.value));
    }
    
    /**
     * Get name of this group.
     * Returns: the name of this group.
     */
    @nogc @safe string name() const nothrow {
        return _name;
    }
    
    /**
     * Returns: the range of $(B IniLikeLine)s included in this group.
     * Note: this does not include Group line itself.
     */
    @system auto byIniLine() const {
        return _values.filter!(v => v.type != IniLikeLine.Type.None);
    }
    
    @trusted void addComment(string comment) nothrow {
        _values ~= IniLikeLine.fromComment(comment);
    }
    
private:
    size_t[string] _indices;
    IniLikeLine[] _values;
    string _name;
    const IniLikeFile _parent;
}

/**
 * Exception thrown on the file read error.
 */
class IniLikeException : Exception
{
    this(string msg, size_t lineNumber, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _lineNumber = lineNumber;
    }
    
    ///Number of line in the file where the exception occured, starting from 1. Don't be confused with $(B line) property of $(B Throwable).
    @nogc @safe size_t lineNumber() const nothrow {
        return _lineNumber;
    }
    
private:
    size_t _lineNumber;
}

/**
 * Reads range of strings into the range of IniLikeLines.
 * See_Also: iniLikeFileReader, iniLikeStringReader
 */
@trusted auto iniLikeRangeReader(Range)(Range byLine) if(is(ElementType!Range == string))
{
    return byLine.map!(function(string line) {
        line = strip(line);
        if (line.empty || line.startsWith("#")) {
            return IniLikeLine.fromComment(line);
        } else if (line.startsWith("[") && line.endsWith("]")) {
            return IniLikeLine.fromGroupName(line[1..$-1]);
        } else {
            auto t = line.findSplit("=");
            auto key = t[0].stripRight();
            auto value = t[2].stripLeft();
            
            if (t[1].length) {
                return IniLikeLine.fromKeyValue(key, value);
            } else {
                return IniLikeLine();
            }         
        }
    });
}

/**
 * ditto, convenient function for reading from the file.
 * Throws: $(B ErrnoException) if file could not be opened.
 */
@trusted auto iniLikeFileReader(string fileName)
{
    return iniLikeRangeReader(File(fileName, "r").byLine().map!(s => s.idup));
}

/**
 * ditto, convenient function for reading from string.
 */
@trusted auto iniLikeStringReader(string contents)
{
    return iniLikeRangeReader(contents.splitLines());
}

/**
 * Ini-like file.
 * 
 */
class IniLikeFile
{
public:
    ///Flags to manage .ini like file reading
    enum ReadOptions
    {
        noOptions = 0,              /// Read all groups and skip comments and empty lines.
        firstGroupOnly = 1,         /// Ignore other groups than the first one.
        preserveComments = 2,       /// Preserve comments and empty lines. Use this when you want to preserve them across writing.
        ignoreGroupDuplicates = 4,  /// Ignore group duplicates. The first found will be used.
        ignoreInvalidKeys = 8       /// Skip invalid keys during parsing.
    }
    
    /**
     * Construct empty IniLikeFile, i.e. without any groups or values
     */
    @nogc @safe this() nothrow {
        
    }
    
    /**
     * Read from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeException) if error occured while reading the file.
     */
    @safe this(string fileName, ReadOptions options = ReadOptions.noOptions) {
        this(iniLikeFileReader(fileName), options, fileName);
    }
    
    /**
     * Read from range of $(B IniLikeLine)s.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing.
     */
    @trusted this(Range)(Range byLine, ReadOptions options = ReadOptions.noOptions, string fileName = null) if(is(ElementType!Range == IniLikeLine))
    {
        size_t lineNumber = 0;
        IniLikeGroup currentGroup;
        bool ignoreKeyValues;
        
        try {
            foreach(line; byLine)
            {
                lineNumber++;
                final switch(line.type)
                {
                    case IniLikeLine.Type.Comment:
                    {
                        if (options & ReadOptions.preserveComments) {
                            if (currentGroup is null) {
                                addFirstComment(line.comment);
                            } else {
                                currentGroup.addComment(line.comment);
                            }
                        }
                    }
                    break;
                    case IniLikeLine.Type.GroupStart:
                    {
                        if ((options & ReadOptions.ignoreGroupDuplicates) && group(line.groupName)) {
                            ignoreKeyValues = true;
                            continue;
                        }
                        ignoreKeyValues = false;
                        currentGroup = addGroup(line.groupName);
                        
                        if (options & ReadOptions.firstGroupOnly) {
                            break;
                        }
                    }
                    break;
                    case IniLikeLine.Type.KeyValue:
                    {
                        if (ignoreKeyValues || ((options & ReadOptions.ignoreInvalidKeys) && !isValidKey(line.key)) ) {
                            continue;
                        }
                        enforce(currentGroup, "met key-value pair before any group");
                        currentGroup[line.key] = line.value;
                    }
                    break;
                    case IniLikeLine.Type.None:
                    {
                        throw new Exception("not key-value pair, nor group start nor comment");
                    }
                }
            }
            
            _fileName = fileName;
        }
        catch (Exception e) {
            throw new IniLikeException(e.msg, lineNumber, e.file, e.line, e.next);
        }
    }
    
    /**
     * Get group by name.
     * Returns: IniLikeGroup instance associated with groupName or $(B null) if not found.
     * See_Also: byGroup
     */
    @nogc @safe inout(IniLikeGroup) group(string groupName) nothrow inout {
        auto pick = groupName in _groupIndices;
        if (pick) {
            return _groups[*pick];
        }
        return null;
    }
    
    /**
     * Create new group using groupName.
     * Returns: newly created instance of IniLikeGroup.
     * Throws: Exception if group with such name already exists or groupName is empty.
     * See_Also: removeGroup, group
     */
    @safe IniLikeGroup addGroup(string groupName) {
        enforce(groupName.length, "empty group name");
        enforce(group(groupName) is null, "group already exists");
        
        auto iniLikeGroup = new IniLikeGroup(groupName, this);
        _groupIndices[groupName] = _groups.length;
        _groups ~= iniLikeGroup;
        
        return iniLikeGroup;
    }
    
    /**
     * Remove group by name.
     * See_Also: addGroup, group
     */
    @safe void removeGroup(string groupName) nothrow {
        auto pick = groupName in _groupIndices;
        if (pick) {
            _groups[*pick] = null;
        }
    }
    
    /**
     * Range of groups in order how they were defined in file.
     * See_Also: group
     */
    @nogc @safe final auto byGroup() const nothrow {
        return _groups.filter!(f => f !is null);
    }
    
    ///ditto
    @nogc @safe final auto byGroup() nothrow {
        return _groups.filter!(f => f !is null);
    }
    
    
    /**
     * Save object to the file using .ini-like format.
     * Throws: ErrnoException if the file could not be opened or an error writing to the file occured.
     * See_Also: saveToString, save
     */
    @trusted void saveToFile(string fileName) const {
        auto f = File(fileName, "w");
        void dg(string line) {
            f.writeln(line);
        }
        save(&dg);
    }
    
    /**
     * Save object to string using .ini like format.
     * Returns: string representing the contents of file.
     * See_Also: saveToFile, save
     */
    @safe string saveToString() const {
        auto a = appender!(string[])();
        void dg(string line) {
            a.put(line);
        }
        save(&dg);
        return a.data.join("\n");
    }
    
    /**
     * Alias for saving delegate.
     * See_Also: save
     */
    alias SaveDelegate = void delegate(string);
    
    /**
     * Use delegate to retrieve strings line by line. 
     * Those strings can be written to the file or be showed in text area.
     * Note: returned strings don't have trailing newline character.
     */
    @trusted void save(SaveDelegate sink) const {
        foreach(line; firstComments()) {
            sink(line);
        }
        
        foreach(group; byGroup()) {
            sink("[" ~ group.name ~ "]");
            foreach(line; group.byIniLine()) {
                if (line.type == IniLikeLine.Type.Comment) {
                    sink(line.comment);
                } else if (line.type == IniLikeLine.Type.KeyValue) {
                    sink(line.key ~ "=" ~ line.value);
                }
            }
        }
    }
    
    /**
     * File path where the object was loaded from.
     * Returns: file name as was specified on the object creation.
     */
    @nogc @safe string fileName() nothrow const {
        return  _fileName;
    }
    
    /**
    * Tell whether the string is valid key. For IniLikeFile the valid key is any non-empty string.
    * Reimplement this function in the derived class to throw exception from IniLikeGroup when key is invalid.
    */
    @nogc @safe bool isValidKey(string key) pure nothrow const {
        return key.length != 0;
    }
    
protected:
    @nogc @trusted final auto firstComments() const nothrow {
        return _firstComments;
    }
    
    @trusted final void addFirstComment(string line) nothrow {
        _firstComments ~= line;
    }
    
private:
    string _fileName;
    size_t[string] _groupIndices;
    IniLikeGroup[] _groups;
    string[] _firstComments;
}

unittest
{
    //Test locale-related functions
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", null, null, "mod") == "ru@mod");
    
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    assert(parseLocaleName("ru_RU") == tuple("ru", "RU", string.init, string.init));
    
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru_RU.UTF-8") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
    
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    //Test locale matching lookup
    auto lilf = new IniLikeFile;
    lilf.addGroup("Entry");
    auto group = lilf.group("Entry");
    assert(group.name == "Entry"); 
    group["Name"] = "Programmer";
    group["Name[ru_RU]"] = "Разработчик";
    group["Name[ru@jargon]"] = "Кодер";
    group["Name[ru]"] = "Программист";
    group["GenericName"] = "Program";
    group["GenericName[ru]"] = "Программа";
    assert(group["Name"] == "Programmer");
    assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
    assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
    assert(group.localizedValue("Name", "ru") == "Программист");
    assert(group.localizedValue("Name", "nonexistent locale") == "Programmer");
    assert(group.localizedValue("GenericName", "ru_RU") == "Программа");
    
    //Test escaping and unescaping
    assert("a\\next\nline\top".escapeValue() == `a\\next\nline\top`);
    assert(`a\\next\nline\top`.unescapeValue() == "a\\next\nline\top");
    
    //Test key types functions
    assert(isTrue("true"));
    assert(isTrue("1"));
    assert(!isTrue("not boolean"));
    
    assert(isFalse("false"));
    assert(isFalse("0"));
    assert(!isFalse("not boolean"));
    
    assert(isBoolean("true"));
    assert(isBoolean("1"));
    assert(isBoolean("false"));
    assert(isBoolean("0"));
    assert(!isBoolean("not boolean"));
    
    //Test IniLikeFile
    string contents = 
`# The first comment
[First Entry]
# Comment
GenericName=File manager
GenericName[ru]=Файловый менеджер
# Another comment
[Another Group]
Name=Commander
Comment=Manage files
# The last comment`;

    auto ilf = new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.preserveComments);
    assert(ilf.group("First Entry"));
    assert(ilf.group("Another Group"));
    assert(ilf.saveToString() == contents);
    
    auto firstEntry = ilf.group("First Entry");
    
    assert(firstEntry["GenericName"] == "File manager");
    assert(firstEntry.value("GenericName") == "File manager");
    firstEntry["GenericName"] = "Manager of files";
    assert(firstEntry["GenericName"] == "Manager of files");
    firstEntry["Authors"] = "Unknown";
    assert(firstEntry["Authors"] == "Unknown");
    
    assert(firstEntry.localizedValue("GenericName", "ru") == "Файловый менеджер");
    firstEntry.setLocalizedValue("GenericName", "ru", "Менеджер файлов");
    assert(firstEntry.localizedValue("GenericName", "ru") == "Менеджер файлов");
    firstEntry.setLocalizedValue("Authors", "ru", "Неизвестны");
    assert(firstEntry.localizedValue("Authors", "ru") == "Неизвестны");
    
    firstEntry.removeEntry("GenericName");
    assert(!firstEntry.contains("GenericName"));
    firstEntry["GenericName"] = "File Manager";
    assert(firstEntry["GenericName"] == "File Manager");
    
    assert(ilf.group("Another Group")["Name"] == "Commander");
    assert(equal(ilf.group("Another Group").byKeyValue(), [ KeyValueTuple("Name", "Commander"), KeyValueTuple("Comment", "Manage files") ]));
    
    assert(equal(ilf.byGroup().map!(g => g.name), ["First Entry", "Another Group"]));
    
    ilf.removeGroup("Another Group");
    assert(!ilf.group("Another Group"));
    assert(equal(ilf.byGroup().map!(g => g.name), ["First Entry"]));
    
    ilf.addGroup("Another Group");
    assert(ilf.group("Another Group"));
    assert(ilf.group("Another Group").byIniLine().empty);
    assert(ilf.group("Another Group").byKeyValue().empty);
    
    ilf.addGroup("Other Group");
    assert(equal(ilf.byGroup().map!(g => g.name), ["First Entry", "Another Group", "Other Group"]));
    
    const IniLikeFile cilf = ilf;
    static assert(is(typeof(cilf.byGroup())));
    static assert(is(typeof(cilf.group("First Entry").byKeyValue())));
    static assert(is(typeof(cilf.group("First Entry").byIniLine())));
    
    contents = 
`[Group]
GenericName=File manager
[Group]
Name=Commander`;

    assertThrown(new IniLikeFile(iniLikeStringReader(contents)));
    assertNotThrown(new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.ignoreGroupDuplicates));
    
    contents = 
`[Group]
=File manager`;

    assertThrown(new IniLikeFile(iniLikeStringReader(contents)));
    assertNotThrown(new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.ignoreInvalidKeys));
}
