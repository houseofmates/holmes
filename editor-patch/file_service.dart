import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:mime/mime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_item.dart';

// local file service for device storage with comprehensive error handling
// all code comments are entirely in lowercase

/// sealed result type for file operations
sealed class FileOperationResult {
  const FileOperationResult();
}

class FileOperationSuccess extends FileOperationResult {
  final String? path;
  final String? message;
  const FileOperationSuccess({this.path, this.message});
}

class FileOperationFailure extends FileOperationResult {
  final String message;
  final FileOperationError error;
  const FileOperationFailure(this.message, this.error);
}

/// file operation error types
enum FileOperationError {
  permissionDenied,
  notFound,
  alreadyExists,
  diskFull,
  invalidPath,
  ioError,
  unknown,
}

final fileServiceProvider = Provider((ref) => FileService());

class FileService {
  /// list local files in a directory with improved error handling
  Future<List<FileItem>> listLocalFiles(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        debugPrint('directory does not exist: $path');
        return [];
      }

      final entities = <FileSystemEntity>[];
      await for (final entity in dir.list()) {
        entities.add(entity);
      }

      // sort: directories first, then by name
      entities.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      final items = <FileItem>[];
      for (final entity in entities) {
        try {
          final stats = await entity.stat();
          final name = p.basename(entity.path);

          // skip hidden files on linux
          if (Platform.isLinux && name.startsWith('.')) continue;

          items.add(FileItem(
            name: name,
            path: entity.path,
            size: stats.size,
            lastModified: stats.modified,
            isDirectory: entity is Directory,
            isRemote: false,
            type: entity is Directory ? FileType.folder : FileItem.determineFileType(name),
          ));
        } catch (e) {
          // skip files we can't access
          debugPrint('skipping inaccessible file: ${entity.path}');
        }
      }

      return items;
    } on FileSystemException catch (e) {
      debugPrint('filesystem error listing files: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('error listing files: $e');
      return [];
    }
  }

  /// get standard root path for file browsing
  Future<String> getRootPath() async {
    if (Platform.isLinux) {
      return Platform.environment['HOME'] ?? '/';
    } else if (Platform.isAndroid) {
      // check if we have storage permissions first
      final status = await Permission.manageExternalStorage.status;
      if (status.isGranted) {
        return '/storage/emulated/0';
      }
      // fallback to app-specific directory
      final dir = await getExternalStorageDirectory();
      return dir?.path ?? '/storage/emulated/0';
    } else {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    }
  }

  /// get common media directories
  Future<Map<String, String>> getMediaDirectories() async {
    final Map<String, String> dirs = {};

    if (Platform.isAndroid) {
      final base = '/storage/emulated/0';
      dirs['downloads'] = '$base/Download';
      dirs['pictures'] = '$base/Pictures';
      dirs['videos'] = '$base/Movies';
      dirs['music'] = '$base/Music';
      dirs['dcim'] = '$base/DCIM';
    } else if (Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '/';
      dirs['downloads'] = '$home/Downloads';
      dirs['pictures'] = '$home/Pictures';
      dirs['videos'] = '$home/Videos';
      dirs['music'] = '$home/Music';
      dirs['documents'] = '$home/Documents';
    }

    // filter out non-existent directories
    final existing = <String, String>{};
    for (final entry in dirs.entries) {
      if (await Directory(entry.value).exists()) {
        existing[entry.key] = entry.value;
      }
    }

    return existing;
  }

  /// add a file from external path to a destination directory
  Future<FileOperationResult> addFile(String sourcePath, String destDirPath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return const FileOperationFailure(
          'source file does not exist',
          FileOperationError.notFound,
        );
      }

      final destDir = Directory(destDirPath);
      if (!await destDir.exists()) {
        return const FileOperationFailure(
          'destination directory does not exist',
          FileOperationError.notFound,
        );
      }

      final fileName = p.basename(sourcePath);
      final destPath = p.join(destDirPath, fileName);

      // check if destination already exists
      if (await File(destPath).exists()) {
        // generate unique name
        final baseName = p.basenameWithoutExtension(fileName);
        final ext = p.extension(fileName);
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final uniqueName = '${baseName}_$timestamp$ext';
        final uniqueDestPath = p.join(destDirPath, uniqueName);
        await sourceFile.copy(uniqueDestPath);
        return FileOperationSuccess(path: uniqueDestPath, message: 'file copied with new name');
      }

      await sourceFile.copy(destPath);
      return FileOperationSuccess(path: destPath, message: 'file copied successfully');
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 28) {
        return const FileOperationFailure('disk is full', FileOperationError.diskFull);
      }
      if (e.osError?.errorCode == 13) {
        return const FileOperationFailure('permission denied', FileOperationError.permissionDenied);
      }
      return FileOperationFailure('file system error: ${e.message}', FileOperationError.ioError);
    } catch (e) {
      return FileOperationFailure('failed to copy file: $e', FileOperationError.unknown);
    }
  }

  /// move a file to a new location
  Future<FileOperationResult> moveFile(String sourcePath, String destPath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return const FileOperationFailure('source file does not exist', FileOperationError.notFound);
      }

      // try rename first (faster, same filesystem)
      try {
        await sourceFile.rename(destPath);
        return FileOperationSuccess(path: destPath, message: 'file moved successfully');
      } on FileSystemException {
        // cross-filesystem move, fall back to copy + delete
        await sourceFile.copy(destPath);
        await sourceFile.delete();
        return FileOperationSuccess(path: destPath, message: 'file moved successfully');
      }
    } on FileSystemException catch (e) {
      return FileOperationFailure('file system error: ${e.message}', FileOperationError.ioError);
    } catch (e) {
      return FileOperationFailure('failed to move file: $e', FileOperationError.unknown);
    }
  }

  /// delete a local file or directory
  Future<FileOperationResult> deleteFile(String path) async {
    try {
      final type = await FileSystemEntity.type(path);

      if (type == FileSystemEntityType.notFound) {
        return const FileOperationFailure('file not found', FileOperationError.notFound);
      }

      if (type == FileSystemEntityType.file) {
        await File(path).delete();
        return const FileOperationSuccess(message: 'file deleted');
      } else if (type == FileSystemEntityType.directory) {
        await Directory(path).delete(recursive: true);
        return const FileOperationSuccess(message: 'directory deleted');
      }

      return const FileOperationFailure('unknown file type', FileOperationError.unknown);
    } on FileSystemException catch (e) {
      if (e.osError?.errorCode == 13) {
        return const FileOperationFailure('permission denied', FileOperationError.permissionDenied);
      }
      return FileOperationFailure('file system error: ${e.message}', FileOperationError.ioError);
    } catch (e) {
      return FileOperationFailure('failed to delete: $e', FileOperationError.unknown);
    }
  }

  /// create a new directory
  Future<FileOperationResult> createDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (await dir.exists()) {
        return const FileOperationFailure('directory already exists', FileOperationError.alreadyExists);
      }

      await dir.create(recursive: true);
      return FileOperationSuccess(path: path, message: 'directory created');
    } on FileSystemException catch (e) {
      return FileOperationFailure('file system error: ${e.message}', FileOperationError.ioError);
    } catch (e) {
      return FileOperationFailure('failed to create directory: $e', FileOperationError.unknown);
    }
  }

  /// rename a file or directory
  Future<FileOperationResult> rename(String path, String newName) async {
    try {
      final type = await FileSystemEntity.type(path);

      if (type == FileSystemEntityType.notFound) {
        return const FileOperationFailure('file not found', FileOperationError.notFound);
      }

      final parentDir = p.dirname(path);
      final newPath = p.join(parentDir, newName);

      // check if new name already exists
      if (await FileSystemEntity.type(newPath) != FileSystemEntityType.notFound) {
        return const FileOperationFailure('a file with that name already exists', FileOperationError.alreadyExists);
      }

      if (type == FileSystemEntityType.file) {
        await File(path).rename(newPath);
      } else {
        await Directory(path).rename(newPath);
      }

      return FileOperationSuccess(path: newPath, message: 'renamed successfully');
    } on FileSystemException catch (e) {
      return FileOperationFailure('file system error: ${e.message}', FileOperationError.ioError);
    } catch (e) {
      return FileOperationFailure('failed to rename: $e', FileOperationError.unknown);
    }
  }

  /// get file information
  Future<FileItem?> getFileInfo(String path) async {
    try {
      final type = await FileSystemEntity.type(path);
      if (type == FileSystemEntityType.notFound) return null;

      final stats = await File(path).stat();
      final name = p.basename(path);

      return FileItem(
        name: name,
        path: path,
        size: stats.size,
        lastModified: stats.modified,
        isDirectory: type == FileSystemEntityType.directory,
        isRemote: false,
        type: type == FileSystemEntityType.directory ? FileType.folder : FileItem.determineFileType(name),
      );
    } catch (e) {
      debugPrint('error getting file info: $e');
      return null;
    }
  }

  /// get available disk space in bytes
  Future<int?> getAvailableSpace(String path) async {
    try {
      if (Platform.isLinux) {
        final result = await Process.run('df', ['-B1', path]);
        if (result.exitCode == 0) {
          final lines = (result.stdout as String).split('\n');
          if (lines.length >= 2) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              return int.tryParse(parts[3]);
            }
          }
        }
      }
      // android doesn't have a reliable way to get this without native code
      return null;
    } catch (e) {
      return null;
    }
  }

  /// get file's mime type
  String? getMimeType(String path) {
    return lookupMimeType(path);
  }

  /// check if path is a media file
  bool isMediaFile(String path) {
    final type = FileItem.determineFileType(path);
    return type == FileType.image || type == FileType.video || type == FileType.audio;
  }

  /// request storage permissions (android)
  Future<bool> requestStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    // for android 11+, request manage external storage
    if (await Permission.manageExternalStorage.isGranted) return true;

    final status = await Permission.manageExternalStorage.request();
    if (status.isGranted) return true;

    // fallback to legacy storage permissions
    final readStatus = await Permission.storage.request();
    return readStatus.isGranted;
  }

  /// check if storage permissions are granted
  Future<bool> hasStoragePermissions() async {
    if (!Platform.isAndroid) return true;

    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;

    return false;
  }

  /// copy file to cache directory (for sharing, editing)
  Future<FileOperationResult> copyToCache(String sourcePath) async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final fileName = p.basename(sourcePath);
      final destPath = p.join(cacheDir.path, fileName);

      await File(sourcePath).copy(destPath);
      return FileOperationSuccess(path: destPath);
    } catch (e) {
      return FileOperationFailure('failed to copy to cache: $e', FileOperationError.ioError);
    }
  }

  /// clear cache directory
  Future<void> clearCache() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      final entities = await cacheDir.list().toList();
      for (final entity in entities) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('error clearing cache: $e');
    }
  }

  /// get cache size in bytes
  Future<int> getCacheSize() async {
    try {
      final cacheDir = await getTemporaryDirectory();
      int totalSize = 0;

      await for (final entity in cacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}
