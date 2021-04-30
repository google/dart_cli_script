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

import 'package:charcode/charcode.dart';
import 'package:string_scanner/string_scanner.dart';

import '../script.dart';
import 'byte_stream.dart';

/// Extensions on [Stream<String>] that treat it as a stream of discrete lines
/// (as commonly emitted by a shell script).
extension LineStreamExtensions on Stream<String> {
  /// Converts this to a byte stream with newlines baked in.
  Stream<List<int>> get bytes => map((line) => utf8.encode("$line\n"));

  /// Pipes [this] into [script]'s [stdin] with newlines baked in.
  ///
  /// This works like [Script.pipe], treating this stream as a process that
  /// emits only stdout. If [this] emits an error, it's treated the same as an
  /// unhandled Dart error in a [Script.capture] block: it's printed to stderr
  /// and the virtual stream process exits with error code 256.
  Script operator |(Script script) => bytes | script;

  /// Shorthand for `stream.bytes.pipe`.
  Future<void> operator >(StreamConsumer<List<int>> consumer) =>
      bytes.pipe(consumer);

  /// Returns the elements of [this] that match [regexp].
  ///
  /// If [exclude] is `true`, instead returns the elements of [this] that
  /// *don't* match [regexp].
  ///
  /// The [caseSensitive], [unicode], and [dotAll] flags are the same as for
  /// [new RegExp].
  Stream<String> grep(String regexp,
      {bool exclude = false,
      bool caseSensitive = true,
      bool unicode = false,
      bool dotAll = false}) {
    var pattern = RegExp(regexp,
        caseSensitive: caseSensitive, unicode: unicode, dotAll: dotAll);
    return where((line) => pattern.hasMatch(line) != exclude);
  }

  /// Replaces matches of [regexp] with [replacement].
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
  Stream<String> replace(String regexp, String replacement,
          {bool all = false,
          bool caseSensitive = true,
          bool unicode = false,
          bool dotAll = false}) =>
      replaceMapped(regexp, (match) {
        var scanner = StringScanner(replacement);
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
      },
          all: all,
          caseSensitive: caseSensitive,
          unicode: unicode,
          dotAll: dotAll);

  /// Replaces matches of [regexp] with the result of calling [replace].
  ///
  /// By default, only replaces the first match per line. If [all] is `true`,
  /// replaces all matches in each line instead.
  ///
  /// The [caseSensitive], [unicode], and [dotAll] flags are the same as for
  /// [new RegExp].
  Stream<String> replaceMapped(String regexp, String replace(Match match),
      {bool all = false,
      bool caseSensitive = true,
      bool unicode = false,
      bool dotAll = false}) {
    var pattern = RegExp(regexp,
        caseSensitive: caseSensitive, unicode: unicode, dotAll: dotAll);
    return map((line) => all
        ? line.replaceAllMapped(pattern, replace)
        : line.replaceFirstMapped(pattern, replace));
  }
}
