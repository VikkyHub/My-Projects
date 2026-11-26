import 'package:autohub_core/autohub_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../parts/products_screen.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = AppLocalizations.of(context);
    final session = ref.watch(sessionProvider);
    final user = session.user ?? const {};
    final vehicles = ref.watch(vehiclesProvider).asData?.value ?? const [];
    return Scaffold(
      appBar: AppBar(title: Text(t.tabAccount)),
      body: ListView(children: [
        ListTile(
          leading: const CircleAvatar(child: Icon(Icons.person)),
          title: Text(user['fullName'] as String? ?? user['phone'] as String? ?? ''),
          subtitle: Text(user['phone'] as String? ?? ''),
        ),
        if (user['walletBalancePaise'] != null)
          ListTile(leading: const Icon(Icons.account_balance_wallet_outlined), title: const Text('Wallet'),
              trailing: Text(formatPaise(user['walletBalancePaise'] as num))),
        const Divider(),
        for (final v in vehicles)
          ListTile(leading: const Icon(Icons.directions_car), title: Text(vehicleLabel(v)), subtitle: Text('${v['fuelType']}'),
              trailing: v['isDefault'] == true ? const Icon(Icons.star, size: 18) : null),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.translate),
          title: Text(t.language),
          trailing: DropdownButton<String>(
            value: session.language,
            underline: const SizedBox.shrink(),
            items: [for (final e in supportedLanguages.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => v == null ? null : session.setLanguage(v),
          ),
        ),
        ListTile(leading: const Icon(Icons.dns_outlined), title: Text(t.serverAddress), subtitle: Text(ref.read(coreProvider).config.apiBaseUrl)),
        ListTile(leading: const Icon(Icons.logout), title: Text(t.logout), onTap: session.logout),
      ]),
    );
  }
}
