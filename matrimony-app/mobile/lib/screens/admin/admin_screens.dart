import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../widgets/media.dart';
import '../../widgets/translate.dart';
import '../../widgets/ui.dart';

const _reasonLabel = {
  'fake': 'Fake profile', 'harassment': 'Harassment', 'married': 'Already married', 'scam_money': 'Asked for money',
  'dowry': 'Dowry demand', 'obscene': 'Obscene content', 'underage': 'Under-age', 'other': 'Other',
};

(String, Color, Color, IconData) statusStyle(String s) => switch (s) {
      'active' => ('Live', C.green, C.greenBg, Icons.check_circle_rounded),
      'approved' => ('Approved', C.green, C.greenBg, Icons.check_circle_rounded),
      'pending_review' || 'pending' || 'open' => (s == 'open' ? 'Open' : (s == 'pending' ? 'Pending' : 'In review'), C.amber, C.amberBg, Icons.schedule_rounded),
      'rejected' => ('Needs changes', Color(0xFFC2410C), Color(0xFFFFF7ED), Icons.warning_amber_rounded),
      'suspended' => ('Suspended', C.red, C.redBg, Icons.block_rounded),
      'banned' => ('Banned', C.red, C.redBg, Icons.block_rounded),
      'draft' => ('Awaiting consent', C.muted, C.sand, Icons.radio_button_unchecked_rounded),
      'actioned' => ('Actioned', C.muted, C.sand, Icons.check_circle_rounded),
      'dismissed' => ('Dismissed', C.muted, C.sand, Icons.radio_button_unchecked_rounded),
      _ => (s, C.muted, C.sand, Icons.circle_outlined),
    };

Widget statusPill(String s) {
  final (l, fg, bg, i) = statusStyle(s);
  return Pill(l, icon: i, fg: fg, bg: bg);
}

String when(String? iso) {
  if (iso == null) return '—';
  final t = DateTime.parse(iso).toLocal();
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${t.day} ${m[t.month - 1]}, ${clock(iso)}';
}

Future<String?> askReason(BuildContext context, String title, String label, {String? hint, bool required = true, List<String> quick = const []}) {
  final c = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: display(22)),
        if (hint != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(hint, style: const TextStyle(color: C.muted))),
        if (quick.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final q in quick) ActionChip(label: Text(q), onPressed: () => Navigator.pop(ctx, q))]),
        ],
        FieldLabel(label),
        TextField(controller: c, maxLines: 3, maxLength: 300, autofocus: quick.isEmpty),
        const SizedBox(height: 10),
        Btn('Confirm', expand: true, onPressed: () {
          if (required && c.text.trim().length < 3) return;
          Navigator.pop(ctx, c.text.trim());
        }),
      ]),
    ),
  );
}

// ======================= shell =======================
class AdminShell extends StatefulWidget {
  const AdminShell({super.key});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  String page = 'dashboard';
  J stats = {};
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _stats();
    _t = Timer.periodic(const Duration(seconds: 60), (_) => _stats());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _stats() async {
    try {
      final s = Map<String, dynamic>.from(await staffApi.get('/admin/stats') as Map);
      if (mounted) setState(() => stats = s);
    } catch (_) {}
  }

  void go(String p) => setState(() => page = p);

  @override
  Widget build(BuildContext context) {
    final admin = appState.isAdmin;
    final nav = <(String, String, IconData, int?)>[
      ('dashboard', 'Dashboard', Icons.dashboard_rounded, null),
      ('profiles', 'Profiles', Icons.people_alt_rounded, stats['profiles_pending'] as int?),
      ('photos', 'Photos', Icons.photo_library_rounded, stats['photos_pending'] as int?),
      ('reports', 'Reports', Icons.flag_rounded, stats['reports_open'] as int?),
      ('support', 'Support', Icons.support_agent_rounded, stats['support_waiting'] as int?),
      if (admin) ('audit', 'Audit log', Icons.receipt_long_rounded, null),
      if (admin) ('logs', 'App logs', Icons.monitor_heart_rounded, null),
      if (admin) ('staff', 'Staff', Icons.manage_accounts_rounded, null),
    ];
    final title = nav.firstWhere((n) => n.$1 == page).$2;
    final body = switch (page) {
      'profiles' => const ProfilesPage(),
      'photos' => const PhotosPage(),
      'reports' => const ReportsPage(),
      'support' => const SupportPage(),
      'audit' => const AuditPage(),
      'logs' => const LogsPage(),
      'staff' => const StaffPage(),
      _ => DashboardPage(stats: stats, go: go, refresh: _stats),
    };
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      drawer: Drawer(
        backgroundColor: C.brand800,
        child: Stack(children: [
          Positioned.fill(child: DecoratedBox(decoration: const BoxDecoration(gradient: C.heroGradient), child: CustomPaint(painter: MandalaPainter()))),
          SafeArea(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.favorite_rounded, color: C.gold300),
                title: Text(Config.appName, style: display(18, color: Colors.white)),
                subtitle: const Text('ADMIN PANEL', style: TextStyle(color: C.gold200, fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              for (final (k, l, i, n) in nav)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  child: ListTile(
                    selected: page == k,
                    selectedTileColor: Colors.white,
                    selectedColor: C.brand800,
                    iconColor: Colors.white70,
                    textColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    leading: Icon(i),
                    title: Text(l, style: const TextStyle(fontWeight: FontWeight.w600)),
                    trailing: (n ?? 0) > 0 ? Pill('$n', fg: C.brand950, bg: C.gold300) : null,
                    onTap: () {
                      Navigator.pop(context);
                      go(k);
                      _stats();
                    },
                  ),
                ),
              const Spacer(),
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(18)),
                child: Row(children: [
                  CircleAvatar(backgroundColor: C.gold300, child: Text(((appState.staff?['name'] as String?) ?? 'S')[0], style: const TextStyle(color: C.brand950, fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(appState.staff?['name'] as String? ?? '', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      Text((appState.staff?['role'] as String? ?? '').toUpperCase(), style: const TextStyle(color: C.gold200, fontSize: 11, fontWeight: FontWeight.w700)),
                    ]),
                  ),
                  IconButton(tooltip: 'Sign out', onPressed: () => appState.signOut(), icon: const Icon(Icons.logout_rounded, color: Colors.white)),
                ]),
              ),
            ]),
          ),
        ]),
      ),
      body: PatternBg(child: body),
    );
  }
}

// ======================= dashboard =======================
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.stats, required this.go, required this.refresh});
  final J stats;
  final void Function(String) go;
  final Future<void> Function() refresh;

  Widget _queue(String page, IconData icon, String label, Object? count, String text) {
    final has = (count as int? ?? 0) > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        color: has ? C.brand50 : Colors.white,
        border: has ? C.brand100 : null,
        onTap: () => go(page),
        child: Row(children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(gradient: has ? C.buttonGradient : null, color: has ? null : C.sand, borderRadius: BorderRadius.circular(16)),
            child: Icon(icon, color: has ? Colors.white : C.muted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${count ?? '—'}', style: display(26)),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(has ? text : 'All clear — nothing waiting', style: const TextStyle(fontSize: 12, color: C.muted)),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: C.brand400),
        ]),
      ),
    );
  }

  Widget _tile(String label, Object? v, IconData icon, Color fg, Color bg) => AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Expanded(child: Text(label, style: const TextStyle(color: C.muted, fontWeight: FontWeight.w600, fontSize: 13))), IconChip(icon, fg: fg, bg: bg, size: 34)]),
          const SizedBox(height: 6),
          Text('${v ?? '—'}', style: display(28)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final h = DateTime.now().hour;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Good ${h < 12 ? 'morning' : h < 17 ? 'afternoon' : 'evening'}, ${(appState.staff?['name'] as String? ?? '').split(' ').first}', style: display(26)),
        const Text("Here's what needs attention today.", style: TextStyle(color: C.muted)),
        const SizedBox(height: 16),
        _queue('profiles', Icons.how_to_reg_rounded, 'Profiles to review', stats['profiles_pending'], 'Oldest first — approve or ask for changes'),
        _queue('photos', Icons.photo_library_rounded, 'Photos to review', stats['photos_pending'], 'Check for real, appropriate photos'),
        _queue('reports', Icons.flag_rounded, 'Open reports', stats['reports_open'], 'Safety first — handle these quickly'),
        _queue('support', Icons.support_agent_rounded, 'Help requests', stats['support_waiting'], 'Members waiting for a person'),
        const SizedBox(height: 8),
        Text('Members', style: display(20)),
        const SizedBox(height: 10),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.45,
          children: [
            _tile('Total profiles', stats['members_total'], Icons.people_rounded, C.brand600, C.brand50),
            _tile('Live profiles', stats['profiles_live'], Icons.auto_awesome_rounded, C.teal, C.tealBg),
            _tile('New today', stats['signups_today'], Icons.person_add_rounded, C.violet, C.violetBg),
            _tile('Premium', stats['premium_members'], Icons.workspace_premium_rounded, C.gold500, C.gold50),
            _tile('Interests today', stats['interests_today'], Icons.favorite_rounded, const Color(0xFFF43F5E), const Color(0xFFFFF1F2)),
            _tile('Messages today', stats['messages_today'], Icons.chat_bubble_rounded, C.sky, C.skyBg),
          ],
        ),
      ]),
    );
  }
}

// ======================= profiles =======================
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});
  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  String status = 'pending_review';
  final q = TextEditingController();
  late Future<J> _f = _load();
  Future<J> _load() async => Map<String, dynamic>.from(await staffApi.get('/admin/profiles', query: {if (status.isNotEmpty) 'status': status, if (q.text.trim().isNotEmpty) 'q': q.text.trim()}) as Map);
  void _reload() => setState(() => _f = _load());

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: q,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _reload(),
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Name or profile ID'),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
          child: Row(children: [
            for (final (v, l) in [('pending_review', 'To review'), ('active', 'Live'), ('rejected', 'Needs changes'), ('suspended', 'Suspended'), ('draft', 'Awaiting consent'), ('', 'All')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(l), selected: status == v, selectedColor: C.brand600, labelStyle: TextStyle(color: status == v ? Colors.white : C.ink, fontWeight: FontWeight.w600), onSelected: (_) {
                  status = v;
                  _reload();
                }),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: Loader<J>(
              future: _f,
              onRetry: _reload,
              builder: (d) {
                final items = (d['items'] as List).cast<Map>();
                if (items.isEmpty) return ListView(children: [EmptyState(icon: Icons.task_alt_rounded, title: status == 'pending_review' ? 'All caught up' : 'No profiles', text: 'Nothing to show here.')]);
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = Map<String, dynamic>.from(items[i]);
                    return AppCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () async {
                        await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminProfileDetail(p['public_id'] as String)));
                        _reload();
                      },
                      child: Row(children: [
                        Avatar(name: p['name'] as String, seed: p['public_id'] as String, size: 46),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['name'] as String, style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${p['public_id']} · ${p['gender'] == 'female' ? 'F' : 'M'}, ${p['age']} · ${[p['community'] ?? p['religion'], p['city']].whereType<String>().join(' · ')}',
                                style: const TextStyle(fontSize: 12, color: C.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, runSpacing: 4, children: [
                              statusPill(p['account_status'] != 'active' ? p['account_status'] as String : p['status'] as String),
                              Pill('${p['completeness']}%'),
                              if ((p['photos_pending'] as int) > 0) Pill('${p['photos_pending']} photo', icon: Icons.photo_rounded, fg: C.amber, bg: C.amberBg),
                              if ((p['reports_open'] as int) > 0) Pill('${p['reports_open']}', icon: Icons.flag_rounded, fg: C.red, bg: C.redBg),
                            ]),
                          ]),
                        ),
                        const Icon(Icons.chevron_right_rounded, color: C.muted),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ]);
}

class AdminProfileDetail extends StatefulWidget {
  const AdminProfileDetail(this.publicId, {super.key});
  final String publicId;
  @override
  State<AdminProfileDetail> createState() => _AdminProfileDetailState();
}

class _AdminProfileDetailState extends State<AdminProfileDetail> {
  late Future<J> _f = _load();
  String? phone;
  Future<J> _load() async => Map<String, dynamic>.from(await staffApi.get('/admin/profiles/${widget.publicId}') as Map);
  void _reload() => setState(() => _f = _load());

  Future<void> _act(String action) async {
    String? reason;
    if (['reject', 'suspend', 'ban'].contains(action)) {
      reason = await askReason(
        context,
        {'reject': 'Ask for changes', 'suspend': 'Suspend member', 'ban': 'Ban permanently'}[action]!,
        action == 'reject' ? 'What should they fix? (the member sees this)' : 'Reason (internal)',
        hint: action == 'ban' ? 'Permanent. For scams, dowry demands, harassment or fake identities.' : null,
      );
      if (reason == null) return;
    }
    try {
      await staffApi.post('/admin/profiles/${widget.publicId}/moderate', {'action': action, 'reason': reason});
      if (mounted) snack(context, 'Done');
      _reload();
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Future<void> _photo(String id, String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await askReason(context, 'Reject photo', 'Reason', quick: ['Not a real person / stock photo', 'Face not visible', 'Group photo', 'Inappropriate', 'Contains contact details']);
      if (reason == null) return;
    }
    try {
      await staffApi.post('/admin/photos/$id/moderate', {'action': action, 'reason': reason});
      _reload();
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Widget _kv(Map? d) {
    if (d == null) return const Text('Not provided', style: TextStyle(color: C.muted));
    String nice(String v) => RegExp(r'^[a-z_]+$').hasMatch(v) ? (v[0].toUpperCase() + v.substring(1)).replaceAll('_', ' ') : v;
    return Facts([for (final e in d.entries) if (!(e.key as String).endsWith('_id') && e.value != null) ((e.key as String).replaceAll('_', ' '), nice('${e.value}'))]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Review profile')),
        body: PatternBg(
          child: Loader<J>(
            future: _f,
            onRetry: _reload,
            builder: (p) {
              final admin = appState.isAdmin;
              final locked = p['account_status'] != 'active';
              final photos = (p['photos'] as List).cast<Map>();
              final reports = (p['reports'] as List).cast<Map>();
              final history = (p['history'] as List).cast<Map>();
              return ListView(padding: const EdgeInsets.all(16), children: [
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(p['name'] as String, style: display(24))),
                      statusPill(locked ? p['account_status'] as String : p['status'] as String),
                    ]),
                    Text('${p['public_id']} · ${p['gender'] == 'female' ? 'Female' : 'Male'}, ${p['age']} · by ${p['created_by']} · joined ${when(p['created_at'] as String)}',
                        style: const TextStyle(color: C.muted, fontSize: 13)),
                    if (p['moderation_note'] != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Note to member: ${p['moderation_note']}', style: const TextStyle(color: Color(0xFFC2410C)))),
                    if (p['consent_pending'] == true) const Padding(padding: EdgeInsets.only(top: 8), child: Text("Candidate hasn't confirmed consent yet — can't approve.", style: TextStyle(color: C.muted))),
                    const SizedBox(height: 14),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (!locked && p['status'] != 'active') Btn('Approve', icon: Icons.check_rounded, small: true, onPressed: p['consent_pending'] == true ? null : () => _act('approve')),
                      if (!locked && p['status'] != 'rejected') Btn('Ask for changes', icon: Icons.edit_rounded, small: true, kind: BtnKind.secondary, onPressed: () => _act('reject')),
                      if (!locked) Btn('Suspend', icon: Icons.pause_circle_rounded, small: true, kind: BtnKind.secondary, onPressed: () => _act('suspend')),
                      if (admin && p['account_status'] != 'banned') Btn('Ban', icon: Icons.block_rounded, small: true, kind: BtnKind.danger, onPressed: () => _act('ban')),
                      if (locked && (p['account_status'] != 'banned' || admin)) Btn('Reactivate', icon: Icons.restart_alt_rounded, small: true, kind: BtnKind.secondary, onPressed: () => _act('reactivate')),
                    ]),
                  ]),
                ),
                const SizedBox(height: 12),
                AppCard(
                  child: Row(children: [
                    const Icon(Icons.phone_rounded, color: C.muted),
                    const SizedBox(width: 10),
                    Expanded(child: Text(phone ?? p['phone_masked'] as String? ?? '—', style: const TextStyle(fontFamily: 'monospace', fontSize: 15))),
                    if (phone == null && p['phone_masked'] != null)
                      Btn('Reveal', icon: Icons.visibility_rounded, small: true, kind: BtnKind.secondary, onPressed: () async {
                        final r = await askReason(context, 'Reveal phone number', 'Why do you need it?', hint: 'Recorded in the audit log.');
                        if (r == null) return;
                        try {
                          final d = await staffApi.post('/admin/profiles/${widget.publicId}/reveal-phone', {'reason': r}) as Map;
                          setState(() => phone = d['phone'] as String);
                        } on ApiError catch (e) {
                          if (context.mounted) snack(context, e.message);
                        }
                      }),
                  ]),
                ),
                const SizedBox(height: 12),
                Text('Photos (${photos.length})', style: display(18)),
                const SizedBox(height: 8),
                if (photos.isEmpty) const Text('No photos uploaded', style: TextStyle(color: C.muted)),
                SizedBox(
                  height: photos.isEmpty ? 0 : 250,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final ph in photos)
                      Container(
                        width: 150,
                        margin: const EdgeInsets.only(right: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          ClipRRect(borderRadius: BorderRadius.circular(16), child: CachedNetworkImage(imageUrl: Config.media(ph['url'] as String)!, height: 170, width: 150, fit: BoxFit.cover)),
                          const SizedBox(height: 6),
                          Row(children: [statusPill(ph['status'] as String), if (ph['duplicate'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.warning_rounded, color: C.red, size: 18))]),
                          if (ph['status'] == 'pending')
                            Row(children: [
                              IconButton(tooltip: 'Approve', onPressed: () => _photo(ph['id'] as String, 'approve'), icon: const Icon(Icons.check_circle_rounded, color: C.green)),
                              IconButton(tooltip: 'Reject', onPressed: () => _photo(ph['id'] as String, 'reject'), icon: const Icon(Icons.cancel_rounded, color: C.red)),
                            ]),
                        ]),
                      ),
                  ]),
                ),
                const SizedBox(height: 12),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('About', style: display(18)),
                  const SizedBox(height: 8),
                  Text(p['about_me'] as String? ?? 'Not written', style: const TextStyle(height: 1.4)),
                  const Divider(height: 24),
                  Facts([
                    ('Date of birth', p['dob'] as String?), ('Height', heightLabel(p['height_cm'])), ('Marital status', maritalLabels[p['marital_status']]),
                    ('Religion', p['religion'] as String?), ('Community', p['community'] as String?), ('Mother tongue', p['mother_tongue'] as String?), ('City', p['city'] as String?),
                  ]),
                ])),
                const SizedBox(height: 12),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Career', style: display(18)), const SizedBox(height: 10), _kv(p['career'] as Map?)])),
                const SizedBox(height: 12),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Family', style: display(18)), const SizedBox(height: 10), _kv(p['family'] as Map?)])),
                const SizedBox(height: 12),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Reports (${reports.length})', style: display(18)),
                  if (reports.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('No reports', style: TextStyle(color: C.muted))),
                  for (final r in reports)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [Expanded(child: Text(_reasonLabel[r['reason']] ?? r['reason'] as String, style: const TextStyle(fontWeight: FontWeight.w700))), statusPill(r['status'] as String)]),
                        if (r['details'] != null) Text(r['details'] as String),
                        if (r['message'] != null) Text('Message: “${r['message']}”', style: const TextStyle(color: C.red, fontSize: 13)),
                        Text('by ${(r['reporter'] as Map)['name']} · ${when(r['created_at'] as String)}', style: const TextStyle(fontSize: 12, color: C.muted)),
                      ]),
                    ),
                ])),
                const SizedBox(height: 12),
                AppCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Moderation history', style: display(18)),
                  if (history.isEmpty) const Padding(padding: EdgeInsets.only(top: 6), child: Text('No actions yet', style: TextStyle(color: C.muted))),
                  for (final h in history)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text.rich(TextSpan(text: '${h['action']}', style: const TextStyle(fontWeight: FontWeight.w700), children: [
                        TextSpan(text: '  ${h['staff']} · ${when(h['created_at'] as String)}${h['reason'] != null ? '\n“${h['reason']}”' : ''}', style: const TextStyle(fontWeight: FontWeight.w400, color: C.muted, fontSize: 12.5)),
                      ])),
                    ),
                ])),
              ]);
            },
          ),
        ),
      );
}

// ======================= photos =======================
class PhotosPage extends StatefulWidget {
  const PhotosPage({super.key});
  @override
  State<PhotosPage> createState() => _PhotosPageState();
}

class _PhotosPageState extends State<PhotosPage> {
  late Future<List> _f = _load();
  Future<List> _load() => staffApi.get('/admin/photos', query: {'status': 'pending'}).then((d) => d as List);

  Future<void> _act(Map ph, String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await askReason(context, 'Reject photo', 'Reason', quick: ['Not a real person / stock photo', 'Face not visible', 'Group photo', 'Inappropriate', 'Contains contact details', 'Duplicate of another profile']);
      if (reason == null) return;
    }
    try {
      await staffApi.post('/admin/photos/${ph['id']}/moderate', {'action': action, 'reason': reason});
      setState(() => _f = _load());
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: () async => setState(() => _f = _load()),
        child: Loader<List>(
          future: _f,
          builder: (list) => list.isEmpty
              ? ListView(children: const [EmptyState(icon: Icons.task_alt_rounded, title: 'No photos waiting', text: 'All caught up.')])
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: .58),
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final ph = list[i] as Map;
                    final p = ph['profile'] as Map;
                    return AppCard(
                      padding: EdgeInsets.zero,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(child: ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(24)), child: CachedNetworkImage(imageUrl: Config.media(ph['url'] as String)!, fit: BoxFit.cover))),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('${p['name']}, ${p['age']}', style: const TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                            if (ph['duplicate'] == true) const Text('⚠ Also on another profile', style: TextStyle(color: C.red, fontSize: 12, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(child: Btn('OK', small: true, expand: true, onPressed: () => _act(ph, 'approve'))),
                              const SizedBox(width: 6),
                              Expanded(child: Btn('Reject', small: true, expand: true, kind: BtnKind.secondary, onPressed: () => _act(ph, 'reject'))),
                            ]),
                          ]),
                        ),
                      ]),
                    );
                  },
                ),
        ),
      );
}

// ======================= reports =======================
class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String status = 'open';
  late Future<List> _f = _load();
  Future<List> _load() => staffApi.get('/admin/reports', query: {'status': status}).then((d) => d as List);

  Future<void> _resolve(Map r, String action) async {
    final note = await askReason(context, {'dismiss': 'Dismiss report', 'warn': 'Warn member', 'suspend': 'Suspend member', 'ban': 'Ban member'}[action]!,
        action == 'warn' ? 'Message to the member' : 'Note', required: action != 'dismiss');
    if (note == null) return;
    try {
      await staffApi.post('/admin/reports/${r['id']}/resolve', {'action': action, 'note': note.isEmpty ? null : note});
      setState(() => _f = _load());
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'open', label: Text('Open')), ButtonSegment(value: 'closed', label: Text('Resolved'))],
            selected: {status},
            onSelectionChanged: (s) => setState(() {
              status = s.first;
              _f = _load();
            }),
          ),
        ),
        Expanded(
          child: Loader<List>(
            future: _f,
            builder: (list) => list.isEmpty
                ? const EmptyState(icon: Icons.task_alt_rounded, title: 'No reports', text: 'Nothing here.')
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      final r = list[i] as Map;
                      return AppCard(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [Expanded(child: Text(_reasonLabel[r['reason']] ?? r['reason'] as String, style: display(18))), statusPill(r['status'] as String)]),
                          if ((r['reported_open_reports'] as int) > 1) Padding(padding: const EdgeInsets.only(top: 6), child: Pill('${r['reported_open_reports']} open reports on this member', icon: Icons.warning_rounded, fg: C.red, bg: C.redBg)),
                          const SizedBox(height: 6),
                          Text('${(r['reported'] as Map)['name']} (${(r['reported'] as Map)['public_id']}) reported by ${(r['reporter'] as Map)['name']} · ${when(r['created_at'] as String)}', style: const TextStyle(fontSize: 13, color: C.muted)),
                          if (r['details'] != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('“${r['details']}”')),
                          if (r['message'] != null)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: C.redBg, borderRadius: BorderRadius.circular(12)),
                              child: Text('Reported message: “${r['message']}”', style: const TextStyle(color: C.red)),
                            ),
                          if (r['status'] == 'open') ...[
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              Btn('Dismiss', small: true, kind: BtnKind.secondary, onPressed: () => _resolve(r, 'dismiss')),
                              Btn('Warn', small: true, kind: BtnKind.secondary, onPressed: () => _resolve(r, 'warn')),
                              Btn('Suspend', small: true, kind: BtnKind.secondary, onPressed: () => _resolve(r, 'suspend')),
                              if (appState.isAdmin) Btn('Ban', small: true, kind: BtnKind.danger, onPressed: () => _resolve(r, 'ban')),
                            ]),
                          ],
                        ]),
                      );
                    },
                  ),
          ),
        ),
      ]);
}

// ======================= support inbox =======================
class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  String status = 'waiting_team';
  late Future<List> _f = _load();
  Future<List> _load() => staffApi.get('/admin/support', query: {'status': status}).then((d) => d as List);

  @override
  Widget build(BuildContext context) => Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            for (final (v, l) in [('waiting_team', 'Waiting for us'), ('answered', 'Replied'), ('bot', 'Assistant only'), ('closed', 'Closed')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(l), selected: status == v, selectedColor: C.brand600, labelStyle: TextStyle(color: status == v ? Colors.white : C.ink, fontWeight: FontWeight.w600), onSelected: (_) => setState(() {
                  status = v;
                  _f = _load();
                })),
              ),
          ]),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => setState(() => _f = _load()),
            child: Loader<List>(
              future: _f,
              builder: (list) => list.isEmpty
                  ? ListView(children: [EmptyState(icon: Icons.support_agent_rounded, title: status == 'waiting_team' ? 'No one is waiting' : 'Nothing here', text: 'All caught up.')])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final t = list[i] as Map;
                        final m = t['member'] as Map;
                        return AppCard(
                          padding: const EdgeInsets.all(14),
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: (_) => SupportThread(t['id'] as String)));
                            setState(() => _f = _load());
                          },
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Expanded(child: Text(m['name'] as String, style: TextStyle(fontWeight: (t['unread'] as int) > 0 ? FontWeight.w800 : FontWeight.w600))),
                              Text(when(t['last_message_at'] as String?), style: const TextStyle(fontSize: 11.5, color: C.muted)),
                            ]),
                            Text(t['last_message'] as String? ?? t['subject'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: C.muted)),
                            const SizedBox(height: 6),
                            Wrap(spacing: 6, children: [
                              if (t['urgent'] == true) const Pill('Urgent', icon: Icons.warning_rounded, fg: C.red, bg: C.redBg),
                              if (t['topic'] != null) Pill(t['topic'] as String),
                              if ((t['unread'] as int) > 0) Pill('${t['unread']} new', fg: Colors.white, bg: C.brand600),
                            ]),
                          ]),
                        );
                      },
                    ),
            ),
          ),
        ),
      ]);
}

class SupportThread extends StatefulWidget {
  const SupportThread(this.ticketId, {super.key});
  final String ticketId;
  @override
  State<SupportThread> createState() => _SupportThreadState();
}

class _SupportThreadState extends State<SupportThread> {
  J? d;
  final reply = TextEditingController();
  bool busy = false;
  static const canned = [
    "Thanks for reaching out! I'm looking into this now.",
    "Could you share a screenshot of what you see? It'll help us fix this faster.",
    'This is fixed now — please refresh the app and try again.',
    'Your profile has been reviewed and is now live. Good luck!',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = Map<String, dynamic>.from(await staffApi.get('/admin/support/${widget.ticketId}') as Map);
    setState(() => d = r);
  }

  Future<void> _send({bool close = false}) async {
    if (reply.text.trim().isEmpty) return;
    setState(() => busy = true);
    try {
      final r = Map<String, dynamic>.from(await staffApi.post('/admin/support/${widget.ticketId}/reply', {'body': reply.text.trim(), 'close': close}) as Map);
      reply.clear();
      setState(() => d = r);
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = d?['ticket'] as Map?;
    final m = t?['member'] as Map?;
    final msgs = (d?['messages'] as List?)?.cast<Map>() ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(m?['name'] as String? ?? 'Conversation', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: C.ink)),
          if (m != null) Text('${m['public_id'] ?? 'No profile'} · ${m['phone'] ?? ''}', style: const TextStyle(fontSize: 12, color: C.muted)),
        ]),
        actions: [
          const Center(child: LanguagePicker()),
          if (t != null && t['status'] != 'closed')
            IconButton(tooltip: 'Close conversation', onPressed: () async {
              final r = Map<String, dynamic>.from(await staffApi.post('/admin/support/${widget.ticketId}/close') as Map);
              setState(() => d = r);
            }, icon: const Icon(Icons.check_circle_outline_rounded)),
        ],
      ),
      body: d == null
          ? const Center(child: CircularProgressIndicator())
          : PatternBg(
              child: Column(children: [
                Expanded(
                  child: ListView(padding: const EdgeInsets.all(14), children: [
                    for (final x in msgs) _msg(x),
                  ]),
                ),
                if (t!['status'] != 'closed')
                  SafeArea(
                    top: false,
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      child: Column(children: [
                        SizedBox(
                          height: 36,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final c in canned) Padding(padding: const EdgeInsets.only(right: 6), child: ActionChip(label: Text(c.length > 34 ? '${c.substring(0, 32)}…' : c, style: const TextStyle(fontSize: 12)), onPressed: () => reply.text = c)),
                          ]),
                        ),
                        const SizedBox(height: 6),
                        Row(children: [
                          Expanded(child: TextField(controller: reply, minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: 'Reply to ${(m?['name'] as String? ?? '').split(' ').first}…'))),
                          const SizedBox(width: 6),
                          IconButton.filled(onPressed: busy ? null : _send, style: IconButton.styleFrom(backgroundColor: C.brand600), icon: const Icon(Icons.send_rounded)),
                        ]),
                        Align(alignment: Alignment.centerRight, child: TextButton(onPressed: busy ? null : () => _send(close: true), child: const Text('Reply & close'))),
                      ]),
                    ),
                  ),
              ]),
            ),
    );
  }

  Widget _msg(Map x) {
    final member = x['sender'] == 'member';
    final bot = x['sender'] == 'bot';
    return Align(
      alignment: member ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .8),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: member ? Colors.white : (bot ? C.skyBg : C.gold50),
          border: Border.all(color: member ? C.line : (bot ? const Color(0xFFE0F2FE) : C.gold200)),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${member ? 'MEMBER' : bot ? 'ASSISTANT' : (x['staff_name'] as String? ?? 'STAFF').toUpperCase()} · ${when(x['created_at'] as String)}',
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: C.muted, letterSpacing: .5)),
          const SizedBox(height: 4),
          if (x['kind'] == 'photo')
            ClipRRect(borderRadius: BorderRadius.circular(12), child: CachedNetworkImage(imageUrl: Config.media(x['media_url'] as String)!, height: 220, fit: BoxFit.cover))
          else if (x['kind'] == 'voice')
            VoicePlayer(url: x['media_url'] as String, seconds: x['duration_s'] as int?)
          else ...[
            RichBody(x['body'] as String? ?? '', style: const TextStyle(fontSize: 14, height: 1.4)),
            if (member) TranslateButton(x['body'] as String? ?? ''),
          ],
          if ((x['meta'] as Map?)?['helpful'] == false) const Text("Member said this didn't help", style: TextStyle(fontSize: 11.5, color: C.amber, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

// ======================= audit / logs / staff (admins) =======================
class AuditPage extends StatelessWidget {
  const AuditPage({super.key});
  @override
  Widget build(BuildContext context) => Loader<List>(
        future: staffApi.get('/admin/audit').then((d) => d as List),
        builder: (list) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(),
          itemBuilder: (_, i) {
            final a = list[i] as Map;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${a['action']}'.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${a['staff']} · ${a['target_type']} ${a['target_type'] == 'profile' ? a['target_id'] : ''}\n${a['reason'] ?? ''}'.trim()),
              trailing: Text(when(a['created_at'] as String), style: const TextStyle(fontSize: 11.5, color: C.muted)),
              isThreeLine: a['reason'] != null,
            );
          },
        ),
      );
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key});
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String level = '', category = '';
  late Future<(J, J)> _f = _load();
  Timer? _live;

  Future<(J, J)> _load() async {
    final s = Map<String, dynamic>.from(await staffApi.get('/admin/logs/summary') as Map);
    final l = Map<String, dynamic>.from(await staffApi.get('/admin/logs', query: {if (level.isNotEmpty) 'level': level, if (category.isNotEmpty) 'category': category}) as Map);
    return (s, l);
  }

  @override
  void initState() {
    super.initState();
    _live = Timer.periodic(const Duration(seconds: 15), (_) => setState(() => _f = _load()));
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Loader<(J, J)>(
        future: _f,
        builder: (r) {
          final (s, l) = r;
          final items = (l['items'] as List).cast<Map>();
          Widget tile(String label, Object? v, Color fg, Color bg, IconData i) => Expanded(
                child: AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [Expanded(child: Text(label, style: const TextStyle(fontSize: 11.5, color: C.muted, fontWeight: FontWeight.w600))), Icon(i, size: 16, color: fg)]),
                    Text('${v ?? '—'}', style: display(22)),
                  ]),
                ),
              );
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [
              tile('Events 24h', s['events_24h'], C.sky, C.skyBg, Icons.monitor_heart_rounded),
              const SizedBox(width: 8),
              tile('Failed sign-ins', s['failed_logins_24h'], C.gold500, C.gold50, Icons.key_rounded),
              const SizedBox(width: 8),
              tile('Errors', s['errors_24h'], C.red, C.redBg, Icons.error_rounded),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, lbl) in [('', 'All levels'), ('warning', 'Warnings & errors'), ('error', 'Errors')])
                ChoiceChip(label: Text(lbl), selected: level == v, onSelected: (_) => setState(() { level = v; _f = _load(); })),
            ]),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final (v, lbl) in [('', 'All'), ('auth', 'Member sign-in'), ('staff', 'Staff sign-in'), ('safety', 'Safety'), ('support', 'Help desk'), ('chat', 'Chat'), ('system', 'System')])
                ChoiceChip(label: Text(lbl), selected: category == v, onSelected: (_) => setState(() { category = v; _f = _load(); })),
            ]),
            const SizedBox(height: 10),
            for (final e in items)
              Card(
                elevation: 0,
                color: e['level'] == 'error' ? C.redBg : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: C.line)),
                child: ExpansionTile(
                  leading: Icon(
                    e['level'] == 'error' ? Icons.error_rounded : (e['level'] == 'warning' ? Icons.warning_amber_rounded : Icons.info_outline_rounded),
                    color: e['level'] == 'error' ? C.red : (e['level'] == 'warning' ? C.amber : C.sky),
                  ),
                  title: Text('${e['event']}'.replaceAll('_', ' '), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  subtitle: Text('${e['actor'] ?? '—'} · ${when(e['created_at'] as String)}', style: const TextStyle(fontSize: 12)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (e['message'] != null) Text(e['message'] as String),
                    Text('IP ${e['ip'] ?? '—'} · request ${e['request_id'] ?? '—'}', style: const TextStyle(fontSize: 12, color: C.muted)),
                    if (e['meta'] != null) Text('${e['meta']}', style: const TextStyle(fontSize: 11.5, fontFamily: 'monospace')),
                  ],
                ),
              ),
          ]);
        },
      );
}

class StaffPage extends StatefulWidget {
  const StaffPage({super.key});
  @override
  State<StaffPage> createState() => _StaffPageState();
}

class _StaffPageState extends State<StaffPage> {
  late Future<List> _f = staffApi.get('/admin/staff').then((d) => d as List);
  void _reload() => setState(() => _f = staffApi.get('/admin/staff').then((d) => d as List));

  void _showPassword(Map r) => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Temporary password'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('For ${(r['staff'] as Map)['email']} — shown only once. Share it privately (not by email).'),
            const SizedBox(height: 12),
            SelectableText(r['temporary_password'] as String, style: const TextStyle(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700)),
          ]),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: r['temporary_password'] as String)), child: const Text('Copy')),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("I've shared it")),
          ],
        ),
      );

  Future<void> _invite() async {
    final name = TextEditingController(), email = TextEditingController();
    var role = 'moderator';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Invite staff', style: display(22)),
            const FieldLabel('Full name'),
            TextField(controller: name),
            const FieldLabel('Work email'),
            TextField(controller: email, keyboardType: TextInputType.emailAddress),
            const FieldLabel('Role'),
            Pick<String>(value: role, items: const [('moderator', 'Moderator — review & moderate'), ('admin', 'Admin — everything, incl. bans & staff')], onChanged: (v) => set(() => role = v ?? role)),
            const SizedBox(height: 16),
            Btn('Create & get password', expand: true, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final r = await staffApi.post('/admin/staff', {'name': name.text.trim(), 'email': email.text.trim(), 'role': role}) as Map;
      _reload();
      if (mounted) _showPassword(r);
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.transparent,
        floatingActionButton: FloatingActionButton.extended(onPressed: _invite, backgroundColor: C.brand600, foregroundColor: Colors.white, icon: const Icon(Icons.person_add_rounded), label: const Text('Invite staff')),
        body: Loader<List>(
          future: _f,
          builder: (list) => ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              final s = list[i] as Map;
              final me = s['id'] == appState.staff?['id'];
              return AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Avatar(name: s['name'] as String? ?? '?', seed: s['id'] as String, size: 46),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${s['name']}${me ? '  (you)' : ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text(s['email'] as String? ?? '', style: const TextStyle(fontSize: 12, color: C.muted)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, children: [
                        Pill(s['role'] as String, fg: s['role'] == 'admin' ? C.gold600 : C.violet, bg: s['role'] == 'admin' ? C.gold50 : C.violetBg),
                        Pill(s['status'] == 'active' ? 'Active' : 'Disabled', fg: s['status'] == 'active' ? C.green : C.muted, bg: s['status'] == 'active' ? C.greenBg : C.sand),
                        Pill(s['totp_enabled'] == true ? '2-step on' : '2-step not set up', icon: Icons.shield_rounded),
                      ]),
                    ]),
                  ),
                  if (!me)
                    PopupMenuButton<String>(
                      onSelected: (a) async {
                        try {
                          final r = await staffApi.post('/admin/staff/${s['id']}/$a');
                          _reload();
                          if (a == 'reset' && mounted) _showPassword(r as Map);
                        } on ApiError catch (e) {
                          if (context.mounted) snack(context, e.message);
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'reset', child: Text('Reset login')),
                        PopupMenuItem(value: s['status'] == 'active' ? 'disable' : 'enable', child: Text(s['status'] == 'active' ? 'Disable' : 'Enable')),
                      ],
                    ),
                ]),
              );
            },
          ),
        ),
      );
}
