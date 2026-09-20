import 'dart:math' as math;
import 'dart:typed_data';
import '../lib/services/motion_flow.dart';

const int W = 96, H = 176;
Uint8List makeImage(int seed, {int dx = 0, int dy = 0}) {
  final rnd = math.Random(seed);
  final img = Uint8List(W * H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      var v = 90 + (y * 40 ~/ H) + (x * 20 ~/ W);
      v += rnd.nextInt(80) - 40;
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      img[y * W + x] = v;
    }
  }
  for (var y = 70; y < 150; y++) {
    for (var x = 25; x < 70; x++) {
      final ny = y + dy, nx2 = x + dx;
      if (ny < 0 || ny >= H || nx2 < 0 || nx2 >= W) continue;
      var v = img[ny * W + nx2] + 45;
      if (v > 255) v = 255;
      img[ny * W + nx2] = v;
    }
  }
  return img;
}
Uint8List shift(Uint8List img, int dx, int dy) {
  final out = Uint8List(W * H);
  for (var y = 0; y < H; y++) {
    final sy = y - dy;
    if (sy < 0 || sy >= H) continue;
    for (var x = 0; x < W; x++) {
      final sx = x - dx;
      if (sx < 0 || sx >= W) continue;
      out[y * W + x] = img[sy * W + sx];
    }
  }
  return out;
}
void main() {
  final prev = makeImage(1);
  final cur = shift(prev, 7, -5);
  final f = MotionEstimator.estimate(prev, cur, W, H, 0.5);
  if (f == null) { print('null'); return; }
  print('grid ${f.nx}x${f.ny}  灰度位移应为 (7,-5)');
  for (var by = 0; by < f.ny; by++) {
    final sb = StringBuffer('row$by: ');
    for (var bx = 0; bx < f.nx; bx++) {
      final k = by * f.nx + bx;
      sb.write('(${f.dx[k].toStringAsFixed(1)},${f.dy[k].toStringAsFixed(1)})c${f.conf[k].toStringAsFixed(1)} ');
    }
    print(sb);
  }
}
