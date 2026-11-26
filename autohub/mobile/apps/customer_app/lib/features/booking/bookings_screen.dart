import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final myBookingsProvider = FutureProvider.autoDispose<CachedResult<dynamic>>((ref) => ref.watch(apiProvider).getCached('/bookings'));

class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(myBookingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t.myBookings)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myBookingsProvider)),
        data: (r) {
          final items = ((r.data as Map)['data'] as List).cast<Map<String, dynamic>>();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(myBookingsProvider.future),
            child: items.isEmpty
                ? ListView(children: [Padding(padding: const EdgeInsets.all(48), child: Center(child: Text(t.noBookings)))])
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length + (r.fromCache ? 1 : 0),
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      if (r.fromCache && i == 0) return const OfflineBanner();
                      final b = items[i - (r.fromCache ? 1 : 0)];
                      final start = DateTime.parse(b['scheduledStart'] as String).toLocal();
                      final total = b['finalTotalPaise'] ?? b['quotedTotalPaise'];
                      return Card(
                        child: ListTile(
                          onTap: () async {
                            await context.push('/bookings/${b['id']}');
                            ref.invalidate(myBookingsProvider);
                          },
                          title: Text(b['vendorName'] as String),
                          subtitle: Text('${b['vehicleModel']} · ${start.day}/${start.month} ${start.hour.toString().padLeft(2, '0')}:'
                              '${start.minute.toString().padLeft(2, '0')} · ${formatPaise(total as num)}'),
                          trailing: StatusChip(b['status'] as String),
                        ),
                      );
                    },
                  ),
          );
        },
      ),
    );
  }
}
