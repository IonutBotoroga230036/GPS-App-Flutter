// Persists the currently-active recording session so the app can:
//  - route the participant straight back to the recording screen on reopen,
//  - resume recording after the OS restarts the background service,
//  - refuse to start a second, parallel session.
//
// Place at: lib/services/session_store.dart
//
// The saved session is the single source of truth for "is a session active?".
// It is written when recording starts and cleared when it stops (including the
// automatic max-duration stop). A saved session therefore always means
// "recording should be happening right now".

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SessionStore {
  static const _key = 'active_session_v1';

  /// Save (or overwrite) the active session. [data] must contain everything
  /// needed to rebuild the UI and resume the service:
  /// projectId, projectName, participantId, phoneUuid, deviceModel,
  /// config (map), geojson, startedAtMillis.
  static Future<void> save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  /// Returns the saved session, or null if none is active.
  static Future<Map<String, dynamic>?> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded as Map);
    } catch (_) {
      return null;
    }
  }

  /// Clear the active session (recording ended).
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
