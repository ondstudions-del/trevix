import 'dart:io';

import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:gal/gal.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Permiso del dispositivo y para qué lo usa TREVIX.
enum Access { notifications, location, contacts, photos, microphone }

enum AccessState { unknown, granted, denied }

/// Error con un mensaje en español listo para mostrar.
class DeviceException implements Exception {
  DeviceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Permisos del iPhone y las funciones reales que dependen de ellos:
///  - notificaciones: avisos de mensajes y notificaciones nuevas;
///  - ubicación: completar el país del perfil;
///  - contactos: invitar a tus contactos por SMS;
///  - fotos: guardar imágenes en la galería;
///  - micrófono: grabar notas de voz.
class DeviceAccess {
  DeviceAccess._();

  static final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();
  static bool _notificationsReady = false;
  static final Map<Access, AccessState> _cache = {};

  static String _key(Access a) => 'trevix_access_${a.name}';

  static Future<void> _remember(Access a, bool granted) async {
    _cache[a] = granted ? AccessState.granted : AccessState.denied;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(a), granted);
  }

  /// Estado conocido sin mostrar el diálogo del sistema.
  static Future<AccessState> state(Access a) async {
    final cached = _cache[a];
    if (a == Access.location) {
      final p = await Geolocator.checkPermission();
      if (p == LocationPermission.deniedForever) return AccessState.denied;
      return p == LocationPermission.denied ? AccessState.unknown : AccessState.granted;
    }
    if (a == Access.contacts) {
      return switch (await fc.FlutterContacts.permissions.check(fc.PermissionType.read)) {
        fc.PermissionStatus.granted || fc.PermissionStatus.limited => AccessState.granted,
        fc.PermissionStatus.notDetermined => AccessState.unknown,
        _ => AccessState.denied,
      };
    }
    if (a == Access.photos && await Gal.hasAccess()) return AccessState.granted;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_key(a));
    if (value == null) return AccessState.unknown;
    return _cache[a] = value ? AccessState.granted : AccessState.denied;
  }

  /// Muestra el diálogo del sistema (la primera vez) y devuelve si quedó concedido.
  static Future<bool> request(Access a) async {
    var granted = false;
    switch (a) {
      case Access.notifications:
        await _initNotifications();
        final ios = _notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        granted = await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
      case Access.location:
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        granted = p == LocationPermission.whileInUse || p == LocationPermission.always;
      case Access.contacts:
        final s = await fc.FlutterContacts.permissions.request(fc.PermissionType.read);
        granted = s == fc.PermissionStatus.granted || s == fc.PermissionStatus.limited;
      case Access.photos:
        granted = await Gal.hasAccess() || await Gal.requestAccess();
      case Access.microphone:
        final recorder = AudioRecorder();
        try {
          granted = await recorder.hasPermission();
        } finally {
          await recorder.dispose();
        }
    }
    await _remember(a, granted);
    return granted;
  }

  /// Ajustes de TREVIX en el iPhone, para reactivar un permiso rechazado.
  static Future<void> openSettings() => launchUrl(Uri.parse('app-settings:'));

  // ---------- Notificaciones ----------

  static Future<void> _initNotifications() async {
    if (_notificationsReady) return;
    await _notifications.initialize(const InitializationSettings(
      iOS: DarwinInitializationSettings(requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
    ));
    _notificationsReady = true;
  }

  /// Aviso local; no hace nada si el usuario no concedió el permiso.
  static Future<void> notify(int id, String title, String body) async {
    try {
      if (await state(Access.notifications) != AccessState.granted) return;
      await _initNotifications();
      await _notifications.show(
        id,
        title,
        body,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentList: true, presentSound: true),
        ),
      );
    } catch (_) {}
  }

  // ---------- Ubicación ----------

  /// Código ISO del país donde está el teléfono (para el perfil).
  static Future<String> detectCountry() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw DeviceException('Activa la ubicación en Ajustes › Privacidad › Localización.');
    }
    if (!await request(Access.location)) {
      throw DeviceException('TREVIX no tiene permiso de ubicación. Puedes activarlo en Ajustes.');
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.low, timeLimit: Duration(seconds: 20)),
      );
      final marks = await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final code = marks.isEmpty ? '' : (marks.first.isoCountryCode ?? '').toUpperCase();
      if (code.length != 2) throw DeviceException('No pudimos reconocer tu país.');
      return code;
    } on DeviceException {
      rethrow;
    } catch (_) {
      throw DeviceException('No pudimos obtener tu ubicación. Inténtalo de nuevo.');
    }
  }

  /// Lugar actual para publicar: «Barrio, Ciudad, País» y coordenadas redondeadas a ~100 m (sin la dirección exacta).
  static Future<({String name, double lat, double lng})> currentPlace() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw DeviceException('Activa la ubicación en Ajustes › Privacidad › Localización.');
    }
    if (!await request(Access.location)) {
      throw DeviceException('TREVIX no tiene permiso de ubicación. Puedes activarlo en Ajustes.');
    }
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 20)),
      );
      double round(double v) => (v * 1000).roundToDouble() / 1000;
      final lat = round(pos.latitude), lng = round(pos.longitude);
      final marks = await placemarkFromCoordinates(lat, lng);
      final m = marks.isEmpty ? null : marks.first;
      final parts = <String>[
        for (final part in [m?.subLocality, m?.locality ?? m?.subAdministrativeArea, m?.country])
          if (part != null && part.trim().isNotEmpty) part.trim(),
      ];
      final name = parts.toSet().join(', ');
      if (name.isEmpty) throw DeviceException('No encontramos el nombre de este lugar. Escríbelo tú.');
      return (name: name.length > 120 ? name.substring(0, 120) : name, lat: lat, lng: lng);
    } on DeviceException {
      rethrow;
    } catch (_) {
      throw DeviceException('No pudimos obtener tu ubicación. Inténtalo de nuevo.');
    }
  }

  // ---------- Contactos ----------

  /// Contactos con al menos un teléfono, ordenados por nombre.
  static Future<List<fc.Contact>> contacts() async {
    if (!await request(Access.contacts)) {
      throw DeviceException('TREVIX no tiene permiso para ver tus contactos. Puedes activarlo en Ajustes.');
    }
    final list = await fc.FlutterContacts.getAll(properties: {fc.ContactProperty.name, fc.ContactProperty.phone});
    final withPhone = list.where((c) => c.phones.isNotEmpty).toList()
      ..sort((a, b) => (a.displayName ?? '').toLowerCase().compareTo((b.displayName ?? '').toLowerCase()));
    return withPhone;
  }

  // ---------- Fotos ----------

  /// Descarga la imagen y la guarda en la galería del iPhone.
  static Future<void> saveImage(String url) async {
    if (!await request(Access.photos)) {
      throw DeviceException('TREVIX no tiene permiso para guardar en Fotos. Puedes activarlo en Ajustes.');
    }
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 60));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) throw DeviceException('No se pudo descargar la imagen.');
    final path = Uri.parse(url).path.toLowerCase();
    final ext = path.endsWith('.png') ? 'png' : path.endsWith('.webp') ? 'webp' : path.endsWith('.gif') ? 'gif' : 'jpg';
    final file = File('${(await getTemporaryDirectory()).path}/trevix_${DateTime.now().millisecondsSinceEpoch}.$ext');
    await file.writeAsBytes(res.bodyBytes);
    try {
      await Gal.putImage(file.path);
    } on GalException catch (e) {
      throw DeviceException(e.type == GalExceptionType.accessDenied ? 'TREVIX no tiene permiso para guardar en Fotos.' : 'No se pudo guardar la imagen.');
    } finally {
      if (await file.exists()) await file.delete();
    }
  }
}
