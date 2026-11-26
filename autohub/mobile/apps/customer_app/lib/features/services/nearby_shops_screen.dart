import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

/// Search centre. MVP uses Pune city centre; Phase 2 swaps in the device location (geolocator)
/// or the default saved address, and adds the Google Maps view.
const _defaultLat = 18.5204, _defaultLng = 73.8567;

final domainProvider = NotifierProvider<_Domain, String>(_Domain.new);

class _Domain extends Notifier<String> {
  @override
  String build() => 'service';
  void set(String d) => state = d;
}

final nearbyProvider = FutureProvider<CachedResult<dynamic>>((ref) {
  final domain = ref.watch(domainProvider);
  return ref.watch(apiProvider).getCached('/vendors/nearby',
      query: {'lat': _defaultLat, 'lng': _defaultLng, 'radiusKm': 25, 'domain': domain});
});

class NearbyShopsScreen extends ConsumerWidget {
  const NearbyShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final domain = ref.watch(domainProvider);
    final async = ref.watch(nearbyProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(t.nearbyShops),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'service', icon: const Icon(Icons.build_outlined), label: Text(t.tabServices)),
                const ButtonSegment(value: 'decor', icon: Icon(Icons.auto_awesome_outlined), label: Text('Decor')),
              ],
              selected: {domain},
              onSelectionChanged: (s) => ref.read(domainProvider.notifier).set(s.first),
            ),
          ),
        ),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(nearbyProvider)),
        data: (r) {
          final shops = ((r.data as Map)['data'] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(nearbyProvider.future),
            child: ListView(padding: const EdgeInsets.all(12), children: [
              if (r.fromCache) const OfflineBanner(),
              for (final s in shops) Padding(padding: const EdgeInsets.only(bottom: 8), child: _ShopCard(shop: s)),
            ]),
          );
        },
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});
  final Map<String, dynamic> shop;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final rating = shop['rating'] as Map<String, dynamic>;
    final loc = shop['location'] as Map<String, dynamic>;
    final open = shop['isOpenNow'] == true;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundImage: shop['logoUrl'] != null ? NetworkImage(shop['logoUrl'] as String) : null,
              child: shop['logoUrl'] == null ? const Icon(Icons.storefront) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop['businessName'] as String, style: theme.textTheme.titleMedium),
                Text('★ ${rating['avg']} (${rating['count']}) · ${t.kmAway('${shop['distanceKm']}')}', style: theme.textTheme.bodySmall),
              ]),
            ),
            Text(open ? t.openNow : t.closed,
                style: TextStyle(color: open ? Colors.green.shade700 : theme.colorScheme.error, fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 8),
          Text(shop['address'] as String, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.directions, size: 18),
              label: const Text('Map'),
              onPressed: () => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${loc['lat']},${loc['lng']}'),
                  mode: LaunchMode.externalApplication),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => context.push('/shops/${shop['id']}/book?name=${Uri.encodeComponent(shop['businessName'] as String)}'),
              child: Text(t.bookService),
            ),
          ]),
        ]),
      ),
    );
  }
}
