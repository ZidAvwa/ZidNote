import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:share_plus/share_plus.dart';
import '../models/note.dart';
import '../services/exporters.dart';
import '../services/storage.dart';
import '../widgets/rich_controller.dart';

class EditorPage extends StatefulWidget {
  final Note note;
  const EditorPage({super.key, required this.note});
  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  final ctl = RichCtl();
  late final title = TextEditingController(text: widget.note.title);
  List<int> palette = loadPalette();
  static const fonts = ['Roboto', 'serif', 'monospace', 'cursive', 'Arial'];

  @override
  void initState() {
    super.initState();
    ctl.load(widget.note.runs);
  }

  void save() {
    widget.note.title = title.text;
    widget.note.runs = ctl.runs();
    saveNote(widget.note);
  }

  Future<void> addColor() async {
    Color c = Colors.red;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        content: SingleChildScrollView(
            child: ColorPicker(pickerColor: c, onColorChanged: (v) => c = v, enableAlpha: false)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save color'))
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        if (!palette.contains(c.value)) palette.add(c.value);
        savePalette(palette);
      });
      ctl.apply((s) => s.copy(color: c.value));
    }
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
      case 'import':
        setState(() => ctl.load(fromColorTxt(n.plain)));
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
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
                  PopupMenuItem(value: 'import', child: Text('Parse <#color> tags in text')),
                ],
              )
            ],
          ),
          body: Column(children: [
            SizedBox(
              height: 52,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (final c in palette)
                  GestureDetector(
                    onTap: () => ctl.apply((s) => s.copy(color: c)),
                    onLongPress: () => setState(() {
                      palette.remove(c);
                      savePalette(palette);
                    }),
                    child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color: Color(c),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey))),
                  ),
                IconButton(onPressed: addColor, icon: const Icon(Icons.add_circle_outline)),
                IconButton(
                    onPressed: () => ctl.apply((s) => s.copy(bold: !s.bold)),
                    icon: const Icon(Icons.format_bold)),
                IconButton(
                    onPressed: () => ctl.apply((s) => s.copy(size: s.size + 2)),
                    icon: const Icon(Icons.text_increase)),
                IconButton(
                    onPressed: () => ctl.apply((s) => s.copy(size: (s.size - 2).clamp(8, 80))),
                    icon: const Icon(Icons.text_decrease)),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.font_download_outlined),
                  onSelected: (f) => ctl.apply((s) => s.copy(font: f)),
                  itemBuilder: (_) => [for (final f in fonts) PopupMenuItem(value: f, child: Text(f))],
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
                    decoration: const InputDecoration(border: InputBorder.none, hintText: 'Write here…')),
              ),
            ),
          ]),
        ),
      );
}
