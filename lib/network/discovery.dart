import 'dart:convert';
import 'dart:io';
import '../storage/settings.dart';

class Peer {
  final String ip;
  final String name;
  final DateTime lastSeen;

  Peer({required this.ip, required this.name, required this.lastSeen});
}

class DiscoveryService {
  static const int port = 4545;
  RawDatagramSocket? _socket;
  final Map<String, Peer> _peers = {};

  String get myName => SettingsService.userName;

  Function(List<Peer>)? onPeersUpdated;

  bool _isBroadcasting = false;

  Future<void> start() async {
    _socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      port,
      reuseAddress: true,
    );
    _socket!.broadcastEnabled = true;

    _socket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        Datagram? datagram = _socket!.receive();
        if (datagram != null) {
          _handleDatagram(datagram);
        }
      }
    });

    _isBroadcasting = true;
    _startBroadcasting();
  }

  void _handleDatagram(Datagram datagram) {
    String message = utf8.decode(datagram.data);
    try {
      Map<String, dynamic> data = jsonDecode(message);
      if (data['type'] == 'announce') {
        String ip = datagram.address.address;
        String name = data['user'] ?? 'Unknown';

        _peers[ip] = Peer(ip: ip, name: name, lastSeen: DateTime.now());

        _cleanupStalePeers();
        if (onPeersUpdated != null) {
          onPeersUpdated!(_peers.values.toList());
        }
      }
    } catch (e) {
      print('Invalid datagram: $message');
    }
  }

  Future<void> _startBroadcasting() async {
    while (_isBroadcasting) {
      if (_socket != null) {
        String ip = await _getLocalIp();
        Map<String, dynamic> announcement = {
          "type": "announce",
          "user": myName,
          "ip": ip,
        };
        List<int> data = utf8.encode(jsonEncode(announcement));

        // Broadcast to 255.255.255.255
        try {
          _socket!.send(data, InternetAddress('255.255.255.255'), port);
        } catch (_) {}

        // Also broadcast to the subnet if possible
        try {
          if (ip.isNotEmpty) {
            List<String> parts = ip.split('.');
            if (parts.length == 4) {
              parts[3] = '255';
              String subnetBroadcast = parts.join('.');
              _socket!.send(data, InternetAddress(subnetBroadcast), port);
            }
          }
        } catch (_) {}
      }
      await Future.delayed(const Duration(seconds: 3));
    }
  }

  void _cleanupStalePeers() {
    final now = DateTime.now();
    _peers.removeWhere(
      (key, peer) => now.difference(peer.lastSeen).inSeconds > 10,
    );
  }

  Future<String> _getLocalIp() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            return addr.address;
          }
        }
      }
    } catch (e) {
      print("Could not get local IP: $e");
    }
    return '';
  }

  void stop() {
    _isBroadcasting = false;
    _socket?.close();
    _socket = null;
  }
}
