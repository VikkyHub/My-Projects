/// Shared building blocks for the AutoHub customer and vendor apps.
library;

import 'src/api_client.dart';
import 'src/config.dart';
import 'src/response_cache.dart';
import 'src/session.dart';
import 'src/token_store.dart';

export 'l10n/gen/app_localizations.dart';
export 'src/api_client.dart';
export 'src/config.dart';
export 'src/login_screen.dart';
export 'src/money.dart';
export 'src/payments.dart';
export 'src/response_cache.dart';
export 'src/session.dart';
export 'src/token_store.dart';
export 'src/ui.dart';

/// Wires config → secure token store → offline cache → API client → session.
Future<Core> bootstrapCore(String clientApp) async {
  final config = await AppConfig.load(clientApp);
  final tokens = SecureTokenStore('autohub.$clientApp');
  final cache = await SqfliteResponseCache.open('autohub_${clientApp}_cache');
  late final SessionController session;
  final api = ApiClient(config: config, tokens: tokens, cache: cache, onLoggedOut: () => session.onForcedLogout());
  session = SessionController(api, tokens);
  await session.restore();
  return Core(config: config, api: api, session: session);
}
