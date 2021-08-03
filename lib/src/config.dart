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

import 'package:stack_trace/stack_trace.dart';

/// The packages whose stack frames should be folded by [terseChain].
const _packagesToFold = {
  'cli_script',
  'async',
  'collection',
  'glob',
  'path',
  'string_scanner'
};

/// Returns whether debug mode is currently active.
bool get inDebugMode => Zone.current[#_debug] == true;

/// Prints [message] directly to stderr if debug mode is active.
void debug(String message) {
  if (!inDebugMode) return;
  stderr.writeln(message);
}

/// Folds irrelevant frames of [chain] together, unless we're in verbose trace
/// mode.
Chain terseChain(Chain chain) => Zone.current[#_verboseTrace] == true
    ? chain
    : chain.foldFrames((frame) => _packagesToFold.contains(frame.package),
        terse: true);

/// Runs [callback] with the given configuration values set.
///
/// If [verboseTrace] is `true`, full stack traces will be printed for
/// exceptions. If [debug] is `true`, extra information will be printed.
T withConfig<T>(T callback(),
        {bool verboseTrace = false, bool debug = false}) =>
    runZoned(callback,
        zoneValues: {#_debug: debug, #_verboseTrace: verboseTrace});
