/// Liveness of the daemon's CDC event stream.
///
/// A phone loses this connection constantly, and a stale timeline is
/// indistinguishable from a working agent unless the UI can say which it is.
enum EventStreamStatus { connecting, connected, reconnecting }
