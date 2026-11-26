import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import 'api_client.dart';

/// One palette for both apps. Plain Material 3 — cheap to render on low-end phones.
ThemeData autohubTheme({required Color seed, Brightness brightness = Brightness.light}) {
  final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: scheme.outlineVariant)),
      margin: EdgeInsets.zero,
    ),
  );
}

const supportedLanguages = {'en': 'English', 'hi': 'हिन्दी', 'mr': 'मराठी'};

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final msg = error is ApiException ? (error as ApiException).message : t.somethingWrong;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(error is ApiException && (error as ApiException).isNetwork ? Icons.wifi_off : Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center),
          if (onRetry != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(t.retry)),
          ],
        ]),
      ),
    );
  }
}

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onTertiaryContainer),
          const SizedBox(width: 8),
          Expanded(child: Text(AppLocalizations.of(context).offlineBanner, style: TextStyle(color: scheme.onTertiaryContainer))),
        ]),
      ),
    );
  }
}

/// Localised label for a booking status code.
String bookingStatusLabel(AppLocalizations t, String status) => switch (status) {
      'requested' => t.status_requested,
      'confirmed' => t.status_confirmed,
      'vehicle_received' => t.status_vehicle_received,
      'estimate_shared' => t.status_estimate_shared,
      'in_progress' => t.status_in_progress,
      'ready' => t.status_ready,
      'completed' => t.status_completed,
      'rejected' => t.status_rejected,
      'cancelled' => t.status_cancelled,
      'no_show' => t.status_no_show,
      _ => status,
    };

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      'completed' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'cancelled' || 'rejected' || 'no_show' => (scheme.errorContainer, scheme.onErrorContainer),
      'estimate_shared' || 'ready' || 'requested' => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(bookingStatusLabel(AppLocalizations.of(context), status),
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

void showError(BuildContext context, Object e) {
  final msg = e is ApiException ? e.message : AppLocalizations.of(context).somethingWrong;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}
