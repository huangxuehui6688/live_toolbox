import 'dart:math' as math;
import 'dart:typed_data';

/// 帧间运动场：块匹配的结果。
///
/// **位移定义（全篇统一）**：`prev` 里坐标 (x,y) 的内容，在 `cur` 里跑到了 (x+dx, y+dy)。
/// 所以要把遮罩从旧帧外推到新帧，就按 `mask_new(p) = mask_old(p - v(p))` 反向采样。
class MotionField {
  MotionField({
    required this.nx,
    required this.ny,
    required this.w,
    required this.h,
    required this.grayPerModel,
    required this.dx,
    required this.dy,
    required this.conf,
  });

  /// 块网格列数 / 行数（每块 ≈ w/nx × h/ny 像素）
  final int nx;
  final int ny;

  /// 估计所用灰度图的尺寸
  final int w;
  final int h;

  /// 灰度图坐标 ÷ 模型坐标（灰度 96 宽、模型 192 宽 → 0.5）
  final double grayPerModel;

  /// 每块的有效位移（灰度图像素；正 = 内容向右/下移动），已按置信度加权并做过邻域平滑
  final Float32List dx;
  final Float32List dy;

  /// 每块置信度 0~1（诊断显示 + 二次判断用）
  final Float32List conf;

  double get _bw => w / nx;
  double get _bh => h / ny;

  /// 取「模型坐标 (mx,my) 处内容从 prev 到 cur 的位移」，双线性插值，单位 = 模型像素。
  /// 结果写进 [out]（长度 2）——避免每像素分配。
  void sampleModel(double mx, double my, Float32List out) {
    final inv = 1.0 / grayPerModel;
    var gx = mx * grayPerModel / _bw - 0.5;
    var gy = my * grayPerModel / _bh - 0.5;
    if (gx < 0) gx = 0;
    if (gy < 0) gy = 0;
    var i0 = gx.floor();
    var j0 = gy.floor();
    final imax = nx - 2 < 0 ? 0 : nx - 2;
    final jmax = ny - 2 < 0 ? 0 : ny - 2;
    if (i0 > imax) i0 = imax;
    if (j0 > jmax) j0 = jmax;
    final fx = (gx - i0).clamp(0.0, 1.0);
    final fy = (gy - j0).clamp(0.0, 1.0);
    final i1 = i0 + 1 < nx ? i0 + 1 : nx - 1;
    final j1 = j0 + 1 < ny ? j0 + 1 : ny - 1;
    final o00 = j0 * nx + i0, o01 = j0 * nx + i1;
    final o10 = j1 * nx + i0, o11 = j1 * nx + i1;
    final ax = dx[o00] + (dx[o01] - dx[o00]) * fx;
    final bx = dx[o10] + (dx[o11] - dx[o10]) * fx;
    final ay = dy[o00] + (dy[o01] - dy[o00]) * fx;
    final by = dy[o10] + (dy[o11] - dy[o10]) * fx;
    out[0] = (ax + (bx - ax) * fy) * inv;
    out[1] = (ay + (by - ay) * fy) * inv;
  }

  /// 位移均方根（模型像素；诊断用）
  double rmsModel() {
    if (dx.isEmpty) return 0;
    final inv = 1.0 / grayPerModel;
    double s = 0;
    for (var i = 0; i < dx.length; i++) {
      s += dx[i] * dx[i] + dy[i] * dy[i];
    }
    return math.sqrt(s / dx.length) * inv;
  }

  /// 最大位移（模型像素；诊断用）
  double maxModel() {
    final inv = 1.0 / grayPerModel;
    double m = 0;
    for (var i = 0; i < dx.length; i++) {
      final v = dx[i] * dx[i] + dy[i] * dy[i];
      if (v > m) m = v;
    }
    return math.sqrt(m) * inv;
  }
}

/// 块匹配运动估计。
///
/// **为什么需要**：AI 抠像只有 ~4fps，遮罩天生滞后约 0.25s。人一动，遮罩还停在旧姿态，
/// 于是人的**前缘会露出一条真实背景**（就是"背景从人身上漏出来"）。这里估出运动场，
/// 发布遮罩时按运动场反向采样，把遮罩"推到"当前帧的位置。
///
/// **为什么在"模型输入空间"里估**：alpha 就在这个坐标系（已转正、非方形），
/// 估出的位移可以直接作用到 alpha 的采样坐标上，不需要再转换一次。
///
/// **搜索策略（踩过坑才定下来的）**：
///   只做"粗步长 + 精修"是不行的 —— 高频纹理（细条纹、噪点、眼镜反光）的相关峰是**尖的**，
///   粗步长会整个跳过真峰，之后再怎么精修也回不来（实测：真位移 +12 被估成 +3.6）。
///   所以必须**稠密**搜；但稠密全范围用全样本又太贵。折中：
///     ① 预筛：**步长 1 的稠密**搜索 ±preR，只用块四角的 4 个样本 → 便宜（真峰处这 4 个差也是 0，
///        所以真峰一定会进前几名）；
///     ② 复算：对前几名 + 全局先验 + 其 ±1 邻域，用全部 16 个样本精确算 SAD，定胜负。
///   这样"稠密不漏峰"和"精确"两者都要到了，代价只有前者的一半不到。
///
/// **安全阀**：纹理太弱（纯墙/纯色）的块直接置零；整体改善不足（没找到可信运动）也置零；
/// 每块结果乘置信度后再做邻域平滑。**找不到真峰时的表现是"不补偿"，而不是"补错方向"**。
class MotionEstimator {
  /// 块边长（灰度图像素）
  static const int block = 16;

  /// 块内 SAD 采样步长（16/4 → 每块 4×4 = 16 个样本）
  static const int sadStep = 4;

  /// 预筛半径（灰度像素，**步长 1**）
  static const int preR = 14;

  /// 预筛保留的候选个数（复算阶段用全样本重算）
  static const int keepTop = 4;

  /// 全局平移搜索半径 / 步长 / 图像采样步长
  static const int globalRadius = 16;
  static const int globalStep = 2;
  static const int globalSampleStep = 6;

  /// 块内纹理能量下限：低于它说明是纯色墙/天空，位移不可信
  static const double minTexture = 4.0;

  /// 相对"零位移"的最小改善比例：低于它视为没找到可信运动
  static const double minGain = 0.10;

  /// 位移上限（占图像短边的比例）：超过就视为不可信
  static const double maxShiftFrac = 0.30;

  /// "偏爱不动"的代价系数（每个采样点、每像素位移）。
  /// 重复纹理很容易在远处凑出一个假的好匹配；相关面平时宁可少补一点
  /// （少补只是补偿不足，补错方向才是灾难）。
  static const double stillBias = 0.20;

  /// 块内 4×4 采样偏移（相对块左上角）
  static final Int32List _gx = _build(4, 0);
  static final Int32List _gy = _build(4, 1);

  static Int32List _build(int step, int axis) {
    final a = Int32List((block ~/ step) * (block ~/ step));
    var i = 0;
    for (var oy = 0; oy < block; oy += step) {
      for (var ox = 0; ox < block; ox += step) {
        a[i++] = axis == 0 ? ox : oy;
      }
    }
    return a;
  }

  /// 估 prev → cur 的运动场（prev/cur 是同一尺寸 (w,h) 的灰度图）。
  ///
  /// [grayPerModel] = 灰度宽 ÷ 模型输入宽（用于把位移换算成模型像素）。
  static MotionField? estimate(
    Uint8List prev,
    Uint8List cur,
    int w,
    int h,
    double grayPerModel,
  ) {
    if (w < block * 2 || h < block * 2) return null;
    if (prev.length < w * h || cur.length < w * h) return null;
    if (grayPerModel <= 0) return null;

    final offX = _gx;
    final offY = _gy;
    final on = offX.length;

    final maxShift = math.max(2, (math.min(w, h) * maxShiftFrac).round());
    final r = globalRadius;

    // ---------------- 1) 全局平移：稀疏采样 + 大步长 ----------------
    final gxs = <int>[];
    final gys = <int>[];
    for (var y = r; y < h - r; y += globalSampleStep) {
      for (var x = r; x < w - r; x += globalSampleStep) {
        gxs.add(x);
        gys.add(y);
      }
    }
    final gn = gxs.length;
    if (gn < 16) return null;
    final gv = Int32List(gn);
    for (var i = 0; i < gn; i++) {
      gv[i] = prev[gys[i] * w + gxs[i]];
    }
    var sadZero = 0;
    for (var i = 0; i < gn; i++) {
      sadZero += (gv[i] - cur[gys[i] * w + gxs[i]]).abs();
    }
    var gBest = sadZero, gx = 0, gy = 0;
    for (var vy = -r; vy <= r; vy += globalStep) {
      for (var vx = -r; vx <= r; vx += globalStep) {
        if (vx == 0 && vy == 0) continue;
        var s = 0;
        for (var i = 0; i < gn; i++) {
          s += (gv[i] - cur[(gys[i] + vy) * w + gxs[i] + vx]).abs();
        }
        if (s < gBest) {
          gBest = s;
          gx = vx;
          gy = vy;
        }
      }
    }
    final globalGain = sadZero == 0 ? 0.0 : 1.0 - gBest / sadZero;
    if (globalGain < minGain) {
      gx = 0;
      gy = 0;
    }

    // ---------------- 2) 逐块搜索 ----------------
    final nx = w ~/ block;
    final ny = h ~/ block;
    if (nx < 1 || ny < 1) return null;
    final n = nx * ny;
    final rawX = Float32List(n);
    final rawY = Float32List(n);
    final rawC = Float32List(n);
    final pv = Int32List(on);
    final cxs = Int32List(keepTop);
    final cys = Int32List(keepTop);
    final cst = Int32List(keepTop);

    for (var by = 0; by < ny; by++) {
      final y0 = by * block;
      for (var bx = 0; bx < nx; bx++) {
        final x0 = bx * block;
        // ★允许的位移范围：位移后所有采样点都必须还在图内（最远的采样偏移是 13）。
        //   边缘块只能朝图内方向匹配 —— 内容跑出画面本来也匹配不了。
        final vxMin = math.max(-maxShift, -x0);
        final vxMax = math.min(maxShift, w - 1 - x0 - 13);
        final vyMin = math.max(-maxShift, -y0);
        final vyMax = math.min(maxShift, h - 1 - y0 - 13);
        if (vxMin > vxMax || vyMin > vyMax) continue;

        final base = y0 * w + x0;

        // 块内纹理能量（相对块内均值的平均绝对偏差）→ 纯色墙/天空直接不可信
        var sum = 0;
        for (var i = 0; i < on; i++) {
          final v = prev[base + offY[i] * w + offX[i]];
          pv[i] = v;
          sum += v;
        }
        final mean = sum / on;
        var energy = 0.0;
        for (var i = 0; i < on; i++) {
          energy += (pv[i] - mean).abs();
        }
        energy /= on;

        // 零位移的 SAD（置信度基准）
        var sad0 = 0;
        for (var i = 0; i < on; i++) {
          sad0 += (pv[i] - cur[base + offY[i] * w + offX[i]]).abs();
        }

        // ---- ① 预筛：稠密（步长 1）+ 只用 4 个角样本 ----
        final q0 = prev[base + 2 * w + 2];
        final q1 = prev[base + 2 * w + 13];
        final q2 = prev[base + 13 * w + 2];
        final q3 = prev[base + 13 * w + 13];
        for (var i = 0; i < keepTop; i++) {
          cst[i] = 1 << 30;
          cxs[i] = 0;
          cys[i] = 0;
        }
        final loX = math.max(vxMin, -preR);
        final hiX = math.min(vxMax, preR);
        final loY = math.max(vyMin, -preR);
        final hiY = math.min(vyMax, preR);
        for (var dyv = loY; dyv <= hiY; dyv++) {
          final row = base + dyv * w;
          for (var dxv = loX; dxv <= hiX; dxv++) {
            final o = row + dxv;
            final s = (q0 - cur[o + 2 * w + 2]).abs() +
                (q1 - cur[o + 2 * w + 13]).abs() +
                (q2 - cur[o + 13 * w + 2]).abs() +
                (q3 - cur[o + 13 * w + 13]).abs();
            if (s < cst[keepTop - 1]) {
              // 插入排序（keepTop 很小，很便宜）
              var k = keepTop - 1;
              while (k > 0 && cst[k - 1] > s) {
                cst[k] = cst[k - 1];
                cxs[k] = cxs[k - 1];
                cys[k] = cys[k - 1];
                k--;
              }
              cst[k] = s;
              cxs[k] = dxv;
              cys[k] = dyv;
            }
          }
        }

        // ---- ② 复算：幸存候选 + 全局先验 + ±1 邻域，用全样本算 SAD ----
        var sadMin = sad0;
        var vx = 0, vy = 0;
        var costMin = sad0.toDouble();
        var bestSx = 0, bestSy = 0;

        void evalAt(int sx, int sy) {
          if (sx < vxMin || sx > vxMax || sy < vyMin || sy > vyMax) return;
          var s = 0;
          for (var i = 0; i < on; i++) {
            s += (pv[i] - cur[base + (sy + offY[i]) * w + sx + offX[i]]).abs();
          }
          final cost = s + (sx.abs() + sy.abs()) * on * stillBias;
          if (cost < costMin) {
            costMin = cost;
            sadMin = s;
            vx = sx;
            vy = sy;
          }
        }

        for (var i = 0; i < keepTop; i++) {
          if (cst[i] >= (1 << 30)) break;
          evalAt(cxs[i], cys[i]);
        }
        evalAt(gx, gy);
        // 胜者 ±1 精修（1 像素精度）
        bestSx = vx;
        bestSy = vy;
        for (var dyv = -1; dyv <= 1; dyv++) {
          for (var dxv = -1; dxv <= 1; dxv++) {
            if (dxv == 0 && dyv == 0) continue;
            evalAt(bestSx + dxv, bestSy + dyv);
          }
        }

        var c = sad0 == 0 ? 0.0 : 1.0 - sadMin / sad0;
        if (energy < minTexture || c < minGain) c = 0.0;
        if (c > 1) c = 1;
        if (c == 0) {
          vx = 0;
          vy = 0;
        }
        final k = by * nx + bx;
        rawX[k] = vx.toDouble();
        rawY[k] = vy.toDouble();
        rawC[k] = c;
      }
    }

    // ---------------- 3) 置信度加权 + 3×3 邻域平滑（消块间接缝）----------------
    final outX = Float32List(n);
    final outY = Float32List(n);
    final outC = Float32List(n);
    for (var by = 0; by < ny; by++) {
      for (var bx = 0; bx < nx; bx++) {
        var wx = 0.0, wy = 0.0, wc = 0.0;
        for (var j = by - 1; j <= by + 1; j++) {
          if (j < 0 || j >= ny) continue;
          for (var i = bx - 1; i <= bx + 1; i++) {
            if (i < 0 || i >= nx) continue;
            final k = j * nx + i;
            final c = rawC[k];
            if (c <= 0) continue;
            wx += rawX[k] * c;
            wy += rawY[k] * c;
            wc += c;
          }
        }
        final k0 = by * nx + bx;
        if (wc > 0.05) {
          outX[k0] = wx / wc;
          outY[k0] = wy / wc;
        }
        outC[k0] = rawC[k0];
      }
    }

    return MotionField(
      nx: nx,
      ny: ny,
      w: w,
      h: h,
      grayPerModel: grayPerModel,
      dx: outX,
      dy: outY,
      conf: outC,
    );
  }
}
