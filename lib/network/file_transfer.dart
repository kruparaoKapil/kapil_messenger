import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class FileTransferService {
  /// Global transfer progress map (key: timestamp string)
  static final ValueNotifier<Map<String, double>> globalTransferProgress =
      ValueNotifier({});

  /// Start hosting a file on a random ephemeral port, and return that port.
  static Future<int> hostFile(File file, Function(double) onProgress) async {
    ServerSocket server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    int port = server.port;

    // Listen for a single connection
    server.listen((Socket client) async {
      int total = await file.length();
      int sent = 0;

      file.openRead().listen(
        (List<int> chunk) {
          client.add(chunk);
          sent += chunk.length;
          onProgress(sent / total);
        },
        onDone: () async {
          await client.flush();
          await client.close();
          await server.close(); // Close server after transferring
        },
        onError: (e) {
          client.close();
          server.close();
        },
      );
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
        timeout: const Duration(seconds: 5),
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
