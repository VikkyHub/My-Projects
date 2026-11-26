import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/config.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../widgets/match_card.dart';
import '../../widgets/ui.dart';

class ProfileViewScreen extends StatefulWidget {
  const ProfileViewScreen(this.publicId, {super.key});
  final String publicId;
  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  late Future<J> _f = _load();
  int _photo = 0;
  Future<J> _load() async => Map<String, dynamic>.from(await memberApi.get('/profiles/${widget.publicId}') as Map);
  void _reload() => setState(() => _f = _load());

  Widget _block(String title, IconData icon, Color fg, Color bg, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [IconChip(icon, fg: fg, bg: bg), const SizedBox(width: 12), Text(title, style: display(18))]),
            const SizedBox(height: 14),
            child,
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Profile'), actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'report') {
                await reportSheet(context, widget.publicId);
              } else if (v == 'block') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Block this person?'),
                    content: const Text("You won't see each other anywhere, and any chat closes."),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Block', style: TextStyle(color: C.red))),
                    ],
                  ),
                );
                if (ok == true) {
                  try {
                    await memberApi.post('/profiles/${widget.publicId}/block');
                    if (context.mounted) {
                      snack(context, 'Blocked');
                      context.pop();
                    }
                  } on ApiError catch (e) {
                    if (context.mounted) snack(context, e.message);
                  }
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'report', child: ListTile(leading: Icon(Icons.flag_rounded, color: C.gold500), title: Text('Report profile'))),
              PopupMenuItem(value: 'block', child: ListTile(leading: Icon(Icons.block_rounded, color: C.red), title: Text('Block'))),
            ],
          ),
        ]),
        body: PatternBg(
          child: Loader<J>(
            future: _f,
            onRetry: _reload,
            builder: (p) {
              final photos = (p['photos'] as List).cast<String>();
              final reasons = (p['match_reasons'] as List).cast<String>();
              final career = p['career'] as Map?, family = p['family'] as Map?, horo = p['horoscope'] as Map?;
              return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: AspectRatio(
                    aspectRatio: 4 / 5,
                    child: Stack(fit: StackFit.expand, children: [
                      if (photos.isEmpty)
                        Avatar(name: p['name'] as String, seed: p['public_id'] as String, size: 400, radius: 0)
                      else
                        PageView(
                          onPageChanged: (i) => setState(() => _photo = i),
                          children: [for (final u in photos) CachedNetworkImage(imageUrl: Config.media(u)!, fit: BoxFit.cover)],
                        ),
                      if (p['photo_locked'] == true)
                        Container(
                          color: C.brand950.withValues(alpha: .35),
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(30),
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            const CircleAvatar(radius: 28, backgroundColor: Colors.white, child: Icon(Icons.lock_rounded, color: C.brand700)),
                            const SizedBox(height: 10),
                            const Text('Photos are private', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                            Text("${p['first_name']} shares photos once you're connected.", textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
                          ]),
                        ),
                      if (p['match_score'] != null)
                        Positioned(left: 14, top: 14, child: Pill('${p['match_score']}% match', icon: Icons.auto_awesome_rounded, fg: C.brand700, bg: Colors.white)),
                      if (photos.length > 1 && p['photo_locked'] != true)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            for (var i = 0; i < photos.length; i++)
                              Container(width: 8, height: 8, margin: const EdgeInsets.all(3), decoration: BoxDecoration(shape: BoxShape.circle, color: i == _photo ? Colors.white : Colors.white54)),
                          ]),
                        ),
                    ]),
                  ),
                ),
                const SizedBox(height: 14),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p['name'] as String, style: display(28)),
                    const SizedBox(height: 4),
                    Text(
                      [
                        '${p['age']} yrs',
                        heightLabel(p['height_cm'], withCm: false),
                        maritalLabels[p['marital_status']],
                        if (p['city'] != null) '${p['city']}, ${p['state']}',
                      ].whereType<String>().join(' · '),
                      style: const TextStyle(color: C.muted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (p['is_premium'] == true) const Pill('Premium', fg: C.gold600, bg: C.gold50),
                      if (p['last_active'] != null) Pill(p['last_active'] as String, fg: C.green, bg: C.greenBg),
                      Pill(p['public_id'] as String),
                      for (final r in reasons) Pill(r, fg: C.brand700, bg: C.brand50),
                    ]),
                    if (p['about_full'] != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(color: C.sand.withValues(alpha: .6), borderRadius: BorderRadius.circular(18)),
                        child: Text('“${p['about_full']}”', style: display(17, weight: FontWeight.w500, style: FontStyle.italic).copyWith(height: 1.45)),
                      ),
                    ],
                    if (p['created_by'] != 'self')
                      Padding(padding: const EdgeInsets.only(top: 10), child: Text('Profile managed by their ${p['created_by']}.', style: const TextStyle(color: C.muted, fontSize: 13))),
                  ]),
                ),
                const SizedBox(height: 14),
                _block('Basics', Icons.person_rounded, C.brand600, C.brand50, Facts([
                  ('Religion', p['religion'] as String?), ('Community', p['community'] as String?), ('Mother tongue', p['mother_tongue'] as String?),
                  ('Diet', diet[p['diet']]), ('Smoking', habit[p['smoke']]), ('Drinking', habit[p['drink']]),
                ])),
                if (career != null)
                  _block('Education & career', Icons.work_rounded, C.gold500, C.gold50, Facts([
                    ('Education', career['education'] as String?), ('Degree', career['education_detail'] as String?), ('College', career['college'] as String?),
                    ('Occupation', career['occupation'] as String?), ('Employed in', employedIn[career['employed_in']]),
                    ('Annual income', career['annual_income_band'] == null ? null : incomeBands[career['annual_income_band'] as int]),
                  ])),
                if (family != null)
                  _block('Family', Icons.home_rounded, C.teal, C.tealBg, Facts([
                    ('Father', family['father_occupation'] as String?), ('Mother', family['mother_occupation'] as String?),
                    ('Brothers', family['brothers'] == null ? null : '${family['brothers']} (${family['brothers_married'] ?? 0} married)'),
                    ('Sisters', family['sisters'] == null ? null : '${family['sisters']} (${family['sisters_married'] ?? 0} married)'),
                    ('Family type', familyType[family['family_type']]), ('Family status', familyStatus[family['family_status']]),
                    ('Family values', familyValues[family['family_values']]), ('Native place', family['native_place'] as String?),
                  ])),
                if (horo != null || p['horoscope_locked'] == true)
                  _block('Horoscope', Icons.nightlight_round, C.violet, C.violetBg, horo != null
                      ? Facts([
                          ('Rashi', horo['rashi'] as String?), ('Nakshatra', horo['nakshatra'] as String?), ('Manglik', manglik[horo['manglik']]),
                          ('Time of birth', horo['birth_time'] as String?), ('Place of birth', horo['birth_place'] as String?), ('Gotra', horo['gotra'] as String?),
                        ])
                      : Text("${p['first_name']} shares horoscope details after you're connected.", style: const TextStyle(color: C.muted))),
                const Center(child: Text('Contact details are never shown on profiles.', style: TextStyle(fontSize: 12, color: C.muted))),
                _bottom(p),
              ]);
            },
          ),
        ),
      );

  Widget _bottom(J p) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(children: [
          Expanded(child: InterestAction(p, small: false, onChanged: _reload)),
          const SizedBox(width: 10),
          IconButton.outlined(
            style: IconButton.styleFrom(side: const BorderSide(color: C.line), padding: const EdgeInsets.all(12)),
            onPressed: () => toggleShortlist(context, p, _reload),
            icon: Icon(p['shortlisted'] == true ? Icons.favorite_rounded : Icons.favorite_border_rounded, color: C.brand600),
          ),
        ]),
      );
}

Future<void> reportSheet(BuildContext context, String publicId, {int? messageId}) async {
  String? reason;
  final details = TextEditingController();
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Report', style: display(22)),
          const FieldLabel("What's wrong?"),
          Pick<String>(value: reason, items: reportReasons.entries.map((e) => (e.key, e.value)).toList(), onChanged: (v) => set(() => reason = v)),
          const FieldLabel('Details', optional: true),
          TextField(controller: details, maxLines: 3, decoration: const InputDecoration(hintText: 'Anything that helps us review faster')),
          const SizedBox(height: 16),
          Btn('Submit report', expand: true, onPressed: reason == null
              ? null
              : () async {
                  try {
                    await memberApi.post('/profiles/$publicId/report', {'reason': reason, 'details': details.text.isEmpty ? null : details.text, 'message_id': messageId});
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      snack(context, 'Thank you — our safety team will review this.');
                    }
                  } on ApiError catch (e) {
                    if (ctx.mounted) snack(ctx, e.message);
                  }
                }),
        ]),
      ),
    ),
  );
}
