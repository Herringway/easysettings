private import siryul;
private import standardpaths;

private enum settingsFilename = "settings.yml";
private alias settingsFormat = YAML;
/**
 * Load settings. Will create settings file by default. Searches all system-wide
 * settings dirs as well as the user's settings dir, and loads the first file
 * found.
 * Params:
 * T = Type of settings struct to load
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 */
auto loadSettings(T)(string name) {
	import std.algorithm : filter, map;
	import std.range : chain;
	import std.path : exists, buildPath;
	auto paths = standardPaths(StandardPath.config).chain(["."]).map!(x => buildPath(x, name, settingsFilename)).filter!exists;
	if (!paths.empty)
		return fromFile!(T,settingsFormat)(paths.front);
	else
		saveSettings(T.init, name);
	return T.init;
}
///
unittest {
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
 */
void saveSettings(T)(T data, string name) {
	import std.path : exists, buildPath;
	import std.file : mkdir;
	string configPath = buildPath(writablePath(StandardPath.config), name);
    if (!configPath.exists)
        mkdir(configPath);
	data.toFile!settingsFormat(buildPath(configPath, settingsFilename));
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
 */
void deleteSettings(string name) {
	import std.path : buildPath, dirName, exists;
	import std.file : remove, dirEntries, SpanMode, rmdir;
	auto path = buildPath(writablePath(StandardPath.config), name, settingsFilename);
	if (path.exists)
		remove(path);
	if (path.dirName.exists && path.dirName.dirEntries(SpanMode.shallow).empty)
		rmdir(path.dirName);
}
///
unittest {
	deleteSettings("testapp");
}