<?php
declare(strict_types=1);

namespace Trevix\Core;

use PDO;
use Throwable;

/**
 * Conexión PDO perezosa: solo se abre la primera vez que un modelo la necesita,
 * así las páginas públicas no dependen de MySQL.
 */
final class Database
{
    private static ?PDO $pdo = null;

    public static function connection(): PDO
    {
        if (self::$pdo instanceof PDO) {
            return self::$pdo;
        }

        $c = Config::get('database');
        $dsn = sprintf(
            'mysql:host=%s;port=%d;dbname=%s;charset=%s',
            $c['host'],
            $c['port'],
            $c['name'],
            $c['charset']
        );

        self::$pdo = new PDO($dsn, $c['user'], $c['password'], [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false,
            PDO::ATTR_STRINGIFY_FETCHES  => false,
        ]);

        $stmt = self::$pdo->prepare('SET time_zone = ?');
        $stmt->execute([date('P')]);

        return self::$pdo;
    }

    /**
     * Tras una espera larga (p. ej. una llamada a una API externa), MySQL puede haber cerrado la conexión por
     * inactividad: si no responde, la descarta para que la siguiente consulta abra una nueva.
     */
    public static function ensureAlive(): void
    {
        if (!self::$pdo instanceof PDO || self::$pdo->inTransaction()) {
            return;
        }
        try {
            @self::$pdo->query('SELECT 1');
        } catch (Throwable) {
            self::$pdo = null;
        }
    }

    /** Si ya hay una transacción abierta, el callback se ejecuta dentro de ella. */
    public static function transaction(callable $callback): mixed
    {
        $pdo = self::connection();
        if ($pdo->inTransaction()) {
            return $callback($pdo);
        }
        $pdo->beginTransaction();
        try {
            $result = $callback($pdo);
            $pdo->commit();
            return $result;
        } catch (Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }
    }
}
