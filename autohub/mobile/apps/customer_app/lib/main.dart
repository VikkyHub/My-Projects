import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final core = await bootstrapCore('customer');
  runApp(ProviderScope(overrides: [coreProvider.overrideWithValue(core)], child: const CustomerApp()));
}
