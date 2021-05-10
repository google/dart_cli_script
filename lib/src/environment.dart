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

import 'package:collection/collection.dart';

/// The default environment for subprocesses spawned by [Platform.environment].
///
/// This is a copy of [Platform.environment], except it's modifiable so that
/// scripts can export variables for use in multiple subprocesses.
///
/// On Windows, environment keys are canonicalized to upper-case, since
/// environment variables are case-insensitive.
Map<String, String> get env {
  var environment = Zone.current[#_environment];
  return environment is Map<String, String> ? environment : _defaultEnvironment;
}

/// The default value of [env], outside any zones that might set it differently.
final _defaultEnvironment = _newMap()..addAll(Platform.environment);

/// Runs [callback] in a zone with its own environment variables.
///
/// Any modifications to environment variables within [callback] won't affect
/// the outer environment.
///
/// By default, [environment] is merged with [env]. Any `null` values will
/// remove the corresponding keys from the parent [env]. If
/// [includeParentEnvironment] is `false`, [environment] is used as the *entire*
/// child environment instead.
T withEnv<T>(T callback(), Map<String, String?> environment,
    {bool includeParentEnvironment = true}) {
  var newEnvironment = _newMap();
  if (includeParentEnvironment) newEnvironment.addAll(env);

  for (var entry in environment.entries) {
    var value = entry.value;
    if (value == null) {
      newEnvironment.remove(entry.key);
    } else {
      newEnvironment[entry.key] = value;
    }
  }

  return runZoned(callback, zoneValues: {#_environment: newEnvironment});
}

/// Create a new map, case-insensitively on Windows.
Map<String, String> _newMap() => Platform.isWindows
    ? CanonicalizedMap<String, String, String>((key) => key.toUpperCase())
    : {};
