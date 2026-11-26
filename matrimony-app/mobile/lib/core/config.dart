/// App-wide settings. Change the name/ID here before the first Play Store upload.
///
/// The API address comes from a build flag so the same code works everywhere:
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1      (Android emulator -> your PC)
///   flutter run --dart-define=API_URL=http://192.168.1.20:8000/api/v1  (real phone on your Wi-Fi)
///   flutter build appbundle --dart-define=API_URL=https://api.ghargharmatrimony.com/api/v1
class Config {
  static const appName = 'GharGharMatrimony';
  static const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');

  static Uri get _api => Uri.parse(apiUrl);
  static String get origin => '${_api.scheme}://${_api.authority}';

  /// Backend returns signed media paths like /api/v1/media/...; make them absolute.
  static String? media(String? path) => path == null ? null : (path.startsWith('http') ? path : '$origin$path');

  static String ws(String ticket) {
    final scheme = _api.scheme == 'https' ? 'wss' : 'ws';
    return '$scheme://${_api.authority}${_api.path}/ws?ticket=${Uri.encodeComponent(ticket)}';
  }
}
