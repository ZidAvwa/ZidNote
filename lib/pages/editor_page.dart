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

class _EditorPageState extends State<EditorPage> {
  final ctl = RichCtl();
  late final title = TextEditingController(text: widget.note.title);
  late Map<String, List<int>> presets;
  late String active;
  late List<String> groups;
  bool showPalette = false;

  static const fonts = ['Roboto', 'serif', 'monospace', 'cursive', 'Arial'];
  static const sizes = <double>[10, 12, 14, 16, 18, 20, 24, 28, 32, 40];

  @override
  void initState() {
    super.initState();
    presets = loadPresets();
    active = loadActivePreset();
    if (!presets.containsKey(active)) active = presets.keys.first;
    groups = loadGroups();
    if (!groups.contains(widget.note.group)) widget.note.group = '';
    ctl.load(widget.note.runs);
    ctl.addListener(() {
      if (mounted) setState(() {}); // keeps the toolbar in sync with the cursor
    });
  }

  void save() {
    widget.note.title = title.text;
    widget.note.runs = ctl.runs();
    saveNote(widget.note);
  }

  // ---- color ----

  Future<void> addColor() async {
    Color c = Color(ctl.current.color);
    final w = min(300.0, MediaQuery.of(context).size.width - 120);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: SingleChildScrollView(
          // Default RGB / HSV / HSL value changers stay; the hex code input is at the bottom.
          child: ColorPicker(
            pickerColor: c,
            onColorChanged: (v) => c = v,
            enableAlpha: false,
            hexInputBar: true,
            portraitOnly: true,
            colorPickerWidth: w,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Add color'))
        ],
      ),
    );
    if (ok != true) return;
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

  // ---- export ----

  Future<void> export(String kind) async {
    save();
    final n = widget.note, name = safeName(n.title);
    switch (kind) {
      case 'docx':
        await shareFile('$name.docx', toDocx(n),
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document');
      case 'txt':
        await shareFile('$name.txt', utf8.encode(n.plain), 'text/plain');
      case 'ctxt':
        await shareFile('$name.txt', utf8.encode(toColorTxt(n.runs)), 'text/plain');
      case 'samsung':
        // .sdocx is Samsung's private format; share sheet -> Samsung Notes imports text.
        await Share.share('${n.title}\n\n${n.plain}');
      case 'parse':
        setState(() => ctl.load(fromColorTxt(n.plain)));
    }
  }

  // ---- UI pieces ----

  String fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Group selector, placed beside the triple-dots menu.
  Widget groupSelector() => SizedBox(
        width: 120,
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: widget.note.group,
            isExpanded: true,
            icon: const Icon(Icons.folder_outlined, size: 20),
            items: [
              const DropdownMenuItem(
                  value: '', child: Text('No group', overflow: TextOverflow.ellipsis)),
              for (final g in groups)
                DropdownMenuItem(value: g, child: Text(g, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => widget.note.group = v ?? ''),
          ),
        ),
      );

  Widget palettePanel(TS cur) {
    final colors = presets[active]!;
    Widget swatch({required Color color, required bool on, VoidCallback? tap, VoidCallback? hold, Widget? child}) =>
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
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    return PopScope(
      onPopInvokedWithResult: (_, __) => save(),
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
              controller: title,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none)),
          actions: [
            groupSelector(),
            PopupMenuButton<String>(
              onSelected: export,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'docx', child: Text('Save as .docx')),
                PopupMenuItem(value: 'txt', child: Text('Save as .txt (plain)')),
                PopupMenuItem(value: 'ctxt', child: Text('Save as .txt (with colors)')),
                PopupMenuItem(value: 'samsung', child: Text('Send to Samsung Notes')),
                PopupMenuItem(value: 'parse', child: Text('Parse <#color> tags in text')),
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
