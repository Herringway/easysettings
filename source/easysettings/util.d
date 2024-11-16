module easysettings.util;

import standardpaths;
import siryul;

package alias DocFormat = YAML;

enum SettingsFlags {
	none = 0, /// No flags set
	writePortable = 1 << 0, /// Prefer writing to the working directory, but read from other directories as normal
	writeMinimal = 1 << 1, /// Avoid writing values that are identical to the default
	dontWriteNonexistent = 1 << 2, /// Don't write a settings file if none found
}

package:
/**
 * Get a list of paths where settings files were found.
 * Params:
 * format = The serialization format used to save and load settings (YAML, JSON, etc)
 * standardPath = Type of path to use.
 * name = Subdirectory of settings dir to save config to. Created if nonexistent.
 * filename = The filename the settings will be loaded from.
 * writable = Whether or not non-writable paths should be included.
 * subdir = The subdirectory that the settings will be loaded from.
 * flags = Optional flags for tweaking behaviour.
 */
auto getPaths(alias format)(StandardPath standardPath, string name, string subdir, string filename, bool writable, SettingsFlags flags) {
	import std.algorithm : cartesianProduct, filter, map;
	import std.conv : text;
	import std.experimental.logger : tracef;
	import std.file : exists;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only, takeNone;
	import std.typecons : BitFlags;
	const bitFlags = BitFlags!SettingsFlags(flags);
	const subPath = buildPath(name, subdir);
	auto candidates = writable.choose(bitFlags.writePortable.choose(takeNone!(string[])(), only(writablePath(standardPath, subPath, FolderFlag.create))), standardPaths(standardPath, subPath));
	auto searchPaths = candidates.chain(["."]).cartesianProduct(only(Extensions!format)).map!(x => chainPath(x[0], filename ~ x[1]));
	debug(verbosesettings) tracef("Search paths: %s", searchPaths);
	return searchPaths.filter!(x => writable || x.exists);
}

/**
 * Load a document. Will create file by default. Searches all system-wide
 * dirs as well as the user's dir, and loads the first file found.
 * Params:
 * T = Type of data struct to load
 * standardPath = Type of path to use.
 * name = Subdirectory of dir to save to. Created if nonexistent.
 * flags = Optional flags for tweaking behaviour.
 * filename = The filename the data will be loaded from.
 * subdir = The subdirectory that the data will be loaded from.
 */
auto load(T, alias format)(StandardPath standardPath, string name, SettingsFlags flags, string filename, string subdir) {
	import std.conv : text;
	import std.experimental.logger : tracef;
	auto paths = getPaths!format(standardPath, name, subdir, filename, false, flags);
	if (!paths.empty) {
		debug(verbosesettings) tracef("Loading settings from '%s'", paths.front);
		return fromFile!(T, format, DeSiryulize.optionalByDefault)(paths.front.text);
	} else if (!(flags & SettingsFlags.dontWriteNonexistent)) {
		save!(T, format)(standardPath, T.init, name, flags, filename, subdir);
	}
	return T.init;
}

/**
 * Loads all settings files from a subdirectory, with the assumption that each
 * file has the same format.
 * Params:
 * standardPath = Type of path to use.
 * name = The main settings directory for the application
 * subdir = The subdirectory to load these settings files from
 */
auto loadSubdir(T, alias format)(StandardPath standardPath, string name, string subdir) {
	import std.algorithm : cartesianProduct, filter, joiner, map;
	import std.file : dirEntries, exists, SpanMode;
	import std.path : buildPath, chainPath, withExtension;
	import std.range : chain, choose, only;
	const subPath = buildPath(name, subdir);
	return standardPaths(standardPath, subPath)
		.cartesianProduct(only(Extensions!format))
		.filter!(x => x[0].exists)
		.map!(x => dirEntries(x[0], "*"~x[1], SpanMode.depth))
		.joiner()
		.map!(x => fromFile!(T, format, DeSiryulize.optionalByDefault)(x));
}

/**
 * Saves settings. Uses user's settings dir.
 * Params:
 * standardPath = Type of path to use.
 * data = The data that will be saved to the settings file.
 * name = The subdirectory of the settings dir to save the config to. Created if nonexistent.
 * flags = Optional flags for tweaking behaviour.
 * filename = The filename the settings will be saved to.
 * subdir = The subdirectory that the settings will be saved in.
 */
void save(T, alias format)(StandardPath standardPath, T data, string name, SettingsFlags flags, string filename, string subdir) {
	import std.conv : text;
	import std.exception : enforce;
	auto paths = getPaths!format(standardPath, name, subdir, filename, true, flags);
	enforce (!paths.empty, "No writable paths found");
	if (flags & SettingsFlags.writeMinimal) {
		safeSave(paths.front.text, toString!(format, Siryulize.omitInits)(data));
	} else {
		safeSave(paths.front.text, toString!format(data));
	}
}
/**
 * Deletes settings files for the specified app that are handled by this
 * library. Also removes directory if empty.
 * Params:
 * standardPath = Type of path to use.
 * name = App name.
 * flags = Optional flags for tweaking behaviour.
 * filename = The settings file that will be deleted.
 * subdir = Data subdirectory to delete.
 */
void deleteDoc(alias format)(StandardPath standardPath, string name, SettingsFlags flags, string filename, string subdir) {
	import std.conv : text;
	import std.file : exists, remove, dirEntries, SpanMode, rmdir;
	import std.path : dirName;
	foreach (path; getPaths!format(standardPath, name, subdir, filename, true, flags)) {
		if (path.exists) {
			remove(path);
			if (path.dirName.text.dirEntries(SpanMode.shallow).empty) {
				rmdir(path.dirName);
			}
		}
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


package template Extensions(T) {
	import std.meta : AliasSeq;
	static if (is(T == YAML)) {
		alias Extensions = AliasSeq!(".yaml", ".yml");
	} else static if (is(T == JSON)) {
		alias Extensions = AliasSeq!(".json");
	}
}
