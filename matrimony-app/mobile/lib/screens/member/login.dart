import 'dart:async';

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/api.dart';
import '../../core/app_state.dart';
import '../../core/config.dart';
import '../../core/theme.dart';
import '../../widgets/ui.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  String _code = '';
  bool _codeStep = false, _busy = false;
  String? _err;
  int _resendIn = 0;
  Timer? _t;

  @override
  void dispose() {
    _t?.cancel();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = await memberApi.post('/auth/otp/send', {'phone': _phone.text}) as Map;
      _t?.cancel();
      setState(() {
        _codeStep = true;
        _code = '';
        _resendIn = r['resend_after'] as int;
      });
      _t = Timer.periodic(const Duration(seconds: 1), (t) {
        if (_resendIn <= 1) t.cancel();
        setState(() => _resendIn = (_resendIn - 1).clamp(0, 999));
      });
    } on ApiError catch (e) {
      setState(() => _err = e.message);
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _verify() async {
    if (_code.length != 6 || _busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      final r = Map<String, dynamic>.from(await memberApi.post('/auth/otp/verify', {'phone': _phone.text, 'code': _code}) as Map);
      await appState.memberSignedIn(r);
      if (mounted) context.go(appState.hasProfile ? '/' : '/register');
    } on ApiError catch (e) {
      setState(() => _err = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: PatternBg(
          child: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              HeroPanel(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.favorite_rounded, color: C.gold300, size: 20),
                    ),
                    const SizedBox(width: 10),
                    Text(Config.appName, style: display(18, color: Colors.white)),
                  ]),
                  const SizedBox(height: 28),
                  Text.rich(TextSpan(text: 'Where families meet, ', style: display(30, color: Colors.white), children: [
                    TextSpan(text: 'and forever', style: display(30, color: C.gold300, style: FontStyle.italic)),
                    const TextSpan(text: ' begins.'),
                  ])),
                  const SizedBox(height: 12),
                  Text('A safe, private and respectful place to find your life partner — for you, or for someone you love.',
                      style: TextStyle(color: Colors.white.withValues(alpha: .8), height: 1.4)),
                  const SizedBox(height: 18),
                  for (final (i, t) in [
                    (Icons.verified_rounded, 'Every profile verified & reviewed'),
                    (Icons.visibility_off_rounded, 'You control who sees your photos'),
                    (Icons.handshake_rounded, 'Chat only when both say yes'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(children: [
                        Icon(i, size: 18, color: C.gold300),
                        const SizedBox(width: 10),
                        Text(t, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                ]),
              ),
              const SizedBox(height: 20),
              AppCard(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!_codeStep) ...[
                      Text('Welcome', style: display(28)),
                      const SizedBox(height: 6),
                      const Text('Log in or create your profile with your mobile number.', style: TextStyle(color: C.muted)),
                      const FieldLabel('Mobile number'),
                      PhoneField(controller: _phone, onChanged: (_) => setState(() {})),
                      const SizedBox(height: 20),
                      Btn('Get OTP', icon: Icons.arrow_forward_rounded, expand: true, loading: _busy, onPressed: _phone.text.length == 10 ? _send : null),
                    ] else ...[
                      TextButton.icon(
                        onPressed: () => setState(() => _codeStep = false),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text('Change number'),
                        style: TextButton.styleFrom(foregroundColor: C.muted, padding: EdgeInsets.zero),
                      ),
                      Text('Enter the code', style: display(28)),
                      const SizedBox(height: 6),
                      Text.rich(TextSpan(text: 'We sent a 6-digit code to ', style: const TextStyle(color: C.muted), children: [
                        TextSpan(text: '+91 ${_phone.text}', style: const TextStyle(color: C.ink, fontWeight: FontWeight.w700)),
                      ])),
                      const SizedBox(height: 20),
                      OtpField(
                        onChanged: (v) => setState(() {
                          _code = v;
                          _err = null;
                        }),
                        onCompleted: (_) => _verify(),
                      ),
                      const SizedBox(height: 20),
                      Btn('Verify & continue', expand: true, loading: _busy, onPressed: _code.length == 6 ? _verify : null),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: _resendIn > 0 || _busy ? null : _send,
                          child: Text(_resendIn > 0 ? 'Resend in ${_resendIn}s' : 'Resend OTP',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                    ErrorBox(_err),
                    const Divider(height: 32),
                    const Text('By continuing you agree to our Terms and Privacy Policy.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: C.muted)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: TextButton.icon(
                  onPressed: () => context.go('/admin/login'),
                  icon: const Icon(Icons.shield_outlined, size: 16),
                  label: const Text('Staff sign in'),
                  style: TextButton.styleFrom(foregroundColor: C.muted),
                ),
              ),
            ]),
          ),
        ),
      );
}
