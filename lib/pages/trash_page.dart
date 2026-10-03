import 'dart:math';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/storage.dart';
import '../widgets/dialogs.dart';

class TrashPage extends StatefulWidget {
  const TrashPage({super.key});
  @override
  State<TrashPage> createState() => _TrashPageState();
}

class _TrashPageState extends State<TrashPage> {
  List<Note> items = _load();

  static List<Note> _load() => loadTrash()..sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
  void reload() => setState(() => items = _load());

  String daysLeft(Note n) {
    final used = (DateTime.now().millisecondsSinceEpoch - n.deletedAt) ~/ 86400000;
    final left = max(trashDays - used, 0);
    return left == 1 ? '1 day left' : '$left days left';
  }

  Future<void> deleteForever(Note n) async {
    if (!await confirm(context, 'Permanently delete this note?')) return;
    purgeNote(n.id);
    reload();
  }

  Future<void> empty() async {
    if (!await confirm(context, 'Permanently delete all ${items.length} notes in the trash?')) {
      return;
    }
    emptyTrash();
    reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Trash'),
          actions: [
            if (items.isNotEmpty)
              PopupMenuButton<String>(
                onSelected: (_) => empty(),
                itemBuilder: (_) => const [PopupMenuItem(value: 'empty', child: Text('Empty trash'))],
              ),
          ],
        ),
        body: items.isEmpty
            ? const Center(child: Text('Trash is empty', style: TextStyle(color: Colors.grey)))
            : ListView(children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text('Notes are removed for good after $trashDays days.',
                      style: const TextStyle(color: Colors.grey)),
                ),
                for (final n in items)
                  ListTile(
                    title: Text(n.title.isEmpty ? 'Untitled' : n.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(n.plain.replaceAll('\n', ' '), maxLines: 1, overflow: TextOverflow.ellipsis),
                      Text(daysLeft(n), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'restore') {
                          restoreNote(n.id);
                          reload();
                        } else {
                          deleteForever(n);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'restore', child: Text('Restore')),
                        PopupMenuItem(value: 'delete', child: Text('Delete forever')),
                      ],
                    ),
                  ),
              ]),
      );
}
