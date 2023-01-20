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
import 'dart:typed_data';

import 'package:async/async.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:stack_trace/stack_trace.dart';

import 'cli_arguments.dart';
import 'config.dart';
import 'environment.dart';
import 'exception.dart';
import 'extensions/byte_stream.dart';
import 'stdio.dart';
import 'stdio_group.dart';
import 'util.dart';
import 'util/delayed_completer.dart';

/// An opaque key for the Zone value that contains the name of the current
/// [Script].
final scriptNameKey = #_captureName;

/// A unit of execution that behaves like a process, with [stdin], [stdout], and
/// [stderr] streams that ultimately produces an [exitCode] indicating success
/// or failure.
///
/// This is usually a literal subprocess (created using [new Script]). However,
/// it can also be a block of Dart code (created using [Script.capture]) or a
/// user-defined custom script (created using [Script.fromComponents]).
///
/// **Heads up:** If you want to handle a [Script]'s [stdout], [stderr], or
/// [exitCode] make sure to set up your handlers *synchronously* after you
/// create the [Script]! If you try to listen too late, you'll get "Stream has
/// already been listened to" errors because the streams have already been piped
/// into the parent process's output.
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
  late final IOSink stdin;

  /// A transformer used to forcibly cancel streams being piped to [stdin]
  final _stdinCloser = StreamCloser<List<int>>();

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
  ///
  /// This is delayed so that [done] doesn't fire until [stdout] and [stderr]
  /// have a chance to be automatically propagated to the enclosing context.
  /// This way, even if a non-zero exit code causes the entire script to exit,
  /// there will still be time to write stdio.
  ///
  /// Note: this should not be made sync, because otherwise process exits will
  /// outrace [_extraStderrController] messages and cause errors to be
  /// swallowed.
  final _doneCompleter = DelayedCompleter<void>();

  /// A transformer that's used to forcibly close [stdout] and [stderr] once the
  /// script exits.
  final _outputCloser = StreamCloser<List<int>>();

  /// The script's signal handler to terminate the process.
  bool Function(ProcessSignal) _signalHandler;

  /// Sends a [ProcessSignal] to terminate the process.
  ///
  /// If the [Script] is a Unix-style OS process, pass the given signal to the
  /// process. On platforms without signal support, including Windows, the
  /// [signal] is ignored and the process terminates in a platform specific way.
  ///
  /// Returns `true` if the signal is successfully delivered to the [Script].
  /// Otherwise the signal could not be sent, usually meaning that the process
  /// is already dead or the [Script] doesn't have a signal handler.
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (_doneCompleter.isCompleted) return false;
    try {
      return _signalHandler(signal);
    } catch (e, s) {
      _handleError(e, s);
      return false;
    }
  }

  /// Creates a [Script] that runs a subprocess.
  ///
  /// The [executableAndArgs] and [args] arguments are parsed as described in
  /// [the README]. The [name] is a human-readable identifier for this script
  /// that's used in debugging and error reporting, and defaults to the
  /// executable name. All other arguments are forwarded to [Process.start].
  ///
  /// [the README]: https://github.com/google/dart_cli_script/blob/main/README.md#argument-parsing
  factory Script(String executableAndArgs,
      {Iterable<String>? args,
      String? name,
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true,
      bool runInShell = false}) {
    var parsedExecutableAndArgs = CliArguments.parse(executableAndArgs);

    name ??= p.basename(parsedExecutableAndArgs.executable);
    ProcessSignal? capturedSignal;
    Process? process;
    return Script.fromComponentsInternal(name, () async {
      if (includeParentEnvironment) {
        environment = environment == null
            ? env
            // Use [withEnv] to ensure that the copied environment correctly
            // overrides the parent [env], including handling case-insensitive
            // keys on Windows.
            : withEnv(() => env, environment!);
      }

      var allArgs = [
        ...await parsedExecutableAndArgs.arguments(root: workingDirectory),
        ...?args
      ];

      if (inDebugMode) {
        // dart-lang/language#1536
        debug("[${name!}] ${parsedExecutableAndArgs.executable} "
            "${allArgs.join(' ')}");
      }

      process = await Process.start(parsedExecutableAndArgs.executable, allArgs,
          workingDirectory: workingDirectory,
          environment: environment,
          includeParentEnvironment: false,
          runInShell: runInShell);

      // Passes the [capturedSignal] received by the [Script.kill] function to
      // the [Process.kill] function if the signal was received before the
      // process started.
      if (capturedSignal != null) process!.kill(capturedSignal!);

      return ScriptComponents(
          process!.stdin, process!.stdout, process!.stderr, process!.exitCode);
    }, (signal) {
      if (process != null) return process!.kill(signal);
      capturedSignal = signal;
      return true;
    }, silenceStartMessage: true);
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
  ///   257.
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
  ///
  /// The [callback] can't be interrupted by calling [kill], but the [onSignal]
  /// callback allows capturing those signals so the callback may react
  /// appropriately. When no [onSignal] handler was set, calling [kill] will do
  /// nothing and return `false`.
  factory Script.capture(
      FutureOr<void> Function(Stream<List<int>> stdin) callback,
      {String? name,
      bool onSignal(ProcessSignal signal)?}) {
    _checkCapture();

    var scriptName = name ?? "capture";
    var childScripts = FutureGroup<void>();
    var stdinController = StreamController<List<int>>();
    var groups = StdioGroup.entangled();
    var stdoutGroup = groups.item1;
    var stderrGroup = groups.item2;
    var exitCodeCompleter = Completer<int>();

    runZonedGuarded(
        () async {
          if (onSignal != null) {
            onSignal = Zone.current.bindUnaryCallback(onSignal!);
          }

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
          scriptNameKey: scriptName,
          stdoutKey: stdoutGroup,
          stderrKey: stderrGroup
        },
        zoneSpecification: ZoneSpecification(print: (_, parent, zone, line) {
          if (!exitCodeCompleter.isCompleted) stdoutGroup.writeln(line);
        }));

    return Script._(scriptName, stdinController.sink, stdoutGroup.stream,
        stderrGroup.stream, exitCodeCompleter.future, (signal) {
      if (onSignal == null) return false;
      return onSignal!(signal);
    });
  }

  /// Creates a [Script] from a [StreamTransformer] on byte streams.
  ///
  /// This script transforms all its stdin with [transformer] and emits it via
  /// stdout. It exits once the transformed stream closes. Any error events
  /// emitted by [transformer] are treated as errors in the script.
  ///
  /// [Script.kill] returns `true` if the stream was interrupted and the script
  /// exits with [Script.exitCode] `143`, or `false` if the stream was already
  /// closed.
  factory Script.fromByteTransformer(
      StreamTransformer<List<int>, List<int>> transformer,
      {String? name}) {
    _checkCapture();
    var controller = StreamController<List<int>>();
    var exitCodeCompleter = Completer<int>.sync();
    var signalCloser = StreamCloser<List<int>>();

    return Script._(
      name ?? transformer.toString(),
      controller.sink,
      controller.stream.transform(signalCloser).transform(transformer).onDone(
          () => exitCodeCompleter.complete(signalCloser.isClosed ? 143 : 0)),
      Stream.empty(),
      exitCodeCompleter.future,
      (_) {
        signalCloser.close();
        return true;
      },
    );
  }

  /// Creates a [Script] from a [StreamTransformer] on string streams.
  ///
  /// This script transforms each line of stdin with [transformer] and emits it
  /// via stdout. It exits once the transformed stream closes. Any error events
  /// emitted by [transformer] are treated as errors in the script.
  ///
  /// [Script.kill] returns `true` if the stream was interrupted and the script
  /// exits with [Script.exitCode] `143`, or `false` if the stream was already
  /// closed.
  factory Script.fromLineTransformer(
          StreamTransformer<String, String> transformer,
          {String? name}) =>
      Script.fromByteTransformer(
          StreamTransformer.fromBind((stream) => stream.lines
              .transform(transformer)
              .map((line) => utf8.encode("$line\n"))),
          name: name ?? transformer.toString());

  /// Creates a [Script] from a function that maps strings to strings.
  ///
  /// This script passes each line of stdin to [mapper] and emits the result via
  /// stdout.
  factory Script.mapLines(String Function(String line) mapper,
          {String? name}) =>
      Script.fromLineTransformer(
          StreamTransformer.fromBind((stream) => stream.map(mapper)),
          name: name ?? mapper.toString());

  /// Pipes each script's [stdout] into the next script's [stdin].
  ///
  /// Each element of [scripts] must be either a [Script] or an object that can
  /// be converted into a script using the [Script.fromByteTransformer] and
  /// [Script.fromLineTransformer] constructors.
  ///
  /// Returns a new [Script] whose [stdin] comes from the first script's, and
  /// whose [stdout] and [stderr] come from the last script's.
  ///
  /// This behaves like a Bash pipeline with `set -o pipefail`: if any script
  /// exits with a non-zero exit code, the returned script will fail, but it
  /// will only exit once *all* component scripts have exited. If multiple
  /// scripts exit with errors, the last non-zero exit code will be returned.
  ///
  /// Similarly, the [kill] handler will send the event to the first script
  /// that accepts the signal.
  ///
  /// This doesn't add any special handling for any script's [stderr] except for
  /// the last one.
  ///
  /// See also [operator |], which provides a syntax for creating pipelines two
  /// scripts at a time.
  factory Script.pipeline(Iterable<Object> scripts, {String? name}) {
    _checkCapture();

    var list = scripts.map(_toScript).toList();
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
            exitCodes.lastWhere((code) => code != 0, orElse: () => 0)),
        (signal) => list.any((script) => script.kill(signal)));
  }

  /// Converts [scriptlike] into a [Script], or throws an [ArgumentError] if it
  /// can't be converted.
  static Script _toScript(Object scriptlike) {
    if (scriptlike is Script) {
      return scriptlike;
    } else if (scriptlike is StreamTransformer<List<int>, List<int>>) {
      return Script.fromByteTransformer(scriptlike);
    } else if (scriptlike is StreamTransformer<String, String>) {
      return Script.fromLineTransformer(scriptlike);
    } else if (scriptlike is String Function(String)) {
      return Script.mapLines(scriptlike);
    } else {
      throw ArgumentError(
          "$scriptlike is not a Script and can't be converted to one.");
    }
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
  ///
  /// The [callback] can't be interrupted by calling [kill], but the [onSignal]
  /// callback allows capturing those signals so the callback may react
  /// appropriately. When no [onSignal] handler was set, calling [kill] will do
  /// nothing and return `false`.
  Script.fromComponents(String name, FutureOr<ScriptComponents> callback(),
      {bool onSignal(ProcessSignal signal)?})
      : this.fromComponentsInternal(name, callback, onSignal ?? (_) => false,
            silenceStartMessage: false);

  /// Like [Script.fromComponents], but with an internal [silenceStartMessage]
  /// option that's forwarded to [Script._].
  ///
  /// @nodoc
  @internal
  Script.fromComponentsInternal(
      String name,
      FutureOr<ScriptComponents> callback(),
      bool signalHandler(ProcessSignal signal),
      {required bool silenceStartMessage})
      : this._fromComponentsInternal(
            _checkCapture(),
            name,
            callback,
            StreamCompleter(),
            StreamCompleter(),
            StreamSinkCompleter(),
            signalHandler,
            silenceStartMessage: silenceStartMessage);

  /// A helper method for [Script.fromComponentsInternal] that takes a bunch of
  /// intermediate values as parameters so it can refer to them multiple times
  /// when invoking [Script._].
  ///
  /// It would be much cleaner to just make [Script.fromComponentsInternal] a
  /// factory constructor, but then it and [Script.fromComponents] couldn't be
  /// invoked by  subclasses.
  Script._fromComponentsInternal(
      // A void parameter is pretty nasty, but it allows us to throw an error if
      // the surrounding capture is closed before scheduling [callback].
      void checkCapture,
      String name,
      FutureOr<ScriptComponents> callback(),
      StreamCompleter<List<int>> stdoutCompleter,
      StreamCompleter<List<int>> stderrCompleter,
      StreamSinkCompleter<List<int>> stdinCompleter,
      bool signalHandler(ProcessSignal signal),
      {required bool silenceStartMessage})
      : this._(
            name,
            stdinCompleter.sink.rejectErrors(),
            stdoutCompleter.stream,
            stderrCompleter.stream,
            Future.sync(callback).then((components) {
              stdinCompleter.setDestinationSink(components.stdin);
              stdoutCompleter.setSourceStream(components.stdout);
              stderrCompleter.setSourceStream(components.stderr);
              return components.exitCode;
            }),
            signalHandler,
            silenceStartMessage: silenceStartMessage);

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
  ///
  /// If [silenceStartMessage] is `false` (the default), this prints a message
  /// in debug mode indicating that the script has started running.
  Script._(this.name, StreamSink<List<int>> stdin, Stream<List<int>> stdout,
      Stream<List<int>> stderr, Future<int> exitCode, this._signalHandler,
      {bool silenceStartMessage = false}) {
    this.stdin = IOSink(stdin
        .transform(StreamSinkTransformer.fromStreamTransformer(_stdinCloser)));
    if (!silenceStartMessage) debug("[$name] starting");

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
        debug("[$name] exited with exit code 0");
        _doneCompleter.complete(null);
      } else {
        debug("[$name] exited with exit code $code");
        _doneCompleter.completeError(
            ScriptException(name, code), StackTrace.current);
      }

      _closeOutputStreams();
      _extraStderrController.close();
      _stdinCloser.close();
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

      // [_doneCompleter] has been waiting to fire until the streams have a
      // chance to be forwarded. If both [stdout] and [stderr] have already been
      // accessed by this point, there's no need to wait longer for their events
      // to propagate further so we mark [_doneCompleter] as ready
      // synchronously.
      if (_stdoutAccessed && _stderrAccessed) {
        _doneCompleter.ready();
      } else {
        Timer.run(_doneCompleter.ready);
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
      debug("[$name] exited with exit code ${error.exitCode}");
      _doneCompleter.completeError(ScriptException(name, error.exitCode));
    } else {
      var chain = terseChain(Chain.forTrace(trace));
      if (inDebugMode) {
        debug("[$name] exited with Dart exception:\n" +
            "$error\n$chain"
                .trimRight()
                .split("\n")
                .map((line) => "| $line")
                .join("\n"));
      }

      // Otherwise, if this is an unexpected Dart error, print information about
      // it to stderr and exit with code 257. That code is higher than actual
      // subprocesses can emit, so it can be used as a sentinel to detect
      // Dart-based failures.
      _extraStderrController.add(utf8.encode("Error in $name:\n"
          "$error\n"
          "$chain\n"));
      _extraStderrController.close();
      _doneCompleter.completeError(
          ScriptException(name, 257), StackTrace.current);
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

  /// Returns this script's stdout, with trailing newlines removed.
  ///
  /// Like `stdout.text`, but throws a [ScriptException] if the executable
  /// returns a non-zero exit code.
  Future<String> get output async =>
      (await Future.wait([stdout.text, done]))[0] as String;

  /// Returns this script's stdout as bytes.
  ///
  /// Like `collectBytes(stdout)`, but throws a [ScriptException] if the
  /// executable returns a non-zero exit code.
  Future<Uint8List> get outputBytes async =>
      (await Future.wait([collectBytes(stdout), done]))[0] as Uint8List;

  /// Returns a stream of lines [this] prints to stdout.
  ///
  /// Like [stdout.lines], but emits a [ScriptException] if the executable
  /// returns a non-zero exit code.
  Stream<String> get lines =>
      StreamGroup.merge([stdout.lines, Stream.fromFuture(done).withoutData()]);

  /// Returns a stream that combines both [stdout] and [stderr] the same way
  /// they'd be displayed in a terminal.
  Stream<List<int>> combineOutput() => StreamGroup.merge([stdout, stderr]);

  /// Pipes this script's [stdout] into [other]'s [stdin].
  ///
  /// The [other] must be either a [Script] or an object that can be converted
  /// into a script using the [Script.fromByteTransformer] and
  /// [Script.fromLineTransformer] constructors.
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
  Script operator |(Object other) => Script.pipeline([this, other]);

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
