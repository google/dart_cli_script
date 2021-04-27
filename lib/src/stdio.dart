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

import 'stdio_group.dart';

/// An opaque key for the Zone value that contains the [StdioGroup] for the
/// current captured stdout context.
final stdoutKey = Object();

/// An opaque key for the Zone value that contains the [StdioGroup] for the
/// current captured stderr context.
final stderrKey = Object();

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
