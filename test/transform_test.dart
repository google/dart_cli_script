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

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';

import 'util.dart';

// Tests for utility stream transforms.
void main() {
  group("withSpans", () {
    test("emits each line", () async {
      var tuples =
          await Stream.fromIterable(["foo", "bar", "baz"]).withSpans().toList();
      expect(tuples[0].item1, equals("foo"));
      expect(tuples[1].item1, equals("bar"));
      expect(tuples[2].item1, equals("baz"));
    });

    test("emits spans that cover each line", () async {
      var tuples =
          await Stream.fromIterable(["foo", "bar", "baz"]).withSpans().toList();

      expect(tuples[0].item2.start.offset, equals(0));
      expect(tuples[0].item2.start.line, equals(0));
      expect(tuples[0].item2.start.column, equals(0));
      expect(tuples[0].item2.end.offset, equals(3));
      expect(tuples[0].item2.end.line, equals(0));
      expect(tuples[0].item2.end.column, equals(3));
      expect(tuples[0].item2.text, equals("foo"));
      expect(tuples[0].item2.context, equals("foo"));

      expect(tuples[1].item2.start.offset, equals(4));
      expect(tuples[1].item2.start.line, equals(1));
      expect(tuples[1].item2.start.column, equals(0));
      expect(tuples[1].item2.end.offset, equals(7));
      expect(tuples[1].item2.end.line, equals(1));
      expect(tuples[1].item2.end.column, equals(3));
      expect(tuples[1].item2.text, equals("bar"));
      expect(tuples[1].item2.context, equals("bar"));

      expect(tuples[2].item2.start.offset, equals(8));
      expect(tuples[2].item2.start.line, equals(2));
      expect(tuples[2].item2.start.column, equals(0));
      expect(tuples[2].item2.end.offset, equals(11));
      expect(tuples[2].item2.end.line, equals(2));
      expect(tuples[2].item2.end.column, equals(3));
      expect(tuples[2].item2.text, equals("baz"));
      expect(tuples[2].item2.context, equals("baz"));
    });

    test("URLs default to null", () async {
      var tuples =
          await Stream.fromIterable(["foo", "bar", "baz"]).withSpans().toList();

      expect(tuples[0].item2.sourceUrl, isNull);
      expect(tuples[0].item2.start.sourceUrl, isNull);
      expect(tuples[0].item2.end.sourceUrl, isNull);

      expect(tuples[1].item2.sourceUrl, isNull);
      expect(tuples[1].item2.start.sourceUrl, isNull);
      expect(tuples[1].item2.end.sourceUrl, isNull);

      expect(tuples[2].item2.sourceUrl, isNull);
      expect(tuples[2].item2.start.sourceUrl, isNull);
      expect(tuples[2].item2.end.sourceUrl, isNull);
    });

    test("URLs can be set with sourceUrl", () async {
      var url = Uri.parse('file:///some/file.txt');
      var tuples = await Stream.fromIterable(["foo", "bar", "baz"])
          .withSpans(sourceUrl: url)
          .toList();

      expect(tuples[0].item2.sourceUrl, equals(url));
      expect(tuples[0].item2.start.sourceUrl, equals(url));
      expect(tuples[0].item2.end.sourceUrl, equals(url));

      expect(tuples[1].item2.sourceUrl, equals(url));
      expect(tuples[1].item2.start.sourceUrl, equals(url));
      expect(tuples[1].item2.end.sourceUrl, equals(url));

      expect(tuples[2].item2.sourceUrl, equals(url));
      expect(tuples[2].item2.start.sourceUrl, equals(url));
      expect(tuples[2].item2.end.sourceUrl, equals(url));
    });

    test("URLs can be set with sourcePath", () async {
      var path = 'some/file';
      var url = p.toUri(path);
      var tuples = await Stream.fromIterable(["foo", "bar", "baz"])
          .withSpans(sourcePath: path)
          .toList();

      expect(tuples[0].item2.sourceUrl, equals(url));
      expect(tuples[0].item2.start.sourceUrl, equals(url));
      expect(tuples[0].item2.end.sourceUrl, equals(url));

      expect(tuples[1].item2.sourceUrl, equals(url));
      expect(tuples[1].item2.start.sourceUrl, equals(url));
      expect(tuples[1].item2.end.sourceUrl, equals(url));

      expect(tuples[2].item2.sourceUrl, equals(url));
      expect(tuples[2].item2.start.sourceUrl, equals(url));
      expect(tuples[2].item2.end.sourceUrl, equals(url));
    });

    test("sourcePath and sourceUrl can't both be set", () async {
      expect(
          () => Stream.fromIterable(["foo", "bar", "baz"])
              .withSpans(sourceUrl: Uri.parse("foo"), sourcePath: "foo"),
          throwsArgumentError);
    });
  });

  group("grep", () {
    test("returns matching lines", () {
      expect(Stream.fromIterable(["foo", "bar", "baz"]).grep(r"^b"),
          emitsInOrder(["bar", "baz", emitsDone]));
    });

    test("returns non-matching lines with exclude: true", () {
      expect(
          Stream.fromIterable(["foo", "bar", "baz"]).grep(r"^b", exclude: true),
          emitsInOrder(["foo", emitsDone]));
    });

    group("with onlyMatching: true", () {
      test("throws an error if exclude is also true", () {
        expect(
            () => Stream.fromIterable(["foo", "bar", "baz"])
                .grep(r"^b", onlyMatching: true, exclude: true),
            throwsArgumentError);
      });

      test("prints the matching parts of lines that match", () {
        expect(
            Stream.fromIterable(["foo", "bar", "baz"])
                .grep(r"a.", onlyMatching: true),
            emitsInOrder(["ar", "az"]));
      });

      test("prints multiple matching parts per line", () {
        expect(
            Stream.fromIterable(["foo bar", "baz bang bop"])
                .grep(r"[a-z]{3}", onlyMatching: true),
            emitsInOrder(["foo", "bar", "baz", "ban", "bop"]));
      });

      test("doesn't print empty matches", () {
        expect(
            Stream.fromIterable(["foo", "bar", "baz"])
                .grep(r"q?", onlyMatching: true),
            emitsDone);
      });
    });

    group("with spans", () {
      test("returns matching spans", () async {
        var tuples = await Stream.fromIterable(["foo", "bar", "baz"])
            .withSpans()
            .grep(r"^b")
            .toList();
        expect(tuples, hasLength(2));
        expect(tuples[0].item2.text, equals("bar"));
        expect(tuples[1].item2.text, equals("baz"));
      });

      test("returns non-matching spans with exclude: true", () async {
        var tuples = await Stream.fromIterable(["foo", "bar", "baz"])
            .withSpans()
            .grep(r"^b", exclude: true)
            .toList();
        expect(tuples, hasLength(1));
        expect(tuples[0].item2.text, equals("foo"));
      });

      group("with onlyMatching: true", () {
        test("emits the matching parts of spans that match", () async {
          var tuples = await Stream.fromIterable(["foo", "bar", "baz"])
              .withSpans()
              .grep(r"a.", onlyMatching: true)
              .toList();

          expect(tuples, hasLength(2));
          expect(tuples[0].item2.text, equals("ar"));
          expect(tuples[1].item2.text, equals("az"));
        });

        test("preserves the context of spans that match", () async {
          var tuples = await Stream.fromIterable(["foo", "bar", "baz"])
              .withSpans()
              .grep(r"a.", onlyMatching: true)
              .toList();

          expect(tuples, hasLength(2));
          expect(tuples[0].item2.context, equals("bar"));
          expect(tuples[1].item2.context, equals("baz"));
        });

        test("emits the matching parts of multiple matches per line", () async {
          var tuples = await Stream.fromIterable(["foo bar", "baz bang bop"])
              .withSpans()
              .grep(r"[a-z]{3}", onlyMatching: true)
              .toList();

          expect(tuples, hasLength(5));
          expect(tuples[0].item2.text, equals("foo"));
          expect(tuples[1].item2.text, equals("bar"));
          expect(tuples[2].item2.text, equals("baz"));
          expect(tuples[3].item2.text, equals("ban"));
          expect(tuples[4].item2.text, equals("bop"));
        });

        test("preserves the context of multiple matches per line", () async {
          var tuples = await Stream.fromIterable(["foo bar", "baz bang bop"])
              .withSpans()
              .grep(r"[a-z]{3}", onlyMatching: true)
              .toList();

          expect(tuples, hasLength(5));
          expect(tuples[0].item2.context, equals("foo bar"));
          expect(tuples[1].item2.context, equals("foo bar"));
          expect(tuples[2].item2.context, equals("baz bang bop"));
          expect(tuples[3].item2.context, equals("baz bang bop"));
          expect(tuples[4].item2.context, equals("baz bang bop"));
        });
      });
    });
  });

  group("replaceMapped", () {
    test("replaces the first match", () {
      expect(
          Stream.fromIterable(["foo", "bar baz", "boz bop"])
              .replaceMapped(r"b(.)", (match) => match[1]! + "q"),
          emitsInOrder(["foo", "aqr baz", "oqz bop", emitsDone]));
    });

    test("replaces all matches with all: true", () {
      expect(
          Stream.fromIterable(["foo", "bar baz", "boz bop"])
              .replaceMapped(r"b(.)", (match) => match[1]! + "q", all: true),
          emitsInOrder(["foo", "aqr aqz", "oqz oqp", emitsDone]));
    });
  });

  group("replace", () {
    test("replaces the first match", () {
      expect(
          Stream.fromIterable(["foo", "bar baz", "boz bop"])
              .replace(r"b(.)", r"\1q"),
          emitsInOrder(["foo", "aqr baz", "oqz bop", emitsDone]));
    });

    test("replaces all matches with all: true", () {
      expect(
          Stream.fromIterable(["foo", "bar baz", "boz bop"])
              .replace(r"b(.)", r"\1q", all: true),
          emitsInOrder(["foo", "aqr aqz", "oqz oqp", emitsDone]));
    });

    test("converts double backslash to single", () {
      expect(
          Stream.fromIterable(["foo", "bar", "boz"]).replace(r"b(.)", r"\\q"),
          emitsInOrder(["foo", r"\qr", r"\qz", emitsDone]));
    });

    test("ignores other backslash", () {
      expect(Stream.fromIterable(["foo", "bar", "boz"]).replace(r"b(.)", r"\q"),
          emitsInOrder(["foo", "qr", "qz", emitsDone]));
    });

    test("allows trailing backslash", () {
      expect(Stream.fromIterable(["foo", "bar", "boz"]).replace(r"b(.)", "q\\"),
          emitsInOrder(["foo", "qr", "qz", emitsDone]));
    });

    test("allows references to unmatched groups", () {
      expect(
          Stream.fromIterable(["foo", "bar", "boz"])
              .replace(r"(zink)|(bar)", r"\1"),
          emitsInOrder(["foo", "", "boz", emitsDone]));
    });

    test("forbids references to non-existent groups", () {
      expect(
          Stream.fromIterable(["foo", "bar", "boz"])
              .replace(r"(zink)|(bar)", r"\3"),
          emitsInOrder(["foo", emitsError(isFormatException)]));
    });
  });

  group("teeToStderr", () {
    test("passes inputs through as-is", () {
      silenceStderr(() {
        expect(Stream.fromIterable(["foo", "bar", "baz"]).teeToStderr,
            emitsInOrder(["foo", "bar", "baz"]));
      });
    });

    test("emits inputs to sdterr", () {
      var script = Script.capture((_) =>
          Stream.fromIterable(["foo", "bar", "baz"]).teeToStderr.drain<void>());
      expect(script.stderr.lines, emitsInOrder(["foo", "bar", "baz"]));
    });
  });

  group("xargs", () {
    group("from a stream", () {
      test("passes stream entries as arguments", () {
        var script = Stream.fromIterable(["foo", "bar\nbaz"]).xargs(
            expectAsync1((args) => expect(args, equals(["foo", "bar\nbaz"]))));
        expect(script.done, completes);
      });

      test("only passes maxArgs per callback", () {
        var count = 0;
        var script = Stream.fromIterable(["1", "2", "3", "4", "5"]).xargs(
            expectAsync1((args) {
              if (count == 0) {
                expect(args, equals(["1", "2", "3"]));
              } else {
                expect(args, equals(["4", "5"]));
              }
              count++;
            }, count: 2),
            maxArgs: 3);
        expect(script.done, completes);
      });

      test("doesn't run a future callback until a previous one returns",
          () async {
        var count = 0;
        var completer = Completer<void>();
        var script = Stream.fromIterable(["1", "2"]).xargs(
            expectAsync1((args) {
              count++;
              return completer.future;
            }, count: 2),
            maxArgs: 1);
        expect(script.done, completes);

        await pumpEventQueue();
        expect(count, equals(1));

        completer.complete();
        await pumpEventQueue();
        expect(count, equals(2));
      });

      test("the script doesn't complete until the callbacks are finished",
          () async {
        var count = 0;
        var completers = List.generate(5, (_) => Completer<void>());
        var script = Stream.fromIterable(["1", "2", "3", "4", "5"]).xargs(
            expectAsync1((args) => completers[count++].future, count: 5),
            maxArgs: 1);

        var done = false;
        script.done.then((_) {
          done = true;
        });

        for (var completer in completers) {
          await pumpEventQueue();
          expect(done, isFalse);
          completer.complete();
        }

        await pumpEventQueue();
        expect(done, isTrue);
      });

      test("the script doesn't complete until the callbacks are finished",
          () async {
        var count = 0;
        var completers = List.generate(5, (_) => Completer<void>());
        var script = Stream.fromIterable(["1", "2", "3", "4", "5"]).xargs(
            expectAsync1((args) => completers[count++].future, count: 5),
            maxArgs: 1);

        var done = false;
        script.done.then((_) {
          done = true;
        });

        for (var completer in completers) {
          await pumpEventQueue();
          expect(done, isFalse);
          completer.complete();
        }

        await pumpEventQueue();
        expect(done, isTrue);
      });

      test("the script fails if the stream throws", () async {
        var controller = StreamController<String>();
        var script = controller.stream.xargs(print);
        script.stderr.drain<void>();

        controller.addError(Exception('oh no'));
        expect(script.done, throwsScriptException(257));
      });

      test(
          "the script fails preserving the exit code "
          "if the stream throws a ScriptException", () async {
        var controller = StreamController<String>();
        var script = controller.stream.xargs(print);
        script.stderr.drain<void>();

        controller.addError(ScriptException('whatever', 42));
        expect(script.done, throwsScriptException(42));
      });

      test("the script fails once a callback throws", () async {
        var script = Stream.fromIterable(["1", "2", "3", "4", "5"])
            .xargs(expectAsync1((args) => throw "oh no", count: 1), maxArgs: 1);
        script.stderr.drain<void>();
        expect(script.exitCode, completion(equals(257)));

        // Give xargs time to run further callbacks if it's going to.
        await pumpEventQueue();
      });
    });

    group("as a script", () {
      test("converts each line of stdin into an argument", () {
        var script = Script.capture((_) {
              print("foo bar");
              print("baz\nbang");
            }) |
            xargs(expectAsync1(
                (args) => expect(args, equals(["foo bar", "baz", "bang"]))));
        expect(script.done, completes);
      });
    });
  });
}
