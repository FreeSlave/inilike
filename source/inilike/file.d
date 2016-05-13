/**
 * Class representation of ini-like file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.file;

private import std.exception;

import inilike.common;
public import inilike.range;

private @trusted string makeComment(string line) pure nothrow
{
    if (line.length && line[$-1] == '\n') {
        line = line[0..$-1];
    }
    if (!line.isComment && line.length) {
        line = '#' ~ line;
    }
    line = line.replace("\n", " ");
    return line;
}

/**
 * Line in group.
 */
struct IniLikeLine
{
    /**
     * Type of line.
     */
    enum Type
    {
        None = 0,   /// deleted or invalid line
        Comment = 1, /// a comment or empty line
        KeyValue = 2 /// key-value pair
    }
    
    /**
     * Contruct from comment.
     */
    @nogc @safe static IniLikeLine fromComment(string comment) nothrow pure {
        return IniLikeLine(comment, null, Type.Comment);
    }
    
    /**
     * Construct from key and value.
     */
    @nogc @safe static IniLikeLine fromKeyValue(string key, string value) nothrow pure {
        return IniLikeLine(key, value, Type.KeyValue);
    }
    
    /**
     * Get comment.
     * Returns: Comment or empty string if type is not Type.Comment.
     */
    @nogc @safe string comment() const nothrow pure {
        return _type == Type.Comment ? _first : null;
    }
    
    /**
     * Get key.
     * Returns: Key or empty string if type is not Type.KeyValue
     */
    @nogc @safe string key() const nothrow pure {
        return _type == Type.KeyValue ? _first : null;
    }
    
    /**
     * Get value.
     * Returns: Value or empty string if type is not Type.KeyValue
     */
    @nogc @safe string value() const nothrow pure {
        return _type == Type.KeyValue ? _second : null;
    }
    
    /**
     * Get type of line.
     */
    @nogc @safe Type type() const nothrow pure {
        return _type;
    }
    
    /**
     * Assign Type.None to line.
     */
    @nogc @safe void makeNone() nothrow pure {
        _type = Type.None;
    }
private:
    string _first;
    string _second;
    Type _type = Type.None;
}


/**
 * This class represents the group (section) in the ini-like file. 
 * You can create and use instances of this class only in the context of $(B IniLikeFile) or its derivatives.
 * Note: Keys are case-sensitive.
 */
class IniLikeGroup
{
public:
    /**
     * Create instance on IniLikeGroup and set its name to groupName.
     */
    protected @nogc @safe this(string groupName) nothrow {
        _name = groupName;
    }
    
    /**
     * Returns: The value associated with the key.
     * Note: The value is not unescaped automatically.
     * Warning: It's an error to access nonexistent value.
     * See_Also: value
     */
    @nogc @safe final string opIndex(string key) const nothrow pure {
        auto i = key in _indices;
        assert(_values[*i].type == IniLikeLine.Type.KeyValue);
        assert(_values[*i].key == key);
        return _values[*i].value;
    }
    
    private @safe final string setKeyValueImpl(string key, string value) nothrow pure
    in {
        assert(!value.needEscaping);
    }
    body {
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
     * Insert new value or replaces the old one if value associated with key already exists.
     * Note: The value is not escaped automatically upon writing. It's your responsibility to escape it.
     * Returns: Inserted/updated value or null string if key was not added.
     * Throws: IniLikeEntryException if key or value is not valid or value needs to be escaped.
     * See_Also: writeEntry
     */
    @safe final string opIndexAssign(string value, string key) {
        validateKeyValue(key, value);
        if (value.needEscaping()) {
            throw new IniLikeEntryException("The value needs to be escaped", _name, key, value);
        }
        return setKeyValueImpl(key, value);
    }
    /**
     * Assign localized value.
     * Note: The value is not escaped automatically upon writing. It's your responsibility to escape it.
     * See_Also: setLocalizedValue, localizedValue
     */
    @safe final string opIndexAssign(string value, string key, string locale) {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    /**
     * Tell if group contains value associated with the key.
     */
    @nogc @safe final bool contains(string key) const nothrow pure {
        return value(key) !is null;
    }
    
    /**
     * Get value by key.
     * Returns: The value associated with the key, or defaultValue if group does not contain such item.
     * Note: The value is not unescaped automatically.
     * See_Also: readEntry, localizedValue
     */
    @nogc @safe final string value(string key, string defaultValue = null) const nothrow pure {
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
     * Get value by key. This function automatically unescape the found value before returning.
     * Returns: The unescaped value associated with key or null if not found.
     * See_Also: value
     */
    @safe final string readEntry(string key, string locale = null) const nothrow pure {
        if (locale.length) {
            return localizedValue(key, locale).unescapeValue();
        } else {
            return value(key).unescapeValue();
        }
    }
    
    /**
     * Set value by key. This function automatically escape the value (you should not escape value yourself) when writing it.
     * Throws: IniLikeEntryException if key or value is not valid.
     */
    @safe final string writeEntry(string key, string value, string locale = null) {
        value = value.escapeValue();
        validateKeyValue(key, value);
        string keyName = localizedKey(key, locale);
        return setKeyValueImpl(keyName, value);
    }
    
    /**
     * Perform locale matching lookup as described in $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html, Localized values for keys).
     * Params:
     *  key = Non-localized key.
     *  locale = Locale in intereset.
     *  nonLocaleFallback = Allow fallback to non-localized version.
     * Returns: The localized value associated with key and locale, 
     * or the value associated with non-localized key if group does not contain localized value and nonLocaleFallback is true.
     * Note: The value is not unescaped automatically.
     * See_Also: value
     */
    @safe final string localizedValue(string key, string locale, bool nonLocaleFallback = true) const nothrow pure {
        //Any ideas how to get rid of this boilerplate and make less allocations?
        const t = parseLocaleName(locale);
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
                pick = value(localizedKey(key, lang, string.init, modifier));
                if (pick !is null) {
                    return pick;
                }
            }
            pick = value(localizedKey(key, lang, string.init));
            if (pick !is null) {
                return pick;
            }
        }
        
        if (nonLocaleFallback) {
            return value(key);
        } else {
            return null;
        }
    }
    
    ///
    unittest 
    {
        auto lilf = new IniLikeFile;
        lilf.addGroup("Entry");
        auto group = lilf.group("Entry");
        assert(group.groupName == "Entry"); 
        group["Name"] = "Programmer";
        group["Name[ru_RU]"] = "Разработчик";
        group["Name[ru@jargon]"] = "Кодер";
        group["Name[ru]"] = "Программист";
        group["Name[de_DE@dialect]"] = "Programmierer"; //just example
        group["Name[fr_FR]"] = "Programmeur";
        group["GenericName"] = "Program";
        group["GenericName[ru]"] = "Программа";
        assert(group["Name"] == "Programmer");
        assert(group.localizedValue("Name", "ru@jargon") == "Кодер");
        assert(group.localizedValue("Name", "ru_RU@jargon") == "Разработчик");
        assert(group.localizedValue("Name", "ru") == "Программист");
        assert(group.localizedValue("Name", "ru_RU.UTF-8") == "Разработчик");
        assert(group.localizedValue("Name", "nonexistent locale") == "Programmer");
        assert(group.localizedValue("Name", "de_DE@dialect") == "Programmierer");
        assert(group.localizedValue("Name", "fr_FR.UTF-8") == "Programmeur");
        assert(group.localizedValue("GenericName", "ru_RU") == "Программа");
        assert(group.localizedValue("GenericName", "fr_FR") == "Program");
        assert(group.localizedValue("GenericName", "fr_FR", false) is null);
    }
    
    /**
     * Same as localized version of opIndexAssign, but uses function syntax.
     * Note: The value is not escaped automatically upon writing. It's your responsibility to escape it.
     * Throws: IniLikeEntryException if key or value is not valid or value needs to be escaped.
     * See_Also: writeEntry
     */
    @safe final void setLocalizedValue(string key, string locale, string value) {
        this[key, locale] = value;
    }
    
    /**
     * Removes entry by key. Do nothing if not value associated with key found.
     * Returns: true if entry was removed, false otherwise.
     */
    @safe final bool removeEntry(string key) nothrow pure {
        auto pick = key in _indices;
        if (pick) {
            _values[*pick].makeNone();
            return true;
        }
        return false;
    }
    
    ///ditto, but remove entry by localized key
    @safe final void removeEntry(string key, string locale) nothrow pure {
        removeEntry(localizedKey(key, locale));
    }
    
    /**
     * Remove all entries satisying ToDelete function. 
     * ToDelete should be function accepting string key and value and return boolean.
     */
    final void removeEntries(alias ToDelete)()
    {
        IniLikeLine[] values;
        
        foreach(line; _values) {
            if (line.type == IniLikeLine.Type.KeyValue && ToDelete(line.key, line.value)) {
                _indices.remove(line.key);
                continue;
            }
            if (line.type == IniLikeLine.Type.None) {
                continue;
            }
            values ~= line;
        }
        
        _values = values;
        foreach(i, line; _values) {
            if (line.type == IniLikeLine.Type.KeyValue) {
                _indices[line.key] = i;
            }
        }
    }
    
    ///
    unittest
    {
        string contents = 
`[Group]
Key1=Value1
Name=Value
# Comment
ToRemove=Value
Key2=Value2
NameGeneric=Value
Key3=Value3`;
        auto ilf = new IniLikeFile(iniLikeStringReader(contents));
        assert(ilf.group("Group").removeEntry("ToRemove"));
        assert(!ilf.group("Group").removeEntry("NonExistent"));
        ilf.group("Group").removeEntries!(function bool(string key, string value) {
            return key.startsWith("Name");
        })();
        
        auto group = ilf.group("Group");
        
        assert(group.value("Key1") == "Value1");
        assert(group.value("Key2") == "Value2");
        assert(group.value("Key3") == "Value3");
        assert(equal(group.byIniLine(), [
                    IniLikeLine.fromKeyValue("Key1", "Value1"), IniLikeLine.fromComment("# Comment"), 
                    IniLikeLine.fromKeyValue("Key2", "Value2"), IniLikeLine.fromKeyValue("Key3", "Value3")]));
        assert(!group.contains("Name"));
        assert(!group.contains("NameGeneric"));
    }
    
    /**
     * Iterate by Key-Value pairs.
     * Returns: Range of Tuple!(string, "key", string, "value").
     * See_Also: value, localizedValue
     */
    @nogc @safe final auto byKeyValue() const nothrow {
        return staticByKeyValue(_values);
    }
    
    /**
     * Empty range of the same type as byKeyValue. Can be used in derived classes if it's needed to have empty range.
     * Returns: Empty range of Tuple!(string, "key", string, "value").
     */
    @nogc @safe static auto emptyByKeyValue() nothrow {
        return staticByKeyValue((IniLikeLine[]).init);
    }
    
    ///
    unittest
    {
        assert(emptyByKeyValue().empty);
        auto group = new IniLikeGroup("Group name");
        static assert(is(typeof(emptyByKeyValue()) == typeof(group.byKeyValue()) ));
    }
    
    private @nogc @safe static auto staticByKeyValue(const(IniLikeLine)[] values) nothrow {
        return values.filter!(v => v.type == IniLikeLine.Type.KeyValue).map!(v => keyValueTuple(v.key, v.value));
    }
    
    /**
     * Get name of this group.
     * Returns: The name of this group.
     */
    @nogc @safe final string groupName() const nothrow pure {
        return _name;
    }
    
    /**
     * Returns: Range of $(B IniLikeLine)s included in this group.
     */
    @trusted final auto byIniLine() const {
        return _values.filter!(v => v.type != IniLikeLine.Type.None);
    }
    
    /**
     * Add comment line into the group.
     * Returns: Line added as comment.
     * See_Also: byIniLine, prependComment
     */
    @safe final string appendComment(string comment) nothrow pure {
        _values ~= IniLikeLine.fromComment(makeComment(comment));
        return _values[$-1].comment();
    }
    
    /**
     * Add comment line at the start of group (after group header, before any key-value pairs).
     * Returns: Line added as comment.
     * See_Also: byIniLine, appendComment
     */
    @safe final string prependComment(string comment) nothrow pure {
        _values = IniLikeLine.fromComment(makeComment(comment)) ~ _values;
        return _values[0].comment();
    }
    
protected:
    /**
     * Validate key and value before setting value to key for this group and throw exception if not valid.
     * Can be reimplemented in derived classes. 
     * Default implementation check if key is not empty string, does not look like comment and does not contain new line or carriage return characters. Value is left unchecked.
     * Params:
     *  key = key to validate.
     *  value = value to validate. Considered to be escaped.
     * Throws: IniLikeEntryException if either key or value is invalid.
     */
    @trusted void validateKeyValue(string key, string value) const {
        if (key.empty || key.strip.empty) {
            throw new IniLikeEntryException("key must not be empty", _name, key, value);
        }
        if (key.isComment()) {
            throw new IniLikeEntryException("key must not start with #", _name, key, value);
        }
        if (key.needEscaping()) {
            throw new IniLikeEntryException("key must not contain new line characters", _name, key, value);
        }
    }
    
    ///
    unittest
    {
        auto ilf = new IniLikeFile();
        ilf.addGroup("Group");
        
        auto entryException = collectException!IniLikeEntryException(ilf.group("Group")[""] = "Value1");
        assert(entryException !is null);
        assert(entryException.groupName == "Group");
        assert(entryException.key == "");
        assert(entryException.value == "Value1");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["    "] = "Value2");
        assert(entryException !is null);
        assert(entryException.key == "    ");
        assert(entryException.value == "Value2");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["Key"] = "New\nline");
        assert(entryException !is null);
        assert(entryException.key == "Key");
        assert(entryException.value == "New\nline");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["New\nLine"] = "Value3");
        assert(entryException !is null);
        assert(entryException.key == "New\nLine");
        assert(entryException.value == "Value3");
        
        entryException = collectException!IniLikeEntryException(ilf.group("Group")["# Comment"] = "Value4");
        assert(entryException !is null);
        assert(entryException.key == "# Comment");
        assert(entryException.value == "Value4");
    }
    
private:
    size_t[string] _indices;
    IniLikeLine[] _values;
    string _name;
}

class IniLikeException : Exception
{
    this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
    }
}

/**
 * Exception thrown on the file read error.
 */
class IniLikeReadException : IniLikeException
{
    /**
     * Create IniLikeReadException with msg, lineNumber and fileName.
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
     * Can be empty if fileName was not given upon IniLikeFile creating.
     * Don't confuse with $(B file) property of $(B Throwable).
     */
    @nogc @safe string fileName() const nothrow pure {
        return _fileName;
    }
    
    /**
     * Original IniLikeEntryException which caused this error.
     * This will have the same msg.
     * Returns: IniLikeEntryException object or null if the cause of error was something else.
     */
    @nogc @safe IniLikeEntryException entryException() nothrow pure {
        return _entryException;
    }
    
private:
    size_t _lineNumber;
    string _fileName;
    IniLikeEntryException _entryException;
}

/**
 * Exception thrown when trying to set invalid key or value.
 */
class IniLikeEntryException : IniLikeException
{
    this(string msg, string group, string key, string value, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _group = group;
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
    
    /**
     * Name of group where error occured.
     */
    @nogc @safe string groupName() const nothrow pure {
        return _group;
    }
    
private:
    string _group;
    string _key;
    string _value;
}

/**
 * Ini-like file.
 * 
 */
class IniLikeFile
{
protected:
    /**
     * Add comment for group.
     * This function is called only in constructor and can be reimplemented in derived classes.
     * Params:
     *  comment = Comment line to add.
     *  currentGroup = The group returned recently by createGroup during parsing. Can be null (e.g. if discarded)
     *  groupName = The name of the currently parsed group. Set even if currentGroup is null.
     * See_Also: createGroup, IniLikeGroup.appendComment
     */
    @trusted void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            currentGroup.appendComment(comment);
        }
    }
    
    /**
     * Add key/value pair for group.
     * This function is called only in constructor and can be reimplemented in derived classes.
     * Params:
     *  key = Key to insert or set.
     *  value = Value to set for key.
     *  currentGroup = The group returned recently by createGroup during parsing. Can be null (e.g. if discarded)
     *  groupName = The name of the currently parsed group. Set even if currentGroup is null.
     * See_Also: createGroup
     */
    @trusted void addKeyValueForGroup(string key, string value, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            if (currentGroup.contains(key)) {
                throw new Exception("key already exists");
            }
            currentGroup[key] = value;
        }
    }
    
    /**
     * Create iniLikeGroup by groupName.
     * This function is called only in constructor and can be reimplemented in derived classes, 
     * e.g. to insert additional checks or create specific derived class depending on groupName.
     * Returned value is later passed to addCommentForGroup and addKeyValueForGroup methods as currentGroup. 
     * Reimplemented method also is allowd to return null.
     * Default implementation just returns empty IniLikeGroup with name set to groupName.
     * Throws:
     *  IniLikeException if group with such name already exists.
     * See_Also:
     *  addKeyValueForGroup, addCommentForGroup
     */
    @trusted IniLikeGroup createGroup(string groupName)
    {
        if (group(groupName) !is null) {
            throw new IniLikeException("group already exists");
        }
        return createEmptyGroup(groupName);
    }
    
    /**
     * Can be used in derived classes to create instance of IniLikeGroup.
     */
    @safe static createEmptyGroup(string groupName) {
        return new IniLikeGroup(groupName);
    }
    
public:
    /**
     * Construct empty IniLikeFile, i.e. without any groups or values
     */
    @nogc @safe this() nothrow {
        
    }
    
    /**
     * Read from file.
     * Throws:
     *  $(B ErrnoException) if file could not be opened.
     *  $(B IniLikeReadException) if error occured while reading the file.
     */
    @trusted this(string fileName) {
        this(iniLikeFileReader(fileName), fileName);
    }
    
    /**
     * Read from range of inilike.range.IniLikeReader.
     * Note: All exceptions thrown within constructor are turning into IniLikeReadException.
     * Throws:
     *  $(B IniLikeReadException) if error occured while parsing.
     */
    this(IniLikeReader)(IniLikeReader reader, string fileName = null)
    {
        size_t lineNumber = 0;
        IniLikeGroup currentGroup;
        
        version(DigitalMars) {
            static void foo(size_t ) {}
        }
        
        try {
            foreach(line; reader.byLeadingLines)
            {
                lineNumber++;
                if (line.isComment || line.strip.empty) {
                    appendLeadingComment(line);
                } else {
                    throw new IniLikeException("Expected comment or empty line before any group");
                }
            }
            
            foreach(g; reader.byGroup)
            {
                lineNumber++;
                string groupName = g.groupName;
                
                version(DigitalMars) {
                    foo(lineNumber); //fix dmd codgen bug with -O
                }
                
                currentGroup = addGroup(groupName);
                
                foreach(line; g.byEntry)
                {
                    lineNumber++;
                    
                    if (line.isComment || line.strip.empty) {
                        addCommentForGroup(line, currentGroup, groupName);
                    } else {
                        const t = parseKeyValue(line);
                        
                        string key = t.key.stripRight;
                        string value = t.value.stripLeft;
                        
                        if (key.length == 0 && value.length == 0) {
                            throw new IniLikeException("Expected comment, empty line or key value inside group");
                        } else {
                            addKeyValueForGroup(key, value, currentGroup, groupName);
                        }
                    }
                }
            }
            
            _fileName = fileName;
            
        }
        catch(IniLikeEntryException e) {
            throw new IniLikeReadException(e.msg, lineNumber, fileName, e, e.file, e.line, e.next);
        }
        catch (Exception e) {
            throw new IniLikeReadException(e.msg, lineNumber, fileName, null, e.file, e.line, e.next);
        }
    }
    
    /**
     * Get group by name.
     * Returns: IniLikeGroup instance associated with groupName or $(B null) if not found.
     * See_Also: byGroup
     */
    @nogc @safe final inout(IniLikeGroup) group(string groupName) nothrow inout pure {
        auto pick = groupName in _groupIndices;
        if (pick) {
            return _groups[*pick];
        }
        return null;
    }
    
    /**
     * Create new group using groupName.
     * Returns: Newly created instance of IniLikeGroup.
     * Throws: IniLikeException if group with such name already exists or groupName is empty.
     * See_Also: removeGroup, group
     */
    @safe final IniLikeGroup addGroup(string groupName) {
        if (groupName.length == 0) {
            throw new IniLikeException("empty group name");
        }
        
        auto iniLikeGroup = createGroup(groupName);
        if (iniLikeGroup !is null) {
            _groupIndices[groupName] = _groups.length;
            _groups ~= iniLikeGroup;
        }
        return iniLikeGroup;
    }
    
    /**
     * Remove group by name. Do nothing if group with such name does not exist.
     * Returns: true if group was deleted, false otherwise.
     * See_Also: addGroup, group
     */
    @safe bool removeGroup(string groupName) nothrow {
        auto pick = groupName in _groupIndices;
        if (pick) {
            _groups[*pick] = null;
            return true;
        } else {
            return false;
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
    @trusted final void saveToFile(string fileName) const {
        import std.stdio : File;
        
        auto f = File(fileName, "w");
        void dg(in string line) {
            f.writeln(line);
        }
        save(&dg);
    }
    
    /**
     * Save object to string using .ini like format.
     * Returns: A string that represents the contents of file.
     * See_Also: saveToFile, save
     */
    @trusted final string saveToString() const {
        auto a = appender!(string[])();
        save(a);
        return a.data.join("\n");
    }
    
    /**
     * Use Output range or delegate to retrieve strings line by line. 
     * Those strings can be written to the file or be showed in text area.
     * Note: returned strings don't have trailing newline character.
     */
    final void save(OutRange)(OutRange sink) const if (isOutputRange!(OutRange, string)) {
        foreach(line; leadingComments()) {
            put(sink, line);
        }
        
        foreach(group; byGroup()) {
            put(sink, "[" ~ group.groupName ~ "]");
            foreach(line; group.byIniLine()) {
                if (line.type == IniLikeLine.Type.Comment) {
                    put(sink, line.comment);
                } else if (line.type == IniLikeLine.Type.KeyValue) {
                    put(sink, line.key ~ "=" ~ line.value);
                }
            }
        }
    }
    
    /**
     * File path where the object was loaded from.
     * Returns: File name as was specified on the object creation.
     */
    @nogc @safe final string fileName() nothrow const pure {
        return _fileName;
    }
    
    /**
     * Leading comments.
     * Returns: Range of leading comments (before any group)
     * See_Also: appendLeadingComment, prependLeadingComment
     */
    @nogc @safe final auto leadingComments() const nothrow pure {
        return _leadingComments;
    }
    
    ///
    unittest
    {
        auto ilf = new IniLikeFile();
        assert(ilf.appendLeadingComment("First") == "#First");
        assert(ilf.appendLeadingComment("#Second") == "#Second");
        assert(ilf.appendLeadingComment("Sneaky\nKey=Value") == "#Sneaky Key=Value");
        assert(ilf.appendLeadingComment("# New Line\n") == "# New Line");
        assert(ilf.appendLeadingComment("") == "");
        assert(ilf.appendLeadingComment("\n") == "");
        assert(ilf.prependLeadingComment("Shebang") == "#Shebang");
        assert(ilf.leadingComments().equal(["#Shebang", "#First", "#Second", "#Sneaky Key=Value", "# New Line", "", ""]));
        ilf.clearLeadingComments();
        assert(ilf.leadingComments().empty);
    }
    
    /**
     * Add leading comment. This will be appended to the list of leadingComments.
     * Note: # will be prepended automatically if line is not empty and does not have # at the start. 
     *  The last new line character will be removed if present. Others will be replaced with whitespaces.
     * Returns: Line that was added as comment.
     * See_Also: leadingComments, prependLeadingComment
     */
    @safe string appendLeadingComment(string line) nothrow {
        line = makeComment(line);
        _leadingComments ~= line;
        return line;
    }
    
    /**
     * Prepend leading comment (e.g. for setting shebang line).
     * Returns: Line that was added as comment.
     * See_Also: leadingComments, appendLeadingComment
     */
    @safe string prependLeadingComment(string line) nothrow pure {
        line = makeComment(line);
        _leadingComments = line ~ _leadingComments;
        return line;
    }
    
    /**
     * Remove all coments met before groups.
     */
    @nogc final @safe void clearLeadingComments() nothrow {
        _leadingComments = null;
    }
    
private:
    string _fileName;
    size_t[string] _groupIndices;
    IniLikeGroup[] _groups;
    string[] _leadingComments;
}

///
unittest
{
    import std.file;
    import std.path;
    
    string contents = 
`# The first comment
[First Entry]
# Comment
GenericName=File manager
GenericName[ru]=Файловый менеджер
NeedUnescape=yes\\i\tneed
NeedUnescape[ru]=да\\я\tнуждаюсь
# Another comment
[Another Group]
Name=Commander
Comment=Manage files
# The last comment`;

    auto ilf = new IniLikeFile(iniLikeStringReader(contents), "contents.ini");
    assert(ilf.fileName() == "contents.ini");
    assert(equal(ilf.leadingComments(), ["# The first comment"]));
    assert(ilf.group("First Entry"));
    assert(ilf.group("Another Group"));
    assert(ilf.saveToString() == contents);
    
    string tempFile = buildPath(tempDir(), "inilike-unittest-tempfile");
    try {
        assertNotThrown!IniLikeReadException(ilf.saveToFile(tempFile));
        auto fileContents = cast(string)std.file.read(tempFile);
        static if( __VERSION__ < 2067 ) {
            assert(equal(fileContents.splitLines, contents.splitLines), "Contents should be preserved as is");
        } else {
            assert(equal(fileContents.lineSplitter, contents.lineSplitter), "Contents should be preserved as is");
        }
        
        IniLikeFile filf; 
        assertNotThrown!IniLikeReadException(filf = new IniLikeFile(tempFile));
        assert(filf.fileName() == tempFile);
        remove(tempFile);
    } catch(Exception e) {
        //environmental error in unittests
    }
    
    auto firstEntry = ilf.group("First Entry");
    
    assert(!firstEntry.contains("NonExistent"));
    assert(firstEntry.contains("GenericName"));
    assert(firstEntry.contains("GenericName[ru]"));
    assert(firstEntry["GenericName"] == "File manager");
    assert(firstEntry.value("GenericName") == "File manager");
    
    assert(firstEntry.value("NeedUnescape") == `yes\\i\tneed`);
    assert(firstEntry.readEntry("NeedUnescape") == "yes\\i\tneed");
    assert(firstEntry.localizedValue("NeedUnescape", "ru") == `да\\я\tнуждаюсь`);
    assert(firstEntry.readEntry("NeedUnescape", "ru") == "да\\я\tнуждаюсь");
    
    firstEntry.writeEntry("NeedEscape", "i\rneed\nescape");
    assert(firstEntry.value("NeedEscape") == `i\rneed\nescape`);
    firstEntry.writeEntry("NeedEscape", "мне\rнужно\nэкранирование");
    assert(firstEntry.localizedValue("NeedEscape", "ru") == `мне\rнужно\nэкранирование`);
    
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
    firstEntry.removeEntry("GenericName", "ru");
    assert(!firstEntry.contains("GenericName[ru]"));
    firstEntry["GenericName"] = "File Manager";
    assert(firstEntry["GenericName"] == "File Manager");
    
    assert(ilf.group("Another Group")["Name"] == "Commander");
    assert(equal(ilf.group("Another Group").byKeyValue(), [ keyValueTuple("Name", "Commander"), keyValueTuple("Comment", "Manage files") ]));
    
    assert(ilf.group("Another Group").appendComment("The lastest comment"));
    assert(ilf.group("Another Group").prependComment("The first comment"));
    
    assert(equal(
        ilf.group("Another Group").byIniLine(), 
        [IniLikeLine.fromComment("#The first comment"), IniLikeLine.fromKeyValue("Name", "Commander"), IniLikeLine.fromKeyValue("Comment", "Manage files"), IniLikeLine.fromComment("# The last comment"), IniLikeLine.fromComment("#The lastest comment")]
    ));
    
    assert(equal(ilf.byGroup().map!(g => g.groupName), ["First Entry", "Another Group"]));
    
    assert(!ilf.removeGroup("NonExistent Group"));
    
    assert(ilf.removeGroup("Another Group"));
    assert(!ilf.group("Another Group"));
    assert(equal(ilf.byGroup().map!(g => g.groupName), ["First Entry"]));
    
    ilf.addGroup("Another Group");
    assert(ilf.group("Another Group"));
    assert(ilf.group("Another Group").byIniLine().empty);
    assert(ilf.group("Another Group").byKeyValue().empty);
    
    ilf.addGroup("Other Group");
    assert(equal(ilf.byGroup().map!(g => g.groupName), ["First Entry", "Another Group", "Other Group"]));
    
    assertThrown!IniLikeException(ilf.addGroup(""));
    
    const IniLikeFile cilf = ilf;
    static assert(is(typeof(cilf.byGroup())));
    static assert(is(typeof(cilf.group("First Entry").byKeyValue())));
    static assert(is(typeof(cilf.group("First Entry").byIniLine())));
    
    contents = 
`[Group]
GenericName=File manager
[Group]
GenericName=Commander`;

    auto shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents), "config.ini"));
    assert(shouldThrow !is null, "Duplicate groups should throw");
    assert(shouldThrow.lineNumber == 3);
    assert(shouldThrow.lineIndex == 2);
    assert(shouldThrow.fileName == "config.ini");
    
    contents = 
`[Group]
Key=Value1
Key=Value2`;

    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Duplicate key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents =
`[Group]
Key=Value
=File manager`;

    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Empty key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents = 
`[Group]
#Comment
Valid=Key
NotKeyNotGroupNotComment`;

    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Invalid entry should throw");
    assert(shouldThrow.lineNumber == 4);
    
    contents = 
`#Comment
NotComment
[Group]
Valid=Key`;
    shouldThrow = collectException!IniLikeReadException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Invalid comment should throw");
    assert(shouldThrow.lineNumber == 2);
}
