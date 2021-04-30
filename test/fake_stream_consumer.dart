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

/// A [StreamConsumer] whose implementation just comes from a callback.
class FakeStreamConsumer<T> implements StreamConsumer<T> {
  final Future<void> Function(Stream<T> stream) _implementation;

  FakeStreamConsumer(this._implementation);

  Future<void> addStream(Stream<T> stream) => _implementation(stream);

  Future<void> close() => Future.value();
}
