///
module easysettings.data;

private import siryul;
private import standardpaths;
private import easysettings.util;

private enum defaultFilename = "data";

alias DataFlags = SettingsFlags;

/**
 * Get a list of paths where data files were found.
 * Params:
 * format = The serialization format used to save and load state (YAML, JSON, etc)
 * name = Subdirectory of data dir to save data to. Created if nonexistent.
 * filename = The filename the data will be loaded from.
 * writable = Whether or not the dir needs to be writable.
 * flags = Optional flags for tweaking behaviour.
 * subdir = The subdirectory that the data will be loaded from.
 */
auto getDataPaths(alias format = DocFormat)(string name, string subdir, string filename, bool writable, DataFlags flags = DataFlags.none) {
	return getPaths!format(StandardPath.data, name, subdir, filename, writable, flags);
}

@safe unittest {
	import std.conv : text;
	import std.path : buildPath;
	assert(getDataPaths("test", "", "data", true, DataFlags.writePortable).front.text == buildPath(".", "data.yaml"));
	assert(getDataPaths("test", "", "data", true, DataFlags.none).front.text != buildPath(".", "data.yaml"));
	assert(getDataPaths("test", "", "data", false, DataFlags.none).empty);
}

/**
 * Load program state. Will create file by default. Searches all system-wide
 * state dirs as well as the user's state dir, and loads the first file found.
 * Params:
 * T = Type of data struct to load
 * format = The serialization format used to save and load state (YAML, JSON, etc)
 * name = Subdirectory of data dir to save data to. Created if nonexistent.
 * flags = Optional flags for tweaking loading behaviour.
 * filename = The filename the data will be loaded from.
 * subdir = The subdirectory that the data will be loaded from.
 */
auto loadData(T, alias format = DocFormat)(string name, DataFlags flags = DataFlags.none, string filename = defaultFilename, string subdir = "") {
	return load!(T, format)(StandardPath.data, name, flags, filename, subdir);
}
///
@safe unittest {
	struct Data {
		bool blah;
		string text;
		string[] texts;
	}
	auto data = loadData!Data("testapp", DataFlags.none, "data", "subdir");
	data.texts = ["a", "b", "c"];
	saveData(data, "testapp", DataFlags.none, "data", "subdir");

	auto reloadedData = loadData!Data("testapp", DataFlags.none, "data", "subdir");
	assert(reloadedData == data);
	assert(reloadedData.texts == ["a", "b", "c"]);
}
/**
 * Loads all data files from a subdirectory, with the assumption that each
 * file has the same format.
 * Params:
 * T = Type of data struct to load
 * format = The serialization format used to save and load state (YAML, JSON, etc)
 * name = The main data directory for the application
 * subdir = The subdirectory to load these data files from
 */
auto loadSubdirData(T, alias format = DocFormat)(string name, string subdir) {
	return loadSubdir!(T, format)(StandardPath.data, name, subdir);
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
 * Saves data. Uses user's data dir.
 * Params:
 * T = Type of data struct to save
 * format = The serialization format used to save and load state (YAML, JSON, etc)
 * data = The data that will be saved to the data file.
 * name = The subdirectory of the data dir to save the data to. Created if nonexistent.
 * flags = Optional flags for tweaking saving behaviour.
 * filename = The filename the data will be saved to.
 * subdir = The subdirectory that the data will be saved in.
 */
void saveData(T, alias format = DocFormat)(T data, string name, DataFlags flags = DataFlags.none, string filename = defaultFilename, string subdir = "") {
	save!(T, format)(StandardPath.data, data, name, flags, filename, subdir);
}
///
@safe unittest {
	struct Data {
		bool blah;
		string text;
		string[] texts;
	}
	saveData(Data(true, "some words", ["c", "b", "a"]), "testapp", DataFlags.none, "data", "subdir");

	assert(loadData!Data("testapp", DataFlags.none, "data", "subdir") == Data(true, "some words", ["c", "b", "a"]));

	saveData(Data.init, "testapp", DataFlags.writeMinimal, "data", "subdir");

	assert(loadData!Data("testapp", DataFlags.none, "data", "subdir") == Data.init);
}
/**
 * Deletes data files for the specified app that are handled by this
 * library. Also removes directory if empty.
 * Params:
 * format = The serialization format used to save and load state (YAML, JSON, etc)
 * name = App name.
 * flags = Optional flags for tweaking deletion behaviour.
 * filename = The data file that will be deleted.
 * subdir = Data subdirectory to delete.
 */
void deleteData(alias format = DocFormat)(string name, DataFlags flags = DataFlags.none, string filename = defaultFilename, string subdir = "") {
	deleteDoc!format(StandardPath.data, name, flags, filename, subdir);
}
///
@system unittest {
	deleteData("testapp", DataFlags.none, "data", "subdir");
	deleteData("testapp", DataFlags.none, "data", "mysubdir");
	deleteData("testapp", DataFlags.none, "data", "");
}
