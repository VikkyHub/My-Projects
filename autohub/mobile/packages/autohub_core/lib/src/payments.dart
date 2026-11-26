import 'dart:async';

import 'package:flutter/material.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../l10n/gen/app_localizations.dart';
import 'api_client.dart';
import 'money.dart';

/// Opens Razorpay Checkout for a server-created order and verifies the result on the server.
///
/// When the server runs with RAZORPAY_MODE=fake (key starts with `rzp_fake`), a test sheet stands in
/// for Razorpay so the whole flow can be tried without an account. Returns the verify response.
class PaymentLauncher {
  static Future<Map<String, dynamic>?> pay(BuildContext context, ApiClient api, Map<String, dynamic> payment) async {
    final rz = payment['razorpay'] as Map<String, dynamic>;
    final keyId = rz['keyId'] as String;
    final orderId = rz['orderId'] as String;

    Map<String, dynamic> proof;
    if (keyId.startsWith('rzp_fake')) {
      final ok = await _fakeSheet(context, rz['amountPaise'] as num);
      if (ok != true) return null;
      proof = await api.post('/dev/payments/simulate', {'razorpayOrderId': orderId}) as Map<String, dynamic>;
    } else {
      final r = await _razorpay(rz);
      if (r == null) return null;
      proof = r;
    }
    return await api.post('/payments/verify', proof) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>?> _razorpay(Map<String, dynamic> rz) {
    final completer = Completer<Map<String, dynamic>?>();
    final razorpay = Razorpay();
    razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse r) {
      completer.complete({'razorpayOrderId': r.orderId, 'razorpayPaymentId': r.paymentId, 'razorpaySignature': r.signature});
    });
    razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse r) {
      // Code 2 = user closed the sheet; anything else is a failed attempt. Either way nothing to verify.
      completer.complete(null);
    });
    razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse _) {});
    razorpay.open({
      'key': rz['keyId'],
      'order_id': rz['orderId'],
      'amount': rz['amountPaise'],
      'currency': 'INR',
      'name': rz['name'] ?? 'AutoHub',
      'description': rz['description'] ?? '',
      'prefill': rz['prefill'] ?? const {},
      'theme': {'color': '#0F766E'},
    });
    return completer.future.whenComplete(razorpay.clear);
  }

  static Future<bool?> _fakeSheet(BuildContext context, num amountPaise) {
    final t = AppLocalizations.of(context);
    return showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              const Icon(Icons.science_outlined),
              const SizedBox(width: 8),
              Text(t.testPaymentTitle, style: Theme.of(ctx).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(t.testPaymentBody),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.qr_code_2),
              label: Text(t.payNow(formatPaise(amountPaise))),
              onPressed: () => Navigator.pop(ctx, true),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t.cancel)),
          ]),
        ),
      ),
    );
  }
}
