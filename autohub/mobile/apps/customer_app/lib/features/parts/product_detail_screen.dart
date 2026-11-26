import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'products_screen.dart';

final productProvider = FutureProvider.family<CachedResult<dynamic>, (String, String?)>((ref, args) {
  final (id, vehicleId) = args;
  return ref.watch(apiProvider).getCached('/products/$id', query: {'vehicleId': vehicleId});
});

class ProductDetailScreen extends ConsumerWidget {
  const ProductDetailScreen({super.key, required this.productId});
  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final vehicleId = ref.watch(selectedVehicleProvider);
    final async = ref.watch(productProvider((productId, vehicleId)));
    return Scaffold(
      appBar: AppBar(),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(productProvider((productId, vehicleId)))),
        data: (r) {
          final p = r.data as Map<String, dynamic>;
          final theme = Theme.of(context);
          final images = (p['images'] as List).cast<Map<String, dynamic>>();
          final vendor = p['vendor'] as Map<String, dynamic>;
          final fit = (p['fitForVehicle'] as Map?)?['fit'] as String?;
          final rating = p['rating'] as Map<String, dynamic>;
          return ListView(children: [
            if (r.fromCache) const OfflineBanner(),
            if (images.isNotEmpty)
              AspectRatio(
                aspectRatio: 1.4,
                child: PageView(children: [
                  for (final img in images) Image.network(img['url'] as String, fit: BoxFit.contain, cacheWidth: 800),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['name'] as String, style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text([(p['brand'] as Map?)?['name'], 'Part no. ${p['partNumber'] ?? '—'}'].whereType<String>().join(' · ')),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(formatPaise(p['pricePaise'] as num), style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('MRP ${formatPaise(p['mrpPaise'] as num)}', style: const TextStyle(decoration: TextDecoration.lineThrough)),
                ]),
                Text('Incl. ${(p['gstRateBps'] as num) / 100}% GST · HSN ${p['hsnCode']}', style: theme.textTheme.bodySmall),
                const SizedBox(height: 12),
                if (fit != null)
                  Card(
                    color: fit == 'does_not_fit' ? theme.colorScheme.errorContainer : theme.colorScheme.primaryContainer,
                    child: ListTile(
                      leading: Icon(fit == 'does_not_fit' ? Icons.cancel : Icons.check_circle),
                      title: Text(switch (fit) {
                        'fits' => t.fitsYourCar,
                        'universal' => t.universalFit,
                        'does_not_fit' => t.doesNotFit,
                        _ => '—',
                      }),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(p['description'] as String? ?? ''),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  Chip(label: Text('${p['warrantyMonths']} mo warranty')),
                  Chip(label: Text('${p['returnWindowDays']}-day returns')),
                  Chip(label: Text('★ ${rating['avg']} (${rating['count']})')),
                ]),
                const SizedBox(height: 16),
                Text('Fits', style: theme.textTheme.titleSmall),
                for (final f in (p['fitments'] as List).cast<Map<String, dynamic>>())
                  Text('• ${f['make']} ${f['model'] ?? ''} ${f['yearFrom'] ?? ''}–${f['yearTo'] ?? 'now'}'),
                if (p['isUniversalFit'] == true) Text('• ${t.universalFit}'),
                const Divider(height: 32),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.storefront),
                  title: Text(vendor['businessName'] as String),
                  subtitle: Text('★ ${vendor['rating']}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.call),
                    onPressed: () => launchUrl(Uri.parse('tel:${vendor['phone']}')),
                  ),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
