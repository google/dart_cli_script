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

import 'package:async/async.dart';
import 'package:test/test.dart';

import 'package:cli_script/src/util/delayed_completer.dart';

void main() {
  late DelayedCompleter<String> completer;
  setUp(() => completer = DelayedCompleter());

  group("when the completer is completed and then ready() is called", () {
    Result<String>? result;
    setUp(() {
      result = null;
      completer.future.then((value) {
        result = Result.value(value);
      }).onError((error, stackTrace) {
        result = Result.error(error!, stackTrace);
      });
    });

    test("completes with a value", () async {
      expect(completer.isCompleted, isFalse);
      completer.complete("foo");
      expect(completer.isCompleted, isTrue);
      await pumpEventQueue();
      expect(result, isNull);

      expect(completer.isReady, isFalse);
      expect(completer.isReady, isFalse);
      completer.ready();
      expect(completer.isReady, isTrue);
      expect(completer.isReady, isTrue);
      await pumpEventQueue();
      expect(result!.asValue!.value, equals("foo"));
    });

    test("completes with an error", () async {
      expect(completer.isCompleted, isFalse);
      completer.completeError("oh no");
      expect(completer.isCompleted, isTrue);
      await pumpEventQueue();
      expect(result, isNull);

      expect(completer.isReady, isFalse);
      completer.ready();
      expect(completer.isReady, isTrue);
      await pumpEventQueue();
      expect(result!.asError!.error, equals("oh no"));
    });

    test("completes with an asynchronous value", () async {
      expect(completer.isCompleted, isFalse);
      completer.complete(Future.value("foo"));
      expect(completer.isCompleted, isTrue);
      await pumpEventQueue();
      expect(result, isNull);

      expect(completer.isReady, isFalse);
      completer.ready();
      expect(completer.isReady, isTrue);
      await pumpEventQueue();
      expect(result!.asValue!.value, equals("foo"));
    });

    test("completes with an asynchronous error", () async {
      expect(completer.isCompleted, isFalse);
      completer.complete(Future.error("oh no"));
      expect(completer.isCompleted, isTrue);
      await pumpEventQueue();
      expect(result, isNull);

      expect(completer.isReady, isFalse);
      completer.ready();
      expect(completer.isReady, isTrue);
      await pumpEventQueue();
      expect(result!.asError!.error, equals("oh no"));
    });
  });

  group("when ready() is called and then the completer is completed", () {
    setUp(() {
      expect(completer.isReady, isFalse);
      completer.ready();
      expect(completer.isReady, isTrue);
    });

    test("completes with a value", () async {
      expect(completer.isCompleted, isFalse);
      completer.complete("foo");
      expect(completer.isCompleted, isTrue);
      expect(completer.future, completion(equals("foo")));
    });

    test("completes with an error", () async {
      expect(completer.isCompleted, isFalse);
      completer.completeError("oh no");
      expect(completer.isCompleted, isTrue);
      expect(completer.future, throwsA("oh no"));
    });

    test("completes with an asynchronous value", () async {
      expect(completer.isCompleted, isFalse);
      completer.complete(Future.value("foo"));
      expect(completer.isCompleted, isTrue);
      expect(completer.future, completion(equals("foo")));
    });

    test("completes with an asynchronous error", () async {
      expect(completer.isCompleted, isFalse);
      completer.complete(Future.error("oh no"));
      expect(completer.isCompleted, isTrue);
      expect(completer.future, throwsA("oh no"));
    });
  });
}
