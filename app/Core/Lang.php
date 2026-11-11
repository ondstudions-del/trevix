<?php
declare(strict_types=1);

namespace Trevix\Core;

use Trevix\Models\User;

/**
 * Idioma de la interfaz. Los textos se escriben en español en el código y t() los traduce con los diccionarios
 * de app/Lang/<idioma>/*.php (texto en español => traducción). Lo que no esté en el diccionario se muestra en
 * español. Los marcadores {nombre} se reemplazan después de traducir.
 *
 * Web: idioma de la cuenta, si no la cookie, si no el del navegador. API: solo el que pide la app con
 * Accept-Language (sin cabecera, español), para que la app no mezcle idiomas mientras no esté traducida.
 */
final class Lang
{
    public const SUPPORTED = ['es' => 'Español', 'en' => 'English'];
    public const DEFAULT = 'es';
    public const COOKIE = 'trevix_lang';

    private static ?string $locale = null;
    /** @var array<string, array<string, string>> */
    private static array $dictionaries = [];

    public static function locale(): string
    {
        return self::$locale ??= self::detect();
    }

    public static function isSupported(string $locale): bool
    {
        return isset(self::SUPPORTED[$locale]);
    }

    /** Cambia el idioma de esta petición (p. ej. para escribir un correo en el idioma de quien lo recibe). */
    public static function use(string $locale): void
    {
        if (self::isSupported($locale)) {
            self::$locale = $locale;
        }
    }

    /** Guarda el idioma elegido: en la cookie (un año) y, con sesión, en la cuenta. */
    public static function remember(string $locale): void
    {
        if (!self::isSupported($locale)) {
            return;
        }
        self::$locale = $locale;
        if (!headers_sent()) {
            setcookie(self::COOKIE, $locale, [
                'expires'  => time() + 365 * 86400,
                'path'     => base_path() === '' ? '/' : base_path() . '/',
                'secure'   => Request::isHttps(),
                'httponly' => true,
                'samesite' => 'Lax',
            ]);
        }
        $id = Auth::id();
        if ($id !== null) {
            User::setLocale($id, $locale);
        }
    }

    public static function t(string $text, array $params = []): string
    {
        $locale = self::locale();
        if ($locale !== self::DEFAULT) {
            $text = self::dictionary($locale)[$text] ?? $text;
        }
        if ($params === []) {
            return $text;
        }
        $replace = [];
        foreach ($params as $key => $value) {
            $replace['{' . $key . '}'] = (string) $value;
        }
        return strtr($text, $replace);
    }

    /** Textos que usa el JavaScript del cliente (app/Lang/<idioma>/js.php). */
    public static function clientDictionary(): array
    {
        $locale = self::locale();
        if ($locale === self::DEFAULT) {
            return [];
        }
        $file = APP_PATH . '/Lang/' . $locale . '/js.php';
        return is_file($file) ? (array) require $file : [];
    }

    /** @return array<string, string> */
    private static function dictionary(string $locale): array
    {
        if (!isset(self::$dictionaries[$locale])) {
            $dictionary = [];
            foreach (glob(APP_PATH . '/Lang/' . $locale . '/*.php') ?: [] as $file) {
                $dictionary += (array) require $file;
            }
            self::$dictionaries[$locale] = $dictionary;
        }
        return self::$dictionaries[$locale];
    }

    private static function detect(): string
    {
        if (defined('TREVIX_API')) {
            return self::fromHeader((string) ($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '')) ?? self::DEFAULT;
        }
        $user = Auth::user();
        if ($user !== null && self::isSupported((string) ($user['locale'] ?? ''))) {
            return (string) $user['locale'];
        }
        $cookie = (string) ($_COOKIE[self::COOKIE] ?? '');
        if (self::isSupported($cookie)) {
            return $cookie;
        }
        return self::fromHeader((string) ($_SERVER['HTTP_ACCEPT_LANGUAGE'] ?? '')) ?? self::DEFAULT;
    }

    /** Primer idioma admitido de una cabecera Accept-Language («en-US,en;q=0.9,es;q=0.8»). */
    private static function fromHeader(string $header): ?string
    {
        $best = null;
        $bestQ = 0.0;
        foreach (explode(',', $header) as $part) {
            $pieces = explode(';', trim($part));
            $code = strtolower(substr(trim($pieces[0]), 0, 2));
            $q = 1.0;
            if (isset($pieces[1]) && preg_match('/q=([0-9.]+)/', $pieces[1], $m)) {
                $q = (float) $m[1];
            }
            if (self::isSupported($code) && $q > $bestQ) {
                $best = $code;
                $bestQ = $q;
            }
        }
        return $best;
    }
}
