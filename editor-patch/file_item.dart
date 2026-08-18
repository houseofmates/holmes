import 'package:webdav_client/webdav_client.dart' as dav;

// simple model for unified file representation
// all code comments are entirely in lowercase

/// file type categories for media handling
enum FileType { image, video, audio, document, archive, folder, other }

class FileItem {
  final String name;
  final String path;
  final int size;
  final DateTime lastModified;
  final bool isDirectory;
  final bool isRemote;
  final FileType type;

  FileItem({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
    required this.isDirectory,
    required this.isRemote,
    required this.type,
  });

  /// create file item from webdav file response
  factory FileItem.fromWebDav(dav.File file) {
    return FileItem(
      name: file.name ?? '',
      path: file.path ?? '',
      size: file.size ?? 0,
      lastModified: file.mTime ?? DateTime.now(),
      isDirectory: file.isDir ?? false,
      isRemote: true,
      type: file.isDir == true ? FileType.folder : determineFileType(file.name ?? ''),
    );
  }

  /// get file extension without dot
  String get extension {
    final dotIndex = name.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == name.length - 1) return '';
    return name.substring(dotIndex + 1).toLowerCase();
  }

  /// check if file is a media type (can be edited)
  bool get isMedia => type == FileType.image || type == FileType.video || type == FileType.audio;

  /// check if file is an image type
  bool get isImage => type == FileType.image;

  /// check if file is a video type
  bool get isVideo => type == FileType.video;

  /// check if file is an audio type
  bool get isAudio => type == FileType.audio;

  /// format file size for display
  String get formattedSize {
    if (isDirectory) return '--';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// format last modified for display
  String get formattedDate {
    final now = DateTime.now();
    final diff = now.difference(lastModified);

    if (diff.inDays == 0) {
      if (diff.inHours == 0) {
        return '${diff.inMinutes}m ago';
      }
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    } else if (diff.inDays < 365) {
      return '${lastModified.month}/${lastModified.day}';
    }
    return '${lastModified.year}/${lastModified.month}/${lastModified.day}';
  }

  /// comprehensive file type detection based on extension
  static FileType determineFileType(String name) {
    final lowerName = name.toLowerCase();
    final ext = lowerName.contains('.') ? lowerName.split('.').last : '';

    // image formats
    const imageExtensions = {
      'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg', 'ico', 'tiff', 'tif',
      'heic', 'heif', 'avif', 'raw', 'cr2', 'nef', 'arw', 'dng', 'psd', 'xcf',
    };
    if (imageExtensions.contains(ext)) return FileType.image;

    // video formats
    const videoExtensions = {
      'mp4', 'mov', 'avi', 'mkv', 'webm', 'flv', 'wmv', 'm4v', 'mpeg', 'mpg',
      '3gp', '3g2', 'ogv', 'ts', 'mts', 'm2ts', 'vob', 'divx', 'xvid',
    };
    if (videoExtensions.contains(ext)) return FileType.video;

    // audio formats
    const audioExtensions = {
      'mp3', 'wav', 'm4a', 'flac', 'ogg', 'aac', 'wma', 'aiff', 'aif', 'opus',
      'ape', 'alac', 'mid', 'midi', 'pcm', 'dsd', 'dsf', 'dff', 'mka',
    };
    if (audioExtensions.contains(ext)) return FileType.audio;

    // document formats
    const documentExtensions = {
      'pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'odt', 'ods', 'odp',
      'txt', 'rtf', 'csv', 'md', 'html', 'htm', 'xml', 'json', 'yaml', 'yml',
    };
    if (documentExtensions.contains(ext)) return FileType.document;

    // archive formats
    const archiveExtensions = {
      'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'lz', 'lzma', 'iso', 'dmg',
    };
    if (archiveExtensions.contains(ext)) return FileType.archive;

    return FileType.other;
  }

  /// get mime type for file
  String? get mimeType {
    switch (type) {
      case FileType.image:
        switch (extension) {
          case 'jpg':
          case 'jpeg':
            return 'image/jpeg';
          case 'png':
            return 'image/png';
          case 'gif':
            return 'image/gif';
          case 'webp':
            return 'image/webp';
          case 'svg':
            return 'image/svg+xml';
          case 'bmp':
            return 'image/bmp';
          default:
            return 'image/*';
        }
      case FileType.video:
        switch (extension) {
          case 'mp4':
            return 'video/mp4';
          case 'webm':
            return 'video/webm';
          case 'mov':
            return 'video/quicktime';
          case 'avi':
            return 'video/x-msvideo';
          case 'mkv':
            return 'video/x-matroska';
          default:
            return 'video/*';
        }
      case FileType.audio:
        switch (extension) {
          case 'mp3':
            return 'audio/mpeg';
          case 'wav':
            return 'audio/wav';
          case 'ogg':
            return 'audio/ogg';
          case 'flac':
            return 'audio/flac';
          case 'm4a':
            return 'audio/m4a';
          case 'aac':
            return 'audio/aac';
          default:
            return 'audio/*';
        }
      case FileType.document:
        switch (extension) {
          case 'pdf':
            return 'application/pdf';
          case 'txt':
            return 'text/plain';
          case 'html':
          case 'htm':
            return 'text/html';
          case 'json':
            return 'application/json';
          default:
            return 'application/octet-stream';
        }
      case FileType.archive:
        switch (extension) {
          case 'zip':
            return 'application/zip';
          case 'rar':
            return 'application/vnd.rar';
          case '7z':
            return 'application/x-7z-compressed';
          case 'tar':
            return 'application/x-tar';
          case 'gz':
            return 'application/gzip';
          default:
            return 'application/octet-stream';
        }
      case FileType.folder:
        return null;
      case FileType.other:
        return 'application/octet-stream';
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is FileItem && other.path == path && other.isRemote == isRemote;
  }

  @override
  int get hashCode => path.hashCode ^ isRemote.hashCode;

  @override
  String toString() => 'FileItem(name: $name, path: $path, type: $type, isRemote: $isRemote)';

  /// create a copy with optional overrides
  FileItem copyWith({
    String? name,
    String? path,
    int? size,
    DateTime? lastModified,
    bool? isDirectory,
    bool? isRemote,
    FileType? type,
  }) {
    return FileItem(
      name: name ?? this.name,
      path: path ?? this.path,
      size: size ?? this.size,
      lastModified: lastModified ?? this.lastModified,
      isDirectory: isDirectory ?? this.isDirectory,
      isRemote: isRemote ?? this.isRemote,
      type: type ?? this.type,
    );
  }
}
