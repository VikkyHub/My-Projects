import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/account/account_screen.dart';
import 'features/booking/book_service_screen.dart';
import 'features/booking/booking_detail_screen.dart';
import 'features/booking/bookings_screen.dart';
import 'features/parts/product_detail_screen.dart';
import 'features/parts/products_screen.dart';
import 'features/services/nearby_shops_screen.dart';

GoRouter buildRouter(SessionController session) => GoRouter(
      initialLocation: '/parts',
      refreshListenable: session,
      redirect: (context, state) {
        final loggedIn = session.status == SessionStatus.loggedIn;
        final atLogin = state.matchedLocation == '/login';
        if (!loggedIn && !atLogin) return '/login';
        if (loggedIn && atLogin) return '/parts';
        return null;
      },
      routes: [
        GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => HomeShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/parts', builder: (_, _) => const ProductsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/services', builder: (_, _) => const NearbyShopsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/bookings', builder: (_, _) => const BookingsScreen())]),
            StatefulShellBranch(routes: [GoRoute(path: '/account', builder: (_, _) => const AccountScreen())]),
          ],
        ),
        GoRoute(path: '/products/:id', builder: (_, s) => ProductDetailScreen(productId: s.pathParameters['id']!)),
        GoRoute(
          path: '/shops/:id/book',
          builder: (_, s) => BookServiceScreen(vendorId: s.pathParameters['id']!, vendorName: s.uri.queryParameters['name'] ?? ''),
        ),
        GoRoute(path: '/bookings/:id', builder: (_, s) => BookingDetailScreen(bookingId: s.pathParameters['id']!)),
      ],
    );

class CustomerApp extends ConsumerStatefulWidget {
  const CustomerApp({super.key});
  @override
  ConsumerState<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends ConsumerState<CustomerApp> {
  late final GoRouter _router = buildRouter(ref.read(sessionProvider));

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) => MaterialApp.router(
        title: 'AutoHub',
        debugShowCheckedModeBanner: false,
        theme: autohubTheme(seed: const Color(0xFF0F766E)),
        darkTheme: autohubTheme(seed: const Color(0xFF0F766E), brightness: Brightness.dark),
        locale: Locale(session.language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        routerConfig: _router,
      ),
    );
  }
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});
  @override
  Widget build(BuildContext context) => OtpLoginScreen(title: AppLocalizations.of(context).loginTitle);
}

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.settings_suggest_outlined), label: t.tabParts),
          NavigationDestination(icon: const Icon(Icons.car_repair_outlined), label: t.tabServices),
          NavigationDestination(icon: const Icon(Icons.event_note_outlined), label: t.tabBookings),
          NavigationDestination(icon: const Icon(Icons.person_outline), label: t.tabAccount),
        ],
      ),
    );
  }
}
