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
import 'util.dart';

@sealed
class Script {
  final String name;

  final IOSink stdin;
  late final Stream<List<int>> stdout;
  late final Stream<List<int>> stderr;

  final _extraStderrController = StreamController<List<int>>();

  /// See also [success], which should be preferred when simply checking whether
  /// the script has succeeded.
  Future<int> get exitCode =>
      _exitCompleter.future.then((_) => 0, onError: (error, stackTrace) {
        if (error is! ScriptException) throw error;
        return error.exitCode;
      });

  Future<bool> get success async => await exitCode == 0;

  Future<void> get done => _exitCompleter.future;

  final _exitCompleter = Completer<void>();

  var _stdoutListened = false;
  var _stderrListened = false;

  factory Script(String executableAndArgs,
      {List<String>? args,
      String? name,
      String? workingDirectory,
      Map<String, String>? environment,
      bool includeParentEnvironment = true}) {
    var parsedExecutableAndArgs = parseArgs(executableAndArgs);

    var stdinCompleter = StreamSinkCompleter<List<int>>();
    var stdoutCompleter = StreamCompleter<List<int>>();
    var stderrCompleter = StreamCompleter<List<int>>();

    var exitCode = Process.start(parsedExecutableAndArgs[0],
            [...parsedExecutableAndArgs.skip(1), ...?args],
            workingDirectory: workingDirectory,
            environment: environment,
            includeParentEnvironment: includeParentEnvironment)
        .then((process) {
      stdinCompleter.setDestinationSink(process.stdin);
      stdoutCompleter.setSourceStream(process.stdout);
      stderrCompleter.setSourceStream(process.stderr);

      return process.exitCode;
    });

    return Script.fromComponents(
        p.basename(parsedExecutableAndArgs[0]),
        stdinCompleter.sink,
        stdoutCompleter.stream,
        stderrCompleter.stream,
        exitCode);
  }

  factory Script.capture(
      FutureOr<void> Function(Stream<List<int>> stdin) contents,
      {String? name}) {
    var spawningScripts = FutureGroup<void>();
    var stdinController = StreamController<List<int>>();
    var stdoutGroup = StreamGroup<List<int>>();
    var stderrGroup = StreamGroup<List<int>>();
    var exitCodeCompleter = Completer<int>();

    runZonedGuarded(
        () async {
          await contents(stdinController.stream);

          // Once there are no scripts still spawning and no streams still emitting,
          // mark this script as done.
          void checkIdle() {
            if (stdoutGroup.isIdle &&
                stderrGroup.isIdle &&
                spawningScripts.isIdle &&
                !exitCodeCompleter.isCompleted) {
              stdoutGroup.close();
              stderrGroup.close();
              spawningScripts.close();
              exitCodeCompleter.complete(0);
            }
          }

          checkIdle();
          stdoutGroup.onIdle.listen((_) => checkIdle());
          stderrGroup.onIdle.listen((_) => checkIdle());
          spawningScripts.onIdle.listen((_) => checkIdle());
        },
        (error, stackTrace) {
          if (!exitCodeCompleter.isCompleted) {
            stdoutGroup.close();
            stderrGroup.close();
            spawningScripts.close();
            exitCodeCompleter.completeError(error, stackTrace);
          }
        },
        zoneValues: {
          #_spawningScripts: spawningScripts,
          #_stdoutGroup: stdoutGroup,
          #_stderrGroup: stderrGroup
        },
        zoneSpecification: ZoneSpecification(print: (_, parent, zone, line) {
          if (!exitCodeCompleter.isCompleted) {
            // Add a new stream for each print rather than keeping open a single
            // [StreamController] because otherwise we can't detect when
            // [stdoutGroup] has gone idle.
            stdoutGroup.add(Stream.value(utf8.encode("$line\n")));
          }
        }));

    return Script.fromComponents(name ?? "capture", stdinController.sink,
        stdoutGroup.stream, stderrGroup.stream, exitCodeCompleter.future);
  }

  Script.fromComponents(this.name, StreamConsumer<List<int>> stdin,
      Stream<List<int>> stdout, Stream<List<int>> stderr, Future<int> exitCode)
      : stdin = stdin is IOSink ? stdin : IOSink(stdin) {
    this.stdout =
        stdout.onListen(() => _stdoutListened = true).handleError(_handleError);
    this.stderr = StreamGroup.merge([
      stderr.onListen(() => _stderrListened = true).handleError(_handleError),
      _extraStderrController.stream
    ]);

    exitCode.then((code) {
      if (_exitCompleter.isCompleted) return;

      if (code == 0) {
        _exitCompleter.complete(null);
      } else {
        _exitCompleter.completeError(
            ScriptException(name, code), StackTrace.current);
      }
      _extraStderrController.close();
    }, onError: _handleError);

    // Run the script after a macrotask elapses, to give the user time to set up
    // handlers for stdout and stderr.
    var spawningScripts = Zone.current[#_spawningScripts];
    var future = Future(_pipeUnlistenedStreams);

    try {
      if (spawningScripts is FutureGroup<void>) spawningScripts.add(future);
    } on StateError {
      // The FutureGrop is cloesd, indicating that the surrounding capture group
      // has already exited.
      throw StateError("Can't create a Script within a Script.capture() block "
          "that already exited.");
    }
  }

  Stream<List<int>> combineOutput() => StreamGroup.merge([stdout, stderr]);

  void _handleError(Object error, StackTrace trace) {
    if (_exitCompleter.isCompleted) return;

    if (error is ScriptException) {
      // If an internal script fails and the failure isn't handled, this script
      // will also fail with the same exit code.
      _exitCompleter.completeError(ScriptException(name, error.exitCode));
    } else {
      // Otherwise, if this is an unexpected Dart error, print information about
      // it to stderr and exit with code 256. That code is higher than actual
      // subprocesses can emit, so it can be used as a sentinel to detect
      // Dart-based failures.
      _extraStderrController.add(utf8.encode("Error running $name:\n"
          "$error\n"
          "${Chain.forTrace(trace)}\n"));
      _extraStderrController.close();
      _exitCompleter.completeError(
          ScriptException(name, 256), StackTrace.current);
    }
  }

  void _pipeUnlistenedStreams() {
    if (!_stdoutListened) {
      _pipeUnlistenedStream(stdout, #_stdoutGroup, io.stdout);
    }

    if (!_stderrListened) {
      _pipeUnlistenedStream(stderr, #_stderrGroup, io.stderr);
    }
  }

  void _pipeUnlistenedStream(Stream<List<int>> stream, Symbol groupSymbol,
      Sink<List<int>> defaultConsumer) {
    var group = Zone.current[groupSymbol];
    if (group is StreamGroup<List<int>>) {
      group.add(stream);
    } else {
      stream.listen(defaultConsumer.add);
    }
  }
}
