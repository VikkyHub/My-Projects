import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'realtime.dart';

enum Auth { unknown, loggedOut, member, staff }

/// Who is signed in, plus the member's own profile. Drives navigation redirects.
class AppState extends ChangeNotifier {
  Auth auth = Auth.unknown;
  J? me; // member profile (null = logged in but no profile yet)
  J? staff; // {id, name, email, role}
  J counts = {};

  bool get hasProfile => me != null;
  bool get isAdmin => staff?['role'] == 'admin';

  Future<void> boot() async {
    memberApi.onExpired = () => _signedOut();
    staffApi.onExpired = () => _signedOut();
    if (await memberApi.hasSession()) {
      try {
        await loadMe();
        auth = Auth.member;
        Realtime.instance.start();
      } on ApiError catch (e) {
        auth = e.status == 0 ? Auth.member : Auth.loggedOut; // offline: keep session
      }
    } else {
      auth = Auth.loggedOut;
    }
    notifyListeners();
  }

  Future<void> loadMe() async {
    try {
      me = Map<String, dynamic>.from(await memberApi.get('/profiles/me') as Map);
    } on ApiError catch (e) {
      if (e.status == 404) {
        me = null;
      } else {
        rethrow;
      }
    }
    notifyListeners();
  }

  Future<void> refreshCounts() async {
    if (auth != Auth.member || me == null) return;
    try {
      counts = Map<String, dynamic>.from(await memberApi.get('/interests/counts') as Map);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> memberSignedIn(J tokens) async {
    await memberApi.setTokens(tokens);
    await loadMe();
    auth = Auth.member;
    Realtime.instance.start();
    notifyListeners();
  }

  void setMe(J p) {
    me = p;
    notifyListeners();
  }

  Future<void> staffSignedIn(J res) async {
    await staffApi.setTokens(res);
    staff = Map<String, dynamic>.from(res['staff'] as Map);
    auth = Auth.staff;
    notifyListeners();
  }

  Future<void> signOut() async {
    Realtime.instance.stop();
    if (auth == Auth.staff) {
      await staffApi.logout();
    } else {
      await memberApi.logout();
    }
    _signedOut();
  }

  void _signedOut() {
    Realtime.instance.stop();
    me = null;
    staff = null;
    counts = {};
    auth = Auth.loggedOut;
    notifyListeners();
  }
}

final appState = AppState();
