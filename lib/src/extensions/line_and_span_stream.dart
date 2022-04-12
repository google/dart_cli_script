// Copyright 2022 Google LLC
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

import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

import '../stdio.dart';
import '../util.dart';

/// Extensions on [Stream<Tuple2<String, SourceSpanWithContext>>] that treat it
/// as a stream of discrete lines associated with spans that indicate where the
/// lines came from originally.
extension LineAndSpanStreamExtensions
    on Stream<Tuple2<String, SourceSpanWithContext>> {
  /// Returns the stream of lines alone.
  Stream<String> get lines => map((tuple) => tuple.item1);

  /// Returns the elements of [this] that match [regexp].
  ///
  /// If [exclude] is `true`, instead returns the elements of [this] that
  /// *don't* match [regexp].
  ///
  /// If [onlyMatching] is `true`, this only prints the non-empty matched parts
  /// of each line. Prints each match on a separate line. This flag can't be
  /// `true` at the same time as [exclude].
  ///
  /// The [caseSensitive], [unicode], and [dotAll] flags are the same as for
  /// [new RegExp].
  Stream<Tuple2<String, SourceSpanWithContext>> grep(String regexp,
      {bool exclude = false,
      bool onlyMatching = false,
      bool caseSensitive = true,
      bool unicode = false,
      bool dotAll = false}) {
    if (exclude && onlyMatching) {
      throw ArgumentError(
          "The exclude and onlyMatching flags can't both be set");
    }

    var pattern = RegExp(regexp,
        caseSensitive: caseSensitive, unicode: unicode, dotAll: dotAll);

    return onlyMatching
        ? expand((tuple) => pattern
            .allMatches(tuple.item1)
            .map((match) => Tuple2(
                match.group(0)!, tuple.item2.subspan(match.start, match.end)))
            .where((tuple) => tuple.item1.isNotEmpty))
        : where((tuple) => pattern.hasMatch(tuple.item1) != exclude);
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
  Stream<Tuple2<String, SourceSpanWithContext>> replace(
          String regexp, String replacement,
          {bool all = false,
          bool caseSensitive = true,
          bool unicode = false,
          bool dotAll = false}) =>
      replaceMapped(regexp, (match) => replaceMatch(match, replacement),
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
  Stream<Tuple2<String, SourceSpanWithContext>> replaceMapped(
      String regexp, String replace(Match match),
      {bool all = false,
      bool caseSensitive = true,
      bool unicode = false,
      bool dotAll = false}) {
    var pattern = RegExp(regexp,
        caseSensitive: caseSensitive, unicode: unicode, dotAll: dotAll);
    return mapLines((line) => all
        ? line.replaceAllMapped(pattern, replace)
        : line.replaceFirstMapped(pattern, replace));
  }

  /// Returns a stream that emits the same events as this one, but also prints
  /// each string to [currentStderr].
  ///
  /// This is primarily intended for debugging.
  Stream<Tuple2<String, SourceSpanWithContext>> get teeToStderr =>
      mapLines((line) {
        currentStderr.writeln(line);
        return line;
      });

  /// Like [Stream.map], but only applies the callback to the lines and not the
  /// spans.
  Stream<Tuple2<String, SourceSpanWithContext>> mapLines(
          String Function(String line) callback) =>
      map((tuple) => Tuple2(callback(tuple.item1), tuple.item2));
}
