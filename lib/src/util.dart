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

/// Stream extensions used internally within `cli_script`, not for public
/// consumption.
extension UtilStreamExtensions<T> on Stream<T> {
  /// Returns a transformation of [this] that runs [callback] immediately after
  /// [listen] is called.
  Stream<T> onListen(void callback()) {
    callback = Zone.current.bindCallbackGuarded(callback);
    return transform(StreamTransformer((stream, cancelOnError) {
      var subscription = stream.listen(null, cancelOnError: cancelOnError);
      callback();
      return subscription;
    }));
  }

  /// Returns a transformation of [this] that only emits error and done events,
  /// not data events.
  ///
  /// Because the returned stream doesn't emit data events, it can be used as a
  /// stream of any type.
  Stream<S> withoutData<S>() => where((_) => false).cast<S>();
}
