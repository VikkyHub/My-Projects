import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../widgets/match_card.dart';
import '../../widgets/ui.dart';

class InterestsTab extends StatefulWidget {
  const InterestsTab({super.key});
  @override
  State<InterestsTab> createState() => _InterestsTabState();
}

class _InterestsTabState extends State<InterestsTab> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 4, vsync: this);
  final _keys = List.generate(4, (_) => UniqueKey());

  void _changed() {
    setState(() => _keys.setAll(0, List.generate(4, (_) => UniqueKey())));
    appState.refreshCounts();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Material(
          color: Colors.white,
          child: ListenableBuilder(
            listenable: appState,
            builder: (_, _) {
              final n = appState.counts['received_pending'] as int? ?? 0;
              return TabBar(
                controller: _tabs,
                isScrollable: true,
                labelColor: C.brand700,
                indicatorColor: C.brand600,
                unselectedLabelColor: C.muted,
                labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                tabs: [
                  Tab(text: n > 0 ? 'Received ($n)' : 'Received'),
                  const Tab(text: 'Sent'),
                  const Tab(text: 'Connected'),
                  const Tab(text: 'Shortlisted'),
                ],
              );
            },
          ),
        ),
        ListenableBuilder(
          listenable: appState,
          builder: (_, _) {
            final c = appState.counts;
            if (c['daily_limit'] == null) return const SizedBox.shrink();
            final left = ((c['daily_limit'] as int) - (c['sent_today'] as int)).clamp(0, 999);
            return Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text('$left of ${c['daily_limit']} interests left today', style: const TextStyle(fontSize: 12.5, color: C.muted)),
            );
          },
        ),
        Expanded(
          child: TabBarView(controller: _tabs, children: [
            for (final (i, box) in [(0, 'received'), (1, 'sent'), (2, 'accepted')]) _InterestList(key: _keys[i], box: box, onChanged: _changed),
            _Shortlist(key: _keys[3], onChanged: _changed),
          ]),
        ),
      ]);
}

class _InterestList extends StatelessWidget {
  const _InterestList({super.key, required this.box, required this.onChanged});
  final String box;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Loader<List>(
        future: memberApi.get('/interests', query: {'box': box}).then((d) => d as List),
        onRetry: onChanged,
        builder: (list) => list.isEmpty
            ? EmptyState(
                icon: box == 'received' ? Icons.inbox_rounded : (box == 'sent' ? Icons.send_rounded : Icons.auto_awesome_rounded),
                title: {'received': 'No new interests', 'sent': "You haven't sent any interests", 'accepted': 'No connections yet'}[box]!,
                text: {
                  'received': 'When someone sends you an interest, it shows up here. A complete profile with photos gets noticed more.',
                  'sent': 'Find someone you like in Matches and send an interest — it\'s the first step.',
                  'accepted': "When an interest is accepted, you're connected and can start chatting.",
                }[box]!,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final it = Map<String, dynamic>.from(list[i] as Map);
                  final p = Map<String, dynamic>.from(it['profile'] as Map);
                  return AppCard(
                    padding: const EdgeInsets.all(14),
                    onTap: () => context.push('/p/${p['public_id']}'),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Avatar(name: p['name'] as String, seed: p['public_id'] as String, photo: p['photo_url'] as String?, locked: p['photo_locked'] == true, premium: p['is_premium'] == true, size: 84, radius: 18),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text('${p['name']}, ${p['age']}', style: display(18), overflow: TextOverflow.ellipsis)),
                            Text(timeAgo((it['responded_at'] ?? it['created_at']) as String), style: const TextStyle(fontSize: 11.5, color: C.muted)),
                          ]),
                          Text([heightLabel(p['height_cm'], withCm: false), p['community'], p['city']].whereType<String>().join(' · '),
                              style: const TextStyle(fontSize: 13, color: C.muted)),
                          if (it['note'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${it['note']}”', style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13))),
                          const SizedBox(height: 10),
                          if (it['status'] == 'pending' && it['direction'] == 'received')
                            Row(children: [
                              Btn('Accept', icon: Icons.check_rounded, small: true, onPressed: () => respondInterest(context, it['id'] as String, 'accept', onChanged)),
                              const SizedBox(width: 8),
                              Btn('Decline', small: true, kind: BtnKind.secondary, onPressed: () => respondInterest(context, it['id'] as String, 'decline', onChanged)),
                            ])
                          else if (it['status'] == 'pending')
                            Row(children: [
                              const Pill('Awaiting reply', icon: Icons.schedule_rounded, fg: C.amber, bg: C.amberBg),
                              TextButton(onPressed: () => respondInterest(context, it['id'] as String, 'withdraw', onChanged), child: const Text('Withdraw')),
                            ])
                          else if (it['status'] == 'declined')
                            const Pill('Not interested')
                          else
                            Btn('Message', icon: Icons.chat_bubble_rounded, small: true, onPressed: () => context.push('/chat/${p['conversation_id']}')),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
      );
}

class _Shortlist extends StatelessWidget {
  const _Shortlist({super.key, required this.onChanged});
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) => Loader<List>(
        future: memberApi.get('/shortlist').then((d) => d as List),
        onRetry: onChanged,
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.favorite_border_rounded, title: 'No one shortlisted yet', text: 'Tap the heart on any profile to save it here for later.')
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 110),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (_, i) => MatchCard(Map<String, dynamic>.from(list[i] as Map), onChanged: onChanged),
              ),
      );
}
