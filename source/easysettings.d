module easysettings;
private import siryul;
private import standardpaths;

private enum settingsFilename = "settings";
private alias SettingsFormat = YAML;


enum SettingsFlags {
	none = 0, /// No flags set
	writePortable = 1 << 0, /// Prefer writing to the working directory, but read from other directories as normal
	writeMinimal = 1 << 1, /// Avoid writing values that are identical to the default
	dontWriteNonexistent = 1 << 2, /// Don't write a settings file if none found
}

/**
 * Get a list of paths where settings files were found.
 * Params:
 * settingsForma = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * filename = The filename the settings will be loaded from.
 * subdir = The subdirectory that the settings will be loaded from.
 */
auto getSettingsPaths(alias settingsFormat = SettingsFormat)(string name, string subdir, string filename, bool writable, SettingsFlags flags = SettingsFlags.none) {
	import std.algorithm : cartesianProduct, filter, map;
	import std.conv : text;
	import std.experimental.logger : tracef;
	import std.file : exists;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only, takeNone;
	import std.typecons : BitFlags;
	const bitFlags = BitFlags!SettingsFlags(flags);
	const subPath = buildPath(name, subdir);
	auto candidates = writable.choose(bitFlags.writePortable.choose(takeNone!(string[])(), only(writablePath(StandardPath.config, subPath, FolderFlag.create))), standardPaths(StandardPath.config, subPath));
	auto searchPaths = candidates.chain(["."]).cartesianProduct(only(SettingsExtensions!settingsFormat)).map!(x => chainPath(x[0], filename ~ x[1]));
	debug(verbosesettings) tracef("Search paths: %s", searchPaths);
	return searchPaths.filter!(x => writable || x.exists);
}

@safe unittest {
	import std.conv : text;
	import std.path : buildPath;
	assert(getSettingsPaths("test", "", "settings", true, SettingsFlags.writePortable).front.text == buildPath(".", "settings.yaml"));
	assert(getSettingsPaths("test", "", "settings", true, SettingsFlags.none).front.text != buildPath(".", "settings.yaml"));
	assert(getSettingsPaths("test", "", "settings", false, SettingsFlags.none).empty);
}

/**
 * Load settings. Will create settings file by default. Searches all system-wide
 * settings dirs as well as the user's settings dir, and loads the first file
 * found.
 * Params:
 * T = Type of settings struct to load
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * filename = The filename the settings will be loaded from.
 * subdir = The subdirectory that the settings will be loaded from.
 */
auto loadSettings(T, alias settingsFormat = SettingsFormat)(string name, SettingsFlags flags = SettingsFlags.none, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.experimental.logger : tracef;
	auto paths = getSettingsPaths!settingsFormat(name, subdir, filename, false, flags);
	if (!paths.empty) {
		debug(verbosesettings) tracef("Loading settings from '%s'", paths.front);
		return fromFile!(T, settingsFormat, DeSiryulize.optionalByDefault)(paths.front.text);
	} else if (!(flags & SettingsFlags.dontWriteNonexistent)) {
		saveSettings(T.init, name, flags, filename, subdir);
	}
	return T.init;
}
///
@safe unittest {
	struct Settings {
		bool blah;
		string text;
		string[] texts;
	}
	auto settings = loadSettings!Settings("testapp", SettingsFlags.none, "settings", "subdir");
	settings.texts = ["a", "b", "c"];
	saveSettings(settings, "testapp", SettingsFlags.none, "settings", "subdir");

	auto reloadedSettings = loadSettings!Settings("testapp", SettingsFlags.none, "settings", "subdir");
	assert(reloadedSettings == settings);
	assert(reloadedSettings.texts == ["a", "b", "c"]);
}
/**
 * Loads all settings files from a subdirectory, with the assumption that each
 * file has the same format.
 * Params:
 * name = The main settings directory for the application
 * subdir = The subdirectory to load these settings files from
 */
auto loadSubdirSettings(T, alias settingsFormat = SettingsFormat)(string name, string subdir) {
	import std.algorithm : cartesianProduct, filter, joiner, map;
	import std.file : dirEntries, exists, SpanMode;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only;
	const subPath = buildPath(name, subdir);
	return standardPaths(StandardPath.config, subPath)
		.cartesianProduct(only(SettingsExtensions!settingsFormat))
		.filter!(x => x[0].exists)
		.map!(x => dirEntries(x[0], "*"~x[1], SpanMode.depth))
		.joiner()
		.map!(x => fromFile!(T, settingsFormat, DeSiryulize.optionalByDefault)(x));
}
///
@system unittest {
	import std.array : array;
	import std.algorithm.searching : canFind;
	static struct Settings {
		uint a;
	}
	saveSettings(Settings(1), "testapp", SettingsFlags.none, "1", "mysubdir");
	saveSettings(Settings(2), "testapp", SettingsFlags.none, "2", "mysubdir");
	auto loaded = loadSubdirSettings!Settings("testapp", "mysubdir").array;
	assert(loaded.canFind(Settings(1)));
	assert(loaded.canFind(Settings(2)));
}

/**
 * Saves settings. Uses user's settings dir.
 * Params:
 * data = The data that will be saved to the settings file.
 * name = The subdirectory of the settings dir to save the config to. Created if nonexistent.
 * filename = The filename the settings will be saved to.
 * subdir = The subdirectory that the settings will be saved in.
 */
void saveSettings(T, alias settingsFormat = SettingsFormat)(T data, string name, SettingsFlags flags = SettingsFlags.none, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.exception : enforce;
	auto paths = getSettingsPaths(name, subdir, filename, true, flags);
	enforce (!paths.empty, "No writable paths found");
	if (flags & SettingsFlags.writeMinimal) {
		safeSave(paths.front.text, toString!(settingsFormat, Siryulize.omitInits)(data));
	} else {
		safeSave(paths.front.text, toString!settingsFormat(data));
	}
}
///
@safe unittest {
	struct Settings {
		bool blah;
		string text;
		string[] texts;
	}
	saveSettings(Settings(true, "some words", ["c", "b", "a"]), "testapp", SettingsFlags.none, "settings", "subdir");

	assert(loadSettings!Settings("testapp", SettingsFlags.none, "settings", "subdir") == Settings(true, "some words", ["c", "b", "a"]));

	saveSettings(Settings.init, "testapp", SettingsFlags.writeMinimal, "settings", "subdir");

	assert(loadSettings!Settings("testapp", SettingsFlags.none, "settings", "subdir") == Settings.init);
}
/**
 * Deletes settings files for the specified app that are handled by this
 * library. Also removes directory if empty.
 * Params:
 * name = App name.
 * filename = The settings file that will be deleted.
 * subdir = Settings subdirectory to delete.
 */
void deleteSettings(alias settingsFormat = SettingsFormat)(string name, SettingsFlags flags = SettingsFlags.none, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.file : exists, remove, dirEntries, SpanMode, rmdir;
	import std.path : dirName;
	foreach (path; getSettingsPaths(name, subdir, filename, true, flags)) {
		if (path.exists) {
			remove(path);
			if (path.dirName.text.dirEntries(SpanMode.shallow).empty) {
				rmdir(path.dirName);
			}
		}
	}
}
///
@system unittest {
	deleteSettings("testapp", SettingsFlags.none, "settings", "subdir");
	deleteSettings("testapp", SettingsFlags.none, "settings", "mysubdir");
	deleteSettings("testapp", SettingsFlags.none, "settings", "");
}

private template SettingsExtensions(T) {
	import std.meta : AliasSeq;
	static if (is(T == YAML)) {
		alias SettingsExtensions = AliasSeq!(".yaml", ".yml");
	} else static if (is(T == JSON)) {
		alias SettingsExtensions = AliasSeq!(".json");
	}
}

/** Safely save a text file. If something goes wrong while writing, the new
 * file is simply discarded while the old one is untouched
 */
void safeSave(string path, string data) @safe {
	import std.file : exists, remove, rename, write;
	import std.path : setExtension;
	const tmpFile = path.setExtension(".tmp");
	scope(exit) {
		if (tmpFile.exists) {
			remove(tmpFile);
		}
	}
	write(tmpFile, data);
	if (path.exists) {
		remove(path);
	}
	rename(tmpFile, path);
}

@safe unittest {
	import std.exception : assertThrown;
	import std.file : exists, getAttributes, mkdir, remove, rmdir, setAttributes;
	import std.path : buildPath;
	enum testdir = "test";
	enum testFile = buildPath(testdir, "test.txt");
	mkdir(testdir);
	scope(exit) {
		rmdir(testdir);
	}
	safeSave(testFile, "");
	version(Windows) {
		import core.sys.windows.winnt : FILE_ATTRIBUTE_READONLY;
		enum readOnly = FILE_ATTRIBUTE_READONLY;
		enum attributesTarget = testFile;
	} else version(Posix) {
		enum readOnly = 555;
		enum attributesTarget = "test";
	}
	const oldAttributes = getAttributes(attributesTarget);
	setAttributes(attributesTarget, readOnly);
	scope(exit) {
		setAttributes(attributesTarget, oldAttributes);
		remove(testFile);
	}
	assertThrown(safeSave(testFile, ""));
	assert(!(testFile~".tmp").exists);
}
