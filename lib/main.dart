import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'storage/settings.dart';
import 'storage/chat_store.dart';
import 'network/discovery.dart';
import 'network/tcp_server.dart';
import 'ui/chat_screen.dart';
import 'ui/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SettingsService.init();
  await ChatStore.init();

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
      title: 'Kapil Messenger',
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

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _initWindowBehavior();
    _initNetwork();
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

      ChatStore.addMessage(ip, {
        'text': data['text'] ?? data['filename'] ?? message,
        'type': data['type'] ?? 'text',
        'isMine': false,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'filename': data['filename'],
        'size': data['size'],
        'port': data['port'],
      });

      await windowManager.show();
      await windowManager.focus();
    };
    await _tcpServer.start();
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kapil Messenger'),
        centerTitle: false,
        elevation: 1,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Sidebar showing online peers on the LAN
          Container(
            width: 250,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Theme.of(context).dividerColor),
              ),
            ),
            child: _peers.isEmpty
                ? const Center(
                    child: Text(
                      "Scanning LAN...",
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _peers.length,
                    itemBuilder: (context, index) {
                      final peer = _peers[index];
                      return ListTile(
                        leading: const CircleAvatar(
                          backgroundColor: Colors.blueAccent,
                          child: Icon(Icons.computer, color: Colors.white),
                        ),
                        title: Text(
                          peer.name,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          peer.ip,
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatScreen(peer: peer),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    "Select a user to start chatting",
                    style: TextStyle(color: Colors.grey, fontSize: 18),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
