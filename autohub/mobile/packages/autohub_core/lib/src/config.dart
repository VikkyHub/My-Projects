import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the API lives.
///
/// Precedence: value saved on the login screen (testing on a real phone) →
/// `--dart-define=API_URL=...` → emulator default.
class AppConfig {
  AppConfig._(this._prefs, this.clientApp);

  static const _key = 'api_base_url';
  static const _defined = String.fromEnvironment('API_URL');

  final SharedPreferences? _prefs;

  /// `customer` or `vendor` — sent as X-Client-App and baked into tokens by the server.
  final String clientApp;

  static Future<AppConfig> load(String clientApp) async {
    return AppConfig._(await SharedPreferences.getInstance(), clientApp);
  }

  /// For tests.
  @visibleForTesting
  factory AppConfig.fixed(String baseUrl, String clientApp) => _FixedConfig(baseUrl, clientApp);

  String get apiBaseUrl {
    final saved = _prefs?.getString(_key);
    if (saved != null && saved.isNotEmpty) return saved;
    if (_defined.isNotEmpty) return _defined;
    // Android emulator reaches the host machine on 10.0.2.2; iOS simulator on localhost.
    final isAndroid = !kIsWeb && Platform.isAndroid;
    return isAndroid ? 'http://10.0.2.2:3000/v1' : 'http://localhost:3000/v1';
  }

  Future<void> setApiBaseUrl(String url) async {
    var u = url.trim();
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    if (!u.endsWith('/v1')) u = '$u/v1';
    await _prefs?.setString(_key, u);
  }
}

class _FixedConfig extends AppConfig {
  _FixedConfig(this._url, String clientApp) : super._(null, clientApp);
  final String _url;
  @override
  String get apiBaseUrl => _url;
  @override
  Future<void> setApiBaseUrl(String url) async {}
}
