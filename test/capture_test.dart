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

import 'package:async/async.dart';
import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';

import 'util.dart';

void main() {
  test("forwards stdout from child processes", () {
    expect(
        Script.capture((_) async {
          await mainScript("print('child 1');").done;
          await mainScript("print('child 2');").done;
          await mainScript("print('child 3');").done;
        }).stdout.lines,
        emitsInOrder(["child 1", "child 2", "child 3"]));
  });

  test("forwards stderr from child processes", () {
    expect(
        Script.capture((_) async {
          await mainScript("stderr.writeln('child 1');").done;
          await mainScript("stderr.writeln('child 2');").done;
          await mainScript("stderr.writeln('child 3');").done;
        }).stderr.lines,
        emitsInOrder(["child 1", "child 2", "child 3"]));
  });

  test("forwards prints as stdout", () {
    expect(
        Script.capture((_) async {
          await mainScript("print('child 1');").done;
          print("print 1");
          await mainScript("print('child 2');").done;
          print("print 2");
        }).stdout.lines,
        emitsInOrder([
          "child 1",
          "print 1",
          "child 2",
          "print 2",
        ]));
  });

  test("prints an unhandled error to stderr", () {
    var script = Script.capture((_) => throw "oh no");
    expect(script.done, throwsA(anything));
    expect(script.stderr.lines, emitsInOrder(["Error in capture:", "oh no"]));
  });

  group("exitCode", () {
    test("completes with 0 when the capture exits successfully", () {
      expect(Script.capture((_) {}).exitCode, completion(equals(0)));
    });

    test("completes with 256 when the capture throws", () {
      expect(Script.capture((_) => throw "oh no").exitCode,
          completion(equals(256)));
    });

    group("forwards a child script's exit code", () {
      test("when the child's done future isn't listened", () {
        expect(
            Script.capture((_) {
              mainScript("exitCode = 123;");
            }).exitCode,
            completion(equals(123)));
      });

      test("when the child's done future is piped through the callback", () {
        expect(
            Script.capture((_) => mainScript("exitCode = 123;").done).exitCode,
            completion(equals(123)));
      });

      test("when the child's done future error is top-leveled", () {
        expect(
            Script.capture((_) {
              mainScript("exitCode = 123;").done.then((_) {});
            }).exitCode,
            completion(equals(123)));
      });
    });

    group("ignores a child script's exit code", () {
      test("when the child's done future exception is handled out-of-band", () {
        expect(
            Script.capture((_) {
              mainScript("exitCode = 123;").done.catchError((_) {});
            }).exitCode,
            completion(equals(0)));
      });

      test("when the child's done future exception is handled in-band", () {
        expect(
            Script.capture((_) =>
                mainScript("exitCode = 123;").done.catchError((_) {})).exitCode,
            completion(equals(0)));
      });

      test("when the child's success field is accessed", () {
        expect(
            Script.capture((_) {
              mainScript("exitCode = 123;").success;
            }).exitCode,
            completion(equals(0)));
      });

      test("when the child's exitCode field is accessed", () {
        expect(
            Script.capture((_) {
              mainScript("exitCode = 123;").exitCode;
            }).exitCode,
            completion(equals(0)));
      });
    });

    test("doesn't complete until the body completes", () async {
      var completer = Completer();

      var doneComplete = false;
      Script.capture((_) => completer.future).done.then((_) {
        doneComplete = true;
      });

      await pumpEventQueue();
      expect(doneComplete, isFalse);

      completer.complete();
      await pumpEventQueue();
      expect(doneComplete, isTrue);
    });

    test("doesn't complete until all child scripts complete", () async {
      var stdinCompleter = Completer<IOSink>();
      var childDoneCompleter = Completer();
      var doneComplete = false;
      Script.capture((_) {
        // Run an extra script just to make totally sure there's a lot of time
        var script = mainScript("stdin.readLineSync();");
        stdinCompleter.complete(script.stdin);
        childDoneCompleter.complete(script.done);
      }).done.then((_) {
        doneComplete = true;
      });

      var stdin = await stdinCompleter.future;
      expect(doneComplete, isFalse);
      stdin.writeln("");

      await childDoneCompleter.future;
      await pumpEventQueue();
      expect(doneComplete, isTrue);
    });

    test(
        "completes when an error is top-leveled even if the callback isn't "
        "done", () async {
      expect(
          Script.capture((_) {
            Future.error("oh no");
            return Completer().future;
          }).exitCode,
          completion(equals(256)));
    });
  });

  group("stdin", () {
    test("passes data to the stdin argument", () {
      Script.capture((stdin) async {
        await expectLater(stdin.lines, emits("hello!"));
      }).stdin.writeln("hello!");
    });

    test("passes a done event to the stdin argument", () {
      Script.capture((stdin) async {
        await expectLater(stdin, emitsDone);
      }).stdin.close();
    });
  });

  group("after the capture is done", () {
    test("stdout closes", () {
      expect(Script.capture((_) {}).stdout, emitsDone);
    });

    test("stderr closes", () {
      expect(Script.capture((_) {}).stdout, emitsDone);
    });

    test("spawning a child script throws an error", () {
      var childSpawnedCompleter = Completer();
      var captureDoneCompleter = Completer();
      captureDoneCompleter.complete(Script.capture((_) {
        captureDoneCompleter.future.then((_) {
          try {
            mainScript("");
            childSpawnedCompleter.complete();
          } catch (error, stackTrace) {
            childSpawnedCompleter.completeError(error, stackTrace);
          }
        });
      }).done);

      expect(childSpawnedCompleter.future, throwsStateError);
    });

    test("additional errors are swallowed", () async {
      var captureDoneCompleter = Completer();
      captureDoneCompleter.complete(Script.capture((_) async {
        await captureDoneCompleter.future;
        throw "oh no";
      }).done);

      // Give "oh no" time to get top-leveled if it's going to.
      await pumpEventQueue();
    });
  });
}
