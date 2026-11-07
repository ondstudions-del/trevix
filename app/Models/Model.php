<?php
declare(strict_types=1);

namespace Trevix\Models;

use PDO;
use Trevix\Core\Database;

/** Base de los modelos: todas las consultas pasan por sentencias preparadas. */
abstract class Model
{
    protected static function db(): PDO
    {
        return Database::connection();
    }

    protected static function fetchOne(string $sql, array $params = []): ?array
    {
        $stmt = self::db()->prepare($sql);
        $stmt->execute($params);
        $row = $stmt->fetch();
        return $row === false ? null : $row;
    }

    protected static function fetchAll(string $sql, array $params = []): array
    {
        $stmt = self::db()->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchAll();
    }

    protected static function fetchValue(string $sql, array $params = []): mixed
    {
        $stmt = self::db()->prepare($sql);
        $stmt->execute($params);
        return $stmt->fetchColumn();
    }

    protected static function execute(string $sql, array $params = []): int
    {
        $stmt = self::db()->prepare($sql);
        $stmt->execute($params);
        return $stmt->rowCount();
    }

    /** Lista de palabras vacías por defecto de InnoDB: con "+" obligatorio anularían toda la búsqueda. */
    private const FULLTEXT_STOPWORDS = [
        'about', 'are', 'com', 'for', 'from', 'how', 'that', 'the', 'this', 'was', 'what', 'when', 'where',
        'who', 'will', 'with', 'und', 'www',
    ];

    /**
     * Convierte lo que escribió el usuario en una consulta FULLTEXT en modo booleano ("+palabra*" por término).
     * Descarta operadores, palabras de menos de 3 letras (no se indexan) y palabras vacías.
     * Devuelve '' si no queda ningún término útil: en ese caso se busca con LIKE.
     */
    protected static function booleanSearch(string $term): string
    {
        $words = preg_split('/[^\p{L}\p{N}_]+/u', mb_strtolower($term), -1, PREG_SPLIT_NO_EMPTY) ?: [];
        $words = array_filter(
            array_unique($words),
            static fn (string $w) => mb_strlen($w) >= 3 && !in_array($w, self::FULLTEXT_STOPWORDS, true)
        );
        return implode(' ', array_map(static fn (string $w) => '+' . $w . '*', array_slice($words, 0, 8)));
    }

    /** Escapa los comodines de LIKE para buscar el texto literal. */
    protected static function likeEscape(string $term): string
    {
        return addcslashes($term, '%_\\');
    }
}
