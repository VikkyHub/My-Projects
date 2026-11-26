import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/gen/app_localizations.dart';
import 'api_client.dart';
import 'session.dart';
import 'ui.dart';

/// Phone → OTP login, shared by the customer and vendor apps.
class OtpLoginScreen extends ConsumerStatefulWidget {
  const OtpLoginScreen({super.key, required this.title, this.icon = Icons.directions_car});
  final String title;
  final IconData icon;

  @override
  ConsumerState<OtpLoginScreen> createState() => _OtpLoginScreenState();
}

class _OtpLoginScreenState extends ConsumerState<OtpLoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  OtpChallenge? _challenge;
  bool _busy = false;
  String? _error;
  int _resendIn = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  String get _e164 => '+91${_phone.text.replaceAll(RegExp(r'\D'), '')}';

  Future<void> _send() async {
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(_phone.text.replaceAll(RegExp(r'\D'), ''))) {
      setState(() => _error = AppLocalizations.of(context).phoneLabel);
      return;
    }
    await _run(() async {
      final c = await ref.read(sessionProvider).requestOtp(_e164);
      _code.text = '';
      _startCountdown(c.resendAfterSeconds);
      setState(() => _challenge = c);
    });
  }

  Future<void> _verify() async {
    final c = _challenge;
    if (c == null || _code.text.length != 6) return;
    await _run(() => ref.read(sessionProvider).verify(c, _code.text));
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startCountdown(int seconds) {
    _timer?.cancel();
    setState(() => _resendIn = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _resendIn <= 1) {
        t.cancel();
        if (mounted) setState(() => _resendIn = 0);
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  Future<void> _editServer() async {
    final config = ref.read(coreProvider).config;
    final ctrl = TextEditingController(text: config.apiBaseUrl);
    final t = AppLocalizations.of(context);
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.serverAddress),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.20:3000'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(t.save)),
        ],
      ),
    );
    if (url != null && url.trim().isNotEmpty) {
      await config.setApiBaseUrl(url);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final c = _challenge;
    final session = ref.watch(sessionProvider);
    return Scaffold(
      appBar: AppBar(actions: [
        PopupMenuButton<String>(
          icon: const Icon(Icons.translate),
          onSelected: (code) async {
            await session.setLanguage(code);
            if (mounted) setState(() {});
          },
          itemBuilder: (_) => [for (final e in supportedLanguages.entries) PopupMenuItem(value: e.key, child: Text(e.value))],
        ),
        IconButton(tooltip: t.serverAddress, icon: const Icon(Icons.dns_outlined), onPressed: _editServer),
      ]),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(24), children: [
          Icon(widget.icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 12),
          Text(widget.title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(c == null ? t.loginSubtitle : t.otpSentTo(c.phone), textAlign: TextAlign.center),
          const SizedBox(height: 28),
          if (c == null) ...[
            TextField(
              key: const Key('phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              autofillHints: const [AutofillHints.telephoneNumberNational],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
              decoration: InputDecoration(labelText: t.phoneLabel, prefixText: '+91 '),
              onSubmitted: (_) => _send(),
            ),
            const SizedBox(height: 16),
            FilledButton(key: const Key('send-otp'), onPressed: _busy ? null : _send, child: Text(t.sendOtp)),
          ] else ...[
            TextField(
              key: const Key('otp'),
              controller: _code,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
              decoration: InputDecoration(labelText: t.otpLabel),
              style: const TextStyle(fontSize: 22, letterSpacing: 8),
              onChanged: (v) => v.length == 6 ? _verify() : null,
            ),
            if (c.devCode != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ActionChip(
                  avatar: const Icon(Icons.science_outlined, size: 18),
                  label: Text(t.devCodeHint(c.devCode!)),
                  onPressed: () {
                    _code.text = c.devCode!;
                    _verify();
                  },
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(key: const Key('verify'), onPressed: _busy ? null : _verify, child: Text(t.verify)),
            TextButton(
              onPressed: _busy || _resendIn > 0 ? null : _send,
              child: Text(_resendIn > 0 ? t.resendIn(_resendIn) : t.resend),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: Center(child: CircularProgressIndicator())),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 24),
          Text(ref.read(coreProvider).config.apiBaseUrl,
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
    );
  }
}
