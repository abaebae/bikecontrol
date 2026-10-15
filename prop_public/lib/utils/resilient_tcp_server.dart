//INFO: This is a stub - contact me if you need the full implementation.
//
// This public stub keeps the surface the app relies on, with a working
// implementation for the parts the LAN bridging methods need: a single-client
// TCP server with dual-stack listening, owner-supersede, port fallback and
// probe filtering. The full implementation additionally handles concurrent
// clients and reconnect churn.

import 'dart:async';
import 'dart:io';

class ResilientTcpServer {
  ResilientTcpServer({
    required this.preferredPort,
    this.portAttempts = 5,
    this.forceIPv4 = false,
    this.allowConcurrentClients = false,
    this.maxConcurrentClients = 8,
    this.label,
    this.owner,
    required this.onClientConnected,
    required this.onData,
    required this.onClientDisconnected,
    this.onClientLeft,
  }) : assert(portAttempts >= 1),
        assert(maxConcurrentClients >= 1);

  final int preferredPort;
  final int portAttempts;
  final bool forceIPv4;
  final bool allowConcurrentClients;
  final int maxConcurrentClients;
  final String? label;

  /// Whoever this server serves on behalf of — the emulator instance, or a
  /// stable key. Compared with `==`.
  final Object? owner;

  /// Every currently-running server, for the diagnostics block.
  static final List<ResilientTcpServer> activeServers = [];

  final void Function(Socket socket) onClientConnected;
  final void Function(Socket socket, List<int> data) onData;
  final void Function() onClientDisconnected;

  /// One client went away, while others may remain.
  final void Function(Socket socket)? onClientLeft;

  ServerSocket? _server;
  StreamSubscription<Socket>? _accepts;
  Socket? _client;
  bool _started = false;

  bool get isRunning => _started;
  bool get hasClient => _client != null;
  Socket? get client => _client;
  int get boundPort => _server?.port ?? preferredPort;

  /// The listening address. Dual-stack by default (an `anyIPv6` socket with
  /// `v6Only: false` accepts IPv4 too), so a peer that reaches us over IPv4 or
  /// IPv6 — the MyWhoosh app resolves the phone by hostname — both land.
  InternetAddress get _bindAddress => forceIPv4 ? InternetAddress.anyIPv4 : InternetAddress.anyIPv6;

  Future<void> start() async {
    if (_started) return;

    // A (re)start supersedes any server of ours still registered under the same
    // owner — one whose stop is still closing, or one a previous start lost
    // track of — so we rebind the preferred port instead of walking past it.
    if (owner != null) {
      for (final existing in activeServers.where((s) => !identical(s, this) && s.owner == owner).toList()) {
        await existing.stop();
      }
    }

    ServerSocket? server;
    Object? lastError;
    for (var attempt = 0; attempt < portAttempts; attempt++) {
      try {
        server = await ServerSocket.bind(_bindAddress, preferredPort + attempt, v6Only: false);
        break;
      } on SocketException catch (e) {
        lastError = e;
      }
    }
    if (server == null) {
      throw lastError ?? SocketException('could not bind $preferredPort');
    }

    _server = server;
    _started = true;
    activeServers.add(this);
    _accepts = server.listen((socket) {
      // The network self-test announces its throwaway probe, so it does not
      // register as a trainer app connecting.
      if (_isProbe(socket)) {
        socket.destroy();
        return;
      }
      _client = socket;
      onClientConnected(socket);
      var closed = false;
      void gone() {
        if (closed) return;
        closed = true;
        if (identical(_client, socket)) {
          _client = null;
          onClientDisconnected();
        } else {
          onClientLeft?.call(socket);
        }
      }

      socket.listen((data) => onData(socket, data), onError: (_) => gone(), onDone: gone, cancelOnError: true);
    });
  }

  /// Announces that this process is about to open a throwaway TCP connection
  /// to its own server, so the next matching accepted socket is ignored.
  void expectProbe({
    required String address,
    required int sourcePort,
    Duration validity = const Duration(seconds: 5),
  }) {
    _probeAddress = address;
    _probeSourcePort = sourcePort;
    _probeExpiry = DateTime.now().add(validity);
  }

  String? _probeAddress;
  int? _probeSourcePort;
  DateTime? _probeExpiry;

  bool _isProbe(Socket socket) {
    final address = _probeAddress;
    final port = _probeSourcePort;
    if (address == null || port == null) return false;
    final expiry = _probeExpiry;
    if (expiry != null && DateTime.now().isAfter(expiry)) {
      _probeAddress = null;
      _probeSourcePort = null;
      _probeExpiry = null;
      return false;
    }
    // A dual-stack listener reports IPv4 peers as IPv4-mapped IPv6
    // (`::ffff:127.0.0.1`); normalise so the announced probe still matches.
    return _plain(socket.remoteAddress.address) == _plain(address) && socket.remotePort == port;
  }

  static String _plain(String address) =>
      address.startsWith('::ffff:') ? address.substring('::ffff:'.length) : address;

  void dropClient() {
    _client?.destroy();
    _client = null;
  }

  Future<void> stop() async {
    if (!isRunning) return;
    _started = false;
    activeServers.remove(this);
    final accepts = _accepts;
    _accepts = null;
    try {
      await accepts?.cancel();
    } catch (_) {}
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _client?.destroy();
    _client = null;
  }
}
