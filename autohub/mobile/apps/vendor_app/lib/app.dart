import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/bookings/job_card_screen.dart';
import 'features/dashboard/dashboard_screen.dart';

GoRouter buildRouter(SessionController session) => GoRouter(
      initialLocation: '/',
      refreshListenable: session,
      redirect: (context, state) {
        final loggedIn = session.status == SessionStatus.loggedIn;
        final loc = state.matchedLocation;
        if (!loggedIn) return loc == '/login' ? null : '/login';
        if (session.activeVendor == null) return loc == '/no-shop' ? null : '/no-shop';
        if (loc == '/login' || loc == '/no-shop') return '/';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (context, _) => OtpLoginScreen(title: 'AutoHub Partner', icon: Icons.storefront)),
        GoRoute(path: '/no-shop', builder: (_, _) => const NoShopScreen()),
        GoRoute(path: '/', builder: (_, _) => const DashboardScreen()),
        GoRoute(path: '/bookings/:id', builder: (_, s) => JobCardScreen(bookingId: s.pathParameters['id']!)),
      ],
    );

class VendorApp extends ConsumerStatefulWidget {
  const VendorApp({super.key});
  @override
  ConsumerState<VendorApp> createState() => _VendorAppState();
}

class _VendorAppState extends ConsumerState<VendorApp> {
  late final GoRouter _router = buildRouter(ref.read(sessionProvider));

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => MaterialApp.router(
        title: 'AutoHub Partner',
        debugShowCheckedModeBanner: false,
        theme: autohubTheme(seed: const Color(0xFF1D4ED8)),
        darkTheme: autohubTheme(seed: const Color(0xFF1D4ED8), brightness: Brightness.dark),
        locale: Locale(session.language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: _router,
      ),
    );
  }
}

/// Logged in, but this phone number isn't a member of any shop yet (registration flow comes next).
class NoShopScreen extends ConsumerWidget {
  const NoShopScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(actions: [IconButton(icon: const Icon(Icons.logout), onPressed: ref.read(sessionProvider).logout)]),
      body: Center(child: Padding(padding: const EdgeInsets.all(32), child: Text(t.notVendor, textAlign: TextAlign.center))),
    );
  }
}
