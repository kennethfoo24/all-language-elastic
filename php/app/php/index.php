<?php
$log = require __DIR__ . '/bootstrap.php';

$start  = microtime(true);
$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$path   = $_SERVER['REQUEST_URI'] ?? '/php';

$log->info('request received', ['method' => $method, 'path' => $path]);

header('Content-Type: application/json');

$body = [
    'service'   => 'php',
    'message'   => 'Hello from php',
    'status'    => 'ok',
    'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
    'upstream'  => null,
];
echo json_encode($body, JSON_UNESCAPED_SLASHES);

$log->info('request completed', [
    'method'      => $method,
    'path'        => $path,
    'status_code' => 200,
    'duration_ms' => (int) round((microtime(true) - $start) * 1000),
]);
