//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation is a standards-compliant Cycling Power Measurement
// (0x2A63) parser shared by the BLE sensor source and the emulated power
// peripheral. This stub keeps the public surface — parse, build and the
// cadence delta helper — with behaviour pinned by the repo's own tests.

/// A parsed Cycling Power Measurement (0x2A63) notification.
///
/// `powerWatts` is the instantaneous power (signed). The crank revolution
/// fields are present only when the frame declares them.
class CpsMeasurement {
  final int powerWatts;
  final int? crankRevolutions;

  /// Cumulative crank event time in 1/1024 s units.
  final int? crankEventTime1024;

  const CpsMeasurement({
    required this.powerWatts,
    this.crankRevolutions,
    this.crankEventTime1024,
  });

  /// Parses a raw notification. Returns `null` for a malformed or truncated
  /// frame rather than guessing.
  ///
  /// Field offsets follow the flags: an optional pedal-power-balance byte
  /// and accumulated-torque word precede the instantaneous power, and the
  /// crank revolution sub-field (flag `0x20`) follows it.
  static CpsMeasurement? parse(List<int> bytes) {
    if (bytes.length < 4) return null;
    final flags = bytes[0] | (bytes[1] << 8);
    var offset = 2;
    if (flags & 0x01 != 0) offset += 1; // pedal power balance
    if (flags & 0x02 != 0) offset += 2; // accumulated torque
    if (bytes.length < offset + 2) return null;

    var power = bytes[offset] | (bytes[offset + 1] << 8);
    if (power & 0x8000 != 0) power -= 0x10000; // sint16

    int? crankRevolutions;
    int? crankEventTime1024;
    if (flags & 0x20 != 0) {
      if (bytes.length < offset + 6) return null;
      crankRevolutions = bytes[offset + 2] | (bytes[offset + 3] << 8);
      crankEventTime1024 = bytes[offset + 4] | (bytes[offset + 5] << 8);
    }

    return CpsMeasurement(
      powerWatts: power,
      crankRevolutions: crankRevolutions,
      crankEventTime1024: crankEventTime1024,
    );
  }
}

/// Builds a Cycling Power Measurement frame — instantaneous power plus, when
/// crank data is given, the crank revolution sub-field.
List<int> buildCyclingPowerMeasurement(int watts, {int? crankRevs, int? eventTime1024}) {
  final hasCrank = crankRevs != null && eventTime1024 != null;
  return [
    if (hasCrank) 0x20 else 0x00,
    0x00,
    watts & 0xFF,
    (watts >> 8) & 0xFF,
    if (hasCrank) ...[
      crankRevs & 0xFF,
      (crankRevs >> 8) & 0xFF,
      eventTime1024 & 0xFF,
      (eventTime1024 >> 8) & 0xFF,
    ],
  ];
}

/// Cadence (rpm) between two power-meter crank samples, or `null` when it
/// cannot be computed: either sample lacks crank data, or the event time did
/// not advance. Both counters are 16-bit and wrap; the deltas mask
/// accordingly.
int? cpsCadenceRpm(CpsMeasurement prev, CpsMeasurement cur) {
  if (prev.crankRevolutions == null ||
      prev.crankEventTime1024 == null ||
      cur.crankRevolutions == null ||
      cur.crankEventTime1024 == null) {
    return null;
  }
  final dRevs = (cur.crankRevolutions! - prev.crankRevolutions!) & 0xFFFF;
  final dTime = (cur.crankEventTime1024! - prev.crankEventTime1024!) & 0xFFFF;
  if (dTime == 0) return null;
  return (dRevs * 61440 / dTime).round();
}
