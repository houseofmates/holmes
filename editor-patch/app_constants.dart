// app-wide constants for consistent values
// eliminates magic numbers and duplicated strings
// all code comments are entirely in lowercase

/// layout constants
class LayoutConstants {
  LayoutConstants._();

  /// breakpoint for switching between mobile and desktop layout
  static const double wideScreenBreakpoint = 900.0;

  /// standard padding values
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  /// standard border radius
  static const double borderRadiusSmall = 4.0;
  static const double borderRadiusMedium = 8.0;
  static const double borderRadiusLarge = 12.0;
  static const double borderRadiusXLarge = 16.0;

  /// icon sizes
  static const double iconSizeSmall = 16.0;
  static const double iconSizeMedium = 24.0;
  static const double iconSizeLarge = 32.0;
  static const double iconSizeXLarge = 48.0;
  static const double iconSizeHero = 64.0;

  /// button heights
  static const double buttonHeightSmall = 32.0;
  static const double buttonHeightMedium = 44.0;
  static const double buttonHeightLarge = 56.0;

  /// thumbnail sizes
  static const double thumbnailSizeSmall = 48.0;
  static const double thumbnailSizeMedium = 80.0;
  static const double thumbnailSizeLarge = 120.0;
}

/// video processing constants
class VideoConstants {
  VideoConstants._();

  /// quality presets (height in pixels, crf value)
  static const int quality480pHeight = 480;
  static const int quality720pHeight = 720;
  static const int quality1080pHeight = 1080;
  static const int quality4kHeight = 2160;

  static const int crfLow = 28; // lower quality, smaller file
  static const int crfMedium = 23;
  static const int crfHigh = 18;
  static const int crfLossless = 0;

  /// speed limits
  static const double minSpeed = 0.1;
  static const double maxSpeed = 10.0;

  /// audio tempo limits (atempo filter)
  static const double minTempo = 0.5;
  static const double maxTempo = 2.0;

  /// default audio sample rate
  static const int defaultSampleRate = 44100;

  /// text overlay defaults
  static const int defaultTextFontSize = 48;
  static const String defaultTextColor = 'white';
  static const String defaultTextBorderColor = 'black';
  static const int defaultTextBorderWidth = 2;
}

/// image processing constants
class ImageConstants {
  ImageConstants._();

  /// quality values (0-100)
  static const int qualityLow = 60;
  static const int qualityMedium = 80;
  static const int qualityHigh = 95;
  static const int qualityLossless = 100;

  /// jpeg quality mapping (for ffmpeg -q:v)
  static const int jpegQualityBest = 2;
  static const int jpegQualityWorst = 31;

  /// common resize dimensions
  static const int thumbnailWidth = 320;
  static const int thumbnailHeight = 180;
  static const int previewMaxWidth = 800;
  static const int hdWidth = 1920;
  static const int hdHeight = 1080;

  /// sharpness limits
  static const double minSharpness = 0.0;
  static const double maxSharpness = 3.0;
}

/// color grading constants
class ColorGradingConstants {
  ColorGradingConstants._();

  /// slider ranges
  static const double minTemperature = -100.0;
  static const double maxTemperature = 100.0;
  static const double minTint = -100.0;
  static const double maxTint = 100.0;
  static const double minBrightness = -100.0;
  static const double maxBrightness = 100.0;
  static const double minContrast = -100.0;
  static const double maxContrast = 100.0;
  static const double minSaturation = -100.0;
  static const double maxSaturation = 100.0;
  static const double minVibrance = -100.0;
  static const double maxVibrance = 100.0;
  static const double minSharpness = 0.0;
  static const double maxSharpness = 100.0;

  /// hue slider range (degrees)
  static const double minHue = -180.0;
  static const double maxHue = 180.0;
}

/// cache constants
class CacheConstants {
  CacheConstants._();

  /// ttl durations in hours
  static const int previewTtlHours = 1;
  static const int historyTtlHours = 12;
  static const int defaultTtlHours = 24;
  static const int exportTtlHours = 48;

  /// max cache size in bytes (500mb)
  static const int maxCacheSizeBytes = 500 * 1024 * 1024;

  /// max history entries per file
  static const int maxHistoryPerFile = 20;
}

/// file size display thresholds
class FileSizeConstants {
  FileSizeConstants._();

  static const int kb = 1024;
  static const int mb = 1024 * 1024;
  static const int gb = 1024 * 1024 * 1024;
}

/// animation durations
class AnimationConstants {
  AnimationConstants._();

  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration loading = Duration(seconds: 2);
}

/// debounce delays
class DebounceConstants {
  DebounceConstants._();

  static const Duration search = Duration(milliseconds: 300);
  static const Duration slider = Duration(milliseconds: 100);
  static const Duration preview = Duration(milliseconds: 300);
}

/// navigation indices for main shell
class NavIndex {
  NavIndex._();

  static const int files = 0;
  static const int image = 1;
  static const int video = 2;
  static const int audio = 3;
  static const int compose = 4;
  static const int settings = 5;
}

/// supported file extensions
class FileExtensions {
  FileExtensions._();

  static const List<String> image = [
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'ico', 'tiff', 'tif',
    'heic', 'heif', 'avif', 'raw', 'cr2', 'nef', 'arw', 'dng', 'psd', 'xcf',
  ];

  static const List<String> video = [
    'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv', 'm4v', 'mpeg', 'mpg',
    '3gp', '3g2', 'ogv', 'ts', 'mts', 'm2ts', 'vob', 'divx', 'xvid',
  ];

  static const List<String> audio = [
    'mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac', 'wma', 'aiff', 'aif', 'opus',
    'ape', 'alac', 'mid', 'midi', 'pcm', 'dsd', 'dsf', 'dff', 'mka',
  ];

  static const List<String> document = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
    'txt', 'rtf', 'csv', 'md', 'html', 'htm', 'xml', 'json', 'yaml', 'yml',
  ];

  static const List<String> archive = [
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'lz', 'lzma', 'iso', 'dmg',
  ];
}

/// overlay position defaults
class OverlayDefaults {
  OverlayDefaults._();

  static const int x = 10;
  static const int y = 10;
  static const double opacity = 1.0;
}
