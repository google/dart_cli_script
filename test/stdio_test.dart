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

import 'dart:async';

import 'package:test/test.dart';

import 'package:cli_script/cli_script.dart';

import 'util.dart';

void main() {
  group("silenceStdout() suppresses stdout from", () {
    group("scripts", () {
      test("started synchronously", () {
        expect(
            Script.capture((_) {
              silenceStdout(() => mainScript("print('howdy!');"));
            }).stdout,
            emitsDone);
      });

      test("started asynchronously", () {
        expect(
            Script.capture((_) {
              silenceStdout(() =>
                  scheduleMicrotask(() => mainScript("print('howdy!');")));
            }).stdout,
            emitsDone);
      });
    });

    group("print", () {
      test("synchronously", () {
        expect(
            Script.capture((_) {
              silenceStdout(() => print("howdy!"));
            }).stdout,
            emitsDone);
      });

      test("asynchronously", () {
        expect(
            Script.capture((_) {
              silenceStdout(() => scheduleMicrotask(() => print('howdy!')));
            }).stdout,
            emitsDone);
      });
    });

    group("currentStdout", () {
      test("synchronously", () {
        expect(
            Script.capture((_) {
              silenceStdout(() => currentStdout.writeln("howdy!"));
            }).stdout,
            emitsDone);
      });

      test("asynchronously", () {
        expect(
            Script.capture((_) {
              silenceStdout(() =>
                  scheduleMicrotask(() => currentStdout.writeln('howdy!')));
            }).stdout,
            emitsDone);
      });
    });
  });

  group("silenceStderr() suppresses stderr from", () {
    group("scripts", () {
      test("started synchronously", () {
        expect(
            Script.capture((_) {
              silenceStderr(() => mainScript("stderr.writeln('howdy!');"));
            }).stderr,
            emitsDone);
      });

      test("started asynchronously", () {
        expect(
            Script.capture((_) {
              silenceStderr(() => scheduleMicrotask(
                  () => mainScript("stderr.writeln('howdy!');")));
            }).stderr,
            emitsDone);
      });
    });

    group("currentStderr", () {
      test("synchronously", () {
        expect(
            Script.capture((_) {
              silenceStderr(() => currentStderr.writeln("howdy!"));
            }).stderr,
            emitsDone);
      });

      test("asynchronously", () {
        expect(
            Script.capture((_) {
              silenceStderr(() =>
                  scheduleMicrotask(() => currentStderr.writeln('howdy!')));
            }).stderr,
            emitsDone);
      });
    });
  });

  group("silenceOutput() suppresses output from", () {
    group("scripts", () {
      test("started synchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() => mainScript("""
                print('howdy!');
                stderr.writeln('howdy!');
              """));
            }).combineOutput(),
            emitsDone);
      });

      test("started asynchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() => scheduleMicrotask(() => mainScript("""
                print('howdy!');
                stderr.writeln('howdy!');
              """)));
            }).combineOutput(),
            emitsDone);
      });
    });

    group("print", () {
      test("synchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() => print("howdy!"));
            }).combineOutput(),
            emitsDone);
      });

      test("asynchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() => scheduleMicrotask(() => print('howdy!')));
            }).combineOutput(),
            emitsDone);
      });
    });

    group("currentStdout", () {
      test("synchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() => currentStdout.writeln("howdy!"));
            }).combineOutput(),
            emitsDone);
      });

      test("asynchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() =>
                  scheduleMicrotask(() => currentStdout.writeln('howdy!')));
            }).combineOutput(),
            emitsDone);
      });
    });

    group("currentStderr", () {
      test("synchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() => currentStderr.writeln("howdy!"));
            }).combineOutput(),
            emitsDone);
      });

      test("asynchronously", () {
        expect(
            Script.capture((_) {
              silenceOutput(() =>
                  scheduleMicrotask(() => currentStderr.writeln('howdy!')));
            }).combineOutput(),
            emitsDone);
      });
    });
  });

  group("silenceUntilFailure()", () {
    group("suppresses output from", () {
      group("scripts", () {
        test("started synchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure((_) => mainScript("""
                  print('howdy!');
                  stderr.writeln('howdy!');
                """));
              }).combineOutput(),
              emitsDone);
        });

        test("started asynchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure(
                    (_) => scheduleMicrotask(() => mainScript("""
                      print('howdy!');
                      stderr.writeln('howdy!');
                    """)));
              }).combineOutput(),
              emitsDone);
        });
      });

      group("print", () {
        test("synchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure((_) => print("howdy!"));
              }).combineOutput(),
              emitsDone);
        });

        test("asynchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure(
                    (_) => scheduleMicrotask(() => print('howdy!')));
              }).combineOutput(),
              emitsDone);
        });
      });

      group("currentStdout", () {
        test("synchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure((_) => currentStdout.writeln("howdy!"));
              }).combineOutput(),
              emitsDone);
        });

        test("asynchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure((_) =>
                    scheduleMicrotask(() => currentStdout.writeln('howdy!')));
              }).combineOutput(),
              emitsDone);
        });
      });

      group("currentStderr", () {
        test("synchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure((_) => currentStderr.writeln("howdy!"));
              }).combineOutput(),
              emitsDone);
        });

        test("asynchronously", () {
          expect(
              Script.capture((_) {
                silenceUntilFailure((_) =>
                    scheduleMicrotask(() => currentStderr.writeln('howdy!')));
              }).combineOutput(),
              emitsDone);
        });
      });
    });

    group("releases stdio when the callback fails", () {
      test("synchronously", () {
        var script = Script.capture((_) {
          silenceUntilFailure((_) {
            print("howdy!");
            throw 'oh no';
          });
        });
        expect(script.done, throwsScriptException(257));
        expect(script.stdout.text, completion(equals('howdy!')));
        expect(script.stderr.text, completion(contains('oh no')));
      });

      test("asynchronously", () {
        var script = Script.capture((_) {
          silenceUntilFailure((_) async {
            print("howdy!");
            await mainScript("throw 'oh no';").done;
          });
        });
        expect(script.done, throwsScriptException(255));
        expect(script.stdout.text, completion(equals('howdy!')));
        expect(script.stderr.text, completion(contains('oh no')));
      });
    });
  });
}
