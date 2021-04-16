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

import 'package:async/async.dart';
import 'package:charcode/charcode.dart';

/// Extensions on [Stream<List<int>>] that make it easier to consume the output
/// of scripts in a human-friendly, easily-to-manipulate manner.
extension ByteStreamExtensions on Stream<List<int>> {
  /// Returns the full UTF-8 text produced by [this], with trailing newlines removed.
  Future<String> get text async {
    var text = const Utf8Decoder(allowMalformed: true)
        .convert(await collectBytes(this));

    var i = text.length - 1;
    while (i >= 0 && text.codeUnitAt(i) == $lf) {
      i--;
    }

    return text.substring(0, i + 1);
  }

  /// Returns a stream of UTF-8 lines emitted by this process.
  Stream<String> get lines =>
      transform(utf8.decoder).transform(const LineSplitter());
}
