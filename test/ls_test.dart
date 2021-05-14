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

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'package:cli_script/cli_script.dart';

void main() {
  group("ls()", () {
    test("lists files that match the glob", () async {
      await d.file("foo.txt").create();
      await d.file("bar.txt").create();
      await d.file("baz.zip").create();

      expect(
          ls("*.txt", root: d.sandbox),
          emitsInOrder([
            emitsInAnyOrder(["foo.txt", "bar.txt"]),
            emitsDone
          ]));
    });

    test("an absolute glob expands to absolute paths", () async {
      await d.file("foo.txt").create();
      await d.file("bar.txt").create();
      await d.file("baz.zip").create();

      expect(
          ls(p.join(Glob.quote(d.sandbox), "*.txt"), root: d.sandbox),
          emitsInOrder([
            emitsInAnyOrder([d.path("foo.txt"), d.path("bar.txt")]),
            emitsDone
          ]));
    });
  });
}
