//INFO: Public re-implementation of the address picker.
//
// Scores every interface so the address a trainer app can actually reach wins:
// a Wi-Fi/Ethernet port beats a VPN tunnel, a virtualization bridge, a
// container NIC or a mobile-data interface, and an unroutable range
// (169.254/16, 192.0.0/24) never wins at all.

import 'dart:io';

/// How the host's network interfaces are enumerated. Injectable so tests can
/// simulate multi-homed machines without touching the real network stack.
typedef InterfaceLister = Future<List<NetworkInterface>> Function();

/// One scored IPv4 candidate considered by [AdvertisedAddressPicker].
class AddressCandidate {
  final String interfaceName;
  final String address;
  final int score;
  final bool isVirtual;

  const AddressCandidate({
    required this.interfaceName,
    required this.address,
    required this.score,
    required this.isVirtual,
  });
}

/// The picker's decision plus the candidates it weighed — for diagnostics.
class AddressPickReport {
  final InternetAddress? chosen;
  final List<AddressCandidate> candidates;

  const AddressPickReport({required this.chosen, required this.candidates});
}

/// Picks the IPv4 address BikeControl advertises over mDNS.
class AdvertisedAddressPicker {
  AdvertisedAddressPicker._();

  /// Test seam: replace to simulate interface layouts; reset in tearDown.
  static InterfaceLister listInterfaces = _defaultLister;

  static Future<List<NetworkInterface>> _defaultLister() =>
      NetworkInterface.list(includeLoopback: false, includeLinkLocal: false);

  /// The address to advertise plus every candidate considered.
  static Future<AddressPickReport> report() async {
    final interfaces = await listInterfaces();
    AddressCandidate? best;
    final candidates = <AddressCandidate>[];
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (address.type != InternetAddressType.IPv4 || address.isLoopback) continue;
        final candidate = AddressCandidate(
          interfaceName: interface.name,
          address: address.address,
          score: _scoreFor(interface.name, address.address),
          isVirtual: _isVirtualName(interface.name),
        );
        candidates.add(candidate);
        if (best == null || _isBetter(candidate, best)) best = candidate;
      }
    }
    return AddressPickReport(
      chosen: best == null ? null : InternetAddress(best.address),
      candidates: candidates,
    );
  }

  /// The address to advertise, or null when the host has no usable IPv4.
  static Future<InternetAddress?> pick() async => (await report()).chosen;

  /// Higher score wins; on a tie a real port beats a virtual one, and then the
  /// first one enumerated wins — [listInterfaces] order is otherwise stable.
  static bool _isBetter(AddressCandidate a, AddressCandidate b) {
    if (a.score != b.score) return a.score > b.score;
    return b.isVirtual && !a.isVirtual;
  }

  /// Scores one IPv4 by the port it sits on and the range it is in. A port
  /// name is worth more than any range bonus, so the Wi-Fi/Ethernet address
  /// beats a tunnel on the same subnet.
  static int _scoreFor(String name, String address) {
    var score = 0;
    if (_lanPortNamePattern.hasMatch(name)) score += 40;
    if (_cellularNamePattern.hasMatch(name)) score -= 70;
    if (_tunnelNamePattern.hasMatch(name)) score -= 70;
    if (_bridgeNamePattern.hasMatch(name)) score -= 80;

    if (_isUnreachable(address)) {
      score -= 199;
    } else if (_isCgnat(address)) {
      score -= 30;
    } else if (_isPrivate(address)) {
      score += 10;
    }
    return score;
  }
}

/// Interface names of a real Wi-Fi or Ethernet port: `en0`/`enp3s0`/`eth0`,
/// `wlan0`/`wlp2s0`, and Windows' "Ethernet"/"Wi-Fi"/"WLAN" FriendlyNames.
final _lanPortNamePattern = RegExp(r'^(en|eth|wl|wi-?fi)', caseSensitive: false);

/// Mobile-data interfaces: iOS `pdp_ip`, Android `rmnet`/`ccmni` and the
/// 464XLAT `v4-`/`clat` ones. The carrier owns the address on these, so no
/// rider's trainer app can reach it.
final _cellularNamePattern = RegExp(r'^(pdp_ip|rmnet|ccmni|v4-|clat)', caseSensitive: false);

/// VPN tunnel device names (unix) and the common Windows FriendlyNames.
final _tunnelNamePattern = RegExp(
  r'^(utun|tun|tap|ppp|wg|nordlynx|zt)'
  r'|wireguard|openvpn|tailscale|zerotier|mullvad|proton|anyconnect|vpn|tunnel',
  caseSensitive: false,
);

/// Virtualization bridges, container NICs and hypervisor adapters.
final _bridgeNamePattern = RegExp(
  r'^(bridge|docker|vboxnet|vmnet|vnic|virbr|br-)',
  caseSensitive: false,
);

/// 169.254/16 is link-local and 192.0.0/24 the 464XLAT/`ipsec` dummy range;
/// no other device can ever route to either.
bool _isUnreachable(String address) =>
    address.startsWith('169.254.') || address.startsWith('192.0.0.');

/// 100.64/10, the CGNAT range mesh VPNs (Tailscale, ZeroTier) hand out.
bool _isCgnat(String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  return parts[0] == 100 && parts[1]! >= 64 && parts[1]! <= 127;
}

/// RFC 1918 private ranges — the LAN a rider's trainer app sits on.
bool _isPrivate(String address) {
  final parts = address.split('.').map(int.tryParse).toList();
  if (parts.length != 4 || parts.any((p) => p == null)) return false;
  final a = parts[0]!, b = parts[1]!;
  if (a == 10) return true;
  if (a == 192 && b == 168) return true;
  if (a == 172 && b >= 16 && b <= 31) return true;
  return false;
}

/// Whether [name] belongs to an adapter the picker treats as virtual: a
/// tunnel, a bridge/container NIC or a mobile-data port. `ipsec` and vendor
/// gateway NICs are deliberately not here — they carry a LAN-range address a
/// real VPN rides on, and are the VPN row's business, not a second network.
bool _isVirtualName(String name) =>
    _cellularNamePattern.hasMatch(name) ||
    _tunnelNamePattern.hasMatch(name) ||
    _bridgeNamePattern.hasMatch(name);
