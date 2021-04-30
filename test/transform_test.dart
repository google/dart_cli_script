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
}
