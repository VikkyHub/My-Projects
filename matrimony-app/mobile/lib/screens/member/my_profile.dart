import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class MyProfileTab extends StatefulWidget {
  const MyProfileTab({super.key});
  @override
  State<MyProfileTab> createState() => _MyProfileTabState();
}

class _MyProfileTabState extends State<MyProfileTab> {
  List<J> photos = [];
  String visibility = 'all';
  final lk = <String, List<J>>{};

  @override
  void initState() {
    super.initState();
    _photos();
    memberApi.get('/profiles/me/photo-settings').then((d) => setState(() => visibility = (d as Map)['photo_visibility'] as String));
    for (final k in ['religions', 'mother-tongues', 'cities', 'education-levels', 'occupations']) {
      Master.list(k).then((v) => setState(() => lk[k] = v));
    }
    _communities();
  }

  void _communities() {
    final p = appState.me;
    if (p == null) return;
    Master.list('communities?religion_id=${p['religion_id']}').then((v) => setState(() => lk['communities'] = v));
    if (p['community_id'] != null) Master.list('sub-communities?community_id=${p['community_id']}').then((v) => setState(() => lk['subs'] = v));
  }

  Future<void> _photos() async {
    final d = await memberApi.get('/profiles/me/photos') as List;
    setState(() => photos = d.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
  }

  Future<void> _patch(J body) async {
    final p = Map<String, dynamic>.from(await memberApi.patch('/profiles/me', body) as Map);
    appState.setMe(p);
    _communities();
  }

  String? n(String list, Object? id) => Master.nameOf(lk[list], id);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: appState,
        builder: (_, _) {
          final p = appState.me;
          if (p == null) return const Center(child: CircularProgressIndicator());
          final career = p['career'] as Map?, family = p['family'] as Map?, horo = p['horoscope'] as Map?;
          final main = photos.where((x) => x['is_primary'] == true).firstOrNull;
          final city = lk['cities']?.where((c) => c['id'] == p['city_id']).firstOrNull;
          final checklist = [
            ('Basic details', true),
            ('About me (50+ characters)', ((p['about_me'] as String?)?.length ?? 0) >= 50),
            ('Diet & lifestyle', p['diet'] != null),
            ('Family details', family?['father_occupation'] != null || family?['family_type'] != null),
            ('Education', career?['education_level_id'] != null),
            ('Occupation & income', career?['occupation_id'] != null && career?['annual_income_band'] != null),
            ('Photos', photos.isNotEmpty),
          ];
          final status = switch (p['status']) {
            'active' => ('Live', C.green, C.greenBg),
            'draft' => ('Awaiting consent', C.amber, C.amberBg),
            'rejected' => ('Needs changes', C.red, C.redBg),
            'suspended' => ('Suspended', C.red, C.redBg),
            _ => ('Under review', C.amber, C.amberBg),
          };
          return RefreshIndicator(
            onRefresh: () async {
              await appState.loadMe();
              await _photos();
            },
            child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), children: [
              // Cover + identity
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(children: [
                  SizedBox(
                    height: 110,
                    child: HeroPanel(
                      radius: 0,
                      padding: const EdgeInsets.all(12),
                      child: Align(alignment: Alignment.topRight, child: Pill(status.$1, fg: status.$2, bg: Colors.white)),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -48),
                    child: Column(children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [C.gold200, C.gold400, C.brand500])),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: Avatar(name: '${p['first_name']} ${p['last_name'] ?? ''}', seed: p['public_id'] as String, photo: main?['url'] as String?, size: 96),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('${p['first_name']} ${p['last_name'] ?? ''}'.trim(), style: display(26)),
                      const SizedBox(height: 4),
                      Text(
                        ['${p['age']} yrs', heightLabel(p['height_cm'], withCm: false), n('religions', p['religion_id']), n('communities', p['community_id']), city?['name']]
                            .whereType<String>()
                            .join(' · '),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: C.muted),
                      ),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, children: [
                        const Pill('Mobile verified', icon: Icons.verified_rounded, fg: C.green, bg: C.greenBg),
                        Pill(p['public_id'] as String, icon: Icons.tag_rounded),
                        if (p['created_by'] != 'self') Pill('Managed by ${p['created_by']}', fg: C.gold600, bg: C.gold50),
                      ]),
                    ]),
                  ),
                ]),
              ),
              if (p['candidate_consent_pending'] == true) ...[const SizedBox(height: 14), _ConsentCard(p)],
              if (p['moderation_note'] != null) ...[
                const SizedBox(height: 14),
                AppCard(
                  color: const Color(0xFFFFF7ED),
                  border: const Color(0xFFFED7AA),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const IconChip(Icons.warning_amber_rounded, fg: Colors.white, bg: Color(0xFFF97316)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p['status'] == 'rejected' ? 'Please update your profile' : 'A note from our safety team', style: display(17)),
                        const SizedBox(height: 4),
                        Text(p['moderation_note'] as String, style: const TextStyle(height: 1.4)),
                        if (p['status'] == 'rejected')
                          const Padding(padding: EdgeInsets.only(top: 6), child: Text('Save your changes below and your profile goes back for review automatically.', style: TextStyle(fontSize: 12, color: C.muted))),
                      ]),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 14),
              AppCard(
                child: Column(children: [
                  Row(children: [
                    ProgressRing(p['completeness'] as int, size: 88),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Profile strength', style: display(19)),
                        const SizedBox(height: 4),
                        Text((p['completeness'] as int) >= 90 ? "Excellent! You're ready to shine." : 'Complete profiles get up to 3× more interest.', style: const TextStyle(color: C.muted, fontSize: 13)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  for (final (label, ok) in checklist)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 20, color: ok ? const Color(0xFF10B981) : C.line),
                        const SizedBox(width: 10),
                        Text(label, style: TextStyle(color: ok ? C.muted : C.ink, decoration: ok ? TextDecoration.lineThrough : null, fontWeight: ok ? null : FontWeight.w600)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              _photosCard(),
              const SizedBox(height: 14),
              _section('Basic details', Icons.person_rounded, C.brand600, C.brand50, false, Facts([
                ('Name', '${p['first_name']} ${p['last_name'] ?? ''}'.trim()),
                ('Date of birth', p['dob'] as String),
                ('Gender', p['gender'] == 'female' ? 'Female' : 'Male'),
                ('Marital status', maritalLabels[p['marital_status']]),
                ('Height', heightLabel(p['height_cm'])),
                ('Religion', n('religions', p['religion_id'])),
                ('Community', n('communities', p['community_id'])),
                ('Sub-community', n('subs', p['sub_community_id'])),
                ('Mother tongue', n('mother-tongues', p['mother_tongue_id'])),
                ('City', city == null ? null : '${city['name']}, ${city['state']}'),
              ]), () => _editBasic(p)),
              _section('About & lifestyle', Icons.auto_awesome_rounded, const Color(0xFFF43F5E), const Color(0xFFFFF1F2), p['about_me'] == null && p['diet'] == null, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (p['about_me'] != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(color: C.sand.withValues(alpha: .6), borderRadius: BorderRadius.circular(16)),
                    child: Text('“${p['about_me']}”', style: display(16, weight: FontWeight.w500, style: FontStyle.italic).copyWith(height: 1.45)),
                  ),
                Facts([('Diet', diet[p['diet']]), ('Smoking', habit[p['smoke']]), ('Drinking', habit[p['drink']])]),
              ]), () => _editAbout(p)),
              _section('Education & career', Icons.work_rounded, C.gold500, C.gold50, career == null, Facts([
                ('Highest education', n('education-levels', career?['education_level_id'])),
                ('Degree', career?['education_detail'] as String?),
                ('College', career?['college'] as String?),
                ('Occupation', n('occupations', career?['occupation_id'])),
                ('Employed in', employedIn[career?['employed_in']]),
                ('Employer', career?['employer'] as String?),
                ('Annual income', career?['annual_income_band'] == null ? null : incomeBands[career!['annual_income_band'] as int]),
              ]), () => _editCareer(career)),
              _section('Family', Icons.home_rounded, C.teal, C.tealBg, family == null, Facts([
                ('Father', family?['father_occupation'] as String?),
                ('Mother', family?['mother_occupation'] as String?),
                ('Brothers', family?['brothers'] == null ? null : '${family!['brothers']} (${family['brothers_married'] ?? 0} married)'),
                ('Sisters', family?['sisters'] == null ? null : '${family!['sisters']} (${family['sisters_married'] ?? 0} married)'),
                ('Family type', familyType[family?['family_type']]),
                ('Family status', familyStatus[family?['family_status']]),
                ('Family values', familyValues[family?['family_values']]),
                ('Native place', family?['native_place'] as String?),
              ]), () => _editFamily(family)),
              _section('Horoscope', Icons.nightlight_round, C.violet, C.violetBg, horo == null, Facts([
                ('Rashi', horo?['rashi'] as String?),
                ('Nakshatra', horo?['nakshatra'] as String?),
                ('Manglik', manglik[horo?['manglik']]),
                ('Time of birth', (horo?['birth_time'] as String?)?.substring(0, 5)),
                ('Place of birth', horo?['birth_place'] as String?),
                ('Gotra', horo?['gotra'] as String?),
                ('Visible to', visibleTo[horo?['visible_to']]),
              ]), () => _editHoroscope(horo)),
              const SizedBox(height: 4),
              _premiumCard(),
              const SizedBox(height: 14),
              _safetyCard(),
              const SizedBox(height: 20),
              Center(child: Btn('Log out', icon: Icons.logout_rounded, kind: BtnKind.secondary, onPressed: () => appState.signOut())),
            ]),
          );
        },
      );

  Widget _section(String title, IconData icon, Color fg, Color bg, bool empty, Widget view, VoidCallback edit) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconChip(icon, fg: fg, bg: bg),
              const SizedBox(width: 12),
              Expanded(child: Text(title, style: display(18))),
              Btn(empty ? 'Add' : 'Edit', icon: empty ? Icons.add_rounded : Icons.edit_rounded, small: true, kind: empty ? BtnKind.secondary : BtnKind.ghost, onPressed: edit),
            ]),
            const Divider(height: 28),
            if (empty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: C.sand.withValues(alpha: .6), borderRadius: BorderRadius.circular(16)),
                child: const Text('Not added yet — profiles with this section get more responses.', style: TextStyle(color: C.muted, fontSize: 13)),
              )
            else
              view,
          ]),
        ),
      );

  // ---------------- photos ----------------
  Widget _photosCard() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconChip(Icons.photo_camera_rounded, fg: Color(0xFFF43F5E), bg: Color(0xFFFFF1F2)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Photos', style: display(18)),
                Text('${photos.length} of 6 · location data removed', style: const TextStyle(fontSize: 12, color: C.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.lock_rounded, size: 16, color: C.muted),
            const SizedBox(width: 6),
            const Text('Visible to', style: TextStyle(color: C.muted, fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: Pick<String>(
                value: visibility,
                items: photoVisibility.entries.map((e) => (e.key, e.value)).toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => visibility = v);
                  await memberApi.put('/profiles/me/photo-settings', {'photo_visibility': v});
                },
              ),
            ),
          ]),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 3 / 4,
            children: [
              for (final ph in photos)
                GestureDetector(
                  onTap: () => _photoMenu(ph),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(fit: StackFit.expand, children: [
                      CachedNetworkImage(imageUrl: Config.media(ph['url'] as String)!, fit: BoxFit.cover),
                      if (ph['is_primary'] == true) const Positioned(left: 6, top: 6, child: Pill('Main', icon: Icons.star_rounded, fg: C.brand950, bg: C.gold300)),
                      if (ph['status'] == 'pending') const Positioned(left: 6, bottom: 6, child: Pill('In review', icon: Icons.schedule_rounded, fg: C.amber, bg: Colors.white)),
                    ]),
                  ),
                ),
              if (photos.length < 6)
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _addPhoto,
                  child: Container(
                    decoration: BoxDecoration(color: C.brand50.withValues(alpha: .6), borderRadius: BorderRadius.circular(16), border: Border.all(color: C.brand200, width: 2)),
                    child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.add_photo_alternate_rounded, color: C.brand600, size: 30),
                      SizedBox(height: 6),
                      Text('Add photo', style: TextStyle(color: C.brand700, fontWeight: FontWeight.w700, fontSize: 13)),
                    ]),
                  ),
                ),
            ],
          ),
        ]),
      );

  Future<void> _addPhoto() async {
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
    final x = await ImagePicker().pickImage(source: src, maxWidth: 2000, imageQuality: 90);
    if (x == null) return;
    if (!mounted) return;
    snack(context, 'Uploading…');
    try {
      final d = await memberApi.post('/profiles/me/photos', FormData.fromMap({'file': await MultipartFile.fromFile(x.path, filename: 'photo.jpg')})) as List;
      setState(() => photos = d.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      await appState.loadMe();
      if (mounted) snack(context, 'Photo added — our team will review it shortly');
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  Future<void> _photoMenu(J ph) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (ph['is_primary'] != true)
            ListTile(leading: const Icon(Icons.star_rounded, color: C.gold500), title: const Text('Make main photo'), onTap: () => Navigator.pop(context, 'primary')),
          ListTile(leading: const Icon(Icons.delete_rounded, color: C.red), title: const Text('Delete photo'), onTap: () => Navigator.pop(context, 'delete')),
        ]),
      ),
    );
    if (a == null) return;
    try {
      final d = (a == 'primary' ? await memberApi.post('/profiles/me/photos/${ph['id']}/primary') : await memberApi.delete('/profiles/me/photos/${ph['id']}')) as List;
      setState(() => photos = d.cast<Map>().map((e) => Map<String, dynamic>.from(e)).toList());
      await appState.loadMe();
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    }
  }

  // ---------------- edit sheets ----------------
  Future<void> _sheet(String title, Widget Function(StateSetter set) fields, Future<void> Function() save) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) {
          String? err;
          bool busy = false;
          return StatefulBuilder(
            builder: (ctx, set) => Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * .88),
                child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
                  Text(title, style: display(22)),
                  fields(set),
                  ErrorBox(err),
                  const SizedBox(height: 18),
                  Btn('Save', expand: true, loading: busy, onPressed: () async {
                    set(() {
                      busy = true;
                      err = null;
                    });
                    try {
                      await save();
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on ApiError catch (e) {
                      set(() => err = e.message);
                    } finally {
                      if (ctx.mounted) set(() => busy = false);
                    }
                  }),
                ]),
              ),
            ),
          );
        },
      );

  List<(int, String)> _opts(String k) => [for (final e in lk[k] ?? <J>[]) (e['id'] as int, e['name'] as String)];
  String? _s(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  void _editBasic(J p) {
    final first = TextEditingController(text: p['first_name'] as String), last = TextEditingController(text: p['last_name'] as String? ?? '');
    var v = <String, dynamic>{
      'marital_status': p['marital_status'], 'height_cm': p['height_cm'], 'religion_id': p['religion_id'], 'community_id': p['community_id'],
      'sub_community_id': p['sub_community_id'], 'mother_tongue_id': p['mother_tongue_id'], 'city_id': p['city_id'],
    };
    var comms = lk['communities'] ?? <J>[], subs = lk['subs'] ?? <J>[];
    _sheet('Basic details', (set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          const Text("Gender and date of birth can't be changed here — ask Help if they're wrong.", style: TextStyle(fontSize: 12.5, color: C.muted)),
          const FieldLabel('First name'),
          TextField(controller: first, textCapitalization: TextCapitalization.words),
          const FieldLabel('Last name', optional: true),
          TextField(controller: last, textCapitalization: TextCapitalization.words),
          const FieldLabel('Marital status'),
          Pick<String>(value: v['marital_status'] as String?, items: maritalLabels.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['marital_status'] = x)),
          const FieldLabel('Height'),
          Pick<int>(value: v['height_cm'] as int?, items: [for (final h in heights) (h.cm, '${h.label} (${h.cm} cm)')], onChanged: (x) => set(() => v['height_cm'] = x)),
          const FieldLabel('Religion'),
          Pick<int>(value: v['religion_id'] as int?, items: _opts('religions'), onChanged: (x) async {
            set(() {
              v = {...v, 'religion_id': x, 'community_id': null, 'sub_community_id': null};
              comms = [];
              subs = [];
            });
            if (x != null) {
              final c = await Master.list('communities?religion_id=$x');
              set(() => comms = c);
            }
          }),
          const FieldLabel('Community'),
          Pick<int>(value: v['community_id'] as int?, items: [for (final e in comms) (e['id'] as int, e['name'] as String)], onChanged: (x) async {
            set(() {
              v = {...v, 'community_id': x, 'sub_community_id': null};
              subs = [];
            });
            if (x != null) {
              final s = await Master.list('sub-communities?community_id=$x');
              set(() => subs = s);
            }
          }),
          if (subs.isNotEmpty) ...[
            const FieldLabel('Sub-community', optional: true),
            Pick<int>(value: v['sub_community_id'] as int?, items: [for (final e in subs) (e['id'] as int, e['name'] as String)], onChanged: (x) => set(() => v['sub_community_id'] = x)),
          ],
          const FieldLabel('Mother tongue'),
          Pick<int>(value: v['mother_tongue_id'] as int?, items: _opts('mother-tongues'), onChanged: (x) => set(() => v['mother_tongue_id'] = x)),
          const FieldLabel('City'),
          Pick<int>(value: v['city_id'] as int?, items: [for (final c in lk['cities'] ?? <J>[]) (c['id'] as int, '${c['name']}, ${c['state']}')], onChanged: (x) => set(() => v['city_id'] = x)),
        ]), () => _patch({...v, 'first_name': first.text.trim(), 'last_name': _s(last)}));
  }

  void _editAbout(J p) {
    final about = TextEditingController(text: p['about_me'] as String? ?? '');
    final v = <String, dynamic>{'diet': p['diet'], 'smoke': p['smoke'], 'drink': p['drink']};
    _sheet('About & lifestyle', (set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('About me', hint: "Personality, interests, what you're looking for. No phone numbers, emails or links."),
          TextField(controller: about, maxLines: 5, maxLength: 1000, textCapitalization: TextCapitalization.sentences),
          const FieldLabel('Diet'),
          Pick<String>(value: v['diet'] as String?, items: diet.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['diet'] = x)),
          const FieldLabel('Smoking'),
          Pick<String>(value: v['smoke'] as String?, items: habit.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['smoke'] = x)),
          const FieldLabel('Drinking'),
          Pick<String>(value: v['drink'] as String?, items: habit.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['drink'] = x)),
        ]), () => _patch({...v, 'about_me': _s(about)}));
  }

  void _editCareer(Map? c) {
    final detail = TextEditingController(text: c?['education_detail'] as String? ?? ''), college = TextEditingController(text: c?['college'] as String? ?? ''), employer = TextEditingController(text: c?['employer'] as String? ?? '');
    final v = <String, dynamic>{'education_level_id': c?['education_level_id'], 'occupation_id': c?['occupation_id'], 'employed_in': c?['employed_in'], 'annual_income_band': c?['annual_income_band']};
    _sheet('Education & career', (set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('Highest education'),
          Pick<int>(value: v['education_level_id'] as int?, items: _opts('education-levels'), onChanged: (x) => set(() => v['education_level_id'] = x)),
          const FieldLabel('Degree / specialisation', optional: true),
          TextField(controller: detail, decoration: const InputDecoration(hintText: 'e.g. B.Tech Computer Science')),
          const FieldLabel('College', optional: true),
          TextField(controller: college),
          const FieldLabel('Occupation'),
          Pick<int>(value: v['occupation_id'] as int?, items: _opts('occupations'), onChanged: (x) => set(() => v['occupation_id'] = x)),
          const FieldLabel('Employed in'),
          Pick<String>(value: v['employed_in'] as String?, items: employedIn.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['employed_in'] = x)),
          const FieldLabel('Employer', optional: true, hint: 'Hidden from other members'),
          TextField(controller: employer),
          const FieldLabel('Annual income'),
          Pick<int>(value: v['annual_income_band'] as int?, items: [for (var i = 0; i < incomeBands.length; i++) (i, incomeBands[i])], onChanged: (x) => set(() => v['annual_income_band'] = x)),
        ]), () => _patch({'career': {...v, 'education_detail': _s(detail), 'college': _s(college), 'employer': _s(employer)}}));
  }

  void _editFamily(Map? f) {
    final father = TextEditingController(text: f?['father_occupation'] as String? ?? ''), mother = TextEditingController(text: f?['mother_occupation'] as String? ?? ''), native = TextEditingController(text: f?['native_place'] as String? ?? '');
    final v = <String, dynamic>{
      for (final k in ['brothers', 'brothers_married', 'sisters', 'sisters_married', 'family_type', 'family_status', 'family_values']) k: f?[k],
    };
    List<(int, String)> counts() => [for (var i = 0; i <= 5; i++) (i, '$i')];
    _sheet('Family', (set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel("Father's occupation"),
          TextField(controller: father, decoration: const InputDecoration(hintText: 'e.g. Retired govt. officer')),
          const FieldLabel("Mother's occupation"),
          TextField(controller: mother, decoration: const InputDecoration(hintText: 'e.g. Homemaker')),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const FieldLabel('Brothers'), Pick<int>(value: v['brothers'] as int?, items: counts(), onChanged: (x) => set(() => v['brothers'] = x))])),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const FieldLabel('Married'), Pick<int>(value: v['brothers_married'] as int?, items: counts(), onChanged: (x) => set(() => v['brothers_married'] = x))])),
          ]),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const FieldLabel('Sisters'), Pick<int>(value: v['sisters'] as int?, items: counts(), onChanged: (x) => set(() => v['sisters'] = x))])),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const FieldLabel('Married'), Pick<int>(value: v['sisters_married'] as int?, items: counts(), onChanged: (x) => set(() => v['sisters_married'] = x))])),
          ]),
          const FieldLabel('Family type'),
          Pick<String>(value: v['family_type'] as String?, items: familyType.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['family_type'] = x)),
          const FieldLabel('Family status'),
          Pick<String>(value: v['family_status'] as String?, items: familyStatus.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['family_status'] = x)),
          const FieldLabel('Family values'),
          Pick<String>(value: v['family_values'] as String?, items: familyValues.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['family_values'] = x)),
          const FieldLabel('Native place', optional: true),
          TextField(controller: native),
        ]), () => _patch({'family': {...v, 'father_occupation': _s(father), 'mother_occupation': _s(mother), 'native_place': _s(native)}}));
  }

  void _editHoroscope(Map? h) {
    final place = TextEditingController(text: h?['birth_place'] as String? ?? ''), gotra = TextEditingController(text: h?['gotra'] as String? ?? '');
    final v = <String, dynamic>{'rashi': h?['rashi'], 'nakshatra': h?['nakshatra'], 'manglik': h?['manglik'], 'birth_time': (h?['birth_time'] as String?)?.substring(0, 5), 'visible_to': h?['visible_to'] ?? 'accepted'};
    _sheet('Horoscope', (set) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const FieldLabel('Rashi (moon sign)'),
          Pick<String>(value: v['rashi'] as String?, items: [for (final r in rashis) (r, r)], onChanged: (x) => set(() => v['rashi'] = x)),
          const FieldLabel('Nakshatra'),
          Pick<String>(value: v['nakshatra'] as String?, items: [for (final r in nakshatras) (r, r)], onChanged: (x) => set(() => v['nakshatra'] = x)),
          const FieldLabel('Manglik'),
          Pick<String>(value: v['manglik'] as String?, items: manglik.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['manglik'] = x)),
          const FieldLabel('Time of birth', optional: true),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule_rounded),
            label: Text((v['birth_time'] as String?) ?? 'Select time'),
            onPressed: () async {
              final t = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 6, minute: 0));
              if (t != null) set(() => v['birth_time'] = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
            },
          ),
          const FieldLabel('Place of birth', optional: true),
          TextField(controller: place),
          const FieldLabel('Gotra', optional: true),
          TextField(controller: gotra),
          const FieldLabel('Who can see my horoscope'),
          Pick<String>(value: v['visible_to'] as String?, items: visibleTo.entries.map((e) => (e.key, e.value)).toList(), onChanged: (x) => set(() => v['visible_to'] = x)),
        ]), () => _patch({'horoscope': {...v, 'birth_place': _s(place), 'gotra': _s(gotra)}}));
  }

  Widget _premiumCard() => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.gold100, C.gold50, Colors.white]), borderRadius: BorderRadius.circular(24), border: Border.all(color: C.gold200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const IconChip(Icons.workspace_premium_rounded, fg: Colors.white, bg: C.gold400),
          const SizedBox(height: 12),
          Text('Go Premium', style: display(20)),
          const Text('Connect faster with the people you like.', style: TextStyle(color: C.muted)),
          const SizedBox(height: 10),
          for (final (i, t) in [(Icons.phone_rounded, 'View verified contact numbers'), (Icons.chat_bubble_rounded, 'Chat with people you match'), (Icons.auto_awesome_rounded, 'Stand out in search results')])
            Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [Icon(i, size: 16, color: C.gold500), const SizedBox(width: 10), Text(t, style: const TextStyle(fontWeight: FontWeight.w600))])),
          const SizedBox(height: 14),
          const Btn('Plans coming soon', kind: BtnKind.gold, expand: true),
        ]),
      );

  Widget _safetyCard() => AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [const IconChip(Icons.shield_rounded, fg: C.teal, bg: C.tealBg), const SizedBox(width: 12), Text('Stay safe', style: display(18))]),
          const SizedBox(height: 10),
          for (final t in ['Never send money or share OTPs, bank or card details.', "Meet first in a public place, and tell family where you'll be.", 'Keep your address and workplace private until you trust someone.'])
            Padding(padding: const EdgeInsets.only(top: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Icon(Icons.check_rounded, size: 18, color: C.teal), const SizedBox(width: 8), Expanded(child: Text(t))])),
        ]),
      );
}

/// Parent/sibling-created profile: send an OTP to the candidate, then confirm.
class _ConsentCard extends StatefulWidget {
  const _ConsentCard(this.p);
  final J p;
  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends State<_ConsentCard> {
  bool sent = false, busy = false;
  String code = '';
  String? err;

  Future<void> _go(Future<void> Function() f) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await f();
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.gold50, Colors.white, C.brand50]), borderRadius: BorderRadius.circular(24), border: Border.all(color: C.gold200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const IconChip(Icons.verified_user_rounded, fg: Colors.white, bg: C.gold400),
            const SizedBox(width: 12),
            Expanded(child: Text("One last step: ${widget.p['first_name']}'s consent", style: display(18))),
          ]),
          const SizedBox(height: 8),
          Text('The profile stays hidden until ${widget.p['first_name']} confirms with an OTP sent to ${widget.p['candidate_phone_masked']}.', style: const TextStyle(height: 1.4)),
          const SizedBox(height: 14),
          if (!sent)
            Btn('Send OTP to ${widget.p['first_name']}', icon: Icons.send_rounded, kind: BtnKind.gold, loading: busy, onPressed: () => _go(() async {
                  await memberApi.post('/profiles/me/candidate-consent/send');
                  setState(() => sent = true);
                }))
          else ...[
            OtpField(onChanged: (v) => setState(() => code = v)),
            const SizedBox(height: 12),
            Btn('Confirm consent', expand: true, loading: busy, onPressed: code.length == 6
                ? () => _go(() async => appState.setMe(Map<String, dynamic>.from(await memberApi.post('/profiles/me/candidate-consent/verify', {'code': code}) as Map)))
                : null),
          ],
          ErrorBox(err),
        ]),
      );
}
