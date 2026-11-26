import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import 'config.dart';
import 'response_cache.dart';
import 'token_store.dart';

/// Error envelope from the API: `{ "error": { code, message, details, requestId } }`.
class ApiException implements Exception {
  ApiException(this.status, this.code, this.message, [this.details]);
  final int? status;
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  bool get isNetwork => code == 'NETWORK';

  /// Field → message for VALIDATION_FAILED.
  Map<String, String> get fieldErrors =>
      ((details?['fields'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));

  @override
  String toString() => message;
}

/// A GET result that may have come from the offline cache.
class CachedResult<T> {
  const CachedResult(this.data, {required this.fromCache, this.savedAt});
  final T data;
  final bool fromCache;
  final DateTime? savedAt;
}

class ApiClient {
  ApiClient({required this.config, required this.tokens, required this.cache, Dio? dio, this.onLoggedOut})
      : _dio = dio ?? Dio() {
    _dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      // 304 Not Modified counts as success; 4xx/5xx raise DioException
      ..validateStatus = ((s) => s != null && s < 400)
      ..responseType = ResponseType.plain;
    _dio.interceptors.add(InterceptorsWrapper(onRequest: _onRequest));
  }

  final AppConfig config;
  final TokenStore tokens;
  final ResponseCache cache;
  final Dio _dio;
  final void Function()? onLoggedOut;

  String language = 'en';
  String? vendorId;
  Completer<bool>? _refreshing;

  Future<void> _onRequest(RequestOptions o, RequestInterceptorHandler h) async {
    o.baseUrl = config.apiBaseUrl;
    o.headers['X-Client-App'] = config.clientApp;
    o.headers['Accept-Language'] = language;
    if (vendorId != null) o.headers['X-Vendor-Id'] = vendorId;
    if (o.extra['auth'] != false) {
      final t = await tokens.read();
      if (t != null) o.headers['Authorization'] = 'Bearer ${t.accessToken}';
    }
    h.next(o);
  }

  // ---------------- public API ----------------

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body, Map<String, String>? headers]) =>
      _send('POST', path, body: body ?? const {}, headers: headers);

  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);

  /// Stale-while-revalidate GET backed by the offline cache. Uses `If-None-Match`, so an unchanged
  /// listing costs a few hundred bytes. With no network, returns the last saved copy.
  Future<CachedResult<dynamic>> getCached(String path, {Map<String, dynamic>? query}) async {
    final key = '${config.clientApp}|$language|$path?${_canonical(query)}';
    final cached = await cache.get(key);
    try {
      final res = await _raw('GET', path, query: query, headers: {if (cached?.etag != null) 'If-None-Match': cached!.etag!});
      if (res.statusCode == 304 && cached != null) {
        await cache.touch(key);
        return CachedResult(jsonDecode(cached.body), fromCache: false, savedAt: cached.savedAt);
      }
      final body = res.data as String;
      await cache.put(key, body, res.headers.value('etag'));
      return CachedResult(jsonDecode(body), fromCache: false);
    } on ApiException catch (e) {
      if (e.isNetwork && cached != null) {
        return CachedResult(jsonDecode(cached.body), fromCache: true, savedAt: cached.savedAt);
      }
      rethrow;
    }
  }

  // ---------------- internals ----------------

  Future<dynamic> _send(String method, String path, {Map<String, dynamic>? query, Object? body, Map<String, String>? headers}) async {
    final res = await _raw(method, path, query: query, body: body, headers: headers);
    final text = res.data as String?;
    return text == null || text.isEmpty ? null : jsonDecode(text);
  }

  Future<Response<dynamic>> _raw(String method, String path,
      {Map<String, dynamic>? query, Object? body, Map<String, String>? headers, bool retried = false}) async {
    try {
      return await _dio.request<dynamic>(path,
          queryParameters: query == null ? null : (Map.of(query)..removeWhere((_, v) => v == null)),
          data: body,
          options: Options(method: method, headers: headers, contentType: body == null ? null : Headers.jsonContentType));
    } on DioException catch (e) {
      final res = e.response;
      if (res == null) throw ApiException(null, 'NETWORK', 'No internet connection');
      final err = _parseError(res);
      // Access token expired → refresh once (single-flight across concurrent requests), then retry.
      if (res.statusCode == 401 && err.code == 'TOKEN_EXPIRED' && !retried && await _refresh()) {
        return _raw(method, path, query: query, body: body, headers: headers, retried: true);
      }
      if (res.statusCode == 401 && !path.startsWith('/auth/')) {
        await tokens.clear();
        onLoggedOut?.call();
      }
      throw err;
    }
  }

  Future<bool> _refresh() async {
    if (_refreshing != null) return _refreshing!.future;
    final c = _refreshing = Completer<bool>();
    try {
      final t = await tokens.read();
      if (t == null) return false;
      final res = await _dio.post<dynamic>('/auth/refresh',
          data: {'refreshToken': t.refreshToken}, options: Options(extra: {'auth': false}, contentType: Headers.jsonContentType));
      final j = jsonDecode(res.data as String) as Map<String, dynamic>;
      await tokens.write(Tokens(j['accessToken'] as String, j['refreshToken'] as String));
      c.complete(true);
    } catch (_) {
      c.complete(false);
    } finally {
      _refreshing = null;
    }
    return c.future;
  }

  ApiException _parseError(Response<dynamic> res) {
    try {
      final j = jsonDecode(res.data as String) as Map<String, dynamic>;
      final e = j['error'] as Map<String, dynamic>;
      return ApiException(res.statusCode, e['code'] as String, e['message'] as String? ?? 'Error', e['details'] as Map<String, dynamic>?);
    } catch (_) {
      return ApiException(res.statusCode, 'HTTP_${res.statusCode}', 'Unexpected server response');
    }
  }

  static String _canonical(Map<String, dynamic>? q) {
    if (q == null) return '';
    final keys = q.keys.where((k) => q[k] != null).toList()..sort();
    return keys.map((k) => '$k=${q[k]}').join('&');
  }
}
