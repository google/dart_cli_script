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
import 'package:test/test.dart';

import 'package:cli_script/src/util/entangled_controllers.dart';

void main() {
  late StreamController<Object> controller1;
  late StreamController<Object> controller2;
  setUp(() {
    var tuple = createEntangledControllers<Object>();
    controller1 = tuple.item1;
    controller2 = tuple.item2;
  });

  group("with no events buffered", () {
    group("both streams emit no events", () {
      test("when listened in the same microtask", () {
        controller1.stream.listen(expectAsync1((_) {}, count: 0),
            onError: expectAsync2((_, __) {}, count: 0),
            onDone: expectAsync0(() {}, count: 0));
        controller2.stream.listen(expectAsync1((_) {}, count: 0),
            onError: expectAsync2((_, __) {}, count: 0),
            onDone: expectAsync0(() {}, count: 0));
      });

      test("when listened in separate microtasks", () async {
        controller1.stream.listen(expectAsync1((_) {}, count: 0),
            onError: expectAsync2((_, __) {}, count: 0),
            onDone: expectAsync0(() {}, count: 0));
        await Future<void>.value();
        controller2.stream.listen(expectAsync1((_) {}, count: 0),
            onError: expectAsync2((_, __) {}, count: 0),
            onDone: expectAsync0(() {}, count: 0));
      });

      test("when listened in distant microtasks", () async {
        controller1.stream.listen(expectAsync1((_) {}, count: 0),
            onError: expectAsync2((_, __) {}, count: 0),
            onDone: expectAsync0(() {}, count: 0));
        await pumpEventQueue();
        controller2.stream.listen(expectAsync1((_) {}, count: 0),
            onError: expectAsync2((_, __) {}, count: 0),
            onDone: expectAsync0(() {}, count: 0));
      });
    });

    group("both streams emit further events synchronously", () {
      late _CollectedEvents events1;
      late _CollectedEvents events2;
      tearDown(() {
        controller1.add("foo");
        expect(events1.value(0), equals("foo"));
        controller1.addError("oh no");
        expect(events1.error(1), equals("oh no"));

        controller2.add("bar");
        expect(events2.value(0), equals("bar"));
        expect(events2.done, isFalse);
        controller2.close();
        expect(events2.done, isTrue);

        expect(events1.done, isFalse);
        controller1.close();
        expect(events1.done, isTrue);
      });

      test("when listened in the same microtask", () {
        events1 = _collectEvents(controller1);
        events2 = _collectEvents(controller2);
      });

      test("when listened in a different microtask", () async {
        events1 = _collectEvents(controller1);
        await Future<void>.value();
        events2 = _collectEvents(controller2);
      });

      test("when listened in a distant microtask", () async {
        events1 = _collectEvents(controller1);
        await pumpEventQueue();
        events2 = _collectEvents(controller2);
      });
    });
  });

  group("with events buffered", () {
    setUp(() {
      controller1.add("1:1");
      controller1.add("1:2");
      controller2.add("2:1");
      controller2.add("2:2");
      controller1.add("1:3");
      controller2.add("2:3");
      controller2.addError("2:4");
      controller1.add("1:4");
    });

    group("when both controllers are listened simultaneously", () {
      test("events are emitted in order", () async {
        var events = _collectEventsFromBoth(controller1, controller2);

        // Events shouldn't be emitted synchronously on listen.
        expect(events.events, isEmpty);

        await pumpEventQueue();
        expect(events.events, hasLength(8));
        expect(events.value(0), equals("1:1"));
        expect(events.value(1), equals("1:2"));
        expect(events.value(2), equals("2:1"));
        expect(events.value(3), equals("2:2"));
        expect(events.value(4), equals("1:3"));
        expect(events.value(5), equals("2:3"));
        expect(events.error(6), equals("2:4"));
        expect(events.value(7), equals("1:4"));
      });

      // This matches the buffer-flushing behavior of the `dart:async`
      // [StreamController] implementation.
      test("one event is emitted per microtask", () async {
        var events = _collectEventsFromBoth(controller1, controller2);

        for (var i = 0; i < 9; i++) {
          expect(events.events, hasLength(i));
          await Future<void>.value();
        }
      });

      test("events added during flushing are also flushed as microtasks",
          () async {
        var events = _collectEventsFromBoth(controller1, controller2);

        for (var i = 0; i < 4; i++) {
          controller1.add("extra $i");
          await Future<void>.value();
        }

        for (var i = 4; i < 13; i++) {
          expect(events.events, hasLength(i));
          await Future<void>.value();
        }

        expect(events.events, hasLength(12));
        expect(events.value(8), equals("extra 0"));
        expect(events.value(9), equals("extra 1"));
        expect(events.value(10), equals("extra 2"));
        expect(events.value(11), equals("extra 3"));
      });

      test("both streams emit further events synchronously", () async {
        var events1 = _collectEvents(controller1);
        var events2 = _collectEvents(controller2);
        await pumpEventQueue();

        controller1.add("foo");
        expect(events1.value(4), equals("foo"));
        controller1.addError("oh no");
        expect(events1.error(5), equals("oh no"));

        controller2.add("bar");
        expect(events2.value(4), equals("bar"));
        expect(events2.done, isFalse);
        controller2.close();
        expect(events2.done, isTrue);

        expect(events1.done, isFalse);
        controller1.close();
        expect(events1.done, isTrue);
      });
    });

    group("when one controller is listened in a separate microtask", () {
      test("both controllers emit the right events", () async {
        var events1 = _collectEvents(controller1);
        await Future<void>.value();
        var events2 = _collectEvents(controller2);

        await pumpEventQueue();
        expect(events1.events, hasLength(4));
        expect(events1.value(0), equals("1:1"));
        expect(events1.value(1), equals("1:2"));
        expect(events1.value(2), equals("1:3"));
        expect(events1.value(3), equals("1:4"));

        expect(events1.events, hasLength(4));
        expect(events2.value(0), equals("2:1"));
        expect(events2.value(1), equals("2:2"));
        expect(events2.value(2), equals("2:3"));
        expect(events2.error(3), equals("2:4"));
      });

      test(
          "new events for the second controller are buffered until it's listened",
          () async {
        _collectEvents(controller1);
        controller2.add("2:5");
        await Future<void>.value();
        var events2 = _collectEvents(controller2);

        await pumpEventQueue();
        expect(events2.value(4), equals("2:5"));
      });
    });

    group("when one controller is listened in a distant microtask", () {
      test("both controllers emit the right events", () async {
        var events1 = _collectEvents(controller1);
        await pumpEventQueue();
        expect(events1.events, hasLength(4));
        expect(events1.value(0), equals("1:1"));
        expect(events1.value(1), equals("1:2"));
        expect(events1.value(2), equals("1:3"));
        expect(events1.value(3), equals("1:4"));

        var events2 = _collectEvents(controller2);
        await pumpEventQueue();
        expect(events1.events, hasLength(4));
        expect(events2.value(0), equals("2:1"));
        expect(events2.value(1), equals("2:2"));
        expect(events2.value(2), equals("2:3"));
        expect(events2.error(3), equals("2:4"));
      });

      test(
          "new events for the second controller are buffered until it's listened",
          () async {
        _collectEvents(controller1);
        controller2.add("2:5");
        await pumpEventQueue();
        var events2 = _collectEvents(controller2);

        await pumpEventQueue();
        expect(events2.value(4), equals("2:5"));
      });
    });
  });
}

/// The events collected by [collectEvents].
class _CollectedEvents {
  final events = <Result<Object>>[];
  var done = false;

  /// Asserts that the event at [index] is a data event and returns its value.
  Object value(int index) => events[index].asValue!.value;

  /// Asserts that the event at [index] is an error event and returns its value.
  Object error(int index) => events[index].asError!.error;
}

/// Returns an object that's updated with events emitted by [controller]'s
/// stream as it emits them.
_CollectedEvents _collectEvents(StreamController<Object> controller) {
  var events = _CollectedEvents();
  _collectEventsInto(controller, events);
  return events;
}

/// Returns an object that's updated with events emitted by both [controller1]'s
/// and [controller2]'s streams.
_CollectedEvents _collectEventsFromBoth(StreamController<Object> controller1,
    StreamController<Object> controller2) {
  var events = _CollectedEvents();
  _collectEventsInto(controller1, events);
  _collectEventsInto(controller2, events);
  return events;
}

/// Listens to [controller]'s stream and adds all events it emits to [events].
void _collectEventsInto(
    StreamController<Object> controller, _CollectedEvents events) {
  controller.stream.listen((value) => events.events.add(Result.value(value)),
      onError: (Object error, StackTrace stackTrace) =>
          events.events.add(Result.error(error, stackTrace)),
      onDone: () => events.done = true);
}
