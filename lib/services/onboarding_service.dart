import 'package:shared_preferences/shared_preferences.dart';

class OnboardingService {
  static const String _keyIsSetupComplete = 'is_setup_complete';

  static Future<bool> isSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyIsSetupComplete) ?? false;
  }

  static Future<void> markSetupComplete() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSetupComplete, true);
  }

  static Future<void> resetSetup() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyIsSetupComplete, false);
  }
}
