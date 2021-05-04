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

// Tests for constructors that wrap other objects as [Script]s.
void main() {
  group("Script.fromByteTransformer()", () {
    test("converts data from stdin", () {
      var script = Script.fromByteTransformer(zlib.decoder);
      script.stdin.add(zlib.encode(utf8.encode("hello!\n")));
      expect(script.stdout.lines, emits("hello!"));
    });

    test("exits when stdin closes", () {
      var script = Script.fromByteTransformer(zlib.decoder);
      script.stdin.close();
      expect(script.stdout, emitsDone);
      expect(script.done, completes);
    });

    test("surfaces an error as a Script error", () {
      var script = Script.fromByteTransformer(
          StreamTransformer.fromHandlers(handleData: (_, sink) {
        sink.addError("oh no!");
      }));
      script.stdin.add([1, 2, 3]);
      expect(script.stderr.lines, emitsThrough(contains("oh no!")));
      expect(script.exitCode, completion(equals(256)));
    });
  });

  group("Script.fromStringTransformer()", () {
    var transformer = StreamTransformer<String, String>.fromBind((stream) =>
        stream.map(
            (string) => String.fromCharCodes(string.runes.toList().reversed)));

    test("converts data from stdin", () {
      var script = Script.fromLineTransformer(transformer);
      script.stdin.writeln("hello!");
      expect(script.stdout.lines, emits("!olleh"));
    });

    test("exits when stdin closes", () {
      var script = Script.fromLineTransformer(transformer);
      script.stdin.close();
      expect(script.stdout, emitsDone);
      expect(script.done, completes);
    });

    test("surfaces an error as a Script error", () {
      var script = Script.fromByteTransformer(
          StreamTransformer.fromHandlers(handleData: (_, sink) {
        sink.addError("oh no!");
      }));
      script.stdin.writeln("hello!");
      expect(script.stderr.lines, emitsThrough(contains("oh no!")));
      expect(script.exitCode, completion(equals(256)));
    });
  });
}
