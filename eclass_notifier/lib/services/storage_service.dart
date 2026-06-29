import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'eclass_service.dart';

class StorageService {
  static const _storage = FlutterSecureStorage();

  static const _keyUsername = 'upnet_username';
  static const _keyPassword = 'upnet_password';
  static const _keyCourseCode = 'selected_course_code';
  static const _keyCourseName = 'selected_course_name';
  static const _keyCategoryName = 'selected_category_name';
  static const _keyCategoryUrlview = 'selected_category_urlview';
  static const _keySessionCookies = 'session_cookies';
  static const _keyPreviousSlots = 'previous_slots';
  static const _keyPollInterval = 'poll_interval_minutes';

  // Credentials
  static Future<void> saveCredentials(String username, String password) async {
    await _storage.write(key: _keyUsername, value: username);
    await _storage.write(key: _keyPassword, value: password);
  }

  static Future<Map<String, String?>> getCredentials() async {
    return {
      'username': await _storage.read(key: _keyUsername),
      'password': await _storage.read(key: _keyPassword),
    };
  }

  static Future<bool> hasCredentials() async {
    final username = await _storage.read(key: _keyUsername);
    return username != null && username.isNotEmpty;
  }

  // Session cookies
  static Future<void> saveCookies(Map<String, String> cookies) async {
    await _storage.write(
      key: _keySessionCookies,
      value: cookies.entries.map((e) => '${e.key}=${e.value}').join(';'),
    );
  }

  static Future<Map<String, String>> getCookies() async {
    final raw = await _storage.read(key: _keySessionCookies);
    if (raw == null || raw.isEmpty) return {};
    return Map.fromEntries(
      raw.split(';').map((e) {
        final idx = e.indexOf('=');
        if (idx == -1) return MapEntry(e, '');
        return MapEntry(e.substring(0, idx), e.substring(idx + 1));
      }),
    );
  }

  static Future<void> clearCookies() async {
    await _storage.delete(key: _keySessionCookies);
  }

  // Selected course
  static Future<void> saveCourse(String code, String name) async {
    await _storage.write(key: _keyCourseCode, value: code);
    await _storage.write(key: _keyCourseName, value: name);
  }

  static Future<Map<String, String?>> getCourse() async {
    return {
      'code': await _storage.read(key: _keyCourseCode),
      'name': await _storage.read(key: _keyCourseName),
    };
  }

  // Selected category
  static Future<void> saveCategory(String name, String urlview) async {
    await _storage.write(key: _keyCategoryName,    value: name);
    await _storage.write(key: _keyCategoryUrlview, value: urlview);
  }

  static Future<Map<String, String?>> getCategory() async {
    return {
      'name':    await _storage.read(key: _keyCategoryName),
      'urlview': await _storage.read(key: _keyCategoryUrlview),
    };
  }

  static Future<bool> hasSelection() async {
    final code    = await _storage.read(key: _keyCourseCode);
    final urlview = await _storage.read(key: _keyCategoryUrlview);
    return code != null && urlview != null;
  }

  // Clear all
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  // Slots
  static Future<void> savePreviousSlots(List<GroupSlot> slots) async {
    final encoded = slots.map((s) => '${s.name}|||${s.current}|||${s.maximum}').join(';;;');
    await _storage.write(key: _keyPreviousSlots, value: encoded);
  }

  static Future<List<GroupSlot>> getPreviousSlots() async {
    final raw = await _storage.read(key: _keyPreviousSlots);
    if (raw == null || raw.isEmpty) return [];
    return raw.split(';;;').map((entry) {
      final parts = entry.split('|||');
      return GroupSlot(name: parts[0], current: parts[1], maximum: parts[2]);
    }).toList();
  }

  // Poll interval
  static Future<void> savePollInterval(int minutes) async {
    await _storage.write(key: _keyPollInterval, value: minutes.toString());
  }

  static Future<int> getPollInterval() async {
    final raw = await _storage.read(key: _keyPollInterval);
    return raw != null ? int.tryParse(raw) ?? 10 : 10;
  }
}