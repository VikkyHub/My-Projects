import 'package:autohub_core/autohub_core.dart';
import 'package:autohub_core/src/testing.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeAdapter http;
  late MemoryTokenStore tokens;
  late ApiClient api;
  var loggedOut = 0;

  setUp(() {
    http = FakeAdapter();
    tokens = MemoryTokenStore();
    loggedOut = 0;
    api = ApiClient(
      config: AppConfig.fixed('http://api.test/v1', 'customer'),
      tokens: tokens,
      cache: MemoryResponseCache(),
      dio: Dio()..httpClientAdapter = http,
      onLoggedOut: () => loggedOut++,
    );
  });

  test('sends app, language and auth headers', () async {
    await tokens.write(const Tokens('access-1', 'refresh-1'));
    api.language = 'mr';
    http.routes['GET /me'] = (_) => FakeReply(200, {'id': 'u1'});
    await api.get('/me');
    final h = http.calls.single.headers;
    expect(h['X-Client-App'], 'customer');
    expect(h['Accept-Language'], 'mr');
    expect(h['Authorization'], 'Bearer access-1');
  });

  test('parses the error envelope into ApiException', () async {
    http.routes['POST /auth/otp/verify'] = (_) => FakeReply(422, {
          'error': {'code': 'OTP_INVALID', 'message': 'Incorrect code.', 'details': {'attemptsLeft': 3}}
        });
    late ApiException e;
    try {
      await api.post('/auth/otp/verify', {});
      fail('expected ApiException');
    } on ApiException catch (err) {
      e = err;
    }
    expect(e.status, 422);
    expect(e.code, 'OTP_INVALID');
    expect(e.details!['attemptsLeft'], 3);
  });

  test('getCached revalidates with If-None-Match and serves 304 from cache', () async {
    var hits = 0;
    http.routes['GET /products'] = (req) {
      hits++;
      if (req.headers['If-None-Match'] == 'W/"v1"') return FakeReply(304);
      return FakeReply(200, {'data': [{'id': 'p1'}]}, {'etag': 'W/"v1"'});
    };
    final first = await api.getCached('/products', query: {'q': 'brake'});
    final second = await api.getCached('/products', query: {'q': 'brake'});
    expect(hits, 2);
    expect(http.calls.last.headers['If-None-Match'], 'W/"v1"');
    expect((second.data as Map)['data'], (first.data as Map)['data']);
    expect(second.fromCache, isFalse);
  });

  test('getCached falls back to the saved copy when offline', () async {
    http.routes['GET /products'] = (_) => FakeReply(200, {'data': [{'id': 'p1'}]}, {'etag': 'x'});
    await api.getCached('/products');
    http.offline = true;
    final r = await api.getCached('/products');
    expect(r.fromCache, isTrue);
    expect((r.data as Map)['data'], hasLength(1));

    // Nothing cached for this query → the network error surfaces.
    expect(() => api.getCached('/products', query: {'q': 'other'}), throwsA(isA<ApiException>().having((e) => e.isNetwork, 'isNetwork', true)));
  });

  test('refreshes an expired access token once, even for concurrent requests', () async {
    await tokens.write(const Tokens('old', 'rt-1'));
    var refreshes = 0;
    http.routes['POST /auth/refresh'] = (_) {
      refreshes++;
      return FakeReply(200, {'accessToken': 'new', 'refreshToken': 'rt-2'});
    };
    http.routes['GET /me'] = (req) => req.headers['Authorization'] == 'Bearer new'
        ? FakeReply(200, {'id': 'u1'})
        : FakeReply(401, {'error': {'code': 'TOKEN_EXPIRED', 'message': 'Session expired.'}});

    final results = await Future.wait([api.get('/me'), api.get('/me'), api.get('/me')]);
    expect(results.every((r) => (r as Map)['id'] == 'u1'), isTrue);
    expect(refreshes, 1);
    expect((await tokens.read())!.refreshToken, 'rt-2');
  });

  test('a rejected refresh logs the user out', () async {
    await tokens.write(const Tokens('old', 'stolen'));
    http.routes['POST /auth/refresh'] = (_) => FakeReply(401, {'error': {'code': 'UNAUTHENTICATED', 'message': 'Please log in again.'}});
    http.routes['GET /me'] = (_) => FakeReply(401, {'error': {'code': 'TOKEN_EXPIRED', 'message': 'Session expired.'}});
    await expectLater(api.get('/me'), throwsA(isA<ApiException>()));
    expect(await tokens.read(), isNull);
    expect(loggedOut, 1);
  });

  test('formatPaise uses Indian grouping', () {
    expect(formatPaise(149900), '₹1,499');
    expect(formatPaise(12345678), '₹1,23,456.78');
    expect(formatPaise(10000000000), '₹10,00,00,000');
    expect(parseRupeesToPaise('1,499.50'), 149950);
    expect(parseRupeesToPaise('abc'), isNull);
  });
}
