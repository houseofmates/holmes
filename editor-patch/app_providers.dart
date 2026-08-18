import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/file_item.dart';

// navigation and global state providers
// all code comments are entirely in lowercase

// current active tab index in main shell
final navIndexProvider = StateProvider<int>((ref) => 0);

// currently selected file for editing
final selectedFileItemProvider = StateProvider<FileItem?>((ref) => null);

// helper to switch tab and select file
extension NavExtension on WidgetRef {
  void openEditor(FileItem file) {
    read(selectedFileItemProvider.notifier).state = file;
    int index = 0;
    switch (file.type) {
      case FileType.image:
        index = 1;
        break;
      case FileType.video:
        index = 2;
        break;
      case FileType.audio:
        index = 3;
        break;
      default:
        index = 0;
    }
    read(navIndexProvider.notifier).state = index;
  }
}
