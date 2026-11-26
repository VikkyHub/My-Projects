import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Scripted HTTP layer for tests: `routes['GET /products'] = (req) => FakeReply(200, {...})`.
class FakeReply {
  FakeReply(this.status, [this.body, this.headers = const {}]);
  final int status;
  final Object? body;
  final Map<String, String> headers;
}

class FakeAdapter implements HttpClientAdapter {
  final routes = <String, FakeReply Function(RequestOptions)>{};
  final calls = <RequestOptions>[];
  bool offline = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add(options);
    if (offline) {
      throw DioException.connectionError(requestOptions: options, reason: 'offline (FakeAdapter)');
    }
    final handler = routes['${options.method} ${options.path}'];
    final reply = handler?.call(options) ??
        FakeReply(404, {'error': {'code': 'NOT_FOUND', 'message': 'No fake route for ${options.method} ${options.path}'}});
    final text = reply.body == null ? '' : (reply.body is String ? reply.body as String : jsonEncode(reply.body));
    return ResponseBody.fromString(text, reply.status, headers: {
      Headers.contentTypeHeader: ['application/json'],
      for (final e in reply.headers.entries) e.key: [e.value],
    });
  }

  @override
  void close({bool force = false}) {}
}
