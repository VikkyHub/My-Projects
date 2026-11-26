import 'package:autohub_core/autohub_core.dart';
import 'package:autohub_core/src/testing.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('phone → OTP → logged in, using the test-mode code chip', (tester) async {
    final http = FakeAdapter()
      ..routes['POST /auth/otp/request'] = ((_) => FakeReply(200, {
            'otpRequestId': '6adccd70-127d-4db1-b3c0-40cb6755731a', 'expiresInSeconds': 300, 'resendAfterSeconds': 30, 'devCode': '648261',
          }))
      ..routes['POST /auth/otp/verify'] = ((req) => (req.data as Map)['code'] == '648261'
          ? FakeReply(200, {
              'accessToken': 'a', 'refreshToken': 'r', 'isNewUser': false,
              'user': {'id': 'u1', 'phone': '+919000000001', 'fullName': 'Rahul Patil'}, 'vendorMemberships': [],
            })
          : FakeReply(422, {'error': {'code': 'OTP_INVALID', 'message': 'Incorrect code.'}}));
    final config = AppConfig.fixed('http://api.test/v1', 'customer');
    final tokens = MemoryTokenStore();
    final api = ApiClient(config: config, tokens: tokens, cache: MemoryResponseCache(), dio: Dio()..httpClientAdapter = http);
    final session = SessionController(api, tokens);

    await tester.pumpWidget(ProviderScope(
      overrides: [coreProvider.overrideWithValue(Core(config: config, api: api, session: session))],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: OtpLoginScreen(title: 'Log in'),
      ),
    ));

    // Invalid number is caught locally — no request sent.
    await tester.enterText(find.byKey(const Key('phone')), '12345');
    await tester.tap(find.byKey(const Key('send-otp')));
    await tester.pump();
    expect(http.calls, isEmpty);

    await tester.enterText(find.byKey(const Key('phone')), '9000000001');
    await tester.tap(find.byKey(const Key('send-otp')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect((http.calls.single.data as Map)['phone'], '+919000000001');
    expect(find.text('Code sent to +919000000001'), findsOneWidget);
    expect(find.text('Test mode code: 648261'), findsOneWidget);

    await tester.tap(find.text('Test mode code: 648261'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.status, SessionStatus.loggedIn);
    expect(session.user?['fullName'], 'Rahul Patil');
    expect((await tokens.read())?.accessToken, 'a');

    // Clean up the resend countdown timer.
    await tester.pumpWidget(const SizedBox());
  });
}
