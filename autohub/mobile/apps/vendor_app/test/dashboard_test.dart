import 'package:autohub_core/autohub_core.dart';
import 'package:autohub_vendor/features/dashboard/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shape of GET /v1/vendor/dashboard (trimmed from a real response).
final sample = <String, dynamic>{
  'vendor': {'id': 'v1', 'businessName': 'Shree Auto Parts & Service', 'status': 'approved', 'isAcceptingOrders': true,
      'ratingAvg': 4.67, 'ratingCount': 6},
  'today': {
    'date': '2026-11-26', 'newOrders': 2, 'ordersToDispatch': 3,
    'bookings': {'total': 4, 'requested': 1, 'inProgress': 2, 'completed': 1},
    'revenuePaise': 1849500,
    'schedule': [
      {'id': 'b1', 'bookingNumber': 'BKG-261126-000001', 'status': 'requested', 'localTime': '10:30', 'model': 'Swift',
          'registrationNumber': 'MH12AB1234', 'customerName': 'Rahul Patil', 'serviceNames': 'AC Gas Refill (R134a)'},
    ],
  },
  'actionItems': [
    {'type': 'low_stock', 'id': 'p1', 'label': 'Creta Front Brake Pads · 2 left', 'at': null},
  ],
  'earnings': {'availablePaise': 1147893, 'onHoldPaise': 473165, 'payoutInProgress': null},
  'last7Days': [
    for (var d = 20; d <= 26; d++) {'date': '2026-11-$d', 'revenuePaise': d * 10000, 'orders': 0, 'bookings': 1, 'profileViews': 120},
  ],
  'unreadChats': 0,
};

Widget wrap(Widget child, {Locale locale = const Locale('en')}) => MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('shows KPIs, action items, schedule and the 7-day chart', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(wrap(DashboardBody(data: sample)));
    expect(find.text('₹18,495'), findsOneWidget);           // revenue today
    expect(find.text('₹11,478.93'), findsOneWidget);        // available balance
    expect(find.text('Creta Front Brake Pads · 2 left'), findsOneWidget);
    expect(find.text('10:30'), findsOneWidget);
    expect(find.text('Waiting for shop'), findsOneWidget);  // status chip
    expect(find.byType(RevenueBars), findsOneWidget);
    expect(find.byType(OfflineBanner), findsNothing);
  });

  testWidgets('renders in Hindi and shows the offline banner for cached data', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    await tester.pumpWidget(wrap(DashboardBody(data: sample, fromCache: true), locale: const Locale('hi')));
    expect(find.text('आज की कमाई'), findsOneWidget);
    expect(find.text('आज का शेड्यूल'), findsOneWidget);
    expect(find.byType(OfflineBanner), findsOneWidget);
  });

  testWidgets('hides money from staff accounts (earnings null)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 1600));
    // Staff accounts get the same payload with money fields nulled by the server.
    final staffView = <String, dynamic>{
      ...sample,
      'earnings': null,
      'today': <String, dynamic>{...sample['today'] as Map<String, dynamic>, 'revenuePaise': null},
      'last7Days': [for (final d in sample['last7Days'] as List) <String, dynamic>{...d as Map<String, dynamic>, 'revenuePaise': null}],
    };
    await tester.pumpWidget(wrap(DashboardBody(data: staffView)));
    expect(find.text('Revenue today'), findsNothing);
    expect(find.text('Available'), findsNothing);
  });
}
