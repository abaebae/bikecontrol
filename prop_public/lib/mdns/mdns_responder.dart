//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation is an in-process mDNS responder with pinned
// multicast egress and a query log it folds repeated identical queries
// into (by entry identity, bumping [MdnsQueryLogEntry.count] in place).
// This stub keeps the log-entry surface the app's diagnostics, privacy
// filter and network self-test read.

/// One observed mDNS query (possibly folded across repeats).
///
/// Identity matters: the responder folds a repeat by mutating the SAME
/// entry (`count++`) and re-appending it at the tail of the log, so
/// consumers must correlate entries by instance, never by list position.
class MdnsQueryLogEntry {
  final DateTime at;

  /// Dotted-quad source address of the querier.
  final String source;
  final int sourcePort;

  /// Whether the querier requested a unicast (QU) reply.
  final bool wantsUnicast;

  /// Question names in wire order, e.g. `PTR _wahoo-fitness-tnp._tcp.local`.
  final List<String> questions;
  final bool answeredUnicast;
  final bool answeredMulticast;

  /// How many identical queries this entry has folded so far. Starts at 1.
  int count;

  /// How the query was answered, for diagnostics: `unicast`, `multicast`,
  /// `unicast+multicast`, or `no answer`.
  String get reply {
    if (answeredUnicast && answeredMulticast) return 'unicast+multicast';
    if (answeredUnicast) return 'unicast';
    if (answeredMulticast) return 'multicast';
    return 'no answer';
  }

  MdnsQueryLogEntry({
    required this.at,
    required this.source,
    required this.sourcePort,
    required this.wantsUnicast,
    required this.questions,
    required this.answeredUnicast,
    required this.answeredMulticast,
    this.count = 1,
  });
}
