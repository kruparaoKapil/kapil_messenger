import 'package:flutter/material.dart';
import '../network/tcp_client.dart';
import '../storage/chat_store.dart';
import '../storage/group_store.dart';
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
  final String? senderIp;

  ChatMessage({
    required this.text,
    required this.isMine,
    required this.timestamp,
    this.type = 'text',
    this.filename,
    this.size,
    this.port,
    this.senderIp,
  });
}

class ChatView extends StatefulWidget {
  final Peer peer;
  const ChatView({super.key, required this.peer});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final TextEditingController _controller = TextEditingController();
  final TcpClient _tcpClient = TcpClient();
  final Map<int, double> _transferProgress = {};
  final DiscoveryService _discoveryService = DiscoveryService();

  bool _isSearching = false;
  String _searchQuery = "";
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final messageData = {
      'text': text,
      'type': 'text',
      'isMine': true,
      'timestamp': timestamp,
    };

    ChatStore.addMessage(widget.peer.ip, messageData);
    _scrollToBottom();

    final Map<String, dynamic> payload = {'type': 'text', 'text': text};

    if (widget.peer.ip == "BROADCAST") {
      payload['isBroadcast'] = true;
      payload['groupId'] = "BROADCAST";
      final peers = _discoveryService.onlinePeers;
      await _tcpClient.sendBroadcastJsonMessage(
        peers.map((p) => p.ip).toList(),
        payload,
      );
    } else if (widget.peer.ip.startsWith("GROUP:")) {
      final groupId = widget.peer.ip.replaceFirst("GROUP:", "");
      payload['groupId'] = groupId;
      final groups = GroupStore.getAllGroups();
      try {
        final group = groups.firstWhere((g) => g.id == groupId);
        payload['groupName'] = group.name;
        payload['peerIps'] = group.peerIps;
        await _tcpClient.sendBroadcastJsonMessage(group.peerIps, payload);
      } catch (e) {
        print("Group not found: $groupId");
      }
    } else {
      await _tcpClient.sendJsonMessage(widget.peer.ip, payload);
    }
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

    final downloadIp = msg.senderIp ?? widget.peer.ip;

    File? file = await FileTransferService.receiveFile(
      downloadIp,
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

  void _showSharedFiles() {
    final messages = ChatStore.getMessages(widget.peer.ip);
    final files = messages.where((m) => m['type'] == 'file_offer').toList();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text("Shared Files (${files.length})"),
          content: SizedBox(
            width: 400,
            height: 400,
            child: files.isEmpty
                ? const Center(child: Text("No files shared yet."))
                : ListView.builder(
                    itemCount: files.length,
                    itemBuilder: (context, index) {
                      final file = files[index];
                      return ListTile(
                        leading: const Icon(
                          Icons.insert_drive_file,
                          color: Colors.blueAccent,
                        ),
                        title: Text(file['filename'] ?? "Unknown File"),
                        subtitle: Text(
                          "${((file['size'] ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB",
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.download),
                          onPressed: () {
                            Navigator.pop(context);
                            // We need a ChatMessage object for _downloadFile
                            _downloadFile(
                              ChatMessage(
                                text: file['text'] ?? '',
                                isMine: file['isMine'] == true,
                                timestamp: DateTime.fromMillisecondsSinceEpoch(
                                  file['timestamp'] ?? 0,
                                ),
                                filename: file['filename'],
                                size: file['size'],
                                port: file['port'],
                                senderIp: file['senderIp'],
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }
  // In a real implementation we'd use a global message bus or provider.

  @override
  Widget build(BuildContext context) {
    final bool isGroup =
        widget.peer.ip.startsWith("GROUP:") || widget.peer.ip == "BROADCAST";
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white10 : Colors.grey[200]!,
              ),
            ),
          ),
          child: Row(
            children: [
              if (!_isSearching) ...[
                if (!isGroup)
                  const CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.blueAccent,
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  )
                else
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.green.withOpacity(0.1),
                    child: const Icon(
                      Icons.group,
                      color: Colors.green,
                      size: 20,
                    ),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.peer.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isGroup ? "Group Chat" : widget.peer.ip,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  onPressed: () => setState(() => _isSearching = true),
                ),
              ] else ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  onPressed: () {
                    setState(() {
                      _isSearching = false;
                      _searchQuery = "";
                      _searchController.clear();
                    });
                  },
                ),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      hintText: "Search messages...",
                      border: InputBorder.none,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val),
                  ),
                ),
              ],
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                onSelected: (value) async {
                  if (value == 'clear') {
                    await ChatStore.box.delete(widget.peer.ip);
                    if (mounted) setState(() {});
                  } else if (value == 'files') {
                    _showSharedFiles();
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'clear',
                    child: Text('Clear History'),
                  ),
                  const PopupMenuItem(
                    value: 'files',
                    child: Text('Shared Files'),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Chat Area
        Expanded(
          child: Container(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: ValueListenableBuilder(
              valueListenable: ChatStore.box.listenable(keys: [widget.peer.ip]),
              builder: (context, Box box, _) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => _scrollToBottom(),
                );
                var messages = ChatStore.getMessages(widget.peer.ip);
                if (_searchQuery.isNotEmpty) {
                  messages = messages
                      .where(
                        (m) =>
                            (m['text'] ?? "").toString().toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ) ||
                            (m['filename'] ?? "")
                                .toString()
                                .toLowerCase()
                                .contains(_searchQuery.toLowerCase()),
                      )
                      .toList();
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.chat_bubble_outline
                              : Icons.search_off,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? "No messages yet"
                              : "No results found for '$_searchQuery'",
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 20,
                  ),
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
                      senderIp: msgMap['senderIp'],
                    );
                    return _buildMessageBubble(msg);
                  },
                );
              },
            ),
          ),
        ),
        _buildInputArea(),
      ],
    );
  }

  Widget _buildMessageBubble(ChatMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    bool isGroup =
        widget.peer.ip.startsWith("GROUP:") || widget.peer.ip == "BROADCAST";

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: msg.isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          if (isGroup && !msg.isMine && msg.senderIp != null)
            Padding(
              padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
              child: Text(
                msg.senderIp!,
                style: const TextStyle(
                  fontSize: 10,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          Row(
            mainAxisAlignment: msg.isMine
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!msg.isMine)
                const CircleAvatar(
                  radius: 14,
                  backgroundColor: Colors.grey,
                  child: Icon(Icons.person, size: 16, color: Colors.white),
                ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: msg.isMine
                        ? const LinearGradient(
                            colors: [Colors.blueAccent, Color(0xFF448AFF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: msg.isMine
                        ? null
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : Colors.grey[200]),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(msg.isMine ? 20 : 0),
                      bottomRight: Radius.circular(msg.isMine ? 0 : 20),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.2 : 0.05,
                        ),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (msg.type == 'file_offer')
                        _buildFileMessage(msg)
                      else
                        Text(
                          msg.text,
                          style: TextStyle(
                            color: msg.isMine
                                ? Colors.white
                                : (isDark ? Colors.white : Colors.black87),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        "${msg.timestamp.hour}:${msg.timestamp.minute.toString().padLeft(2, '0')}",
                        style: TextStyle(
                          color: msg.isMine
                              ? Colors.white70
                              : (isDark ? Colors.white54 : Colors.black38),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (msg.isMine)
                const Icon(
                  Icons.check_circle_outline,
                  size: 14,
                  color: Colors.blueAccent,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFileMessage(ChatMessage msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timestamp = msg.timestamp.millisecondsSinceEpoch;
    final isDownloading = _transferProgress.containsKey(timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: msg.isMine
                    ? Colors.white24
                    : Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.insert_drive_file,
                color: msg.isMine ? Colors.white : Colors.blueAccent,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    msg.filename ?? "Unknown File",
                    style: TextStyle(
                      color: msg.isMine ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (msg.size != null)
                    Text(
                      "${(msg.size! / 1024 / 1024).toStringAsFixed(2)} MB",
                      style: TextStyle(
                        color: msg.isMine
                            ? Colors.white70
                            : (isDark ? Colors.white70 : Colors.black54),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (isDownloading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _transferProgress[timestamp],
              color: msg.isMine ? Colors.white : Colors.blueAccent,
              backgroundColor: msg.isMine
                  ? Colors.white24
                  : (isDark ? Colors.white10 : Colors.grey[300]),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Transferring... ${(_transferProgress[timestamp]! * 100).toInt()}%",
            style: TextStyle(
              color: msg.isMine
                  ? Colors.white70
                  : (isDark ? Colors.white70 : Colors.black54),
              fontSize: 10,
            ),
          ),
        ] else if (!msg.isMine)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: ElevatedButton.icon(
              onPressed: () => _downloadFile(msg),
              icon: const Icon(Icons.download, size: 16),
              label: const Text("Download"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildInputArea() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          top: BorderSide(color: isDark ? Colors.white10 : Colors.grey[200]!),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                color: Colors.blueAccent,
              ),
              onPressed: _sendFile,
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.05)
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                ),
                child: TextField(
                  controller: _controller,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  decoration: InputDecoration(
                    hintText: "Aa",
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white38 : Colors.grey,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 10,
                    ),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.blueAccent),
              onPressed: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }
}
