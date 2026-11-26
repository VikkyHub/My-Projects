import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/labels.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../widgets/media.dart';
import '../../widgets/translate.dart';
import '../../widgets/ui.dart';

/// Shared state so the floating button knows when the team has replied.
final supportView = ValueNotifier<J?>(null);

Future<void> refreshSupport() async {
  try {
    supportView.value = Map<String, dynamic>.from(await memberApi.get('/support') as Map);
  } catch (_) {}
}

bool teamReplied(J? v) {
  final t = v?['ticket'] as Map?;
  final msgs = v?['messages'] as List? ?? [];
  return t?['status'] == 'answered' && msgs.isNotEmpty && (msgs.last as Map)['sender'] == 'staff';
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => const Scaffold(body: SafeArea(bottom: false, child: HelpChat()));
}

class HelpChat extends StatefulWidget {
  const HelpChat({super.key, this.onClose});
  final VoidCallback? onClose;
  @override
  State<HelpChat> createState() => _HelpChatState();
}

class _HelpChatState extends State<HelpChat> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  bool busy = false;
  String? err;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    refreshSupport().then((_) => _toBottom());
    _sub = Realtime.instance.on({'support'}).listen((_) => refreshSupport().then((_) => _toBottom()));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _run(Future<dynamic> Function() call) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      supportView.value = Map<String, dynamic>.from(await call() as Map);
      _toBottom();
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _say({String? body, String? intent}) => _run(() => memberApi.post('/support/messages', {'body': body ?? '', 'intent': intent}));
  void _escalate() => _run(() => memberApi.post('/support/escalate'));

  Future<void> _upload(String kind, File f, {int? seconds}) => _run(() async => memberApi.post(
      '/support/attachments',
      FormData.fromMap({
        'kind': kind,
        if (seconds != null) 'duration_s': '$seconds',
        'file': await MultipartFile.fromFile(f.path, filename: kind == 'voice' ? 'voice.m4a' : 'photo.jpg'),
      })));

  Future<void> _pickPhoto() async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_rounded), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_rounded), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ]),
      ),
    );
    if (src == null) return;
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2000, imageQuality: 88);
    if (x != null) await _upload('photo', File(x.path));
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<J?>(
        valueListenable: supportView,
        builder: (_, v, _) {
          final msgs = ((v?['messages'] as List?) ?? []).cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          final status = (v?['ticket'] as Map?)?['status'] as String? ?? 'bot';
          final (label, fg, bg, icon) = switch (status) {
            'waiting_team' => ('Waiting for our team', C.amber, C.amberBg, Icons.schedule_rounded),
            'answered' => ('Team replied', C.green, C.greenBg, Icons.check_circle_rounded),
            'closed' => ('Closed', C.muted, C.sand, Icons.check_circle_rounded),
            _ => ('Assistant', C.sky, C.skyBg, Icons.smart_toy_rounded),
          };
          final lastBot = msgs.lastWhere((m) => m['sender'] != 'member', orElse: () => {});
          return Column(children: [
            Container(
              decoration: const BoxDecoration(gradient: C.heroGradient),
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
              child: Row(children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.smart_toy_rounded, color: C.gold200),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Help & support', style: display(19, color: Colors.white)),
                    const SizedBox(height: 4),
                    Pill(label, icon: icon, fg: fg, bg: bg),
                  ]),
                ),
                const LanguagePicker(light: true),
                IconButton(
                  onPressed: widget.onClose ?? () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
              ]),
            ),
            Expanded(
              child: PatternBg(
                child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(14, 14, 14, 14), children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(color: C.tealBg, borderRadius: BorderRadius.circular(16)),
                    child: const Text('Our team will never ask for your OTP, password or payment details here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Color(0xFF134E4A))),
                  ),
                  _botBubble('Assistant', v?['welcome'] as String? ?? 'Hi! How can I help you today?', staff: false),
                  if (msgs.isEmpty && v != null) _chips(((v['suggestions'] as List?) ?? []).cast<Map>()),
                  for (final m in msgs) ..._message(m, identical(m['id'], lastBot['id'])),
                  if (busy) const Padding(padding: EdgeInsets.only(left: 48, top: 4), child: Text('Typing…', style: TextStyle(fontSize: 12, color: C.muted))),
                  if (status == 'waiting_team')
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: Pill("A team member will reply here — you'll be notified", icon: Icons.schedule_rounded, fg: C.amber, bg: C.amberBg)),
                    ),
                ]),
              ),
            ),
            if (err != null) Container(width: double.infinity, color: C.redBg, padding: const EdgeInsets.all(10), child: Text(err!, style: const TextStyle(color: C.red, fontSize: 13))),
            SafeArea(
              top: false,
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Column(children: [
                  Row(children: [
                    IconButton.outlined(
                      tooltip: 'Send a photo or screenshot',
                      onPressed: busy ? null : _pickPhoto,
                      style: IconButton.styleFrom(side: const BorderSide(color: C.line), foregroundColor: C.brand600),
                      icon: const Icon(Icons.add_photo_alternate_rounded),
                    ),
                    const SizedBox(width: 6),
                    VoiceRecorder(enabled: !busy, onSend: (f, s) => _upload('voice', f, seconds: s)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _text,
                        minLines: 1,
                        maxLines: 4,
                        textCapitalization: TextCapitalization.sentences,
                        onSubmitted: (_) => _sendText(),
                        decoration: InputDecoration(
                          hintText: 'Type your question…',
                          filled: true,
                          fillColor: C.sand.withValues(alpha: .6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(onPressed: busy ? null : _sendText, style: IconButton.styleFrom(backgroundColor: C.brand600), icon: const Icon(Icons.send_rounded)),
                  ]),
                  Align(
                    alignment: Alignment.centerRight,
                    child: status == 'waiting_team'
                        ? TextButton(onPressed: () => _run(() => memberApi.post('/support/close')), child: const Text('My problem is solved — close'))
                        : TextButton.icon(onPressed: busy ? null : _escalate, icon: const Icon(Icons.support_agent_rounded, size: 18), label: const Text('Talk to a person')),
                  ),
                ]),
              ),
            ),
          ]);
        },
      );

  void _sendText() {
    final t = _text.text.trim();
    if (t.isEmpty || busy) return;
    _text.clear();
    _say(body: t);
  }

  Widget _chips(List<Map> items) => Padding(
        padding: const EdgeInsets.only(left: 46, bottom: 12),
        child: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final c in items)
            ActionChip(
              label: Text(c['title'] as String),
              labelStyle: const TextStyle(color: C.brand700, fontWeight: FontWeight.w600),
              backgroundColor: Colors.white,
              side: const BorderSide(color: C.brand200),
              onPressed: busy ? null : () => c['key'] == 'talk' ? _escalate() : _say(intent: c['key'] as String),
            ),
        ]),
      );

  Widget _botBubble(String name, String text, {required bool staff, String? at, Widget? extra}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: staff ? C.gold400 : C.brand700,
            child: Icon(staff ? Icons.headset_mic_rounded : Icons.smart_toy_rounded, size: 17, color: staff ? C.brand950 : Colors.white),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              decoration: BoxDecoration(
                color: staff ? C.gold50 : Colors.white,
                border: Border.all(color: staff ? C.gold200 : C.line),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22), bottomRight: Radius.circular(22), bottomLeft: Radius.circular(6)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name.toUpperCase(), style: const TextStyle(fontSize: 10.5, letterSpacing: .8, fontWeight: FontWeight.w800, color: C.muted)),
                const SizedBox(height: 4),
                RichBody(text),
                TranslateButton(text),
                ?extra,
                if (at != null) Align(alignment: Alignment.centerRight, child: Text(clock(at), style: const TextStyle(fontSize: 11, color: C.muted))),
              ]),
            ),
          ),
        ]),
      );

  List<Widget> _message(J m, bool last) {
    if (m['sender'] == 'member') {
      return [
        Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: const BoxDecoration(
              gradient: C.buttonGradient,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(22), topRight: Radius.circular(22), bottomLeft: Radius.circular(22), bottomRight: Radius.circular(6)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (m['kind'] == 'photo')
                ClipRRect(borderRadius: BorderRadius.circular(14), child: CachedNetworkImage(imageUrl: Config.media(m['media_url'] as String)!, height: 200, fit: BoxFit.cover))
              else if (m['kind'] == 'voice')
                SizedBox(width: 220, child: VoicePlayer(url: m['media_url'] as String, seconds: m['duration_s'] as int?, dark: true))
              else
                Text(m['body'] as String? ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
              const SizedBox(height: 2),
              Text(clock(m['created_at'] as String), style: const TextStyle(fontSize: 11, color: Colors.white70)),
            ]),
          ),
        ),
      ];
    }
    final meta = (m['meta'] as Map?) ?? {};
    final staff = m['sender'] == 'staff';
    return [
      _botBubble(
        staff ? '${m['staff_name'] ?? 'Support'} · Support team' : 'Assistant',
        m['body'] as String? ?? '',
        staff: staff,
        at: m['created_at'] as String,
        extra: meta['ask_feedback'] == true && last
            ? Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Wrap(spacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  const Text('Did this help?', style: TextStyle(fontSize: 12, color: C.muted)),
                  ActionChip(
                    avatar: const Icon(Icons.thumb_up_alt_rounded, size: 15, color: C.green),
                    label: const Text('Yes'),
                    onPressed: () => _run(() => memberApi.post('/support/feedback', {'message_id': m['id'], 'helpful': true})),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.thumb_down_alt_rounded, size: 15, color: C.brand600),
                    label: const Text('No, talk to a person'),
                    onPressed: () => _run(() => memberApi.post('/support/feedback', {'message_id': m['id'], 'helpful': false})),
                  ),
                ]),
              )
            : null,
      ),
      if (last && (meta['suggestions'] as List?)?.isNotEmpty == true) _chips((meta['suggestions'] as List).cast<Map>()),
    ];
  }
}

/// Floating "Need help?" button for every member tab; opens the chat as a sheet.
class HelpFab extends StatefulWidget {
  const HelpFab({super.key});
  @override
  State<HelpFab> createState() => _HelpFabState();
}

class _HelpFabState extends State<HelpFab> {
  Timer? _poll;
  @override
  void initState() {
    super.initState();
    refreshSupport();
    _poll = Timer.periodic(const Duration(seconds: 60), (_) => refreshSupport());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<J?>(
        valueListenable: supportView,
        builder: (_, v, _) {
          final replied = teamReplied(v);
          return Row(mainAxisSize: MainAxisSize.min, children: [
            if (replied)
              Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(99), boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 12)]),
                child: const Text('Our team replied 💬', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            Badge(
              isLabelVisible: replied,
              label: const Text('1'),
              backgroundColor: C.gold400,
              textColor: C.brand950,
              child: FloatingActionButton(
                heroTag: 'help',
                tooltip: 'Help & support',
                backgroundColor: C.brand700,
                shape: const CircleBorder(side: BorderSide(color: Colors.white, width: 3)),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: false,
                  useSafeArea: true,
                  clipBehavior: Clip.antiAlias,
                  builder: (ctx) => SizedBox(height: MediaQuery.of(ctx).size.height * .92, child: HelpChat(onClose: () => Navigator.pop(ctx))),
                ),
                child: const Icon(Icons.smart_toy_rounded, color: C.gold200, size: 28),
              ),
            ),
          ]);
        },
      );
}
