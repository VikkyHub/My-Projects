import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/realtime.dart';
import '../../core/theme.dart';
import '../../widgets/translate.dart';
import '../../widgets/ui.dart';
import 'profile_view.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});
  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  late Future<List> _f = _load();
  StreamSubscription? _sub;
  Future<List> _load() => memberApi.get('/conversations').then((d) => d as List);

  @override
  void initState() {
    super.initState();
    _sub = Realtime.instance.on({'message', 'read', 'refresh', 'interest_accepted'}).listen((_) => setState(() => _f = _load()));
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => setState(() => _f = _load()),
        child: Loader<List>(
          future: _f,
          onRetry: () => setState(() => _f = _load()),
          builder: (list) => list.isEmpty
              ? ListView(children: const [
                  EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'No conversations yet', text: 'Chats open when an interest is accepted. Check your Interests.'),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 110),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const Divider(height: 1, indent: 82),
                  itemBuilder: (_, i) {
                    final c = Map<String, dynamic>.from(list[i] as Map);
                    final p = Map<String, dynamic>.from(c['profile'] as Map);
                    final unread = c['unread'] as int;
                    final preview = c['last_message'] != null
                        ? '${c['last_from_me'] == true ? 'You: ' : ''}${c['last_message']}'
                        : (c['can_chat'] == true ? 'Say hello 👋' : (c['blocked_reason'] == 'premium_required' ? 'Connected · Premium to chat' : 'Conversation closed'));
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: Avatar(name: p['name'] as String, seed: p['public_id'] as String, photo: p['photo_url'] as String?, premium: p['is_premium'] == true, size: 52),
                      title: Text(p['name'] as String, style: TextStyle(fontWeight: unread > 0 ? FontWeight.w800 : FontWeight.w600)),
                      subtitle: Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread > 0 ? C.ink : C.muted, fontWeight: unread > 0 ? FontWeight.w600 : null)),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(timeAgo(c['last_message_at'] as String?), style: const TextStyle(fontSize: 11.5, color: C.muted)),
                        if (unread > 0)
                          Container(
                            margin: const EdgeInsets.only(top: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: C.brand600, borderRadius: BorderRadius.circular(99)),
                            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                          ),
                      ]),
                      onTap: () async {
                        await context.push('/chat/${c['id']}');
                        setState(() => _f = _load());
                        appState.refreshCounts();
                      },
                    );
                  },
                ),
        ),
      );
}

class ThreadScreen extends StatefulWidget {
  const ThreadScreen(this.convId, {super.key});
  final String convId;
  @override
  State<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends State<ThreadScreen> {
  J? conv;
  List<J> msgs = [];
  String? err, sendErr;
  bool sending = false;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription? _sub;

  String get myId => appState.me?['public_id'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    _load();
    _sub = Realtime.instance.on({'message', 'read'}).listen((ev) {
      if (ev['type'] == 'message') {
        final m = Map<String, dynamic>.from(ev['message'] as Map);
        if (m['conversation_id'] != widget.convId || msgs.any((x) => x['id'] == m['id'])) return;
        setState(() => msgs.add(m));
        _toBottom();
        if (m['sender_public_id'] != myId) memberApi.post('/conversations/${widget.convId}/read');
      } else {
        _loadMessages();
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = (await memberApi.get('/conversations') as List).cast<Map>();
      final c = list.firstWhere((e) => e['id'] == widget.convId, orElse: () => {});
      if (c.isEmpty) throw ApiError(404, 'Conversation not found');
      setState(() => conv = Map<String, dynamic>.from(c));
      await _loadMessages();
      if ((c['unread'] as int) > 0) {
        await memberApi.post('/conversations/${widget.convId}/read');
        appState.refreshCounts();
      }
    } on ApiError catch (e) {
      setState(() => err = e.message);
    }
  }

  Future<void> _loadMessages() async {
    final d = (await memberApi.get('/conversations/${widget.convId}/messages') as List).cast<Map>();
    setState(() => msgs = d.map((e) => Map<String, dynamic>.from(e)).toList());
    _toBottom();
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      });

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || sending) return;
    setState(() {
      sending = true;
      sendErr = null;
    });
    try {
      final m = Map<String, dynamic>.from(await memberApi.post('/conversations/${widget.convId}/messages', {'body': t}) as Map);
      _text.clear();
      if (!msgs.any((x) => x['id'] == m['id'])) setState(() => msgs.add(m));
      _toBottom();
    } on ApiError catch (e) {
      setState(() => sendErr = e.message);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = conv?['profile'] as Map?;
    final flagged = msgs.reversed.firstWhere((m) => m['sender_public_id'] != myId && m['flagged'] == true, orElse: () => {});
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: p == null
            ? const Text('Chat')
            : InkWell(
                onTap: () => context.push('/p/${p['public_id']}'),
                child: Row(children: [
                  Avatar(name: p['name'] as String, seed: p['public_id'] as String, photo: p['photo_url'] as String?, size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: C.ink)),
                      Text((p['last_active'] ?? '${p['age']} yrs · ${p['city'] ?? ''}') as String, style: const TextStyle(fontSize: 12, color: C.muted)),
                    ]),
                  ),
                ]),
              ),
        actions: [
          const Padding(padding: EdgeInsets.only(right: 4), child: Center(child: LanguagePicker())),
          if (p != null) IconButton(tooltip: 'Report', onPressed: () => reportSheet(context, p['public_id'] as String), icon: const Icon(Icons.flag_outlined)),
        ],
      ),
      body: err != null
          ? EmptyState(icon: Icons.chat_bubble_outline_rounded, title: 'Conversation not available', text: err!)
          : PatternBg(
              child: Column(children: [
                Expanded(
                  child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(14, 14, 14, 14), children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(color: C.tealBg, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFCCFBF1))),
                      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.verified_user_rounded, size: 18, color: C.teal),
                        SizedBox(width: 8),
                        Expanded(child: Text("Never send money or share OTPs, bank details or your address. Meet in a public place and tell family where you'll be.", style: TextStyle(fontSize: 12.5, color: Color(0xFF134E4A)))),
                      ]),
                    ),
                    for (final m in msgs) _bubble(m),
                    if (msgs.isEmpty && conv?['can_chat'] == true)
                      Center(child: Padding(padding: const EdgeInsets.all(24), child: Text("You're connected with ${p?['first_name']}. Say hello! 👋", style: const TextStyle(color: C.muted)))),
                  ]),
                ),
                if (flagged.isNotEmpty)
                  Container(
                    color: C.amberBg,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: const Row(children: [
                      Icon(Icons.warning_amber_rounded, color: C.amber, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text("A message here mentions money or contact details. Never send money to someone you haven't met.", style: TextStyle(fontSize: 12.5, color: C.amber))),
                    ]),
                  ),
                if (sendErr != null) Container(width: double.infinity, color: C.redBg, padding: const EdgeInsets.all(10), child: Text(sendErr!, style: const TextStyle(color: C.red, fontSize: 13))),
                _composer(),
              ]),
            ),
    );
  }

  Widget _bubble(J m) {
    final mine = m['sender_public_id'] == myId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          gradient: mine ? C.buttonGradient : null,
          color: mine ? null : Colors.white,
          border: mine ? null : Border.all(color: C.line),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(22),
            topRight: const Radius.circular(22),
            bottomLeft: Radius.circular(mine ? 22 : 6),
            bottomRight: Radius.circular(mine ? 6 : 22),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Align(alignment: Alignment.centerLeft, child: Text(m['body'] as String, style: TextStyle(fontSize: 15, height: 1.35, color: mine ? Colors.white : C.ink))),
          if (!mine) Align(alignment: Alignment.centerLeft, child: TranslateButton(m['body'] as String)),
          const SizedBox(height: 2),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(clock(m['created_at'] as String), style: TextStyle(fontSize: 11, color: mine ? Colors.white70 : C.muted)),
            if (mine) ...[const SizedBox(width: 4), Icon(m['read_at'] != null ? Icons.done_all_rounded : Icons.done_rounded, size: 14, color: m['read_at'] != null ? C.gold200 : Colors.white70)],
          ]),
        ]),
      ),
    );
  }

  Widget _composer() {
    if (conv == null) return const SizedBox.shrink();
    if (conv!['can_chat'] != true) {
      final premium = conv!['blocked_reason'] == 'premium_required';
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(gradient: premium ? const LinearGradient(colors: [C.gold50, C.brand50]) : null, color: premium ? null : C.sand),
          child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(premium ? Icons.workspace_premium_rounded : Icons.lock_rounded, color: premium ? C.gold500 : C.muted),
              const SizedBox(width: 8),
              Text(premium ? "You're connected!" : 'This conversation is closed.', style: display(17)),
            ]),
            if (premium) const Text('Chat unlocks when either of you has a Premium plan. Plans are launching soon.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: C.muted)),
          ]),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _text,
              minLines: 1,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Message ${(conv!['profile'] as Map)['first_name']}…',
                filled: true,
                fillColor: C.sand.withValues(alpha: .6),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(28), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: sending ? null : _send,
            style: IconButton.styleFrom(backgroundColor: C.brand600, padding: const EdgeInsets.all(14)),
            icon: sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.send_rounded),
          ),
        ]),
      ),
    );
  }
}
