import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prop/utils/network_address.dart';

/// The picker feeds the address BikeControl advertises over mDNS. On an iPhone
/// `NetworkInterface.list()` yields the cellular (`pdp_ip0`) and `ipsec0`
/// (192.0.0.x) addresses as well, and enumerating them first made the app
/// advertise an unreachable address — the network self-test then reported "no
/// Wi-Fi" and the advertisement was invisible to the LAN.
void main() {
  tearDown(() => AdvertisedAddressPicker.listInterfaces = NetworkInterface.list);

  void interfaces(List<NetworkInterface> list) {
    AdvertisedAddressPicker.listInterfaces = () async => list;
  }

  test('an iPhone on Wi-Fi picks en0 over cellular and ipsec', () async {
    interfaces([
      _iface('ipsec0', ['192.0.0.6']),
      _iface('pdp_ip0', ['10.140.12.7']),
      _iface('utun3', ['10.5.0.2']),
      _iface('en0', ['192.168.1.23']),
    ]);

    final report = await AdvertisedAddressPicker.report();
    expect(report.chosen?.address, '192.168.1.23');
    expect(
      report.candidates.map((c) => c.interfaceName).toSet(),
      {'ipsec0', 'pdp_ip0', 'utun3', 'en0'},
    );
    // The tunnels and the mobile-data port are flagged, en0 is not.
    expect(report.candidates.firstWhere((c) => c.interfaceName == 'en0').isVirtual, isFalse);
    expect(report.candidates.firstWhere((c) => c.interfaceName == 'pdp_ip0').isVirtual, isTrue);
    expect(report.candidates.firstWhere((c) => c.interfaceName == 'utun3').isVirtual, isTrue);
    // ipsec is not the picker's "virtual" — a real IKEv2 VPN rides on it, and
    // the VPN row (not a second-network warning) is what reports it.
    expect(report.candidates.firstWhere((c) => c.interfaceName == 'ipsec0').isVirtual, isFalse);
  });

  test('the Wi-Fi address beats a tunnel on the same subnet', () async {
    interfaces([
      _iface('utun3', ['192.168.1.9']),
      _iface('en0', ['192.168.1.23']),
    ]);

    expect((await AdvertisedAddressPicker.report()).chosen?.address, '192.168.1.23');
  });

  test('with no LAN the cellular address is still picked, and flagged virtual', () async {
    interfaces([_iface('pdp_ip0', ['10.140.12.7'])]);

    final report = await AdvertisedAddressPicker.report();
    expect(report.chosen?.address, '10.140.12.7');
    expect(report.candidates.single.isVirtual, isTrue);
  });

  test('with no LAN a lone tunnel is picked, and flagged virtual', () async {
    interfaces([_iface('utun3', ['10.5.0.2'])]);

    final report = await AdvertisedAddressPicker.report();
    expect(report.chosen?.address, '10.5.0.2');
    expect(report.candidates.single.isVirtual, isTrue);
  });

  test('two real ports tie on score, and the first enumerated wins', () async {
    interfaces([
      _iface('en0', ['192.168.1.50']),
      _iface('en1', ['10.0.0.20']),
    ]);

    expect((await AdvertisedAddressPicker.report()).chosen?.address, '192.168.1.50');
  });

  test('a bridge/container NIC loses to the Wi-Fi port', () async {
    interfaces([
      _iface('bridge100', ['172.20.10.1']),
      _iface('docker0', ['172.17.0.1']),
      _iface('en0', ['192.168.1.23']),
    ]);

    final report = await AdvertisedAddressPicker.report();
    expect(report.chosen?.address, '192.168.1.23');
    expect(report.candidates.firstWhere((c) => c.interfaceName == 'bridge100').isVirtual, isTrue);
    expect(report.candidates.firstWhere((c) => c.interfaceName == 'docker0').isVirtual, isTrue);
  });

  test('an unroutable address never wins over the Wi-Fi port', () async {
    interfaces([
      _iface('en7', ['169.254.10.3']),
      _iface('ipsec2', ['192.0.0.6']),
      _iface('en0', ['192.168.1.23']),
    ]);

    expect((await AdvertisedAddressPicker.report()).chosen?.address, '192.168.1.23');
  });

  test('no usable IPv4 picks nothing', () async {
    interfaces([
      _iface('lo0', ['127.0.0.1']),
      _iface('utun6', <String>[]),
    ]);

    final report = await AdvertisedAddressPicker.report();
    expect(report.chosen, isNull);
    expect(report.candidates, isEmpty);
  });
}

NetworkInterface _iface(String name, List<String> addresses) =>
    _FakeInterface(name, addresses);

class _FakeInterface implements NetworkInterface {
  _FakeInterface(this.name, List<String> addresses)
      : addresses = addresses.map(_FakeInterfaceAddress.new).toList();

  @override
  final String name;

  @override
  final List<InterfaceAddress> addresses;

  @override
  int get index => 1;
}

class _FakeInterfaceAddress implements InterfaceAddress {
  _FakeInterfaceAddress(String ip) : _inner = InternetAddress(ip);

  final InternetAddress _inner;

  @override
  int get prefixLength => 24;

  @override
  InternetAddress? get broadcast => null;

  @override
  InternetAddressType get type => _inner.type;

  @override
  String get address => _inner.address;

  @override
  String get host => _inner.host;

  @override
  Uint8List get rawAddress => _inner.rawAddress;

  @override
  bool get isLoopback => _inner.isLoopback;

  @override
  bool get isLinkLocal => _inner.isLinkLocal;

  @override
  bool get isMulticast => _inner.isMulticast;

  @override
  Future<InternetAddress> reverse() => _inner.reverse();
}
