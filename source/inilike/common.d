/**
 * Common functions for dealing with entries in ini-like file.
 * Authors: 
 *  $(LINK2 https://github.com/MyLittleRobo, Roman Chistokhodov)
 * Copyright:
 *  Roman Chistokhodov, 2015-2016
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
    import std.conv : to;
    
    static if( __VERSION__ < 2066 ) enum nogc = 1;
    
    auto keyValueTuple(String)(String key, String value)
    {
        alias KeyValueTuple = Tuple!(String, "key", String, "value");
        return KeyValueTuple(key, value);
    }
}

private @nogc @trusted auto stripLeftChar(inout(char)[] s) pure nothrow
{
    size_t spaceNum = 0;
    while(spaceNum < s.length) {
        const char c = s[spaceNum];
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
        const char c = s[$-1-spaceNum];
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

@nogc @trusted auto parseGroupHeader(inout(char)[] s) pure nothrow
{
    s = s.stripRightChar;
    if (isGroupHeader(s)) {
        return s[1..$-1];
    } else {
        return null;
    }
}

///
unittest
{
    assert(parseGroupHeader("[Group name]") == "Group name");
    assert(parseGroupHeader("NotGroupName") == string.init);
    
    assert(parseGroupHeader("[Group name]".dup) == "Group name".dup);
}

/**
 * Parse entry of kind Key=Value into pair of Key and Value.
 * Returns: tuple of key and value strings or tuple of empty strings if it's is not a key-value entry.
 * Note: this function does not check whether parsed key is valid key.
 * See_Also: isValidKey
 */
@nogc @trusted auto parseKeyValue(String)(String s) pure nothrow if (is(String : const(char)[]))
{
    auto t = s.findSplit("=");
    auto key = t[0];
    auto value = t[2];
    
    if (key.length && t[1].length) {
        return keyValueTuple(key, value);
    }
    return keyValueTuple(String.init, String.init);
}

///
unittest
{
    assert(parseKeyValue("Key=Value") == tuple("Key", "Value"));
    assert(parseKeyValue("Key=") == tuple("Key", string.init));
    assert(parseKeyValue("=Value") == tuple(string.init, string.init));
    assert(parseKeyValue("NotKeyValue") == tuple(string.init, string.init));
    
    assert(parseKeyValue("Key=Value".dup) == tuple("Key".dup, "Value".dup));
}

/**
* Test whether the string is valid key. 
* Only the characters A-Za-z0-9- may be used in key names. See $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s02.html, Basic format of the file)
* Note: this function automatically separate key from locale. It does not check validity of the locale itself.
*/
@nogc @safe bool isValidKey(String)(String key) pure nothrow if (is(String : const(char)[])) {
    key = separateFromLocale(key)[0];
    
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
    assert(isValidKey("Generic-Name[ru_RU]"));
    assert(!isValidKey("Name$"));
    assert(!isValidKey(""));
    assert(!isValidKey("[ru_RU]"));
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
@safe String makeLocaleName(String)(
    String lang, String country = null, 
    String encoding = null, 
    String modifier = null) pure
if (is(String : const(char)[]))
{
    return lang ~ (country.length ? "_".to!String~country : String.init)
                ~ (encoding.length ? ".".to!String~encoding : String.init)
                ~ (modifier.length ? "@".to!String~modifier : String.init);
}

///
unittest
{
    assert(makeLocaleName("ru", "RU") == "ru_RU");
    assert(makeLocaleName("ru", "RU", "UTF-8") == "ru_RU.UTF-8");
    assert(makeLocaleName("ru", "RU", "UTF-8", "mod") == "ru_RU.UTF-8@mod");
    assert(makeLocaleName("ru", string.init, string.init, "mod") == "ru@mod");
    
    assert(makeLocaleName("ru".dup, (char[]).init, (char[]).init, "mod".dup) == "ru@mod".dup);
}

/**
 * Parse locale name into the tuple of 4 values corresponding to language, country, encoding and modifier
 * Returns: Tuple!(string, "lang", string, "country", string, "encoding", string, "modifier")
 * See_Also: makeLocaleName
 */
@nogc @trusted auto parseLocaleName(String)(String locale) pure nothrow if (is(String : const(char)[]))
{
    auto modifiderSplit = findSplit(locale, "@");
    auto modifier = modifiderSplit[2];
    
    auto encodongSplit = findSplit(modifiderSplit[0], ".");
    auto encoding = encodongSplit[2];
    
    auto countrySplit = findSplit(encodongSplit[0], "_");
    auto country = countrySplit[2];
    
    auto lang = countrySplit[0];
    
    alias LocaleTuple = Tuple!(String, "lang", String, "country", String, "encoding", String, "modifier");
    
    return LocaleTuple(lang, country, encoding, modifier);
}

///
unittest 
{
    assert(parseLocaleName("ru_RU.UTF-8@mod") == tuple("ru", "RU", "UTF-8", "mod"));
    assert(parseLocaleName("ru@mod") == tuple("ru", string.init, string.init, "mod"));
    assert(parseLocaleName("ru_RU") == tuple("ru", "RU", string.init, string.init));
    
    assert(parseLocaleName("ru_RU.UTF-8@mod".dup) == tuple("ru".dup, "RU".dup, "UTF-8".dup, "mod".dup));
}

/**
 * Drop encoding part from locale (it's not used in constructing localized keys).
 * Returns: Locale string with encoding part dropped out or original string if encoding was not present.
 */
@safe String dropEncodingPart(String)(String locale) pure nothrow if (is(String : const(char)[]))
{
    auto t = parseLocaleName(locale);
    if (!t.encoding.empty) {
        return makeLocaleName(t.lang, t.country, String.init, t.modifier);
    }
    return locale;
}

///
unittest
{
    assert("ru_RU.UTF-8".dropEncodingPart() == "ru_RU");
    string locale = "ru_RU";
    assert(locale.dropEncodingPart() is locale);
}

/**
 * Construct localized key name from key and locale.
 * Returns: localized key in form key[locale] dropping encoding out if present.
 * See_Also: separateFromLocale
 */
@safe String localizedKey(String)(String key, String locale) pure nothrow if (is(String : const(char)[]))
{
    if (locale.empty) {
        return key;
    }
    return key ~ "[".to!String ~ locale.dropEncodingPart() ~ "]".to!String;
}

///
unittest 
{
    string key = "Name";
    assert(localizedKey(key, "") == key);
    assert(localizedKey("Name", "ru_RU") == "Name[ru_RU]");
    assert(localizedKey("Name", "ru_RU.UTF-8") == "Name[ru_RU]");
}

/**
 * ditto, but constructs locale name from arguments.
 */
@safe String localizedKey(String)(String key, String lang, String country, String modifier = null) pure
{
    return key ~ "[".to!String ~ makeLocaleName(lang, country, String.init, modifier) ~ "]".to!String;
}

///
unittest 
{
    assert(localizedKey("Name", "ru", "RU") == "Name[ru_RU]");
    assert(localizedKey("Name".dup, "ru".dup, "RU".dup) == "Name[ru_RU]".dup);
}

/** 
 * Separate key name into non-localized key and locale name.
 * If key is not localized returns original key and empty string.
 * Returns: tuple of key and locale name.
 * See_Also: localizedKey
 */
@nogc @trusted auto separateFromLocale(String)(String key) pure nothrow if (is(String : const(char)[])) {
    if (key.endsWith("]")) {
        auto t = key.findSplit("[");
        if (t[1].length) {
            return tuple(t[0], t[2][0..$-1]);
        }
    }
    return tuple(key, typeof(key).init);
}

///
unittest 
{
    assert(separateFromLocale("Name[ru_RU]") == tuple("Name", "ru_RU"));
    assert(separateFromLocale("Name") == tuple("Name", string.init));
    
    char[] mutableString = "Hello".dup;
    assert(separateFromLocale(mutableString) == tuple(mutableString, typeof(mutableString).init));
}

/**
 * Choose the better localized value matching to locale between two localized values. The "goodness" is determined using algorithm described in $(LINK2 http://standards.freedesktop.org/desktop-entry-spec/latest/ar01s04.html, Localized values for keys).
 * Params:
 *  locale = original locale to match to
 *  firstLocale = first locale
 *  firstValue = first value
 *  secondLocale = second locale
 *  secondValue = second value
 * Returns: The best alternative among two or empty string if none of alternatives match original locale.
 * Note: value with empty locale is considered better choice than value with locale that does not match the original one.
 */
@nogc @trusted auto chooseLocalizedValue(String)(
    String locale, 
    String firstLocale,  String firstValue, 
    String secondLocale, String secondValue) pure nothrow
{   
    const lt = parseLocaleName(locale);
    const lt1 = parseLocaleName(firstLocale);
    const lt2 = parseLocaleName(secondLocale);
    
    int score1, score2;
    
    if (lt.lang == lt1.lang) {
        score1 = 1 + ((lt.country == lt1.country) ? 2 : 0 ) + ((lt.modifier == lt1.modifier) ? 1 : 0);
    }
    if (lt.lang == lt2.lang) {
        score2 = 1 + ((lt.country == lt2.country) ? 2 : 0 ) + ((lt.modifier == lt2.modifier) ? 1 : 0);
    }
    
    if (score1 == 0 && score2 == 0) {
        if (firstLocale.empty && !firstValue.empty) {
            return tuple(firstLocale, firstValue);
        } else if (secondLocale.empty && !secondValue.empty) {
            return tuple(secondLocale, secondValue);
        } else {
            return tuple(String.init, String.init);
        }
    }
    
    if (score1 >= score2) {
        return tuple(firstLocale, firstValue);
    } else {
        return tuple(secondLocale, secondValue);
    }
}

///
unittest
{
    string locale = "ru_RU.UTF-8@jargon";
    assert(chooseLocalizedValue(string.init, "ru_RU", "Программист", "ru@jargon", "Кодер") == tuple(string.init, string.init));
    assert(chooseLocalizedValue(locale, "fr_FR", "Programmeur", string.init, "Programmer") == tuple(string.init, "Programmer"));
    assert(chooseLocalizedValue(locale, string.init, "Programmer", "de_DE", "Programmierer") == tuple(string.init, "Programmer"));
    assert(chooseLocalizedValue(locale, "fr_FR", "Programmeur", "de_DE", "Programmierer") == tuple(string.init, string.init));
    
    assert(chooseLocalizedValue(string.init, string.init, "Value", string.init, string.init) == tuple(string.init, "Value"));
    assert(chooseLocalizedValue(locale, string.init, "Value", string.init, string.init) == tuple(string.init, "Value"));
    assert(chooseLocalizedValue(locale, string.init, string.init, string.init, "Value") == tuple(string.init, "Value"));
    
    assert(chooseLocalizedValue(locale, "ru_RU", "Программист", "ru@jargon", "Кодер") == tuple("ru_RU", "Программист"));
    assert(chooseLocalizedValue(locale, "ru_RU", "Программист", "ru_RU@jargon", "Кодер") == tuple("ru_RU@jargon", "Кодер"));
    
    assert(chooseLocalizedValue(locale, "ru", "Разработчик", "ru_RU", "Программист") == tuple("ru_RU", "Программист"));
}

/**
 * Check if value needs to be escaped. This function is currently tolerant to single slashes.
 * Returns: true if value needs to escaped, false otherwise.
 */
@nogc @safe bool needEscaping(string value) nothrow pure
{
    for (size_t i=0; i<value.length; ++i) {
        char c = value[i];
        if (c == '\n' || c == '\t' || c == '\r') {
            return true;
        }
    }
    return false;
}

///
unittest
{
    assert("new\nline".needEscaping);
    assert(!`i have \ slash`.needEscaping);
    assert("i\tlike\ttabs".needEscaping);
    assert(!"just a text".needEscaping);
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
@trusted String escapeValue(String)(String value) pure if (is(String : const(char)[])) {
    return value.replace("\\", `\\`.to!String).replace("\n", `\n`.to!String).replace("\r", `\r`.to!String).replace("\t", `\t`.to!String);
}

///
unittest 
{
    assert("a\\next\nline\top".escapeValue() == `a\\next\nline\top`); // notice how the string on the right is raw.
    assert("a\\next\nline\top".dup.escapeValue() == `a\\next\nline\top`.dup);
}


/**
 * Unescape value. If value does not need unescaping this function returns original value.
 * Params:
 *  value = string to unescape
 *  pairs = pairs of escaped characters and their unescaped forms.
 */
@trusted inout(char)[] doUnescape(inout(char)[] value, in Tuple!(char, char)[] pairs) nothrow pure {
    //little optimization to avoid unneeded allocations.
    size_t i = 0;
    for (; i < value.length; i++) {
        if (value[i] == '\\') {
            break;
        }
    }
    if (i == value.length) {
        return value;
    }
    
    auto toReturn = appender!(typeof(value))();
    toReturn.put(value[0..i]);
    
    for (; i < value.length; i++) {
        if (value[i] == '\\') {
            if (i+1 < value.length) {
                const char c = value[i+1];
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

unittest
{
    static immutable Tuple!(char, char)[] pairs = [tuple('\\', '\\')];
    static assert(is(typeof(doUnescape("", pairs)) == string));
    static assert(is(typeof(doUnescape("".dup, pairs)) == char[]));
}


/**
 * Unescapes string. You should unescape values returned by library before displaying until you want keep them as is (e.g., to allow user to edit values in escaped form).
 * Returns: Unescaped string.
 * See_Also: escapeValue
 */
@trusted auto unescapeValue(inout(char)[] value) nothrow pure
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
    assert(`\\next\nline\top`.unescapeValue() == "\\next\nline\top");
    string value = `nounescape`;
    assert(value.unescapeValue() is value); //original is returned.
    assert(`a\\next\nline\top`.dup.unescapeValue() == "a\\next\nline\top".dup);
}
