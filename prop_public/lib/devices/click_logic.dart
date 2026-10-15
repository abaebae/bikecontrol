//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation decodes the Zwift Click/Play pairing pages and
// drives the periodic RESET recovery. This stub keeps the static surface so
// the app compiles.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

/// Where the right puck's keep-awake has got to, for the app to show.
enum ClickKeepAwakeStatus {
  /// No right puck connected, so there is nothing to keep awake.
  idle,

  /// Working, but with no left puck in range.
  waitingForLeftSide,

  /// Running.
  active,

  /// The last attempt failed; the loop keeps retrying.
  failed,
}

class ClickLogic {
  static final _resettingDevices = <String>{};

  static final _keepAwakeStatusN = ValueNotifier(ClickKeepAwakeStatus.idle);

  /// Live state of the Click V2 keep-awake choreography, for the home card.
  static ValueListenable<ClickKeepAwakeStatus> get keepAwakeStatus => _keepAwakeStatusN;

  /// Nudges a pending keep-awake to start now.
  static void startKeepAwakeIfPending() {}

  /// Forgets the right puck and clears the status.
  static void forgetKeepAwake() {
    _keepAwakeStatusN.value = ClickKeepAwakeStatus.idle;
  }

  static bool isResetting(String deviceId) => _resettingDevices.contains(deviceId);

  static void clearResetting(String deviceId) => _resettingDevices.remove(deviceId);

  /// Invoked right before a RESET command is sent.
  static void Function(String deviceId)? onResetSent;

  /// Wired by the app: whether a left puck is currently in range. Never gates
  /// the keep-awake itself — only the LED-refresh re-entry does.
  static set isLeftSideNearby(bool Function()? callback) => _isLeftSideNearby = callback;
  static bool Function()? _isLeftSideNearby;

  static void processData(Uint8List bytes, {required String deviceId, required List<BleService> services}) {}

  static Future<void> setupHandshake(List<BleService> services, String deviceId, {required bool isRight}) async {}

  static void resetTimer() {}
}
