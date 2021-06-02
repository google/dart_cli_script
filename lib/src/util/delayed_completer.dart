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

import 'package:async/async.dart';
import 'package:meta/meta.dart';

/// A completer that doesn't actually dispatch the completion event until
/// [ready] is called.
@sealed
class DelayedCompleter<T> implements Completer<T> {
  /// Whether [ready] has been called.
  bool get isReady => _ready;
  var _ready = false;

  /// The result with which to complete [_inner] once [ready] is called.
  ///
  /// This is [null] before this has been completed yet and after [ready] has
  /// been called.
  FutureOr<Result<T>>? _result;

  /// The inner completer that actually dispatches the event.
  final Completer<T> _inner;

  bool get isCompleted => _completed;
  var _completed = false;

  Future<T> get future => _inner.future;

  DelayedCompleter() : _inner = Completer<T>();

  /// Like [Completer.sync].
  DelayedCompleter.sync() : _inner = Completer<T>.sync();

  void complete([FutureOr<T>? value]) {
    if (_completed) {
      throw StateError("DelayedCompleter has already been completed.");
    }
    _completed = true;

    if (_ready) {
      _inner.complete(value);
    } else if (value is Future<T>) {
      _result = Result.capture(value);
    } else {
      _result = Result.value(value as T);
    }
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completed) {
      throw StateError("DelayedCompleter has already been completed.");
    }
    _completed = true;

    if (_ready) {
      _inner.completeError(error, stackTrace);
    } else {
      _result = Result.error(error, stackTrace);
    }
  }

  /// Indicates that the completer is allowed to dispatch the completion event.
  ///
  /// If this has already been completed, it will cause [future] to complete at
  /// some point in the near future. Otherwise, it will cause any upcoming call
  /// to [complete] or [completeError] to complete the future once they're
  /// called.
  ///
  /// This may be called multiple times. Any calls after the first will be
  /// ignored.
  void ready() {
    if (_ready) return;

    var result = _result;
    _result = null;
    _ready = true;

    if (result is Future<Result<T>>) {
      _inner.complete(Result.release(result));
    } else if (result != null) {
      result.complete(_inner);
    }
  }
}
