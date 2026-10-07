import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/note.dart';
import '../services/app_theme.dart';
import '../services/backup.dart';
import '../services/exporters.dart';
import '../services/importers.dart';
import '../services/storage.dart';
import '../widgets/dialogs.dart';
import 'editor_page.dart';
import 'trash_page.dart';

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

  bool searching = false;
  String query = '';
  final searchCtl = TextEditingController();

  final Set<String> picked = {}; // ids of the selected notes (selection mode)
  bool get selecting => picked.isNotEmpty;

  List<String> get tabs => [_all, '', ...groups];
  bool get realGroup => filter != _all && filter != '';

  /// Unique id; the id is also the creation time in ms.
  String newId() {
    var t = DateTime.now().millisecondsSinceEpoch;
    while (noteExists(t.toString())) {
      t++;
    }
    return t.toString();
  }

  void snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  void refresh() => setState(() {
        notes = loadNotes();
        groups = loadGroups();
        gcolors = loadGroupColors();
        picked.retainAll(notes.map((n) => n.id));
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

  Future<void> openTrash() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TrashPage()));
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

  List<Note> listFor(String value) =>
      sorted(value == _all ? [...notes] : notes.where((n) => n.group == value).toList());

  // ---- search ----

  List<Note> searchResults() {
    final q = query.toLowerCase();
    if (q.isEmpty) return [];
    return sorted(notes
        .where((n) => n.title.toLowerCase().contains(q) || n.plain.toLowerCase().contains(q))
        .toList());
  }

  void closeSearch() => setState(() {
        searching = false;
        query = '';
        searchCtl.clear();
      });

  Widget results() {
    if (query.isEmpty) {
      return const Center(child: Text('Type to search all notes', style: TextStyle(color: Colors.grey)));
    }
    final list = searchResults();
    if (list.isEmpty) {
      return const Center(child: Text('No matches', style: TextStyle(color: Colors.grey)));
    }
    return GridView.count(
        crossAxisCount: 2, padding: const EdgeInsets.all(8), children: [for (final n in list) card(n)]);
  }

  // ---- selection mode (long-press a note) ----

  List<Note> get pickedNotes => notes.where((n) => picked.contains(n.id)).toList();
  List<Note> get visible => searching ? searchResults() : listFor(filter);

  void toggle(Note n) => setState(() {
        if (!picked.add(n.id)) picked.remove(n.id);
      });

  void clearPick() => setState(picked.clear);

  void pinPicked() {
    final ps = pickedNotes;
    final allPinned = ps.every((n) => n.pinned);
    for (final n in ps) {
      n.pinned = !allPinned;
    }
    saveMany(ps);
    picked.clear();
    refresh();
  }

  void movePicked(String group) {
    final ps = pickedNotes;
    for (final n in ps) {
      n.group = group;
    }
    saveMany(ps);
    picked.clear();
    refresh();
  }

  void duplicatePicked() {
    final copies = <Note>[];
    for (final n in pickedNotes) {
      copies.add(Note(newId(), '${n.title.isEmpty ? 'Untitled' : n.title} (copy)', List.of(n.runs),
          n.group, false, n.bg, null, 0, List.of(n.images)));
      saveNote(copies.last); // so the next newId() is different
    }
    picked.clear();
    refresh();
    snack('Duplicated ${copies.length} note${copies.length == 1 ? '' : 's'}');
  }

  void trashPicked() {
    final ids = picked.toList();
    for (final id in ids) {
      trashNote(id);
    }
    picked.clear();
    refresh();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Moved ${ids.length} to trash'),
      action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            for (final id in ids) {
              restoreNote(id);
            }
            refresh();
          }),
    ));
  }

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
    final moved = notes.where((n) => n.group == filter).toList();
    for (final n in moved) {
      n.group = name;
    }
    saveMany(moved);
    filter = name;
    refresh();
  }

  Future<void> changeGroupColor() async {
    final pick = await pickSwatch(context, 'Group color', groupPalette, custom: true);
    if (pick == null || !mounted) return;
    final Color? c = pick == -1
        ? await pickColorDialog(context, Color(gcolors[filter] ?? groupPalette[0]))
        : Color(pick);
    if (c == null) return;
    gcolors[filter] = c.value;
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
    final moved = notes.where((n) => n.group == filter).toList();
    for (final n in moved) {
      n.group = '';
    }
    saveMany(moved);
    filter = _all;
    refresh();
    goTo(_all);
  }

  Future<void> pickTheme() async {
    final cur = loadTheme();
    final v = await showDialog<String>(
      context: context,
      builder: (d) => SimpleDialog(title: const Text('Theme'), children: [
        for (final e in {'system': 'System default', 'light': 'Light', 'dark': 'Dark'}.entries)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(d, e.key),
            child: Row(children: [
              Icon(cur == e.key ? Icons.radio_button_checked : Icons.radio_button_off),
              const SizedBox(width: 12),
              Text(e.value),
            ]),
          ),
      ]),
    );
    if (v != null) setTheme(v);
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
      snack('Could not import: $e');
    }
  }

  // ---- backup & restore (.zip with photos and drawings) ----

  Future<void> backup({required bool toDevice}) async {
    try {
      final bytes = await makeBackup();
      final d = DateTime.now();
      final name = 'colornote-backup-${d.year}'
          '${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}.zip';
      if (toDevice) {
        final p = await saveToDevice(name, bytes);
        if (p != null) snack('Saved $name');
      } else {
        await shareFile(name, bytes, 'application/zip');
      }
    } catch (e) {
      snack('Backup failed: $e');
    }
  }

  Future<void> restore() async {
    try {
      final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
      final f = r?.files.single;
      if (f == null || f.bytes == null) return;
      final n = await restoreBackup(f.bytes!);
      refresh();
      snack('Restored $n note${n == 1 ? '' : 's'}');
    } catch (e) {
      snack('Could not restore: $e');
    }
  }

  void backupSheet() => showModalBottomSheet(
        context: context,
        builder: (s) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.backup_outlined),
              title: const Text('Back up all notes'),
              subtitle: Text('${notes.length} notes with photos, drawings, groups and palettes'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Save to device',
                    icon: const Icon(Icons.save_alt),
                    onPressed: () {
                      Navigator.pop(s);
                      backup(toDevice: true);
                    }),
                IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.share),
                    onPressed: () {
                      Navigator.pop(s);
                      backup(toDevice: false);
                    }),
              ]),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Restore from backup file'),
              subtitle: const Text('Adds missing notes; nothing is deleted'),
              onTap: () {
                Navigator.pop(s);
                restore();
              },
            ),
          ]),
        ),
      );

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

  PreferredSizeWidget tabStrip() => PreferredSize(
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
      );

  Widget card(Note n) {
    final ink = autoInk(context, n.bg);
    final primary = Theme.of(context).colorScheme.primary;
    final on = picked.contains(n.id);
    final thumb = n.images.isEmpty ? null : n.images.first;
    return Card(
      color: n.bg == 0 ? null : Color(n.bg),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: on ? primary : Colors.transparent, width: 3),
      ),
      child: InkWell(
        onTap: () => selecting ? toggle(n) : open(n),
        onLongPress: () => toggle(n),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (thumb != null)
            SizedBox(
              height: 70,
              width: double.infinity,
              child: Image.file(File(imagePath(thumb)),
                  fit: BoxFit.cover,
                  cacheWidth: 400,
                  errorBuilder: (_, __, ___) => const SizedBox()),
            ),
          Expanded(
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
                  if (on) Icon(Icons.check_circle, size: 18, color: primary),
                ]),
                const SizedBox(height: 6),
                Expanded(
                    child: Text.rich(
                        TextSpan(children: [
                          for (final r in n.runs) TextSpan(text: r.t, style: r.s.styleOn(ink))
                        ]),
                        overflow: TextOverflow.fade)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget page(String value) {
    final list = listFor(value);
    if (list.isEmpty) {
      return const Center(child: Text('No notes here', style: TextStyle(color: Colors.grey)));
    }
    return GridView.count(
        crossAxisCount: 2, padding: const EdgeInsets.all(8), children: [for (final n in list) card(n)]);
  }

  AppBar selectionBar() {
    final ps = pickedNotes;
    final allPinned = ps.isNotEmpty && ps.every((n) => n.pinned);
    return AppBar(
      leading: IconButton(tooltip: 'Cancel', icon: const Icon(Icons.close), onPressed: clearPick),
      title: Text('${picked.length} selected'),
      actions: [
        IconButton(
            tooltip: allPinned ? 'Unpin' : 'Pin to top',
            icon: Icon(allPinned ? Icons.push_pin_outlined : Icons.push_pin),
            onPressed: pinPicked),
        PopupMenuButton<String>(
          tooltip: 'Move to group',
          icon: const Icon(Icons.folder_open),
          onSelected: movePicked,
          itemBuilder: (_) => [
            const PopupMenuItem<String>(value: '', child: Text('No group')),
            for (final g in groups)
              PopupMenuItem<String>(
                value: g,
                child: Row(children: [
                  Icon(Icons.folder, color: Color(gcolors[g] ?? groupPalette[0])),
                  const SizedBox(width: 12),
                  Flexible(child: Text(g, overflow: TextOverflow.ellipsis)),
                ]),
              ),
          ],
        ),
        IconButton(tooltip: 'Move to trash', icon: const Icon(Icons.delete_outline), onPressed: trashPicked),
        PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'all') setState(() => picked.addAll(visible.map((n) => n.id)));
            if (v == 'copy') duplicatePicked();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'all', child: Text('Select all')),
            PopupMenuItem(value: 'copy', child: Text('Duplicate')),
          ],
        ),
      ],
      bottom: tabStrip(),
    );
  }

  AppBar normalBar(ColorScheme cs) => AppBar(
        title: searching
            ? TextField(
                controller: searchCtl,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Search notes', border: InputBorder.none),
                onChanged: (v) => setState(() => query = v.trim()),
              )
            : const Text('My Notes'),
        backgroundColor: cs.primaryContainer,
        foregroundColor: cs.onPrimaryContainer,
        actions: searching
            ? [IconButton(tooltip: 'Close search', icon: const Icon(Icons.close), onPressed: closeSearch)]
            : [
                IconButton(
                    tooltip: 'Search',
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => searching = true)),
                PopupMenuButton<String>(
                  tooltip: 'Sort',
                  icon: const Icon(Icons.sort),
                  onSelected: (v) {
                    saveSort(v);
                    setState(() => sort = v);
                  },
                  itemBuilder: (_) => [
                    CheckedPopupMenuItem(
                        value: 'modified',
                        checked: sort == 'modified',
                        child: const Text('Date modified')),
                    CheckedPopupMenuItem(
                        value: 'created', checked: sort == 'created', child: const Text('Date created')),
                    CheckedPopupMenuItem(
                        value: 'az', checked: sort == 'az', child: const Text('Title A–Z')),
                    CheckedPopupMenuItem(
                        value: 'za', checked: sort == 'za', child: const Text('Title Z–A')),
                  ],
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'import') importNote();
                    if (v == 'backup') backupSheet();
                    if (v == 'trash') openTrash();
                    if (v == 'theme') pickTheme();
                    if (v == 'rename') renameGroup();
                    if (v == 'color') changeGroupColor();
                    if (v == 'delete') deleteGroup();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'import', child: Text('Import note (.docx / .txt)')),
                    const PopupMenuItem(value: 'backup', child: Text('Backup & restore')),
                    const PopupMenuItem(value: 'trash', child: Text('Trash')),
                    const PopupMenuItem(value: 'theme', child: Text('Theme')),
                    if (realGroup) const PopupMenuItem(value: 'rename', child: Text('Rename group')),
                    if (realGroup) const PopupMenuItem(value: 'color', child: Text('Group color')),
                    if (realGroup) const PopupMenuItem(value: 'delete', child: Text('Delete group')),
                  ],
                ),
              ],
        bottom: searching ? null : tabStrip(),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !searching && !selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) {
          clearPick();
        } else {
          closeSearch();
        }
      },
      child: Scaffold(
        appBar: selecting ? selectionBar() : normalBar(cs),
        floatingActionButton: selecting
            ? null
            : FloatingActionButton(
                onPressed: () => open(Note(newId(), '', [], realGroup ? filter : '')),
                child: const Icon(Icons.edit)),
        // Swipe left/right on the list to move to the next/previous group tab.
        body: Stack(fit: StackFit.expand, children: [
          PageView.builder(
            controller: pc,
            itemCount: tabs.length,
            onPageChanged: (i) {
              setState(() => filter = tabs[i]);
              reveal(tabs[i]);
            },
            itemBuilder: (_, i) => page(tabs[i]),
          ),
          if (searching)
            Positioned.fill(
              child: ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: results()),
            ),
        ]),
      ),
    );
  }
}
