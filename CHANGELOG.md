## 0.2.0

* Add a `runInShell` argument for subprocesses.

* Accept `Iterable<String>` instead of `List<String>` for subprocess arguments.

* Use 257 rather than 256 as the sentinel value for `ScriptException`s caused by
  Dart exceptions.

* Fix a bug where Dart exceptions could cause the script to exit before their
  debug information was printed to stderr.

## 0.1.0

* Initial release.
