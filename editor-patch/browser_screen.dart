import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart' hide FileType;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../services/file_service.dart';
import '../services/webdav_service.dart';
import '../models/file_item.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'batch_screen.dart';

// unified file browser for local and nextcloud
// all code comments are entirely in lowercase
final currentPathProvider = StateProvider<String>((ref) => '');
final isRemoteProvider = StateProvider<bool>((ref) => false);
final selectedFileInBrowserProvider = StateProvider<FileItem?>((ref) => null);

// cached provider for media directories to avoid recreating future on every rebuild
final mediaDirectoriesProvider = FutureProvider<Map<String, String>>((ref) async {
  final fileService = ref.read(fileServiceProvider);
  return fileService.getMediaDirectories();
});

final fileListProvider = FutureProvider<List<FileItem>>((ref) async {
  final path = ref.watch(currentPathProvider);
  final isRemote = ref.watch(isRemoteProvider);

  if (isRemote) {
    return ref.read(webDavServiceProvider).listFiles(path);
  } else {
    // handle android permissions
    if (Platform.isAndroid) {
      final fileService = ref.read(fileServiceProvider);
      final hasPermissions = await fileService.hasStoragePermissions();
      if (!hasPermissions) {
        await fileService.requestStoragePermissions();
      }
    }

    final service = ref.read(fileServiceProvider);
    final root = path.isEmpty ? await service.getRootPath() : path;
    return service.listLocalFiles(root);
  }
});

class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filesAsync = ref.watch(fileListProvider);
    final isRemote = ref.watch(isRemoteProvider);
    final selectedFile = ref.watch(selectedFileInBrowserProvider);
    final currentPath = ref.watch(currentPathProvider);
    final isWide = MediaQuery.of(context).size.width > 900;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openBatchProcessing(context),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: AppTheme.backgroundColor,
        icon: const Icon(Icons.layers),
        label: const Text(
          'batch',
          style: TextStyle(fontFamily: 'VarelaRound'),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, ref, details.globalPosition),
          onLongPressStart: (details) =>
              _showContextMenu(context, ref, details.globalPosition),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: filesAsync.when(
                  data: (files) {
                    return CustomScrollView(
                      clipBehavior: Clip.none,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                            child: Row(
                              children: [
                                if (currentPath.isNotEmpty)
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    onPressed: () {
                                      final current = ref.read(currentPathProvider);
                                      if (current.isEmpty) return;
                                      final parts = current.split('/');
                                      parts.removeLast();
                                      ref.read(currentPathProvider.notifier).state =
                                          parts.join('/');
                                    },
                                  ),
                                Text(
                                  (isRemote ? 'nextcloud' : 'local files').toLowerCase(),
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'VarelaRound',
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  'remote',
                                  style: TextStyle(
                                    color: AppTheme.textMuted,
                                    fontFamily: 'VarelaRound',
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Switch(
                                  value: isRemote,
                                  activeColor: AppTheme.primaryColor,
                                  onChanged: (val) {
                                    ref.read(isRemoteProvider.notifier).state = val;
                                    ref.read(currentPathProvider.notifier).state = '';
                                    ref.read(selectedFileInBrowserProvider.notifier).state = null;
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        // quick access chips
                        if (!isRemote && currentPath.isEmpty)
                          SliverToBoxAdapter(
                            child: const QuickAccessChips(),
                          ),
                        if (files.isEmpty)
                          SliverFillRemaining(
                            child: Center(
                              child: Text(
                                isRemote
                                    ? 'no files found in this folder\n(right-click to add files or refresh)'
                                    : 'no files found\n(tap anywhere to add)',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTheme.textMuted,
                                  fontFamily: 'VarelaRound',
                                ),
                              ),
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 60),
                            sliver: SliverGrid(
                              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: isWide ? 95 : 75,
                                crossAxisSpacing: 12,
                                mainAxisSpacing: 20,
                                childAspectRatio: 0.8,
                              ),
                              delegate: SliverChildBuilderDelegate(
                                (context, index) {
                                  final file = files[index];
                                  final isSelected = selectedFile?.path == file.path;
                                  return FileGridItem(
                                    file: file,
                                    isSelected: isSelected,
                                    onTap: () {
                                      if (file.isDirectory) {
                                        ref.read(currentPathProvider.notifier).state = file.path;
                                        ref.read(selectedFileInBrowserProvider.notifier).state = null;
                                      } else {
                                        ref.read(selectedFileInBrowserProvider.notifier).state = file;
                                        if (!isWide) {
                                          ref.openEditor(file);
                                        }
                                      }
                                    },
                                    onSecondaryTap: (pos) =>
                                        _showContextMenu(context, ref, pos, file),
                                  );
                                },
                                childCount: files.length,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (err, stack) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: AppTheme.textMuted),
                        const SizedBox(height: 16),
                        Text(
                          'error loading files',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          err.toString(),
                          style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () => ref.invalidate(fileListProvider),
                          icon: const Icon(Icons.refresh),
                          label: const Text('retry'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isWide && selectedFile != null) const VerticalDivider(width: 1),
              if (isWide && selectedFile != null)
                Expanded(
                  flex: 1,
                  child: FileDetailsPanel(file: selectedFile),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, Offset position,
      [FileItem? file]) {
    showMenu(
      context: context,
      position:
          RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: AppTheme.surfaceColor,
      items: file == null
          ? [
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.add, size: 18),
                    SizedBox(width: 12),
                    Text('add file'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'batch',
                child: Row(
                  children: [
                    Icon(Icons.layers, size: 18),
                    SizedBox(width: 12),
                    Text('batch process'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh, size: 18),
                    SizedBox(width: 12),
                    Text('refresh'),
                  ],
                ),
              ),
            ]
          : [
              const PopupMenuItem(
                value: 'open',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18),
                    SizedBox(width: 12),
                    Text('open'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 12),
                    Text('delete', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
      elevation: 8,
    ).then((value) {
      if (!context.mounted) return;
      if (value == 'add') {
        _addFile(context, ref);
      } else if (value == 'batch') {
        _openBatchProcessing(context);
      } else if (value == 'refresh') {
        ref.invalidate(fileListProvider);
      } else if (value == 'open' && file != null) {
        ref.openEditor(file);
      } else if (value == 'delete' && file != null) {
        _deleteFile(context, ref, file);
      }
    });
  }

  void _openBatchProcessing(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const BatchScreen()),
    );
  }

  void _deleteFile(BuildContext context, WidgetRef ref, FileItem file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surfaceColor,
        title: const Text('delete file'),
        content: Text('are you sure you want to delete ${file.name.toLowerCase()}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final isRemote = ref.read(isRemoteProvider);
      final scaffoldMessenger = ScaffoldMessenger.of(context);

      if (isRemote) {
        final success = await ref.read(webDavServiceProvider).deleteFile(file.path);
        if (success) {
          ref.invalidate(fileListProvider);
          scaffoldMessenger.showSnackBar(const SnackBar(content: Text('file deleted')));
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('failed to delete file')),
          );
        }
      } else {
        final result = await ref.read(fileServiceProvider).deleteFile(file.path);
        switch (result) {
          case FileOperationSuccess():
            ref.invalidate(fileListProvider);
            ref.read(selectedFileInBrowserProvider.notifier).state = null;
            scaffoldMessenger.showSnackBar(const SnackBar(content: Text('file deleted')));
          case FileOperationFailure(:final message):
            scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
        }
      }
    }
  }

  void _addFile(BuildContext context, WidgetRef ref) async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null && context.mounted) {
      final sourcePath = result.files.single.path!;
      final isRemote = ref.read(isRemoteProvider);
      final currentPath = ref.read(currentPathProvider);

      final scaffoldMessenger = ScaffoldMessenger.of(context);

      if (isRemote) {
        final service = ref.read(webDavServiceProvider);
        final fileName = sourcePath.split('/').last;
        final remotePath = currentPath.isEmpty ? fileName : '$currentPath/$fileName';

        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()),
        );

        final success = await service.uploadFile(sourcePath, remotePath);

        if (context.mounted) Navigator.pop(context); // close loader

        if (success) {
          ref.invalidate(fileListProvider);
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('file uploaded to nextcloud')),
          );
        } else {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('failed to upload to nextcloud')),
          );
        }
      } else {
        final service = ref.read(fileServiceProvider);
        final destDir = currentPath.isEmpty ? await service.getRootPath() : currentPath;
        final result = await service.addFile(sourcePath, destDir);

        switch (result) {
          case FileOperationSuccess(:final message):
            ref.invalidate(fileListProvider);
            scaffoldMessenger.showSnackBar(
              SnackBar(content: Text(message ?? 'file added successfully')),
            );
          case FileOperationFailure(:final message):
            scaffoldMessenger.showSnackBar(SnackBar(content: Text(message)));
        }
      }
    }
  }
}

class QuickAccessChips extends ConsumerWidget {
  const QuickAccessChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // use cached provider instead of FutureBuilder to avoid memory leak
    final dirsAsync = ref.watch(mediaDirectoriesProvider);

    return dirsAsync.when(
      data: (dirs) {
        if (dirs.isEmpty) {
          return const SizedBox.shrink();
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: dirs.entries.map((entry) {
              IconData icon;
              switch (entry.key) {
                case 'downloads':
                  icon = Icons.download;
                  break;
                case 'pictures':
                  icon = Icons.image;
                  break;
                case 'videos':
                  icon = Icons.movie;
                  break;
                case 'music':
                  icon = Icons.music_note;
                  break;
                case 'dcim':
                  icon = Icons.camera_alt;
                  break;
                case 'documents':
                  icon = Icons.description;
                  break;
                default:
                  icon = Icons.folder;
              }

              return ActionChip(
                avatar: Icon(icon, size: 16, color: AppTheme.primaryColor),
                label: Text(
                  entry.key,
                  style: const TextStyle(
                    fontFamily: 'VarelaRound',
                    fontSize: 12,
                  ),
                ),
                backgroundColor: AppTheme.accentColor,
                side: BorderSide.none,
                onPressed: () {
                  ref.read(currentPathProvider.notifier).state = entry.value;
                },
              );
            }).toList(),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class FileGridItem extends StatelessWidget {
  final FileItem file;
  final bool isSelected;
  final VoidCallback onTap;
  final Function(Offset) onSecondaryTap;

  const FileGridItem({
    required this.file,
    required this.isSelected,
    required this.onTap,
    required this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) => onSecondaryTap(details.globalPosition),
      onLongPressStart: (details) => onSecondaryTap(details.globalPosition),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: _buildIcon(theme),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                file.name.toLowerCase(),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.visible,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface,
                  height: 1.1,
                  fontFamily: 'VarelaRound',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(ThemeData theme) {
    // use type-specific icons
    IconData icon;
    Color? iconColor;

    switch (file.type) {
      case FileType.folder:
        return Image.asset(
          'assets/folder.png',
          color: theme.colorScheme.primary,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.folder,
            size: 24,
            color: theme.colorScheme.primary,
          ),
        );
      case FileType.image:
        icon = Icons.image;
        iconColor = AppTheme.secondaryColor;
        break;
      case FileType.video:
        icon = Icons.movie;
        iconColor = AppTheme.primaryColor;
        break;
      case FileType.audio:
        icon = Icons.audiotrack;
        iconColor = Colors.green;
        break;
      case FileType.document:
        icon = Icons.description;
        iconColor = AppTheme.textMuted;
        break;
      case FileType.archive:
        icon = Icons.folder_zip;
        iconColor = AppTheme.textMuted;
        break;
      case FileType.other:
        return Image.asset(
          'assets/file.png',
          color: theme.colorScheme.primary,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.insert_drive_file,
            size: 24,
            color: theme.colorScheme.primary,
          ),
        );
    }

    return Icon(icon, size: 24, color: iconColor);
  }
}

class FileDetailsPanel extends ConsumerWidget {
  final FileItem file;
  const FileDetailsPanel({required this.file});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Container(
      color: AppTheme.surfaceColor,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'file details',
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.textMuted,
              fontFamily: 'VarelaRound',
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.accentColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getIcon(file.type),
                size: 64,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
              ),
            ),
          ),
          const SizedBox(height: 24),
          _DetailRow(label: 'name', value: file.name.toLowerCase()),
          _DetailRow(label: 'size', value: _formatSize(file.size)),
          _DetailRow(
            label: 'modified',
            value: file.lastModified.toLocal().toString().split('.')[0],
          ),
          _DetailRow(label: 'type', value: file.type.name.toLowerCase()),
          _DetailRow(label: 'location', value: file.isRemote ? 'nextcloud' : 'local'),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => ref.openEditor(file),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: AppTheme.backgroundColor,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.edit),
              label: const Text(
                'open in editor',
                style: TextStyle(fontFamily: 'VarelaRound'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes b';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} kb';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} mb';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} gb';
  }

  IconData _getIcon(FileType type) {
    switch (type) {
      case FileType.image:
        return Icons.image;
      case FileType.video:
        return Icons.movie;
      case FileType.audio:
        return Icons.music_note;
      case FileType.document:
        return Icons.description;
      case FileType.archive:
        return Icons.folder_zip;
      default:
        return Icons.insert_drive_file;
    }
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.textMuted,
              fontFamily: 'VarelaRound',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w500,
              fontFamily: 'VarelaRound',
            ),
          ),
        ],
      ),
    );
  }
}
