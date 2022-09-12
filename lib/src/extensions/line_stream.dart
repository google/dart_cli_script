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

import 'package:async/async.dart';
import 'package:cli_script/cli_script.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

import '../util.dart';

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
  /// and the virtual stream process exits with error code 257.
  Script operator |(Script script) => bytes | script;

  /// Shorthand for `stream.bytes.pipe`.
  Future<void> operator >(StreamConsumer<List<int>> consumer) =>
      bytes.pipe(consumer);

  /// Returns a stream of lines along with [FileSpan]s indicating the position
  /// of those lines within the original source (assuming that this stream is
  /// the entirety of the source).
  ///
  /// The [sourceUrl] argument provides the URL of the resulting spans. The
  /// [sourcePath] argument is a shorthand for converting the path to a URL and
  /// passing it to [sourceUrl]. The [sourceUrl] and [sourcePath] arguments may
  /// not both be passed at once.
  ///
  /// See [LineAndSpanStreamExtensions].
  Stream<Tuple2<String, SourceSpanWithContext>> withSpans(
      {Uri? sourceUrl, String? sourcePath}) {
    if (sourcePath != null) {
      if (sourceUrl != null) {
        throw ArgumentError("Only one of url and path may be passed.");
      }
      sourceUrl = p.toUri(sourcePath);
    }

    var lineNumber = 0;
    var offset = 0;
    return map((line) {
      var span = SourceSpanWithContext(
          SourceLocation(offset,
              sourceUrl: sourceUrl, line: lineNumber, column: 0),
          SourceLocation(offset + line.length,
              sourceUrl: sourceUrl, line: lineNumber, column: line.length),
          line,
          line);
      lineNumber++;
      offset += line.length + 1;
      return Tuple2(line, span);
    });
  }

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
  Stream<String> grep(String regexp,
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
        ? expand((line) => pattern
            .allMatches(line)
            .map((match) => match.group(0)!)
            .where((match) => match.isNotEmpty))
        : where((line) => pattern.hasMatch(line) != exclude);
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

  /// Returns a stream that emits the same events as this one, but also prints
  /// each string to [currentStderr].
  ///
  /// This is primarily intended for debugging.
  Stream<String> get teeToStderr => map((line) {
        currentStderr.writeln(line);
        return line;
      });

  /// Passes the strings emitted by this stream as arguments to [callback].
  ///
  /// The [callback] is invoked within a [Script.capture] block, so any stdout
  /// or stderr it emits will be piped into the returned [Script]'s stdout and
  /// stderr streams. If any [callback] throws an error or starts a [Script]
  /// that fails with a non-zero exit code, the returned [Script] will fail as
  /// well.
  ///
  /// Waits for each [callback] to complete before executing the next one. While
  /// it's possible for callbacks to run in parallel by returning before the
  /// processing is complete, this is not recommended, as it will cause error and
  /// output streams from multiple callbacks to become mangled and could cause
  /// later callbacks to be executed even if earlier ones failed.
  ///
  /// If [maxArgs] is passed, this invokes [callback] multiple times, passing at
  /// most [maxArgs] arguments to each invocation. Otherwise, it passes all
  /// arguments to a single invocation.
  ///
  /// If [name] is passed, it's used as the name of the spawned script.
  ///
  /// [Script.kill] closes the input stream. It returns `true` if the stream was
  /// interrupted and the script exits with [Script.exitCode] `143`, or `false`
  /// if the stream was already closed.
  ///
  /// The [callback] can't be interrupted by calling [kill], but the [onSignal]
  /// callback allows capturing those signals so the callback may react
  /// appropriately. Calling [kill] returns `true` even without an [onSignal]
  /// callback if the stream is interrupted.
  ///
  /// See also `xargs` in `package:cli_script/cli_script.dart`, which takes
  /// arguments from [stdin] rather than from this string stream.
  Script xargs(FutureOr<void> callback(List<String> args),
      {int? maxArgs, String? name, void onSignal(ProcessSignal signal)?}) {
    if (maxArgs != null && maxArgs < 1) {
      throw RangeError.range(maxArgs, 1, null, 'maxArgs');
    }

    var signalCloser = StreamCloser<String>();
    var self = transform(signalCloser);
    var chunks =
        maxArgs != null ? self.slices(maxArgs) : self.toList().asStream();

    return Script.capture(
        (_) async {
          await for (var chunk in chunks) {
            if (signalCloser.isClosed) break;
            await callback(chunk);
          }
          if (signalCloser.isClosed) {
            throw ScriptException(name ?? 'xargs', 143);
          }
        },
        name: name,
        onSignal: (signal) {
          signalCloser.close();
          if (onSignal != null) onSignal(signal);
          return true;
        });
  }
}
