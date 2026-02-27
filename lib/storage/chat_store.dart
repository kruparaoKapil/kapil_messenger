import 'package:hive_flutter/hive_flutter.dart';

class ChatStore {
  static const boxName = 'chats_v1';
  static late Box box;

  static Future<void> init() async {
    await Hive.initFlutter();
    box = await Hive.openBox(boxName);
  }

  static List<Map<String, dynamic>> getMessages(String peerIp) {
    var raw = box.get(peerIp);
    if (raw == null) return [];

    // Hive stores dynamically, so we must safely cast the list and maps
    return List<Map<String, dynamic>>.from(
      (raw as List).map((e) {
        if (e is Map) {
          return Map<String, dynamic>.from(e);
        }
        return <String, dynamic>{};
      }),
    );
  }

  static void addMessage(String peerIp, Map<String, dynamic> msg) {
    List<Map<String, dynamic>> msgs = getMessages(peerIp);
    msgs.add(msg);
    box.put(peerIp, msgs);
  }
}
