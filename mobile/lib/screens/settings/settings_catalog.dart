import 'package:flutter/cupertino.dart';

import '../../core/i18n.dart';

/// Catálogo de las 11 agrupaciones del hub de Ajustes.
enum SettingsCategory {
  account,
  security,
  payments,
  chats,
  notifications,
  appearance,
  devices,
  content,
  team,
  info,
  session,
}

class SettingsCategoryMeta {
  const SettingsCategoryMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    this.staffOnly = false,
  });

  final SettingsCategory id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool staffOnly;
}

List<SettingsCategoryMeta> settingsCategories({required bool isStaff}) {
  final all = [
    SettingsCategoryMeta(
      id: SettingsCategory.account,
      title: tr('Cuenta y VINCRIPTAR'),
      subtitle: tr('Perfil, correo, verificación y vincular dispositivo'),
      icon: CupertinoIcons.person_crop_circle_fill,
      color: const Color(0xFF8B5CF6),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.security,
      title: tr('Seguridad y privacidad'),
      subtitle: tr('Contraseña, sesiones, bloqueo y privacidad'),
      icon: CupertinoIcons.lock_shield_fill,
      color: const Color(0xFF06B6D4),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.payments,
      title: tr('Pagos y colaborador'),
      subtitle: tr('Monedero, regalos, suscripciones y colaborador'),
      icon: CupertinoIcons.creditcard_fill,
      color: const Color(0xFF22C55E),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.chats,
      title: tr('Chats y comunicación'),
      subtitle: tr('Lecturas, cifrado, chats privados y grupos'),
      icon: CupertinoIcons.chat_bubble_2_fill,
      color: const Color(0xFF3B82F6),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.notifications,
      title: tr('Notificaciones'),
      subtitle: tr('Push y avisos de actividad'),
      icon: CupertinoIcons.bell_fill,
      color: const Color(0xFFF59E0B),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.appearance,
      title: tr('Apariencia y preferencias'),
      subtitle: tr('Tema, accesibilidad e idioma'),
      icon: CupertinoIcons.paintbrush_fill,
      color: const Color(0xFFA855F7),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.devices,
      title: tr('Dispositivos y contactos'),
      subtitle: tr('Permisos del teléfono e invitar contactos'),
      icon: CupertinoIcons.device_phone_portrait,
      color: const Color(0xFF14B8A6),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.content,
      title: tr('Contenido y comunidades'),
      subtitle: tr('Guardados, comunidades, música y artista'),
      icon: CupertinoIcons.square_stack_3d_up_fill,
      color: const Color(0xFFEC4899),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.team,
      title: tr('Equipo y administración'),
      subtitle: tr('Panel del equipo de TREVIX'),
      icon: CupertinoIcons.shield_lefthalf_fill,
      color: const Color(0xFF7C3AED),
      staffOnly: true,
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.info,
      title: tr('Información y soporte'),
      subtitle: tr('Términos, privacidad y bienvenida'),
      icon: CupertinoIcons.doc_text_fill,
      color: const Color(0xFF64748B),
    ),
    SettingsCategoryMeta(
      id: SettingsCategory.session,
      title: tr('Sesión y cuenta'),
      subtitle: tr('Cambiar cuenta, cerrar sesión y zona delicada'),
      icon: CupertinoIcons.square_arrow_right,
      color: const Color(0xFFEF4444),
    ),
  ];
  return all.where((c) => !c.staffOnly || isStaff).toList();
}

/// Entradas indexables por el buscador del hub.
class SettingsSearchHit {
  const SettingsSearchHit({
    required this.category,
    required this.label,
    required this.keywords,
  });

  final SettingsCategory category;
  final String label;
  final String keywords;
}

List<SettingsSearchHit> settingsSearchIndex() => [
      SettingsSearchHit(category: SettingsCategory.account, label: tr('Editar perfil'), keywords: 'perfil nombre bio'),
      SettingsSearchHit(category: SettingsCategory.account, label: tr('Usuario y correo'), keywords: 'email correo usuario'),
      SettingsSearchHit(category: SettingsCategory.account, label: tr('VINCRIPTAR'), keywords: 'vincular dispositivo codigo'),
      SettingsSearchHit(category: SettingsCategory.account, label: tr('Verificación'), keywords: 'verificado insignia'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Contraseña'), keywords: 'password clave'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Sesiones activas'), keywords: 'dispositivos sesiones'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Estado de la cuenta'), keywords: 'advertencias apelaciones'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Bloqueo de app'), keywords: 'face id pin huella'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Cuenta privada'), keywords: 'privado seguidores'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Cuentas bloqueadas'), keywords: 'bloquear'),
      SettingsSearchHit(category: SettingsCategory.security, label: tr('Mejores amigos'), keywords: 'amigos nota'),
      SettingsSearchHit(category: SettingsCategory.payments, label: tr('Monedero'), keywords: 'saldo recarga paypal google'),
      SettingsSearchHit(category: SettingsCategory.payments, label: tr('OND-ADS'), keywords: 'anuncios patrocinado promocion ads'),
      SettingsSearchHit(category: SettingsCategory.payments, label: tr('Colaborador'), keywords: 'suscripcion plan'),
      SettingsSearchHit(category: SettingsCategory.payments, label: tr('Regalos'), keywords: 'gift'),
      SettingsSearchHit(category: SettingsCategory.chats, label: tr('Cifrado'), keywords: 'e2ee seguridad chat'),
      SettingsSearchHit(category: SettingsCategory.chats, label: tr('Chats privados'), keywords: 'pin privado'),
      SettingsSearchHit(category: SettingsCategory.notifications, label: tr('Notificaciones'), keywords: 'avisos push likes comentarios'),
      SettingsSearchHit(category: SettingsCategory.appearance, label: tr('Apariencia'), keywords: 'tema oscuro claro'),
      SettingsSearchHit(category: SettingsCategory.appearance, label: tr('Idioma'), keywords: 'español ingles language'),
      SettingsSearchHit(category: SettingsCategory.devices, label: tr('Permisos'), keywords: 'camara microfono ubicacion'),
      SettingsSearchHit(category: SettingsCategory.content, label: tr('Guardados'), keywords: 'saved bookmarks'),
      SettingsSearchHit(category: SettingsCategory.content, label: tr('Comunidades'), keywords: 'comunidad'),
      SettingsSearchHit(category: SettingsCategory.content, label: tr('Mis apps'), keywords: 'oauth api desarrollador developer'),
      SettingsSearchHit(category: SettingsCategory.team, label: tr('Panel del equipo'), keywords: 'admin moderador'),
      SettingsSearchHit(category: SettingsCategory.team, label: tr('Apps OAuth'), keywords: 'oauth apps desarrolladores'),
      SettingsSearchHit(category: SettingsCategory.info, label: tr('Términos'), keywords: 'legal privacidad cookies'),
      SettingsSearchHit(category: SettingsCategory.session, label: tr('Cerrar sesión'), keywords: 'logout salir'),
      SettingsSearchHit(category: SettingsCategory.session, label: tr('Eliminar cuenta'), keywords: 'borrar desactivar'),
    ];
