import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cli_script/cli_script.dart';
import 'package:test/test.dart';

import 'util.dart';

void main() {
  group('on Script', () {
    test('interrupts with default signal', () async {
      var script = mainScript('while (true) {}');
      await pumpEventQueue();

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(-15));
    });

    test('interrupts before process starts', () async {
      var script = mainScript('throw Exception("oh no!");');

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(-15));
    });

    test('interrupts with custom signal', () async {
      var script = mainScript('while (true) {}');
      await pumpEventQueue();

      expect(script.kill(ProcessSignal.sigint), true);
      expect(script.done, throwsScriptException(-2));
    });

    test('can interrupt after Future.timeout', () async {
      var script = mainScript('while (true) {}');
      await pumpEventQueue();

      script.done.timeout(Duration(milliseconds: 1), onTimeout: script.kill);

      expect(script.done, throwsScriptException(-15));
    });

    test("can't be interrupt after it already exited", () async {
      var script = mainScript('print("done!");');

      expect(await script.output, 'done!');
      expect(script.kill(), false);
    });

    test('can be trapped without interrupting', () async {
      var completer = Completer<void>();
      var script = _watchSignalsAndExit(completer);
      var output = script.output;

      expect(script.kill(), true);

      completer.complete();
      expect(await output, 'SIGTERM\nbye!');
      expect(script.kill(), false);
    });
  });

  group('on Script.capture', () {
    test('does not interrupt by default', () async {
      var completer = Completer<void>();
      var script = Script.capture((_) async {
        await completer.future;
        print('done!');
      });
      var output = script.output;

      expect(script.kill(), false);

      completer.complete();
      expect(await output, 'done!');
      expect(script.kill(), false);
    });

    test('can capture Script.kill signals', () async {
      var completer = Completer<void>();
      var script = _watchSignalsAndExit(completer);
      var output = script.output;

      expect(script.kill(), true);

      completer.complete();
      expect(await output, 'SIGTERM\nbye!');
      expect(script.kill(), false);
    });

    test('prints from signal handler', () async {
      var completer = Completer<void>();
      var script = Script.capture((_) async => await completer.future,
          onSignal: (signal) {
        print('stdout: $signal');
        currentStderr.writeln('stderr: $signal');
        return true;
      });
      var lines = script.combineOutput().lines;

      expect(script.kill(), true);

      completer.complete();
      expect(await lines.toList(), ['stdout: SIGTERM', 'stderr: SIGTERM']);
      expect(script.kill(), false);
    });

    test('does not call signal handler after script exited', () async {
      var completer = Completer<void>();
      var killCalls = 0;
      var script = Script.capture((_) async => await completer.future,
          onSignal: (signal) {
        killCalls++;
        return true;
      });

      expect(script.kill(), true);

      completer.complete();
      await pumpEventQueue();

      expect(script.kill(), false);
      expect(killCalls, 1);
    });

    test('catches script error from signal handler', () async {
      var completer = Completer<void>();
      var script = Script.capture((_) async => await completer.future,
          onSignal: (signal) => throw ScriptException('onSignal', 42));

      expect(script.kill(), false);

      completer.complete();
      expect(script.done, throwsScriptException(42));
      expect(script.kill(), false);
    });

    test('catches exception from signal handler', () async {
      var completer = Completer<void>();
      var script = Script.capture((_) async => await completer.future,
          onSignal: (signal) => throw Exception('oh no!'));

      expect(script.kill(), false);

      completer.complete();
      expect(script.done, throwsScriptException(257));
      expect(script.kill(), false);
    });
  });

  test('BufferedScript.capture can capture Script.kill signals', () async {
    var completer = Completer<void>();
    var signalStream = StreamController<ProcessSignal>();
    var script = BufferedScript.capture((_) async {
      signalStream.stream.listen(print);
      await completer.future;
      await signalStream.close();
      print('bye!');
    }, onSignal: (signal) {
      signalStream.sink.add(signal);
      return true;
    });

    var done = false;
    var output = script.output.then((v) {
      done = true;
      return v;
    });

    expect(script.kill(), true);

    completer.complete();
    expect(done, false);

    await script.release();
    expect(await output, 'SIGTERM\nbye!');
    expect(script.kill(), false);
  });

  test('interrupts a Script.fromLineTransformer', () async {
    var script = Script.fromLineTransformer(StreamTransformer.fromHandlers(
      handleData: (data, sink) => sink.add(data.toUpperCase()),
    ));

    var events = <String>[];
    var done = false;
    script.stdout.lines.listen(events.add, onDone: () => done = true);

    script.stdin.writeln('before');
    await pumpEventQueue();

    expect(script.kill(), true);
    expect(script.done, throwsScriptException(143));

    await pumpEventQueue();

    expect(done, true);
    expect(events, ['BEFORE']);
    expect(script.kill(), false);
  });

  group('on a ByteStream pipe', () {
    test('interrupts pipe', () async {
      var controller = StreamController<List<int>>();
      var completer = Completer<void>();
      var script = controller.stream | _watchSignalsAndStdin(completer);
      var lines = script.stdout.lines;

      controller.sink.add(utf8.encode('before'));
      await pumpEventQueue();

      expect(script.kill(), true);
      await pumpEventQueue();

      controller.sink.add(utf8.encode('after'));
      await pumpEventQueue();

      expect(script.kill(), true);
      await pumpEventQueue();

      completer.complete();
      expect(script.done, throwsScriptException(143));
      expect(await lines.toList(), [
        'from a: before',
        'b: SIGTERM',
        'b: bye!',
      ]);

      expect(script.kill(), false);
    });

    test('cancels underlying stream', () async {
      var controller = StreamController<String>();
      var completer = Completer<void>();
      var script = controller.stream |
          Script.capture((_) async => await completer.future);
      var canceled = false;
      controller.onCancel = () => canceled = true;
      var done = script.done;

      expect(script.kill(), true);
      await pumpEventQueue();

      completer.complete();
      expect(done, throwsScriptException(143));
      expect(canceled, true);
    });
  });

  group('on LineStream.xargs', () {
    test('interrupts without maxArgs', () async {
      var controller = StreamController<String>();
      var script = controller.stream.xargs(print);
      var lines = script.stdout.text;

      controller.sink.add('before');
      await pumpEventQueue();

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(143));

      controller.sink.add('after');
      await pumpEventQueue();

      expect(script.kill(), false);
      expect(await lines, '');
    });

    test('interrupts with maxArgs', () async {
      var controller = StreamController<String>();
      var script = controller.stream.xargs(print, maxArgs: 2);
      var lines = script.stdout.text;

      controller.sink.add('a');
      controller.sink.add('b');
      controller.sink.add('c');
      await pumpEventQueue();

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(143));

      controller.sink.add('d');
      await pumpEventQueue();

      expect(script.kill(), false);
      expect(await lines, '[a, b]');
    });

    test('can capture Script.kill signals', () async {
      var signalCompleter = Completer<ProcessSignal>();
      var controller = StreamController<String>();
      var script =
          controller.stream.xargs(print, onSignal: signalCompleter.complete);

      expect(script.kill(), true);
      expect(await signalCompleter.future, ProcessSignal.sigterm);
      expect(script.done, throwsScriptException(143));
    });

    test('cancels underlying stream', () async {
      var controller = StreamController<String>();
      var script = controller.stream.xargs(print);
      var canceled = false;
      controller.onCancel = () => canceled = true;

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(143));
      expect(canceled, true);
    });
  });

  group('on xargs from stdin', () {
    test('interrupts without maxArgs', () async {
      var completer = Completer<void>();
      var script = Script.capture((_) async {
            print('before');
            await completer.future;
            print('after');
          }) |
          xargs(print, maxArgs: 2);
      var lines = script.stdout.text;

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(143));

      completer.complete();
      await pumpEventQueue();

      expect(script.kill(), false);
      expect(await lines, '');
    });

    test('interrupts with maxArgs', () async {
      var completer = Completer<void>();
      var script = Script.capture((_) async {
            print('a\nb\nc');
            await completer.future;
            print('d');
          }) |
          xargs(print, maxArgs: 2);
      var lines = script.stdout.text;
      await pumpEventQueue();

      expect(script.kill(), true);
      expect(script.done, throwsScriptException(143));

      completer.complete();
      await pumpEventQueue();

      expect(script.kill(), false);
      expect(await lines, '[a, b]');
    });

    test('can capture Script.kill signals', () async {
      var signalCompleter = Completer<ProcessSignal>();
      var script = Script.capture((_) async => await signalCompleter.future) |
          xargs(print, onSignal: signalCompleter.complete);

      expect(script.kill(), true);
      expect(await signalCompleter.future, ProcessSignal.sigterm);
      expect(script.done, throwsScriptException(143));
    });
  });

  test('on silenceUntilFailure can capture Script.kill signals', () async {
    var signalStream = StreamController<ProcessSignal>();
    var completer = Completer<void>();
    var script = silenceUntilFailure((_) async {
      signalStream.stream.listen(print);
      await completer.future;
      await signalStream.close();
      throw ScriptException('testerino', 1);
    }, onSignal: (signal) {
      signalStream.sink.add(signal);
      return true;
    });
    var stderr = script.stderr.text;
    var stdout = script.stdout.text;

    expect(script.kill(), true);
    expect(script.done, throwsScriptException(1));

    completer.complete();
    expect(await stdout, 'SIGTERM');
    expect(await stderr, '');

    expect(script.kill(), false);
  });

  test("sends signal to script currently running in a pipe chain", () async {
    var completer1 = Completer<void>();
    var completer2 = Completer<void>();
    var pipeline =
        _watchSignalsAndExit(completer1) | _watchSignalsAndStdin(completer2);
    var lines = pipeline.lines;

    expect(pipeline.kill(), true);
    await pumpEventQueue();

    completer1.complete();
    await pumpEventQueue();

    expect(pipeline.kill(), true);
    await pumpEventQueue();

    completer2.complete();
    expect(await lines.toList(), [
      'from a: SIGTERM',
      'from a: bye!',
      'b: SIGTERM',
      'b: bye!',
    ]);

    await pipeline.done;
    expect(pipeline.kill(), false);
  });
}

Script _watchSignalsAndExit(Completer<void> completer) {
  var signalStream = StreamController<ProcessSignal>();
  return Script.capture((_) async {
    signalStream.stream.listen(print);
    await completer.future;
    await signalStream.close();
    print('bye!');
  }, onSignal: (signal) {
    signalStream.sink.add(signal);
    return true;
  });
}

Script _watchSignalsAndStdin(Completer<void> completer) {
  var signalStream = StreamController<ProcessSignal>();
  return Script.capture((stdin) async {
    signalStream.stream.listen((event) {
      print('b: $event');
    });
    await for (var line in stdin.lines) {
      print('from a: $line');
    }
    await completer.future;
    print('b: bye!');
    await signalStream.close();
  }, onSignal: (signal) {
    signalStream.sink.add(signal);
    return true;
  });
}
