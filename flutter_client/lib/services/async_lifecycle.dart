import 'dart:async';

/// Runs asynchronous operations one at a time, in the order they were
/// enqueued. An operation that throws does not block operations queued
/// behind it — the error only propagates to whoever awaited that specific
/// [run] call.
///
/// Used wherever a resource (a file, a remote subscription) must not see two
/// writes in flight at once, e.g. the on-disk store, the notification store,
/// and push-token register/unregister sequencing.
class SerialQueue {
  Future<void> _tail = Future<void>.value();

  /// Completes once every operation enqueued so far has settled, successful
  /// or not.
  Future<void> get drained => _tail;

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (_, _) {});
    return result;
  }
}

/// A monotonically increasing token for discarding stale async work.
///
/// Capture [current] before starting an operation; after each `await`,
/// compare it against [current] again — or call [isStale] — to check
/// whether [advance] has superseded it in the meantime, and bail out rather
/// than apply a result for a session/credential/attempt that no longer
/// applies.
class Generation {
  int _value = 0;

  int get current => _value;

  /// Invalidates any work captured against the previous value and returns
  /// the new one.
  int advance() => ++_value;

  bool isStale(int captured) => captured != _value;
}
