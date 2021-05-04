## Dart CLI Scripting

This package is designed to make it easy to write scripts that call out to
subprocesses with the ease of shell scripting and the power of Dart. It captures
the core virtues of shell scripting: terseness, pipelining, and composability.
At the same time, it uses standard Dart idioms like exceptions, `Stream`s, and
`Future`s, with a few extensions to make them extra easy to work with in a
scripting context.

* [Terseness](#terseness)
  * [The `Script` Class](#the-script-class)
  * [Do The Right Thing](#do-the-right-thing)
* [Pipelining](#pipelining)
* [Composability](#composability)
* [Dartiness](#dartiness)
* [Other Features](#other-features)
  * [Argument Parsing](#argument-parsing)
  * [Search and Replace](#search-and-replace)

While `cli_script` can be used as a library in any Dart application, its primary
goal is to support stand-alone scripts that serve the same purpose as shell
scripts. Because they're just normal Dart code, with static types and data
structures and the entire Dart ecosystem at your fingertips, these scripts will
be much more maintainable than their Shell counterparts without sacrificing ease
of use.

Here's an example of a simple Hello World script:

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    await run('echo "Hello, world!");
  });
}
```

(Note that [`wrapMain()`] isn't strictly necessary here, but it handles errors
much more nicely than Dart's built-in handling!)

[`wrapMain()`]: https://pub.dev/documentation/cli_script/latest/cli_script/wrapMain.html

Many programming environments have tried to make themselves suitable for shell
scripting, but in the end they all fall far short of the ease of calling out to
subprocesseses in Bash. As such, a principal design goal of `cli_script` is to
identify the core virtues that make shell scripting so appealing and reproduce
them as closely as possible in Dart:

### Terseness

Shell scripts make it very easy to write code that calls out to child processes
*tersely*, without needing to write a bunch of boilerplate. Running a child
process is as simple as calling [`run()`]:

[`run()`]: https://pub.dev/documentation/cli_script/latest/cli_script/run.html

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    await run("mkdir -p path/to/dir");
    await run("touch path/to/dir/foo");
  });
}
```

Similarly, it's easy to get the output of a command just like you would using
`"$(command)"` in a shell, using either [`output()`] to get a single string or
[`lines()`] to get a stream of lines:

[`output()`]: https://pub.dev/documentation/cli_script/latest/cli_script/output.html
[`lines()`]: https://pub.dev/documentation/cli_script/latest/cli_script/lines.html

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    await for (var file in lines("find . -type f -maxdepth 1")) {
      var contents = await output("cat", args: [file]);
      if (contents.contains("needle")) print(file);
    }
  });
}
```

You can also use [`check()`] to test whether a script returns exit code 0 or
not:

[`check()`]: https://pub.dev/documentation/cli_script/latest/cli_script/check.html

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    await for (var file in lines("find . -type f -maxdepth 1")) {
      if (await check("grep -q needle", args: [file])) print(file);
    }
  });
}
```

#### The `Script` Class

All of these top-level functions are just thin wrappers around the [`Script`]
class at the heart of `cli_script`. This class represents a subprocess (or
[something process-like](#composability)) and provides access to its [`stdin`],
[`stdout`], [`stderr`], and [`exitCode`].

[`Script`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script.html
[`stdin`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/stdin.html
[`stdout`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/stdout.html
[`stderr`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/stderr.html
[`exitCode`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/exitCode.html

Although `stdout` and `stderr` are just simple `Stream<List<int>>`s,
representing raw binary data, they're still easy to work with thanks to
`cli_script`'s [extension methods]. These make it easy to transform byte streams
into [line streams] or just [plain strings].

[extension methods]: https://pub.dev/documentation/cli_script/latest/cli_script/ByteStreamExtensions.html
[line streams]: https://pub.dev/documentation/cli_script/latest/cli_script/ByteStreamExtensions/lines.html
[plain strings]: https://pub.dev/documentation/cli_script/latest/cli_script/ByteStreamExtensions/text.html

#### Do The Right Thing

Terseness also means that you don't need any extra boilerplate to ensure that
the right thing happens when something goes wrong. In a shell script, if you
don't redirect a subprocess's output it will automatically print it for the user
to see, so you can automatically see any errors it prints. In `cli_script`, if
you don't listen to a `Script`'s [`stdout`] or [`stderr`] streams immediately
after creating it, they'll be redirected to the parent script's stdout or
stderr, respectively.

Similarly, in a shell script with `set -e` the script will abort as soon as a
child process fails unless that process is in an `if` statement or similar. In
`cli_script`, a `Script` will throw an exception if it exits with a failing exit
code unless the [`exitCode`] or [`success`] fields are accessed.

[`success`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/success.html

### Pipelining

In shell scripts, it's easy to hook multiple processes together in a pipeline
where each one passes its output to the next. `cli_script` supports this to,
using the [`|` operator]. This pipes all stdout from one script into another
script's stdin and returns a new script that encapsulates both. This new script
works just like a Bash pipeline with `set -o pipefail`: it forwards the last
script's stdout and stderr, but it'll fail if *any* script in the pipeline
fails.

[`|` operator]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/operator_bitwise_or.html

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    var pipeline = Script("find -name *.dart") |
        Script("xargs grep waitFor") |
        Script("wc -l");
    print("${await pipeline.stdout.text} instances of waitFor");
  });
}
```

Depending on how you're using a pipeline, you may find it more convenient to use
the [`Script.pipeline`] constructor. This works just like the `|` operator, it
just uses a different syntax.

[`Script.pipeline`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/pipeline.html

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    var count = await Script.pipeline([
      Script("find -name *.dart"),
      Script("xargs grep waitFor"),
      Script("wc -l")
    ]).stdout.text;
    print("$count instances of waitFor");
  });
}
```

You can even include certain `StreamTransformer`s in pipelines: those that
transform byte streams (`StreamTransformer<List<int>, List<int>>`) and those
that transform streams of lines (`StreamTransformer<String, String>`). These act
like scripts that transform their stdin into stdout according to the logic of
the transformer.

```dart
import 'dart:io';

import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    Script("cat data.gz") |
        zlib.decoder |
        Script("grep needle");
  });
}
```

In addition to piping scripts together, you can pipe the following types into
scripts:

* `Stream<List<int>>` (a stream of chunked binary data)
* `Stream<String>` (a stream of lines of text)
* `List<List<int>>` (chunked binary data)
* `List<int>` (a single binary blob)
* `List<String>` (lines of text)
* `String` (a single text blob)

This makes it easy to pass standard Dart data into process, such as files:

```dart
import 'dart:io';

import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    var pipeline = File("names.txt").openRead() |
        Script("grep Natalie") |
        Script("wc -l");
    print("There are ${await pipeline.stdout.text} Natalies");
  });
}
```

`Script`, `Stream<List<int>>`, and `Stream<String>` also support the `>`
operator as a shorthand for [`Stream.pipe()`]. This makes it easy to write the
output of a script or pipeline to a file on disk:

[`Stream.pipe()`]: https://api.dart.dev/stable/dart-async/Stream/pipe.html

```dart
import 'dart:io';

import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() {
    Script.capture((_) async {
      await for (var file in lines("find . -type f -maxdepth 1")) {
        var contents = await output("cat", args: [file]);
        if (contents.contains("needle")) print(file);
      }
    }) > File("needles.txt").openWrite();
  });
}
```

### Composability

In shell scripts, everything is a process. Obviously child processes are
processes, but functions also have input/output streams and exit codes so that
they work like processes to. You can even group a block of code into a virtual
process using `{}`!

In `cli_script`, anything can be a `Script`. The most common way to make a
script that's not a subprocess is using [`Script.capture()`]. This factory
constructor runs a block of code and captures all stdout and stderr produced by
child scripts (or calls to `print()`) into that `Script`'s [`stdout`] and
[`stderr`]:

[`Script.capture()`]: https://pub.dev/documentation/cli_script/latest/cli_script/Script/capture.html

```dart
import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    var script = Script.capture((_) async {
      await run("find . -type f -maxdepth 1");
      print("subdir/extra-file");
    });

    await for (var file in script.stdout.lines) {
      if (await check("grep -q needle", args: [file])) print(file);
    }
  });
}
```

If an exception is thrown within `Script.capture()`, including by a child
process returning an unhandled non-zero exit code, the entire capture block will
fail—but it'll fail like a process: by printing error messages to its stderr and
emitting a non-zero exit code that can be handled like any other `Script`'s.

`Script.capture()` also provides access to the script's [`stdin`], as a stream
that's passed into the callback. The capture block can ignore this completely,
it can use it as input to a child process or, it can do really whatever it
wants!

### Other Features

#### Argument Parsing

*(This section describes how `cli_script` parses arguments that your script
passes into child processes. For parsing arguments passed into your script, we
recommend the [`args`] package)*

[`args`]: https://pub.dev/packages/args

All `cli_script` functions that spawn subprocesses accept arguments in the same
format: a string named `executableAndArgs` along with a named `List<String>`
parameter named `args`. This makes it easy to invoke simple commands with very
little boilerplate (`lines("find . -type f -name '*.dart'")`) *and* easy to pass
in dynamically-generated arguments without worrying whether they contain spaces
(`run("cp -r", args: [source, destination])`).

The `executableAndArgs` string is parsed as a space-separated string. Components
can also be surrounded by single quotes or double quotes, which will allow them
to contain spaces, as in `run("git commit -m 'A commit message'")`. Characters
can also be escaped with `\`. The best way to make sure the backslash isn't just
consumed by Dart itself is to use a [raw string], as in
`run(r"git commit -m A\ commit\ message")`.

[raw string]: https://www.educative.io/edpresso/how-to-create-a-raw-string-in-dart

The arguments from `executableAndArgs` always come before the arguments in
`args`. You can also manually escape an argument for interpolation into
`executableAndArgs` using the [`arg()`] function, as in `run("cp -r
${arg(source)} build/")`.

[`run()`]: https://pub.dev/documentation/cli_script/latest/cli_script/run.html

#### Search and Replace

You can always continue to use `grep` and `sed` for your search-and-replace
needs, but `cli_script` has some useful functions to make that possible without
even bothering with a subprocess. The [`grep()`], [`replace()`], and
[`replaceMapped()`] functions return `StreamTransformer`s that can be used in
pipelines just like `Script`s:

[`grep()`]: https://pub.dev/documentation/cli_script/latest/cli_script/grep.html
[`replace()`]: https://pub.dev/documentation/cli_script/latest/cli_script/replace.html
[`replaceMapped()`]: https://pub.dev/documentation/cli_script/latest/cli_script/replaceMapped.html

```dart
import 'dart:io';

import 'package:cli_script/cli_script.dart';

void main() {
  wrapMain(() async {
    var pipeline = File("names.txt").openRead() |
        grep("Natalie") |
        Script("wc -l");
    print("There are ${await pipeline.stdout.text} Natalies");
  });
}
```

There are also corresponding [`Stream<String>.grep()`],
[`Stream<String>.replace()`], and [`Stream<String>.replaceMapped()`] extension
methods that make it easy to do these transformations on individual streams if
you need.

[`Stream<String>.grep()`]: https://pub.dev/documentation/cli_script/latest/cli_script/LineStreamExtensions/grep.html
[`Stream<String>.replace()`]: https://pub.dev/documentation/cli_script/latest/cli_script/LineStreamExtensions/replace.html
[`Stream<String>.replaceMapped()`]: https://pub.dev/documentation/cli_script/latest/cli_script/LineStreamExtensions/replaceMapped.html
