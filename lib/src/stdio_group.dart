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
import 'dart:io';

import 'package:async/async.dart';

/// A wrapper over a [StreamGroup] that collects stdout or stderr streams and
/// also provides an additional sink that can be used to manually add emit data
/// to stdout/stderr.
class StdioGroup {
  /// The inner stream group that handles all the heavy lifting of merging
  /// streams.
  final _group = StreamGroup<List<int>>();

  /// The sink for manually adding additional output.
  final IOSink sink;

  /// See [StreamGroup.stream].
  Stream<List<int>> get stream => _group.stream;

  /// The controller for [sink].
  final StreamController<List<int>> _sinkController;

  StdioGroup() : this._(StreamController());

  StdioGroup._(this._sinkController) : sink = IOSink(_sinkController.sink) {
    _group.add(_sinkController.stream);
  }

  /// See [StreamGroup.add].
  Future<void>? add(Stream<List<int>> stream) => _group.add(stream);

  /// See [StreamGroup.close].
  Future<void> close() {
    sink.close();
    return _group.close();
  }
}
