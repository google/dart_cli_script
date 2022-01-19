## 0.2.3+2

* Documentation improvements only.

## 0.2.3+1

* Properly respect `onlyMatching` in the top-level `grep()` method.

## 0.2.3

* Add an `onlyMatching` flag to `grep()` which prints the sections of input
  lines that match the given regular expression.

* Add a `teeToStderr` transformer and extension method on
  `Stream<List<String>>`. This passes a stream to stderr without modifying it,
  which is useful for debugging.

* Add a `Script.mapLines` constructor that returns a script that maps stdin
  lines according to a `String Function(String)`.

* Add support for passing a `String Function(String)` to `Script.pipeline` and
  `Script.operator |` to map stdin lines.

* Fold stack frames for a few more packages used internally.

## 0.2.2

* Add a `BufferedScript` class that buffers output from a Script until it's
  explicitly released, making it easier to run multiple script in parallel
  without having their outputs collide with one another.

* If the same `capture()` block both calls `print()` and writes to
  `currentStdout`, ensure that the order of prints is preserved.

* If the same `capture()` block writes to both `currentStdout` and
  `currentStderr`, ensure that the relative order of those writes is preserved
  when collected with `combineOutput()`.

## 0.2.1

* Give the stream transformers exposed by this package human-readable
  `toString()`s.

## 0.2.0

* Add a `debug` option to `wrapMain()` to print extra diagnostic information.

* Add a `runInShell` argument for subprocesses.

* Accept `Iterable<String>` instead of `List<String>` for subprocess arguments.

* Use 257 rather than 256 as the sentinel value for `ScriptException`s caused by
  Dart exceptions.

* Fix a bug where Dart exceptions could cause the script to exit before their
  debug information was printed to stderr.

## 0.1.0

* Initial release.
