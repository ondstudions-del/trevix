/// Direcciones del servidor. Se pueden cambiar al compilar con --dart-define=TREVIX_SITE=https://…/
class AppConfig {
  static const site = String.fromEnvironment('TREVIX_SITE', defaultValue: 'https://trevix.ond-s.com/');
  static const apiBase = '${site}api/v1/';

  /// Versión visible de la app. Cada lanzamiento suma una décima (Alpha 1.2, 1.3 … 1.9 y luego 2.0); debe coincidir
  /// con «version» de pubspec.yaml (1.2.0 → Alpha 1.2). Historial en docs/VERSIONES.md.
  static const version = 'Alpha 1.7';

  static String web(String path) => '$site$path';
}
