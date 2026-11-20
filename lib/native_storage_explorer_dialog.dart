import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app_theme.dart';

class NativeStorageExplorerDialog extends StatefulWidget {
  final bool isFolderPicker;
  final List<String> fileExtensions;

  const NativeStorageExplorerDialog({
    super.key,
    required this.isFolderPicker,
    this.fileExtensions = const ['.json'],
  });

  @override
  State<NativeStorageExplorerDialog> createState() => _NativeStorageExplorerDialogState();
}

class _NativeStorageExplorerDialogState extends State<NativeStorageExplorerDialog> {
  late Directory currentDirectory;
  List<FileSystemEntity> entities = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _initDirectory();
  }

  Future<void> _initDirectory() async {
    Directory? target;
    final candidates = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
    ];

    for (final path in candidates) {
      final d = Directory(path);
      if (await d.exists()) {
        try {
          d.listSync();
          target = d;
          break;
        } catch (_) {}
      }
    }

    if (target == null) {
      final ext = await getExternalStorageDirectory();
      target = ext ?? await getApplicationDocumentsDirectory();
    }

    _loadDirectory(target);
  }

  void _loadDirectory(Directory dir) {
    setState(() {
      isLoading = true;
      currentDirectory = dir;
    });

    try {
      final list = dir.listSync();
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });

      if (!widget.isFolderPicker) {
        entities = list.where((e) {
          if (e is Directory) return true;
          final ext = p.extension(e.path).toLowerCase();
          return widget.fileExtensions.contains(ext);
        }).toList();
      } else {
        entities = list.whereType<Directory>().toList();
      }
    } catch (_) {
      entities = [];
    }

    if (mounted) {
      setState(() {
        isLoading = false;
      });
    }
  }

  bool get canGoUp => currentDirectory.path != '/storage/emulated/0';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.isFolderPicker ? 'Choose Folder' : 'Select File'),
      content: SizedBox(
        width: 480,
        height: 380,
        child: Column(
          children: [
            Row(
              children: [
                if (canGoUp)
                  IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    onPressed: () => _loadDirectory(currentDirectory.parent),
                  ),
                Expanded(
                  child: Text(
                    currentDirectory.path.replaceAll('/storage/emulated/0', 'Storage'),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: entities.length,
                      itemBuilder: (_, index) {
                        final item = entities[index];
                        final isDir = item is Directory;
                        return ListTile(
                          dense: true,
                          leading: Icon(isDir ? Icons.folder_rounded : Icons.insert_drive_file_rounded, color: isDir ? AppColors.amber : AppColors.cyan),
                          title: Text(p.basename(item.path), style: const TextStyle(fontSize: 12)),
                          onTap: () {
                            if (isDir) {
                              _loadDirectory(Directory(item.path));
                            } else if (!widget.isFolderPicker) {
                              Navigator.pop(context, File(item.path));
                            }
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        if (widget.isFolderPicker)
          FilledButton(
            onPressed: () => Navigator.pop(context, currentDirectory),
            child: const Text('Save In This Folder'),
          ),
      ],
    );
  }
}
