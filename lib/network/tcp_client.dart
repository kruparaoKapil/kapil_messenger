import 'dart:convert';
import 'dart:io';

class TcpClient {
  static const int port = 4546;

  Future<bool> sendMessage(String ip, String message) async {
    try {
      Socket socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 3),
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

  Future<void> sendBroadcastJsonMessage(
    List<String> ips,
    Map<String, dynamic> data,
  ) async {
    String jsonString = jsonEncode(data);
    for (String ip in ips) {
      sendMessage(ip, jsonString); // Fire and forget for broadcast
    }
  }
}
