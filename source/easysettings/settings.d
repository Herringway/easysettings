///
module easysettings.settings;

private import siryul;
private import standardpaths;
private import easysettings.util;

private enum defaultFilename = "settings";

/**
 * Get a list of paths where settings files were found.
 * Params:
 * format = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * filename = The filename the settings will be loaded from.
 * writable = Whether or not the dir needs to be writable.
 * flags = Optional flags for tweaking behaviour.
 * subdir = The subdirectory that the settings will be loaded from.
 */
auto getSettingsPaths(alias format = DocFormat)(string name, string subdir, string filename, bool writable, SettingsFlags flags = SettingsFlags.none) {
	return getPaths!format(StandardPath.config, name, subdir, filename, writable, flags);
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
 * format = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * flags = Optional flags for tweaking behaviour.
 * filename = The filename the settings will be loaded from.
 * subdir = The subdirectory that the settings will be loaded from.
 */
auto loadSettings(T, alias format = DocFormat)(string name, SettingsFlags flags = SettingsFlags.none, string filename = defaultFilename, string subdir = "") {
	return load!(T, format)(StandardPath.config, name, flags, filename, subdir);
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
 * format = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = The main settings directory for the application
 * subdir = The subdirectory to load these settings files from
 */
auto loadSubdirSettings(T, alias format = DocFormat)(string name, string subdir) {
	return loadSubdir!(T, format)(StandardPath.config, name, subdir);
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
 * T = Type of settings struct to save
 * format = The serialization format used to save and load settings (YAML, JSON, etc)
 * data = The data that will be saved to the settings file.
 * name = The subdirectory of the settings dir to save the config to. Created if nonexistent.
 * flags = Optional flags for tweaking behaviour.
 * filename = The filename the settings will be saved to.
 * subdir = The subdirectory that the settings will be saved in.
 */
void saveSettings(T, alias format = DocFormat)(T data, string name, SettingsFlags flags = SettingsFlags.none, string filename = defaultFilename, string subdir = "") {
	save!(T, format)(StandardPath.config, data, name, flags, filename, subdir);
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
 * format = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = App name.
 * flags = Optional flags for tweaking behaviour.
 * filename = The settings file that will be deleted.
 * subdir = Settings subdirectory to delete.
 */
void deleteSettings(alias format = DocFormat)(string name, SettingsFlags flags = SettingsFlags.none, string filename = defaultFilename, string subdir = "") {
	deleteDoc!format(StandardPath.config, name, flags, filename, subdir);
}
///
@system unittest {
	deleteSettings("testapp", SettingsFlags.none, "settings", "subdir");
	deleteSettings("testapp", SettingsFlags.none, "settings", "mysubdir");
	deleteSettings("testapp", SettingsFlags.none, "settings", "");
}
