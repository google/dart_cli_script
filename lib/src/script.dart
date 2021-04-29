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
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;

import 'package:async/async.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';

import 'exception.dart';
import 'parse_args.dart';
import 'stdio.dart';
import 'stdio_group.dart';
import 'util.dart';

/// A unit of execution that behaves like a process, with [stdin], [stdout], and
/// [stderr] streams that ultimately produces an [exitCode] indicating success
/// or failure.
///
/// This is usually a literal subprocess (created using [new Script]). However,
/// it can also be a block of Dart code (created using [Script.capture]) or a
/// user-defined custom script (created using [Script.fromComponents]).
///
/// All script types provide the following guarantees:
///
/// * All errors will be emitted through [exitCode], [success], and/or [done]
///   (depending on which is accessed). If the underlying [stdout] or [stderr]
///   stream would emit an error, it's forwarded to the exit futures. Catching
///   errors on one exit future is sufficient to catch all errors emitted by the
///   [Script].
///
/// * Any errors emitted after [done] completes will be silently ignored, even
///   if [done] completed successfully.
///
/// * Once [done] completes, [stdout] and [stderr] will emit done events
///   immediately afterwards (modulo a few microtasks).
///
/// * After constructing the [Script], the user has one macrotask (that is,
///   until a [Timer.run] event fires) to listen to [stdout] and [stderr]. After
///   that, they'll be forwarded to the surrounding [Stream.capture] (if one
///   exists) or to the root script's [stdout] and [stderr] streams.
///
/// * Passing error events to [stdin] is not allowed. If an error is passed,
///   [stdin] wil close and forward the error to [stdin.done].
@sealed
class Script {
  /// A human-readable name of the script.
  final String name;

  /// The standard input stream that's used to pass data into the process.
  final IOSink stdin;

  /// The script's standard output stream, typically used to emit data it
  /// produces.
  Stream<List<int>> get stdout {
    _stdoutAccessed = true;
    return _stdout;
  }

  late final Stream<List<int>> _stdout;
  bool _stdoutAccessed = false;

  /// The script's standard error stream, typically used to emit error messages
  /// and diagnostics.
  Stream<List<int>> get stderr {
    _stderrAccessed = true;
    return _stderr;
  }

  late final Stream<List<int>> _stderr;
  bool _stderrAccessed = false;

  /// A controller for stderr produced by the [Script] infrastructure, merged
  /// with the stderr stream passed to [Script.fromComponents].
  final _extraStderrController = StreamController<List<int>>();

  /// The exit code indicating the status of the script's execution.
  ///
  /// An exit code of `0` indicates success or a "true" return value, and any
  /// non-zero exit code indicates failure or a "false" return value. Otherwise,
  /// different scripts use different conventions for non-zero exit codes.
  ///
  /// Throws any Dart exceptions that come up when running this [Script].
  ///
  /// See also [success], which should be preferred when simply checking whether
  /// the script has succeeded.
  Future<int> get exitCode => done.then((_) => 0, onError: (Object error, _) {
        if (error is! ScriptException) throw error;
        return error.exitCode;
      });

  /// Whether the script succeeded or failed (that is, whether it emitted an
  /// exit code of `0`).
  ///
  /// Throws any Dart exceptions that come up when running this [Script].
  Future<bool> get success async => await exitCode == 0;

  /// A future that completes when the script is finished.
  ///
  /// Throws any Dart exceptions that come up when running this [Script], and
  /// throws a [ScriptException] if the [Script] completes with a non-zero exit
  /// code.
  late final Future<void> done;

  /// Returns a future that completes when this script finishes running, whether
  /// or not it encountered an error and without disrupting the error handling
  /// that would otherwise occur.
  Future<void> get _doneWithoutError =>
      _doneCompleter.future.catchError((_) {});

  /// The completer for [done].
  final _doneCompleter = Completer<void>();

  /// A transformer that's used to forcibly close [stdout] and [stderr] once the
  /// script exits.
  final _outputCloser = StreamCloser<List<int>>();

  /// Creates a [Script] that runs a subprocess.
  ///
  /// The [executableAndArgs] and [args] arguments are parsed as described in
  /// [the README]. The [name] is a human-readable identifier for this script
  /// that's used in debugging and error reporting, and defaults to the
  /// executable name. All other arguments are forwarded to [Process.start].
  ///
  /// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
  factory Script(String executableAndArgs,
      {List<String>? args,
      String? name,
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true}) {
    var parsedExecutableAndArgs = parseArgs(executableAndArgs);

    return Script.fromComponents(name ?? p.basename(parsedExecutableAndArgs[0]),
        () async {
      var process = await Process.start(parsedExecutableAndArgs[0],
          [...parsedExecutableAndArgs.skip(1), ...?args],
          workingDirectory: workingDirectory,
          environment: environment,
          includeParentEnvironment: includeParentEnvironment);

      return ScriptComponents(
          process.stdin, process.stdout, process.stderr, process.exitCode);
    });
  }

  /// Runs [callback] and captures the output of [Script]s created within it.
  ///
  /// As much as possible, [callback] is treated as its own isolated process. In
  /// particular:
  ///
  /// * The [stdout] and [stderr] streams of any child [Script]s are forwarded
  ///   to this script's [stdout] and [stderr], respectively, unless the getters
  ///   are accessed within the span of a macrotask after being created (that
  ///   is, before a [Timer.run] event fires).
  ///
  /// * Calls to [print] are also forwarded to [stdout].
  ///
  /// * Any unhandled [ScriptException]s within [callback], such as from child
  ///   [Script]s failing unexpectedly, cause this [Script] to fail with the
  ///   same exit code.
  ///
  /// * Any unhandled Dart exceptions within [callback] cause this [Script] to
  ///   print the error message and stack trace to [stderr] and exit with code
  ///   256.
  ///
  /// * Any errors within [callback] that go unhandled after this [script] has
  ///   already exited are silently ignored, as is any additional output.
  ///
  /// * Creating a [Script] within [callback] after this [Script] has exited
  ///   will throw a [StateError] (which will then be silently ignored unless
  ///   otherwise handled).
  ///
  /// The returned [Script] exits automatically as soon as the [Future] returned
  /// by [callback] has completed *and* all child [Script]s created within
  /// [callback] have completed. It will exit early if an error goes unhandled,
  /// including from a child [Script] failing unexpectedly.
  ///
  /// The [name] is a human-readable name for the script, used for debugging and
  /// error messages. It defaults to `"capture"`.
  factory Script.capture(
      FutureOr<void> Function(Stream<List<int>> stdin) callback,
      {String? name}) {
    _checkCapture();

    var childScripts = FutureGroup<void>();
    var stdinController = StreamController<List<int>>();
    var stdoutGroup = StdioGroup();
    var stderrGroup = StdioGroup();
    var exitCodeCompleter = Completer<int>();

    runZonedGuarded(
        () async {
          await callback(stdinController.stream);

          // Once there are no child scripts still spawning or running, mark
          // this script as done.
          void checkIdle() {
            if (childScripts.isIdle && !exitCodeCompleter.isCompleted) {
              stdoutGroup.close();
              stderrGroup.close();
              childScripts.close();
              exitCodeCompleter.complete(0);
            }
          }

          checkIdle();
          childScripts.onIdle.listen((_) => Timer.run(checkIdle));
        },
        (error, stackTrace) {
          if (!exitCodeCompleter.isCompleted) {
            stdoutGroup.close();
            stderrGroup.close();
            childScripts.close();
            exitCodeCompleter.completeError(error, stackTrace);
          }
        },
        zoneValues: {
          #_childScripts: childScripts,
          stdoutKey: stdoutGroup,
          stderrKey: stderrGroup
        },
        zoneSpecification: ZoneSpecification(print: (_, parent, zone, line) {
          if (!exitCodeCompleter.isCompleted) {
            // Add a separate stream rather than using [stdoutGroup.sink] so
            // that prints will go through even if the user has put the sink
            // in a weird state by calling [StreamSink.close] or
            // [StreamSink.addStream].
            stdoutGroup.add(Stream.value(utf8.encode("$line\n")));
          }
        }));

    return Script._(name ?? "capture", stdinController.sink, stdoutGroup.stream,
        stderrGroup.stream, exitCodeCompleter.future);
  }

  /// Creates a [Script] from a [StreamTransformer] on byte streams.
  ///
  /// This script transforms all its stdin with [transformer] and emits it via
  /// stdout. It exits once the transformed stream closes. Any error events
  /// emitted by [transformer] are treated as errors in the script.
  factory Script.fromByteTransformer(
      StreamTransformer<List<int>, List<int>> transformer,
      {String? name}) {
    _checkCapture();
    var controller = StreamController<List<int>>();
    var exitCodeCompleter = Completer<int>.sync();
    return Script._(
        name ?? transformer.toString(),
        controller.sink,
        controller.stream
            .transform(transformer)
            .onDone(() => exitCodeCompleter.complete(0)),
        Stream.empty(),
        exitCodeCompleter.future);
  }

  /// Creates a [Script] from a [StreamTransformer] on string streams.
  ///
  /// This script transforms each line of stdin with [transformer] and emits it
  /// via stdout. It exits once the transformed stream closes. Any error events
  /// emitted by [transformer] are treated as errors in the script.
  factory Script.fromLineTransformer(
          StreamTransformer<String, String> transformer,
          {String? name}) =>
      Script.fromByteTransformer(
          StreamTransformer.fromBind((stream) => stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .transform(transformer)
              .map((line) => utf8.encode("$line\n"))),
          name: name ?? transformer.toString());

  /// Pipes each script's [stdout] into the next script's [stdin].
  ///
  /// Returns a new [Script] whose [stdin] comes from the first script's, and
  /// whose [stdout] and [stderr] come from the last script's.
  ///
  /// This behaves like a Bash pipeline with `set -o pipefail`: if any script
  /// exits with a non-zero exit code, the returned script will fail, but it
  /// will only exit once *all* component scripts have exited. If multiple
  /// scripts exit with errors, the last non-zero exit code will be returned.
  ///
  /// This doesn't add any special handling for any script's [stderr] except for
  /// the last one.
  ///
  /// See also [operator |], which provides a syntax for creating pipelines two
  /// scripts at a time.
  factory Script.pipeline(Iterable<Script> scripts, {String? name}) {
    _checkCapture();

    var list = scripts.toList();
    if (list.isEmpty) {
      throw ArgumentError.value(list, "script", "May not be empty");
    } else if (list.length == 1) {
      return list.first;
    }

    for (var i = 0; i < list.length - 1; i++) {
      list[i].stdout.pipe(list[i + 1].stdin);
    }

    return Script._(
        name ?? list.map((script) => script.name).join(" | "),
        list.first.stdin,
        // Wrap the final script's stdout and stderr in [SubscriptionStream]s so
        // that the inner scripts will see that someone's listening and not try
        // to top-level the streams' output.
        SubscriptionStream(list.last.stdout.listen(null)),
        SubscriptionStream(list.last.stderr.listen(null)),
        Future.wait(list.map((script) => script.exitCode)).then((exitCodes) =>
            exitCodes.lastWhere((code) => code != 0, orElse: () => 0)));
  }

  /// Creates a script from existing [stdin], [stdout], [stderr], and [exitCode]
  /// objects encapsulated in a [ScriptComponents].
  ///
  /// This takes a [callback] rather than taking a bunch of arguments directly
  /// for two reasons:
  ///
  /// 1. If there's an error while starting the script, it's handled
  ///    automatically the same way an error emitted by [exitCode] would be.
  ///
  /// 2. If there's a reason the script shouldn't even start loading (such as
  ///    being called in a [Script.capture] block that's already exited), this
  ///    will throw an error before even running [callback].
  ///
  /// This constructor should generally be avoided outside library code. Script
  /// authors are expected to primarily use [Script] and [Script.capture].
  factory Script.fromComponents(
      String name, FutureOr<ScriptComponents> callback()) {
    _checkCapture();

    // TODO: there are too few guarantees about when a stream will actually get
    // listened. Even piping it doesn't immediately listen. I think we need to
    // just check access instead.
    var stdoutCompleter = StreamCompleter<List<int>>();
    var stdout = stdoutCompleter.stream;

    var stderrCompleter = StreamCompleter<List<int>>();
    var stderr = stderrCompleter.stream;

    var stdinCompleter = StreamSinkCompleter<List<int>>();

    return Script._(
        name,
        stdinCompleter.sink.rejectErrors(),
        stdout,
        stderr,
        Future.sync(callback).then((components) {
          stdinCompleter.setDestinationSink(components.stdin);
          stdoutCompleter.setSourceStream(components.stdout);
          stderrCompleter.setSourceStream(components.stderr);
          return components.exitCode;
        }));
  }

  /// Pipes [stream]'s events to a [StdioGroup] indexed by [key] in the current
  /// zone if it exists, or else to [defaultConsumer] if it doesn't.
  static void _pipeUnlistenedStream(
      Stream<List<int>> stream, Object key, Sink<List<int>> defaultConsumer) {
    var group = Zone.current[key];
    if (group is StdioGroup) {
      group.add(stream);
    } else {
      stream.listen(defaultConsumer.add);
    }
  }

  /// Creates a [Script] directly from its component fields.
  Script._(this.name, StreamConsumer<List<int>> stdin, Stream<List<int>> stdout,
      Stream<List<int>> stderr, Future<int> exitCode)
      : stdin = IOSink(stdin) {
    _stdout = stdout.handleError(_handleError).transform(_outputCloser);
    _stderr = StreamGroup.merge([stderr, _extraStderrController.stream])
        .handleError(_handleError)
        .transform(_outputCloser);

    // Add an extra [Future.then] so that any errors passed to [_doneCompleter]
    // will still be top-leveled unless [done] specifically has a listener,
    // *even if* [_doneWithoutError] has its own listener.
    done = _doneCompleter.future.then((_) {});

    exitCode.then((code) {
      if (_doneCompleter.isCompleted) return;

      if (code == 0) {
        _doneCompleter.complete(null);
      } else {
        _doneCompleter.completeError(
            ScriptException(name, code), StackTrace.current);
      }

      _closeOutputStreams();
      _extraStderrController.close();
    }, onError: _handleError);

    // Forward streams after a macrotask elapses to give the user time to start
    // listening. *Don't* wait until the process starts because that'll take a
    // non-deterministic amount of time, and we want to guarantee as best as
    // possible that if the user adds a listener too late it will fail
    // consistently rather than flakily.
    Timer.run(() {
      if (!_stdoutAccessed) {
        _pipeUnlistenedStream(this.stdout, stdoutKey, io.stdout);
      }

      if (!_stderrAccessed) {
        _pipeUnlistenedStream(this.stderr, stderrKey, io.stderr);
      }
    });

    _childScripts?.add(_doneWithoutError);
  }

  /// Throws a [StateError] if this is running in a closed [Script.capture]
  /// block.
  static void _checkCapture() {
    _childScripts;
  }

  /// Returns the current [Script.capture] block's [FutureGroup] that tracks
  /// when its child scripts are completed, or `null` if we're not in a
  /// [Script.capture].
  ///
  /// Throws a [StateError] if the surrounding [Script.capture] has already
  /// closed.
  static FutureGroup<void>? get _childScripts {
    var childScripts = Zone.current[#_childScripts];
    if (childScripts is! FutureGroup<void>) return null;

    if (childScripts.isClosed) {
      // The FutureGroup is closed, indicating that the surrounding capture
      // group has already exited.
      throw StateError("Can't create a Script within a Script.capture() block "
          "that already exited.");
    }

    return childScripts;
  }

  /// Handles an error emitted within this script.
  void _handleError(Object error, StackTrace trace) {
    if (_doneCompleter.isCompleted) return;

    if (error is ScriptException) {
      // If an internal script fails and the failure isn't handled, this script
      // will also fail with the same exit code.
      _doneCompleter.completeError(ScriptException(name, error.exitCode));
    } else {
      // Otherwise, if this is an unexpected Dart error, print information about
      // it to stderr and exit with code 256. That code is higher than actual
      // subprocesses can emit, so it can be used as a sentinel to detect
      // Dart-based failures.
      _extraStderrController.add(utf8.encode("Error in $name:\n"
          "$error\n"
          "${Chain.forTrace(trace)}\n"));
      _extraStderrController.close();
      _doneCompleter.completeError(
          ScriptException(name, 256), StackTrace.current);
    }

    _closeOutputStreams();
  }

  /// Closes [stdout] and [stderr] if they aren't already closed.
  void _closeOutputStreams() {
    // Only close the outputs after a macrotask so any last data has time to
    // propagate to its listeners.
    Timer.run(() {
      // Ignore any subscription cancellation errors, because they come from
      // within the script and the script has exited.
      _outputCloser.close().catchError((_) {});
    });
  }

  /// Returns a stream that combines both [stdout] and [stderr] the same way
  /// they'd be displayed in a terminal.
  Stream<List<int>> combineOutput() => StreamGroup.merge([stdout, stderr]);

  /// Pipes this script's [stdout] into [other]'s [stdin].
  ///
  /// Returns a new [Script] whose [stdin] comes from [this] and whose [stdout]
  /// and [stderr] come from [other].
  ///
  /// This behaves like a Bash pipeline with `set -o pipefail`: if either [this]
  /// or [other] exits with a non-zero exit code, the returned script will fail,
  /// but it will only exit once *both* component scripts have exited. If both
  /// exit with errors, [other]'s exit code will be used.
  ///
  /// This doesn't add any special handling for [this]'s [stderr].
  ///
  /// See also [pipe], which provides a syntax for creating a pipeline with many
  /// scripts at once.
  Script operator |(Script other) => Script.pipeline([this, other]);

  /// Shorthand for `script.stdout.pipe(consumer)`.
  Future<void> operator >(StreamConsumer<List<int>> consumer) =>
      stdout.pipe(consumer);
}

/// A struct containing the components needed to create a [Script].
@sealed
class ScriptComponents {
  /// The standard input sink.
  final StreamSink<List<int>> stdin;

  /// The standard output stream.
  final Stream<List<int>> stdout;

  /// The standard error stream.
  final Stream<List<int>> stderr;

  /// The script's exit code, to complete once it exits.
  final Future<int> exitCode;

  ScriptComponents(this.stdin, this.stdout, this.stderr, this.exitCode);
}
