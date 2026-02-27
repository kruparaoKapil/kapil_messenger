import 'package:hive_flutter/hive_flutter.dart';

class Group {
  final String id;
  final String name;
  final List<String> peerIps;

  Group({required this.id, required this.name, required this.peerIps});

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'peerIps': peerIps};
  }

  factory Group.fromMap(Map<dynamic, dynamic> map) {
    return Group(
      id: map['id'],
      name: map['name'],
      peerIps: List<String>.from(map['peerIps']),
    );
  }
}

class GroupStore {
  static const boxName = 'groups_v1';
  static late Box box;

  static Future<void> init() async {
    box = await Hive.openBox(boxName);
  }

  static List<Group> getAllGroups() {
    return box.values.map((e) => Group.fromMap(e as Map)).toList();
  }

  static Future<void> saveGroup(Group group) async {
    await box.put(group.id, group.toMap());
  }

  static Future<void> deleteGroup(String groupId) async {
    await box.delete(groupId);
  }
}
