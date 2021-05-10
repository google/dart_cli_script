// Copyright 2021 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:async';
import 'dart:io';

import 'package:stack_trace/stack_trace.dart';

import 'src/exception.dart';
import 'src/extensions/byte_stream.dart';
import 'src/extensions/line_stream.dart';
import 'src/script.dart';

export 'src/environment.dart';
export 'src/extensions/byte_list.dart';
export 'src/extensions/byte_stream.dart';
export 'src/extensions/chunk_list.dart';
export 'src/extensions/line_list.dart';
export 'src/extensions/line_stream.dart';
export 'src/extensions/string.dart';
export 'src/exception.dart';
export 'src/parse_args.dart' show arg;
export 'src/script.dart';
export 'src/stdio.dart' hide stdoutKey, stderrKey;
export 'src/temp.dart';

/// The packages whose stack frames should be folded by [wrapMain].
const _packagesToFold = {'cli_script', 'async', 'path', 'string_scanner'};

/// A wrapper for the body of the top-level `main()` method.
///
/// It's recommended that all scripts wrap their `main()` methods in this
/// function. It gracefully exits when an error is unhandled, and (if
/// [chainStackTraces] is `true`) tracks stack traces across asynchronous calls
/// to produce better error stacks.
///
/// By default, if a [Script] fails in [callback], this just exits with that
/// script's exit code without printing any additional error messages. If
/// [printScriptException] is `true`, this will print the exception and its
/// stack trace to stderr before exiting.
///
/// By default, stack frames from the Dart core libraries and from this package
/// will be folded together to make stack traces more readable. If
/// [verboseTrace] is `true`, the full stack traces will be printed instead.
void wrapMain(FutureOr<void> callback(),
    {bool chainStackTraces = true,
    bool printScriptException = false,
    bool verboseTrace = false}) {
  Chain.capture(callback, onError: (error, chain) {
    if (!verboseTrace) {
      chain = chain.foldFrames(
          (frame) => _packagesToFold.contains(frame.package),
          terse: true);
    }

    if (error is! ScriptException) {
      stderr.writeln(error);
      stderr.writeln(chain);
      // Use the same exit code that Dart does for unhandled exceptions.
      exit(254);
    }

    // If a script failed, wait a macrotask before exiting so that its stderr
    // has a chance to be piped through to the top level.
    Timer.run(() {
      if (printScriptException) {
        stderr.writeln(error);
        stderr.writeln(chain);
      }

      exit(error.exitCode);
    });
  }, when: chainStackTraces);
}

/// Runs an executable for its side effects.
///
/// Returns a future that completes once the executable exits. Throws a
/// [ScriptException] if the executable returns a non-zero exit code.
///
/// The [executableAndArgs] and [args] arguments are parsed as described in [the
/// README]. The [name] is a human-readable identifier for this script that's
/// used in debugging and error reporting, and defaults to the executable name.
/// All other arguments are forwarded to [Process.start].
///
/// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
Future<void> run(String executableAndArgs,
        {List<String>? args,
        String? name,
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true}) =>
    Script(executableAndArgs,
            args: args,
            name: name,
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment)
        .done;

/// Runs an executable and returns its stdout, with trailing newlines removed.
///
/// Throws a [ScriptException] if the executable returns a non-zero exit code.
///
/// The [executableAndArgs] and [args] arguments are parsed as described in [the
/// README]. The [name] is a human-readable identifier for this script that's
/// used in debugging and error reporting, and defaults to the executable name.
/// All other arguments are forwarded to [Process.start].
///
/// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
///
/// See also [Script.output].
Future<String> output(String executableAndArgs,
        {List<String>? args,
        String? name,
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true}) =>
    Script(executableAndArgs,
            args: args,
            name: name,
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment)
        .output;

/// Runs an executable and returns a stream of lines it prints to stdout.
///
/// The returned stream emits a [ScriptException] if the executable returns a
/// non-zero exit code (unlike [Script.stdout]).
///
/// The [executableAndArgs] and [args] arguments are parsed as described in [the
/// README]. The [name] is a human-readable identifier for this script that's
/// used in debugging and error reporting, and defaults to the executable name.
/// All other arguments are forwarded to [Process.start].
///
/// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
///
/// See also [Script.lines].
Stream<String> lines(String executableAndArgs,
        {List<String>? args,
        String? name,
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true}) =>
    Script(executableAndArgs,
            args: args,
            name: name,
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment)
        .lines;

/// Runs an executable and returns whether it returns exit code 0.
///
/// The [executableAndArgs] and [args] arguments are parsed as described in [the
/// README]. The [name] is a human-readable identifier for this script that's
/// used in debugging and error reporting, and defaults to the executable name.
/// All other arguments are forwarded to [Process.start].
///
/// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
Future<bool> check(String executableAndArgs,
        {List<String>? args,
        String? name,
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true}) =>
    Script(executableAndArgs,
            args: args,
            name: name,
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment)
        .success;

/// Returns a transformer that emits only the the elements of the source stream
/// that match [regexp].
///
/// If [exclude] is `true`, instead returns the elements of the source stream
/// that *don't* match [regexp].
///
/// The [caseSensitive], [unicode], and [dotAll] flags are the same as for
/// [new RegExp].
StreamTransformer<String, String> grep(String regexp,
        {bool exclude = false,
        bool caseSensitive = true,
        bool unicode = false,
        bool dotAll = false}) =>
    StreamTransformer.fromBind((stream) => stream.grep(regexp,
        exclude: exclude,
        caseSensitive: caseSensitive,
        unicode: unicode,
        dotAll: dotAll));

/// Returns a transformer that replaces matches of [regexp] with [replacement].
///
/// By default, only replaces the first match per line. If [all] is `true`,
/// replaces all matches in each line instead.
///
/// The [replacement] may contain references to the capture groups in
/// [regexp], using a backslash followed by the group number. Backslashes not
/// followed by a number return the character immediately following them.
///
/// The [caseSensitive], [unicode], and [dotAll] flags are the same as for
/// [new RegExp].
StreamTransformer<String, String> replace(String regexp, String replacement,
        {bool all = false,
        bool caseSensitive = true,
        bool unicode = false,
        bool dotAll = false}) =>
    StreamTransformer.fromBind((stream) => stream.replace(regexp, replacement,
        all: all,
        caseSensitive: caseSensitive,
        unicode: unicode,
        dotAll: dotAll));

/// Returns a transformer that replaces matches of [regexp] with the result of
/// calling [replace].
///
/// By default, only replaces the first match per line. If [all] is `true`,
/// replaces all matches in each line instead.
///
/// The [caseSensitive], [unicode], and [dotAll] flags are the same as for
/// [new RegExp].
StreamTransformer<String, String> replaceMapped(
        String regexp, String replace(Match match),
        {bool all = false,
        bool caseSensitive = true,
        bool unicode = false,
        bool dotAll = false}) =>
    StreamTransformer.fromBind((stream) => stream.replaceMapped(regexp, replace,
        all: all,
        caseSensitive: caseSensitive,
        unicode: unicode,
        dotAll: dotAll));

/// A shorthand for opening the file at [path] as a stream.
///
/// With [ByteStreamExtensions.operator |], this can be used to pass the
/// contents of a file into a pipeline:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:cli_script/cli_script.dart';
///
/// void main() {
///   wrapMain(() async {
///     var pipeline = read("names.txt") |
///         Script("grep Natalie") |
///         Script("wc -l");
///     print("There are ${await pipeline.stdout.text} Natalies");
///   });
/// }
/// ```
Stream<List<int>> read(String path) => File(path).openRead();

/// A shorthand for opening a sink that writes to the file at [path].
///
/// With [Script.operator >], this can be used to write the output of a script
/// to a file:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:cli_script/cli_script.dart';
///
/// void main() {
///   wrapMain(() {
///     Script.capture((_) async {
///       await for (var file in lines("find . -type f -maxdepth 1")) {
///         var contents = await output("cat", args: [file]);
///         if (contents.contains("needle")) print(file);
///       }
///     }) > write("needles.txt");
///   });
/// }
/// ```
IOSink write(String path) => File(path).openWrite();

/// A shorthand for opening a sink that appends to the file at [path].
///
/// With [Script.operator >], this can be used to append the output of a script
/// to a file:
///
/// ```dart
/// import 'dart:io';
///
/// import 'package:cli_script/cli_script.dart';
///
/// void main() {
///   wrapMain(() {
///     Script.capture((_) async {
///       await for (var file in lines("find . -type f -maxdepth 1")) {
///         var contents = await output("cat", args: [file]);
///         if (contents.contains("needle")) print(file);
///       }
///     }) > append("needles.txt");
///   });
/// }
/// ```
IOSink append(String path) => File(path).openWrite(mode: FileMode.append);
