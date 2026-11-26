import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'config.dart';

typedef J = Map<String, dynamic>;

class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// One login session (member OR staff) with its own tokens.
///
/// - Access token: memory only.
/// - Refresh token: member -> Android Keystore / iOS Keychain (stays logged in);
///   staff -> memory only (signing out = closing the app), matching the web admin policy.
class Api {
  Api({required this.storageKey, required this.persist});

  final String storageKey;
  final bool persist;
  final _store = const FlutterSecureStorage();
  final _dio = Dio(BaseOptions(
    baseUrl: Config.apiUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 30),
    validateStatus: (_) => true,
  ));
  String? _access;
  String? _memRefresh;
  Future<bool>? _refreshing;
  void Function()? onExpired;

  static final _public = RegExp(r'^/(admin/)?auth/(otp/|login|verify|refresh|logout)');

  Future<String?> _getRefresh() async => persist ? await _store.read(key: storageKey) : _memRefresh;

  Future<void> setTokens(J t) async {
    _access = t['access_token'] as String?;
    final r = t['refresh_token'] as String?;
    if (persist) {
      await _store.write(key: storageKey, value: r);
    } else {
      _memRefresh = r;
    }
  }

  Future<void> clear() async {
    _access = null;
    _memRefresh = null;
    if (persist) await _store.delete(key: storageKey);
  }

  Future<bool> hasSession() async => _access != null || await _getRefresh() != null;

  Future<bool> _refresh() async {
    final rt = await _getRefresh();
    if (rt == null) return false;
    try {
      final r = await _dio.post('/auth/refresh', data: {'refresh_token': rt});
      if (r.statusCode == 200) {
        await setTokens(Map<String, dynamic>.from(r.data as Map));
        return true;
      }
    } on DioException {
      return false; // network problem: keep the session, try again later
    }
    await clear();
    onExpired?.call();
    return false;
  }

  Future<bool> _sharedRefresh() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<dynamic> request(String method, String path, {Object? data, Map<String, dynamic>? query, bool retry = true}) async {
    if (_access == null && !_public.hasMatch(path) && await _getRefresh() != null) await _sharedRefresh();
    Response r;
    try {
      r = await _dio.request(path,
          data: data,
          queryParameters: query,
          options: Options(method: method, headers: {if (_access != null) 'Authorization': 'Bearer $_access'}));
    } on DioException catch (e) {
      throw ApiError(0, e.type == DioExceptionType.connectionTimeout || e.type == DioExceptionType.connectionError
          ? "Can't reach the server. Check your internet connection."
          : 'Network error. Please try again.');
    }
    if (r.statusCode == 401 && retry && !_public.hasMatch(path) && await _getRefresh() != null) {
      if (await _sharedRefresh()) return request(method, path, data: data, query: query, retry: false);
    }
    final code = r.statusCode ?? 0;
    if (code == 204) return null;
    if (code >= 200 && code < 300) return r.data;
    throw ApiError(code, _message(r.data, code));
  }

  static String _message(dynamic body, int code) {
    if (body is Map) {
      final d = body['detail'];
      if (d is String) return d;
      if (d is List && d.isNotEmpty && d.first is Map && d.first['msg'] != null) {
        return d.first['msg'].toString().replaceFirst('Value error, ', '');
      }
    }
    return 'Something went wrong ($code)';
  }

  Future<dynamic> get(String p, {Map<String, dynamic>? query}) => request('GET', p, query: query);
  Future<dynamic> post(String p, [Object? data]) => request('POST', p, data: data);
  Future<dynamic> patch(String p, Object data) => request('PATCH', p, data: data);
  Future<dynamic> put(String p, [Object? data]) => request('PUT', p, data: data);
  Future<dynamic> delete(String p) => request('DELETE', p);

  Future<void> logout() async {
    final rt = await _getRefresh();
    if (rt != null) {
      try {
        await post('/auth/logout', {'refresh_token': rt});
      } catch (_) {}
    }
    await clear();
  }
}

/// Members (phone OTP) and staff (email + password + TOTP) never share tokens.
final memberApi = Api(storageKey: 'member_refresh', persist: true);
final staffApi = Api(storageKey: 'staff_refresh', persist: false);

/// Cached dropdown data (religions, communities, cities...).
class Master {
  static final _cache = <String, Future<List<J>>>{};
  static Future<List<J>> list(String path) => _cache[path] ??= memberApi
      .get('/master/$path')
      .then((d) => (d as List).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList())
      .catchError((Object e) {
        _cache.remove(path);
        throw e;
      });

  static String? nameOf(List<J>? list, Object? id) {
    if (id == null || list == null) return null;
    for (final e in list) {
      if (e['id'] == id) return e['name'] as String?;
    }
    return null;
  }
}
