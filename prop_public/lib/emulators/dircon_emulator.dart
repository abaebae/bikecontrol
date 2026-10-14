//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation drives the DirCon TCP server, the BLE peripheral
// transporter and the mDNS advertisement. This stub keeps the public surface
// (and the [composite] child bookkeeping the app reads) so the app compiles.

import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:prop/emulators/ble_definition.dart';
import 'package:prop/emulators/definitions/composite_ble_definition.dart';
import 'package:prop/emulators/definitions/fitness_bike_definition.dart';
import 'package:prop/emulators/definitions/sensor_definition.dart';
import 'package:prop/emulators/definitions/zwift_click_definition.dart';
import 'package:prop/emulators/definitions/zwift_emulator_definition.dart';
import 'package:prop/emulators/transporter/network_transporter.dart';

enum RetrofitMode {
  proxy,
  wifi,
  bluetooth;

  String get label => switch (this) {
    RetrofitMode.proxy => 'Proxy',
    RetrofitMode.wifi => 'Virtual Shifting (WiFi)',
    RetrofitMode.bluetooth => 'Virtual Shifting (Bluetooth)',
  };
}

int _portNumberIterator = 36868;

/// Test seam: rebase the TCP port iterator.
@visibleForTesting
void debugSetDirconPortBase(int base) => _portNumberIterator = base;

/// The standard Wahoo DirCon TCP port. Clients that hard-dial it (ignoring
/// the mDNS SRV port) expect the server here.
const int kWahooDirconStandardPort = 36867;

class DirconEmulator {
  /// [preferredPort] pins the TCP port the emulator asks its server to bind
  /// first. Left unset it auto-assigns a distinct port so concurrent
  /// instances don't pile onto one.
  DirconEmulator({int? preferredPort}) : _ownPort = preferredPort ?? _portNumberIterator++;

  final int _ownPort;

  /// Serve on the standard DirCon port instead of this instance's own port
  /// while it returns true.
  bool Function()? preferStandardPort;

  /// The port this emulator prefers for its DirCon TCP server. The port it
  /// *actually* bound is [boundPort] (may differ after fallback).
  int get preferredPort => _ownPort;

  /// Forces the TCP listener to IPv4 only while it returns true.
  bool Function()? forceIPv4;

  /// Overrides the advertised peripheral / service name.
  String? Function()? advertisementNameOverride;

  /// Advertises 16-bit service UUIDs in their bare form while it returns true.
  bool Function()? bareShortServiceUuids;

  final ValueNotifier<bool> isStarted = ValueNotifier(false);
  final ValueNotifier<bool> isConnected = ValueNotifier(false);
  final ValueNotifier<String> data = ValueNotifier('');

  final ValueNotifier<String?> _localAddressN = ValueNotifier<String?>(null);
  ValueListenable<String?> get localAddress => _localAddressN;

  int? get boundPort => null;

  /// All child definitions exposed by this emulator share a single transport
  /// via this composite.
  final CompositeBleDefinition composite = CompositeBleDefinition();

  /// Callback deciding whether the emulator should advertise on session start.
  bool Function()? shouldAdvertise;

  /// Returns the connected trainer-app name (e.g. "Rouvy", "Zwift").
  String? Function()? trainerApp;

  /// Returns `true` when the user is in trial / non-Pro state.
  bool Function()? isTrial;

  /// Returns the connected device's display name.
  String? Function()? deviceName;

  /// Stubbed: the full implementation derives the advertised name from the
  /// trainer-app / trial / device-name callbacks.
  String get advertisementName => 'BikeControl';

  /// Overrides the advertised peripheral name verbatim when set.
  set advertisementNameOverride(String? Function()? override) => _advertisementNameOverride = override;
  String? Function()? _advertisementNameOverride;

  /// Whether the advertisement should use bare 16-bit service UUIDs (some
  /// trainer apps, e.g. Tacx, only match those).
  set bareShortServiceUuids(bool Function()? callback) => _bareShortServiceUuids = callback;
  bool Function()? _bareShortServiceUuids;

  /// Whether the transport must bind IPv4 only (apps whose discovery breaks
  /// on dual-stack).
  set forceIPv4(bool Function()? callback) => _forceIPv4 = callback;
  bool Function()? _forceIPv4;

  /// Whether the emulator has nothing worth serving: no children, or only a
  /// rider-metrics [SensorDefinition] riding along after its trainer left.
  /// A lone SensorDefinition must not keep the shared bridge composite alive.
  bool get hasNothingToServe => composite.children.every((c) => c is SensorDefinition);

  bool processCharacteristic(String characteristic, Uint8List bytes) => false;

  Future<void> startServer({
    required RetrofitMode mode,
    Map<String, Uint8List> mdnsTxt = const {},
  }) async {
    isConnected.value = false;
    isStarted.value = true;
    _localAddressN.value = null;
  }

  Future<void> stop() async {
    isStarted.value = false;
    isConnected.value = false;
    _localAddressN.value = null;
  }

  Future<void> restart() async {}

  void reconnect() {}

  Future<void> pauseAdvertising() async {}

  Future<void> debug() async {}

  BleDefinition? get activeDefinition => composite;

  /// Whether the composite holds nothing a trainer app would connect for —
  /// rider-metric sinks alone don't count.
  bool get hasNothingToServe => composite.children.every((c) => c is SensorDefinition);

  /// Attach [def] as a child of this emulator's [composite].
  Future<void> attachDefinition(BleDefinition def) async {
    if (def is ZwiftClickDefinition && composite.firstOfType<ZwiftEmulatorDefinition>() != null) {
      composite.detach(composite.firstOfType<ZwiftEmulatorDefinition>()!);
    }
    composite.attach(def);
  }

  /// Detach [def] from this emulator's [composite].
  Future<void> detachDefinition(BleDefinition def) async {
    composite.detach(def);
  }

  FitnessBikeDefinition? get fitnessBike => composite.firstOfType<FitnessBikeDefinition>();

  @visibleForTesting
  void debugSetActiveDefinition(BleDefinition def) {
    for (final c in List<BleDefinition>.from(composite.children)) {
      composite.detach(c);
    }
    composite.attach(def);
  }

  @visibleForTesting
  void debugSetTransporter(NetworkTransporter transporter) {}
}
