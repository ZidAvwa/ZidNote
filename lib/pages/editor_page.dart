import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/note.dart';
import '../models/stroke.dart';
import '../services/exporters.dart';
import '../services/storage.dart';
import '../widgets/dialogs.dart';
import '../widgets/draw_page.dart';
import '../widgets/rich_controller.dart';

const _newPreset = '__new__';
const _delPreset = '__del__';

class EditorPage extends StatefulWidget {
  final Note note;
  const EditorPage({super.key, required this.note});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> with WidgetsBindingObserver {
  final ctl = RichCtl();
  Timer? _timer; // autosave
  bool _gone = false; // note was moved to trash, do not save again
  late final title = TextEditingController(text: widget.note.title);
  late Map<String, List<int>> presets;
  late String active;
  late List<String> groups;
  late Map<String, int> gcolors;
  late String _snap; // note as saved, to detect real changes
  String panel = ''; // open panel: '', 'color' or 'format'
  bool finding = false; // "find in note" bar
  final findCtl = TextEditingController();
  final editorFocus = FocusNode();
  late final String _orig; // the note as it was when opened
  late final bool _existed; // was it already saved before this session?

  static const fonts = ['Roboto', 'serif', 'monospace', 'cursive', 'Arial'];
  static const sizes = <double>[10, 12, 14, 16, 18, 20, 24, 28, 32, 40];
  static const backgrounds = {
    'Default': 0,
    'Cream': 0xFFFFF8E1,
    'Mint': 0xFFE8F5E9,
    'Sky': 0xFFE3F2FD,
    'Rose': 0xFFFCE4EC,
    'Lavender': 0xFFEDE7F6,
    'Peach': 0xFFFFE0B2,
    'Grey': 0xFFEEEEEE,
  };

  @override
  void initState() {
    super.initState();
    _orig = jsonEncode(widget.note.toJson());
    _existed = noteExists(widget.note.id);
    presets = loadPresets();
    active = loadActivePreset();
    if (!presets.containsKey(active)) active = presets.keys.first;
    groups = loadGroups();
    gcolors = loadGroupColors();
    if (!groups.contains(widget.note.group)) widget.note.group = '';
    ctl.load(widget.note.runs);
    _snap = jsonEncode(widget.note.toJson());
    WidgetsBinding.instance.addObserver(this);
    title.addListener(_schedule);
    ctl.addListener(() {
      if (mounted) setState(() {}); // keeps the toolbar in sync with the cursor
      _schedule();
    });
  }

  /// Saves only when something changed (so empty new notes are never created).
  void save() {
    if (_gone) return;
    final n = widget.note;
    n.title = title.text;
    n.runs = ctl.runs();
    if (jsonEncode(n.toJson()) == _snap) return;
    n.modified = DateTime.now().millisecondsSinceEpoch;
    saveNote(n);
    _snap = jsonEncode(n.toJson());
  }

  // ---- autosave: 1 s after you stop typing, and when the app goes to background ----

  void _schedule() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 1), save);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) save();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ctl.dispose();
    title.dispose();
    findCtl.dispose();
    editorFocus.dispose();
    super.dispose();
  }

  // ---- color ----

  Future<Color?> pickColor(Color start) => pickColorDialog(context, start);

  Future<void> addColor() async {
    final c = await pickColor(Color(ctl.current.color));
    if (c == null) return;
    final list = presets[active]!;
    if (!list.contains(c.value)) list.add(c.value);
    savePresets(presets);
    ctl.apply((s) => s.copy(color: c.value));
    setState(() {});
  }

  Future<void> onPreset(String? v) async {
    if (v == null) return;
    if (v == _newPreset) {
      final n = await askText(context, 'New preset name');
      if (n == null || n.isEmpty || presets.containsKey(n)) return;
      presets[n] = [];
      active = n;
    } else if (v == _delPreset) {
      if (!await confirm(context, 'Delete preset "$active"?')) return;
      presets.remove(active);
      active = presets.keys.first;
    } else {
      active = v;
    }
    savePresets(presets);
    saveActivePreset(active);
    setState(() {});
  }

  /// Undoes everything done since the note was opened (also what autosave saved).
  Future<void> discardAndClose() async {
    final n = widget.note;
    n.title = title.text;
    n.runs = ctl.runs();
    final changed = jsonEncode(n.toJson()) != _snap || _snap != _orig;
    if (changed &&
        !await confirm(context, 'Discard everything you changed since opening this note?',
            yes: 'Discard')) {
      return;
    }
    _timer?.cancel();
    _gone = true; // stops autosave and the save on exit
    if (_existed) {
      saveNote(Note.fromJson(jsonDecode(_orig)));
    } else {
      purgeNote(n.id);
    }
    if (mounted) Navigator.pop(context);
  }

  // ---- find in note ----

  Widget findBar() {
    final n = ctl.matchCount;
    return Material(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: findCtl,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Find in note', border: InputBorder.none),
              onChanged: ctl.setFind,
            ),
          ),
          Text(n == 0 ? '0/0' : '${ctl.findIndex + 1}/$n',
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
          IconButton(
              tooltip: 'Previous',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: n == 0
                  ? null
                  : () {
                      ctl.findStep(-1);
                      editorFocus.requestFocus();
                    }),
          IconButton(
              tooltip: 'Next',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: n == 0
                  ? null
                  : () {
                      ctl.findStep(1);
                      editorFocus.requestFocus();
                    }),
          IconButton(
              tooltip: 'Close',
              icon: const Icon(Icons.close),
              onPressed: () {
                findCtl.clear();
                ctl.setFind('');
                setState(() => finding = false);
              }),
        ]),
      ),
    );
  }

  // ---- photos and drawings (stored as files, the note keeps their names) ----

  void snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> addPhotos(ImageSource src) async {
    try {
      final picker = ImagePicker();
      final files = <XFile>[];
      if (src == ImageSource.gallery) {
        files.addAll(await picker.pickMultiImage(maxWidth: 1600, imageQuality: 85));
      } else {
        final x = await picker.pickImage(source: src, maxWidth: 1600, imageQuality: 85);
        if (x != null) files.add(x);
      }
      for (final x in files) {
        var ext = x.path.split('.').last.toLowerCase();
        if (!const ['png', 'jpg', 'jpeg', 'webp'].contains(ext)) ext = 'jpg';
        final name = newImageName('img', ext);
        await File(x.path).copy(imagePath(name));
        widget.note.images.add(name);
      }
      if (files.isNotEmpty) {
        setState(() {});
        _schedule();
      }
    } catch (e) {
      snack('Could not add photo: $e');
    }
  }

  /// Opens the handwriting page; [editing] is an existing drawing to continue.
  Future<void> drawNote({String? editing}) async {
    try {
      var initial = <Stroke>[];
      if (editing != null) {
        final f = File(imagePath(strokesName(editing)));
        if (f.existsSync()) {
          initial = (jsonDecode(f.readAsStringSync()) as List).map((e) => Stroke.fromJson(e)).toList();
        }
      }
      final result = await Navigator.push<List<Stroke>>(
          context, MaterialPageRoute(builder: (_) => DrawPage(initial: initial, paper: widget.note.bg)));
      if (result == null || (result.isEmpty && editing == null)) return;
      final name = newImageName('draw', 'png'); // a new file each time, so "close without saving" can go back
      final paper = widget.note.bg == 0 ? Colors.white : Color(widget.note.bg);
      File(imagePath(name)).writeAsBytesSync(await renderDrawing(result, paper));
      File(imagePath(strokesName(name)))
          .writeAsStringSync(jsonEncode(result.map((s) => s.toJson()).toList()));
      final imgs = widget.note.images;
      final i = editing == null ? -1 : imgs.indexOf(editing);
      setState(() => i >= 0 ? imgs[i] = name : imgs.add(name));
      _schedule();
    } catch (e) {
      snack('Could not save drawing: $e');
    }
  }

  void viewImage(String name) => Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => Scaffold(
                backgroundColor: Colors.black,
                appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
                body: Center(
                    child: InteractiveViewer(maxScale: 5, child: Image.file(File(imagePath(name))))),
              )));

  Future<void> attachmentMenu(int i) async {
    final name = widget.note.images[i];
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (s) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Save to device'),
              onTap: () => Navigator.pop(s, 'save')),
          ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove from note'),
              onTap: () => Navigator.pop(s, 'remove')),
        ]),
      ),
    );
    if (v == 'remove') {
      setState(() => widget.note.images.removeAt(i)); // the file is cleaned up later
      _schedule();
    } else if (v == 'save') {
      try {
        final p = await saveToDevice(name, File(imagePath(name)).readAsBytesSync());
        if (p != null) snack('Saved $name');
      } catch (e) {
        snack('Could not save: $e');
      }
    }
  }

  Widget attachments() {
    final imgs = widget.note.images;
    return SizedBox(
      height: 108,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: imgs.length,
        itemBuilder: (_, i) {
          final name = imgs[i];
          return GestureDetector(
            onTap: () => isDrawing(name) ? drawNote(editing: name) : viewImage(name),
            onLongPress: () => attachmentMenu(i),
            child: Container(
              width: 100,
              margin: const EdgeInsets.all(4),
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(8)),
              child: Stack(fit: StackFit.expand, children: [
                Image.file(File(imagePath(name)),
                    fit: BoxFit.cover,
                    cacheWidth: 300,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
                if (isDrawing(name))
                  const Positioned(right: 4, bottom: 4, child: Icon(Icons.draw, size: 16)),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---- export: save to a device folder, or share ----

  Future<void> doExport(String kind, {required bool toDevice}) async {
    save();
    final n = widget.note, name = safeName(n.title);
    final String file, mime;
    final List<int> bytes;
    switch (kind) {
      case 'docx':
        file = '$name.docx';
        bytes = await toDocx(n);
        mime = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        file = '$name.txt';
        bytes = utf8.encode(n.plain);
        mime = 'text/plain';
      default:
        file = '${name}_color.txt';
        bytes = utf8.encode(toColorTxt(n.runs));
        mime = 'text/plain';
    }
    try {
      if (toDevice) {
        final path = await saveToDevice(file, bytes);
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved $file')));
        }
      } else {
        await shareFile(file, bytes, mime);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    }
  }

  void exportSheet() {
    save();
    showModalBottomSheet(
      context: context,
      builder: (sheet) {
        Widget row(IconData icon, String label, String kind) => ListTile(
              leading: Icon(icon),
              title: Text(label),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Save to device',
                    icon: const Icon(Icons.save_alt),
                    onPressed: () {
                      Navigator.pop(sheet);
                      doExport(kind, toDevice: true);
                    }),
                IconButton(
                    tooltip: 'Share',
                    icon: const Icon(Icons.share),
                    onPressed: () {
                      Navigator.pop(sheet);
                      doExport(kind, toDevice: false);
                    }),
              ]),
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            row(Icons.description_outlined, '.docx (colors, fonts)', 'docx'),
            row(Icons.notes, '.txt (plain)', 'txt'),
            row(Icons.palette_outlined, '.txt (color tags)', 'ctxt'),
          ]),
        );
      },
    );
  }

  void onMenu(String v) {
    final n = widget.note;
    switch (v) {
      case 'export':
        exportSheet();
      case 'pin':
        setState(() => n.pinned = !n.pinned);
      case 'samsung':
        // .sdocx is Samsung's private format; share sheet -> Samsung Notes imports text.
        Share.share('${title.text}\n\n${ctl.text}');
      case 'parse':
        ctl.replaceRuns(fromColorTxt(ctl.text));
      case 'find':
        setState(() => finding = true);
      case 'discard':
        discardAndClose();
      case 'trash':
        n.deletedAt = DateTime.now().millisecondsSinceEpoch;
        n.pinned = false;
        save();
        _gone = true;
        Navigator.pop(context);
    }
  }

  // ---- UI pieces ----

  String counts() {
    final t = ctl.text;
    final words = RegExp(r'\S+').allMatches(t).length;
    return '$words ${words == 1 ? 'word' : 'words'} · ${t.length} chars';
  }

  String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Note background selector.
  Widget backgroundSelector() => PopupMenuButton<int>(
        tooltip: 'Background',
        icon: const Icon(Icons.format_color_fill),
        onSelected: (v) async {
          if (v == -1) {
            final n = widget.note;
            final c = await pickColor(Color(n.bg == 0 ? 0xFFFFFFFF : n.bg));
            if (c != null) setState(() => n.bg = c.value);
          } else {
            setState(() => widget.note.bg = v);
          }
        },
        itemBuilder: (_) => [
          for (final b in backgrounds.entries)
            PopupMenuItem<int>(
              value: b.value,
              child: Row(children: [
                Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                        color: b.value == 0 ? Colors.white : Color(b.value),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.grey))),
                const SizedBox(width: 12),
                Text(b.key),
              ]),
            ),
          const PopupMenuItem<int>(
            value: -1,
            child: Row(children: [Icon(Icons.colorize, size: 20), SizedBox(width: 12), Text('Custom…')]),
          ),
        ],
      );

  /// Color-coded group button: shows only the group's color, names appear in the menu.
  Widget groupSelector() {
    final g = widget.note.group;
    Color colorOf(String x) => Color(gcolors[x] ?? groupPalette[0]);
    return PopupMenuButton<String>(
      tooltip: 'Group',
      icon: Icon(g.isEmpty ? Icons.folder_outlined : Icons.folder,
          color: g.isEmpty ? null : colorOf(g)),
      onSelected: (v) => setState(() => widget.note.group = v),
      itemBuilder: (_) => [
        const PopupMenuItem<String>(
          value: '',
          child: Row(children: [Icon(Icons.folder_off_outlined), SizedBox(width: 12), Text('No group')]),
        ),
        for (final x in groups)
          PopupMenuItem<String>(
            value: x,
            child: Row(children: [
              Icon(Icons.folder, color: colorOf(x)),
              const SizedBox(width: 12),
              Flexible(child: Text(x, overflow: TextOverflow.ellipsis)),
            ]),
          ),
      ],
    );
  }

  Widget palettePanel(TS cur) {
    final colors = presets[active]!;
    Widget swatch(
            {required Color color,
            required bool on,
            VoidCallback? tap,
            VoidCallback? hold,
            Widget? child}) =>
        GestureDetector(
          onTap: tap,
          onLongPress: hold,
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: on ? Colors.blue : Colors.grey, width: on ? 3 : 1)),
            child: child,
          ),
        );
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButton<String>(
                value: active,
                isDense: true,
                underline: const SizedBox(),
                items: [
                  for (final k in presets.keys) DropdownMenuItem(value: k, child: Text(k)),
                  const DropdownMenuItem(value: _newPreset, child: Text('＋ New preset…')),
                  if (presets.length > 1)
                    DropdownMenuItem(value: _delPreset, child: Text('Delete "$active"')),
                ],
                onChanged: onPreset,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 110),
                child: SingleChildScrollView(
                  child: Wrap(children: [
                    for (final c in colors)
                      swatch(
                        color: Color(c),
                        on: cur.color == c,
                        tap: () => ctl.apply((s) => s.copy(color: c)),
                        hold: () => setState(() {
                          colors.remove(c);
                          savePresets(presets);
                        }),
                      ),
                    swatch(
                        color: Colors.transparent,
                        on: false,
                        tap: addColor,
                        child: const Icon(Icons.add, size: 18)),
                  ]),
                ),
              ),
            ]),
      ),
    );
  }

  static const highlights = [0xFFFFF59D, 0xFFA5D6A7, 0xFF81D4FA, 0xFFF48FB1, 0xFFFFCC80, 0xFFCE93D8];

  Widget formatPanel(TS cur) {
    final primary = Theme.of(context).colorScheme.primary;
    Widget tog(IconData icon, String tip, bool on, TS Function(TS) f) => IconButton(
          tooltip: tip,
          icon: Icon(icon, color: on ? primary : null),
          style: on ? IconButton.styleFrom(backgroundColor: primary.withAlpha(40)) : null,
          onPressed: () => ctl.apply(f),
        );
    Widget dot(Color? c, bool on, VoidCallback tap, {Widget? child}) => GestureDetector(
          onTap: tap,
          child: Container(
            width: 32,
            height: 32,
            margin: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(color: on ? Colors.blue : Colors.grey, width: on ? 3 : 1)),
            child: child,
          ),
        );
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            DropdownButton<String>(
              value: cur.font,
              isDense: true,
              underline: const SizedBox(),
              items: [
                for (final f in {...fonts, cur.font})
                  DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f))),
              ],
              onChanged: (v) => ctl.apply((s) => s.copy(font: v)),
            ),
            const SizedBox(width: 24),
            DropdownButton<double>(
              value: cur.size,
              isDense: true,
              underline: const SizedBox(),
              items: [
                for (final z in (<double>{...sizes, cur.size}.toList()..sort()))
                  DropdownMenuItem(value: z, child: Text(fmt(z))),
              ],
              onChanged: (v) => ctl.apply((s) => s.copy(size: v)),
            ),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            tog(Icons.format_bold, 'Bold', cur.bold, (s) => s.copy(bold: !s.bold)),
            tog(Icons.format_italic, 'Italic', cur.italic, (s) => s.copy(italic: !s.italic)),
            tog(Icons.format_underlined, 'Underline', cur.underline, (s) => s.copy(underline: !s.underline)),
            tog(Icons.format_strikethrough, 'Strikethrough', cur.strike, (s) => s.copy(strike: !s.strike)),
          ]),
          const Text('Highlight', style: TextStyle(fontSize: 11, color: Colors.grey)),
          Wrap(children: [
            dot(null, cur.highlight == 0, () => ctl.apply((s) => s.copy(highlight: 0)),
                child: const Icon(Icons.format_color_reset, size: 18)),
            for (final h in highlights)
              dot(Color(h), cur.highlight == h, () => ctl.apply((s) => s.copy(highlight: h))),
            dot(null, false, () async {
              final c = await pickColor(Color(cur.highlight == 0 ? 0xFFFFF59D : cur.highlight));
              if (c != null) ctl.apply((s) => s.copy(highlight: c.value));
            }, child: const Icon(Icons.add, size: 18)),
          ]),
        ]),
      ),
    );
  }

  /// Icon-only bottom bar (all icons fit on screen, no scrolling).
  Widget bottomBar(TS cur) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: ctl.canUndo ? ctl.undo : null),
            IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: ctl.canRedo ? ctl.redo : null),
            IconButton(
              tooltip: 'Text style',
              icon: Icon(Icons.text_format, color: panel == 'format' ? primary : null),
              onPressed: () => setState(() => panel = panel == 'format' ? '' : 'format'),
            ),
            IconButton(
              tooltip: 'Color',
              icon: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: Color(cur.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: panel == 'color' ? primary : Colors.grey, width: 2)),
              ),
              onPressed: () => setState(() => panel = panel == 'color' ? '' : 'color'),
            ),
            PopupMenuButton<String>(
              tooltip: 'Insert',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onSelected: (v) {
                if (v == 'gallery') addPhotos(ImageSource.gallery);
                if (v == 'camera') addPhotos(ImageSource.camera);
                if (v == 'draw') drawNote();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'gallery',
                    child: Row(children: [Icon(Icons.photo_library_outlined), SizedBox(width: 12), Text('Photo from gallery')])),
                PopupMenuItem(
                    value: 'camera',
                    child: Row(children: [Icon(Icons.photo_camera_outlined), SizedBox(width: 12), Text('Take a photo')])),
                PopupMenuItem(
                    value: 'draw',
                    child: Row(children: [Icon(Icons.draw_outlined), SizedBox(width: 12), Text('Handwriting / drawing')])),
              ],
            ),
            PopupMenuButton<String>(
              tooltip: 'List',
              icon: const Icon(Icons.format_list_bulleted),
              onSelected: (k) => k == 'toggle' ? ctl.toggleCheck() : ctl.setList(k),
              itemBuilder: (_) => const [
                PopupMenuItem(
                    value: 'none',
                    child: Row(children: [Icon(Icons.format_clear), SizedBox(width: 12), Text('No list')])),
                PopupMenuItem(
                    value: 'bullet',
                    child: Row(children: [Icon(Icons.format_list_bulleted), SizedBox(width: 12), Text('Bullets')])),
                PopupMenuItem(
                    value: 'number',
                    child: Row(children: [Icon(Icons.format_list_numbered), SizedBox(width: 12), Text('Numbering')])),
                PopupMenuItem(
                    value: 'check',
                    child: Row(children: [Icon(Icons.check_box_outlined), SizedBox(width: 12), Text('Checklist')])),
                PopupMenuItem(
                    value: 'toggle',
                    child: Row(children: [Icon(Icons.done_all), SizedBox(width: 12), Text('Check / uncheck line')])),
              ],
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cur = ctl.current;
    final n = widget.note;
    ctl.bg = n.bg; // lets the editor show readable text on dark backgrounds
    return PopScope(
      onPopInvokedWithResult: (_, __) => save(),
      child: Scaffold(
        backgroundColor: n.bg == 0 ? null : Color(n.bg),
        appBar: AppBar(
          title: TextField(
              controller: title,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none)),
          actions: [
            backgroundSelector(),
            groupSelector(),
            PopupMenuButton<String>(
              onSelected: onMenu,
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'find', child: Text('Find in note')),
                const PopupMenuItem(value: 'export', child: Text('Export…')),
                PopupMenuItem(value: 'pin', child: Text(n.pinned ? 'Unpin' : 'Pin to top')),
                const PopupMenuItem(value: 'samsung', child: Text('Send to Samsung Notes')),
                const PopupMenuItem(value: 'parse', child: Text('Parse <#color> tags in text')),
                const PopupMenuItem(value: 'trash', child: Text('Move to trash')),
                const PopupMenuItem(value: 'discard', child: Text('Close without saving')),
              ],
            ),
          ],
        ),
        body: Column(children: [
          if (finding) findBar(),
          if (widget.note.images.isNotEmpty) attachments(),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: ctl,
                  focusNode: editorFocus,
                  inputFormatters: [ListContinue()],
                  cursorColor: (n.bg != 0 && Color(n.bg).computeLuminance() >= 0.4)
                      ? Colors.black87
                      : null,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration:
                      const InputDecoration(border: InputBorder.none, hintText: 'Write here…')),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 14, bottom: 2),
              child: Text(counts(), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ),
          if (panel == 'color') palettePanel(cur),
          if (panel == 'format') formatPanel(cur),
          bottomBar(cur),
        ]),
      ),
    );
  }
}
