<?php
/**
 * HolmeSviewer / lib / Controller / ViewController
 *
 * GET apps/holmesviewer/view/{fileId}
 *
 * Streams the inner media payload of a .holmes file that belongs to
 * the currently-authenticated Nextcloud user.
 *
 * supported query params:
 *   ?range=bytes=START-END   RFC 7233 partial content
 *
 * note for the package builder:
 *   this controller is intentionally self-contained to avoid Nextcloud
 *   version drift between appinfo/ routing and AppFramework internals.
 */

namespace OCA\HolmeSviewer\Controller;

use OCA\HolmeSviewer\Utils\HolmesParser;
use OCP\AppFramework\Controller;
use OCP\IRequest;
use OCP\AppFramework\Http;
use OCP\AppFramework\Http\Response;

class ViewController extends Controller {
  public function __construct(IRequest $request) {
    parent::__construct('holmesviewer', $request);
  }

  /**
   * GET /apps/holmesviewer/view/{fileId}
   *
   * @param int $fileId  filecache fileid
   */
  public function get(int $fileId): Response {
    // ── 1. look up the file ──────────────────────────────────────
    /** @noinspection PhpUndefinedMethodInspection */
    $qb = \OCP\DB::getQueryBuilder();
    $qb
      ->select(['filecache.path', 'filecache.size', 'filecache.name'])
      ->from('filecache')
      ->where(
        $qb->expr()->eq(
          'filecache.fileid',
          $qb->createNamedParameter($fileId, \PDO::PARAM_INT)
        )
      )
      ->andWhere($qb->expr()->gt('filecache.size', $qb->createNamedParameter(0, \PDO::PARAM_INT)))
      ->setMaxResults(1);

    /** @noinspection PhpParamsInspection */
    $row = $qb->executeQuery()->fetch(\PDO::FETCH_ASSOC);
    if (!$row) {
      abort(404, json_encode(['error' => 'file not found']));
    }

    $config  = \OC::$server->getConfig();
    $datadir = rtrim($config->getSystemValue('datadirectory', '/tmp'), '/');
    // file stores are mounted under data/<user>/files/  — filecache.path stores the path
    // relative to the storage mount, e.g. "/username/files/some/path/to/file.holmes"
    // Nextcloud's filepath helper:
    $storageId = \OC::$server->getUserFolder('')->getStorage()->getNumericStorageId();
    // start from user home: /files/<relative path stored in filecache.path>
    $entryPath = $row['path'];                       // e.g. "/myuser/files/music/song.holmes"
    $userHome  = \OC::$server->getUserFolder('')->getPath(); // "/files"
    // strip user home prefix — but actually in filecache the path is already relative to that.

    // simpler approach: use the file cache directly
    // filecache stores: path = /<user>/files/<relative>
    // filecache stores relative paths as /files/<relpath.png>
    // data dir layout is: <datadir>/<uid>/files/<relpath>
    $uid     = \OCP\User::getUser();
    $datadir = rtrim(\OC::$server->getConfig()->getSystemValue('datadirectory', '/tmp'), '/');
    $rel     = preg_replace('#^/[^/]+/files/#', '', $row['path']);
    $localPath = $datadir . '/' . $uid . '/files/' . $rel;

    if (!is_file($localPath) || !is_readable($localPath)) {
      abort(404, json_encode(['error' => 'file not accessible on this server']));
    }

    // ── 2. parse holmes header ───────────────────────────────────
    try {
      $h = new HolmesParser($localPath);
      $h->parseHeader();
    } catch (\Throwable $e) {
      abort(400, json_encode(['error' => 'invalid holmes: ' . $e->getMessage()]));
    }

    $mime    = $h->getMimeType() ?: 'application/octet-stream';
    $pLen    = (int) $h->getPayloadSize();
    $pOffset = (int) $h->getPayloadOffset();
    $fname   = basename($row['path']);

    // transparent 206 support
    $range = $_SERVER['HTTP_RANGE'] ?? $_SERVER['Range'] ?? null;

    header('Content-Type: ' . $mime);
    header('Accept-Ranges: bytes');

    if ($range !== null) {
      header('Cache-Control: public, max-age=3600');
      if (preg_match('/bytes=(\d+)-(\d*)/', $range, $rm)) {
        $start = (int)$rm[1];
        $end   = $rm[2] !== '' ? (int)$rm[2] : $pLen - 1;
        if ($start >= $pLen) {
          header('Content-Range: bytes */' . $pLen, true, 416);
          exit;
        }
        $end    = min($end, $pLen - 1);
        $length = $end - $start + 1;
        header('Content-Range: bytes ' . $start . '-' . $end . '/' . $pLen);
        header('Content-Length: ' . $length);
        http_response_code(206);

        $fh = @fopen($localPath, 'rb');
        if ($fh) {
          fseek($fh, $pOffset + $start);
          spool($fh, $length, 131072);
          fclose($fh);
        }
        exit;
      }
    }

    header('Content-Length: ' . $pLen);
    http_response_code(200);

    $fh = @fopen($localPath, 'rb');
    if ($fh) {
      fseek($fh, $pOffset);
      spool($fh, $pLen, 131072);
      fclose($fh);
    }
    exit;
  }
}

/**
 * spool up to $limit bytes from $fh in $step-sized chunks to stdout,
 * calling flush() every step so the browser receives data progressively.
 */
function spool($fh, int $limit, int $step): void {
  $remaining = $limit;
  while ($remaining > 0 && !feof($fh)) {
    $read = ($remaining > $step) ? $step : $remaining;
    echo fread($fh, $read);
    $remaining -= $read;
    flush();
  }
}
