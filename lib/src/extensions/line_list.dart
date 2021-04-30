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

import '../script.dart';

/// Extensions on [List<String>] for piping it as input to a [Script].
extension LineListExtensions on List<String> {
  /// Pipes [this] into [script]'s [stdin] with newlines baked in.
  ///
  /// Returns [script].
  Script operator |(Script script) {
    for (var line in this) {
      script.stdin.writeln(line);
    }
    script.stdin.close();

    return script;
  }
}
