import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'config.dart';

/// One WebSocket per app. Server events say *what changed*; screens refetch via REST.
/// Reconnects with backoff.
class Realtime {
  Realtime._();
  static final instance = Realtime._();

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _events.stream;
  Stream<Map<String, dynamic>> on(Set<String> types) => events.where((e) => types.contains(e['type']));

  WebSocketChannel? _ch;
  StreamSubscription? _sub;
  Timer? _retry;
  bool _running = false;
  int _backoff = 1;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  void stop() {
    _running = false;
    _retry?.cancel();
    _sub?.cancel();
    _ch?.sink.close();
    _ch = null;
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final r = await memberApi.post('/auth/ws-ticket') as Map;
      final ch = WebSocketChannel.connect(Uri.parse(Config.ws(r['ticket'] as String)));
      _ch = ch;
      await ch.ready;
      _backoff = 1;
      _sub = ch.stream.listen(
        (raw) {
          final ev = jsonDecode(raw as String) as Map<String, dynamic>;
          if (ev['type'] == 'ping') {
            ch.sink.add('pong');
            return;
          }
          _events.add(ev);
        },
        onDone: _scheduleRetry,
        onError: (_) => _scheduleRetry(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _scheduleRetry() {
    if (!_running) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), _connect);
    _backoff = (_backoff * 2).clamp(1, 30);
  }
}
