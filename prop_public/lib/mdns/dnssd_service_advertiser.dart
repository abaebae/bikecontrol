//INFO: Implementation of the dns_sd bridge for iOS.
//
// Uses Apple's Bonjour (dns_sd) via a Flutter MethodChannel to publish a
// dedicated host that carries a single IPv4 A record, plus the service that
// points at it. The native side is `ios/Runner/DnsSdAdvertiser.swift`.
//
// This is the iOS platform default (see [ServiceAdvertiser.platformDefault]):
// the OS responder would attach every host address — IPv6 link-locals
// included — which some trainer apps cannot connect to.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:prop/mdns/service_advertiser.dart';

/// The platform side of the dns_sd bridge.
class DnsSdPlatform {
  static const conflictCode = 'conflict';
  static const _channelName = 'bikecontrol/dnssd';

  final MethodChannel _channel;

  DnsSdPlatform({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(_channelName);

  Future<void> registerHost({required String label, required String ipv4}) =>
      _channel.invokeMethod<void>('registerHost', {'label': label, 'ipv4': ipv4});

  Future<void> updateHost({required String ipv4}) =>
      _channel.invokeMethod<void>('updateHost', {'ipv4': ipv4});

  Future<void> unregisterHost() => _channel.invokeMethod<void>('unregisterHost');

  Future<int> registerService({
    required String name,
    required String type,
    required int port,
    required String hostLabel,
    required Map<String, Uint8List> txt,
  }) async {
    final result = await _channel.invokeMethod<int>('registerService', {
      'name': name,
      'type': type,
      'port': port,
      'hostLabel': hostLabel,
      'txt': txt,
    });
    return result ?? 0;
  }

  Future<void> unregisterService(int handle) =>
      _channel.invokeMethod<void>('unregisterService', {'handle': handle});
}

/// A [ServiceAdvertiser] backed by the platform's dns_sd bridge (iOS).
class DnsSdServiceAdvertiser implements ServiceAdvertiser {
  static const Duration defaultAnnounceInterval = Duration(seconds: 60);

  final Duration announceInterval;
  final DnsSdPlatform _platform;

  DnsSdServiceAdvertiser({this.announceInterval = defaultAnnounceInterval, DnsSdPlatform? platform})
      : _platform = platform ?? DnsSdPlatform();

  /// The hostname label this advertiser published, or null when it has none.
  String? get hostLabel => _hostLabel;
  String? _hostLabel;

  /// The service handle from the platform, for unregistration.
  int? _serviceHandle;

  Future<void> refreshAddress() async {}

  @override
  ValueListenable<String?> get advertisedAddress => ServiceAdvertiser.untrackedAddress;

  @override
  Future<ServiceAdvertisement> register(AdvertisedService service) async {
    // A unique-per-install suffix keeps two BikeControl instances (or a stale
    // record still in the responder) from colliding on `<name>.local`.
    final suffix = (service.port & 0xffff).toRadixString(16).padLeft(4, '0');
    var label = _hostLabelFor(service.name);

    try {
      await _platform.registerHost(label: label, ipv4: service.address.address);
    } on PlatformException catch (e) {
      if (e.code != DnsSdPlatform.conflictCode) rethrow;
      // The plain name is taken: fall back to the suffixed label.
      label = '${_hostLabelFor(service.name)}-$suffix';
      await _platform.registerHost(label: label, ipv4: service.address.address);
    }

    try {
      _serviceHandle = await _platform.registerService(
        name: service.name,
        type: service.type,
        port: service.port,
        hostLabel: label,
        txt: Map<String, Uint8List>.from(service.txt),
      );
    } catch (_) {
      // Never leave the A record dangling when the service could not be
      // published.
      await _platform.unregisterHost().catchError((_) {});
      rethrow;
    }

    _hostLabel = label;
    return _DnsSdAdvertisement(_platform, _serviceHandle!);
  }

  /// The service name turned into a DNS label (`BikeControl` → `bikecontrol`),
  /// keeping only characters legal in a hostname label.
  static String _hostLabelFor(String serviceName) {
    final cleaned = serviceName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9-]'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'bikecontrol' : cleaned;
  }
}

class _DnsSdAdvertisement implements ServiceAdvertisement {
  final DnsSdPlatform _platform;
  final int _handle;

  _DnsSdAdvertisement(this._platform, this._handle);

  @override
  Future<void> unregister() async {
    await _platform.unregisterService(_handle);
    await _platform.unregisterHost();
  }
}
