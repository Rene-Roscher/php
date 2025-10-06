<?php
// Simple Test Page für PHP-FPM/Nginx Socket Test

header('Content-Type: text/html; charset=utf-8');
?>
<!DOCTYPE html>
<html>
<head>
    <title>PHP Docker Test</title>
    <style>
        body { font-family: sans-serif; max-width: 1200px; margin: 50px auto; padding: 20px; }
        .success { color: #28a745; font-weight: bold; }
        .info { background: #f8f9fa; padding: 15px; border-left: 4px solid #007bff; margin: 10px 0; }
        table { border-collapse: collapse; width: 100%; margin: 20px 0; }
        th, td { padding: 10px; text-align: left; border: 1px solid #ddd; }
        th { background: #007bff; color: white; }
        .metric { font-size: 24px; font-weight: bold; }
    </style>
</head>
<body>
    <h1>🚀 Laravel PHP Docker - Test Page</h1>

    <div class="info">
        <p class="success">✅ PHP-FPM und Nginx kommunizieren erfolgreich!</p>
    </div>

    <h2>📊 System Information</h2>
    <table>
        <tr>
            <th>Property</th>
            <th>Value</th>
        </tr>
        <tr>
            <td>PHP Version</td>
            <td class="metric"><?php echo PHP_VERSION; ?></td>
        </tr>
        <tr>
            <td>Server API</td>
            <td><?php echo php_sapi_name(); ?></td>
        </tr>
        <tr>
            <td>Memory Limit</td>
            <td><?php echo ini_get('memory_limit'); ?></td>
        </tr>
        <tr>
            <td>Max Execution Time</td>
            <td><?php echo ini_get('max_execution_time'); ?>s</td>
        </tr>
        <tr>
            <td>Upload Max Filesize</td>
            <td><?php echo ini_get('upload_max_filesize'); ?></td>
        </tr>
        <tr>
            <td>Post Max Size</td>
            <td><?php echo ini_get('post_max_size'); ?></td>
        </tr>
    </table>

    <h2>⚡ OPcache Status</h2>
    <?php if (function_exists('opcache_get_status')): ?>
        <?php $opcache = opcache_get_status(); ?>
        <table>
            <tr>
                <th>Metric</th>
                <th>Value</th>
            </tr>
            <tr>
                <td>OPcache Enabled</td>
                <td class="success"><?php echo $opcache['opcache_enabled'] ? '✅ YES' : '❌ NO'; ?></td>
            </tr>
            <tr>
                <td>Cache Full</td>
                <td><?php echo $opcache['cache_full'] ? '⚠️ YES' : '✅ NO'; ?></td>
            </tr>
            <tr>
                <td>Memory Usage</td>
                <td><?php echo round($opcache['memory_usage']['used_memory'] / 1024 / 1024, 2); ?> MB /
                    <?php echo round(($opcache['memory_usage']['used_memory'] + $opcache['memory_usage']['free_memory']) / 1024 / 1024, 2); ?> MB</td>
            </tr>
            <tr>
                <td>Cached Scripts</td>
                <td><?php echo $opcache['opcache_statistics']['num_cached_scripts']; ?></td>
            </tr>
            <tr>
                <td>Hits</td>
                <td><?php echo number_format($opcache['opcache_statistics']['hits']); ?></td>
            </tr>
            <tr>
                <td>Misses</td>
                <td><?php echo number_format($opcache['opcache_statistics']['misses']); ?></td>
            </tr>
            <tr>
                <td>Hit Rate</td>
                <td class="metric"><?php echo round($opcache['opcache_statistics']['opcache_hit_rate'], 2); ?>%</td>
            </tr>
            <?php if (isset($opcache['jit'])): ?>
            <tr>
                <td>JIT Enabled</td>
                <td class="success">✅ YES</td>
            </tr>
            <tr>
                <td>JIT Buffer Size</td>
                <td><?php echo round($opcache['jit']['buffer_size'] / 1024 / 1024, 2); ?> MB</td>
            </tr>
            <tr>
                <td>JIT Buffer Free</td>
                <td><?php echo round($opcache['jit']['buffer_free'] / 1024 / 1024, 2); ?> MB</td>
            </tr>
            <?php endif; ?>
        </table>
    <?php else: ?>
        <p class="info">⚠️ OPcache is not available or not enabled</p>
    <?php endif; ?>

    <h2>🔧 Installed Extensions</h2>
    <div class="info">
        <?php
        $extensions = get_loaded_extensions();
        sort($extensions);
        echo implode(', ', $extensions);
        ?>
    </div>

    <h2>🔗 Quick Links</h2>
    <ul>
        <li><a href="/phpinfo.php">📝 Full PHP Info</a></li>
        <li><a href="/ping">🏓 PHP-FPM Ping (should return "pong")</a></li>
        <li><a href="/status?full">📊 PHP-FPM Status (localhost only)</a></li>
    </ul>

    <hr>
    <p style="color: #999; font-size: 12px;">
        Generated at: <?php echo date('Y-m-d H:i:s'); ?> |
        Server: <?php echo $_SERVER['SERVER_SOFTWARE'] ?? 'Unknown'; ?> |
        Request Time: <?php echo round((microtime(true) - $_SERVER['REQUEST_TIME_FLOAT']) * 1000, 2); ?>ms
    </p>
</body>
</html>
