<?php
/**
 * HolmeSviewer / lib / Utils / HolmesParser
 *
 * pure-PHP holmes binary parser — no external extensions required.
 * reads the holmes header and exposes mime-type + payload info.
 */

namespace OCA\HolmeSviewer\Utils;

class HolmesParser {
  private string $path;
  private ?int  $payloadStart = null;
  private ?int  $payloadSize  = null;
  private ?string $mimeType   = null;

  private const MAGIC = 'HOLMES';
  private const VERSION = 1;

  public function __construct(string $path) {
    if (!is_file($path) || !is_readable($path)) {
      throw new \UnexpectedValueException("cannot read: $path");
    }
    $this->path = $path;
  }

  public function parseHeader(): void {
    if (($fh = @fopen($this->path, 'rb')) === false) {
      throw new \UnexpectedValueException("unable to open: {$this->path}");
    }

    // ── magic ────────────────────────────────────────────────────
    $magic = fread($fh, 6);
    if ($magic !== self::MAGIC) {
      fclose($fh);
      throw new \UnexpectedValueException(
        sprintf('bad magic bytes: %s', bin2hex($magic))
      );
    }

    // ── version ──────────────────────────────────────────────────
    $vRaw = fread($fh, 2);
    if (strlen($vRaw) < 2) { fclose($fh); throw new \UnexpectedValueException('truncated: version'); }
    [$ver]      = array_values(unpack('n', $vRaw));
    if ($ver !== self::VERSION) {
      fclose($fh);
      throw new \UnexpectedValueException("unsupported version: $ver (expected " . self::VERSION . ")");
    }

    // ── mime length ──────────────────────────────────────────────
    $mlRaw = fread($fh, 2);
    if (strlen($mlRaw) < 2) { fclose($fh); throw new \UnexpectedValueException('truncated: mime_len'); }
    [$mimeLen] = array_values(unpack('n', $mlRaw));
    if ($mimeLen < 1 || $mimeLen > 255) {
      fclose($fh);
      throw new \UnexpectedValueException("invalid mime_len: $mimeLen");
    }

    // ── mime string ──────────────────────────────────────────────
    $mime = fread($fh, $mimeLen);
    if (strlen($mime) < $mimeLen) { fclose($fh); throw new \UnexpectedValueException('truncated: mime'); }
    $this->mimeType = (string)$mime;

    // ── payload length (uint64be) ────────────────────────────────
    // PHP lacks a native u64be pack, so read first 4 bytes and then the
    // remaining 4 — treat as 2× u32; payloads >2 TiB are rejected.
    $plenRaw = fread($fh, 8);
    if (strlen($plenRaw) < 8) { fclose($fh); throw new \UnexpectedValueException('truncated: payload_len'); }
    [$hi, $lo] = array_values(unpack('N2', $plenRaw));
    $u64 = (int)(($hi << 32) | $lo);
    if ($u64 < 0) { fclose($fh); throw new \UnexpectedValueException('negative payload length'); }
    $this->payloadSize  = (int)$u64;
    $this->payloadStart = ftell($fh);   // = filePos after header
    fclose($fh);
  }

  public function getMimeType(): string {
    if ($this->mimeType === null)  $this->parseHeader();
    return $this->mimeType;
  }

  public function getPayloadSize(): int {
    if ($this->payloadSize === null) $this->parseHeader();
    return $this->payloadSize;
  }

  public function getPayloadOffset(): int {
    if ($this->payloadStart === null) $this->parseHeader();
    return $this->payloadStart;
  }
}
