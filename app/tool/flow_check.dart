// 运动估计的独立自检脚本（不属于产品代码，放 tool/ 不进 git）。
// 直接跑： dart.exe tool/flow_check.dart
//
// 注意：estimate 返回的位移是**灰度图像素**；sampleModel 输入/输出都是**模型坐标**，
// 模型 = 灰度 × 2（grayPerModel=0.5）。所以"灰度移 7 px"= 模型移 14 px。
import 'dart:math' as math;
import 'dart:typed_data';

import '../lib/services/motion_flow.dart';

const int W = 96, H = 176;
const double G2M = 2.0; // 灰度 → 模型 的倍数

/// 造一张有纹理的"画面"：渐变 + 随机斑点；[pull]=1 时把"人"块整体挪 (dx,dy)
Uint8List makeImage(int seed, {int dx = 0, int dy = 0}) {
  final rnd = math.Random(seed);
  final img = Uint8List(W * H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      var v = 90 + (y * 40 ~/ H) + (x * 20 ~/ W);
      v += rnd.nextInt(80) - 40; // 高频纹理（发丝/衣服/墙面细节）
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      img[y * W + x] = v;
    }
  }
  // "人"：一块更亮的区域，按 (dx,dy) 平移（模拟人动、背景不动）
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

/// 只有背景（无物体）：渐变 + 随机纹理
Uint8List makeBase(int seed) {
  final rnd = math.Random(seed);
  final img = Uint8List(W * H);
  for (var y = 0; y < H; y++) {
    for (var x = 0; x < W; x++) {
      var v = 90 + (y * 40 ~/ H) + (x * 20 ~/ W) + rnd.nextInt(50) - 25;
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      img[y * W + x] = v;
    }
  }
  return img;
}

/// 在 img 的 (px,py) 处画一块 32x32 的高对比纹理物体
void paintPatch(Uint8List img, int px, int py) {
  final rnd = math.Random(99);
  for (var y = 0; y < 32; y++) {
    for (var x = 0; x < 32; x++) {
      final ny = py + y, nx2 = px + x;
      if (ny < 0 || ny >= H || nx2 < 0 || nx2 >= W) continue;
      var v = 170 + rnd.nextInt(80) - 40;
      if (v < 0) v = 0;
      if (v > 255) v = 255;
      img[ny * W + nx2] = v;
    }
  }
}

/// 把 img 整体平移 (dx,dy)（越界补 0 = 新露出的区域）
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

/// 内部块的位移均值（模型像素）——边缘块受"内容跑出画面"限制，不参与
List<double> meanInner(MotionField f) {
  final tmp = Float32List(2);
  var sx = 0.0, sy = 0.0, n = 0;
  for (var by = 1; by < f.ny - 1; by++) {
    for (var bx = 1; bx < f.nx - 1; bx++) {
      f.sampleModel((bx + 0.5) * 16.0 * G2M, (by + 0.5) * 16.0 * G2M, tmp);
      sx += tmp[0];
      sy += tmp[1];
      n++;
    }
  }
  return [sx / n, sy / n];
}

int fails = 0;
void check(String name, bool ok, String detail) {
  if (!ok) fails++;
  print('${ok ? "  ✅" : "  ❌"} $name  $detail');
}

void main() {
  final tmp = Float32List(2);
  print('=== 运动估计自检（${W}x$H 灰度，模型 = 灰度 × ${G2M.toInt()}）===');

  // ---------- 1) 已知整体平移 ----------
  for (final t in [
    [0, 0],
    [7, -5],
    [-11, 9],
    [3, 3],
    [-2, 14],
  ]) {
    final prev = makeImage(1);
    final cur = shift(prev, t[0], t[1]);
    final sw = Stopwatch()..start();
    final f = MotionEstimator.estimate(prev, cur, W, H, 0.5);
    sw.stop();
    if (f == null) {
      check('平移 (${t[0]},${t[1]})', false, '返回 null');
      continue;
    }
    final m = meanInner(f);
    final ex = t[0] * G2M, ey = t[1] * G2M;
    final err = math.sqrt((m[0] - ex) * (m[0] - ex) + (m[1] - ey) * (m[1] - ey));
    check(
        '平移 灰度(${t[0]},${t[1]}) → 估模型(${m[0].toStringAsFixed(1)},${m[1].toStringAsFixed(1)})',
        err < 3.0,
        '应≈(${ex.toStringAsFixed(0)},${ey.toStringAsFixed(0)})  误差 ${err.toStringAsFixed(1)} 模型像素  ${sw.elapsedMicroseconds ~/ 1000}ms');
  }

  // ---------- 2) 两张完全相同的图 → 一动不动 ----------
  {
    final prev = makeImage(2);
    final f = MotionEstimator.estimate(prev, Uint8List.fromList(prev), W, H, 0.5);
    if (f == null) {
      check('静止画面', false, '返回 null（应给零场）');
    } else {
      final m = meanInner(f);
      check('静止画面 → (${m[0].toStringAsFixed(2)},${m[1].toStringAsFixed(2)})',
          m[0].abs() < 1.0 && m[1].abs() < 1.0, '应≈0');
    }
  }

  // ---------- 3) 纯色画面（无纹理）→ 不许乱动 ----------
  {
    final flat = Uint8List(W * H)..fillRange(0, W * H, 128);
    final f = MotionEstimator.estimate(flat, shift(flat, 5, 5), W, H, 0.5);
    var bad = false;
    if (f != null) {
      for (var k = 0; k < f.dx.length; k++) {
        if (f.dx[k].abs() > 0.01 || f.dy[k].abs() > 0.01) bad = true;
      }
    }
    check('纯色画面 → 全零', !bad, f == null ? '返回 null（也算安全）' : '无虚假位移');
  }

  // ---------- 4) 局部运动：背景静止 + 一整块纹理物体移动（位移大于块长） ----------
  {
    final prev = makeBase(6);
    final cur = Uint8List.fromList(prev);
    // prev 上画一块 32x32 的纹理物体；cur 上画在移动后的位置
    paintPatch(prev, 30, 80);
    paintPatch(cur, 42, 70);
    final f = MotionEstimator.estimate(prev, cur, W, H, 0.5);
    if (f == null) {
      check('局部运动', false, '返回 null');
    } else {
      // 物体中心（cur 坐标）灰度 ≈ (58,86) → 模型 (116,172)
      f.sampleModel(116, 172, tmp);
      check('局部运动·物体 (${tmp[0].toStringAsFixed(1)},${tmp[1].toStringAsFixed(1)})',
          (tmp[0] - 24).abs() < 6 && (tmp[1] + 20).abs() < 6, '应≈(24,-20)');
      // 背景角落（完全静止）
      f.sampleModel(12, 12, tmp);
      check('局部运动·背景 (${tmp[0].toStringAsFixed(1)},${tmp[1].toStringAsFixed(1)})',
          tmp[0].abs() < 4 && tmp[1].abs() < 4, '应≈(0,0)');
    }
  }

  // ---------- 5) 只平移一点点（亚像素级）→ 不许乱放大 ----------
  {
    final prev = makeImage(5);
    final f = MotionEstimator.estimate(prev, shift(prev, 1, 0), W, H, 0.5);
    if (f == null) {
      check('1px 位移', false, '返回 null');
    } else {
      final m = meanInner(f);
      check('1px 位移 → (${m[0].toStringAsFixed(1)},${m[1].toStringAsFixed(1)})',
          (m[0] - 2).abs() < 3 && m[1].abs() < 3, '应≈(2,0)');
    }
  }

  // ---------- 6) 耗时 ----------
  {
    final prev = makeImage(4);
    final cur = shift(prev, 6, -4);
    final sw = Stopwatch()..start();
    const iters = 50;
    for (var i = 0; i < iters; i++) {
      MotionEstimator.estimate(prev, cur, W, H, 0.5);
    }
    sw.stop();
    print('  ⏱  平均 ${(sw.elapsedMicroseconds / iters / 1000).toStringAsFixed(1)}ms/次（PC）；'
        '手机约 3~5 倍 → 3~5ms，alpha 每 250ms 一次，占比 <2%');
  }
  // ---------- 7) 人像区域整体平移（两次 alpha 之间的连续跟随）----------
  {
    final prev = makeBase(7);
    paintPatch(prev, 30, 80); // 把人放在 (30,80) 起的 32x32
    final cur = shift(prev, 5, -4); // 整幅平移 (5,-4)
    final wt = Uint8List(W * H);
    for (var y = 78; y < 114; y++) {
      for (var x = 28; x < 64; x++) {
        wt[y * W + x] = 1;
      }
    }
    final s = estimateMaskShift(prev, cur, W, H, wt, 18);
    if (s == null) {
      check('人像整体平移', false, '返回 null');
    } else {
      check(
          '人像整体平移 (${s.dx.toStringAsFixed(1)},${s.dy.toStringAsFixed(1)})',
          (s.dx - 5).abs() < 2 && (s.dy + 4).abs() < 2,
          '应≈(5,-4) 灰度像素');
    }
    // 静止 → 不应补偿
    final s2 = estimateMaskShift(prev, Uint8List.fromList(prev), W, H, wt, 18);
    check(
        '人像静止 → 不补偿',
        s2 == null || s2.magnitude < 1.5,
        s2 == null
            ? '返回 null ✓'
            : '(${s2.dx.toStringAsFixed(1)},${s2.dy.toStringAsFixed(1)})');
  }

  print(fails == 0 ? '=== 全部通过 ===' : '=== 有 $fails 项未通过 ===');
}
