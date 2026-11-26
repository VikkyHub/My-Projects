import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/api.dart';
import '../core/labels.dart';
import '../core/theme.dart';
import 'ui.dart';

/// Calls for interests/shortlist; [onChanged] lets the list refresh.
Future<void> sendInterest(BuildContext ctx, J p, VoidCallback onChanged) async {
  try {
    await memberApi.post('/interests', {'public_id': p['public_id']});
    if (ctx.mounted) snack(ctx, 'Interest sent to ${p['first_name']} 💌');
    onChanged();
  } on ApiError catch (e) {
    if (ctx.mounted) snack(ctx, e.message);
  }
}

Future<void> respondInterest(BuildContext ctx, String id, String action, VoidCallback onChanged) async {
  try {
    final r = await memberApi.post('/interests/$id/$action') as Map;
    if (ctx.mounted && action == 'accept') snack(ctx, "You're connected! Say hello 👋");
    onChanged();
    if (ctx.mounted && action == 'accept' && r['conversation_id'] != null) ctx.push('/chat/${r['conversation_id']}');
  } on ApiError catch (e) {
    if (ctx.mounted) snack(ctx, e.message);
  }
}

Future<void> toggleShortlist(BuildContext ctx, J p, VoidCallback onChanged) async {
  try {
    if (p['shortlisted'] == true) {
      await memberApi.delete('/shortlist/${p['public_id']}');
    } else {
      await memberApi.put('/shortlist/${p['public_id']}');
    }
    onChanged();
  } on ApiError catch (e) {
    if (ctx.mounted) snack(ctx, e.message);
  }
}

/// The right call-to-action for the relationship state.
class InterestAction extends StatelessWidget {
  const InterestAction(this.p, {super.key, required this.onChanged, this.small = true});
  final J p;
  final VoidCallback onChanged;
  final bool small;
  @override
  Widget build(BuildContext context) {
    final i = p['interest'] as Map?;
    if (p['conversation_id'] != null || i?['status'] == 'accepted') {
      return Btn('Message', icon: Icons.chat_bubble_rounded, small: small, expand: true, onPressed: () => context.push('/chat/${p['conversation_id']}'));
    }
    if (i?['status'] == 'pending' && i?['direction'] == 'received') {
      return Row(children: [
        Expanded(child: Btn('Accept', icon: Icons.check_rounded, small: small, expand: true, onPressed: () => respondInterest(context, i!['id'] as String, 'accept', onChanged))),
        const SizedBox(width: 8),
        Btn('', icon: Icons.close_rounded, small: small, kind: BtnKind.secondary, onPressed: () => respondInterest(context, i!['id'] as String, 'decline', onChanged)),
      ]);
    }
    if (i?['status'] == 'pending') return Btn('Interest sent', icon: Icons.schedule_rounded, small: small, expand: true, kind: BtnKind.secondary);
    if (i?['status'] == 'declined') return Btn('Not interested', small: small, expand: true, kind: BtnKind.secondary);
    return Btn('Send interest', icon: Icons.favorite_rounded, small: small, expand: true, onPressed: () => sendInterest(context, p, onChanged));
  }
}

class MatchCard extends StatelessWidget {
  const MatchCard(this.p, {super.key, required this.onChanged});
  final J p;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final reasons = (p['match_reasons'] as List? ?? []).cast<String>();
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => context.push('/p/${p['public_id']}'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: AspectRatio(
            aspectRatio: 4 / 3.2,
            child: Stack(fit: StackFit.expand, children: [
              Avatar(name: p['name'] as String, seed: p['public_id'] as String, photo: p['photo_url'] as String?, locked: p['photo_locked'] == true, size: 400, radius: 0),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.transparent, Color(0xCC3B0A20)]))),
              if (p['match_score'] != null)
                Positioned(left: 12, top: 12, child: Pill('${p['match_score']}% match', icon: Icons.auto_awesome_rounded, fg: C.brand700, bg: Colors.white)),
              if (p['is_premium'] == true)
                Positioned(right: 12, top: 12, child: const Pill('Premium', fg: C.brand950, bg: C.gold300)),
              Positioned(
                left: 16,
                right: 16,
                bottom: 12,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p['name']}, ${p['age']}', style: display(22, color: Colors.white)),
                  if (p['last_active'] != null)
                    Row(children: [
                      const Icon(Icons.circle, size: 8, color: Color(0xFF34D399)),
                      const SizedBox(width: 6),
                      Text(p['last_active'] as String, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                    ]),
                ]),
              ),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text([heightLabel(p['height_cm'], withCm: false), p['community'] ?? p['religion'], p['mother_tongue']].whereType<String>().join(' · '),
                style: const TextStyle(color: C.muted, fontSize: 13.5)),
            const SizedBox(height: 10),
            for (final (icon, color, text) in [
              (Icons.place_rounded, C.brand400, p['city'] == null ? null : '${p['city']}, ${p['state']}'),
              (Icons.work_rounded, C.gold500, p['occupation']),
              (Icons.school_rounded, C.violet, p['education']),
            ])
              if (text != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [Icon(icon, size: 16, color: color), const SizedBox(width: 8), Expanded(child: Text(text as String, style: const TextStyle(fontSize: 14)))]),
                ),
            if (reasons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [for (final r in reasons) Pill(r, fg: C.brand700, bg: C.brand50)]),
            ],
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: InterestAction(p, onChanged: onChanged)),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: p['shortlisted'] == true ? 'Remove from shortlist' : 'Shortlist',
                style: IconButton.styleFrom(side: const BorderSide(color: C.line)),
                onPressed: () => toggleShortlist(context, p, onChanged),
                icon: Icon(p['shortlisted'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: C.brand600),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}
