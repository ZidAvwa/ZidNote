import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../models/stroke.dart';
import '../services/storage.dart';
import 'dialogs.dart';

/// Renders strokes to PNG bytes (1080 x 1440) on a [paper] background.
Future<List<int>> renderDrawing(List<Stroke> strokes, Color paper) async {
  const w = 1080.0, h = 1440.0;
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, const Rect.fromLTWH(0, 0, w, h));
  c.drawRect(const Rect.fromLTWH(0, 0, w, h), Paint()..color = paper);
  paintStrokes(c, strokes, w);
  final img = await rec.endRecording().toImage(w.toInt(), h.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Full-screen handwriting page. Pops with the strokes when "done" is pressed.
class DrawPage extends StatefulWidget {
  final List<Stroke> initial;
  final int paper; // note background color, 0 = white
  const DrawPage({super.key, this.initial = const [], this.paper = 0});
  @override
  State<DrawPage> createState() => _DrawPageState();
}

class _DrawPageState extends State<DrawPage> {
  late List<Stroke> strokes = List.of(widget.initial);
  final List<List<Stroke>> _undo = [], _redo = [];
  Stroke? live;
  List<Stroke>? _eraseBase;
  String tool = 'pen'; // pen, highlighter, eraser
  int color = 0xFF000000;
  double penW = 0.006;
  bool showColors = false;
  bool dirty = false;
  double _w = 1;
  int? _pid;
  late final List<int> palette = () {
    final p = loadPresets();
    return List.of(p[loadActivePreset()] ?? p.values.first);
  }();

  Offset _n(Offset p) => Offset(p.dx / _w, p.dy / _w);

  void _down(PointerDownEvent e) {
    if (_pid != null) return;
    _pid = e.pointer;
    if (tool == 'eraser') {
      _eraseBase = List.of(strokes);
      _erase(e.localPosition);
    } else {
      setState(() => live = Stroke([_n(e.localPosition)], color, penW, tool == 'highlighter'));
    }
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pid) return;
    if (tool == 'eraser') {
      _erase(e.localPosition);
    } else if (live != null) {
      setState(() => live!.pts.add(_n(e.localPosition)));
    }
  }

  void _up(PointerEvent e) {
    if (e.pointer != _pid) return;
    _pid = null;
    _eraseBase = null;
    final s = live;
    if (s != null) {
      setState(() {
        _undo.add(List.of(strokes));
        _redo.clear();
        strokes = [...strokes, s];
        live = null;
        dirty = true;
      });
    }
  }

  // The eraser removes whole strokes it touches.
  void _erase(Offset p) {
    final c = _n(p);
    final hit = strokes.where((s) => s.pts.any((q) => (q - c).distance < 0.035)).toSet();
    if (hit.isEmpty) return;
    setState(() {
      if (_eraseBase != null) {
        _undo.add(_eraseBase!);
        _redo.clear();
        _eraseBase = null;
      }
      strokes = strokes.where((s) => !hit.contains(s)).toList();
      dirty = true;
    });
  }

  void undo() {
    if (_undo.isEmpty) return;
    setState(() {
      _redo.add(List.of(strokes));
      strokes = _undo.removeLast();
      dirty = true;
    });
  }

  void redo() {
    if (_redo.isEmpty) return;
    setState(() {
      _undo.add(List.of(strokes));
      strokes = _redo.removeLast();
      dirty = true;
    });
  }

  Future<void> clearAll() async {
    if (strokes.isEmpty || !await confirm(context, 'Clear the whole page?', yes: 'Clear')) return;
    setState(() {
      _undo.add(List.of(strokes));
      _redo.clear();
      strokes = [];
      dirty = true;
    });
  }

  Widget colorPanel() => Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(children: [
            for (final c in palette)
              GestureDetector(
                onTap: () => setState(() => color = c),
                child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: color == c ? Colors.blue : Colors.grey, width: color == c ? 3 : 1)),
                ),
              ),
            GestureDetector(
              onTap: () async {
                final c = await pickColorDialog(context, Color(color));
                if (c != null) {
                  setState(() {
                    palette.add(c.value);
                    color = c.value;
                  });
                }
              },
              child: Container(
                  width: 32,
                  height: 32,
                  margin: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, border: Border.all(color: Colors.grey)),
                  child: const Icon(Icons.add, size: 18)),
            ),
          ]),
        ),
      );

  Widget bottomBar() {
    final primary = Theme.of(context).colorScheme.primary;
    Widget toolBtn(IconData icon, String tip, String v) => IconButton(
          tooltip: tip,
          icon: Icon(icon, color: tool == v ? primary : null),
          onPressed: () => setState(() => tool = v),
        );
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            toolBtn(Icons.edit, 'Pen', 'pen'),
            toolBtn(Icons.border_color, 'Highlighter', 'highlighter'),
            toolBtn(Icons.backspace_outlined, 'Eraser', 'eraser'),
            PopupMenuButton<double>(
              tooltip: 'Thickness',
              icon: const Icon(Icons.line_weight),
              onSelected: (v) => setState(() => penW = v),
              itemBuilder: (_) => [
                for (final e in {'Thin': 0.003, 'Medium': 0.006, 'Thick': 0.012, 'Extra thick': 0.024}.entries)
                  CheckedPopupMenuItem<double>(
                      value: e.value, checked: penW == e.value, child: Text(e.key)),
              ],
            ),
            IconButton(
              tooltip: 'Color',
              icon: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: Color(color),
                    shape: BoxShape.circle,
                    border: Border.all(color: showColors ? primary : Colors.grey, width: 2)),
              ),
              onPressed: () => setState(() => showColors = !showColors),
            ),
            IconButton(
                tooltip: 'Clear page',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: clearAll),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final paper = widget.paper == 0 ? Colors.white : Color(widget.paper);
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirm(context, 'Discard this drawing?', yes: 'Discard') && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Handwriting'),
          actions: [
            IconButton(
                tooltip: 'Undo',
                icon: const Icon(Icons.undo),
                onPressed: _undo.isEmpty ? null : undo),
            IconButton(
                tooltip: 'Redo',
                icon: const Icon(Icons.redo),
                onPressed: _redo.isEmpty ? null : redo),
            IconButton(
                tooltip: 'Done',
                icon: const Icon(Icons.check),
                onPressed: () => Navigator.pop(context, strokes)),
          ],
        ),
        body: Column(children: [
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              final w = min(c.maxWidth, c.maxHeight * 3 / 4); // 3:4 page
              _w = w;
              final h = w * 4 / 3;
              return Center(
                child: Container(
                  width: w,
                  height: h,
                  foregroundDecoration:
                      BoxDecoration(border: Border.all(color: Colors.grey)),
                  child: Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: _down,
                    onPointerMove: _move,
                    onPointerUp: _up,
                    onPointerCancel: _up,
                    child: ClipRect(
                      child: CustomPaint(painter: _Ink(strokes, live, paper), size: Size(w, h)),
                    ),
                  ),
                ),
              );
            }),
          ),
          if (showColors) colorPanel(),
          bottomBar(),
        ]),
      ),
    );
  }
}

class _Ink extends CustomPainter {
  final List<Stroke> strokes;
  final Stroke? live;
  final Color paper;
  _Ink(this.strokes, this.live, this.paper);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    paintStrokes(canvas, [...strokes, if (live != null) live!], size.width);
  }

  @override
  bool shouldRepaint(covariant _Ink old) => true;
}
