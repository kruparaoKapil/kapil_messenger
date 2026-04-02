import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static late SharedPreferences _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static bool get isFirstRun {
    const currentVersion = '1.0.1'; // Increment this to trigger a clear-out
    final lastVersion = _prefs.getString('app_version');
    if (lastVersion != currentVersion) {
      // Don't set version here; set it AFTER initialization is complete in main.dart
      return true;
    }
    return false;
  }

  static Future<void> markFirstRunComplete() async {
    const currentVersion = '1.0.1';
    await _prefs.setString('app_version', currentVersion);
  }

  static Future<void> clearAllData() async {
    // Preserve only the version flag (if we want to avoid infinite loop)
    // Actually, it's safer to just remove everything and let main handle versioning
    await _prefs.clear();
  }

  static String get userName => _prefs.getString('userName') ?? 'User_${DateTime.now().millisecondsSinceEpoch % 10000}';

  static Future<void> setUserName(String name) async {
    await _prefs.setString('userName', name);
  }
}
