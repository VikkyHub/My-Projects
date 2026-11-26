import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

/// Staff sign-in: email + password, then a 6-digit authenticator code.
/// First sign-in shows a QR code (or "Open authenticator app" on the same phone).
class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});
  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final email = TextEditingController(), password = TextEditingController(), newPw = TextEditingController(), newPw2 = TextEditingController();
  J? step;
  String code = '';
  bool busy = false;
  String? err;

  Future<void> _go(Future<void> Function() f) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await f();
    } on ApiError catch (e) {
      setState(() => err = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _login() => _go(() async {
        final r = Map<String, dynamic>.from(await staffApi.post('/admin/auth/login', {'email': email.text.trim(), 'password': password.text}) as Map);
        password.clear();
        setState(() {
          step = r;
          code = '';
        });
      });

  void _verify() => _go(() async {
        if (step!['must_change_password'] == true && newPw.text != newPw2.text) throw ApiError(422, "The two new passwords don't match");
        final r = Map<String, dynamic>.from(await staffApi.post('/admin/auth/verify', {
          'ticket': step!['ticket'],
          'code': code,
          'new_password': step!['must_change_password'] == true ? newPw.text : null,
        }) as Map);
        await appState.staffSignedIn(r);
        if (mounted) context.go('/admin');
      });

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PatternBg(
          child: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              HeroPanel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    const Icon(Icons.favorite_rounded, color: C.gold300),
                    const SizedBox(width: 8),
                    Text(Config.appName, style: display(17, color: Colors.white)),
                  ]),
                  const SizedBox(height: 18),
                  const Pill('STAFF PORTAL', fg: C.gold200, bg: Colors.white12),
                  const SizedBox(height: 10),
                  Text.rich(TextSpan(text: 'Keeping every match ', style: display(26, color: Colors.white), children: [
                    TextSpan(text: 'safe and genuine.', style: display(26, color: C.gold300, style: FontStyle.italic)),
                  ])),
                ]),
              ),
              const SizedBox(height: 18),
              AppCard(
                padding: const EdgeInsets.all(22),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Pill('Staff sign-in', icon: Icons.shield_rounded, fg: C.brand700, bg: C.brand50),
                  const SizedBox(height: 12),
                  if (step == null) ...[
                    Text('Welcome back', style: display(26)),
                    const SizedBox(height: 4),
                    const Text('For moderators and admins only.', style: TextStyle(color: C.muted)),
                    const FieldLabel('Work email'),
                    TextField(controller: email, keyboardType: TextInputType.emailAddress, autofillHints: const [AutofillHints.username]),
                    const FieldLabel('Password'),
                    TextField(controller: password, obscureText: true, autofillHints: const [AutofillHints.password], onSubmitted: (_) => _login()),
                    const SizedBox(height: 18),
                    Btn('Continue', icon: Icons.arrow_forward_rounded, expand: true, loading: busy, onPressed: _login),
                  ] else ...[
                    TextButton.icon(onPressed: () => setState(() => step = null), icon: const Icon(Icons.arrow_back_rounded, size: 18), label: const Text('Back')),
                    if (step!['step'] == 'enroll') ...[
                      Text('Set up 2-step sign-in', style: display(24)),
                      const SizedBox(height: 8),
                      const Text('1. Install Google Authenticator or Microsoft Authenticator.\n2. Scan this code with another phone — or on this phone tap "Open authenticator app".\n3. Enter the 6-digit code it shows.',
                          style: TextStyle(height: 1.5)),
                      const SizedBox(height: 12),
                      Center(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: C.line)),
                          child: QrImageView(data: step!['otpauth_uri'] as String, size: 180),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Btn('Open authenticator app', icon: Icons.open_in_new_rounded, kind: BtnKind.secondary, small: true, onPressed: () async {
                          final ok = await launchUrl(Uri.parse(step!['otpauth_uri'] as String), mode: LaunchMode.externalApplication);
                          if (!ok && context.mounted) snack(context, 'No authenticator app found — install one first');
                        }),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: step!['secret'] as String));
                            snack(context, 'Setup key copied');
                          },
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          label: Text(step!['secret'] as String, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                        ),
                      ),
                    ] else ...[
                      Text('Enter your code', style: display(24)),
                      const SizedBox(height: 4),
                      const Text('Open your authenticator app and enter the current 6-digit code.', style: TextStyle(color: C.muted)),
                    ],
                    const SizedBox(height: 16),
                    OtpField(onChanged: (v) => setState(() => code = v)),
                    if (step!['must_change_password'] == true) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: C.gold50, borderRadius: BorderRadius.circular(18), border: Border.all(color: C.gold100)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text("You're using a temporary password. Choose a new one.", style: TextStyle(fontWeight: FontWeight.w700)),
                          const FieldLabel('New password', hint: 'At least 10 characters, with letters and numbers'),
                          TextField(controller: newPw, obscureText: true),
                          const FieldLabel('Repeat new password'),
                          TextField(controller: newPw2, obscureText: true),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Btn('Verify & sign in', expand: true, loading: busy, onPressed: code.length == 6 ? _verify : null),
                  ],
                  ErrorBox(err),
                  const Divider(height: 30),
                  Center(child: TextButton(onPressed: () => context.go('/login'), child: const Text('Not staff? Member login'))),
                ]),
              ),
            ]),
          ),
        ),
      );
}
