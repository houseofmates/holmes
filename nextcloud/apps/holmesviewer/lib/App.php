<?php
/**
 * HolmeSviewer — app bootstrap
 *
 * registers the .holmes / application/x-holmes MIME type so
 * Nextcloud does not try to render it as plain text.
 * MIME re-registration is idempotent and safe to call each boot.
 */

namespace OCA\HolmeSviewer;

use OCP\AppFramework\App;
use OCP\AppFramework\Bootstrap\IBootstrap;
use OCP\AppFramework\IAppContainer;

class App extends App implements IBootstrap {
  public function __construct(array $urlParams = []) {
    parent::__construct('holmesviewer', $urlParams);
  }

  public function registerContainerRules(IAppContainer $container): void {}

  public function boot(): void {
    // ── register .holmes MIME type ───────────────────────────────────
    // uses the mapper that works across Nextcloud 25–29
    try {
      \OC::$server->getMimeTypeDetector()
        ->register('application/x-holmes', 'holmes');
    } catch (\Throwable $_e) {
      // if that API route is not available we still work;
      // the route controller applies the correct Content-Type header
      // at response time regardless of what Nextcloud thinks the MIME is.
    }

    try {
      \OCP\Util::addActionStyle('holmesviewer', 'style');
    } catch (\Throwable $_e) {}
  }
}
