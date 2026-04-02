import 'dart:convert';
import 'dart:io';

class TcpServer {
  static const int port = 4546;
  ServerSocket? _serverSocket;
  Function(String, String)? onMessageReceived; // IP, Message

  bool get isRunning => _serverSocket != null;

  Future<void> start() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      _serverSocket!.listen((Socket client) {
        _handleConnection(client);
      });
    } catch (e) {
      print("Error starting TCP Server: $e");
    }
  }

  void _handleConnection(Socket client) {
    String clientIp = client.remoteAddress.address.replaceFirst('::ffff:', '');
    // Buffer incoming data — TCP may split a single JSON message across
    // multiple packets, so we must accumulate until the connection closes.
    List<int> buffer = [];

    client.listen(
      (List<int> data) {
        buffer.addAll(data);
      },
      onError: (error) {
        print("Socket error from $clientIp: $error");
        client.close();
      },
      onDone: () {
        // Connection closed — we now have the complete message
        try {
          String message = utf8.decode(buffer);
          if (message.isNotEmpty && onMessageReceived != null) {
            onMessageReceived!(clientIp, message);
          }
        } catch (e) {
          print("Error decoding message from $clientIp: $e");
        }
        client.close();
      },
    );
  }

  void stop() {
    _serverSocket?.close();
    _serverSocket = null;
  }
}
