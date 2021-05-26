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

import 'package:cli_script/src/cli_arguments.dart';

void main() {
  group("parsing", () {
    group("throws an error", () {
      test("for an empty string", () {
        expect(() => CliArguments.parse(""), throwsFormatException);
      });

      test("for a string containing only spaces", () {
        expect(() => CliArguments.parse("   "), throwsFormatException);
      });

      onPosixOrWithGlobTrue((glob) {
        test("for a string containing an invalid glob", () {
          expect(() => CliArguments.parse("a [", glob: glob),
              throwsFormatException);
        });
      });
    });

    group("a single argument", () {
      group("without quotes containing", () {
        test("normal text", () async {
          expect(await _resolve("foo"), equals(["foo"]));
        });

        test("text surrounded by spaces", () async {
          expect(await _resolve("  foo    "), equals(["foo"]));
        });

        test("an escaped backslash", () async {
          expect(await _resolve(r"\\"), equals(["\\"]));
        });

        test("an escaped single quote", () async {
          expect(await _resolve(r"\'"), equals(["'"]));
        });

        test("an escaped double quote", () async {
          expect(await _resolve(r'\"'), equals(['"']));
        });

        test("an escaped normal letter", () async {
          expect(await _resolve(r'\a'), equals(['a']));
        });
      });

      group("with double quotes containing", () {
        test("nothing", () async {
          expect(await _resolve('""'), equals([""]));
        });

        test("spaces", () async {
          expect(await _resolve('" foo bar "'), equals([" foo bar "]));
        });

        test("a single quote", () async {
          expect(await _resolve('"\'"'), equals(["'"]));
        });

        test("an escaped double quote", () async {
          expect(await _resolve(r'"\""'), equals(['"']));
        });

        test("an escaped backslash", () async {
          expect(await _resolve(r'"\\"'), equals(["\\"]));
        });
      });

      group("with single quotes containing", () {
        test("nothing", () async {
          expect(await _resolve("''"), equals([""]));
        });

        test("spaces", () async {
          expect(await _resolve("' foo bar '"), equals([" foo bar "]));
        });

        test("a double quote", () async {
          expect(await _resolve("'\"'"), equals(['"']));
        });

        test("an escaped single quote", () async {
          expect(await _resolve(r"'\''"), equals(["'"]));
        });

        test("an escaped backslash", () async {
          expect(await _resolve(r"'\\'"), equals(["\\"]));
        });
      });

      test("with plain text adjacent to quotes", () async {
        expect(await _resolve("\"foo bar\"baz'bip bop'"),
            equals(["foo barbazbip bop"]));
      });

      onWindowsOrWithGlobFalse((glob) {
        test("that's an invalid glob", () async {
          expect(await _resolve("a [", glob: glob), equals(["a", "["]));
        });
      });
    });

    group("multiple arguments", () {
      test("separated by single spaces", () async {
        expect(await _resolve("a b c d"), equals(["a", "b", "c", "d"]));
      });

      test("separated by multiple spaces", () async {
        expect(await _resolve("a  b   c    d  "), equals(["a", "b", "c", "d"]));
      });

      test("with different quoting styles", () async {
        expect(await _resolve("a \"b c\" 'd e' f\\ g"),
            equals(["a", "b c", "d e", "f g"]));
      });
    });
  });

  group("globbing", () {
    onPosixOrWithGlobTrue((glob) {
      test("lists files that match the glob", () async {
        await d.file("foo.txt").create();
        await d.file("bar.txt").create();
        await d.file("baz.zip").create();

        var args = await _resolve("ls *.txt", glob: glob);
        expect(args.first, equals("ls"));
        expect(args.sublist(1), unorderedEquals(["foo.txt", "bar.txt"]));
      });

      test("an absolute glob expands to absolute paths", () async {
        await d.file("foo.txt").create();
        await d.file("bar.txt").create();
        await d.file("baz.zip").create();

        var pattern = p.join(Glob.quote(d.sandbox), "*.txt");
        var args = await _resolve("ls $pattern", glob: glob);
        expect(args.first, equals("ls"));
        expect(args.sublist(1),
            unorderedEquals([d.path("foo.txt"), d.path("bar.txt")]));
      });

      test("ignores glob characters in quotes", () async {
        await d.file("foo.txt").create();
        await d.file("bar.txt").create();
        await d.file("baz.zip").create();
        expect(
            await _resolve("ls '*.txt'", glob: glob), equals(["ls", "*.txt"]));
      });

      test("ignores backslash-escaped glob characters", () async {
        await d.file("foo.txt").create();
        await d.file("bar.txt").create();
        await d.file("baz.zip").create();
        expect(
            await _resolve(r"ls \*.txt", glob: glob), equals(["ls", "*.txt"]));
      });

      test("returns plain strings for globs that don't match", () async {
        expect(await _resolve("ls *.txt", glob: glob), equals(["ls", "*.txt"]));
      });
    });

    onWindowsOrWithGlobFalse((glob) {
      test("ignores glob characters", () async {
        await d.file("foo.txt").create();
        await d.file("bar.txt").create();
        await d.file("baz.zip").create();

        expect(await _resolve("ls *.txt", glob: glob), equals(["ls", "*.txt"]));
      });
    });
  });

  group("escaping", () {
    test("quotes an empty string", () {
      expect(arg(""), equals('""'));
    });

    test("passes through normal text", () {
      expect(arg("foo"), equals("foo"));
    });

    group("backslash-escapes", () {
      test("a space", () {
        expect(arg(" "), equals(r"\ "));
      });

      test("a double quote", () {
        expect(arg('"'), equals(r'\"'));
      });

      test("a single quote", () {
        expect(arg("'"), equals(r"\'"));
      });

      test("a backslash", () {
        expect(arg("\\"), equals(r"\\"));
      });

      test("an asterisk", () {
        expect(arg("*"), equals(r"\*"));
      });

      test("a question mark", () {
        expect(arg("?"), equals(r"\?"));
      });

      test("square brackets", () {
        expect(arg("[]"), equals(r"\[\]"));
      });

      test("curly brackets", () {
        expect(arg("{}"), equals(r"\{\}"));
      });

      test("parentheses", () {
        expect(arg("()"), equals(r"\(\)"));
      });

      test("a comma", () {
        expect(arg(","), equals(r"\,"));
      });

      test("characters between normal text", () {
        expect(arg("foo bar: 'baz'"), equals(r"foo\ bar:\ \'baz\'"));
      });
    });

    test("quotes multiple arguments", () {
      expect(args(["foo", " ", "", "*"]), equals(r'foo \  "" \*'));
    });
  });
}

/// Runs [callback] in two groups: one restricted to Windows with `glob: null`,
/// and one on all OSes with `glob: false`.
void onWindowsOrWithGlobFalse(void callback(bool? glob)) {
  group("on Windows", () => callback(null), testOn: "windows");
  group("with glob: false", () => callback(false));
}

/// Runs [callback] in two groups: one restricted to non-Windows OSes with
/// `glob: null`, and one on all OSes with `glob: true`.
void onPosixOrWithGlobTrue(void callback(bool? glob)) {
  group("on non-Windows OSes", () => callback(null), testOn: "!windows");
  group("with glob: true", () => callback(true));
}

Future<List<String>> _resolve(String executableAndArgs, {bool? glob}) async {
  var args = CliArguments.parse(executableAndArgs, glob: glob);
  return [args.executable, ...await args.arguments(root: d.sandbox)];
}
