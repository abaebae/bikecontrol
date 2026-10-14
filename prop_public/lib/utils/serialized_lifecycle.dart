//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation serialises start/stop lifecycles whose halves span
// several awaits, so callers may fire them without awaiting (see
// OpenBikeControlMdnsEmulator's usage). This stub keeps that public surface.

/// Serialises submitted tasks: each runs only after the previous one
/// completed (successfully or not), and callers get their own task's result
/// or error back.
class SerializedLifecycle {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) => task());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }
}
