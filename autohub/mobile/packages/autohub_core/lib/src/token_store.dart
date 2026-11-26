import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Tokens {
  const Tokens(this.accessToken, this.refreshToken);
  final String accessToken;
  final String refreshToken;
}

/// Tokens live in the Android Keystore / iOS Keychain, never in plain prefs.
abstract class TokenStore {
  Future<Tokens?> read();
  Future<void> write(Tokens t);
  Future<void> clear();

  Future<String?> readExtra(String key);
  Future<void> writeExtra(String key, String? value);
}

class SecureTokenStore implements TokenStore {
  SecureTokenStore(String namespace) : _ns = namespace;
  final String _ns;
  static const _storage = FlutterSecureStorage();

  @override
  Future<Tokens?> read() async {
    final a = await _storage.read(key: '$_ns.access');
    final r = await _storage.read(key: '$_ns.refresh');
    return a == null || r == null ? null : Tokens(a, r);
  }

  @override
  Future<void> write(Tokens t) async {
    await _storage.write(key: '$_ns.access', value: t.accessToken);
    await _storage.write(key: '$_ns.refresh', value: t.refreshToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: '$_ns.access');
    await _storage.delete(key: '$_ns.refresh');
  }

  @override
  Future<String?> readExtra(String key) => _storage.read(key: '$_ns.$key');

  @override
  Future<void> writeExtra(String key, String? value) =>
      value == null ? _storage.delete(key: '$_ns.$key') : _storage.write(key: '$_ns.$key', value: value);
}

class MemoryTokenStore implements TokenStore {
  Tokens? _t;
  final _extra = <String, String>{};
  @override
  Future<Tokens?> read() async => _t;
  @override
  Future<void> write(Tokens t) async => _t = t;
  @override
  Future<void> clear() async => _t = null;
  @override
  Future<String?> readExtra(String key) async => _extra[key];
  @override
  Future<void> writeExtra(String key, String? value) async => value == null ? _extra.remove(key) : _extra[key] = value;
}
