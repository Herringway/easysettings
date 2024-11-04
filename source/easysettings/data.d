module easysettings.data;

private import siryul;
private import standardpaths;
private import easysettings.util;

private enum settingsFilename = "settings";
private alias DataFormat = YAML;


enum DataFlags {
	none = 0, /// No flags set
	writePortable = 1 << 0, /// Prefer writing to the working directory, but read from other directories as normal
	writeMinimal = 1 << 1, /// Avoid writing values that are identical to the default
	dontWriteNonexistent = 1 << 2, /// Don't write a settings file if none found
}

/**
 * Get a list of paths where settings files were found.
 * Params:
 * settingsFormat = The serialization format used to save and load settings (YAML, JSON, etc)
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * filename = The filename the settings will be loaded from.
 * subdir = The subdirectory that the settings will be loaded from.
 */
auto getDataPaths(alias settingsFormat = DataFormat)(string name, string subdir, string filename, bool writable, DataFlags flags = DataFlags.none) {
	import std.algorithm : cartesianProduct, filter, map;
	import std.conv : text;
	import std.experimental.logger : tracef;
	import std.file : exists;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only, takeNone;
	import std.typecons : BitFlags;
	const bitFlags = BitFlags!DataFlags(flags);
	const subPath = buildPath(name, subdir);
	auto candidates = writable.choose(bitFlags.writePortable.choose(takeNone!(string[])(), only(writablePath(StandardPath.config, subPath, FolderFlag.create))), standardPaths(StandardPath.config, subPath));
	auto searchPaths = candidates.chain(["."]).cartesianProduct(only(DataExtensions!settingsFormat)).map!(x => chainPath(x[0], filename ~ x[1]));
	debug(verbosesettings) tracef("Search paths: %s", searchPaths);
	return searchPaths.filter!(x => writable || x.exists);
}

@safe unittest {
	import std.conv : text;
	import std.path : buildPath;
	assert(getDataPaths("test", "", "settings", true, DataFlags.writePortable).front.text == buildPath(".", "settings.yaml"));
	assert(getDataPaths("test", "", "settings", true, DataFlags.none).front.text != buildPath(".", "settings.yaml"));
	assert(getDataPaths("test", "", "settings", false, DataFlags.none).empty);
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
auto loadData(T, alias settingsFormat = DataFormat)(string name, DataFlags flags = DataFlags.none, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.experimental.logger : tracef;
	auto paths = getDataPaths!settingsFormat(name, subdir, filename, false, flags);
	if (!paths.empty) {
		debug(verbosesettings) tracef("Loading settings from '%s'", paths.front);
		return fromFile!(T, settingsFormat, DeSiryulize.optionalByDefault)(paths.front.text);
	} else if (!(flags & DataFlags.dontWriteNonexistent)) {
		saveData(T.init, name, flags, filename, subdir);
	}
	return T.init;
}
///
@safe unittest {
	struct Data {
		bool blah;
		string text;
		string[] texts;
	}
	auto settings = loadData!Data("testapp", DataFlags.none, "settings", "subdir");
	settings.texts = ["a", "b", "c"];
	saveData(settings, "testapp", DataFlags.none, "settings", "subdir");

	auto reloadedData = loadData!Data("testapp", DataFlags.none, "settings", "subdir");
	assert(reloadedData == settings);
	assert(reloadedData.texts == ["a", "b", "c"]);
}
/**
 * Loads all settings files from a subdirectory, with the assumption that each
 * file has the same format.
 * Params:
 * name = The main settings directory for the application
 * subdir = The subdirectory to load these settings files from
 */
auto loadSubdirData(T, alias settingsFormat = DataFormat)(string name, string subdir) {
	import std.algorithm : cartesianProduct, filter, joiner, map;
	import std.file : dirEntries, exists, SpanMode;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only;
	const subPath = buildPath(name, subdir);
	return standardPaths(StandardPath.config, subPath)
		.cartesianProduct(only(DataExtensions!settingsFormat))
		.filter!(x => x[0].exists)
		.map!(x => dirEntries(x[0], "*"~x[1], SpanMode.depth))
		.joiner()
		.map!(x => fromFile!(T, settingsFormat, DeSiryulize.optionalByDefault)(x));
}
///
@system unittest {
	import std.array : array;
	import std.algorithm.searching : canFind;
	static struct Data {
		uint a;
	}
	saveData(Data(1), "testapp", DataFlags.none, "1", "mysubdir");
	saveData(Data(2), "testapp", DataFlags.none, "2", "mysubdir");
	auto loaded = loadSubdirData!Data("testapp", "mysubdir").array;
	assert(loaded.canFind(Data(1)));
	assert(loaded.canFind(Data(2)));
}

/**
 * Saves settings. Uses user's settings dir.
 * Params:
 * data = The data that will be saved to the settings file.
 * name = The subdirectory of the settings dir to save the config to. Created if nonexistent.
 * filename = The filename the settings will be saved to.
 * subdir = The subdirectory that the settings will be saved in.
 */
void saveData(T, alias settingsFormat = DataFormat)(T data, string name, DataFlags flags = DataFlags.none, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.exception : enforce;
	auto paths = getDataPaths(name, subdir, filename, true, flags);
	enforce (!paths.empty, "No writable paths found");
	if (flags & DataFlags.writeMinimal) {
		safeSave(paths.front.text, toString!(settingsFormat, Siryulize.omitInits)(data));
	} else {
		safeSave(paths.front.text, toString!settingsFormat(data));
	}
}
///
@safe unittest {
	struct Data {
		bool blah;
		string text;
		string[] texts;
	}
	saveData(Data(true, "some words", ["c", "b", "a"]), "testapp", DataFlags.none, "settings", "subdir");

	assert(loadData!Data("testapp", DataFlags.none, "settings", "subdir") == Data(true, "some words", ["c", "b", "a"]));

	saveData(Data.init, "testapp", DataFlags.writeMinimal, "settings", "subdir");

	assert(loadData!Data("testapp", DataFlags.none, "settings", "subdir") == Data.init);
}
/**
 * Deletes settings files for the specified app that are handled by this
 * library. Also removes directory if empty.
 * Params:
 * name = App name.
 * filename = The settings file that will be deleted.
 * subdir = Data subdirectory to delete.
 */
void deleteData(alias settingsFormat = DataFormat)(string name, DataFlags flags = DataFlags.none, string filename = settingsFilename, string subdir = "") {
	import std.conv : text;
	import std.file : exists, remove, dirEntries, SpanMode, rmdir;
	import std.path : dirName;
	foreach (path; getDataPaths(name, subdir, filename, true, flags)) {
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
	deleteData("testapp", DataFlags.none, "settings", "subdir");
	deleteData("testapp", DataFlags.none, "settings", "mysubdir");
	deleteData("testapp", DataFlags.none, "settings", "");
}

private template DataExtensions(T) {
	import std.meta : AliasSeq;
	static if (is(T == YAML)) {
		alias DataExtensions = AliasSeq!(".yaml", ".yml");
	} else static if (is(T == JSON)) {
		alias DataExtensions = AliasSeq!(".json");
	}
}
