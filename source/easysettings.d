module easysettings;
private import siryul;
private import standardpaths;

private enum settingsFilename = "settings";
private alias SettingsFormat = YAML;

/**
 * Get a list of paths where settings files were found.
 * Params:
 * settingsForma = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * filename = The filename the settings will be loaded from.
 * subdir = The subdirectory that the settings will be loaded from.
 */
auto getSettingsPaths(alias settingsFormat = SettingsFormat)(string name, string subdir, string filename, bool writable) {
	import std.algorithm : cartesianProduct, filter, map;
	import std.experimental.logger : tracef;
	import std.file : exists;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only;
	const subPath = buildPath(name, subdir);
	const candidates = writable.choose(only(writablePath(StandardPath.config, subPath, FolderFlag.create)), standardPaths(StandardPath.config, subPath));
	auto searchPaths = candidates.chain(["."]).cartesianProduct(only(SettingsExtensions!settingsFormat)).map!(x => chainPath(x[0], filename ~ x[1]));
	tracef("Search paths: %s", searchPaths);
	return searchPaths.filter!(x => writable || x.exists);
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
auto loadSettings(T, alias settingsFormat = SettingsFormat)(string name, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.experimental.logger : tracef;
	auto paths = getSettingsPaths!settingsFormat(name, subdir, filename, false);
	if (!paths.empty) {
		tracef("Loading settings from '%s'", paths.front);
		return fromFile!(T, settingsFormat, DeSiryulize.optionalByDefault)(paths.front.text);
	} else {
		saveSettings(T.init, name, filename, subdir);
	}
	return T.init;
}
///
@system unittest {
	struct Settings {
		bool blah;
		string text;
		string[] texts;
	}
	auto settings = loadSettings!Settings("testapp", "settings", "subdir");
	settings.texts = ["a", "b", "c"];
	saveSettings(settings, "testapp", "settings", "subdir");

	auto reloadedSettings = loadSettings!Settings("testapp", "settings", "subdir");
	assert(reloadedSettings == settings);
	assert(reloadedSettings.texts == ["a", "b", "c"]);
}
/**
 * Saves settings. Uses user's settings dir.
 * Params:
 * data = The data that will be saved to the settings file.
 * name = The subdirectory of the settings dir to save the config to. Created if nonexistent.
 * filename = The filename the settings will be saved to.
 * subdir = The subdirectory that the settings will be saved in.
 */
void saveSettings(T, alias settingsFormat = SettingsFormat)(T data, string name, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.exception : enforce;
	auto paths = getSettingsPaths(name, subdir, filename, true);
	enforce (!paths.empty, "No writable paths found");
	safeSave(paths.front.text, data.toString!settingsFormat());
}
///
unittest {
	struct Settings {
		bool blah;
		string text;
		string[] texts;
	}
	saveSettings(Settings(true, "some words", ["c", "b", "a"]), "testapp", "settings", "subdir");

	assert(loadSettings!Settings("testapp", "settings", "subdir") == Settings(true, "some words", ["c", "b", "a"]));
}
/**
 * Deletes settings files for the specified app that are handled by this
 * library. Also removes directory if empty.
 * Params:
 * name = App name.
 * filename = The settings file that will be deleted.
 * subdir = Settings subdirectory to delete.
 */
void deleteSettings(alias settingsFormat = SettingsFormat)(string name, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.file : exists, remove, dirEntries, SpanMode, rmdir;
	import std.path : dirName;
	foreach (path; getSettingsPaths(name, subdir, filename, true)) {
		if (path.exists) {
			remove(path);
			if (path.dirName.text.dirEntries(SpanMode.shallow).empty) {
				rmdir(path.dirName);
			}
		}
	}
}
///
unittest {
	deleteSettings("testapp", "settings", "subdir");
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
	const oldAttributes = getAttributes(testFile);
	version(Windows) {
		import core.sys.windows.winnt : FILE_ATTRIBUTE_READONLY;
		enum readOnly = FILE_ATTRIBUTE_READONLY;
		enum attributesTarget = testFile;
	} else version(Posix) {
		enum readOnly = 555;
		enum attributesTarget = "test";
	}
	setAttributes(attributesTarget, readOnly);
	scope(exit) {
		setAttributes(attributesTarget, oldAttributes);
		remove(testFile);
	}
	assertThrown(safeSave(testFile, ""));
	assert(!(testFile~".tmp").exists);
}
