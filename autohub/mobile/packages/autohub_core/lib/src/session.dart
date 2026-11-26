import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'config.dart';
import 'token_store.dart';

class OtpChallenge {
  OtpChallenge(this.otpRequestId, this.phone, this.resendAfterSeconds, this.devCode);
  final String otpRequestId;
  final String phone;
  final int resendAfterSeconds;

  /// Only present when the server runs with OTP_DEV_ECHO=true (local testing).
  final String? devCode;
}

class VendorMembership {
  VendorMembership(this.vendorId, this.businessName, this.role, this.status);
  factory VendorMembership.fromJson(Map<String, dynamic> j) =>
      VendorMembership(j['vendorId'] as String, j['businessName'] as String, j['role'] as String, j['status'] as String);
  final String vendorId;
  final String businessName;
  final String role;
  final String status;
}

enum SessionStatus { unknown, loggedOut, loggedIn }

/// Login state for one app. A [ChangeNotifier] so go_router can redirect when it changes.
class SessionController extends ChangeNotifier {
  SessionController(this.api, this.tokens) {
    api.language = language;
  }

  final ApiClient api;
  final TokenStore tokens;

  SessionStatus status = SessionStatus.unknown;
  Map<String, dynamic>? user;
  List<VendorMembership> memberships = const [];
  VendorMembership? activeVendor;
  String language = 'en';

  Future<void> restore() async {
    language = await tokens.readExtra('lang') ?? 'en';
    api.language = language;
    final t = await tokens.read();
    if (t == null) return _set(SessionStatus.loggedOut);
    try {
      user = await api.get('/me') as Map<String, dynamic>;
      if (api.config.clientApp == 'vendor') await _loadVendors(await tokens.readExtra('vendorId'));
      _set(SessionStatus.loggedIn);
    } on ApiException catch (e) {
      // Offline at launch: stay logged in with what we have; screens fall back to cached data.
      _set(e.isNetwork ? SessionStatus.loggedIn : SessionStatus.loggedOut);
    }
  }

  Future<OtpChallenge> requestOtp(String phone) async {
    final j = await api.post('/auth/otp/request', {'phone': phone}) as Map<String, dynamic>;
    return OtpChallenge(j['otpRequestId'] as String, phone, (j['resendAfterSeconds'] as num).toInt(), j['devCode'] as String?);
  }

  Future<void> verify(OtpChallenge c, String code) async {
    final j = await api.post('/auth/otp/verify', {
      'otpRequestId': c.otpRequestId,
      'phone': c.phone,
      'code': code,
      'device': {'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android'},
    }) as Map<String, dynamic>;
    await tokens.write(Tokens(j['accessToken'] as String, j['refreshToken'] as String));
    user = j['user'] as Map<String, dynamic>;
    if (api.config.clientApp == 'vendor') {
      memberships = ((j['vendorMemberships'] as List?) ?? const [])
          .map((m) => VendorMembership.fromJson(m as Map<String, dynamic>))
          .toList();
      await selectVendor(memberships.isEmpty ? null : memberships.first);
    }
    _set(SessionStatus.loggedIn);
  }

  Future<void> selectVendor(VendorMembership? v) async {
    activeVendor = v;
    api.vendorId = v?.vendorId;
    await tokens.writeExtra('vendorId', v?.vendorId);
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    language = code;
    api.language = code;
    await tokens.writeExtra('lang', code);
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await api.post('/auth/logout');
    } catch (_) {/* already invalid or offline — still log out locally */}
    await tokens.clear();
    await selectVendor(null);
    user = null;
    memberships = const [];
    _set(SessionStatus.loggedOut);
  }

  /// Called by the API client when the server rejects our tokens.
  void onForcedLogout() {
    user = null;
    _set(SessionStatus.loggedOut);
  }

  Future<void> _loadVendors(String? preferredId) async {
    final list = await api.get('/me/vendors') as List;
    memberships = list.map((m) => VendorMembership.fromJson(m as Map<String, dynamic>)).toList();
    final pick = memberships.where((m) => m.vendorId == preferredId).firstOrNull ?? memberships.firstOrNull;
    await selectVendor(pick);
  }

  void _set(SessionStatus s) {
    status = s;
    notifyListeners();
  }
}

/// Everything an app needs, built once in main() and injected with ProviderScope overrides.
class Core {
  Core({required this.config, required this.api, required this.session});
  final AppConfig config;
  final ApiClient api;
  final SessionController session;
}

final coreProvider = Provider<Core>((ref) => throw UnimplementedError('Override coreProvider in main()'));
final apiProvider = Provider<ApiClient>((ref) => ref.watch(coreProvider).api);
final sessionProvider = Provider<SessionController>((ref) => ref.watch(coreProvider).session);
