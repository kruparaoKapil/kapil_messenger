import 'package:flutter/material.dart';
import '../network/tcp_client.dart';
import '../storage/chat_store.dart';
import '../network/discovery.dart';
import '../network/file_transfer.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class ChatMessage {
  final String text;
  final bool isMine;
  final DateTime timestamp;
  final String type;
  final String? filename;
  final int? size;
  final int? port;

  ChatMessage({
    required this.text,
    required this.isMine,
    required this.timestamp,
    this.type = 'text',
    this.filename,
    this.size,
    this.port,
  });
}

class ChatScreen extends StatefulWidget {
  final Peer peer;
  const ChatScreen({super.key, required this.peer});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final TcpClient _tcpClient = TcpClient();
  final Map<int, double> _transferProgress = {};

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    ChatStore.addMessage(widget.peer.ip, {
      'text': text,
      'type': 'text',
      'isMine': true,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });

    // Send via TCP using JSON
    await _tcpClient.sendJsonMessage(widget.peer.ip, {
      'type': 'text',
      'text': text,
    });
  }

  void _sendFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      File file = File(result.files.single.path!);
      String filename = result.files.single.name;
      int size = file.lengthSync();
      int timestamp = DateTime.now().millisecondsSinceEpoch;

      int port = await FileTransferService.hostFile(file, (progress) {
        if (mounted) {
          setState(() {
            _transferProgress[timestamp] = progress;
          });
        }
      });

      ChatStore.addMessage(widget.peer.ip, {
        'text': 'Sent file: $filename',
        'type': 'file_offer',
        'isMine': true,
        'timestamp': timestamp,
        'filename': filename,
        'size': size,
        'port': port,
      });

      await _tcpClient.sendJsonMessage(widget.peer.ip, {
        'type': 'file_offer',
        'filename': filename,
        'size': size,
        'port': port,
      });
    }
  }

  void _downloadFile(ChatMessage msg) async {
    if (msg.port == null || msg.filename == null) return;

    final timestamp = msg.timestamp.millisecondsSinceEpoch;

    File? file = await FileTransferService.receiveFile(
      widget.peer.ip,
      msg.port!,
      msg.filename!,
      msg.size ?? 0,
      (progress) {
        if (mounted) {
          setState(() {
            _transferProgress[timestamp] = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _transferProgress.remove(timestamp);
      });
      if (file != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved to Downloads: ${msg.filename}')),
        );
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Download failed.')));
      }
    }
  }

  // To simulate receiving messages ideally this state should come from a provider/bloc
  // For this basic setup, MainScreen handles receipt.
  // In a real implementation we'd use a global message bus or provider.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.peer.name}'),
        elevation: 1,
      ),
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder(
              valueListenable: ChatStore.box.listenable(keys: [widget.peer.ip]),
              builder: (context, Box box, _) {
                final messages = ChatStore.getMessages(widget.peer.ip);
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msgMap = messages[index];
                    final msg = ChatMessage(
                      text: msgMap['text'] ?? '',
                      isMine: msgMap['isMine'] == true,
                      timestamp: DateTime.fromMillisecondsSinceEpoch(
                        msgMap['timestamp'] ?? 0,
                      ),
                      type: msgMap['type'] ?? 'text',
                      filename: msgMap['filename'],
                      size: msgMap['size'],
                      port: msgMap['port'],
                    );
                    return Align(
                      alignment: msg.isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: msg.isMine
                              ? Colors.blueAccent
                              : Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: msg.type == 'file_offer'
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.insert_drive_file,
                                        color: msg.isMine
                                            ? Colors.white
                                            : Colors.blueAccent,
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          msg.filename ?? 'Unknown File',
                                          style: TextStyle(
                                            color: msg.isMine
                                                ? Colors.white
                                                : null,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_transferProgress.containsKey(
                                    msg.timestamp.millisecondsSinceEpoch,
                                  ))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: LinearProgressIndicator(
                                        value:
                                            _transferProgress[msg
                                                .timestamp
                                                .millisecondsSinceEpoch],
                                        color: msg.isMine
                                            ? Colors.white
                                            : Colors.blueAccent,
                                        backgroundColor: msg.isMine
                                            ? Colors.white24
                                            : Colors.grey[200],
                                      ),
                                    ),
                                  if (!msg.isMine &&
                                      !_transferProgress.containsKey(
                                        msg.timestamp.millisecondsSinceEpoch,
                                      ))
                                    TextButton.icon(
                                      onPressed: () => _downloadFile(msg),
                                      icon: const Icon(
                                        Icons.download,
                                        size: 16,
                                      ),
                                      label: const Text("Download"),
                                    ),
                                ],
                              )
                            : Text(
                                msg.text,
                                style: TextStyle(
                                  color: msg.isMine ? Colors.white : null,
                                ),
                              ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(
                top: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.attach_file, color: Colors.grey),
                  onPressed: _sendFile,
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: "Type a message...",
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send, color: Colors.blueAccent),
                  onPressed: _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
