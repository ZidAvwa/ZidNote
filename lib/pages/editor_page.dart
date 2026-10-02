import 'dart:convert';
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
      if (mounted) setState(() {}); // keeps the selectors in sync with the cursor
    });
  }

  void save() {
    widget.note.title = title.text;
    widget.note.runs = ctl.runs();
    saveNote(widget.note);
  }

  Future<void> addColor() async {
    Color c = Color(ctl.current.color);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: c,
            onColorChanged: (v) => c = v,
            enableAlpha: false,
            hexInputBar: true, // type a color code at the bottom
            portraitOnly: true,
            labelTypes: const [],
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

  /// A labeled dropdown selector.
  Widget sel<T>(String label, T value, List<DropdownMenuItem<T>> items, ValueChanged<T?> onChanged) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          DropdownButton<T>(
              value: value,
              items: items,
              onChanged: onChanged,
              isDense: true,
              underline: const SizedBox()),
        ]),
      );

  String num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  @override
  Widget build(BuildContext context) {
    final cur = ctl.current;
    final fontList = {...fonts, cur.font}.toList();
    final sizeList = <double>{...sizes, cur.size}.toList()..sort();
    final colors = presets[active]!;

    return PopScope(
      onPopInvokedWithResult: (_, __) => save(),
      child: Scaffold(
        appBar: AppBar(
          title: TextField(
              controller: title,
              decoration: const InputDecoration(hintText: 'Title', border: InputBorder.none)),
          actions: [
            PopupMenuButton<String>(
              onSelected: export,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'docx', child: Text('Save as .docx')),
                PopupMenuItem(value: 'txt', child: Text('Save as .txt (plain)')),
                PopupMenuItem(value: 'ctxt', child: Text('Save as .txt (with colors)')),
                PopupMenuItem(value: 'samsung', child: Text('Send to Samsung Notes')),
                PopupMenuItem(value: 'parse', child: Text('Parse <#color> tags in text')),
              ],
            )
          ],
        ),
        body: Column(children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              sel<String>('Group', widget.note.group, [
                const DropdownMenuItem(value: '', child: Text('No group')),
                for (final g in groups) DropdownMenuItem(value: g, child: Text(g)),
              ], (v) => setState(() => widget.note.group = v ?? '')),
              sel<String>('Font', cur.font, [
                for (final f in fontList) DropdownMenuItem(value: f, child: Text(f)),
              ], (v) => ctl.apply((s) => s.copy(font: v))),
              sel<double>('Size', cur.size, [
                for (final z in sizeList) DropdownMenuItem(value: z, child: Text(num(z))),
              ], (v) => ctl.apply((s) => s.copy(size: v))),
              sel<bool>('Style', cur.bold, const [
                DropdownMenuItem(value: false, child: Text('Normal')),
                DropdownMenuItem(value: true, child: Text('Bold')),
              ], (v) => ctl.apply((s) => s.copy(bold: v))),
              sel<String>('Color preset', active, [
                for (final k in presets.keys) DropdownMenuItem(value: k, child: Text(k)),
                const DropdownMenuItem(value: _newPreset, child: Text('＋ New preset…')),
                if (presets.length > 1)
                  DropdownMenuItem(value: _delPreset, child: Text('Delete "$active"')),
              ], onPreset),
            ]),
          ),
          SizedBox(
            height: 48,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final c in colors)
                GestureDetector(
                  onTap: () => ctl.apply((s) => s.copy(color: c)),
                  onLongPress: () => setState(() {
                    colors.remove(c);
                    savePresets(presets);
                  }),
                  child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: cur.color == c ? Colors.blue : Colors.grey,
                              width: cur.color == c ? 3 : 1))),
                ),
              GestureDetector(
                onTap: addColor,
                child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, border: Border.all(color: Colors.grey)),
                    child: const Icon(Icons.add, size: 18)),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                  controller: ctl,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration:
                      const InputDecoration(border: InputBorder.none, hintText: 'Write here…')),
            ),
          ),
        ]),
      ),
    );
  }
}
