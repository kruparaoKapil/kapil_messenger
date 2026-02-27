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
    String clientIp = client.remoteAddress.address;
    client.listen(
      (List<int> data) {
        try {
          String message = utf8.decode(data);
          if (onMessageReceived != null) {
            onMessageReceived!(clientIp, message);
          }
        } catch (e) {
          print("Error decoding message from $clientIp: $e");
        }
      },
      onError: (error) {
        print("Socket error from $clientIp: $error");
        client.close();
      },
      onDone: () {
        client.close();
      },
    );
  }

  void stop() {
    _serverSocket?.close();
    _serverSocket = null;
  }
}
