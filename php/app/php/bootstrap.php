<?php
// Shared logger bootstrap. Returns a Monolog logger that emits the standardized
// JSON schema: timestamp, level, service, message + any context fields.
require __DIR__ . '/../vendor/autoload.php';

use Monolog\Logger;
use Monolog\Level;
use Monolog\Handler\StreamHandler;
use Monolog\Formatter\FormatterInterface;
use Monolog\LogRecord;

$formatter = new class implements FormatterInterface {
    public function format(LogRecord $record): string
    {
        $out = [
            'timestamp' => $record->datetime->setTimezone(new \DateTimeZone('UTC'))->format('Y-m-d\TH:i:s.v\Z'),
            'level'     => strtolower($record->level->getName()),
            'service'   => 'php',
            'message'   => $record->message,
        ];
        foreach ($record->context as $key => $value) {
            $out[$key] = $value;
        }
        return json_encode($out, JSON_UNESCAPED_SLASHES) . "\n";
    }

    public function formatBatch(array $records): string
    {
        return implode('', array_map([$this, 'format'], $records));
    }
};

// Apache surfaces stderr in container logs; use it so `docker logs` captures output.
$handler = new StreamHandler('php://stderr', Level::Info);
$handler->setFormatter($formatter);

$log = new Logger('php');
$log->pushHandler($handler);

return $log;
