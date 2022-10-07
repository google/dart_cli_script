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

import 'fake_stream_consumer.dart';
import 'util.dart';

void main() {
  group("exit code", () {
    test("is available via the exitCode getter", () {
      expect(mainScript("exitCode = 123;").exitCode, completion(equals(123)));
    });

    test(".success returns true for exit code 0", () {
      expect(mainScript("exitCode = 0;").success, completion(isTrue));
    });

    test(".success returns false for non-zero exit code", () {
      expect(mainScript("exitCode = 1;").success, completion(isFalse));
    });

    test(".done doesn't throw for exit code 0", () {
      expect(mainScript("exitCode = 0;").done, completes);
    });

    test(".done throws a ScriptException for non-zero exit code", () {
      expect(mainScript("exitCode = 234;").done, throwsScriptException(234));
    });

    test("is non-zero for a script that can't be found", () async {
      var script = Script("non-existent-executable");
      expect(script.success, completion(isFalse));
    });
  });

  stdoutOrStderr("stdout", (script) => script.stdout);
  stdoutOrStderr("stderr", (script) => script.stderr);

  test("an error while spawning is printed to stderr", () {
    var script = Script("non-existent-executable");
    expect(script.exitCode, completion(equals(257)));
    expect(
        script.stderr.lines,
        emitsInOrder([
          "Error in non-existent-executable:",
          "ProcessException: No such file or directory"
        ]));
  });

  group("stdin", () {
    test("passes data to the process's stdin", () {
      var script = mainScript("exitCode = int.parse(stdin.readLineSync()!);");
      script.stdin.writeln("42");
      expect(script.exitCode, completion(equals(42)));
    });

    test("passes a done event to the process's stdin", () {
      var script = mainScript("print(stdin.readLineSync());");
      script.stdin.close();
      expect(script.stdout.lines, emits("null"));
    });
  });

  group("> adds output to a consumer", () {
    test("that listens immediately", () async {
      var controller = StreamController<List<int>>();
      expect(mainScript("print('hello!');") > controller, completes);
      expect(controller.stream.lines, emits("hello!"));
    });

    // This mimics the behavior of [File.openWrite], which doesn't call
    // [Stream.listen] until the file is actually open.
    test("that waits to listen", () async {
      await (mainScript("print('hello!');") >
          FakeStreamConsumer(expectAsync1((stream) async {
            await pumpEventQueue();
            expect(stream.lines, emits("hello!"));
          })));
    });
  });

  group("subprocess environment", () {
    test("defaults to the parent environment", () {
      expect(_getSubprocessEnvironment(),
          completion(equals(Platform.environment)));
    });

    test("includes modifications to env", () {
      var varName = uid();
      env[varName] = "value";
      expect(_getSubprocessEnvironment(),
          completion(containsPair(varName, "value")));
    });

    test("includes scoped modifications to env", () {
      var varName = uid();
      withEnv(() {
        expect(_getSubprocessEnvironment(),
            completion(containsPair(varName, "value")));
      }, {varName: "value"});
    });

    test("includes values from the environment parameter", () {
      var varName = uid();
      expect(_getSubprocessEnvironment(environment: {varName: "value"}),
          completion(containsPair(varName, "value")));
    });

    test("the environment parameter overrides env", () {
      var varName = uid();
      env[varName] = "outer value";
      expect(_getSubprocessEnvironment(environment: {varName: "inner value"}),
          completion(containsPair(varName, "inner value")));
    });

    group("with includeParentEnvironment: false", () {
      // It would be nice to test that the environment is fully empty in the
      // subprocess, but some environment variables unavoidably exist when
      // spawning a process (at least on Linux).

      test("ignores env", () {
        var varName = uid();
        env[varName] = "value";
        expect(_getSubprocessEnvironment(includeParentEnvironment: false),
            completion(isNot(contains(varName))));
      });

      test("uses the environment parameter", () {
        var varName = uid();
        expect(
            _getSubprocessEnvironment(
                environment: {varName: "value"},
                includeParentEnvironment: false),
            completion(containsPair(varName, "value")));
      });
    });
  });

  group("output", () {
    test("returns the script's output without a trailing newline", () {
      expect(
          mainScript("print('hello!');").output, completion(equals("hello!")));
    });

    test("completes with a ScriptException if the script fails", () {
      expect(mainScript("print('hello!'); exitCode = 12;").output,
          throwsScriptException(12));
    });
  });

  group("lines", () {
    test("returns the script's stdout lines", () {
      expect(mainScript(r"print('hello\nthere!');").lines,
          emitsInOrder(["hello", "there!", emitsDone]));
    });

    test("emits a ScriptException if the script fails", () {
      expect(mainScript("print('hello!'); exitCode = 12;").lines,
          emitsThrough(emitsError(isScriptException(12))));
    });
  });
}

/// Defines tests for either stdout or for stderr.
void stdoutOrStderr(String name, Stream<List<int>> stream(Script script)) {
  group(name, () {
    test("forwards $name from the subprocess and closes", () {
      expect(stream(mainScript("$name.writeln('Hello!');")).lines,
          emitsInOrder(["Hello!", emitsDone]));
    });

    test("closes after emitting nothing", () {
      expect(stream(mainScript("")).lines, emitsDone);
    });

    test("closes for a script that fails to start", () {
      // Run in a capture block to ignore extra stderr from the process failing
      // to start.
      Script.capture((_) {
        var script = Script("non-existent-executable");
        expect(script.done, throwsA(anything));
        expect(stream(script), emitsThrough(emitsDone));
      }).stderr.drain<void>();
    });

    test("emits non-text values", () {
      // Try emitting null bytes and invalid UTF8 sequences to make sure
      // nothing's forcing this to be interpreted as text.
      expect(stream(mainScript("$name.add([0, 0, 0xC3, 0x28]);")),
          emits([0, 0, 0xC3, 0x28]));
    });

    test("can't be listened after a macrotask has elapsed", () async {
      var script = mainScript("");
      expect(script.done, completes);
      await pumpEventQueue();

      // We can't use expect(..., throwsStateError) here bceause of
      // dart-lang/sdk#45815.
      runZonedGuarded(() => stream(script).listen(null),
          expectAsync2((error, stackTrace) => expect(error, isStateError)));
    });
  });
}

/// Runs a Dart subprocess and returns the value of `Process.environment` in
/// that subprocess.
Future<Map<String, String>> _getSubprocessEnvironment(
        {Map<String, String>? environment,
        bool includeParentEnvironment = true}) async =>
    (json.decode(await mainScript(
                "stdout.writeln(json.encode(Platform.environment));",
                environment: environment,
                includeParentEnvironment: includeParentEnvironment)
            .stdout
            .text) as Map)
        .cast<String, String>();
