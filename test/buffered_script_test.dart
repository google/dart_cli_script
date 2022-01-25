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

// dart-lang/sdk#48173
// ignore_for_file: void_checks

import 'package:async/async.dart';
import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';
import 'package:cli_script/cli_script.dart' as cli_script;

import 'util.dart';

void main() {
  test("doesn't forward stdout until release() is called", () async {
    var script = BufferedScript.capture((_) async {
      print("foo");
      print("bar");
      print("baz");
    });

    var stdout = StringBuffer();
    var stdoutDone = false;
    script.stdout.lines.listen(stdout.writeln, onDone: () => stdoutDone = true);

    await pumpEventQueue();
    expect(stdout, isEmpty);
    expect(stdoutDone, isFalse);

    await script.release();
    expect(stdout.toString(), equals("foo\nbar\nbaz\n"));
    expect(stdoutDone, isTrue);
  });

  test("doesn't forward stderr until release() is called", () async {
    var script = BufferedScript.capture((_) async {
      currentStderr.writeln("foo");
      currentStderr.writeln("bar");
      currentStderr.writeln("baz");
    });

    var stderr = StringBuffer();
    var stderrDone = false;
    script.stderr.lines.listen(stderr.writeln, onDone: () => stderrDone = true);

    await pumpEventQueue();
    expect(stderr, isEmpty);
    expect(stderrDone, isFalse);

    await script.release();
    expect(stderr.toString(), equals("foo\nbar\nbaz\n"));
    expect(stderrDone, isTrue);
  });

  test("replays stdout and stderr interleaved", () async {
    var script = BufferedScript.capture((_) async {
      print("stdout 1");
      currentStderr.writeln("stderr 1");
      print("stdout 2");
      currentStderr.writeln("stderr 2");
      print("stdout 3");
      currentStderr.writeln("stderr 3");
    });

    expect(
        script.combineOutput().lines,
        emitsInOrder([
          "stdout 1",
          "stderr 1",
          "stdout 2",
          "stderr 2",
          "stdout 3",
          "stderr 3"
        ]));

    await pumpEventQueue();
    await script.release();
  });

  test("forwards stdout live once release() is called", () async {
    var script = BufferedScript.capture((stdin) async {
      var stdinQueue = StreamQueue(stdin);
      print("foo");
      await stdinQueue.next;
      print("bar");
      await stdinQueue.next;
      print("baz");
      await stdinQueue.next;
    });

    var releaseCompleted = false;
    script.release().then((_) => releaseCompleted = true);

    var stdoutQueue = StreamQueue(script.stdout.lines);
    await expectLater(stdoutQueue, emits("foo"));
    await pumpEventQueue();
    expect(releaseCompleted, isFalse);

    script.stdin.add([0]);
    await expectLater(stdoutQueue, emits("bar"));
    await pumpEventQueue();
    expect(releaseCompleted, isFalse);

    script.stdin.add([0]);
    await expectLater(stdoutQueue, emits("baz"));
    await pumpEventQueue();
    expect(releaseCompleted, isFalse);

    script.stdin.add([0]);
    await expectLater(stdoutQueue, emitsDone);
    await pumpEventQueue();
    expect(releaseCompleted, isTrue);
  });

  test("forwards stderr live once release() is called", () async {
    var script = BufferedScript.capture((stdin) async {
      var stdinQueue = StreamQueue(stdin);
      currentStderr.writeln("foo");
      await stdinQueue.next;
      currentStderr.writeln("bar");
      await stdinQueue.next;
      currentStderr.writeln("baz");
      await stdinQueue.next;
    });

    var releaseCompleted = false;
    script.release().then((_) => releaseCompleted = true);

    var stderrQueue = StreamQueue(script.stderr.lines);
    await expectLater(stderrQueue, emits("foo"));
    await pumpEventQueue();
    expect(releaseCompleted, isFalse);

    script.stdin.add([0]);
    await expectLater(stderrQueue, emits("bar"));
    await pumpEventQueue();
    expect(releaseCompleted, isFalse);

    script.stdin.add([0]);
    await expectLater(stderrQueue, emits("baz"));
    await pumpEventQueue();
    expect(releaseCompleted, isFalse);

    script.stdin.add([0]);
    await expectLater(stderrQueue, emitsDone);
    await pumpEventQueue();
    expect(releaseCompleted, isTrue);
  });

  group("doesn't top-level", () {
    test("a script failure", () async {
      await BufferedScript.capture((_) {
        throw ScriptException("script", 1);
      }).release();

      // Exception shouldn't be top-leveled even if it's unhandled.
      await pumpEventQueue();
    });

    test("a Dart exception", () async {
      var script = BufferedScript.capture((_) {
        throw "oh no";
      });
      expect(script.stderr.lines, emitsThrough(contains("oh no")));

      await script.release();

      // Exception shouldn't be top-leveled even if it's unhandled.
      await pumpEventQueue();
    });
  });

  group("makes available through done", () {
    test("a script failure", () async {
      expect(
          BufferedScript.capture((_) {
            throw ScriptException("script", 123);
          }).done,
          throwsScriptException(123));
    });

    test("a Dart exception", () async {
      expect(
          BufferedScript.capture((_) {
            throw "oh no";
          }).done,
          throwsScriptException(257));
    });
  });
}
