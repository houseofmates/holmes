<?php
declare(strict_types=1);

/**
 * HolmeSviewer — routes
 *
 * GET /apps/holmesviewer/view/{fileId}
 *   Streams the inner media payload of a .holmes file.
 */

return static function (\OCP\AppFramework\App $app, \OCP\AppFramework\IAppContainer $container): void {
    $app->registerRoutes('holmesviewer', [
        ['name' => 'view#get', 'url' => '/view/{fileId}', 'verb' => 'GET', 'requirements' => ['fileId' => '\d+']],
    ]);
};