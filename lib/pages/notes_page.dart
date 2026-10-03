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
  Map<String, int> gcolors = loadGroupColors();
  String filter = _all; // _all, '' (no group) or a group name
  String sort = loadSort();
  final pc = PageController();
  final keys = <String, GlobalKey>{}; // to scroll the tab strip to the selected tab

  List<String> get tabs => [_all, '', ...groups];
  bool get realGroup => filter != _all && filter != '';
  String newId() => DateTime.now().millisecondsSinceEpoch.toString();

  void refresh() => setState(() {
        notes = loadNotes();
        groups = loadGroups();
        gcolors = loadGroupColors();
        if (realGroup && !groups.contains(filter)) {
          filter = _all;
          goTo(_all);
        }
      });

  /// Selects a tab and moves the pages to it.
  void goTo(String value, {bool animate = false}) {
    setState(() => filter = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final i = tabs.indexOf(value);
      if (i >= 0 && pc.hasClients) {
        final cur = (pc.page ?? 0).round();
        if (animate && (cur - i).abs() == 1) {
          pc.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        } else {
          pc.jumpToPage(i);
        }
      }
      reveal(value);
    });
  }

  void reveal(String value) => WidgetsBinding.instance.addPostFrameCallback((_) {
        final c = keys[value]?.currentContext;
        if (c != null) {
          Scrollable.ensureVisible(c,
              duration: const Duration(milliseconds: 200), alignment: 0.5);
        }
      });

  Future<void> open(Note n) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => EditorPage(note: n)));
    refresh();
  }

  // ---- sorting: pinned notes always first ----

  List<Note> sorted(List<Note> l) => l
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      switch (sort) {
        case 'created':
          return b.created.compareTo(a.created);
        case 'az':
          return a.title.toLowerCase().compareTo(b.title.toLowerCase());
        case 'za':
          return b.title.toLowerCase().compareTo(a.title.toLowerCase());
        default:
          return b.modified.compareTo(a.modified);
      }
    });

  // ---- groups ----

  Future<void> addGroup() async {
    final name = await askText(context, 'New group name');
    if (name == null || name.isEmpty || name == _all) return;
    if (!groups.contains(name)) {
      groups.add(name);
      saveGroups(groups);
      gcolors[name] = groupPalette[(groups.length - 1) % groupPalette.length];
      saveGroupColors(gcolors);
    }
    goTo(name);
  }

  Future<void> renameGroup() async {
    final name = await askText(context, 'Rename group', initial: filter);
    if (name == null || name.isEmpty || name == filter || groups.contains(name)) return;
    groups[groups.indexOf(filter)] = name;
    saveGroups(groups);
    gcolors[name] = gcolors.remove(filter) ?? groupPalette[0];
    saveGroupColors(gcolors);
    for (final n in notes.where((n) => n.group == filter)) {
      n.group = name;
      saveNote(n);
    }
    filter = name;
    refresh();
  }

  Future<void> changeGroupColor() async {
    final c = await pickSwatch(context, 'Group color', groupPalette);
    if (c == null) return;
    gcolors[filter] = c;
    saveGroupColors(gcolors);
    setState(() {});
  }

  Future<void> deleteGroup() async {
    if (!await confirm(context, 'Delete group "$filter"? Its notes are kept (no group).')) {
      return;
    }
    groups.remove(filter);
    saveGroups(groups);
    gcolors.remove(filter);
    saveGroupColors(gcolors);
    for (final n in notes.where((n) => n.group == filter)) {
      n.group = '';
      saveNote(n);
    }
    filter = _all;
    refresh();
    goTo(_all);
  }

  // ---- import ----

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
      saveNote(Note(newId(), title, runs, realGroup ? filter : ''));
      refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
  }

  // ---- note actions (long press) ----

  Future<void> noteMenu(Note n) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: Icon(n.pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(n.pinned ? 'Unpin' : 'Pin to top'),
              onTap: () => Navigator.pop(s, 'pin')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(s, 'delete')),
        ]),
      ),
    );
    if (v == 'pin') {
      n.pinned = !n.pinned;
      saveNote(n);
      refresh();
    } else if (v == 'delete') {
      if (!mounted) return;
      if (await confirm(context, 'Delete "${n.title.isEmpty ? 'Untitled' : n.title}"?')) {
        deleteNote(n.id);
        refresh();
      }
    }
  }

  // ---- UI ----

  /// One browser-style tab (groups show their color dot).
  Widget tab(String label, String value) {
    final selected = filter == value;
    final dot = groups.contains(value) ? Color(gcolors[value] ?? groupPalette[0]) : null;
    return GestureDetector(
      onTap: () => goTo(value, animate: true),
      child: Container(
        key: keys.putIfAbsent(value, () => GlobalKey()),
        margin: const EdgeInsets.only(right: 3),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).scaffoldBackgroundColor : Colors.black12,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null)
            Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          Text(label, style: TextStyle(fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget card(Note n) => Card(
        color: n.bg == 0 ? null : Color(n.bg),
        child: InkWell(
          onTap: () => open(n),
          onLongPress: () => noteMenu(n),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text(n.title.isEmpty ? 'Untitled' : n.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold))),
                if (n.pinned) const Icon(Icons.push_pin, size: 16),
              ]),
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
      );

  Widget page(String value) {
    final list = sorted(value == _all
        ? [...notes]
        : notes.where((n) => n.group == value).toList());
    if (list.isEmpty) {
      return const Center(child: Text('No notes here', style: TextStyle(color: Colors.grey)));
    }
    return GridView.count(
        crossAxisCount: 2, padding: const EdgeInsets.all(8), children: [for (final n in list) card(n)]);
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
            tooltip: 'Sort',
            icon: const Icon(Icons.sort),
            onSelected: (v) {
              saveSort(v);
              setState(() => sort = v);
            },
            itemBuilder: (_) => [
              CheckedPopupMenuItem(
                  value: 'modified', checked: sort == 'modified', child: const Text('Date modified')),
              CheckedPopupMenuItem(
                  value: 'created', checked: sort == 'created', child: const Text('Date created')),
              CheckedPopupMenuItem(value: 'az', checked: sort == 'az', child: const Text('Title A–Z')),
              CheckedPopupMenuItem(value: 'za', checked: sort == 'za', child: const Text('Title Z–A')),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'import') importNote();
              if (v == 'rename') renameGroup();
              if (v == 'color') changeGroupColor();
              if (v == 'delete') deleteGroup();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'import', child: Text('Import note (.docx / .txt)')),
              if (realGroup) const PopupMenuItem(value: 'rename', child: Text('Rename group')),
              if (realGroup) const PopupMenuItem(value: 'color', child: Text('Group color')),
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
          onPressed: () => open(Note(newId(), '', [], realGroup ? filter : '')),
          child: const Icon(Icons.edit)),
      // Swipe left/right on the list to move to the next/previous group tab.
      body: PageView.builder(
        controller: pc,
        itemCount: tabs.length,
        onPageChanged: (i) {
          setState(() => filter = tabs[i]);
          reveal(tabs[i]);
        },
        itemBuilder: (_, i) => page(tabs[i]),
      ),
    );
  }
}
