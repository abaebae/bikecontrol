//INFO: This is a stub - contact me if you need the full implementation.
//
// The full implementation is a single-client TCP server with dual-stack
// listening, reconnect-supersede and port-fallback logic. This stub keeps the
// public surface so the app compiles.

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
  Socket? _client;
  bool _started = false;

  bool get isRunning => _started;
  bool get hasClient => _client != null;
  Socket? get client => _client;
  int get boundPort => _server?.port ?? preferredPort;

  Future<void> start() async {
    if (_started) return;
    final server = await ServerSocket.bind(
      forceIPv4 ? InternetAddress.loopbackIPv4 : InternetAddress.anyIPv4,
      preferredPort,
    );
    _server = server;
    _started = true;
    activeServers.add(this);
    server.listen((socket) {
      _client = socket;
      onClientConnected(socket);
      socket.listen((data) => onData(socket, data), onDone: () {
        onClientDisconnected();
        _client = null;
      });
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
  }

  String? _probeAddress;
  int? _probeSourcePort;

  void dropClient() {
    _client?.close();
    _client = null;
  }

  Future<void> stop() async {
    if (!isRunning) return;
    try {
      await _server?.close();
    } catch (_) {}
    _server = null;
    _started = false;
    activeServers.remove(this);
  }
}
