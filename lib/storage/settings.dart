import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static String get userName => _prefs.getString('userName') ?? 'Kapil';

  static Future<void> setUserName(String name) async {
    await _prefs.setString('userName', name);
  }
}
