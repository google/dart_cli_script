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

import 'package:async/async.dart';
import 'package:stack_trace/stack_trace.dart';

import 'src/exception.dart';
import 'src/extensions/byte_stream.dart';
import 'src/script.dart';
import 'src/util.dart';

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
        .stdout
        .text;

/// Runs an executable and returns a stream of lines it prints to stdout.
///
/// The returned stream emits a [ScriptException] if the executable returns a
/// non-zero exit code (unlike [Script.stdout].
///
/// The [executableAndArgs] and [args] arguments are parsed as described in [the
/// README]. The [name] is a human-readable identifier for this script that's
/// used in debugging and error reporting, and defaults to the executable name.
/// All other arguments are forwarded to [Process.start].
///
/// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
Stream<String> lines(String executableAndArgs,
    {List<String>? args,
    String? name,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true}) {
  var script = Script(executableAndArgs,
      args: args,
      name: name,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment);

  // Because the user definitely isn't able to listen to [script.done] for
  // errors themselves, we always forward its potential [ScriptException]
  // through the returned stream.
  return StreamGroup.merge(
      [script.stdout.lines, Stream.fromFuture(script.done).withoutData()]);
}

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
