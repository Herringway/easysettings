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
auto getSettingsPaths(alias settingsFormat = SettingsFormat)(string name, string subdir, string filename) {
	import std.algorithm : cartesianProduct, filter, map;
	import std.experimental.logger : tracef;
	import std.file : exists;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, only;
	auto searchPaths = standardPaths(StandardPath.config, buildPath(name, subdir)).chain(["."]).cartesianProduct(only(SettingsExtensions!settingsFormat)).map!(x => chainPath(x[0], filename.withExtension(x[1])));
	tracef("Search paths: %s", searchPaths);
	return searchPaths.filter!exists;
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
	auto paths = getSettingsPaths!settingsFormat(name, subdir, filename);
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
	auto settings = loadSettings!Settings("testapp");
	settings.texts = ["a", "b", "c"];
	saveSettings(settings, "testapp");

	auto reloadedSettings = loadSettings!Settings("testapp");
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
	import std.path : buildPath, setExtension;
	import std.file : exists, mkdirRecurse;
	string configPath = writablePath(StandardPath.config, buildPath(name, subdir));
    if (!configPath.exists) {
        mkdirRecurse(configPath);
    }
	data.toFile!settingsFormat(buildPath(configPath, filename.setExtension(SettingsExtensions!settingsFormat[0])));
}
///
unittest {
	struct Settings {
		bool blah;
		string text;
		string[] texts;
	}
	saveSettings(Settings(true, "some words", ["c", "b", "a"]), "testapp");

	assert(loadSettings!Settings("testapp") == Settings(true, "some words", ["c", "b", "a"]));
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
	import std.path : buildPath, dirName, setExtension;
	import std.file : exists, remove, dirEntries, SpanMode, rmdir;
	auto path = buildPath(writablePath(StandardPath.config, buildPath(name, subdir)), filename.setExtension(SettingsExtensions!settingsFormat[0]));
	if (path.exists) {
		remove(path);
	}
	if (path.dirName.exists && path.dirName.dirEntries(SpanMode.shallow).empty) {
		rmdir(path.dirName);
	}
}
///
unittest {
	deleteSettings("testapp");
}

private template SettingsExtensions(T) {
	import std.meta : AliasSeq;
	static if (is(T == YAML)) {
		alias SettingsExtensions = AliasSeq!(".yaml", ".yml");
	} else static if (is(T == JSON)) {
		alias SettingsExtensions = AliasSeq!(".json");
	}
}
