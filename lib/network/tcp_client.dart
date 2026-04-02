import 'dart:convert';
import 'dart:io';
import 'discovery.dart';

class TcpClient {
  static const int port = 4546;

  Future<bool> sendMessage(String ip, String message) async {
    try {
      Socket socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      socket.add(utf8.encode(message));
      await socket.flush();
      await socket.close();
      return true;
    } catch (e) {
      print("Error sending message to $ip: $e");
      return false;
    }
  }

  Future<bool> sendJsonMessage(String ip, Map<String, dynamic> data) async {
    String jsonString = jsonEncode(data);
    return await sendMessage(ip, jsonString);
  }

  /// Send a message to multiple peers (for group/broadcast).
  /// Awaits each send to ensure reliable delivery. Skips local IPs.
  Future<void> sendBroadcastJsonMessage(
    List<String> ips,
    Map<String, dynamic> data,
  ) async {
    final myIps = await DiscoveryService.getLocalIps();
    String jsonString = jsonEncode(data);

    // Filter out self IPs
    final targetIps = ips.where((ip) => !myIps.contains(ip)).toList();
    print("Group/Broadcast: sending to ${targetIps.length} peers (filtered from ${ips.length})");

    // Send to all peers concurrently but await completion
    final futures = targetIps.map((ip) async {
      bool success = await sendMessage(ip, jsonString);
      if (!success) {
        print("Failed to deliver to $ip");
      } else {
        print("Successfully delivered to $ip");
      }
    });

    await Future.wait(futures);
  }
}
