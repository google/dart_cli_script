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

import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';

import 'util.dart';

void main() {
  test("pipes one script's stdout into another's stdin", () {
    var pipeline = mainScript('print("hello!");') |
        Script.capture((stdin) async {
          await expectLater(stdin.lines, emits("hello!"));
        });
    expect(pipeline.done, completes);
  });

  test("pipes the pipeline's stdin into the first script's stdin", () {
    var pipeline = mainScript('print("a: " + stdin.readLineSync()!);') |
        mainScript('print("b: " + stdin.readLineSync()!);');
    pipeline.stdin.writeln("hello!");
    expect(pipeline.stdout.lines, emits("b: a: hello!"));
  });

  test("pipes a scriptlike object", () {
    var pipeline =
        mainScript('stdout.add(zlib.encode(utf8.encode("hello!")));') |
            zlib.decoder;
    expect(pipeline.stdout.lines, emits("hello!"));
  });

  group("pipes many scripts' stdios together", () {
    test("with Script.pipeline", () {
      var pipeline = Script.pipeline([
        mainScript('print("a: " + stdin.readLineSync()!);'),
        mainScript('print("b: " + stdin.readLineSync()!);'),
        mainScript('print("c: " + stdin.readLineSync()!);'),
        mainScript('print("d: " + stdin.readLineSync()!);')
      ]);
      pipeline.stdin.writeln("hello!");
      expect(pipeline.stdout.lines, emits("d: c: b: a: hello!"));
    });

    test("with repeated |", () {
      var pipeline = mainScript('print("a: " + stdin.readLineSync()!);') |
          mainScript('print("b: " + stdin.readLineSync()!);') |
          mainScript('print("c: " + stdin.readLineSync()!);') |
          mainScript('print("d: " + stdin.readLineSync()!);');
      pipeline.stdin.writeln("hello!");
      expect(pipeline.stdout.lines, emits("d: c: b: a: hello!"));
    });
  });

  test("only includes the last script's stderr in the pipeline's", () {
    late Script pipeline;
    var captured = Script.capture((_) {
      pipeline = mainScript('stderr.writeln("script 1");') |
          mainScript('stderr.writeln("script 2");');
    });

    expect(captured.stderr.lines, emits("script 1"));
    expect(pipeline.stderr.lines, emits("script 2"));
  });

  group("on exit", () {
    group("if both succeed, waits for both scripts to exit", () {
      test("if the first exits first", () async {
        var completer = Completer<void>();
        var script1 = mainScript("");
        var pipeline = script1 | Script.capture((_) => completer.future);

        var doneCompleted = false;
        pipeline.done.then((_) => doneCompleted = true);
        await script1.done;
        await pumpEventQueue();
        expect(doneCompleted, isFalse);

        completer.complete();
        await pumpEventQueue();
        expect(doneCompleted, isTrue);
      });

      test("if the second exits first", () async {
        var completer = Completer<void>();
        var script2 = mainScript("");
        var pipeline = Script.capture((_) => completer.future) | script2;

        var doneCompleted = false;
        pipeline.done.then((_) => doneCompleted = true);
        await script2.done;
        await pumpEventQueue();
        expect(doneCompleted, isFalse);

        completer.complete();
        await pumpEventQueue();
        expect(doneCompleted, isTrue);
      });
    });

    group("if one fails", () {
      group("waits for both scripts to exit and returns the failing exit code",
          () {
        group("if the first exits first", () {
          test("and the first fails", () async {
            var completer = Completer<void>();
            var script1 = mainScript("exitCode = 123;");
            var pipeline = script1 | Script.capture((_) => completer.future);

            int? exitCode;
            pipeline.exitCode.then((exitCode_) => exitCode = exitCode_);
            expect(await script1.exitCode, equals(123));
            await pumpEventQueue();
            expect(exitCode, isNull);

            completer.complete();
            await pumpEventQueue();
            expect(exitCode, equals(123));
          });

          test("and the second fails", () async {
            var completer = Completer<void>();
            var script1 = mainScript("");
            var pipeline = script1 |
                Script.capture((_) async {
                  await completer.future;
                  throw "oh no";
                });

            // Don't print the unhandled error.
            pipeline.stderr.listen(null);

            int? exitCode;
            pipeline.exitCode.then((exitCode_) => exitCode = exitCode_);
            await script1.done;
            await pumpEventQueue();
            expect(exitCode, isNull);

            completer.complete();
            await pumpEventQueue();
            expect(exitCode, equals(256));
          });
        });

        group("if the second exits first", () {
          test("and the first fails", () async {
            var completer = Completer<void>();

            var capture = Script.capture((_) async {
              await completer.future;
              throw "oh no";
            });

            // Don't print the unhandled error.
            capture.stderr.listen(null);

            var script2 = mainScript("");
            var pipeline = capture | script2;

            int? exitCode;
            pipeline.exitCode.then((exitCode_) => exitCode = exitCode_);
            await script2.done;
            await pumpEventQueue();
            expect(exitCode, isNull);

            completer.complete();
            await pumpEventQueue();
            expect(exitCode, equals(256));
          });

          test("and the second fails", () async {
            var completer = Completer<void>();
            var script2 = mainScript("exitCode = 123;");
            var pipeline = Script.capture((_) => completer.future) | script2;

            int? exitCode;
            pipeline.exitCode.then((exitCode_) => exitCode = exitCode_);
            expect(await script2.exitCode, equals(123));
            await pumpEventQueue();
            expect(exitCode, isNull);

            completer.complete();
            await pumpEventQueue();
            expect(exitCode, equals(123));
          });
        });
      });

      group(
          "the error isn't top-leveled if it's handled only at the pipeline "
          "level", () {
        test("if the first fails", () async {
          var pipeline = mainScript("exitCode = 1;") | mainScript("");
          expect(await pipeline.exitCode, equals(1));

          // Give time for an unhandled error to be top-leveled.
          await pumpEventQueue();
        });

        test("if the second fails", () async {
          var pipeline = mainScript("") | mainScript("exitCode = 1;");
          expect(await pipeline.exitCode, equals(1));

          // Give time for an unhandled error to be top-leveled.
          await pumpEventQueue();
        });
      });
    });

    group("if both fail", () {
      group("returns the last exit code", () {
        test("if the first exits first", () async {
          var completer = Completer<void>();
          var script1 = mainScript("exitCode = 123;");
          var pipeline = script1 |
              Script.capture((_) async {
                await completer.future;
                throw "oh no";
              });

          // Don't print the unhandled error.
          pipeline.stderr.listen(null);

          int? exitCode;
          pipeline.exitCode.then((exitCode_) => exitCode = exitCode_);
          expect(await script1.exitCode, equals(123));
          await pumpEventQueue();
          expect(exitCode, isNull);

          completer.complete();
          await pumpEventQueue();
          expect(exitCode, equals(256));
        });

        test("if the last exits first", () async {
          var completer = Completer<void>();

          var capture = Script.capture((_) async {
            await completer.future;
            throw "oh no";
          });

          // Don't print the unhandled error.
          capture.stderr.listen(null);

          var script2 = mainScript("exitCode = 123;");
          var pipeline = capture | script2;

          int? exitCode;
          pipeline.exitCode.then((exitCode_) => exitCode = exitCode_);
          expect(await script2.exitCode, equals(123));
          await pumpEventQueue();
          expect(exitCode, isNull);

          completer.complete();
          await pumpEventQueue();
          expect(exitCode, equals(123));
        });
      });

      test(
          "the error isn't top-leveled if it's handled only at the pipeline "
          "level", () async {
        var pipeline =
            mainScript("exitCode = 1;") | mainScript("exitCode = 2;");
        expect(await pipeline.exitCode, equals(2));

        // Give time for an unhandled error to be top-leveled.
        await pumpEventQueue();
      });
    });
  });

  group("pipes in", () {
    group("a byte stream", () {
      test("without errors", () {
        var pipeline =
            Stream.fromIterable([utf8.encode("foo"), utf8.encode("bar")]) |
                mainScript("stdin.pipe(stdout);");
        expect(pipeline.stdout.lines, emitsInOrder(["foobar", emitsDone]));
      });

      test("with an error", () {
        var capture = Script.capture((_) {
          var pipeline = Stream<List<int>>.error("oh no") | mainScript("");
          expect(pipeline.exitCode, completion(equals(256)));
        });

        expect(capture.stderr.lines, emitsThrough(contains("oh no")));
        expect(capture.done, completes);
      });
    });

    group("a string stream", () {
      test("without errors", () {
        var pipeline = Stream.fromIterable(["foo", "bar"]) |
            mainScript("stdin.pipe(stdout);");
        expect(pipeline.stdout.lines, emitsInOrder(["foo", "bar", emitsDone]));
      });

      test("with an error", () {
        var capture = Script.capture((_) {
          var pipeline = Stream<String>.error("oh no") | mainScript("");
          expect(pipeline.exitCode, completion(equals(256)));
        });

        expect(capture.stderr.lines, emitsThrough(contains("oh no")));
      });
    });

    test("a chunk list", () {
      var pipeline = [utf8.encode("foo"), utf8.encode("bar")] |
          mainScript("stdin.pipe(stdout);");
      expect(pipeline.stdout.lines, emitsInOrder(["foobar", emitsDone]));
    });

    test("a byte list", () {
      var pipeline = utf8.encode("foobar") | mainScript("stdin.pipe(stdout);");
      expect(pipeline.stdout.lines, emitsInOrder(["foobar", emitsDone]));
    });

    test("a string list", () {
      var pipeline = ["foo", "bar"] | mainScript("stdin.pipe(stdout);");
      expect(pipeline.stdout.lines, emitsInOrder(["foo", "bar", emitsDone]));
    });

    test("a string", () {
      var pipeline = "foobar" | mainScript("stdin.pipe(stdout);");
      expect(pipeline.stdout.lines, emitsInOrder(["foobar", emitsDone]));
    });
  });
}
