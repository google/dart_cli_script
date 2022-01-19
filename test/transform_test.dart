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

import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';

// Tests for utility stream transforms.
void main() {
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
