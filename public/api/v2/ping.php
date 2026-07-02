<?php
/**
 * Gullify API v2 - Ping (no auth)
 * GET /api/v2/ping.php → {server, apiVersion}
 */
require_once __DIR__ . '/_v2.php';

v2_ok([
    'server'     => 'Gullify',
    'apiVersion' => 'v2',
]);
