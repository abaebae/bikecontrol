//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation is a standards-compliant Cycling Speed and Cadence
// (0x2A5B) parser shared by the BLE sensor source and the emulated cadence
// peripheral. This stub keeps the public surface — parse, build, the
// cadence delta helpers and the shared crank-counter advance scheme — with
// behaviour pinned by the repo's own tests.

/// A parsed CSC Measurement (0x2A5B) notification.
///
/// Flags bit 0 selects the wheel revolution fields, bit 1 the crank
/// revolution fields; absent fields are null. A frame that declares more
/// data than it carries is malformed and rejected by [parse].
class CscMeasurement {
  final int? wheelRevolutions;
  final int? wheelEventTime2048;
  final int? crankRevolutions;

  /// Cumulative crank event time in 1/1024 s units.
  final int? crankEventTime1024;

  const CscMeasurement({
    this.wheelRevolutions,
    this.wheelEventTime2048,
    this.crankRevolutions,
    this.crankEventTime1024,
  });

  /// Parses a raw notification. Returns `null` for a malformed or truncated
  /// frame rather than guessing.
  static CscMeasurement? parse(List<int> bytes) {
    if (bytes.isEmpty) return null;
    final flags = bytes[0];
    var offset = 1;

    int? wheelRevolutions;
    int? wheelEventTime2048;
    if (flags & 0x01 != 0) {
      if (bytes.length < offset + 6) return null;
      wheelRevolutions =
          bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) | (bytes[offset + 3] << 24);
      wheelEventTime2048 = bytes[offset + 4] | (bytes[offset + 5] << 8);
      offset += 6;
    }

    int? crankRevolutions;
    int? crankEventTime1024;
    if (flags & 0x02 != 0) {
      if (bytes.length < offset + 4) return null;
      crankRevolutions = bytes[offset] | (bytes[offset + 1] << 8);
      crankEventTime1024 = bytes[offset + 2] | (bytes[offset + 3] << 8);
    }

    return CscMeasurement(
      wheelRevolutions: wheelRevolutions,
      wheelEventTime2048: wheelEventTime2048,
      crankRevolutions: crankRevolutions,
      crankEventTime1024: crankEventTime1024,
    );
  }
}

/// Builds a crank-only CSC Measurement frame — the form the emulated
/// cadence sensor notifies.
List<int> buildCscMeasurement(int crankRevs, int eventTime1024) => [
  0x02,
  crankRevs & 0xFF,
  (crankRevs >> 8) & 0xFF,
  eventTime1024 & 0xFF,
  (eventTime1024 >> 8) & 0xFF,
];

/// Cadence (rpm) between two crank samples, or `null` when it cannot be
/// computed: either sample lacks crank data, or the event time did not
/// advance. Both counters are 16-bit and wrap; the deltas mask accordingly.
int? cscCadenceRpm(CscMeasurement prev, CscMeasurement cur) => _crankCadenceRpm(
  prevRevs: prev.crankRevolutions,
  prevTime: prev.crankEventTime1024,
  curRevs: cur.crankRevolutions,
  curTime: cur.crankEventTime1024,
);

int? _crankCadenceRpm({int? prevRevs, int? prevTime, int? curRevs, int? curTime}) {
  if (prevRevs == null || prevTime == null || curRevs == null || curTime == null) return null;
  final dRevs = (curRevs - prevRevs) & 0xFFFF;
  final dTime = (curTime - prevTime) & 0xFFFF;
  if (dTime == 0) return null;
  return (dRevs * 61440 / dTime).round();
}

/// Advances a cumulative crank counter so two consecutive frames decode back
/// to exactly [rpm] via [cscCadenceRpm]: one fixed 60 s quantum of event
/// time per revolution-count step, so the delta is always integral and
/// wrap-safe within the 16-bit counters.
({int crankRevs, int eventTime1024}) advanceCrankCounter({
  required int crankRevs,
  required int eventTime1024,
  required int rpm,
}) {
  return (
    crankRevs: (crankRevs + rpm) & 0xFFFF,
    eventTime1024: (eventTime1024 + 61440) & 0xFFFF,
  );
}
