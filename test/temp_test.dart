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

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:test_descriptor/test_descriptor.dart' as d;

import 'package:cli_script/cli_script.dart';

void main() {
  group("withTempPath", () {
    test("runs the callback", () {
      withTempPath(expectAsync1((_) {}));
    });

    test("passes a path that doesn't exist", () {
      withTempPath((path) {
        expect(FileSystemEntity.typeSync(path),
            equals(FileSystemEntityType.notFound));
      });
    });

    test("passes different paths each time", () {
      withTempPath((path1) {
        withTempPath((path2) {
          withTempPath((path3) {
            expect(path1, isNot(equals(path2)));
            expect(path2, isNot(equals(path3)));
            expect(path3, isNot(equals(path1)));
          });
        });
      });
    });

    test("adds the prefix to the path", () {
      withTempPath((path) => expect(p.basename(path), startsWith("foo-")),
          prefix: "foo-");
    });

    test("adds the suffix to the path", () {
      withTempPath((path) => expect(path, endsWith(".txt")), suffix: ".txt");
    });

    test("puts the path in Directory.systemTemp by default", () {
      withTempPath((path) =>
          expect(p.isWithin(Directory.systemTemp.path, path), isTrue));
    });

    test("puts the path in parent", () {
      withTempPath((path) => expect(p.isWithin(d.sandbox, path), isTrue),
          parent: d.sandbox);
    });

    group("returns the callback's return value", () {
      test("synchronously", () {
        expect(withTempPath((_) => 123), equals(123));
      });

      test("asynchronously", () {
        expect(withTempPath((_) => Future.value(123)), completion(equals(123)));
      });
    });

    group("deletes the path afterwards", () {
      late String path;
      group("synchronously", () {
        test("if the callback ends successfully", () {
          withTempPath((path_) {
            path = path_;
            File(path).writeAsStringSync("hello!");
          });

          expect(FileSystemEntity.typeSync(path),
              equals(FileSystemEntityType.notFound));
        });

        test("if the callback throws", () {
          expect(() {
            withTempPath((path_) {
              path = path_;
              File(path).writeAsStringSync("hello!");
              throw "oh no";
            });
          }, throwsA("oh no"));

          expect(FileSystemEntity.typeSync(path),
              equals(FileSystemEntityType.notFound));
        });
      });

      group("asynchronously", () {
        test("if the callback ends successfully", () async {
          var completer = Completer<void>();
          var future = withTempPath((path_) {
            path = path_;
            File(path).writeAsStringSync("hello!");
            return completer.future;
          });

          expect(File(path).existsSync(), isTrue);

          completer.complete();
          await future;
          expect(FileSystemEntity.typeSync(path),
              equals(FileSystemEntityType.notFound));
        });

        test("if the callback throws", () async {
          var completer = Completer<void>();
          var future = withTempPath((path_) {
            path = path_;
            File(path).writeAsStringSync("hello!");
            return completer.future;
          });

          expect(File(path).existsSync(), isTrue);

          completer.completeError("oh no");
          await expectLater(future, throwsA("oh no"));
          expect(FileSystemEntity.typeSync(path),
              equals(FileSystemEntityType.notFound));
        });
      });
    });
  });

  group("withTempPathAsync", () {
    test("runs the callback", () async {
      await withTempPathAsync(expectAsync1((_) {}));
    });

    test("passes a path that doesn't exist", () async {
      await withTempPathAsync((path) {
        expect(FileSystemEntity.typeSync(path),
            equals(FileSystemEntityType.notFound));
      });
    });

    test("passes different paths each time", () async {
      await withTempPathAsync((path1) async {
        await withTempPathAsync((path2) async {
          await withTempPathAsync((path3) {
            expect(path1, isNot(equals(path2)));
            expect(path2, isNot(equals(path3)));
            expect(path3, isNot(equals(path1)));
          });
        });
      });
    });

    test("adds the prefix to the path", () async {
      await withTempPathAsync(
          (path) => expect(p.basename(path), startsWith("foo-")),
          prefix: "foo-");
    });

    test("adds the suffix to the path", () async {
      await withTempPathAsync((path) => expect(path, endsWith(".txt")),
          suffix: ".txt");
    });

    test("puts the path in Directory.systemTemp by default", () async {
      await withTempPathAsync((path) =>
          expect(p.isWithin(Directory.systemTemp.path, path), isTrue));
    });

    test("puts the path in parent", () async {
      await withTempPathAsync(
          (path) => expect(p.isWithin(d.sandbox, path), isTrue),
          parent: d.sandbox);
    });

    test("returns the callback's return value", () {
      expect(
          withTempPathAsync((_) => Future.value(123)), completion(equals(123)));
    });

    group("deletes the path afterwards", () {
      late String path;
      test("if the callback ends successfully", () async {
        var callbackStartedCompleter = Completer<void>();
        var callbackFinishedCompleter = Completer<void>();
        var future = withTempPathAsync((path_) {
          callbackStartedCompleter.complete();
          path = path_;
          File(path).writeAsStringSync("hello!");
          return callbackFinishedCompleter.future;
        });

        await callbackStartedCompleter.future;
        expect(File(path).existsSync(), isTrue);

        callbackFinishedCompleter.complete();
        await future;
        expect(FileSystemEntity.typeSync(path),
            equals(FileSystemEntityType.notFound));
      });

      test("if the callback throws", () async {
        var callbackStartedCompleter = Completer<void>();
        var callbackFinishedCompleter = Completer<void>();
        var future = withTempPathAsync((path_) {
          callbackStartedCompleter.complete();
          path = path_;
          File(path).writeAsStringSync("hello!");
          return callbackFinishedCompleter.future;
        });

        await callbackStartedCompleter.future;
        expect(File(path).existsSync(), isTrue);

        callbackFinishedCompleter.completeError("oh no");
        await expectLater(future, throwsA("oh no"));
        expect(FileSystemEntity.typeSync(path),
            equals(FileSystemEntityType.notFound));
      });
    });
  });

  group("withTempDir", () {
    test("runs the callback", () {
      withTempDir(expectAsync1((_) {}));
    });

    test("creates a directory at that location", () {
      withTempDir((dir) {
        expect(Directory(dir).existsSync(), isTrue);
      });
    });

    test("creates different directories each time", () {
      withTempDir((dir1) {
        withTempDir((dir2) {
          withTempDir((dir3) {
            expect(dir1, isNot(equals(dir2)));
            expect(dir2, isNot(equals(dir3)));
            expect(dir3, isNot(equals(dir1)));
          });
        });
      });
    });

    test("adds the prefix to the directory", () {
      withTempDir((dir) => expect(p.basename(dir), startsWith("foo-")),
          prefix: "foo-");
    });

    test("adds the suffix to the directory", () {
      withTempDir((dir) => expect(dir, endsWith(".txt")), suffix: ".txt");
    });

    test("puts the directory in Directory.systemTemp by default", () {
      withTempDir(
          (dir) => expect(p.isWithin(Directory.systemTemp.path, dir), isTrue));
    });

    test("puts the directory in parent", () {
      withTempDir((dir) => expect(p.isWithin(d.sandbox, dir), isTrue),
          parent: d.sandbox);
    });

    group("returns the callback's return value", () {
      test("synchronously", () {
        expect(withTempDir((_) => 123), equals(123));
      });

      test("asynchronously", () {
        expect(withTempDir((_) => Future.value(123)), completion(equals(123)));
      });
    });

    group("deletes the directory afterwards", () {
      late String dir;
      test("even if it has contents", () {
        withTempDir((dir_) {
          dir = dir_;
          File(p.join(dir, 'file.txt')).writeAsStringSync("hello!");
        });

        expect(Directory(dir).existsSync(), isFalse);
      });

      group("synchronously", () {
        test("if the callback ends successfully", () {
          withTempDir((dir_) => dir = dir_);
          expect(Directory(dir).existsSync(), isFalse);
        });

        test("if the callback throws", () {
          expect(() {
            withTempDir((dir_) {
              dir = dir_;
              throw "oh no";
            });
          }, throwsA("oh no"));

          expect(Directory(dir).existsSync(), isFalse);
        });
      });

      group("asynchronously", () {
        test("if the callback ends successfully", () async {
          var completer = Completer<void>();
          var future = withTempDir((dir_) {
            dir = dir_;
            return completer.future;
          });

          expect(Directory(dir).existsSync(), isTrue);

          completer.complete();
          await future;
          expect(Directory(dir).existsSync(), isFalse);
        });

        test("if the callback throws", () async {
          var completer = Completer<void>();
          var future = withTempDir((dir_) {
            dir = dir_;
            return completer.future;
          });

          expect(Directory(dir).existsSync(), isTrue);

          completer.completeError("oh no");
          await expectLater(future, throwsA("oh no"));
          expect(Directory(dir).existsSync(), isFalse);
        });
      });
    });
  });

  group("withTempDirAsync", () {
    test("runs the callback", () async {
      await withTempDirAsync(expectAsync1((_) {}));
    });

    test("creates a directory at that location", () async {
      await withTempDirAsync((dir) {
        expect(Directory(dir).existsSync(), isTrue);
      });
    });

    test("creates different directories each time", () async {
      await withTempDirAsync((dir1) async {
        await withTempDirAsync((dir2) async {
          await withTempDirAsync((dir3) {
            expect(dir1, isNot(equals(dir2)));
            expect(dir2, isNot(equals(dir3)));
            expect(dir3, isNot(equals(dir1)));
          });
        });
      });
    });

    test("adds the prefix to the directory", () async {
      await withTempDirAsync(
          (dir) => expect(p.basename(dir), startsWith("foo-")),
          prefix: "foo-");
    });

    test("adds the suffix to the directory", () async {
      await withTempDirAsync((dir) => expect(dir, endsWith(".txt")),
          suffix: ".txt");
    });

    test("puts the directory in Directory.systemTemp by default", () async {
      await withTempDirAsync(
          (dir) => expect(p.isWithin(Directory.systemTemp.path, dir), isTrue));
    });

    test("puts the directory in parent", () async {
      await withTempDirAsync(
          (dir) => expect(p.isWithin(d.sandbox, dir), isTrue),
          parent: d.sandbox);
    });

    test("returns the callback's return value", () {
      expect(
          withTempDirAsync((_) => Future.value(123)), completion(equals(123)));
    });

    group("deletes the directory afterwards", () {
      late String dir;
      test("even if it has contents", () async {
        await withTempDirAsync((dir_) {
          dir = dir_;
          File(p.join(dir, 'file.txt')).writeAsStringSync("hello!");
        });

        expect(Directory(dir).existsSync(), isFalse);
      });

      test("if the callback ends successfully", () async {
        var callbackStartedCompleter = Completer<void>();
        var callbackFinishedCompleter = Completer<void>();
        var future = withTempDirAsync((dir_) {
          callbackStartedCompleter.complete();
          dir = dir_;
          return callbackFinishedCompleter.future;
        });

        await callbackStartedCompleter.future;
        expect(Directory(dir).existsSync(), isTrue);

        callbackFinishedCompleter.complete();
        await future;
        expect(Directory(dir).existsSync(), isFalse);
      });

      test("if the callback throws", () async {
        var callbackStartedCompleter = Completer<void>();
        var callbackFinishedCompleter = Completer<void>();
        var future = withTempDirAsync((dir_) {
          callbackStartedCompleter.complete();
          dir = dir_;
          return callbackFinishedCompleter.future;
        });

        await callbackStartedCompleter.future;
        expect(Directory(dir).existsSync(), isTrue);

        callbackFinishedCompleter.completeError("oh no");
        await expectLater(future, throwsA("oh no"));
        expect(Directory(dir).existsSync(), isFalse);
      });
    });
  });
}
