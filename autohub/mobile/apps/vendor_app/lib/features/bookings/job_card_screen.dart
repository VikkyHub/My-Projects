import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final jobProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, id) async => await ref.watch(apiProvider).get('/vendor/bookings/$id') as Map<String, dynamic>);

/// One booking from the workshop's side: confirm → check in → estimate → start → ready.
class JobCardScreen extends ConsumerStatefulWidget {
  const JobCardScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  ConsumerState<JobCardScreen> createState() => _JobCardScreenState();
}

class _JobCardScreenState extends ConsumerState<JobCardScreen> {
  bool _busy = false;

  Future<void> _post(String action, [Map<String, dynamic> body = const {}]) async {
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/vendor/bookings/${widget.bookingId}/$action', body);
      ref.invalidate(jobProvider(widget.bookingId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject() async {
    final ctrl = TextEditingController();
    final t = AppLocalizations.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.reject),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Reason (shown to the customer)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: Text(t.reject)),
        ],
      ),
    );
    if (reason != null && reason.isNotEmpty) await _post('reject', {'reason': reason});
  }

  Future<void> _estimate() async {
    final items = await Navigator.of(context).push<List<Map<String, dynamic>>>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => const EstimateBuilder()),
    );
    if (items != null && items.isNotEmpty) await _post('estimates', {'items': items});
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(jobProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(title: Text(async.asData?.value['bookingNumber'] as String? ?? '')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(jobProvider(widget.bookingId))),
        data: (b) {
          final theme = Theme.of(context);
          final a = b['actions'] as Map<String, dynamic>;
          final customer = b['customer'] as Map<String, dynamic>;
          final estimate = b['estimate'] as Map<String, dynamic>?;
          final payments = b['payments'] as Map<String, dynamic>;
          final settlement = b['settlement'] as Map<String, dynamic>?;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Row(children: [StatusChip(b['status'] as String), const Spacer(), Text(b['localTime'] as String, style: theme.textTheme.titleMedium)]),
            const SizedBox(height: 12),
            Text('${(b['vehicle'] as Map)['label']}', style: theme.textTheme.titleLarge),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(customer['name'] as String? ?? '—'),
              subtitle: Text(customer['phone'] as String),
              trailing: (customer['phone'] as String).contains('•')
                  ? null
                  : IconButton(icon: const Icon(Icons.call), onPressed: () => launchUrl(Uri.parse('tel:${customer['phone']}'))),
            ),
            if (b['customerNotes'] != null)
              Card(child: Padding(padding: const EdgeInsets.all(12), child: Text('“${b['customerNotes']}”'))),
            const SizedBox(height: 8),
            for (final s in (b['services'] as List).cast<Map<String, dynamic>>())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(s['name'] as String),
                trailing: Text(s['pricePaise'] == null ? t.priceOnInspection : formatPaise(s['pricePaise'] as num)),
              ),
            if (estimate != null) ...[
              const Divider(height: 24),
              Text('${t.estimate} v${estimate['version']} · ${estimate['status']}', style: theme.textTheme.titleSmall),
              Text('${t.total}: ${formatPaise(estimate['totalPaise'] as num)} (${t.gst} ${formatPaise(estimate['taxPaise'] as num)})'),
            ],
            const Divider(height: 24),
            Text('Paid ${formatPaise(payments['amountPaidPaise'] as num)}'
                '${payments['balanceDuePaise'] != null ? ' · ${t.balanceDue} ${formatPaise(payments['balanceDuePaise'] as num)}' : ''}'),
            if (settlement != null) ...[
              const SizedBox(height: 8),
              Text('Your payout: ${formatPaise(settlement['vendorPayoutPaise'] as num)}', style: theme.textTheme.titleSmall),
              Text('Commission ${formatPaise(settlement['commissionPaise'] as num)} + GST ${formatPaise(settlement['commissionGstPaise'] as num)}'
                  ' · TCS ${formatPaise(settlement['tcsPaise'] as num)} · TDS ${formatPaise(settlement['tdsPaise'] as num)}',
                  style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (a['canConfirm'] == true) FilledButton(onPressed: _busy ? null : () => _post('confirm'), child: Text(t.confirm)),
              if (a['canReject'] == true) OutlinedButton(onPressed: _busy ? null : _reject, child: Text(t.reject)),
              if (a['canCheckIn'] == true) FilledButton(onPressed: _busy ? null : () => _post('check-in'), child: Text(t.checkIn)),
              if (a['canSendEstimate'] == true) FilledButton.tonal(onPressed: _busy ? null : _estimate, child: Text(t.sendEstimate)),
              if (a['canStart'] == true) OutlinedButton(onPressed: _busy ? null : () => _post('start'), child: Text(t.startWork)),
              if (a['canMarkReady'] == true) FilledButton(onPressed: _busy ? null : () => _post('ready'), child: Text(t.markReady)),
            ]),
            const Divider(height: 32),
            for (final e in (b['timeline'] as List).cast<Map<String, dynamic>>())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline, size: 18),
                title: Text(bookingStatusLabel(t, e['status'] as String)),
                subtitle: e['note'] != null ? Text(e['note'] as String) : null,
              ),
          ]);
        },
      ),
    );
  }
}

/// Minimal job-card estimate editor: lines of (kind, description, ₹ excl. GST, optional?). Server computes GST.
class EstimateBuilder extends StatefulWidget {
  const EstimateBuilder({super.key});
  @override
  State<EstimateBuilder> createState() => _EstimateBuilderState();
}

class _Line {
  String kind = 'service';
  final desc = TextEditingController();
  final amount = TextEditingController();
  bool optional = false;
}

class _EstimateBuilderState extends State<EstimateBuilder> {
  final _lines = <_Line>[_Line()];

  int get _subtotal => _lines.fold(0, (s, l) => s + (parseRupeesToPaise(l.amount.text) ?? 0) * (l.kind == 'discount' ? -1 : 1));

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t.sendEstimate), actions: [
        TextButton(
          onPressed: () {
            final items = <Map<String, dynamic>>[];
            for (final l in _lines) {
              final paise = parseRupeesToPaise(l.amount.text);
              if (l.desc.text.trim().isEmpty || paise == null || paise <= 0) continue;
              items.add({
                'kind': l.kind,
                'description': l.desc.text.trim(),
                'quantity': 1,
                'unitPricePaise': l.kind == 'discount' ? -paise : paise,
                'gstRateBps': 1800,
                'isOptional': l.optional,
              });
            }
            Navigator.pop(context, items);
          },
          child: Text(t.save),
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final l in _lines)
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(children: [
                  DropdownButton<String>(
                    value: l.kind,
                    items: const ['service', 'part', 'labour', 'consumable', 'discount']
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: (v) => setState(() => l.kind = v!),
                  ),
                  const Spacer(),
                  Text(t.optionalItem, style: Theme.of(context).textTheme.bodySmall),
                  Switch(value: l.optional, onChanged: (v) => setState(() => l.optional = v)),
                ]),
                TextField(controller: l.desc, decoration: InputDecoration(labelText: t.description)),
                const SizedBox(height: 8),
                TextField(
                  controller: l.amount,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(labelText: t.amountRupees, prefixText: '₹ '),
                  onChanged: (_) => setState(() {}),
                ),
              ]),
            ),
          ),
        OutlinedButton.icon(onPressed: () => setState(() => _lines.add(_Line())), icon: const Icon(Icons.add), label: Text(t.addLine)),
        const SizedBox(height: 16),
        Text('${t.subtotal}: ${formatPaise(_subtotal)}  +  ${t.gst} 18%', textAlign: TextAlign.end),
      ]),
    );
  }
}
