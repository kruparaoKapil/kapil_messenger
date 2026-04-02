import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileTransferService {
  /// Global transfer progress map (key: timestamp string)
  static final ValueNotifier<Map<String, double>> globalTransferProgress =
      ValueNotifier({});

  /// Start hosting a file on a random ephemeral port, and return that port.
  /// For group/broadcast file sharing, multiple peers may connect to download.
  /// The server stays open for [maxConnections] downloads or [timeout] duration.
  static Future<int> hostFile(File file, Function(double) onProgress, {int maxConnections = 20}) async {
    ServerSocket server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    int port = server.port;
    int connectionCount = 0;

    // Auto-close the server after 5 minutes to avoid leaking resources
    Future.delayed(const Duration(minutes: 5), () {
      try {
        server.close();
      } catch (_) {}
    });

    server.listen((Socket client) async {
      connectionCount++;
      try {
        int total = await file.length();
        int sent = 0;

        await for (var chunk in file.openRead()) {
          client.add(chunk);
          sent += chunk.length;
          onProgress(sent / total);
        }
        await client.flush();
        await client.close();
      } catch (e) {
        print("Error serving file to ${client.remoteAddress.address}: $e");
        try {
          await client.close();
        } catch (_) {}
      }

      // Close server after max connections are served
      if (connectionCount >= maxConnections) {
        try {
          await server.close();
        } catch (_) {}
      }
    });

    return port;
  }

  /// Connect to the sender's port and download the file into the Downloads directory.
  static Future<File?> receiveFile(
    String ip,
    int port,
    String filename,
    int size,
    String downloadId,
  ) async {
    try {
      Directory? dir = await getDownloadsDirectory();
      dir ??= await getApplicationDocumentsDirectory();

      File outFile = File('${dir.path}/$filename');

      // If file exists, append a timestamp to avoid overwriting
      if (await outFile.exists()) {
        String nameWithoutExt = filename.split('.').first;
        String ext = filename.split('.').last;
        outFile = File(
          '${dir.path}/${nameWithoutExt}_${DateTime.now().millisecondsSinceEpoch}.$ext',
        );
      }

      var sink = outFile.openWrite();
      Socket socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 10),
      );

      int received = 0;
      await for (var chunk in socket) {
        sink.add(chunk);
        received += chunk.length;
        if (size > 0) {
          final progressMap = Map<String, double>.from(globalTransferProgress.value);
          progressMap[downloadId] = received / size;
          globalTransferProgress.value = progressMap;
        }
      }

      await sink.flush();
      await sink.close();
      await socket.close();
      
      final progressMap = Map<String, double>.from(globalTransferProgress.value);
      progressMap.remove(downloadId);
      globalTransferProgress.value = progressMap;

      return outFile;
    } catch (e) {
      print("File receive error: $e");
      return null;
    }
  }
}
