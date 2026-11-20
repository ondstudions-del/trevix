# TREVIX · Inicio de sesión con TREVIX (OAuth)

Las apps de desarrolladores pueden iniciar sesión de usuarios que ya tienen cuenta TREVIX.
**Solo se comparte:** foto de perfil, nombre de usuario, nombre visible y acceso a la plataforma.
**Nunca** se comparten contraseñas ni datos cifrados.

## Requisitos

1. Cuenta **Creador › Desarrollador**.
2. Crear la app en Ajustes → Contenido → **Mis apps** (icono, nombre, paquete o URL web, descripción, redirect URIs).
3. Guardar el `client_id` y la `client_secret` (la clave solo se muestra una vez).
4. Un administrador o moderador debe **aprobar** la solicitud.

## Flujo

1. Redirige al usuario a:
   `https://treviix.app/oauth/authorize.php?client_id=TVX…&redirect_uri=…&state=…`
2. El usuario inicia sesión (o usa VINCRIPTAR) y pulsa **Permitir**.
3. TREVIX redirige a tu `redirect_uri` con `?code=…&state=…`.
4. Tu backend intercambia el código:

```http
POST /api/v1/oauth/token
Content-Type: application/json

{
  "client_id": "tvx_…",
  "client_secret": "tvs_…",
  "code": "…",
  "redirect_uri": "https://tu-app.com/callback"
}
```

Respuesta:

```json
{
  "access_token": "tva_…",
  "token_type": "Bearer",
  "expires_in": 2592000,
  "user": {
    "id": 1,
    "username": "ana",
    "display_name": "Ana",
    "avatar_url": "https://…",
    "platform": "trevix"
  }
}
```

5. Perfil actualizado:

```http
GET /api/v1/oauth/userinfo
Authorization: Bearer tva_…
```

## App Android / iOS

En el formulario usa el **paquete** (`com.empresa.app`).

## App web

En el formulario elige **Web** e indica la **URL** del sitio (en lugar del paquete).
