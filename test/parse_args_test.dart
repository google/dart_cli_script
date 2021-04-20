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

import 'package:test/test.dart';

import 'package:cli_script/src/parse_args.dart';

void main() {
  group("parsing", () {
    group("throws an error", () {
      test("for an empty string", () {
        expect(() => parseArgs(""), throwsFormatException);
      });

      test("for a string containing only spaces", () {
        expect(() => parseArgs("   "), throwsFormatException);
      });
    });

    group("a single argument", () {
      group("without quotes containing", () {
        test("normal text", () {
          expect(parseArgs("foo"), equals(["foo"]));
        });

        test("text surrounded by spaces", () {
          expect(parseArgs("  foo    "), equals(["foo"]));
        });

        test("an escaped backslash", () {
          expect(parseArgs(r"\\"), equals(["\\"]));
        });

        test("an escaped single quote", () {
          expect(parseArgs(r"\'"), equals(["'"]));
        });

        test("an escaped double quote", () {
          expect(parseArgs(r'\"'), equals(['"']));
        });

        test("an escaped normal letter", () {
          expect(parseArgs(r'\a'), equals(['a']));
        });
      });

      group("with double quotes containing", () {
        test("nothing", () {
          expect(parseArgs('""'), equals([""]));
        });

        test("spaces", () {
          expect(parseArgs('" foo bar "'), equals([" foo bar "]));
        });

        test("a single quote", () {
          expect(parseArgs('"\'"'), equals(["'"]));
        });

        test("an escaped double quote", () {
          expect(parseArgs(r'"\""'), equals(['"']));
        });

        test("an escaped backslash", () {
          expect(parseArgs(r'"\\"'), equals(["\\"]));
        });
      });

      group("with single quotes containing", () {
        test("nothing", () {
          expect(parseArgs("''"), equals([""]));
        });

        test("spaces", () {
          expect(parseArgs("' foo bar '"), equals([" foo bar "]));
        });

        test("a double quote", () {
          expect(parseArgs("'\"'"), equals(['"']));
        });

        test("an escaped single quote", () {
          expect(parseArgs(r"'\''"), equals(["'"]));
        });

        test("an escaped backslash", () {
          expect(parseArgs(r"'\\'"), equals(["\\"]));
        });
      });

      test("with plain text adjacent to quotes", () {
        expect(parseArgs("\"foo bar\"baz'bip bop'"),
            equals(["foo barbazbip bop"]));
      });
    });

    group("multiple arguments", () {
      test("separated by single spaces", () {
        expect(parseArgs("a b c d"), equals(["a", "b", "c", "d"]));
      });

      test("separated by multiple spaces", () {
        expect(parseArgs("a  b   c    d  "), equals(["a", "b", "c", "d"]));
      });

      test("with different quoting styles", () {
        expect(parseArgs("a \"b c\" 'd e' f\\ g"),
            equals(["a", "b c", "d e", "f g"]));
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

      test("characters between normal text", () {
        expect(arg("foo bar: 'baz'"), equals(r"foo\ bar:\ \'baz\'"));
      });
    });
  });
}
