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

import 'buffered_script.dart';
import 'script.dart';
import 'stdio_group.dart';

/// An opaque key for the Zone value that contains the [StdioGroup] for the
/// current captured stdout context.
final Object stdoutKey = #_stdoutKey;

/// An opaque key for the Zone value that contains the [StdioGroup] for the
/// current captured stderr context.
final Object stderrKey = #_stderrKey;

/// Returns a sink for writing directly to the current stdout stream.
///
/// In a [capture] block, this writes to the captured stdout stream. Otherwise,
/// it writes to the process's top-level stream.
///
/// This should not be closed, and error events should not be emitted on it. It
/// should not be stored, as a given value may become invalid later on.
IOSink get currentStdout {
  var fromZone = Zone.current[stdoutKey];
  return fromZone is StdioGroup ? fromZone.sink : stdout;
}

/// Returns a sink for writing directly to the current stderr stream.
///
/// In a [capture] block, this writes to the captured stderr stream. Otherwise,
/// it writes to the process's top-level stream.
///
/// This should not be closed, and error events should not be emitted on it. It
/// should not be stored, as a given value may become invalid later on.
IOSink get currentStderr {
  var fromZone = Zone.current[stderrKey];
  return fromZone is StdioGroup ? fromZone.sink : stderr;
}

/// Runs [callback] and silences all stdout emitted by [Script]s or calls to
/// [print] within it.
///
/// Returns the same result as [callback]. Doesn't add any special error
/// handling.
T silenceStdout<T>(T callback()) {
  var group = StdioGroup();
  group.stream.drain<void>();
  return runZoned(callback,
      zoneValues: {stdoutKey: group},
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}));
}

/// Runs [callback] and silences all stderr emitted by [Script]s.
///
/// Returns the same result as [callback]. Doesn't add any special error
/// handling.
T silenceStderr<T>(T callback()) {
  var group = StdioGroup();
  group.stream.drain<void>();
  return runZoned(callback, zoneValues: {stderrKey: group});
}

/// Runs [callback] and silences all stdout and stderr emitted by [Script]s or
/// calls to [print] within it.
///
/// Returns the same result as [callback]. Doesn't add any special error
/// handling.
T silenceOutput<T>(T callback()) {
  var group = StdioGroup();
  group.stream.drain<void>();
  return runZoned(callback,
      zoneValues: {stdoutKey: group, stderrKey: group},
      zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}));
}

/// Runs [callback] in a [Script.capture] block and silences all stdout and
/// stderr emitted by [Script]s or calls to [print] within it until the
/// [callback] produces an error.
///
/// If and when [callback] produces an error, all the silenced output will be
/// forwarded to the returned script's [Script.stdout] and [Script.stderr]
/// streams.
///
/// If [when] is false, this doesn't silence any output. If [stderrOnly] is
/// false, this only silences stderr and passes stdout on as normal.
Script silenceUntilFailure(
    FutureOr<void> Function(Stream<List<int>> stdin) callback,
    {String? name,
    bool? when,
    bool stderrOnly = false}) {
  // Wrap this in an additional [Script.capture] so that we can both handle the
  // failure *and* still have it be top-leveled if it's not handled by the
  // caller.
  return Script.capture((stdin) async {
    if (when == false) {
      await callback(stdin);
      return;
    }

    var script = BufferedScript.capture((_) => callback(stdin),
        name: name == null ? null : '$name.inner', stderrOnly: stderrOnly);

    try {
      await script.done;
    } catch (_) {
      script.release();

      // Give the new stdio a chance to propagate.
      await Future<void>.delayed(Duration.zero);
      rethrow;
    }
  }, name: name);
}
