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

import 'dart:io';
import 'dart:async';

import 'package:async/async.dart';
import 'package:meta/meta.dart';

import 'script.dart';
import 'util/entangled_controllers.dart';

/// A [Script] wrapper that suppresses all output and stores it in a buffer
/// until [release] is called, at which point it forwards the suppressed output
/// to [stdout] and [stderr].
///
/// Note that this can violate the usual guarantee that [stdout] and [stderr]
/// will emit done events immediately after [done] completes. Instead, they'll
/// emit done events once [done] completes *and* [release] has been called.
///
/// This also doesn't consider errors emitted by the underlying script unhandled
/// by default. Those errors are still emitted as usual through [done],
/// [success], and [exitCode], but users can wait to listen to these futures
/// without worrying about unhandled exceptions.
///
/// This is useful for running multiple scripts in parallel without having their
/// stdout and stderr streams overlap. You can wrap "background" scripts in
/// [BufferedScript] and only [release] them once they're the only script
/// running, or only if they fail.
@sealed
class BufferedScript extends Script {
  Stream<List<int>> get stdout {
    // Even though we use our own stdout stream, access this so that the
    // superclass knows not to forward it to the parent context.
    super.stdout;
    return _stdoutCompleter.stream;
  }

  /// The completer that forwards [_stdoutBuffer] once [release] is called.
  final _stdoutCompleter = StreamCompleter<List<int>>();

  /// A buffer of the inner script's stdout.
  ///
  /// We need to buffer this ourselves rather than relying on the inner script's
  /// buffer because once the inner [Script.done] completes, its stdio streams
  /// will emit done events rather than replaying their buffers.
  final StreamController<List<int>> _stdoutBuffer;

  Stream<List<int>> get stderr {
    // Even though we use our own stderr stream, access this so that the
    // superclass knows not to forward it to the parent context.
    super.stderr;
    return _stderrCompleter.stream;
  }

  /// The completer that forwards [_stderrBuffer] once [release] is called.
  final _stderrCompleter = StreamCompleter<List<int>>();

  /// A buffer of the inner script's stderr.
  ///
  /// We need to buffer this ourselves rather than relying on the inner script's
  /// buffer because once the inner [Script.done] completes, its stdio streams
  /// will emit done events rather than replaying their buffers.
  final StreamController<List<int>> _stderrBuffer;

  /// Like [Script.capture], but all output is silently buffered until [release]
  /// is called.
  factory BufferedScript.capture(
      FutureOr<void> Function(Stream<List<int>> stdin) callback,
      {String? name}) {
    var controllers = createEntangledControllers<List<int>>();
    return BufferedScript._(
        Script.capture(callback, name: name ?? "BufferedScript.capture"),
        controllers.item1,
        controllers.item2);
  }

  /// A helper constructor that allows [BufferedScript.capture] to pass in both
  /// [_stdoutBuffer] and [_stderrBuffer] from a single call to
  /// [createEntangledControllers].
  BufferedScript._(Script script, this._stdoutBuffer, this._stderrBuffer)
      : super.fromComponentsInternal(
            script.name,
            () => ScriptComponents(
                script.stdin, Stream.empty(), Stream.empty(), script.exitCode),
            silenceStartMessage: true) {
    script.stdout.pipe(_stdoutBuffer);
    script.stderr.pipe(_stderrBuffer);

    // Don't consider errors unhandled by default. This allows users to wait to
    // access [done], [success], and [exitCode] until later on, for example
    // after another parallel script has finished executing.
    done.catchError((_) {});
  }

  /// Emits all buffered output to [stdout] and [stderr].
  ///
  /// Returns a future that completes once all output has been emitted. If the
  /// script hasn't completed yet, the returned future will block until it does.
  /// However, unlike [done], the returned future will *not* emit an error even
  /// if the script fails.
  Future<void> release() => _releaseMemo.runOnce(() async {
        _stdoutCompleter.setSourceStream(_stdoutBuffer.stream);
        _stderrCompleter.setSourceStream(_stderrBuffer.stream);

        await Future.wait([_stdoutBuffer.done, _stderrBuffer.done]);

        // Give outer stdio listeners a chance to handle the IO.
        await Future<void>.delayed(Duration.zero);
      });
  final _releaseMemo = AsyncMemoizer<void>();
}
