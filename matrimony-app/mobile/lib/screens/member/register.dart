import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const steps = ['Profile for', 'Basic details', 'Community', 'Location', 'Review'];
  static const stepIcons = [Icons.groups_rounded, Icons.person_rounded, Icons.account_balance_rounded, Icons.place_rounded, Icons.fact_check_rounded];
  static const whoIcons = {'self': Icons.person_rounded, 'parent': Icons.family_restroom_rounded, 'sibling': Icons.people_rounded, 'relative': Icons.volunteer_activism_rounded, 'friend': Icons.emoji_emotions_rounded};

  int step = 0;
  String? err;
  bool busy = false;
  String? createdBy, gender;
  final candidatePhone = TextEditingController(), first = TextEditingController(), last = TextEditingController();
  DateTime? dob;
  String marital = 'never_married';
  bool hasChildren = false, accept = false;
  int? religion, community, subCommunity, tongue, city, height;
  List<J> religions = [], communities = [], subs = [], tongues = [], cities = [];

  bool get isSelf => createdBy == 'self';
  DateTime get maxDob {
    final n = DateTime.now();
    return DateTime(n.year - (gender == 'male' ? 21 : 18), n.month, n.day);
  }

  @override
  void initState() {
    super.initState();
    Master.list('religions').then((v) => setState(() => religions = v));
    Master.list('mother-tongues').then((v) => setState(() => tongues = v));
    Master.list('cities').then((v) => setState(() => cities = v));
  }

  Future<void> _loadCommunities(int? r) async {
    setState(() {
      communities = [];
      subs = [];
      community = null;
      subCommunity = null;
    });
    if (r != null) {
      final v = await Master.list('communities?religion_id=$r');
      setState(() => communities = v);
    }
  }

  Future<void> _loadSubs(int? c) async {
    setState(() {
      subs = [];
      subCommunity = null;
    });
    if (c != null) {
      final v = await Master.list('sub-communities?community_id=$c');
      setState(() => subs = v);
    }
  }

  String? _validate() {
    switch (step) {
      case 0:
        if (createdBy == null) return 'Please choose who this profile is for.';
        if (!isSelf && !RegExp(r'^[6-9]\d{9}$').hasMatch(candidatePhone.text)) return "Enter the candidate's 10-digit mobile number.";
      case 1:
        if (gender == null) return 'Please choose bride or groom.';
        if (first.text.trim().isEmpty) return 'Please enter the first name.';
        if (dob == null) return 'Please enter the date of birth.';
        if (dob!.isAfter(maxDob)) return 'Minimum age is ${gender == 'male' ? 21 : 18} years.';
      case 2:
        if (religion == null) return 'Please choose a religion.';
        if (communities.isNotEmpty && community == null) return 'Please choose a community.';
        if (tongue == null) return 'Please choose a mother tongue.';
      case 3:
        if (city == null) return 'Please choose a city.';
        if (height == null) return 'Please choose a height.';
      case 4:
        if (!accept) return 'Please accept the Terms and Privacy Policy.';
    }
    return null;
  }

  Future<void> _next() async {
    final e = _validate();
    setState(() => err = e);
    if (e != null) return;
    if (step < steps.length - 1) return setState(() => step++);
    setState(() => busy = true);
    try {
      final p = Map<String, dynamic>.from(await memberApi.post('/profiles', {
        'created_by': createdBy,
        'candidate_phone': isSelf ? null : '+91${candidatePhone.text}',
        'first_name': first.text.trim(),
        'last_name': last.text.trim().isEmpty ? null : last.text.trim(),
        'gender': gender,
        'dob': dob!.toIso8601String().substring(0, 10),
        'marital_status': marital,
        'has_children': marital == 'never_married' ? false : hasChildren,
        'height_cm': height,
        'religion_id': religion,
        'community_id': community,
        'sub_community_id': subCommunity,
        'mother_tongue_id': tongue,
        'city_id': city,
        'accept_terms': true,
      }) as Map);
      appState.setMe(p);
      if (mounted) context.go('/');
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget _choice({required bool on, required IconData icon, required String title, String? hint, required VoidCallback onTap}) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: on ? C.brand50 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? C.brand500 : C.line, width: on ? 2 : 1),
          ),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: on ? C.brand600 : C.brand50, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: on ? Colors.white : C.brand600),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                if (hint != null) Text(hint, style: const TextStyle(fontSize: 12.5, color: C.muted)),
              ]),
            ),
            if (on) const Icon(Icons.check_circle_rounded, color: C.brand600),
          ]),
        ),
      );

  List<(int, String)> _opts(List<J> l) => [for (final e in l) (e['id'] as int, e['name'] as String)];

  @override
  Widget build(BuildContext context) {
    final body = switch (step) {
      0 => [
          Text('Who is this profile for?', style: display(22)),
          const SizedBox(height: 14),
          for (final (v, title, hint) in createdBy_)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _choice(on: createdBy == v, icon: whoIcons[v]!, title: title, hint: hint, onTap: () => setState(() => createdBy = v)),
            ),
          if (createdBy != null && !isSelf)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.gold50, C.brand50]), borderRadius: BorderRadius.circular(20), border: Border.all(color: C.gold100)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.verified_user_rounded, color: C.gold500),
                  SizedBox(width: 8),
                  Expanded(child: Text('Consent matters. The profile stays hidden until the candidate confirms with an OTP on their own phone.', style: TextStyle(fontSize: 13, height: 1.35))),
                ]),
                const FieldLabel("Candidate's own mobile number"),
                PhoneField(controller: candidatePhone),
              ]),
            ),
        ],
      1 => [
          Text(isSelf ? 'Tell us about yourself' : 'Tell us about them', style: display(22)),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _choice(on: gender == 'female', icon: Icons.local_florist_rounded, title: 'Bride', hint: 'Female', onTap: () => setState(() => gender = 'female'))),
            const SizedBox(width: 10),
            Expanded(child: _choice(on: gender == 'male', icon: Icons.person_rounded, title: 'Groom', hint: 'Male', onTap: () => setState(() => gender = 'male'))),
          ]),
          const FieldLabel('First name'),
          TextField(controller: first, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'e.g. Priya')),
          const FieldLabel('Last name', optional: true, hint: 'Free members see only the initial'),
          TextField(controller: last, textCapitalization: TextCapitalization.words, decoration: const InputDecoration(hintText: 'e.g. Sharma')),
          const FieldLabel('Date of birth', hint: "Can't be changed later"),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () async {
              final d = await showDatePicker(context: context, firstDate: DateTime(1946), lastDate: maxDob, initialDate: dob ?? DateTime(maxDob.year - 4));
              if (d != null) setState(() => dob = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(suffixIcon: Icon(Icons.calendar_month_rounded)),
              child: Text(dob == null ? 'Select date' : '${dob!.day}/${dob!.month}/${dob!.year}', style: TextStyle(color: dob == null ? C.muted : C.ink)),
            ),
          ),
          const FieldLabel('Marital status'),
          Pick<String>(value: marital, items: marital_.entries.map((e) => (e.key, e.value)).toList(), onChanged: (v) => setState(() => marital = v ?? marital)),
          if (marital != 'never_married') CheckboxListTile(value: hasChildren, onChanged: (v) => setState(() => hasChildren = v ?? false), title: const Text('Has children'), contentPadding: EdgeInsets.zero),
        ],
      2 => [
          Text('Religion & community', style: display(22)),
          const FieldLabel('Religion'),
          Pick<int>(value: religion, items: _opts(religions), onChanged: (v) {
            setState(() => religion = v);
            _loadCommunities(v);
          }),
          if (communities.isNotEmpty) ...[
            const FieldLabel('Community / caste'),
            Pick<int>(value: community, items: _opts(communities), onChanged: (v) {
              setState(() => community = v);
              _loadSubs(v);
            }),
          ],
          if (subs.isNotEmpty) ...[
            const FieldLabel('Sub-community', optional: true),
            Pick<int>(value: subCommunity, items: _opts(subs), onChanged: (v) => setState(() => subCommunity = v)),
          ],
          const FieldLabel('Mother tongue'),
          Pick<int>(value: tongue, items: _opts(tongues), onChanged: (v) => setState(() => tongue = v)),
        ],
      3 => [
          Text(isSelf ? 'Where do you live?' : 'Where do they live?', style: display(22)),
          const FieldLabel('City', hint: 'Only the city is shown — never an address'),
          Pick<int>(value: city, items: [for (final c in cities) (c['id'] as int, '${c['name']}, ${c['state']}')], onChanged: (v) => setState(() => city = v)),
          const FieldLabel('Height'),
          Pick<int>(value: height, items: [for (final h in heights) (h.cm, '${h.label} (${h.cm} cm)')], onChanged: (v) => setState(() => height = v)),
        ],
      _ => [
          Text('Looks good?', style: display(22)),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [C.brand50, Colors.white, C.gold50]), borderRadius: BorderRadius.circular(24), border: Border.all(color: C.brand100)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Avatar(name: '${first.text} ${last.text}', seed: first.text, size: 56),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${first.text} ${last.text}'.trim(), style: display(22)),
                    Text('${gender == 'female' ? 'Bride' : 'Groom'} · ${marital_[marital]}', style: const TextStyle(color: C.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              Facts([
                ('Created by', createdBy_.firstWhere((e) => e.$1 == createdBy).$2),
                ('Date of birth', dob == null ? null : '${dob!.day}/${dob!.month}/${dob!.year}'),
                ('Religion', Master.nameOf(religions, religion)),
                ('Community', [Master.nameOf(communities, community), Master.nameOf(subs, subCommunity)].whereType<String>().join(' · ')),
                ('Mother tongue', Master.nameOf(tongues, tongue)),
                ('City', Master.nameOf(cities, city)),
                ('Height', heightLabel(height)),
              ]),
            ]),
          ),
          if (!isSelf)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text("Next, we'll ask the candidate (+91 ${candidatePhone.text}) to confirm with an OTP before the profile goes live.",
                  style: const TextStyle(fontSize: 13, color: C.amber)),
            ),
          CheckboxListTile(
            value: accept,
            onChanged: (v) => setState(() => accept = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('I confirm these details are true and I accept the Terms of Use and Privacy Policy.', style: TextStyle(fontSize: 13.5)),
          ),
        ],
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create your profile'),
        actions: [TextButton(onPressed: () => appState.signOut(), child: const Text('Log out'))],
      ),
      body: PatternBg(
        child: Column(children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Row(children: [
              for (var i = 0; i < steps.length; i++) ...[
                if (i > 0) Expanded(child: Container(height: 2, color: i <= step ? C.brand500 : C.line)),
                CircleAvatar(
                  radius: 17,
                  backgroundColor: i < step ? C.brand600 : (i == step ? C.brand700 : C.sand),
                  child: Icon(i < step ? Icons.check_rounded : stepIcons[i], size: 17, color: i <= step ? Colors.white : C.muted),
                ),
              ],
            ]),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 18, 20, 20), children: [
              Text('STEP ${step + 1} OF ${steps.length} · ${steps[step].toUpperCase()}',
                  style: const TextStyle(fontSize: 11.5, letterSpacing: 1.2, fontWeight: FontWeight.w800, color: C.gold500)),
              const SizedBox(height: 8),
              ...body,
              ErrorBox(err),
            ]),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Row(children: [
                if (step > 0) Btn('Back', icon: Icons.arrow_back_rounded, kind: BtnKind.secondary, onPressed: () => setState(() { err = null; step--; })),
                const Spacer(),
                Btn(step == steps.length - 1 ? 'Create my profile' : 'Continue', icon: step == steps.length - 1 ? null : Icons.arrow_forward_rounded, loading: busy, onPressed: _next),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// aliases so the switch above reads clearly (avoid shadowing state fields)
const createdBy_ = createdByOptions;
const marital_ = maritalLabels;
