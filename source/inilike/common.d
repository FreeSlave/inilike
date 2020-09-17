/**
 * Common functions for dealing with entries in ini-like file.
 * Authors:
 *  $(LINK2 https://github.com/FreeSlave, Roman Chistokhodov)
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

    auto keyValueTuple(String)(String key, String value)
    {
        alias KeyValueTuple = Tuple!(String, "key", String, "value");
        return KeyValueTuple(key, value);
    }
}

private @nogc @safe auto simpleStripLeft(inout(char)[] s) pure nothrow
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

private @nogc @safe auto simpleStripRight(inout(char)[] s) pure nothrow
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
 * Test whether the string represents a comment.
 */
@nogc @safe bool isComment(scope const(char)[] s) pure nothrow
{
    s = s.simpleStripLeft;
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
 * Test whether the string represents a group header.
 * Note: "[]" is not considered to be a valid group header.
 */
@nogc @safe bool isGroupHeader(scope const(char)[] s) pure nothrow
{
    s = s.simpleStripRight;
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

@nogc @safe auto parseGroupHeader(inout(char)[] s) pure nothrow
{
    s = s.simpleStripRight;
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
 */
@nogc @trusted auto parseKeyValue(String)(String s) pure nothrow if (isSomeString!String && is(ElementEncodingType!String : char))
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

private @nogc @safe bool simpleCanFind(scope const(char)[] str, char c) pure nothrow
{
    for (size_t i=0; i<str.length; ++i) {
        if (str[i] == c) {
            return true;
        }
    }
    return false;
}

/**
 * Test whether the string is valid key, i.e. does not need escaping, is not a comment and not empty string.
 */
@nogc @safe bool isValidKey(scope const(char)[] key) pure nothrow
{
    if (key.empty || key.simpleStripLeft.simpleStripRight.empty) {
        return false;
    }
    if (key.isComment || key.simpleCanFind('=') || key.needEscaping()) {
        return false;
    }
    return true;
}

///
unittest
{
    assert(isValidKey("Valid key"));
    assert(!isValidKey(""));
    assert(!isValidKey("    "));
    assert(!isValidKey("Sneaky\nKey"));
    assert(!isValidKey("# Sneaky key"));
    assert(!isValidKey("Sneaky=key"));
}

/**
* Test whether the string is valid key in terms of Desktop File Specification.
*
* Not actually used in $(D inilike.file.IniLikeFile), but can be used in derivatives.
* Only the characters A-Za-z0-9- may be used in key names.
* Note: this function automatically separate key from locale. Locale is validated against $(D isValidKey).
* See_Also: $(LINK2 https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s03.html, Basic format of the file), $(D isValidKey)
*/
@nogc @safe bool isValidDesktopFileKey(scope const(char)[] desktopKey) pure nothrow {
    auto t = separateFromLocale(desktopKey);
    auto key = t[0];
    auto locale = t[1];

    if (locale.length && !isValidKey(locale)) {
        return false;
    }

    @nogc @safe static bool isValidDesktopFileKeyChar(char c) pure nothrow {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-';
    }

    if (key.empty) {
        return false;
    }
    for (size_t i = 0; i<key.length; ++i) {
        if (!isValidDesktopFileKeyChar(key[i])) {
            return false;
        }
    }
    return true;
}

///
unittest
{
    assert(isValidDesktopFileKey("Generic-Name"));
    assert(isValidDesktopFileKey("Generic-Name[ru_RU]"));
    assert(!isValidDesktopFileKey("Name$"));
    assert(!isValidDesktopFileKey(""));
    assert(!isValidDesktopFileKey("[ru_RU]"));
    assert(!isValidDesktopFileKey("Name[ru\nRU]"));
}

/**
 * Test whether the entry value represents true.
 * See_Also: $(D isFalse), $(D isBoolean)
 */
@nogc @safe bool isTrue(scope const(char)[] value) pure nothrow {
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
 * Test whether the entry value represents false.
 * See_Also: $(D isTrue), $(D isBoolean)
 */
@nogc @safe bool isFalse(scope const(char)[] value) pure nothrow {
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
 * See_Also: $(D isTrue), $(D isFalse)
 */
@nogc @safe bool isBoolean(scope const(char)[] value) pure nothrow {
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
 * Convert bool to string. Can be used to set boolean values.
 * See_Also: $(D isBoolean)
 */
@nogc @safe string boolToString(bool b) nothrow pure {
    return b ? "true" : "false";
}

///
unittest
{
    assert(boolToString(false) == "false");
    assert(boolToString(true) == "true");
}

/**
 * Make locale name based on language, country, encoding and modifier.
 * Returns: locale name in form lang_COUNTRY.ENCODING@MODIFIER
 * See_Also: $(D parseLocaleName)
 */
@safe String makeLocaleName(String)(
    String lang, String country = null,
    String encoding = null,
    String modifier = null) pure
if (isSomeString!String && is(ElementEncodingType!String : char))
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
 * See_Also: $(D makeLocaleName)
 */
@nogc @trusted auto parseLocaleName(String)(String locale) pure nothrow if (isSomeString!String && is(ElementEncodingType!String : char))
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
@safe String dropEncodingPart(String)(String locale) pure nothrow if (isSomeString!String && is(ElementEncodingType!String : char))
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
 * See_Also: $(D separateFromLocale)
 */
@safe String localizedKey(String)(String key, String locale) pure nothrow if (isSomeString!String && is(ElementEncodingType!String : char))
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
@safe String localizedKey(String)(String key, String lang, String country, String modifier = null) pure if (isSomeString!String && is(ElementEncodingType!String : char))
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
 * See_Also: $(D localizedKey)
 */
@nogc @trusted auto separateFromLocale(String)(String key) pure nothrow if (isSomeString!String && is(ElementEncodingType!String : char)) {
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
 * Between two key locales (i.e. locales found in keys of .ini-like file) select a better match for the provided locale. The "goodness" is determined using algorithm described in $(LINK2 https://specifications.freedesktop.org/desktop-entry-spec/latest/ar01s05.html, Localized values for keys).
 * Params:
 *  locale = original locale to match to
 *  firstKeyLocale = first key locale, can be empty
 *  secondKeyLocale = second key locale, can be empty
 * Returns: a locale which is considered a better alternative or an empty string if none of alternatives match the provided locale.
 * Note: Empty locale is considered a better choice than a locale that does not match the original one.
 * See_Also: $(D separateFromLocale), $(D selectLocalizedValue)
 */
@nogc @trusted auto selectKeyLocale(String)(scope String locale, scope return String firstKeyLocale, scope return String secondKeyLocale)
if (isSomeString!String && is(ElementEncodingType!String : char))
{
    const lt = parseLocaleName(locale);
    const lt1 = parseLocaleName(firstKeyLocale);
    const lt2 = parseLocaleName(secondKeyLocale);

    enum MaxScore = 4;

    alias LocaleTuple = typeof(lt);
    static uint evaluateScore(ref scope LocaleTuple locale, ref scope LocaleTuple applicant)
    {
        if (locale.lang == applicant.lang)
        {
            if (locale.country == applicant.country)
            {
                if (locale.modifier == applicant.modifier)
                {
                    return MaxScore;
                }
                return 3;
            }
            else if (applicant.country.empty)
            {
                if (locale.modifier == applicant.modifier && !locale.modifier.empty)
                    return 2;
                else
                    return 1;
            }
        }
        return 0;
    }

    uint score1 = evaluateScore(lt, lt1);
    if (score1 == MaxScore)
        return firstKeyLocale;
    uint score2 = evaluateScore(lt, lt2);
    if (score2 == MaxScore)
        return secondKeyLocale;

    if (score1 == 0 && score2 == 0)
        return String.init;

    if (score1 >= score2)
        return firstKeyLocale;
    else
        return secondKeyLocale;
}

///
unittest
{
    string locale = "ru_RU.UTF-8@jargon";
    assert(selectKeyLocale(string.init, "ru_RU", "ru@jargon") == string.init);
    assert(selectKeyLocale(locale, "fr_FR", string.init) == string.init);
    assert(selectKeyLocale(locale, string.init, "de_DE") == string.init);
    assert(selectKeyLocale(locale, "fr_FR", "de_DE") == string.init);

    assert(selectKeyLocale(locale, "ru", string.init) == "ru");
    assert(selectKeyLocale(locale, "ru", "ru@jargon") == "ru@jargon");
    assert(selectKeyLocale(locale, "ru_RU", string.init) == "ru_RU");
    assert(selectKeyLocale(locale, "ru_RU", "ru") == "ru_RU");
    assert(selectKeyLocale(locale, "ru_RU", "ru@jargon") == "ru_RU");
    assert(selectKeyLocale(locale, "ru_RU", "ru_RU@jargon") == "ru_RU@jargon");

    assert(selectKeyLocale("en_US.UTF-8", "en", "en_GB") == "en");
    assert(selectKeyLocale("en_US.UTF-8", string.init, "en_GB") == string.init);
}

/**
 * Same as $(D selectKeyLocale), but returns a locale bundled with a value in one tuple.
 */
@nogc @trusted auto selectLocalizedValue(String)(
    scope String locale,
    String firstLocale,  String firstValue,
    String secondLocale, String secondValue) pure nothrow
    if (isSomeString!String && is(ElementEncodingType!String : char))
{
    alias SelectedResult = Tuple!(String, "locale", String, "value");

    auto selected = selectKeyLocale(locale, firstLocale, secondLocale);

    if (selected.empty)
    {
        if (!firstValue.empty && firstLocale.empty)
            return SelectedResult(selected, firstValue);
        else if (!secondValue.empty && secondLocale.empty)
            return SelectedResult(selected, secondValue);
    }
    if (selected == firstLocale)
        return SelectedResult(firstLocale, firstValue);
    else if (selected == secondLocale)
        return SelectedResult(secondLocale, secondValue);

    return SelectedResult(String.init, String.init);
}

///
unittest
{
    string locale = "ru_RU.UTF-8@jargon";
    assert(selectLocalizedValue(string.init, "ru_RU", "Программист", "ru@jargon", "Кодер") == tuple(string.init, string.init));
    assert(selectLocalizedValue(locale, "fr_FR", "Programmeur", string.init, "Programmer") == tuple(string.init, "Programmer"));
    assert(selectLocalizedValue(locale, string.init, "Programmer", "de_DE", "Programmierer") == tuple(string.init, "Programmer"));
    assert(selectLocalizedValue(locale, "fr_FR", "Programmeur", "de_DE", "Programmierer") == tuple(string.init, string.init));

    assert(selectLocalizedValue(string.init, string.init, "Value", string.init, string.init) == tuple(string.init, "Value"));
    assert(selectLocalizedValue(locale, string.init, "Value", string.init, string.init) == tuple(string.init, "Value"));
    assert(selectLocalizedValue(locale, string.init, string.init, string.init, "Value") == tuple(string.init, "Value"));

    assert(selectLocalizedValue(locale, "ru_RU", "Программист", "ru@jargon", "Кодер") == tuple("ru_RU", "Программист"));
    assert(selectLocalizedValue(locale, "ru_RU", "Программист", "ru_RU@jargon", "Кодер") == tuple("ru_RU@jargon", "Кодер"));

    assert(selectLocalizedValue(locale, "ru", "Разработчик", "ru_RU", "Программист") == tuple("ru_RU", "Программист"));
}

alias chooseLocalizedValue = selectLocalizedValue;

/**
 * Check if value needs to be escaped. This function is currently tolerant to single slashes and tabs.
 * Returns: true if value needs to escaped, false otherwise.
 * See_Also: $(D escapeValue)
 */
@nogc @safe bool needEscaping(String)(String value) nothrow pure if (isSomeString!String && is(ElementEncodingType!String : char))
{
    for (size_t i=0; i<value.length; ++i) {
        const c = value[i];
        if (c == '\n' || c == '\r') {
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
    assert("i like\rcarriage\rreturns".needEscaping);
    assert(!"just a text".needEscaping);
}

/**
 * Escapes string by replacing special symbols with escaped sequences.
 * These symbols are: '\\' (backslash), '\n' (newline), '\r' (carriage return) and '\t' (tab).
 * Returns: Escaped string.
 * See_Also: $(D unescapeValue)
 */
@trusted String escapeValue(String)(String value) pure if (isSomeString!String && is(ElementEncodingType!String : char)) {
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
        if (value[i] == '\\' && i+1 < value.length) {
            const char c = value[i+1];
            auto t = pairs.find!"a[0] == b[0]"(tuple(c,c));
            if (!t.empty) {
                toReturn.put(t.front[1]);
                i++;
                continue;
            }
        }
        toReturn.put(value[i]);
    }
    return toReturn.data;
}

unittest
{
    enum Tuple!(char, char)[] pairs = [tuple('\\', '\\')];
    static assert(is(typeof(doUnescape("", pairs)) == string));
    static assert(is(typeof(doUnescape("".dup, pairs)) == char[]));
}


/**
 * Unescapes string. You should unescape values returned by library before displaying until you want keep them as is (e.g., to allow user to edit values in escaped form).
 * Returns: Unescaped string.
 * See_Also: $(D escapeValue), $(D doUnescape)
 */
@safe inout(char)[] unescapeValue(inout(char)[] value) nothrow pure
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
