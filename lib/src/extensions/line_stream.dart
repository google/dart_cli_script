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

import '../script.dart';
import 'byte_stream.dart';

/// Extensions on [Stream<String>] that treat it as a stream of discrete lines
/// (as commonly emitted by a shell script).
extension LineStreamExtensions on Stream<String> {
  /// Converts this to a byte stream with newlines baked in.
  Stream<List<int>> get bytes => map((line) => utf8.encode("$line\n"));

  /// Pipes [this] into [script]'s [stdin] with newlines baked in.
  ///
  /// This works like [Script.pipe], treating this stream as a process that
  /// emits only stdout. If [this] emits an error, it's treated the same as an
  /// unhandled Dart error in a [Script.capture] block: it's printed to stderr
  /// and the virtual stream process exits with error code 256.
  Script operator |(Script script) => bytes | script;

  /// Shorthand for `stream.bytes.pipe`.
  Future<void> operator >(StreamConsumer<List<int>> consumer) =>
      bytes.pipe(consumer);
}
