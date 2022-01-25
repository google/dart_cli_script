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

import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';
import 'package:cli_script/cli_script.dart' as cli_script;

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

  test("forwards prints even if the capture closes synchronously", () {
    expect(
        Script.capture((_) async {
          print("print");
        }).stdout.lines,
        emitsInOrder(["print", emitsDone]));
  });

  test("forwards prints even if currentStdout is closed", () {
    expect(
        Script.capture((_) async {
          currentStdout.close();
          print("print");
        }).stdout.lines,
        emitsInOrder(["print", emitsDone]));
  });

  test("forwards writes to currentStdout as stdout", () {
    expect(
        Script.capture((_) async {
          await mainScript("print('child 1');").done;
          currentStdout.writeln("print 1");
          await mainScript("print('child 2');").done;
          currentStdout.writeln("print 2");
        }).stdout.lines,
        emitsInOrder([
          "child 1",
          "print 1",
          "child 2",
          "print 2",
        ]));
  });

  test("forwards writes to currentStderr as stderr", () {
    expect(
        Script.capture((_) async {
          await mainScript("stderr.writeln('child 1');").done;
          currentStderr.writeln("print 1");
          await mainScript("stderr.writeln('child 2');").done;
          currentStderr.writeln("print 2");
        }).stderr.lines,
        emitsInOrder([
          "child 1",
          "print 1",
          "child 2",
          "print 2",
        ]));
  });

  group("interleaves prints and currentStdout", () {
    test("synchronously", () {
      expect(
          Script.capture((_) {
            currentStdout.writeln("stdout 1");
            print("stdout 2");
            currentStdout.writeln("stdout 3");
            print("stdout 4");
            currentStdout.writeln("stdout 5");
          }).combineOutput().lines,
          emitsInOrder(
              ["stdout 1", "stdout 2", "stdout 3", "stdout 4", "stdout 5"]));
    });
    test("asynchronously", () {
      expect(
          Script.capture((_) async {
            await pumpEventQueue();
            currentStdout.writeln("stdout 1");
            print("stdout 2");
            currentStdout.writeln("stdout 3");
            print("stdout 4");
            currentStdout.writeln("stdout 5");
          }).combineOutput().lines,
          emitsInOrder(
              ["stdout 1", "stdout 2", "stdout 3", "stdout 4", "stdout 5"]));
    });
  });

  group("interleaves writes to stdout and stderr", () {
    test("synchronously", () {
      expect(
          Script.capture((_) {
            currentStdout.writeln("stdout 1");
            currentStderr.writeln("stderr 1");
            print("stdout 2");
            currentStderr.writeln("stderr 2");
            currentStdout.writeln("stdout 3");
            currentStdout.writeln("stdout 4");
            currentStderr.writeln("stderr 3");
          }).combineOutput().lines,
          emitsInOrder([
            "stdout 1",
            "stderr 1",
            "stdout 2",
            "stderr 2",
            "stdout 3",
            "stdout 4",
            "stderr 3"
          ]));
    });

    test("asynchronously", () {
      expect(
          Script.capture((_) async {
            await pumpEventQueue();
            currentStdout.writeln("stdout 1");
            currentStderr.writeln("stderr 1");
            print("stdout 2");
            currentStderr.writeln("stderr 2");
            currentStdout.writeln("stdout 3");
            currentStdout.writeln("stdout 4");
            currentStderr.writeln("stderr 3");
          }).combineOutput().lines,
          emitsInOrder([
            "stdout 1",
            "stderr 1",
            "stdout 2",
            "stderr 2",
            "stdout 3",
            "stdout 4",
            "stderr 3"
          ]));
    });
  });

  test("prints an unhandled error to stderr", () {
    var script = Script.capture((_) => throw "oh no");
    expect(script.done, throwsA(anything));
    expect(script.stderr.lines, emitsInOrder(["Error in capture:", "oh no"]));
  });

  test("prints fail's message to stderr", () {
    var script = Script.capture((_) => cli_script.fail("oh no"));
    expect(script.done, throwsA(anything));
    expect(script.stderr.lines, emitsInOrder(["oh no", emitsDone]));
  });

  group("exitCode", () {
    test("completes with 0 when the capture exits successfully", () {
      expect(Script.capture((_) {}).exitCode, completion(equals(0)));
    });

    test("completes with 257 when the capture throws", () {
      var script = Script.capture((_) => throw "oh no");
      script.stderr.drain<void>();
      expect(script.exitCode, completion(equals(257)));
    });

    test("completes with the given exit code when fail() is called", () {
      var script =
          Script.capture((_) => cli_script.fail("oh no", exitCode: 42));
      script.stderr.drain<void>();
      expect(script.exitCode, completion(equals(42)));
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
      var completer = Completer<void>();

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
      var childDoneCompleter = Completer<void>();
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
      var script = Script.capture((_) {
        Future<void>.error("oh no");
        return Completer<void>().future;
      });
      script.stderr.drain<void>();
      expect(script.exitCode, completion(equals(257)));
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
      var childSpawnedCompleter = Completer<void>();
      var captureDoneCompleter = Completer<void>();
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
      var captureDoneCompleter = Completer<void>();
      captureDoneCompleter.complete(Script.capture((_) async {
        await captureDoneCompleter.future;
        throw "oh no";
      }).done);

      // Give "oh no" time to get top-leveled if it's going to.
      await pumpEventQueue();
    });
  });
}
