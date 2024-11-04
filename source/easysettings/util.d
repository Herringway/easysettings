module easysettings.util;

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
