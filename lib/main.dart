import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:window_manager/window_manager.dart';
import 'package:google_fonts/google_fonts.dart';
import 'storage/settings.dart';
import 'storage/chat_store.dart';
import 'storage/group_store.dart';
import 'network/discovery.dart';
import 'network/tcp_server.dart';
import 'network/file_transfer.dart';
import 'ui/chat_screen.dart'; // This now contains ChatView
import 'ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SettingsService.init();
  await ChatStore.init();
  await GroupStore.init();

  await windowManager.ensureInitialized();
  WindowOptions windowOptions = const WindowOptions(
    size: Size(900, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );

  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lords Church Messenger',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blueAccent,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WindowListener {
  final DiscoveryService _discovery = DiscoveryService();
  final TcpServer _tcpServer = TcpServer();

  List<Peer> _peers = [];
  List<Group> _groups = [];

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindowBehavior();
    _initNetwork();
    _loadGroups();
  }

  void _loadGroups() {
    setState(() {
      _groups = GroupStore.getAllGroups();
    });
  }

  Future<void> _initWindowBehavior() async {
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  Peer? _selectedPeer;
  final Map<String, int> _unreadCounts = {};

  Future<void> _initNetwork() async {
    _discovery.onPeersUpdated = (peers) {
      if (mounted) {
        setState(() {
          _peers = peers;
        });
      }
    };
    await _discovery.start();

    _tcpServer.onMessageReceived = (ip, message) async {
      print("Message from $ip: $message");

      Map<String, dynamic> data = {};
      try {
        data = jsonDecode(message);
      } catch (e) {
        data = {'type': 'text', 'text': message};
      }

      final chatKey = data['isBroadcast'] == true
          ? "BROADCAST"
          : (data['groupId'] != null ? "GROUP:${data['groupId']}" : ip);

      // Self-healing Group sync: If we get a group message but don't have the group locally
      if (data['groupId'] != null &&
          data['groupId'] != "BROADCAST" &&
          data['groupName'] != null) {
        final existingGroups = GroupStore.getAllGroups();
        if (!existingGroups.any((g) => g.id == data['groupId'])) {
          await GroupStore.saveGroup(
            Group(
              id: data['groupId'],
              name: data['groupName'],
              peerIps: List<String>.from(data['peerIps'] ?? []),
            ),
          );
          _loadGroups(); // Refresh sidebar
        }
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;

      ChatStore.addMessage(chatKey, {
        'text': data['text'] ?? data['filename'] ?? message,
        'type': data['type'] ?? 'text',
        'isMine': false,
        'senderIp': ip,
        'timestamp': timestamp,
        'filename': data['filename'],
        'size': data['size'],
        'port': data['port'],
      });

      if (data['type'] == 'file_offer' && data['port'] != null && data['filename'] != null) {
        String downloadId = timestamp.toString();
        FileTransferService.receiveFile(
          ip,
          data['port'],
          data['filename'],
          data['size'] ?? 0,
          downloadId,
        ).then((file) {
          if (file != null) {
            ChatStore.updateMessage(chatKey, timestamp, {'savedPath': file.path});
          }
        });
      }

      if (mounted) {
        setState(() {
          if (_selectedPeer?.ip != chatKey) {
            _unreadCounts[chatKey] = (_unreadCounts[chatKey] ?? 0) + 1;
          }
        });
      }

      await windowManager.show();
      await windowManager.focus();

      // Self-healing discovery: If this IP is not in our online list, ping it directly via UDP
      if (!_peers.any((p) => p.ip == ip)) {
        await _discovery.pingPeer(ip);
      }
    };
    await _tcpServer.start();
  }

  void _showCreateGroupDialog() {
    final nameController = TextEditingController();
    List<String> selectedIps = [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text("Create Group"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: "Group Name"),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "Select Members:",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(
                    height: 200,
                    width: 300,
                    child: ListView.builder(
                      itemCount: _peers.length,
                      itemBuilder: (context, index) {
                        final peer = _peers[index];
                        return CheckboxListTile(
                          title: Text(peer.name),
                          value: selectedIps.contains(peer.ip),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedIps.add(peer.ip);
                              } else {
                                selectedIps.remove(peer.ip);
                              }
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty &&
                        selectedIps.isNotEmpty) {
                      final group = Group(
                        id: DateTime.now().millisecondsSinceEpoch.toString(),
                        name: nameController.text,
                        peerIps: selectedIps,
                      );
                      await GroupStore.saveGroup(group);
                      _loadGroups();
                      Navigator.pop(context);
                    }
                  },
                  child: const Text("Create"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildSidebarHeader(String title, {VoidCallback? onAdd}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white54 : Colors.black45,
              letterSpacing: 1.2,
            ),
          ),
          if (onAdd != null)
            IconButton(
              icon: const Icon(
                Icons.add_circle_outline,
                size: 16,
                color: Colors.blueAccent,
              ),
              onPressed: onAdd,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }

  Widget _buildPeerTile(Peer peer, {IconData icon = Icons.person}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final unread = _unreadCounts[peer.ip] ?? 0;
    final isSelected = _selectedPeer?.ip == peer.ip;

    return ListTile(
      selected: isSelected,
      selectedTileColor: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.blue.withValues(alpha: 0.05),
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isSelected
                ? Colors.blueAccent
                : (isDark ? Colors.grey[800] : Colors.grey[300]),
            child: Icon(
              icon,
              size: 18,
              color: isDark ? Colors.white70 : Colors.black54,
            ),
          ),
          if (unread > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  unread.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ),
        ],
      ),
      title: Text(
        peer.name,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: (icon != Icons.group && peer.ip != "BROADCAST")
          ? Text(
              peer.ip,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
            )
          : null,
      onTap: () {
        setState(() {
          _selectedPeer = peer;
          _unreadCounts[peer.ip] = 0;
        });
      },
      onLongPress: () {
        if (peer.ip.startsWith("GROUP:")) {
          final groupId = peer.ip.replaceFirst("GROUP:", "");
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text("Delete Group"),
              content: Text("Are you sure you want to delete ${peer.name}?"),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel"),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await GroupStore.deleteGroup(groupId);
                    if (_selectedPeer?.ip == peer.ip) {
                      setState(() => _selectedPeer = null);
                    }
                    _loadGroups();
                  },
                  child: const Text("Delete", style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildRecentChats() {
    return ValueListenableBuilder(
      valueListenable: ChatStore.box.listenable(),
      builder: (context, Box box, _) {
        final allKeys = box.keys.cast<String>().toList();
        final onlineIps = _peers.map((p) => p.ip).toList();
        final recentIps = allKeys.where((key) {
          return !key.startsWith("GROUP:") &&
              key != "BROADCAST" &&
              !onlineIps.contains(key);
        }).toList();

        if (recentIps.isEmpty) return const SizedBox.shrink();

        return Column(
          children: recentIps.map((ip) {
            final peer = Peer(ip: ip, name: ip, lastSeen: DateTime.now());
            return _buildPeerTile(peer, icon: Icons.history);
          }).toList(),
        );
      },
    );
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _discovery.stop();
    _tcpServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarColor = isDark ? const Color(0xFF1F2C33) : Colors.grey[100];

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          Container(
            width: 300,
            decoration: BoxDecoration(
              color: sidebarColor,
              border: Border(
                right: BorderSide(
                  color: isDark ? const Color(0xFF2A3942) : Colors.grey[300]!,
                ),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  color: sidebarColor,
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: Colors.blueAccent,
                        child: Icon(Icons.account_circle, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Lords Church Messenger",
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.settings,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    children: [
                      _buildPeerTile(
                        Peer(
                          ip: "BROADCAST",
                          name: "Broadcast Room",
                          lastSeen: DateTime.now(),
                        ),
                        icon: Icons.broadcast_on_home,
                      ),
                      _buildSidebarHeader(
                        "GROUPS",
                        onAdd: _showCreateGroupDialog,
                      ),
                      ..._groups.map(
                        (g) => _buildPeerTile(
                          Peer(
                            ip: "GROUP:${g.id}",
                            name: g.name,
                            lastSeen: DateTime.now(),
                          ),
                          icon: Icons.group,
                        ),
                      ),
                      _buildSidebarHeader("RECENT CHATS"),
                      _buildRecentChats(),
                      _buildSidebarHeader("ONLINE USERS (${_peers.length})"),
                      ..._peers.map((p) => _buildPeerTile(p)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Chat Area
          Expanded(
            child: _selectedPeer == null
                ? Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(32),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withOpacity(0.05)
                                  : Colors.blue.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.chat_bubble_outline,
                              size: 64,
                              color: isDark
                                  ? Colors.white24
                                  : Colors.blueAccent.withOpacity(0.3),
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            "Lords Church Messenger",
                            style: GoogleFonts.inter(
                              fontSize: 24,
                              color: isDark ? Colors.white70 : Colors.black87,
                              fontWeight: FontWeight.w300,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Select a conversation to start chatting securely.",
                            style: GoogleFonts.inter(
                              color: isDark ? Colors.white38 : Colors.black45,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ChatView(
                    key: ValueKey(_selectedPeer!.ip),
                    peer: _selectedPeer!,
                  ),
          ),
        ],
      ),
    );
  }
}
