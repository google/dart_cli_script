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
import 'dart:io';

import 'package:async/async.dart';

/// A wrapper over a [StreamGroup] that collects stdout or stderr streams.
///
/// This also provides an additional [sink] that can be used to manually emit
/// data to stdout/stderr, as well as a [writeln] method that can be used for
/// the same purpose but is unaffected by [sink] being closed or locked by
/// [Sink.addStream].
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

  StdioGroup() : this._(StreamController(sync: true));

  StdioGroup._(this._sinkController)
      : sink = _StdioGroupSink(_sinkController.sink) {
    _group.add(_sinkController.stream);
  }

  /// See [StreamGroup.add].
  Future<void>? add(Stream<List<int>> stream) => _group.add(stream);

  /// Writes [object] to [stream] like [IOSink.writeln].
  ///
  /// This can be called even if [sink] is closed or locked by [Sink.addStream].
  void writeln([Object? object = ""]) => _sinkController
    ..add(sink.encoding.encode(object.toString()))
    ..add(sink.encoding.encode("\n"));

  /// See [StreamGroup.close].
  Future<void> close() {
    _sinkController.close();
    return _group.close();
  }
}

/// A custom [IOSink] that doesn't actually close the underlying sink when it's
/// closed.
class _StdioGroupSink extends IOSinkBase implements IOSink {
  /// The underlying sink.
  final StreamSink<List<int>> _sink;

  Encoding encoding = utf8;

  _StdioGroupSink(this._sink);

  void onAdd(List<int> data) => _sink.add(data);

  void onError(Object error, [StackTrace? stackTrace]) =>
      _sink.addError(error, stackTrace);

  void onClose() {}

  /// All writes are flushed automatically as soon as the stream is listened.
  Future<void> onFlush() => Future.value();
}
