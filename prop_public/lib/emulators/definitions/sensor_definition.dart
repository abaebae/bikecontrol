//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation serves Heart Rate (0x180D), Cycling Speed and
// Cadence (0x1816) and Cycling Power (0x1818) over the emulator's GATT
// server. This stub keeps the public surface — the expose flags and service
// UUID bookkeeping the sink controller relies on, plus the metric setters —
// with behaviour pinned by the repo's own tests.

import 'dart:typed_data';

import 'package:prop/emulators/ble_definition.dart';
import 'package:universal_ble/universal_ble.dart';

class SensorDefinition extends BleDefinition {
  SensorDefinition();

  static const String HEART_RATE_SERVICE_UUID = '0000180d-0000-1000-8000-00805f9b34fb';
  static const String HEART_RATE_MEASUREMENT_UUID = '00002a37-0000-1000-8000-00805f9b34fb';
  static const String CYCLING_SPEED_CADENCE_SERVICE_UUID = '00001816-0000-1000-8000-00805f9b34fb';
  static const String CYCLING_SPEED_CADENCE_MEASUREMENT_UUID = '00002a5b-0000-1000-8000-00805f9b34fb';
  static const String CYCLING_POWER_SERVICE_UUID = '00001818-0000-1000-8000-00805f9b34fb';
  static const String CYCLING_POWER_MEASUREMENT_UUID = '00002a63-0000-1000-8000-00805f9b34fb';

  /// A bare definition exposes every service; [exposeServices] narrows it.
  /// The sink controller calls it before every attach so a retracted
  /// service never reaches the wire (see SensorSinkController's doc
  /// comments for the defect history).
  bool _heartRate = true;
  bool _cadence = true;
  bool _power = true;

  int? _heartRateBpm;
  int? _cadenceRpm;
  int? _powerWatts;

  /// Narrows the exposed service set. Used before every attach/standalone
  /// start so the GATT table never advertises more than the current mode
  /// serves.
  void exposeServices({required bool heartRate, required bool cadence, required bool power}) {
    _heartRate = heartRate;
    _cadence = cadence;
    _power = power;
  }

  bool get exposesHeartRate => _heartRate;
  bool get exposesCadence => _cadence;
  bool get exposesPower => _power;

  void setHeartRate(int? bpm) => _heartRateBpm = bpm;
  void setCadence(int? rpm) => _cadenceRpm = rpm;
  void setPower(int? watts) => _powerWatts = watts;

  int? get heartRateBpm => _heartRateBpm;
  int? get cadenceRpm => _cadenceRpm;
  int? get powerWatts => _powerWatts;

  /// Chooses which services this definition advertises and notifies.
  void exposeServices({required bool heartRate, required bool cadence, required bool power}) {
    _heartRate = heartRate;
    _cadence = cadence;
    _power = power;
  }

  @override
  List<String> get serviceUUIDs => [
    if (_heartRate) HEART_RATE_SERVICE_UUID,
    if (_cadence) CYCLING_SPEED_CADENCE_SERVICE_UUID,
    if (_power) CYCLING_POWER_SERVICE_UUID,
  ];

  @override
  List<String> get advertiseServiceUUIDs => serviceUUIDs;

  @override
  List<BleCharacteristic> getCharacteristics(String serviceUUID) => const [];

  @override
  void onWriteRequest(String characteristicUUID, List<int> characteristicData) {}

  @override
  void onNotification(String characteristic, Uint8List bytes) {}
}
