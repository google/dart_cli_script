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

import 'package:charcode/charcode.dart';
import 'package:string_scanner/string_scanner.dart';

/// Runs [onFinally] after [callback] completes, whether it returns a [Future]
/// or a synchronous value.
T tryFinally<T>(T callback(), void onFinally()) {
  late T result;
  try {
    result = callback();
  } catch (_) {
    onFinally();
    rethrow;
  }

  if (result is Future) return result.whenComplete(onFinally) as T;
  onFinally();
  return result;
}

/// Replaces [match] with a [replacement] string in the style of
/// [LineStreamExtensions.replace].
String replaceMatch(Match match, String replacement) {
  var scanner = SpanScanner(replacement);
  var buffer = StringBuffer();

  while (!scanner.isDone) {
    var next = scanner.readChar();
    if (next != $backslash) {
      buffer.writeCharCode(next);
      continue;
    }

    if (scanner.isDone) break;

    next = scanner.readChar();
    if (next >= $0 && next <= $9) {
      var groupNumber = next - $0;
      if (groupNumber > match.groupCount) {
        scanner.error("RegExp doesn't have group $groupNumber.",
            position: scanner.position - 2, length: 2);
      }

      var group = match[groupNumber];
      if (group != null) buffer.write(group);
    } else {
      buffer.writeCharCode(next);
    }
  }

  return buffer.toString();
}

/// Stream extensions used internally within `cli_script`, not for public
/// consumption.
extension UtilStreamExtensions<T> on Stream<T> {
  /// Returns a transformation of [this] that calls [callback] immediately
  /// before sending a `done` event to its listeners.
  Stream<T> onDone(void callback()) =>
      transform(StreamTransformer.fromHandlers(handleDone: (sink) {
        callback();
        sink.close();
      }));

  /// Returns a transformation of [this] that only emits error and done events,
  /// not data events.
  ///
  /// Because the returned stream doesn't emit data events, it can be used as a
  /// stream of any type.
  Stream<S> withoutData<S>() => where((_) => false).cast<S>();
}
