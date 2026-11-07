<?php
declare(strict_types=1);

namespace Trevix\Core;

use RuntimeException;

/**
 * Error esperado de una acción (validación, permisos, límites). Lo lanzan los servicios compartidos
 * entre la web y la API: la web lo muestra como aviso o error de formulario y la API lo responde en JSON.
 * $fields asocia mensajes a campos concretos (p. ej. ['body' => 'Escribe algo.']).
 */
final class ActionError extends RuntimeException
{
    /** @param array<string, string> $fields */
    public function __construct(
        string $message,
        public readonly int $status = 422,
        public readonly array $fields = [],
        public readonly ?int $retryAfter = null,
    ) {
        parent::__construct($message);
    }

    /** Error de validación de un solo campo. */
    public static function field(string $field, string $message, int $status = 422): self
    {
        return new self($message, $status, [$field => $message]);
    }

    /** Errores de validación de varios campos; el primero es el mensaje general. */
    public static function fields(array $fields): self
    {
        return new self((string) reset($fields), 422, $fields);
    }
}
