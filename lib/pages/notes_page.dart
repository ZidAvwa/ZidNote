import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/exporters.dart';
import '../services/importers.dart';
import '../services/storage.dart';
import '../widgets/dialogs.dart';
import 'editor_page.dart';

const _all = '__all__';

class NotesPage extends StatefulWidget {
  const NotesPage({super.key});
  @override
  State<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends State<NotesPage> {
  List<Note> notes = loadNotes();
  List<String> groups = loadGroups();
  String filter = _all; // _all, '' (no group) or a group name

  bool get realGroup => filter != _all && filter != '';
  List<Note> get shown => filter == _all ? notes : notes.where((n) => n.group == filter).toList();
  String newId() => DateTime.now().millisecondsSinceEpoch.toString();

  void refresh() => setState(() {
        notes = loadNotes();
        groups = loadGroups();
        if (realGroup && !groups.contains(filter)) filter = _all;
      });

  Future<void> open(Note n) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorPage(note: n)));
    refresh();
  }

  Future<void> addGroup() async {
    final name = await askText(context, 'New group name');
    if (name == null || name.isEmpty || name == _all) return;
    if (!groups.contains(name)) {
      groups.add(name);
      saveGroups(groups);
    }
    setState(() => filter = name);
  }

  Future<void> renameGroup() async {
    final name = await askText(context, 'Rename group', initial: filter);
    if (name == null || name.isEmpty || name == filter || groups.contains(name)) return;
    groups[groups.indexOf(filter)] = name;
    saveGroups(groups);
    for (final n in notes.where((n) => n.group == filter)) {
      n.group = name;
      saveNote(n);
    }
    filter = name;
    refresh();
  }

  Future<void> deleteGroup() async {
    if (!await confirm(context, 'Delete group "$filter"? Its notes are kept (no group).')) {
      return;
    }
    groups.remove(filter);
    saveGroups(groups);
    for (final n in notes.where((n) => n.group == filter)) {
      n.group = '';
      saveNote(n);
    }
    filter = _all;
    refresh();
  }

  Future<void> importNote() async {
    try {
      final r = await FilePicker.platform
          .pickFiles(type: FileType.custom, allowedExtensions: ['docx', 'txt'], withData: true);
      final f = r?.files.single;
      if (f == null || f.bytes == null) return;
      final isDocx = (f.extension ?? '').toLowerCase() == 'docx';
      final runs = isDocx
          ? fromDocx(f.bytes!)
          : fromColorTxt(utf8.decode(f.bytes!, allowMalformed: true));
      final title = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      saveNote(Note(newId(), title, runs, filter == _all ? '' : filter));
      refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  /// One browser-style tab.
  Widget tab(String label, String value) {
    final selected = filter == value;
    return GestureDetector(
      onTap: () => setState(() => filter = value),
      child: Container(
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).scaffoldBackgroundColor : Colors.black12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Text(label,
            style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') importNote();
              if (v == 'rename') renameGroup();
              if (v == 'delete') deleteGroup();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'import', child: Text('Import note (.docx / .txt)')),
              if (realGroup) const PopupMenuItem(value: 'rename', child: Text('Rename group')),
              if (realGroup) const PopupMenuItem(value: 'delete', child: Text('Delete group')),
            ],
          )
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(left: 8, top: 4),
              children: [
                tab('All', _all),
                tab('No group', ''),
                for (final g in groups) tab(g, g),
                GestureDetector(
                  onTap: addGroup,
                  child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.add)),
                ),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
          onPressed: () => open(Note(newId(), '', [], filter == _all ? '' : filter)),
          child: const Icon(Icons.edit)),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(8),
        children: [
          for (final n in shown)
            Card(
              child: InkWell(
                onTap: () => open(n),
                onLongPress: () async {
                  if (await confirm(context, 'Delete "${n.title.isEmpty ? 'Untitled' : n.title}"?')) {
                    deleteNote(n.id);
                    refresh();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(n.title.isEmpty ? 'Untitled' : n.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Expanded(
                        child: Text.rich(
                            TextSpan(children: [
                              for (final r in n.runs) TextSpan(text: r.t, style: r.s.style)
                            ]),
                            overflow: TextOverflow.fade)),
                  ]),
                ),
              ),
            )
        ],
      ),
    );
  }
}
