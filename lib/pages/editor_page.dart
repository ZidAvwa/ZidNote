import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/note.dart';
import '../services/exporters.dart';
import '../services/storage.dart';
import '../widgets/dialogs.dart';
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
  bool showPalette = false;

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
    super.dispose();
  }

  // ---- color ----

  /// Color picker dialog: RGB / HSV / HSL value changers plus a hex code input at the bottom.
  Future<Color?> pickColor(Color start) async {
    Color c = start;
    final w = min(300.0, MediaQuery.of(context).size.width - 120);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: c,
            onColorChanged: (v) => c = v,
            enableAlpha: false,
            hexInputBar: true,
            portraitOnly: true,
            colorPickerWidth: w,
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('OK'))],
      ),
    );
    return ok == true ? c : null;
  }

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

  // ---- export: save to a device folder, or share ----

  Future<void> doExport(String kind, {required bool toDevice}) async {
    save();
    final n = widget.note, name = safeName(n.title);
    final String file, mime;
    final List<int> bytes;
    switch (kind) {
      case 'docx':
        file = '$name.docx';
        bytes = toDocx(n);
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
      case 'trash':
        n.deletedAt = DateTime.now().millisecondsSinceEpoch;
        n.pinned = false;
        save();
        _gone = true;
        Navigator.pop(context);
    }
  }

  // ---- UI pieces ----

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

  /// Icon-only bottom bar (all icons fit on screen, no scrolling).
  Widget bottomBar(TS cur) {
    final fontList = {...fonts, cur.font}.toList();
    final sizeList = <double>{...sizes, cur.size}.toList()..sort();
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
            PopupMenuButton<String>(
              tooltip: 'Font',
              icon: const Icon(Icons.font_download_outlined),
              onSelected: (f) => ctl.apply((s) => s.copy(font: f)),
              itemBuilder: (_) => [
                for (final f in fontList)
                  CheckedPopupMenuItem<String>(
                      value: f,
                      checked: f == cur.font,
                      child: Text(f, style: TextStyle(fontFamily: f))),
              ],
            ),
            PopupMenuButton<double>(
              tooltip: 'Size',
              icon: const Icon(Icons.format_size),
              onSelected: (z) => ctl.apply((s) => s.copy(size: z)),
              itemBuilder: (_) => [
                for (final z in sizeList)
                  CheckedPopupMenuItem<double>(
                      value: z, checked: z == cur.size, child: Text(fmt(z))),
              ],
            ),
            IconButton(
              tooltip: 'Bold',
              icon: Icon(Icons.format_bold, color: cur.bold ? primary : null),
              onPressed: () => ctl.apply((s) => s.copy(bold: !s.bold)),
            ),
            IconButton(
              tooltip: 'Color',
              icon: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: Color(cur.color),
                    shape: BoxShape.circle,
                    border: Border.all(color: showPalette ? primary : Colors.grey, width: 2)),
              ),
              onPressed: () => setState(() => showPalette = !showPalette),
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
                const PopupMenuItem(value: 'export', child: Text('Export…')),
                PopupMenuItem(value: 'pin', child: Text(n.pinned ? 'Unpin' : 'Pin to top')),
                const PopupMenuItem(value: 'samsung', child: Text('Send to Samsung Notes')),
                const PopupMenuItem(value: 'parse', child: Text('Parse <#color> tags in text')),
                const PopupMenuItem(value: 'trash', child: Text('Move to trash')),
              ],
            ),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: ctl,
                  inputFormatters: [ListContinue()],
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration:
                      const InputDecoration(border: InputBorder.none, hintText: 'Write here…')),
            ),
          ),
          if (showPalette) palettePanel(cur),
          bottomBar(cur),
        ]),
      ),
    );
  }
}
