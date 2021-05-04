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

import 'dart:io';

import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'package:cli_script/cli_script.dart';

var _scriptCount = 0;

/// Runs the Dart code [code] as a subprocess [Script].
Script dartScript(String code,
    {List<String>? args,
    String? name,
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true}) {
  var script = d.path("script_${_scriptCount++}.dart");
  File(script).writeAsString(code);

  return Script(arg(Platform.executable),
      args: [...Platform.executableArguments, script, ...?args],
      name: name,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: includeParentEnvironment);
}

/// A shorthand for [dartScript] that runs [code] in the body of an async
/// `main()` method with access to `dart:async`, `dart:convert`, and `dart:io`.
Script mainScript(String code,
        {List<String>? args,
        String? name,
        String? workingDirectory,
        Map<String, String>? environment,
        bool includeParentEnvironment = true}) =>
    dartScript("""
      import 'dart:async';
      import 'dart:convert';
      import 'dart:io';

      Future<void> main() async {
        $code
      }
    """);

/// Returns a matcher that verifies that the object is a [ScriptException] with
/// the given exit code.
Matcher isScriptException(int exitCode) => predicate((error) {
      expect(error, isA<ScriptException>());
      expect((error as ScriptException).exitCode, equals(exitCode));
      return true;
    });

/// Returns a matcher that verifies that the object throws a [ScriptException]
/// with the given exit code.
Matcher throwsScriptException(int exitCode) =>
    throwsA(isScriptException(exitCode));
