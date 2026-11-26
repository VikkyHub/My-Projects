// End-to-end check of the Dart client against a REAL running API with demo data.
//   AUTOHUB_API=http://localhost:3000/v1 flutter test test/live_backend_test.dart
// Skipped when AUTOHUB_API is not set.
import 'dart:io';

import 'package:autohub_core/autohub_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

void main() {
  final base = Platform.environment['AUTOHUB_API'];
  const swift = 'd0000000-0000-4000-8000-0000000000a1';
  const shree = 'd0000000-0000-4000-8000-0000000000b1';

  Future<SessionController> login(String app, String phone) async {
    final api = ApiClient(config: AppConfig.fixed(base!, app), tokens: MemoryTokenStore(), cache: MemoryResponseCache());
    final s = SessionController(api, api.tokens);
    final c = await s.requestOtp(phone);
    expect(c.devCode, isNotNull, reason: 'server must run with OTP_DEV_ECHO=true');
    await s.verify(c, c.devCode!);
    return s;
  }

  test('customer searches, books, pays; vendor confirms; dashboard updates', () async {
    final customer = await login('customer', '+919000000001');
    final api = customer.api;

    // Fitment-aware search, then the same request revalidated from cache via ETag.
    final r1 = await api.getCached('/products', query: {'q': 'brake', 'vehicleId': swift});
    final names = ((r1.data as Map)['data'] as List).map((p) => p['name']).toList();
    expect(names, contains('Front Brake Pad Set'));
    expect(names, isNot(contains('Creta Front Brake Pads')));
    final r2 = await api.getCached('/products', query: {'q': 'brake', 'vehicleId': swift});
    expect((r2.data as Map)['data'], (r1.data as Map)['data']);

    // Book the first free slot tomorrow-or-later with an advance.
    Map<String, dynamic>? slot;
    for (var d = 1; d <= 7 && slot == null; d++) {
      final date = DateTime.now().toUtc().add(Duration(hours: 5, minutes: 30, days: d)).toIso8601String().substring(0, 10);
      final s = await api.get('/vendors/$shree/slots', query: {'date': date}) as Map<String, dynamic>;
      slot = (s['slots'] as List).cast<Map<String, dynamic>>().where((x) => (x['available'] as num) > 0).firstOrNull;
    }
    expect(slot, isNotNull);
    final booking = await api.post('/bookings', {
      'vendorId': shree,
      'vehicleId': swift,
      'serviceIds': ['d0000000-0000-4000-8000-000000000204'],   // AC gas refill, ₹200 advance
      'slotId': slot!['id'],
    }, {'Idempotency-Key': const Uuid().v4()}) as Map<String, dynamic>;
    expect(booking['status'], 'requested');

    // What PaymentLauncher does in fake mode.
    final rz = (booking['payment'] as Map)['razorpay'] as Map;
    final proof = await api.post('/dev/payments/simulate', {'razorpayOrderId': rz['orderId']});
    final verified = await api.post('/payments/verify', proof) as Map<String, dynamic>;
    expect(verified['status'], 'captured');

    // Vendor side.
    final vendor = await login('vendor', '+919000000002');
    expect(vendor.activeVendor?.businessName, 'Shree Auto Parts & Service');
    final confirmed = await vendor.api.post('/vendor/bookings/${booking['id']}/confirm') as Map<String, dynamic>;
    expect(confirmed['status'], 'confirmed');
    final dash = await vendor.api.get('/vendor/dashboard') as Map<String, dynamic>;
    expect((dash['last7Days'] as List), hasLength(7));

    // Customer cancels (more than 2 h ahead) → advance queued for refund.
    final cancelled = await api.post('/bookings/${booking['id']}/cancel', {}) as Map<String, dynamic>;
    expect(cancelled['status'], 'cancelled');
  }, skip: base == null ? 'set AUTOHUB_API to run against a live server' : false);
}
