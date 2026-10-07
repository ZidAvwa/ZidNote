import 'dart:ui';

/// One pen stroke. Coordinates and width are divided by the canvas width, so a
/// drawing looks the same on any screen size.
class Stroke {
  final List<Offset> pts;
  final int color;
  final double width;
  final bool highlighter;
  Stroke(this.pts, this.color, this.width, this.highlighter);

  Map toJson() => {
        'c': color,
        'w': width,
        'h': highlighter,
        'p': [for (final p in pts) ...[p.dx, p.dy]],
      };

  factory Stroke.fromJson(Map j) {
    final p = (j['p'] as List).cast<num>();
    return Stroke(
      [for (int i = 0; i + 1 < p.length; i += 2) Offset(p[i].toDouble(), p[i + 1].toDouble())],
      j['c'],
      (j['w'] as num).toDouble(),
      j['h'] ?? false,
    );
  }
}

/// Paints strokes; [scale] is the canvas width in pixels.
void paintStrokes(Canvas canvas, List<Stroke> strokes, double scale) {
  for (final s in strokes) {
    if (s.pts.isEmpty) continue;
    final w = s.width * scale * (s.highlighter ? 4 : 1);
    final col = s.highlighter ? Color(s.color).withAlpha(100) : Color(s.color);
    final pts = s.pts;
    if (pts.length == 1) {
      canvas.drawCircle(pts[0] * scale, w / 2, Paint()..color = col);
      continue;
    }
    final paint = Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = s.highlighter ? StrokeCap.butt : StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts[0].dx * scale, pts[0].dy * scale);
    for (int i = 1; i < pts.length - 1; i++) {
      final mx = (pts[i].dx + pts[i + 1].dx) / 2 * scale;
      final my = (pts[i].dy + pts[i + 1].dy) / 2 * scale;
      path.quadraticBezierTo(pts[i].dx * scale, pts[i].dy * scale, mx, my);
    }
    path.lineTo(pts.last.dx * scale, pts.last.dy * scale);
    canvas.drawPath(path, paint);
  }
}
