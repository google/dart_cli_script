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

/// An exception indicating that a [Script] failed.
class ScriptException implements Exception {
  /// The human-readable name of the script that failed.
  final String scriptName;

  /// The exit code produced by the failing script.
  final int exitCode;

  ScriptException(this.scriptName, this.exitCode) {
    if (exitCode == 0) {
      throw RangeError.value(exitCode, "exitCode", "May not be 0");
    }
  }

  String toString() => "$scriptName failed with exit code $exitCode.";
}
