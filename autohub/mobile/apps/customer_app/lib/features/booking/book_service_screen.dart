import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../parts/products_screen.dart';

/// Booking flow: choose services → day + slot → notes → confirm → pay advance (Razorpay) → booking page.
class BookServiceScreen extends ConsumerStatefulWidget {
  const BookServiceScreen({super.key, required this.vendorId, required this.vendorName});
  final String vendorId;
  final String vendorName;

  @override
  ConsumerState<BookServiceScreen> createState() => _BookServiceScreenState();
}

class _BookServiceScreenState extends ConsumerState<BookServiceScreen> {
  // One key per booking attempt: a double tap or a retry after a network drop can't create two bookings.
  final _idempotencyKey = const Uuid().v4();
  final _notes = TextEditingController();
  final _selected = <String>{};
  List<Map<String, dynamic>>? _services;
  List<Map<String, dynamic>>? _slots;
  late DateTime _day = _todayIst();
  String? _slotId;
  bool _busy = false;
  Object? _error;

  static DateTime _todayIst() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));
    return DateTime.utc(now.year, now.month, now.day);
  }

  String get _dayParam => _day.toIso8601String().substring(0, 10);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final api = ref.read(apiProvider);
    final vehicleId = ref.read(selectedVehicleProvider);
    try {
      final s = await api.get('/vendors/${widget.vendorId}/services', query: {'vehicleId': vehicleId});
      setState(() => _services = (s as List).cast<Map<String, dynamic>>());
      await _loadSlots();
    } catch (e) {
      setState(() => _error = e);
    }
  }

  Future<void> _loadSlots() async {
    setState(() {
      _slots = null;
      _slotId = null;
    });
    final r = await ref.read(apiProvider).get('/vendors/${widget.vendorId}/slots', query: {'date': _dayParam}) as Map<String, dynamic>;
    if (mounted) setState(() => _slots = (r['slots'] as List).cast<Map<String, dynamic>>());
  }

  int get _advancePaise => (_services ?? const [])
      .where((s) => _selected.contains(s['id']))
      .fold<int>(0, (sum, s) => sum + (s['advancePaise'] as num).toInt());

  Future<void> _confirm() async {
    final vehicleId = ref.read(selectedVehicleProvider) ?? (ref.read(vehiclesProvider).asData?.value.firstOrNull?['id'] as String?);
    if (vehicleId == null || _slotId == null || _selected.isEmpty) return;
    setState(() => _busy = true);
    final api = ref.read(apiProvider);
    try {
      final booking = await api.post('/bookings', {
        'vendorId': widget.vendorId,
        'vehicleId': vehicleId,
        'serviceIds': _selected.toList(),
        'slotId': _slotId,
        if (_notes.text.trim().isNotEmpty) 'customerNotes': _notes.text.trim(),
      }, {'Idempotency-Key': _idempotencyKey}) as Map<String, dynamic>;

      final payment = booking['payment'] as Map<String, dynamic>?;
      if (payment != null && mounted) {
        try {
          final paid = await PaymentLauncher.pay(context, api, payment);
          if (paid != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).paymentSuccess)));
          }
        } on ApiException catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context).paymentFailed)));
          }
        }
      }
      // Booking exists either way; an unpaid advance can be paid from the booking page.
      if (mounted) context.pushReplacement('/bookings/${booking['id']}');
    } on ApiException catch (e) {
      if (!mounted) return;
      showError(context, e);
      if (e.code == 'SLOT_UNAVAILABLE') await _loadSlots();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (_error != null) return Scaffold(appBar: AppBar(), body: ErrorView(error: _error!, onRetry: _load));
    final services = _services;
    return Scaffold(
      appBar: AppBar(title: Text(widget.vendorName.isEmpty ? t.bookService : widget.vendorName)),
      body: services == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Text(t.selectServices, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final s in services)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _selected.contains(s['id']),
                  onChanged: (v) => setState(() => v == true ? _selected.add(s['id'] as String) : _selected.remove(s['id'])),
                  title: Text(s['name'] as String),
                  subtitle: Text([
                    switch (s['priceType']) {
                      'fixed' => formatPaise(s['pricePaise'] as num),
                      'starting_from' => t.startsFrom(formatPaise(s['pricePaise'] as num)),
                      _ => t.priceOnInspection,
                    },
                    '${s['durationMinutes']} min',
                    ...((s['inclusions'] as List).take(3).cast<String>()),
                  ].join(' · ')),
                ),
              const Divider(height: 32),
              Text(t.pickSlot, style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 64,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: 7,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final d = _todayIst().add(Duration(days: i));
                    return ChoiceChip(
                      label: Text('${const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1]}\n${d.day}',
                          textAlign: TextAlign.center),
                      selected: d == _day,
                      onSelected: (_) {
                        _day = d;
                        _loadSlots();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              if (_slots == null)
                const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
              else if (_slots!.isEmpty)
                Padding(padding: const EdgeInsets.all(16), child: Text(t.noSlots))
              else
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in _slots!)
                    ChoiceChip(
                      label: Text(s['localTime'] as String),
                      selected: _slotId == s['id'],
                      onSelected: (s['available'] as num) > 0 ? (_) => setState(() => _slotId = s['id'] as String) : null,
                    ),
                ]),
              const SizedBox(height: 16),
              TextField(controller: _notes, maxLines: 3, maxLength: 1000, decoration: InputDecoration(labelText: t.notes)),
              const SizedBox(height: 80),
            ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (_advancePaise > 0)
              Expanded(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.advanceToPay, style: theme.textTheme.bodySmall),
                  Text(formatPaise(_advancePaise), style: theme.textTheme.titleMedium),
                ]),
              )
            else
              const Spacer(),
            FilledButton(
              key: const Key('confirm-booking'),
              onPressed: _busy || _selected.isEmpty || _slotId == null ? null : _confirm,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.confirmBooking),
            ),
          ]),
        ),
      ),
    );
  }
}
