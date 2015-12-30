/**
 * Common functions for dealing with entries in ini-like file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015
 * License: 
 *  $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
 * See_Also: 
 *  $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/index.html, Desktop Entry Specification)
 */

module inilike.common;

package {
    import std.algorithm;
    import std.range;
    import std.string;
    import std.traits;
    import std.typecons;
    
    static if( __VERSION__ < 2066 ) enum nogc = 1;
    
    alias LocaleTuple = Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier");
    alias KeyValueTuple = Tuple!(string, "key", string, "value");
}

private @nogc @trusted auto stripLeftChar(inout(char)[] s) pure nothrow
{
    size_t spaceNum = 0;
    while(spaceNum < s.length) {
        char c = s[spaceNum];
        if (c == ' ' || c == '\t') {
            spaceNum++;
        } else {
            break;
        }
    }
    return s[spaceNum..$];
}

private @nogc @trusted auto stripRightChar(inout(char)[] s) pure nothrow
{
    size_t spaceNum = 0;
    while(spaceNum < s.length) {
        char c = s[$-1-spaceNum];
        if (c == ' ' || c == '\t') {
            spaceNum++;
        } else {
            break;
        }
    }
    
    return s[0..$-spaceNum];
}


/**
 * Test whether the string s represents a comment.
 */
@nogc @trusted bool isComment(const(char)[] s) pure nothrow
{
    s = s.stripLeftChar;
    return !s.empty && s[0] == '#';
}

///
unittest
{
    assert( isComment("# Comment"));
    assert( isComment("   # Comment"));
    assert(!isComment("Not comment"));
    assert(!isComment(""));
}

/**
 * Test whether the string s represents a group header.
 * Note: "[]" is not considered as valid group header.
 */
@nogc @trusted bool isGroupHeader(const(char)[] s) pure nothrow
{
    s = s.stripRightChar;
    return s.length > 2 && s[0] == '[' && s[$-1] == ']';
}

///
unittest
{
    assert( isGroupHeader("[Group]"));
    assert( isGroupHeader("[Group]    "));
    assert(!isGroupHeader("[]"));
    assert(!isGroupHeader("[Group"));
    assert(!isGroupHeader("Group]"));
}

/**
 * Retrieve group name from header entry.
 * Returns: group name or empty string if the entry is not group header.
 */

@nogc @trusted string parseGroupHeader(string s) pure nothrow
{
    s = s.stripRightChar;
    if (isGroupHeader(s)) {
        return s[1..$-1];
    } else {
        return string.init;
    }
}

///
unittest
{
    assert(parseGroupHeader("[Group name]") == "Group name");
    assert(parseGroupHeader("NotGroupName") == string.init);
}

/**
 * Parse entry of kind Key=Value into pair of Key and Value.
 * Returns: tuple of key and value strings or tuple of empty strings if it's is not a key-value entry.
 * Note: this function does not check whether parsed key is valid key.
 * See_Also: isValidKey
 */
@nogc @trusted auto parseKeyValue(string s) pure nothrow
{
    auto t = s.findSplit("=");
    auto key = t[0];
    auto value = t[2];
    
    if (t[0].length && t[1].length) {
        return KeyValueTuple(t[0], t[2]);
    }
    return KeyValueTuple(string.init, string.init);
}

///
unittest
{
    assert(parseKeyValue("Key=Value") == tuple("Key", "Value"));
    assert(parseKeyValue("Key=") == tuple("Key", string.init));
    assert(parseKeyValue("=Value") == tuple(string.init, string.init));
    assert(parseKeyValue("NotKeyValue") == tuple(string.init, string.init));
}

/**
* Test whether the string is valid key. 
* Only the characters A-Za-z0-9- may be used in key names. See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s02.html Basic format of the file)
*/
@nogc @safe bool isValidKey(const(char)[] key) pure nothrow {
    @nogc @safe static bool isValidKeyChar(char c) pure nothrow {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
    }
    
    if (key.empty) {
        return false;
    }
    for (size_t i = 0; i<key.length; ++i) {
        if (!isValidKeyChar(key[i])) {
            return false;
        }
    }
    return true;
}

///
unittest
{
    assert(isValidKey("Generic-Name"));
    assert(!isValidKey("Name$"));
    assert(!isValidKey(""));
}

/**
 * Test whether the entry value represents true
 */
@nogc @safe bool isTrue(const(char)[] value) pure nothrow {
    return (value == "true" || value == "1");
}

///
unittest 
{
    assert(isTrue("true"));
    assert(isTrue("1"));
    assert(!isTrue("not boolean"));
}

/**
 * Test whether the entry value represents false
 */
@nogc @safe bool isFalse(const(char)[] value) pure nothrow {
    return (value == "false" || value == "0");
}

///
unittest 
{
    assert(isFalse("false"));
    assert(isFalse("0"));
    assert(!isFalse("not boolean"));
}

/**
 * Check if the entry value can be interpreted as boolean value.
 * See_Also: isTrue, isFalse
 */
@nogc @safe bool isBoolean(const(char)[] value) pure nothrow {
    return isTrue(value) || isFalse(value);
}

///
unittest 
{
    assert(isBoolean("true"));
    assert(isBoolean("1"));
    assert(isBoolean("false"));
    assert(isBoolean("0"));
    assert(!isBoolean("not boolean"));
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

///
unittest
{
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", null, null, "mod") == "ru@mod");
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

///
unittest 
{
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    assert(parseLocaleName("ru_RU") == tuple("ru", "RU", string.init, string.init));
}

/**
 * Construct localized key name from key and locale.
 * Returns: localized key in form key[locale]. Automatically omits locale encoding if present.
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

///
unittest 
{
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru_RU.UTF-8") == "Name[ru_RU]");
}

/**
 * ditto, but constructs locale name from arguments.
 */
@safe string localizedKey(string key, string lang, string country, string modifier = null) pure nothrow
{
    return key ~ "[" ~ makeLocaleName(lang, country, null, modifier) ~ "]";
}

///
unittest 
{
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
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

///
unittest 
{
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
}

/**
 * Escapes string by replacing special symbols with escaped sequences. 
 * These symbols are: '\\' (backslash), '\n' (newline), '\r' (carriage return) and '\t' (tab).
 * Note: 
 *  Currently the library stores values as they were loaded from file, i.e. escaped. 
 *  To keep things consistent you should take care about escaping the value before inserting. The library will not do it for you.
 * Returns: Escaped string.
 * See_Also: unescapeValue
 */
@trusted string escapeValue(string value) nothrow pure {
    return value.replace("\\", `\\`).replace("\n", `\n`).replace("\r", `\r`).replace("\t", `\t`);
}

///
unittest 
{
    assert("a\\next\nline\top".escapeValue() == `a\\next\nline\top`); // notice how the string on the right is raw.
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

///
unittest 
{
    assert(`a\\next\nline\top`.unescapeValue() == "a\\next\nline\top"); // notice how the string on the left is raw.
}
