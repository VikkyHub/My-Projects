import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/labels.dart';
import '../../core/theme.dart';
import '../../widgets/match_card.dart';
import '../../widgets/ui.dart';

class MatchesTab extends StatefulWidget {
  const MatchesTab({super.key});
  @override
  State<MatchesTab> createState() => _MatchesTabState();
}

class _MatchesTabState extends State<MatchesTab> {
  String mode = 'recommended';
  final filters = <String, Object?>{};
  final items = <J>[];
  String? cursor, err;
  bool loading = false, done = false;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _load();
    });
  }

  Future<void> _load({bool reset = false}) async {
    if (loading || (!reset && done)) return;
    setState(() {
      loading = true;
      err = null;
      if (reset) {
        items.clear();
        cursor = null;
        done = false;
      }
    });
    try {
      final q = <String, dynamic>{'mode': mode, for (final e in filters.entries) if (e.value != null && e.value != false) e.key: e.value, 'cursor': cursor}
        ..removeWhere((_, v) => v == null);
      final r = await memberApi.get('/matches', query: q) as Map;
      setState(() {
        items.addAll((r['items'] as List).cast<Map>().map((e) => Map<String, dynamic>.from(e)));
        cursor = r['next_cursor'] as String?;
        done = cursor == null;
      });
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _refreshOne() => _load(reset: true);

  @override
  Widget build(BuildContext context) => RefreshIndicator(
        color: C.brand600,
        onRefresh: () => _load(reset: true),
        child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 12, 16, 100), children: [
          HeroPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('DISCOVER', style: TextStyle(color: C.gold200, fontSize: 12, letterSpacing: 1.5, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text('Your matches', style: display(30, color: Colors.white)),
              const SizedBox(height: 6),
              Text(mode == 'recommended' ? 'People who fit what you want — and would be happy to hear from you.' : 'Everyone on the platform, filtered your way.',
                  style: TextStyle(color: Colors.white.withValues(alpha: .8))),
              const SizedBox(height: 16),
              Btn('Partner preferences', icon: Icons.tune_rounded, kind: BtnKind.gold, small: true, onPressed: () async {
                final changed = await showModalBottomSheet<bool>(context: context, isScrollControlled: true, builder: (_) => const PreferencesSheet());
                if (changed == true) _load(reset: true);
              }),
            ]),
          ),
          const SizedBox(height: 14),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'recommended', label: Text('Recommended'), icon: Icon(Icons.auto_awesome_rounded)),
              ButtonSegment(value: 'all', label: Text('Search all'), icon: Icon(Icons.search_rounded)),
            ],
            selected: {mode},
            onSelectionChanged: (s) {
              setState(() => mode = s.first);
              _load(reset: true);
            },
            style: SegmentedButton.styleFrom(selectedBackgroundColor: C.brand600, selectedForegroundColor: Colors.white),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              _filterChip('Age', filters['age_min'] != null || filters['age_max'] != null ? '${filters['age_min'] ?? 18}–${filters['age_max'] ?? 60}' : null, _ageSheet),
              _masterFilter('Religion', 'religion_id', 'religions'),
              _masterFilter('Mother tongue', 'mother_tongue_id', 'mother-tongues'),
              _masterFilter('State', 'state_id', 'states'),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('With photo'),
                  selected: filters['with_photo'] == true,
                  onSelected: (v) {
                    setState(() => filters['with_photo'] = v);
                    _load(reset: true);
                  },
                ),
              ),
              if (filters.values.any((v) => v != null && v != false))
                TextButton(onPressed: () { setState(filters.clear); _load(reset: true); }, child: const Text('Clear')),
            ]),
          ),
          const SizedBox(height: 12),
          if (err != null) ErrorBox(err),
          for (final p in items) Padding(padding: const EdgeInsets.only(bottom: 16), child: MatchCard(p, onChanged: _refreshOne)),
          if (loading) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator(color: C.brand600))),
          if (!loading && items.isEmpty && err == null)
            EmptyState(
              icon: Icons.people_alt_rounded,
              title: mode == 'recommended' ? 'No recommended matches yet' : 'No one matches these filters',
              text: mode == 'recommended'
                  ? 'Recommendations check preferences both ways. Widen your partner preferences, or search everyone.'
                  : 'Try removing a filter or two.',
              action: mode == 'recommended'
                  ? Btn('Search all profiles', icon: Icons.search_rounded, kind: BtnKind.secondary, onPressed: () { setState(() => mode = 'all'); _load(reset: true); })
                  : null,
            ),
        ]),
      );

  Widget _filterChip(String label, String? value, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          label: Text(value == null ? '$label: Any' : '$label: $value'),
          avatar: const Icon(Icons.expand_more_rounded, size: 18),
          backgroundColor: value == null ? Colors.white : C.brand50,
          side: BorderSide(color: value == null ? C.line : C.brand200),
          onPressed: onTap,
        ),
      );

  Widget _masterFilter(String label, String key, String path) => FutureBuilder<List<J>>(
        future: Master.list(path),
        builder: (_, s) => _filterChip(label, Master.nameOf(s.data, filters[key]), () async {
          final list = s.data ?? [];
          final v = await showModalBottomSheet<Object>(
            context: context,
            builder: (_) => SafeArea(
              child: ListView(shrinkWrap: true, children: [
                ListTile(title: Text('$label: Any'), onTap: () => Navigator.pop(context, 'any')),
                for (final e in list) ListTile(title: Text(e['name'] as String), selected: filters[key] == e['id'], onTap: () => Navigator.pop(context, e['id'])),
              ]),
            ),
          );
          if (v == null) return;
          setState(() => filters[key] = v == 'any' ? null : v);
          _load(reset: true);
        }),
      );

  Future<void> _ageSheet() async {
    var r = RangeValues(((filters['age_min'] as int?) ?? 18).toDouble(), ((filters['age_max'] as int?) ?? 60).toDouble());
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Age ${r.start.round()} – ${r.end.round()}', style: display(20)),
            RangeSlider(values: r, min: 18, max: 60, divisions: 42, activeColor: C.brand600, onChanged: (v) => set(() => r = v)),
            Btn('Apply', expand: true, onPressed: () => Navigator.pop(ctx, true)),
          ]),
        ),
      ),
    );
    if (ok != true) return;
    setState(() {
      filters['age_min'] = r.start.round();
      filters['age_max'] = r.end.round();
    });
    _load(reset: true);
  }
}

class PreferencesSheet extends StatefulWidget {
  const PreferencesSheet({super.key});
  @override
  State<PreferencesSheet> createState() => _PreferencesSheetState();
}

class _PreferencesSheetState extends State<PreferencesSheet> {
  J? v;
  String? err;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    memberApi.get('/profiles/me/preferences').then((d) => setState(() => v = Map<String, dynamic>.from(d as Map)));
  }

  List<T> _list<T>(String k) => (v?[k] as List?)?.cast<T>() ?? <T>[];

  Widget _master(String label, String key, String path) => FutureBuilder<List<J>>(
        future: Master.list(path),
        builder: (_, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          FieldLabel(label),
          ChipSelect<int>(
            options: [for (final e in s.data ?? <J>[]) (e['id'] as int, e['name'] as String)],
            value: _list<int>(key),
            onChanged: (x) => setState(() => v![key] = x.isEmpty ? null : x),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .92,
        builder: (_, sc) => v == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 30), children: [
                Text('Partner preferences', style: display(24)),
                const SizedBox(height: 4),
                const Text('Recommended matches use these, and only show people whose own preferences fit you too.', style: TextStyle(color: C.muted)),
                const FieldLabel('Age'),
                RangeSlider(
                  values: RangeValues(((v!['age_min'] as int?) ?? 18).toDouble(), ((v!['age_max'] as int?) ?? 60).toDouble()),
                  min: 18,
                  max: 60,
                  divisions: 42,
                  activeColor: C.brand600,
                  labels: RangeLabels('${v!['age_min'] ?? 18}', '${v!['age_max'] ?? 60}'),
                  onChanged: (r) => setState(() {
                    v!['age_min'] = r.start.round();
                    v!['age_max'] = r.end.round();
                  }),
                ),
                const FieldLabel('Marital status'),
                ChipSelect<String>(options: maritalLabels.entries.map((e) => (e.key, e.value)).toList(), value: _list<String>('marital_statuses'),
                    onChanged: (x) => setState(() => v!['marital_statuses'] = x.isEmpty ? null : x)),
                _master('Religion', 'religion_ids', 'religions'),
                _master('Mother tongue', 'mother_tongue_ids', 'mother-tongues'),
                _master('Lives in (state)', 'state_ids', 'states'),
                const FieldLabel('Diet'),
                ChipSelect<String>(options: diet.entries.map((e) => (e.key, e.value)).toList(), value: _list<String>('diets'),
                    onChanged: (x) => setState(() => v!['diets'] = x.isEmpty ? null : x)),
                const FieldLabel('Minimum income'),
                Pick<int>(value: v!['min_income_band'] as int?, hint: 'Any', items: [for (var i = 1; i < incomeBands.length; i++) (i, incomeBands[i])],
                    onChanged: (x) => setState(() => v!['min_income_band'] = x)),
                ErrorBox(err),
                const SizedBox(height: 20),
                Row(children: [
                  Btn('Reset', kind: BtnKind.ghost, onPressed: () => setState(() => v = {for (final k in v!.keys) k: null})),
                  const Spacer(),
                  Btn('Save preferences', loading: busy, onPressed: () async {
                    setState(() => busy = true);
                    try {
                      await memberApi.put('/profiles/me/preferences', v);
                      if (context.mounted) Navigator.pop(context, true);
                    } on ApiError catch (e) {
                      setState(() => err = e.message);
                    } finally {
                      if (mounted) setState(() => busy = false);
                    }
                  }),
                ]),
              ]),
      );
}
