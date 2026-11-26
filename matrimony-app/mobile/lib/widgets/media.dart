import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../core/config.dart';
import '../core/theme.dart';

/// Tap the mic to record; tap stop; then send or discard. Max 2 minutes. AAC (.m4a).
class VoiceRecorder extends StatefulWidget {
  const VoiceRecorder({super.key, required this.onSend, this.enabled = true});
  final Future<void> Function(File file, int seconds) onSend;
  final bool enabled;
  @override
  State<VoiceRecorder> createState() => _VoiceRecorderState();
}

class _VoiceRecorderState extends State<VoiceRecorder> {
  static const maxSeconds = 120;
  final _rec = AudioRecorder();
  Timer? _timer;
  int _secs = 0;
  String? _path;
  bool _recording = false;

  @override
  void dispose() {
    _timer?.cancel();
    _rec.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _rec.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Allow microphone access to send voice notes')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _rec.start(const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1, bitRate: 64000), path: path);
    setState(() {
      _recording = true;
      _secs = 0;
      _path = null;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _secs++);
      if (_secs >= maxSeconds) _stop();
    });
  }

  Future<void> _stop() async {
    _timer?.cancel();
    final p = await _rec.stop();
    setState(() {
      _recording = false;
      _path = p;
    });
  }

  @override
  Widget build(BuildContext context) {
    final mmss = '${_secs ~/ 60}:${(_secs % 60).toString().padLeft(2, '0')}';
    if (!_recording && _path == null) {
      return IconButton.outlined(
        tooltip: 'Record a voice note',
        onPressed: widget.enabled ? _start : null,
        style: IconButton.styleFrom(side: const BorderSide(color: C.line), foregroundColor: C.brand600),
        icon: const Icon(Icons.mic_rounded),
      );
    }
    return Expanded(
      child: Container(
        padding: const EdgeInsets.only(left: 14, right: 4),
        height: 48,
        decoration: BoxDecoration(color: C.brand50, borderRadius: BorderRadius.circular(999), border: Border.all(color: C.brand100)),
        child: Row(children: [
          if (_recording) ...[
            const Icon(Icons.fiber_manual_record_rounded, color: Colors.red, size: 14),
            const SizedBox(width: 6),
            Text(mmss, style: const TextStyle(fontWeight: FontWeight.w700, color: C.brand800)),
            const SizedBox(width: 8),
            const Expanded(child: Text('Recording…', style: TextStyle(fontSize: 12, color: C.muted))),
            IconButton(tooltip: 'Stop', onPressed: _stop, icon: const Icon(Icons.stop_circle_rounded, color: Colors.red, size: 30)),
          ] else ...[
            Expanded(child: VoicePlayer(localPath: _path, seconds: _secs)),
            IconButton(tooltip: 'Discard', onPressed: () => setState(() => _path = null), icon: const Icon(Icons.delete_outline_rounded, color: C.muted)),
            IconButton.filled(
              tooltip: 'Send voice note',
              style: IconButton.styleFrom(backgroundColor: C.brand600),
              onPressed: () async {
                final f = File(_path!);
                setState(() => _path = null);
                await widget.onSend(f, _secs.clamp(1, maxSeconds));
              },
              icon: const Icon(Icons.send_rounded, size: 18),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Compact play/pause + progress for a voice note (remote URL or local file).
class VoicePlayer extends StatefulWidget {
  const VoicePlayer({super.key, this.url, this.localPath, this.seconds, this.dark = false});
  final String? url, localPath;
  final int? seconds;
  final bool dark;
  @override
  State<VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<VoicePlayer> {
  final _p = AudioPlayer();
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(_p.onPositionChanged.listen((d) => setState(() => _pos = d)));
    _subs.add(_p.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(_p.onPlayerStateChanged.listen((s) => setState(() => _playing = s == PlayerState.playing)));
    _subs.add(_p.onPlayerComplete.listen((_) => setState(() => _pos = Duration.zero)));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _p.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = _dur.inMilliseconds > 0 ? _dur : Duration(seconds: widget.seconds ?? 0);
    final fg = widget.dark ? Colors.white : C.brand700;
    final v = total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final left = total - _pos;
    return Row(children: [
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, color: fg, size: 32),
        onPressed: () async {
          if (_playing) return _p.pause();
          final src = widget.localPath != null ? DeviceFileSource(widget.localPath!) : UrlSource(Config.media(widget.url)!);
          await _p.play(src);
        },
      ),
      Expanded(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: LinearProgressIndicator(value: v, minHeight: 4, color: fg, backgroundColor: fg.withValues(alpha: .2)),
        ),
      ),
      const SizedBox(width: 8),
      Text('${left.inSeconds ~/ 60}:${(left.inSeconds % 60).toString().padLeft(2, '0')}',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: widget.dark ? Colors.white70 : C.muted)),
    ]);
  }
}
