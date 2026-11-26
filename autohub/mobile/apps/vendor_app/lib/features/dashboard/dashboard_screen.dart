import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

final dashboardProvider = FutureProvider.autoDispose<CachedResult<dynamic>>((ref) {
  // Re-fetch when the user switches shop.
  ref.watch(sessionProvider).activeVendor;
  return ref.watch(apiProvider).getCached('/vendor/dashboard');
});

/// Vendor home: today's numbers, what needs attention, today's schedule, 7-day revenue.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final async = ref.watch(dashboardProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(session.activeVendor?.businessName ?? t.dashboard),
        actions: [
          if (session.memberships.length > 1)
            PopupMenuButton<VendorMembership>(
              icon: const Icon(Icons.swap_horiz),
              onSelected: session.selectVendor,
              itemBuilder: (_) => [for (final m in session.memberships) PopupMenuItem(value: m, child: Text(m.businessName))],
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            onSelected: session.setLanguage,
            itemBuilder: (_) => [for (final e in supportedLanguages.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
          ),
          IconButton(tooltip: t.logout, icon: const Icon(Icons.logout), onPressed: session.logout),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(dashboardProvider)),
        data: (r) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: DashboardBody(data: r.data as Map<String, dynamic>, fromCache: r.fromCache),
        ),
      ),
    );
  }
}

class DashboardBody extends StatelessWidget {
  const DashboardBody({super.key, required this.data, this.fromCache = false});
  final Map<String, dynamic> data;
  final bool fromCache;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final today = data['today'] as Map<String, dynamic>;
    final bookings = today['bookings'] as Map<String, dynamic>;
    final earnings = data['earnings'] as Map<String, dynamic>?;
    final actions = (data['actionItems'] as List).cast<Map<String, dynamic>>();
    final schedule = (today['schedule'] as List).cast<Map<String, dynamic>>();
    final vendor = data['vendor'] as Map<String, dynamic>;

    return ListView(padding: const EdgeInsets.all(16), children: [
      if (fromCache) const Padding(padding: EdgeInsets.only(bottom: 12), child: OfflineBanner()),
      if (vendor['status'] != 'approved')
        Card(
          color: theme.colorScheme.tertiaryContainer,
          child: ListTile(
            leading: const Icon(Icons.hourglass_top),
            title: Text('Shop status: ${vendor['status']}'),
            subtitle: vendor['statusReason'] != null ? Text(vendor['statusReason'] as String) : null,
          ),
        ),
      Row(children: [
        Text('★ ${vendor['ratingAvg']} (${vendor['ratingCount']})', style: theme.textTheme.titleSmall),
        const Spacer(),
        Text(vendor['isAcceptingOrders'] == true ? t.openNow : t.closed),
      ]),
      const SizedBox(height: 12),
      // Two columns that grow with their content (survives large system font sizes).
      LayoutBuilder(builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final k in [
            _Kpi(t.todayBookings, '${bookings['total']}', '${bookings['requested']} new · ${bookings['inProgress']} active'),
            if (today['revenuePaise'] != null) _Kpi(t.revenueToday, formatPaise(today['revenuePaise'] as num), ''),
            _Kpi(t.newOrders, '${today['newOrders']}', '${today['ordersToDispatch']} ${t.toDispatch.toLowerCase()}'),
            if (earnings != null)
              _Kpi(t.availableBalance, formatPaise(earnings['availablePaise'] as num), '${t.onHold} ${formatPaise(earnings['onHoldPaise'] as num)}'),
          ])
            SizedBox(width: w, child: k),
        ]);
      }),
      if (actions.isNotEmpty) ...[
        const SizedBox(height: 20),
        Text(t.needsAttention, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final a in actions)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(switch (a['type']) {
              'low_stock' => Icons.inventory_2_outlined,
              'order_pending_acceptance' => Icons.shopping_bag_outlined,
              _ => Icons.event_available,
            }),
            title: Text(a['label'] as String),
            subtitle: Text((a['type'] as String).replaceAll('_', ' ')),
            trailing: const Icon(Icons.chevron_right),
            onTap: (a['type'] as String).startsWith('booking') ? () => context.push('/bookings/${a['id']}') : null,
          ),
      ],
      const SizedBox(height: 20),
      Text(t.todaySchedule, style: theme.textTheme.titleMedium),
      if (schedule.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(t.nothingScheduled)),
      for (final s in schedule)
        Card(
          margin: const EdgeInsets.only(top: 8),
          child: ListTile(
            leading: Text(s['localTime'] as String, style: theme.textTheme.titleMedium),
            title: Text('${s['model']} · ${s['registrationNumber'] ?? ''}'),
            subtitle: Text('${s['customerName'] ?? ''} · ${s['serviceNames'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: StatusChip(s['status'] as String),
            onTap: () => context.push('/bookings/${s['id']}'),
          ),
        ),
      const SizedBox(height: 20),
      Text(t.last7Days, style: theme.textTheme.titleMedium),
      const SizedBox(height: 8),
      RevenueBars(days: (data['last7Days'] as List).cast<Map<String, dynamic>>()),
    ]);
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.sub);
  final String label, value, sub;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(value, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold), maxLines: 1),
          if (sub.isNotEmpty) Text(sub, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

/// Seven bars, no chart library: one less dependency and nothing heavy to render on low-end phones.
class RevenueBars extends StatelessWidget {
  const RevenueBars({super.key, required this.days});
  final List<Map<String, dynamic>> days;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = days.map((d) => (d['revenuePaise'] as num?)?.toDouble() ?? 0).toList();
    final max = values.fold<double>(0, (a, b) => b > a ? b : a);
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Tooltip(
              message: '${days[i]['date']}: ${formatPaise(values[i])} · ${days[i]['bookings']} bookings',
              child: Column(children: [
                Text(values[i] == 0 ? '' : '₹${(values[i] / 100000).toStringAsFixed(1)}k', style: theme.textTheme.labelSmall),
                const SizedBox(height: 2),
                // Bars take whatever height is left, so labels never push the chart out of its box.
                Expanded(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: max == 0 ? 0.02 : (values[i] / max).clamp(0.02, 1.0),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: i == days.length - 1 ? theme.colorScheme.primary : theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text((days[i]['date'] as String).substring(8), style: theme.textTheme.labelSmall),
              ]),
            ),
          ),
      ]),
    );
  }
}
