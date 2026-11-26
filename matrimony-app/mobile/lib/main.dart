import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/app_state.dart';
import 'core/config.dart';
import 'core/theme.dart';
import 'core/translate.dart';
import 'screens/admin/admin_login.dart';
import 'screens/admin/admin_screens.dart';
import 'screens/member/help.dart';
import 'screens/member/login.dart';
import 'screens/member/messages.dart';
import 'screens/member/profile_view.dart';
import 'screens/member/register.dart';
import 'screens/member/shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadTargetLang();
  runApp(const GharGharApp());
  appState.boot();
}

/// Where each kind of user may go. Pure so it can be unit-tested.
String? redirectFor(Auth auth, bool hasProfile, String path) {
  final staffArea = path.startsWith('/admin');
  final open = path == '/login' || path == '/admin/login' || path == '/splash';
  switch (auth) {
    case Auth.unknown:
      return path == '/splash' ? null : '/splash';
    case Auth.loggedOut:
      return open && path != '/splash' ? null : (staffArea ? '/admin/login' : '/login');
    case Auth.staff:
      return staffArea && path != '/admin/login' ? null : '/admin';
    case Auth.member:
      if (staffArea || open) return hasProfile ? '/' : '/register';
      if (!hasProfile && path != '/register' && path != '/help') return '/register';
      if (hasProfile && path == '/register') return '/';
      return null;
  }
}

final router = GoRouter(
  initialLocation: '/splash',
  refreshListenable: appState,
  redirect: (context, state) => redirectFor(appState.auth, appState.hasProfile, state.matchedLocation),
  routes: [
    GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
    GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
    GoRoute(path: '/', builder: (_, _) => const MemberShell()),
    GoRoute(path: '/p/:publicId', builder: (_, s) => ProfileViewScreen(s.pathParameters['publicId']!)),
    GoRoute(path: '/chat/:convId', builder: (_, s) => ThreadScreen(s.pathParameters['convId']!)),
    GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
    GoRoute(path: '/admin/login', builder: (_, _) => const AdminLoginScreen()),
    GoRoute(path: '/admin', builder: (_, _) => const AdminShell()),
  ],
);

class GharGharApp extends StatelessWidget {
  const GharGharApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp.router(
        title: Config.appName,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        routerConfig: router,
      );
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: C.heroGradient),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.favorite_rounded, color: C.gold300, size: 56),
              const SizedBox(height: 14),
              Text(Config.appName, style: display(30, color: Colors.white)),
              const SizedBox(height: 6),
              const Text('Rishte jo ghar ghar jodte hain', style: TextStyle(color: C.gold200)),
              const SizedBox(height: 28),
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
            ]),
          ),
        ),
      );
}
