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
import 'dart:collection';

import 'package:async/async.dart';
import 'package:tuple/tuple.dart';

import 'dart:io';

/// Returns two stream controllers that are *entangled*, meaning that the
/// relative order in which they emit events is preserved even if their streams
/// are listened to after events have been buffered.
///
/// Order preservation is only guaranteed if the two streams are listened in the
/// same iteration of the event loop.
///
/// Note: these controllers are effectively synchronous, and so should only have
/// events added to them at the end of event loops.
Tuple2<StreamController<T>, StreamController<T>>
    createEntangledControllers<T>() {
  var buffer = _EntangledBuffer<T>();

  var controller1 = _EntangledController<T>(buffer, true);
  var controller2 = _EntangledController<T>(buffer, false);

  return Tuple2(controller1, controller2);
}

/// A buffer of events that have yet to be emitted to either controller.
///
/// This buffer only contains events before either controller has a listener.
/// Once either one is listened to, the controllers' internal buffers are used
/// instead.
class _EntangledBuffer<T> {
  /// The events that will be emitted once either controller gets a listener, or
  /// `null` if the events have already been pushed to the controllers.
  ///
  /// Each event is a tuple. The first value indicates which controller the
  /// event belongs to (`true` for [_controller1], `false` for [_controller2]).
  /// The second is the event itself: a [ValueResult] for a data event, an
  /// [ErrorResult] for an error event, and `null` for a close event.
  Queue<Tuple2<bool, Result<T>?>>? _events = Queue();

  /// The entangled controller that corresponds to events labeled `true`.
  ///
  /// The [StreamSink] methods on this controller should not be accessed outside
  /// of [_EntangledBuffer].
  final StreamController<T> controller1;

  /// The entangled controller that corresponds to events labeled `false`.
  ///
  /// The [StreamSink] methods on this controller should not be accessed outside
  /// of [_EntangledBuffer].
  final StreamController<T> controller2;

  _EntangledBuffer()
      : controller1 = StreamController(sync: true),
        controller2 = StreamController(sync: true) {
    controller1.onListen = _flush;
    controller2.onListen = _flush;
  }

  /// Starts flushing all events from [_events] to their respective controllers.
  void _flush() {
    // Remove both listeners so that the second controller that's listened
    // doesn't start a parallel [_scheduleNextEvent] stream. If it did that
    // wouldn't be a particularly big deal, since it would just be pulling from
    // the same queue, but it would make timing less predictable.
    controller1.onListen = null;
    controller2.onListen = null;

    if (_events!.isEmpty) {
      _events = null;
    } else {
      _scheduleNextEvent();
    }
  }

  /// Fires the next event in [_events].
  ///
  /// This matches the standard buffering behavior of synchronous
  /// [StreamController]s, where each buffered event is emitted in a separate
  /// microtask that's scheduled as the previous event is processed. This
  /// ensures that if an event handler throws an unhandled error, it's
  /// top-leveled immediately rather than having to wait until all the other
  /// buffered events are dispatched.
  void _scheduleNextEvent() {
    scheduleMicrotask(() {
      var events = _events;
      if (events == null) return;

      var event = events.removeFirst();

      // Once we've run out of events, null out the queue to indicate to [add],
      // [addError], and [close] that they can start forwarding events directly
      // to the controllers.
      if (events.isEmpty) _events = null;

      var controller = event.item1 ? controller1 : controller2;
      var result = event.item2;
      if (result == null) {
        controller.close();
      } else if (result is ValueResult<T>) {
        controller.add(result.value);
      } else if (result is ErrorResult) {
        controller.addError(result.error, result.stackTrace);
      }

      _scheduleNextEvent();
    });
  }

  /// Adds [value] as a data event for [controller1] if [forController1] is
  /// `true`, or [controller2] otherwise.
  void add(bool forController1, T value) {
    var events = _events;
    if (events != null) {
      events.add(Tuple2(forController1, Result.value(value)));
    } else {
      (forController1 ? controller1 : controller2).add(value);
    }
  }

  /// Adds [error] as an error event for [controller1] if [forController1] is
  /// `true`, or [controller2] otherwise.
  void addError(bool forController1, Object error, [StackTrace? stackTrace]) {
    var events = _events;
    if (events != null) {
      events.add(Tuple2(forController1, Result.error(error, stackTrace)));
    } else {
      (forController1 ? controller1 : controller2).addError(error, stackTrace);
    }
  }

  /// Adds a close event for [controller1] if [forController1] is `true`, or
  /// [controller2] otherwise.
  void close(bool forController1) {
    var events = _events;
    if (events != null) {
      events.add(Tuple2(forController1, null));
    } else {
      (forController1 ? controller1 : controller2).close();
    }
  }
}

/// A wrapper that pipes inputs to [_EntangledBuffer] and exposes output from
/// one of [_EntangledBuffer]'s controllers.
class _EntangledController<T> extends StreamSinkBase<T>
    implements StreamController<T> {
  /// The buffer that this wraps.
  final _EntangledBuffer<T> _buffer;

  /// Whether this is [_buffer.controller1] or [_buffer.controller2].
  final bool _isController1;

  StreamController<T> get _outputController =>
      _isController1 ? _buffer.controller1 : _buffer.controller2;

  Future<void> get done => _outputController.done;
  bool get hasListener => _outputController.hasListener;
  bool get isClosed => _outputController.isClosed;
  bool get isPaused => _outputController.isPaused;
  Stream<T> get stream => _outputController.stream;

  FutureOr<void> Function()? get onCancel => _outputController.onCancel;
  set onCancel(FutureOr<void> Function()? value) =>
      _outputController.onCancel = value;

  void Function()? get onListen => _outputController.onListen;
  set onListen(void Function()? value) =>
      throw UnsupportedError("Entangled controllers can't set onListen");

  void Function()? get onPause => _outputController.onPause;
  set onPause(void Function()? value) => _outputController.onPause = value;

  void Function()? get onResume => _outputController.onResume;
  set onResume(void Function()? value) => _outputController.onResume = value;

  StreamSink<T> get sink => this;

  _EntangledController(this._buffer, this._isController1);

  Future<void> addStream(Stream<T> stream, {bool? cancelOnError}) {
    if (cancelOnError == true) {
      stream = stream.transform(StreamTransformer(
          (stream, _) => stream.listen(null, cancelOnError: true)));
    }

    return super.addStream(stream);
  }

  void onAdd(T event) => _buffer.add(_isController1, event);

  void onError(Object error, [StackTrace? stackTrace]) =>
      _buffer.addError(_isController1, error, stackTrace);

  void onClose() => _buffer.close(_isController1);
}
