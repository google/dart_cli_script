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
import 'dart:math' as math;

import 'package:charcode/charcode.dart';
import 'package:path/path.dart' as p;

import 'util.dart';

/// The random number generator.
final _random = math.Random();

/// The number of characters to include in the random slug that ensures
/// uniqueness in termporary path names.
const _slugCharacters = 16;

/// Generates a unique temporary path name, passes it to [callback], and deletes
/// it after [callback] finishes.
///
/// This doesn't actually create anything at the path in question. It just
/// chooses a name that's extremely unlikely to conflict with an existing
/// entity, and deletes whatever's at that name after [callback] finishes.
///
/// The [callback] may return a [Future], in which case the path isn't deleted
/// until that [Future] completes. Whether or not [callback] returns a [Future],
/// this deletes the temporary path synchronously; use [withTempPathAsync] to
/// delete it asynchronously instead.
///
/// If [prefix] is passed, it's addded to the beginning of the temporary path's
/// basename. If [suffix] is passed, it's added to the end. If [parent] is
/// passed, it's used as the parent directory for the path; it defaults to
/// [Directory.systemTemp].
T withTempPath<T>(T callback(String path),
    {String? prefix, String? suffix, String? parent}) {
  var path = _tempPathName(prefix, suffix, parent);
  return tryFinally(() => callback(path), () {
    try {
      File(path).deleteSync(recursive: true);
    } on IOException {
      // Ignore cleanup errors. This is probably because the file was never
      // created in the first place.
    }
  });
}

/// Like [withTempPath], but deletes the temporary path asynchronously.
///
/// Note that even [withTempPath] can safely be used with an asynchronous
/// [callback]. This function is only necessary if you need the automatic
/// filesystem operations to be asynchronous.
Future<T> withTempPathAsync<T>(FutureOr<T> callback(String path),
    {String? prefix, String? suffix, String? parent}) async {
  var path = _tempPathName(prefix, suffix, parent);
  try {
    return await callback(path);
  } finally {
    try {
      await File(path).delete(recursive: true);
    } on IOException {
      // Ignore cleanup errors. This is probably because the file was never
      // created in the first place.
    }
  }
}

/// Creates a unique temporary directory, passes it to [callback] and deletes it
/// and its contents after [callback] finishes.
///
/// The [callback] may return a [Future], in which case the path isn't deleted
/// until that [Future] completes. Whether or not [callback] returns a [Future],
/// this creates and deletes the temporary directory synchronously; use
/// [withTempDirAsync] to delete it asynchronously instead.
///
/// If [prefix] is passed, it's addded to the beginning of the temporary
/// directory's basename. If [suffix] is passed, it's added to the end. If
/// [parent] is passed, the temporary directory is created within that path;
/// otherwise, it's created within [Directory.systemTemp].
T withTempDir<T>(T callback(String dir),
        {String? prefix, String? suffix, String? parent}) =>
    withTempPath((path) {
      Directory(path).createSync();
      return callback(path);
    }, prefix: prefix, suffix: suffix, parent: parent);

/// Like [withTempDir], but creates and deletes the temporary directory
/// asynchronously.
///
/// Note that even [withTempDir] can safely be used with an asynchronous
/// [callback]. This function is only necessary if you need the automatic
/// filesystem operations to be asynchronous.
Future<T> withTempDirAsync<T>(FutureOr<T> callback(String dir),
        {String? prefix, String? suffix, String? parent}) =>
    withTempPathAsync((path) async {
      await Directory(path).create();
      return await callback(path);
    }, prefix: prefix, suffix: suffix, parent: parent);

/// Returns the name of a temporary path within [parent] with the given [prefix]
/// and [suffix].
String _tempPathName(String? prefix, String? suffix, String? parent) {
  var slug = String.fromCharCodes(
      Iterable.generate(_slugCharacters, (_) => _randomAlphanumeric()));
  return p.join(parent ?? Directory.systemTemp.path,
      "${prefix ?? ''}$slug${suffix ?? ''}");
}

/// Returns a random alphanumeric character.
int _randomAlphanumeric() {
  // Don't generate uppercase letters on Windows since it's case-insensitive.
  var index = _random.nextInt(10 + 26 * (Platform.isWindows ? 1 : 2));
  if (index < 10) return $0 + index;
  if (index < 36) return index - 10 + $a;
  return index - 36 + $A;
}
