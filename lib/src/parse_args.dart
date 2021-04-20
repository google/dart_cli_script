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

import 'package:charcode/charcode.dart';
import 'package:string_scanner/string_scanner.dart';

/// Parses [argString], a shell-style string of space-separated arguments, into a
/// list of separate arguments.
List<String> parseArgs(String argString) {
  var scanner = StringScanner(argString);

  _consumeSpaces(scanner);

  var args = <String>[];
  while (!scanner.isDone) {
    args.add(_scanArg(scanner));
    _consumeSpaces(scanner);
  }

  if (args.isEmpty) scanner.error("Expected at least one argument.");
  return args;
}

/// Consumes zero or more spaces.
void _consumeSpaces(StringScanner scanner) {
  while (scanner.scanChar($space)) {}
}

/// Scans a single argument and returns its value.
String _scanArg(StringScanner scanner) {
  var buffer = StringBuffer();
  while (true) {
    var next = scanner.peekChar();
    if (next == $space || next == null) {
      return buffer.toString();
    } else if (next == $double_quote || next == $single_quote) {
      scanner.readChar();
      buffer.write(_scanUntil(scanner, next));
      scanner.readChar();
    } else if (next == $backslash) {
      scanner.readChar();
      buffer.writeCharCode(scanner.readChar());
    } else {
      buffer.writeCharCode(scanner.readChar());
    }
  }
}

/// Scans text until the scanner reaches [endChar].
///
/// Does not consume [endChar]. Throws a [FormatException] if the string ends
/// before an [endChar] is found.
String _scanUntil(StringScanner scanner, int endChar) {
  var buffer = StringBuffer();
  while (true) {
    var next = scanner.peekChar();
    if (next == null) {
      scanner.expectChar(endChar);
    } else if (next == endChar) {
      return buffer.toString();
    } else if (next == $backslash) {
      scanner.readChar();
      buffer.writeCharCode(scanner.readChar());
    } else {
      buffer.writeCharCode(scanner.readChar());
    }
  }
}

/// Converts [argument] to a string and escapes it so it's parsed as a single
/// argument by [parseArgs].
///
/// For example, `run("cp -r ${arg(source)} build/")`.
String arg(Object argument) {
  var string = argument.toString();
  if (string.isEmpty) return '""';

  var buffer = StringBuffer();
  for (var i = 0; i < string.length; i++) {
    var codeUnit = string.codeUnitAt(i);
    if (codeUnit == $space ||
        codeUnit == $double_quote ||
        codeUnit == $single_quote ||
        codeUnit == $backslash) {
      buffer.writeCharCode($backslash);
    }
    buffer.writeCharCode(codeUnit);
  }
  return buffer.toString();
}
