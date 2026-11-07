<?php
declare(strict_types=1);

namespace Trevix\Services;

use RuntimeException;
use Trevix\Core\Config;

/**
 * Envío de correos transaccionales (texto + HTML) por mail(), SMTP o registro en archivo.
 * Sin dependencias externas.
 */
final class Mailer
{
    /**
     * Correo con el diseño de TREVIX: título, párrafos y un botón opcional.
     *
     * @param list<string> $paragraphs
     */
    public static function send(string $to, string $subject, string $heading, array $paragraphs, ?string $buttonLabel = null, ?string $buttonUrl = null): bool
    {
        if (!filter_var($to, FILTER_VALIDATE_EMAIL) || preg_match('/[\r\n]/', $to)) {
            return false;
        }

        $subject = trim((string) preg_replace('/[\r\n]+/', ' ', $subject));
        $text = self::renderText($heading, $paragraphs, $buttonLabel, $buttonUrl);
        $html = self::renderHtml($heading, $paragraphs, $buttonLabel, $buttonUrl);

        try {
            match ((string) Config::get('app.mail.driver', 'log')) {
                'mail'  => self::sendWithMail($to, $subject, $text, $html),
                'smtp'  => self::sendWithSmtp($to, $subject, $text, $html),
                default => self::writeLog($to, $subject, $text),
            };
            return true;
        } catch (RuntimeException $e) {
            error_log('[Mailer] ' . $e->getMessage());
            return false;
        }
    }

    /** @param list<string> $paragraphs */
    private static function renderText(string $heading, array $paragraphs, ?string $buttonLabel, ?string $buttonUrl): string
    {
        $lines = [$heading, ''];
        foreach ($paragraphs as $paragraph) {
            $lines[] = $paragraph;
            $lines[] = '';
        }
        if ($buttonLabel !== null && $buttonUrl !== null) {
            $lines[] = $buttonLabel . ': ' . $buttonUrl;
            $lines[] = '';
        }
        $lines[] = '— El equipo de TREVIX';
        return implode("\n", $lines);
    }

    /** @param list<string> $paragraphs */
    private static function renderHtml(string $heading, array $paragraphs, ?string $buttonLabel, ?string $buttonUrl): string
    {
        $body = '';
        foreach ($paragraphs as $paragraph) {
            $body .= '<p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#d4d4d8">' . e($paragraph) . '</p>';
        }
        if ($buttonLabel !== null && $buttonUrl !== null) {
            $body .= '<p style="margin:24px 0"><a href="' . e($buttonUrl) . '" style="display:inline-block;padding:12px 22px;border-radius:10px;'
                . 'background:#7c3aed;color:#ffffff;font-weight:600;font-size:15px;text-decoration:none">' . e($buttonLabel) . '</a></p>'
                . '<p style="margin:0 0 16px;font-size:13px;line-height:1.5;color:#a1a1aa">Si el botón no funciona, copia este enlace en tu navegador:<br>'
                . '<span style="word-break:break-all;color:#c4b5fd">' . e($buttonUrl) . '</span></p>';
        }

        return '<!doctype html><html lang="es"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
            . '<title>' . e($heading) . '</title></head>'
            . '<body style="margin:0;padding:24px 12px;background:#09090b;font-family:Segoe UI,Helvetica,Arial,sans-serif">'
            . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center">'
            . '<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#18181b;border:1px solid #27272a;border-radius:16px">'
            . '<tr><td style="padding:28px 28px 8px"><span style="display:inline-block;width:36px;height:36px;line-height:36px;text-align:center;'
            . 'border-radius:10px;background:#7c3aed;color:#fff;font-weight:700;font-size:20px">#</span>'
            . '<span style="margin-left:10px;font-weight:700;font-size:18px;color:#fff;letter-spacing:1px;vertical-align:middle">TREVIX</span></td></tr>'
            . '<tr><td style="padding:16px 28px 12px"><h1 style="margin:0 0 16px;font-size:22px;color:#ffffff">' . e($heading) . '</h1>' . $body . '</td></tr>'
            . '<tr><td style="padding:0 28px 28px;font-size:12px;color:#71717a">Recibiste este correo por tu cuenta en TREVIX. Si no fuiste tú, puedes ignorarlo.</td></tr>'
            . '</table></td></tr></table></body></html>';
    }

    private static function sendWithMail(string $to, string $subject, string $text, string $html): void
    {
        $from = self::fromAddress();
        [$headers, $body] = self::buildMime($text, $html);
        $headerLines = ['From: ' . self::fromHeader()];
        foreach ($headers as $name => $value) {
            $headerLines[] = $name . ': ' . $value;
        }

        $sent = mail($to, self::encodeHeader($subject), $body, implode("\r\n", $headerLines), '-f' . $from);
        if (!$sent) {
            throw new RuntimeException('mail() rechazó el envío a ' . $to);
        }
    }

    private static function sendWithSmtp(string $to, string $subject, string $text, string $html): void
    {
        $c = (array) Config::get('app.mail.smtp', []);
        $host = (string) ($c['host'] ?? '');
        if ($host === '') {
            throw new RuntimeException('SMTP sin servidor configurado.');
        }
        $port = (int) ($c['port'] ?? 465);
        $encryption = (string) ($c['encryption'] ?? 'ssl');
        $timeout = (int) ($c['timeout'] ?? 15);

        $remote = ($encryption === 'ssl' ? 'ssl://' : 'tcp://') . $host . ':' . $port;
        $context = stream_context_create(['ssl' => ['verify_peer' => true, 'verify_peer_name' => true, 'peer_name' => $host]]);
        $socket = @stream_socket_client($remote, $errno, $errstr, $timeout, STREAM_CLIENT_CONNECT, $context);
        if ($socket === false) {
            throw new RuntimeException("No se pudo conectar a SMTP {$host}:{$port} ({$errstr})");
        }
        stream_set_timeout($socket, $timeout);

        try {
            $hostname = (string) (parse_url((string) Config::get('app.url', ''), PHP_URL_HOST) ?: 'localhost');
            self::smtpExpect($socket, 220);
            self::smtpCommand($socket, 'EHLO ' . $hostname, 250);

            if ($encryption === 'tls') {
                self::smtpCommand($socket, 'STARTTLS', 220);
                if (!stream_socket_enable_crypto($socket, true, STREAM_CRYPTO_METHOD_TLSv1_2_CLIENT | STREAM_CRYPTO_METHOD_TLSv1_3_CLIENT)) {
                    throw new RuntimeException('No se pudo iniciar TLS con el servidor SMTP.');
                }
                self::smtpCommand($socket, 'EHLO ' . $hostname, 250);
            }

            if (($c['username'] ?? '') !== '') {
                self::smtpCommand($socket, 'AUTH LOGIN', 334);
                self::smtpCommand($socket, base64_encode((string) $c['username']), 334);
                self::smtpCommand($socket, base64_encode((string) ($c['password'] ?? '')), 235, true);
            }

            self::smtpCommand($socket, 'MAIL FROM:<' . self::fromAddress() . '>', 250);
            self::smtpCommand($socket, 'RCPT TO:<' . $to . '>', [250, 251]);
            self::smtpCommand($socket, 'DATA', 354);

            [$headers, $body] = self::buildMime($text, $html);
            $message = 'Date: ' . date(DATE_RFC2822) . "\r\n"
                . 'From: ' . self::fromHeader() . "\r\n"
                . 'To: <' . $to . ">\r\n"
                . 'Subject: ' . self::encodeHeader($subject) . "\r\n"
                . 'Message-ID: <' . bin2hex(random_bytes(12)) . '@' . substr(strrchr(self::fromAddress(), '@') ?: '@localhost', 1) . ">\r\n";
            foreach ($headers as $name => $value) {
                $message .= $name . ': ' . $value . "\r\n";
            }
            $message .= "\r\n" . $body;
            $message = (string) preg_replace('/^\./m', '..', str_replace(["\r\n", "\n"], ["\n", "\r\n"], $message));

            fwrite($socket, $message . "\r\n.\r\n");
            self::smtpExpect($socket, 250);
            fwrite($socket, "QUIT\r\n");
        } finally {
            fclose($socket);
        }
    }

    /** @param resource $socket */
    private static function smtpCommand($socket, string $command, int|array $expected, bool $secret = false): void
    {
        fwrite($socket, $command . "\r\n");
        self::smtpExpect($socket, $expected, $secret ? '[credenciales]' : $command);
    }

    /** @param resource $socket */
    private static function smtpExpect($socket, int|array $expected, string $context = 'conexión'): void
    {
        $response = '';
        while (($line = fgets($socket, 515)) !== false) {
            $response .= $line;
            if (strlen($line) < 4 || $line[3] === ' ') {
                break;
            }
        }
        $code = (int) substr($response, 0, 3);
        if (!in_array($code, (array) $expected, true)) {
            throw new RuntimeException('SMTP respondió "' . trim($response) . '" a ' . $context);
        }
    }

    /** @return array{0: array<string, string>, 1: string} */
    private static function buildMime(string $text, string $html): array
    {
        $boundary = 'trevix_' . bin2hex(random_bytes(12));
        $headers = [
            'MIME-Version' => '1.0',
            'Content-Type' => 'multipart/alternative; boundary="' . $boundary . '"',
        ];
        $body = '--' . $boundary . "\r\n"
            . "Content-Type: text/plain; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            . chunk_split(base64_encode($text)) . "\r\n"
            . '--' . $boundary . "\r\n"
            . "Content-Type: text/html; charset=UTF-8\r\nContent-Transfer-Encoding: base64\r\n\r\n"
            . chunk_split(base64_encode($html)) . "\r\n"
            . '--' . $boundary . "--\r\n";
        return [$headers, $body];
    }

    private static function writeLog(string $to, string $subject, string $text): void
    {
        $entry = '[' . date('Y-m-d H:i:s') . "] Para: {$to}\nAsunto: {$subject}\n\n{$text}\n" . str_repeat('-', 60) . "\n";
        if (file_put_contents(BASE_PATH . '/storage/logs/mail.log', $entry, FILE_APPEND | LOCK_EX) === false) {
            throw new RuntimeException('No se pudo escribir storage/logs/mail.log');
        }
    }

    private static function fromAddress(): string
    {
        $from = (string) Config::get('app.mail.from_address', '');
        if (!filter_var($from, FILTER_VALIDATE_EMAIL)) {
            throw new RuntimeException('Remitente de correo no válido: ' . $from);
        }
        return $from;
    }

    private static function fromHeader(): string
    {
        $name = (string) Config::get('app.mail.from_name', 'TREVIX');
        return self::encodeHeader($name) . ' <' . self::fromAddress() . '>';
    }

    private static function encodeHeader(string $value): string
    {
        return preg_match('/[^\x20-\x7E]/', $value) ? '=?UTF-8?B?' . base64_encode($value) . '?=' : $value;
    }
}
