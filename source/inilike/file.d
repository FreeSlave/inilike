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
        None = 0,
        Comment = 1,
        KeyValue = 2
    }
    
    /**
     * Contruct from comment.
     */
    @nogc @safe static IniLikeLine fromComment(string comment) nothrow {
        return IniLikeLine(comment, null, Type.Comment);
    }
    
    /**
     * Construct from key and value.
     */
    @nogc @safe static IniLikeLine fromKeyValue(string key, string value) nothrow {
        return IniLikeLine(key, value, Type.KeyValue);
    }
    
    /**
     * Get comment.
     * Returns: Comment or empty string if type is not Type.Comment.
     */
    @nogc @safe string comment() const nothrow {
        return _type == Type.Comment ? _first : null;
    }
    
    /**
     * Get key.
     * Returns: Key or empty string if type is not Type.KeyValue
     */
    @nogc @safe string key() const nothrow {
        return _type == Type.KeyValue ? _first : null;
    }
    
    /**
     * Get value.
     * Returns: Value or empty string if type is not Type.KeyValue
     */
    @nogc @safe string value() const nothrow {
        return _type == Type.KeyValue ? _second : null;
    }
    
    /**
     * Get type of line.
     */
    @nogc @safe Type type() const nothrow {
        return _type;
    }
    
    /**
     * Assign Type.None to line.
     */
    @nogc @safe void makeNone() nothrow {
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
     * Create instange on IniLikeGroup and set its name to groupName.
     */
    @nogc @safe this(string groupName) nothrow {
        _name = groupName;
    }
    
    /**
     * Returns: The value associated with the key
     * Note: It's an error to access nonexistent value
     * See_Also: value
     */
    @nogc @safe final string opIndex(string key) const nothrow {
        auto i = key in _indices;
        assert(_values[*i].type == IniLikeLine.Type.KeyValue);
        assert(_values[*i].key == key);
        return _values[*i].value;
    }
    
    /**
     * Insert new value or replaces the old one if value associated with key already exists.
     * Returns: Inserted/updated value or null string if key was not added.
     * Throws: $(B Exception) if key is not valid
     */
    @safe final string opIndexAssign(string value, string key) {
        validateKeyValue(key, value);
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
    @safe final string opIndexAssign(string value, string key, string locale) {
        string keyName = localizedKey(key, locale);
        return this[keyName] = value;
    }
    
    /**
     * Tell if group contains value associated with the key.
     */
    @nogc @safe final bool contains(string key) const nothrow {
        return value(key) !is null;
    }
    
    /**
     * Get value by key.
     * Returns: The value associated with the key, or defaultValue if group does not contain such item.
     */
    @nogc @safe final string value(string key, string defaultValue = null) const nothrow {
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
     * Returns: The localized value associated with key and locale, or defaultValue if group does not contain item with this key.
     */
    @safe final string localizedValue(string key, string locale, string defaultValue = null) const nothrow {
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
        
        return value(key, defaultValue);
    }
    
    ///
    unittest 
    {
        auto lilf = new IniLikeFile;
        lilf.addGroup("Entry");
        auto group = lilf.group("Entry");
        assert(group.name == "Entry"); 
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
    }
    
    /**
     * Same as localized version of opIndexAssign, but uses function syntax.
     */
    @safe final void setLocalizedValue(string key, string locale, string value) {
        this[key, locale] = value;
    }
    
    /**
     * Removes entry by key. To remove localized values use localizedKey.
     * See_Also: inilike.common.localizedKey
     */
    @safe final void removeEntry(string key) nothrow {
        auto pick = key in _indices;
        if (pick) {
            _values[*pick].makeNone();
        }
    }
    
    /**
     * Remove all entries satisying ToDelete function. 
     * ToDelete should be function accepting string key and value and return boolean.
     */
    @trusted final void removeEntries(alias ToDelete)()
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
        ilf.group("Group").removeEntry("ToRemove");
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
    @nogc @safe final string name() const nothrow {
        return _name;
    }
    
    /**
     * Returns: Range of $(B IniLikeLine)s included in this group.
     */
    @system final auto byIniLine() const {
        return _values.filter!(v => v.type != IniLikeLine.Type.None);
    }
    
    /**
     * Add comment line into the group.
     * See_Also: byIniLine
     */
    @trusted final void addComment(string comment) nothrow {
        _values ~= IniLikeLine.fromComment(comment);
    }
    
protected:
    /**
     * Validate key and value before setting value to key for this group and throw exception if not valid.
     * Can be reimplemented in derived classes. 
     * Default implementation check if key is not empty string, leaving value unchecked.
     */
    @trusted void validateKeyValue(string key, string value) const {
        enforce(key.length > 0, "key must not be empty");
    }
    
private:
    size_t[string] _indices;
    IniLikeLine[] _values;
    string _name;
}

/**
 * Exception thrown on the file read error.
 */
class IniLikeException : Exception
{
    /**
     * Create IniLikeException with msg, lineNumber and fileName.
     */
    this(string msg, size_t lineNumber, string fileName = null, string file = __FILE__, size_t line = __LINE__, Throwable next = null) pure nothrow @safe {
        super(msg, file, line, next);
        _lineNumber = lineNumber;
        _fileName = fileName;
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
    
private:
    size_t _lineNumber;
    string _fileName;
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
     * See_Also: createGroup
     */
    @trusted void addCommentForGroup(string comment, IniLikeGroup currentGroup, string groupName)
    {
        if (currentGroup) {
            currentGroup.addComment(comment);
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
     *  $(B Exception) if group with such name already exists.
     * See_Also:
     *  addKeyValueForGroup, addCommentForGroup
     */
    @trusted IniLikeGroup createGroup(string groupName)
    {
        enforce(group(groupName) is null, "group already exists");
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
     *  $(B IniLikeException) if error occured while reading the file.
     */
    @safe this(string fileName) {
        this(iniLikeFileReader(fileName), fileName);
    }
    
    /**
     * Read from range of $(B IniLikeLine)s.
     * Note: All exceptions thrown within constructor are turning into IniLikeException.
     * Throws:
     *  $(B IniLikeException) if error occured while parsing.
     */
    @trusted this(IniLikeReader)(IniLikeReader reader, string fileName = null)
    {
        size_t lineNumber = 0;
        IniLikeGroup currentGroup;
        
        version(DigitalMars) {
            static void foo(size_t ) {}
        }
        
        try {
            foreach(line; reader.byFirstLines)
            {
                lineNumber++;
                if (line.isComment || line.strip.empty) {
                    addLeadingComment(line);
                } else {
                    throw new Exception("Expected comment or empty line before any group");
                }
            }
            
            foreach(g; reader.byGroup)
            {
                lineNumber++;
                string groupName = g.name;
                
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
                            throw new Exception("Expected comment, empty line or key value inside group");
                        } else {
                            addKeyValueForGroup(key, value, currentGroup, groupName);
                        }
                    }
                }
            }
            
            _fileName = fileName;
            
        }
        catch (Exception e) {
            throw new IniLikeException(e.msg, lineNumber, fileName, e.file, e.line, e.next);
        }
    }
    
    /**
     * Get group by name.
     * Returns: IniLikeGroup instance associated with groupName or $(B null) if not found.
     * See_Also: byGroup
     */
    @nogc @safe final inout(IniLikeGroup) group(string groupName) nothrow inout {
        auto pick = groupName in _groupIndices;
        if (pick) {
            return _groups[*pick];
        }
        return null;
    }
    
    /**
     * Create new group using groupName.
     * Returns: Newly created instance of IniLikeGroup.
     * Throws: Exception if group with such name already exists or groupName is empty.
     * See_Also: removeGroup, group
     */
    @safe final IniLikeGroup addGroup(string groupName) {
        enforce(groupName.length, "empty group name");
        
        auto iniLikeGroup = createGroup(groupName);
        if (iniLikeGroup !is null) {
            _groupIndices[groupName] = _groups.length;
            _groups ~= iniLikeGroup;
        }
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
    @safe final string saveToString() const {
        auto a = appender!(string[])();
        save(a);
        return a.data.join("\n");
    }
    
    /**
     * Use Output range or delegate to retrieve strings line by line. 
     * Those strings can be written to the file or be showed in text area.
     * Note: returned strings don't have trailing newline character.
     */
    @trusted final void save(OutRange)(OutRange sink) const if (isOutputRange!(OutRange, string)) {
        foreach(line; leadingComments()) {
            put(sink, line);
        }
        
        foreach(group; byGroup()) {
            put(sink, "[" ~ group.name ~ "]");
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
    @nogc @safe final string fileName() nothrow const {
        return _fileName;
    }
    
    @nogc @trusted final auto leadingComments() const nothrow {
        return _leadingComments;
    }
    
    @trusted void addLeadingComment(string line) nothrow {
        _leadingComments ~= line;
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
        assertNotThrown!IniLikeException(ilf.saveToFile(tempFile));
        auto fileContents = cast(string)std.file.read(tempFile);
        static if( __VERSION__ < 2067 ) {
            assert(equal(fileContents.splitLines, contents.splitLines), "Contents should be preserved as is");
        } else {
            assert(equal(fileContents.lineSplitter, contents.lineSplitter), "Contents should be preserved as is");
        }
        
        IniLikeFile filf; 
        assertNotThrown!IniLikeException(filf = new IniLikeFile(tempFile));
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
    assert(equal(ilf.group("Another Group").byKeyValue(), [ keyValueTuple("Name", "Commander"), keyValueTuple("Comment", "Manage files") ]));
    assert(equal(
        ilf.group("Another Group").byIniLine(), 
        [IniLikeLine.fromKeyValue("Name", "Commander"), IniLikeLine.fromKeyValue("Comment", "Manage files"), IniLikeLine.fromComment("# The last comment")]
    ));
    
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
GenericName=Commander`;

    auto shouldThrow = collectException!IniLikeException(new IniLikeFile(iniLikeStringReader(contents), "config.ini"));
    assert(shouldThrow !is null, "Duplicate groups should throw");
    assert(shouldThrow.lineNumber == 3);
    assert(shouldThrow.lineIndex == 2);
    assert(shouldThrow.fileName == "config.ini");
    
    contents = 
`[Group]
Key=Value1
Key=Value2`;

    shouldThrow = collectException!IniLikeException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Duplicate key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents =
`[Group]
Key=Value
=File manager`;

    shouldThrow = collectException!IniLikeException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Empty key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents = 
`[Group]
#Comment
Valid=Key
NotKeyNotGroupNotComment`;

    shouldThrow = collectException!IniLikeException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Invalid entry should throw");
    assert(shouldThrow.lineNumber == 4);
    
    contents = 
`#Comment
NotComment
[Group]
Valid=Key`;
    shouldThrow = collectException!IniLikeException(new IniLikeFile(iniLikeStringReader(contents)));
    assert(shouldThrow !is null, "Invalid comment should throw");
    assert(shouldThrow.lineNumber == 2);
}

