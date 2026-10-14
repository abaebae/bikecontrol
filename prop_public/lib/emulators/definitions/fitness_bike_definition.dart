import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:prop/emulators/ble_definition.dart';
import 'package:prop/transports/ble_trainer_transport.dart';
import 'package:prop/transports/trainer_transport.dart';
import 'package:universal_ble/universal_ble.dart';

/// FitnessDircon implements a virtual Fitness Machine (bike) that apps like
/// Zwift and MyWhoosh can connect to via the DirCon (Direct Connect) protocol.
///
/// Architecture mirrors SHIFTR's `DirConManager` (DirConManager.cpp):
/// - Exposes FTMS, Cycling Power and Zwift Custom services as the source of
///   truth (it is not a passthrough).
/// - Translates FTMS Control Point and Zwift Sync (`ZWIFT_SYNC_RX`) writes
///   into FTMS Control Point writes on the connected physical trainer.
/// - Implements proper Zwift virtual shifting (Sync command 0x04/0x2A) using
///   gear ratios + `Calculations` physics, not slope-byte rewriting.
/// - Pushes synthetic `ZWIFT_ASYNC` (LEB128) and `INDOOR_BIKE_DATA`
///   notifications to the connected client at 1 Hz.
class FitnessBikeDefinition extends BleDefinition {
  final BleDevice connectedDevice;
  final List<BleService> connectedDeviceServices;
  final ValueNotifier<String> data;

  /// When true, the Zwift Play custom service is included in [serviceUUIDs]
  /// and thus advertised alongside FTMS / Cycling Power. The outer app sets
  /// this to true only when the user-selected trainer app is Zwift — other
  /// apps don't consume the Zwift service, and advertising it would just add
  /// noise to their scan results and occasionally confuse their pairing flows.
  final bool shouldAdvertiseZwift;

  /// Upstream I/O transport. Defaults to BLE via the device's id.
  final TrainerTransport transport;

  FitnessBikeDefinition({
    required this.connectedDevice,
    required this.connectedDeviceServices,
    required this.data,
    this.shouldAdvertiseZwift = false,
    TrainerTransport? transport,
  }) : transport = transport ?? BleTrainerTransport(connectedDevice.deviceId);

  // ===========================================================================
  // BLE Service / characteristic UUIDs
  // ===========================================================================

  static const String FITNESS_MACHINE_SERVICE_UUID = '00001826-0000-1000-8000-00805f9b34fb';
  static const String CYCLING_POWER_SERVICE_UUID = '00001818-0000-1000-8000-00805f9b34fb';

  static const String FITNESS_MACHINE_FEATURE_UUID = '00002acc-0000-1000-8000-00805f9b34fb';
  static const String INDOOR_BIKE_DATA_UUID = '00002ad2-0000-1000-8000-00805f9b34fb';
  static const String SUPPORTED_INCLINATION_RANGE_UUID = '00002ad5-0000-1000-8000-00805f9b34fb';
  static const String SUPPORTED_RESISTANCE_LEVEL_RANGE_UUID = '00002ad6-0000-1000-8000-00805f9b34fb';
  static const String SUPPORTED_POWER_RANGE_UUID = '00002ad8-0000-1000-8000-00805f9b34fb';
  static const String FITNESS_MACHINE_CONTROL_POINT_UUID = '00002ad9-0000-1000-8000-00805f9b34fb';
  static const String FITNESS_MACHINE_STATUS_UUID = '00002ada-0000-1000-8000-00805f9b34fb';
  static const String TRAINING_STATUS_UUID = '00002ad3-0000-1000-8000-00805f9b34fb';

  static const String DEVICE_INFORMATION_CHARACTERISTIC_MANUFACTURER_NAME = "00002a29-0000-1000-8000-00805f9b34fb";
  static const String DEVICE_INFORMATION_CHARACTERISTIC_FIRMWARE_REVISION = "00002a26-0000-1000-8000-00805f9b34fb";
  static const String DEVICE_INFORMATION_CHARACTERISTIC_SERIAL_NUMBER = "00002a25-0000-1000-8000-00805f9b34fb";

  static const String CYCLING_POWER_MEASUREMENT_UUID = '00002a63-0000-1000-8000-00805f9b34fb';
  static const String CYCLING_POWER_FEATURE_UUID = '00002a64-0000-1000-8000-00805f9b34fb';

  /// Kept for external consumers (e.g. ProxyDircon) — this class no longer
  /// exposes a Heart Rate service itself.
  static const String HEART_RATE_MEASUREMENT_UUID = '00002a37-0000-1000-8000-00805f9b34fb';

  ValueListenable<double> bicycleWeightKg = ValueNotifier(10.0);

  ValueListenable<double> riderWeightKg = ValueNotifier(70.0);

  static List<double> defaultGearRatios = [];

  @override
  // TODO: implement advertiseServiceUUIDs
  List<String> get advertiseServiceUUIDs => throw UnimplementedError();

  @override
  List<BleCharacteristic> getCharacteristics(String serviceUUID) {
    // TODO: implement getCharacteristics
    throw UnimplementedError();
  }

  @override
  void onNotification(String characteristic, Uint8List bytes) {
    // TODO: implement onNotification
  }

  @override
  void onWriteRequest(String characteristicUUID, List<int> characteristicData) {
    // TODO: implement onWriteRequest
  }

  @override
  // TODO: implement serviceUUIDs
  List<String> get serviceUUIDs => throw UnimplementedError();

  int get maxGear => 13;

  final ValueNotifier<int?> _cadenceRpmN = ValueNotifier<int?>(null);
  ValueListenable<int?> get cadenceRpm => _cadenceRpmN;

  final ValueNotifier<int?> _powerWN = ValueNotifier<int?>(null);
  ValueListenable<int?> get powerW => _powerWN;

  final ValueNotifier<double?> _speedKphN = ValueNotifier<double?>(null);
  ValueListenable<double?> get speedKph => _speedKphN;

  /// Cadence after the app-side smoothing filter. Stub: passthrough.
  int? get filteredCadence => _cadenceRpmN.value;

  final ValueNotifier<int?> _heartRateBpmN = ValueNotifier<int?>(null);
  ValueListenable<int?> get heartRateBpm => _heartRateBpmN;

  final ValueNotifier<TrainerMode> _trainerModeN = ValueNotifier(TrainerMode.simMode);
  ValueListenable<TrainerMode> get trainerMode => _trainerModeN;

  final ValueNotifier<int?> _ergTargetPowerN = ValueNotifier<int?>(null);
  ValueListenable<int?> get ergTargetPower => _ergTargetPowerN;

  final ValueNotifier<int> _currentGearN = ValueNotifier(0);
  ValueListenable<int> get currentGear => _currentGearN;

  final ValueNotifier<int> _targetPowerWN = ValueNotifier(0);
  ValueListenable<int> get targetPowerW => _targetPowerWN;

  final ValueNotifier<double> _gearRatioN = ValueNotifier(0.0);
  ValueListenable<double> get gearRatio => _gearRatioN;

  ValueNotifier<List<double>> get gearRatios => ValueNotifier([]);

  final ValueNotifier<VirtualShiftingMode> _virtualShiftingModeN = ValueNotifier(
    VirtualShiftingMode.targetPower,
  );
  ValueListenable<VirtualShiftingMode> get virtualShiftingMode => _virtualShiftingModeN;

  final ValueNotifier<bool> _trainerFeatureN = ValueNotifier(false);
  ValueListenable<bool> get trainerFeature => _trainerFeatureN;

  ValueListenable<bool> get gradeSmoothingEnabled => ValueNotifier(false);

  int get neutralGear => 0;

  /// The delivery the trainer is actually driven over: the rider's
  /// [controlProtocolOverride] when set, otherwise auto-detection.
  TrainerControlProtocol get controlProtocol => TrainerControlProtocol.ftms;

  /// The rider's forced delivery, or null for auto.
  TrainerControlProtocol? get controlProtocolOverride => null;

  /// Every delivery this trainer can actually carry.
  Set<TrainerControlProtocol> get supportedControlProtocols => const {};

  void setControlProtocolOverride(TrainerControlProtocol? p) {}

  /// The mode virtual shifting is actually driven with, which can differ from
  /// the saved [virtualShiftingMode].
  VirtualShiftingMode get effectiveVirtualShiftingMode => VirtualShiftingMode.targetPower;

  /// The mode auto-selection would pick for this trainer.
  VirtualShiftingMode get defaultVirtualShiftingMode => VirtualShiftingMode.targetPower;

  /// Hands the virtual-shifting mode back to auto-selection.
  void useDefaultVirtualShiftingMode() {}

  /// Compact FTMS capability line for the support bundle.
  String get ftmsCapabilitySummary => '';

  /// The cadence the resistance calculation actually uses.
  int get filteredCadence => 0;

  /// Compact Zwift-Sync handshake line for the support bundle; 'n/a' when the
  /// trainer does not speak it.
  String get zwiftHandshakeSummary => 'n/a';

  /// Compact native gear-acknowledgement line for the support bundle; 'n/a'
  /// when the trainer does not speak it.
  String get gearEchoSummary => 'n/a';

  /// How the gear echo watchdog resolved, or null while nothing is wrong.
  final ValueNotifier<ZwiftGearEchoVerdict?> gearEchoVerdict = ValueNotifier<ZwiftGearEchoVerdict?>(null);

  /// Whether the trainer refused to start grade simulation.
  final ValueNotifier<bool> trackResistanceRefused = ValueNotifier<bool>(false);

  /// The most recent upstream control write, or null before the first one.
  ControlWriteResult? get lastControlWrite => null;

  /// Rider metrics sourced by the app rather than the trainer.
  void setExternalHeartRate(int? bpm) {}

  void setExternalCadence(int? rpm) {}

  void setExternalPower(int? watts) {}

  List<String>? get trainerFtmsMachineFeatureFlagNames => null;

  List<String>? get trainerFtmsTargetSettingFlagNames => null;

  Future<void>? probeTrainerFeatures() async {}

  void setMaxGear(int maxGear) {}

  void setBicycleWeightKg(double bikeWeightKg) {}

  void setRiderWeightKg(double riderWeightKg) {}

  void setGradeSmoothingEnabled(bool gradeSmoothing) {}

  void setVirtualShiftingMode(VirtualShiftingMode mode) => _virtualShiftingModeN.value = mode;

  void setGearRatios(List<double> list) {}

  void setManualErgPower(int watts) => _ergTargetPowerN.value = watts;

  bool shiftUp() {
    return false;
  }

  bool shiftDown() {
    return false;
  }

  void exitErgMode() => _ergTargetPowerN.value = null;

  void adjustIntensity(double d) {}

  bool supportsVirtualShiftingMode(VirtualShiftingMode value) {
    return false;
  }

  static List<double> defaultGearRatiosFor(int count) {
    return [];
  }

  void setGearRatio(int gear, double v) {}

  void resetGearRatios() {}

  void setTargetGear(int i) {}

  // ── Control-protocol (FTMS / FEC / Zwift Sync) delivery ──────────────────

  /// The protocol currently driving the trainer: the rider's override when
  /// set, auto-detection otherwise. Stub: always FTMS.
  TrainerControlProtocol get controlProtocol => _controlProtocolOverride ?? TrainerControlProtocol.ftms;

  TrainerControlProtocol? _controlProtocolOverride;

  /// The rider-forced delivery, null for auto. Plain state, not a
  /// listenable — the settings UI repaints itself after setting it.
  TrainerControlProtocol? get controlProtocolOverride => _controlProtocolOverride;

  /// Every delivery this trainer's advertised services can carry. Stub:
  /// FTMS only, so the protocol card stays hidden (single option).
  List<TrainerControlProtocol> get supportedControlProtocols => const [TrainerControlProtocol.ftms];

  /// Forces the delivery, or null for auto. Ignored for protocols the
  /// trainer cannot carry.
  void setControlProtocolOverride(TrainerControlProtocol? protocol) => _controlProtocolOverride = protocol;

  /// The last control-point write, for support bundles. Stub: nothing.
  ControlWriteResult? get lastControlWrite => null;

  /// Watchdog verdict for native gear commands going unacknowledged.
  final ValueNotifier<ZwiftGearEchoVerdict?> _gearEchoVerdictN = ValueNotifier(null);
  ValueListenable<ZwiftGearEchoVerdict?> get gearEchoVerdict => _gearEchoVerdictN;

  /// Watchdog verdict for grade-simulation writes being refused.
  final ValueNotifier<bool> _trackResistanceRefusedN = ValueNotifier(false);
  ValueListenable<bool> get trackResistanceRefused => _trackResistanceRefusedN;

  /// One-line FTMS capability summary for support bundles.
  String get ftmsCapabilitySummary => '';

  /// One-line Zwift handshake summary, 'n/a' when the trainer does not speak
  /// Zwift Sync.
  String get zwiftHandshakeSummary => 'n/a';

  /// One-line native gear-acknowledgement summary, 'n/a' when not applicable.
  String get gearEchoSummary => 'n/a';

  /// The mode the definition would pick itself with no saved config:
  /// capability-based (Track Resistance on a grade-capable trainer) rather
  /// than the generic Target Power.
  VirtualShiftingMode get defaultVirtualShiftingMode => VirtualShiftingMode.targetPower;

  void useDefaultVirtualShiftingMode() => setVirtualShiftingMode(defaultVirtualShiftingMode);

  /// The mode actually driving the trainer: the saved mode, unless the
  /// trainer reports no cadence — the cadence-driven modes skip every write
  /// there, so the definition falls back to Target Power.
  VirtualShiftingMode get effectiveVirtualShiftingMode => virtualShiftingMode.value;

  /// Seeds the trainer-side heart rate. Unconditional: an external heart
  /// rate source must reach the wire on the next notification even when the
  /// value did not change.
  void setExternalHeartRate(int? bpm) => _heartRateBpmN.value = bpm;

  /// Seeds the trainer-side cadence. Guarded on non-null: the field is
  /// non-nullable-on-the-wire and a null would latch it at 0 for every
  /// rider with no external source selected.
  void setExternalCadence(int? rpm) {
    if (rpm == null) return;
    _cadenceRpmN.value = rpm;
  }

  /// Seeds the trainer-side power. Same null-guard reasoning as cadence.
  void setExternalPower(int? watts) {
    if (watts == null) return;
    _powerWN.value = watts;
  }

  // FAKE placeholder UUID.
  static const String FEC_BLE_SERVICE_UUID = '00000000-0000-0000-0000-0000000000c0';

  final ValueNotifier<bool> _cadenceFilterEnabledN = ValueNotifier(false);
  ValueListenable<bool> get cadenceFilterEnabled => _cadenceFilterEnabledN;
  void setCadenceFilterEnabled(bool enabled) {
    _cadenceFilterEnabledN.value = enabled;
  }

  bool _frontShiftEnabled = false;
  int _smallChainringTeeth = 34;
  int _largeChainringTeeth = 50;
  final ValueNotifier<FrontRing> _frontRingN = ValueNotifier<FrontRing>(FrontRing.small);
  ValueListenable<FrontRing> get frontRing => _frontRingN;
  int get smallChainringTeeth => _smallChainringTeeth;
  int get largeChainringTeeth => _largeChainringTeeth;
  bool get frontShiftEnabled => _frontShiftEnabled;

  void setFrontShiftEnabled(bool enabled) {
    _frontShiftEnabled = enabled;
    if (!enabled) _frontRingN.value = FrontRing.small;
  }

  void setChainringTeeth(int small, int large) {
    _smallChainringTeeth = small;
    _largeChainringTeeth = large;
    _frontRingN.value = FrontRing.small;
  }

  Future<bool> writeClimbInclineUpstream(int grade001Pct) async => false;

  void subscribeToTrainer() {}

  /// Test seam: stubbed.
  void setDebugValues() {}

  final ValueNotifier<int> _simGradeN = ValueNotifier<int>(0);
  ValueListenable<int> get simGrade => _simGradeN;

  bool get supportsClimbRelay => false;

  bool toggleFrontChainring() {
    if (!_frontShiftEnabled) return false;
    _frontRingN.value = _frontRingN.value == FrontRing.small ? FrontRing.large : FrontRing.small;
    return true;
  }
}

/// Outcome of the most recent control write sent upstream to the trainer.
class ControlWriteResult {
  final DateTime at;
  final bool ok;
  final String op;
  const ControlWriteResult({required this.at, required this.ok, required this.op});
}

/// How the gear echo watchdog resolved, once a trainer has ignored enough
/// native gear commands — see [FitnessBikeDefinition.gearEchoVerdict].
enum ZwiftGearEchoVerdict {
  /// Delivery moved to FTMS automatically.
  fellBackToFtms,

  /// The trainer has no FTMS Control Point; the native path stays.
  noFtmsToFallBackTo,

  /// The rider forced a protocol; that choice is kept.
  riderOverrideKept,
}

/// How BikeControl drives the trainer: native FTMS control point, ANT+---
/// over-BLE FEC, or the Zwift custom Sync protocol.
enum TrainerControlProtocol { ftms, fec, zwiftHub }

/// Record of one control-point write, for support bundles.
class ControlWriteResult {
  final DateTime at;
  final bool ok;

  const ControlWriteResult({required this.at, required this.ok});
}

enum FrontRing { small, large }

enum TrainerMode { ergMode, simMode, simModeVirtualShifting }

enum VirtualShiftingMode { targetPower, trackResistance, basicResistance }
