import 'dart:async';

import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// The customer's saved cars (cached for offline use).
final vehiclesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final r = await ref.watch(apiProvider).getCached('/me/vehicles');
  return (r.data as List).cast<Map<String, dynamic>>();
});

/// Which car the parts list is filtered for. null = all cars.
class SelectedVehicle extends Notifier<String?> {
  bool _userChose = false;
  @override
  String? build() {
    final vehicles = ref.watch(vehiclesProvider).asData?.value ?? const [];
    if (_userChose) return stateOrNull;
    return vehicles.where((v) => v['isDefault'] == true).firstOrNull?['id'] as String?;
  }

  void select(String? id) {
    _userChose = true;
    state = id;
  }
}

final selectedVehicleProvider = NotifierProvider<SelectedVehicle, String?>(SelectedVehicle.new);

String vehicleLabel(Map<String, dynamic> v) =>
    '${v['modelName']} ${v['manufactureYear']}${v['registrationNumber'] != null ? ' · ${v['registrationNumber']}' : ''}';

/// Spare-parts search: fitment-aware, paginated, offline-first.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});
  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  final _items = <Map<String, dynamic>>[];
  String? _cursor;
  bool _hasMore = true;
  bool _loading = false;
  bool _offline = false;
  Object? _error;
  String _sort = 'relevance';
  int _generation = 0;   // drops responses from superseded searches

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Map<String, dynamic> _query() => {
        'q': _search.text.trim().isEmpty ? null : _search.text.trim(),
        'vehicleId': ref.read(selectedVehicleProvider),
        'sort': _sort,
        'limit': 20,
        'cursor': _cursor,
      };

  Future<void> _reload() async {
    _generation++;
    setState(() {
      _items.clear();
      _cursor = null;
      _hasMore = true;
      _error = null;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final r = await ref.read(apiProvider).getCached('/products', query: _query());
      if (gen != _generation || !mounted) return;
      final body = r.data as Map<String, dynamic>;
      setState(() {
        _items.addAll((body['data'] as List).cast<Map<String, dynamic>>());
        _cursor = body['nextCursor'] as String?;
        _hasMore = body['hasMore'] == true && !r.fromCache;
        _offline = r.fromCache;
      });
    } catch (e) {
      if (gen == _generation && mounted) setState(() => _error = e);
    } finally {
      if (gen == _generation && mounted) setState(() => _loading = false);
    }
  }

  void _onSearchChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _reload);
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    ref.listen(selectedVehicleProvider, (_, _) => _reload());
    final vehicles = ref.watch(vehiclesProvider).asData?.value ?? const [];
    final selected = ref.watch(selectedVehicleProvider);
    final selectedVehicle = vehicles.where((v) => v['id'] == selected).firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _search,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t.searchParts,
            prefixIcon: const Icon(Icons.search),
            border: InputBorder.none,
            isDense: true,
          ),
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort),
            initialValue: _sort,
            onSelected: (v) {
              _sort = v;
              _reload();
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'relevance', child: Text(t.sortRelevance)),
              PopupMenuItem(value: 'price_asc', child: Text(t.sortPriceLow)),
              PopupMenuItem(value: 'price_desc', child: Text(t.sortPriceHigh)),
              PopupMenuItem(value: 'rating', child: Text(t.sortRating)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), children: [
            for (final v in vehicles)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  avatar: const Icon(Icons.directions_car, size: 18),
                  label: Text(vehicleLabel(v)),
                  selected: v['id'] == selected,
                  onSelected: (_) => ref.read(selectedVehicleProvider.notifier).select(v['id'] as String),
                ),
              ),
            ChoiceChip(
              label: Text(t.allVehicles),
              selected: selected == null,
              onSelected: (_) => ref.read(selectedVehicleProvider.notifier).select(null),
            ),
          ]),
        ),
        if (_offline) const OfflineBanner(),
        if (selectedVehicle != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(t.forVehicle(vehicleLabel(selectedVehicle)), style: Theme.of(context).textTheme.labelMedium),
            ),
          ),
        Expanded(child: _body(t)),
      ]),
    );
  }

  Widget _body(AppLocalizations t) {
    if (_error != null && _items.isEmpty) return ErrorView(error: _error!, onRetry: _reload);
    if (_items.isEmpty && _loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) return Center(child: Text(t.noResults));
    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView.separated(
        controller: _scroll,
        padding: const EdgeInsets.all(12),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, i) {
          if (i >= _items.length) {
            return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
          }
          return ProductTile(product: _items[i]);
        },
      ),
    );
  }
}

class ProductTile extends StatelessWidget {
  const ProductTile({super.key, required this.product});
  final Map<String, dynamic> product;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final p = product;
    final theme = Theme.of(context);
    final vendor = p['vendor'] as Map<String, dynamic>;
    final fit = p['fit'] as String?;
    final discount = (p['discountPercent'] as num?)?.toInt() ?? 0;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/products/${p['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: p['thumbnailUrl'] == null
                  ? Container(width: 84, height: 84, color: theme.colorScheme.surfaceContainerHighest, child: const Icon(Icons.image))
                  : Image.network(
                      p['thumbnailUrl'] as String,
                      width: 84,
                      height: 84,
                      fit: BoxFit.cover,
                      cacheWidth: 168,   // decode small: saves memory on 2 GB phones
                      errorBuilder: (_, _, _) => const SizedBox(width: 84, height: 84, child: Icon(Icons.broken_image)),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  [(p['brand'] as Map?)?['name'], (p['partType'] as String).toUpperCase(), p['partNumber']].whereType<String>().join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Row(children: [
                  Text(formatPaise(p['pricePaise'] as num), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  if (discount > 0) ...[
                    Text(formatPaise(p['mrpPaise'] as num),
                        style: theme.textTheme.bodySmall?.copyWith(decoration: TextDecoration.lineThrough)),
                    const SizedBox(width: 6),
                    Text('$discount% off', style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700)),
                  ],
                ]),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (fit == 'fits') _Tag(Icons.check_circle, t.fitsYourCar, Colors.green.shade700),
                  if (fit == 'universal') _Tag(Icons.all_inclusive, t.universalFit, theme.colorScheme.primary),
                  if (fit == 'does_not_fit') _Tag(Icons.cancel, t.doesNotFit, theme.colorScheme.error),
                  if (p['inStock'] != true) _Tag(Icons.remove_shopping_cart, t.outOfStock, theme.colorScheme.error),
                  if (p['deliveryEta'] == 'today') _Tag(Icons.local_shipping_outlined, t.deliveryToday, theme.colorScheme.secondary),
                  if (p['deliveryEta'] == 'tomorrow') _Tag(Icons.local_shipping_outlined, t.deliveryTomorrow, theme.colorScheme.secondary),
                ]),
                const SizedBox(height: 4),
                Text(
                  '${vendor['businessName']}${vendor['distanceKm'] != null ? ' · ${t.kmAway('${vendor['distanceKm']}')}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.icon, this.label, this.color);
  final IconData icon;
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
      ]);
}
