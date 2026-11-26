import 'dart:async';

import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

final bookingProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  return await ref.watch(apiProvider).get('/bookings/$id') as Map<String, dynamic>;
});

/// Live booking page: timeline, estimate approval, payments, cancel.
/// Polls every 15 s while the job is active (Socket.IO push replaces this in Phase 2).
class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({super.key, required this.bookingId});
  final String bookingId;
  @override
  ConsumerState<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  Timer? _poll;
  final _declined = <String>{};
  bool _busy = false;

  static const _active = {'requested', 'confirmed', 'vehicle_received', 'estimate_shared', 'in_progress', 'ready'};

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 15), (_) {
      final b = ref.read(bookingProvider(widget.bookingId)).asData?.value;
      if (b != null && _active.contains(b['status'])) ref.invalidate(bookingProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _act(Future<void> Function(ApiClient api) f) async {
    setState(() => _busy = true);
    try {
      await f(ref.read(apiProvider));
      ref.invalidate(bookingProvider(widget.bookingId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pay(String purpose) => _act((api) async {
        final payment = await api.post('/bookings/${widget.bookingId}/payments', {'purpose': purpose}) as Map<String, dynamic>;
        if (!mounted) return;
        final r = await PaymentLauncher.pay(context, api, payment);
        if (r != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).paymentSuccess)));
        }
      });

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final async = ref.watch(bookingProvider(widget.bookingId));
    return Scaffold(
      appBar: AppBar(title: Text(async.asData?.value['bookingNumber'] as String? ?? '')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(bookingProvider(widget.bookingId))),
        data: (b) => RefreshIndicator(
          onRefresh: () => ref.refresh(bookingProvider(widget.bookingId).future),
          child: _content(context, t, b),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, AppLocalizations t, Map<String, dynamic> b) {
    final theme = Theme.of(context);
    final actions = b['actions'] as Map<String, dynamic>;
    final payments = b['payments'] as Map<String, dynamic>;
    final vendor = b['vendor'] as Map<String, dynamic>;
    final estimate = b['estimate'] as Map<String, dynamic>?;
    final start = DateTime.parse(b['scheduledStart'] as String).toLocal();

    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [StatusChip(b['status'] as String), const Spacer(), if (_busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))]),
      const SizedBox(height: 12),
      Text(vendor['businessName'] as String, style: theme.textTheme.titleLarge),
      Text('${(b['vehicle'] as Map)['label']}'),
      Text('${start.day}/${start.month}/${start.year} · ${b['localTime']}'),
      const SizedBox(height: 8),
      Row(children: [
        OutlinedButton.icon(
            icon: const Icon(Icons.call, size: 18), label: const Text('Call'), onPressed: () => launchUrl(Uri.parse('tel:${vendor['phone']}'))),
      ]),
      const Divider(height: 32),
      for (final s in (b['services'] as List).cast<Map<String, dynamic>>())
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: Text(s['name'] as String),
          trailing: Text(s['pricePaise'] == null ? t.priceOnInspection : formatPaise(s['pricePaise'] as num)),
        ),
      if (estimate != null) ...[
        const Divider(height: 32),
        Text('${t.estimate} v${estimate['version']}', style: theme.textTheme.titleMedium),
        if (estimate['vendorNote'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(estimate['vendorNote'] as String)),
        for (final i in (estimate['items'] as List).cast<Map<String, dynamic>>())
          i['isOptional'] == true && estimate['status'] == 'pending'
              ? CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: !_declined.contains(i['id']),
                  onChanged: (v) => setState(() => v == true ? _declined.remove(i['id']) : _declined.add(i['id'] as String)),
                  title: Text(i['description'] as String),
                  subtitle: Text(t.optionalItem),
                  secondary: Text(formatPaise((i['unitPricePaise'] as num) * (num.parse('${i['quantity']}')))),
                )
              : ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(i['description'] as String,
                      style: i['isAccepted'] == false ? const TextStyle(decoration: TextDecoration.lineThrough) : null),
                  trailing: Text(formatPaise((i['unitPricePaise'] as num) * (num.parse('${i['quantity']}')))),
                ),
        _totalRow(t.subtotal, estimate['subtotalPaise'] as num),
        _totalRow(t.gst, estimate['taxPaise'] as num),
        _totalRow(t.total, estimate['totalPaise'] as num, bold: true),
        if (actions['canApproveEstimate'] == true)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(children: [
              OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => _act((api) => api.post('/bookings/${b['id']}/estimates/${estimate['id']}/reject', {})),
                child: Text(t.rejectEstimate),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  key: const Key('approve-estimate'),
                  onPressed: _busy
                      ? null
                      : () => _act((api) => api.post('/bookings/${b['id']}/estimates/${estimate['id']}/approve',
                          {'declinedItemIds': _declined.toList()})),
                  child: Text(t.approveEstimate),
                ),
              ),
            ]),
          ),
      ],
      const Divider(height: 32),
      if (payments['finalTotalPaise'] != null) _totalRow(t.total, payments['finalTotalPaise'] as num),
      _totalRow('Paid', payments['amountPaidPaise'] as num),
      if (payments['balanceDuePaise'] != null) _totalRow(t.balanceDue, payments['balanceDuePaise'] as num, bold: true),
      const SizedBox(height: 12),
      if (actions['canPayAdvance'] == true)
        FilledButton(onPressed: _busy ? null : () => _pay('booking_advance'), child: Text(t.payNow(formatPaise((payments['advancePaise'] as num) - (payments['amountPaidPaise'] as num))))),
      if (actions['canPayBalance'] == true)
        FilledButton(onPressed: _busy ? null : () => _pay('booking_balance'), child: Text(t.payNow(formatPaise(payments['balanceDuePaise'] as num)))),
      if (actions['canCancel'] == true)
        TextButton(onPressed: _busy ? null : () => _act((api) => api.post('/bookings/${b['id']}/cancel', {})), child: Text(t.cancelBooking)),
      const Divider(height: 32),
      Text(t.bookingTimeline, style: theme.textTheme.titleMedium),
      for (final e in (b['timeline'] as List).cast<Map<String, dynamic>>())
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle_outline, size: 20),
          title: Text(bookingStatusLabel(t, e['status'] as String)),
          subtitle: e['note'] != null ? Text(e['note'] as String) : null,
          trailing: Text(_hhmm(DateTime.parse(e['at'] as String).toLocal())),
        ),
    ]);
  }

  Widget _totalRow(String label, num paise, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Text(label, style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
          const Spacer(),
          Text(formatPaise(paise), style: bold ? const TextStyle(fontWeight: FontWeight.bold) : null),
        ]),
      );

  static String _hhmm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
