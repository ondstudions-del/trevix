/// Direcciones del servidor. Se pueden cambiar al compilar con --dart-define=TREVIX_SITE=https://…/
class AppConfig {
  static const site = String.fromEnvironment('TREVIX_SITE', defaultValue: 'https://trevix.ond-s.com/');
  static const apiBase = '${site}api/v1/';

  static String web(String path) => '$site$path';
}
