/**
 * Class representation of ini-like file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.file;

private import std.exception;

import inilike.common;
import inilike.range;

struct IniLikeLine
{
    enum Type
    {
        None = 0,
        Comment = 1,
        KeyValue = 2
    }
    
    @nogc @safe static IniLikeLine fromComment(string comment) nothrow {
        return IniLikeLine(comment, null, Type.Comment);
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
 * This class represents the group (section) in the ini-like file. 
 * You can create and use instances of this class only in the context of $(B IniLikeFile) or its derivatives.
 * Note: Keys are case-sensitive.
 */
final class IniLikeGroup
{
private:
    @nogc @safe this(string name) nothrow {
        _name = name;
    }
    
public:
    
    /**
     * Returns: The value associated with the key
     * Note: It's an error to access nonexistent value
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
     * Returns: Inserted/updated value
     * Throws: $(B Exception) if key is not valid
     */
    @safe string opIndexAssign(string value, string key) {
        enforce(isValidKey(key), "key is invalid");
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
     * Returns: The value associated with the key, or defaultValue if group does not contain such item.
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
     * Returns: The localized value associated with key and locale, or defaultValue if group does not contain item with this key.
     */
    @safe string localizedValue(string key, string locale, string defaultValue = null) const nothrow {
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
     * Returns: Range of Tuple!(string, "key", string, "value")
     */
    @nogc @safe auto byKeyValue() const nothrow {
        return _values.filter!(v => v.type == IniLikeLine.Type.KeyValue).map!(v => KeyValueTuple(v.key, v.value));
    }
    
    /**
     * Get name of this group.
     * Returns: The name of this group.
     */
    @nogc @safe string name() const nothrow {
        return _name;
    }
    
    /**
     * Returns: Range of $(B IniLikeLine)s included in this group.
     * Note: This does not include Group line itself.
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
 * Ini-like file.
 * 
 */
class IniLikeFile
{
public:
    ///Flags to manage .ini like file reading
    enum ReadOptions
    {
        noOptions = 0,              /// Read all groups, skip comments and empty lines, stop on any error.
        //firstGroupOnly = 1,         /// Ignore other groups than the first one.
        preserveComments = 2,       /// Preserve comments and empty lines. Use this when you want to keep them across writing.
        ignoreGroupDuplicates = 4,  /// Ignore group duplicates. The first found will be used.
        ignoreInvalidKeys = 8,      /// Skip invalid keys during parsing.
        ignoreKeyDuplicates = 16    /// Ignore key duplicates. The first found will be used.
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
    @trusted this(IniLikeReader)(IniLikeReader reader, ReadOptions options = ReadOptions.noOptions, string fileName = null)
    {
        size_t lineNumber = 0;
        IniLikeGroup currentGroup;
        bool ignoreKeyValues;
        
        version(DigitalMars) {
            static void foo(size_t val) {}
        }
        
        try {
            foreach(line; reader.byFirstLines)
            {
                lineNumber++;
                if (line.isComment || line.strip.empty) {
                    if (options & ReadOptions.preserveComments) {
                        addFirstComment(line);
                    }
                } else {
                    throw new Exception("Expected comment or empty line before any group");
                }
            }
            
            foreach(g; reader.byGroup)
            {
                lineNumber++;
                
                version(DigitalMars) {
                    foo(lineNumber); //fix dmd codgen bug with -O
                }
                
                ignoreKeyValues = false;
                
                if ((options & ReadOptions.ignoreGroupDuplicates) && group(g.name)) {
                    ignoreKeyValues = true;
                } else {
                    currentGroup = addGroup(g.name);
                }
                
                foreach(line; g.byEntry)
                {
                    lineNumber++;
                    
                    if (ignoreKeyValues) {
                        continue;
                    }
                    
                    if (line.isComment || line.strip.empty) {
                        currentGroup.addComment(line);
                    } else {
                        auto t = parseKeyValue(line);
                        
                        string key = t.key.stripRight;
                        string value = t.value.stripLeft;
                        
                        if (key.length) {
                            if (!isValidKey(key)) {
                                if (options & ReadOptions.ignoreInvalidKeys) {
                                    continue;
                                } else {
                                    throw new Exception("invalid key");
                                }
                            }
                            
                            if (currentGroup.contains(key)) {
                                if (options & ReadOptions.ignoreKeyDuplicates) {
                                    continue;
                                } else {
                                    throw new Exception("key duplicate");
                                }
                            } else {
                                currentGroup[key] = t[1];
                            }
                        } else {
                            throw new Exception("Expected comment, empty line or key value inside group");
                        }
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
     * Returns: Newly created instance of IniLikeGroup.
     * Throws: Exception if group with such name already exists or groupName is empty.
     * See_Also: removeGroup, group
     */
    @safe IniLikeGroup addGroup(string groupName) {
        enforce(groupName.length, "empty group name");
        enforce(group(groupName) is null, "group already exists");
        
        auto iniLikeGroup = new IniLikeGroup(groupName);
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
        import std.stdio;
        
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
    @safe string saveToString() const {
        auto a = appender!(string[])();
        save(a);
        return a.data.join("\n");
    }
    
    /**
     * Use Output range or delegate to retrieve strings line by line. 
     * Those strings can be written to the file or be showed in text area.
     * Note: returned strings don't have trailing newline character.
     */
    @trusted const void save(OutRange)(OutRange sink) if (isOutputRange!(OutRange, string)) {
        foreach(line; firstComments()) {
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
    @nogc @safe string fileName() nothrow const {
        return _fileName;
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

    auto ilf = new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.preserveComments, "contents.ini");
    assert(ilf.fileName() == "contents.ini");
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
        assertNotThrown!IniLikeException(filf = new IniLikeFile(tempFile, IniLikeFile.ReadOptions.preserveComments));
        assert(filf.fileName() == tempFile);
        remove(tempFile);
    } catch(Exception e) {
        //probably some environment issue unrelated to unittest itself, e.g. could not write to file.
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
GenericName=Commander`;

    IniLikeException shouldThrow = null;
    try {
        new IniLikeFile(iniLikeStringReader(contents));
    } catch(IniLikeException e) {
        shouldThrow = e;
    }
    assert(shouldThrow !is null, "Duplicate groups should throw");
    assert(shouldThrow.lineNumber == 3);
    
    ilf = new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.ignoreGroupDuplicates);
    assert(ilf.group("Group").value("GenericName") == "File manager");
    
    contents = 
`[Group]
Key=Value1
Key=Value2`;

    try {
        shouldThrow = null;
        new IniLikeFile(iniLikeStringReader(contents));
    } catch(IniLikeException e) {
        shouldThrow = e;
    }
    
    assert(shouldThrow !is null, "Duplicate key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    ilf = new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.ignoreKeyDuplicates);
    assert(ilf.group("Group").value("Key") == "Value1");
    
    contents = 
`[Group]
$#=File manager`;

    try {
        shouldThrow = null;
        new IniLikeFile(iniLikeStringReader(contents));
    } catch(IniLikeException e) {
        shouldThrow = e;
    }
    assert(shouldThrow !is null, "Invalid key should throw");
    assert(shouldThrow.lineNumber == 2);
    assertNotThrown(new IniLikeFile(iniLikeStringReader(contents), IniLikeFile.ReadOptions.ignoreInvalidKeys));
    
    contents =
`[Group]
Key=Value
=File manager`;
    try {
        shouldThrow = null;
        new IniLikeFile(iniLikeStringReader(contents));
    } catch(IniLikeException e) {
        shouldThrow = e;
    }
    assert(shouldThrow !is null, "Empty key should throw");
    assert(shouldThrow.lineNumber == 3);
    
    contents = 
`[Group]
#Comment
Valid=Key
NotKeyNotGroupNotComment`;

    try {
        shouldThrow = null;
        new IniLikeFile(iniLikeStringReader(contents));
    } catch(IniLikeException e) {
        shouldThrow = e;
    }
    assert(shouldThrow !is null, "Invalid entry should throw");
    assert(shouldThrow.lineNumber == 4);
    
    contents = 
`#Comment
NotComment
[Group]
Valid=Key`;
    try {
        shouldThrow = null;
        new IniLikeFile(iniLikeStringReader(contents));
    } catch(IniLikeException e) {
        shouldThrow = e;
    }
    assert(shouldThrow !is null, "Invalid comment should throw");
    assert(shouldThrow.lineNumber == 2);
}

