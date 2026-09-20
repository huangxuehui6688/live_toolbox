/// ONNX Runtime C API 的极简 FFI 绑定（只绑抠像需要的二十来个函数）。
///
/// ★为什么不引 `flutter_ort_plugin` / `onnxruntime_v2` 之类的包：
///   本工程经 `sherpa_onnx` 已经带进一份**完整的标准版 `libonnxruntime.so`**
///   （arm64-v8a，21.2MB，版本号 VERS_1.28.2，导出 `OrtGetApiBase`）。
///   再引一个自带 ORT 的包 → APK 里出现**两份同名 `libonnxruntime.so`**
///   （Gradle 打包直接冲突 + 体积翻倍）。所以这里直接复用现有这份 .so，
///   **运行时净增体积 = 0**。
///
/// ★怎么调：`OrtGetApiBase()->GetApi(28)` 返回一个**巨型函数指针结构体**。
///   该结构体是 ORT 明确承诺「只追加、不改动」的 ABI 契约，所以按**下标**取
///   函数指针是安全的。下面每个下标都由 `onnxruntime_c_api.h`（v1.28.2，
///   与 .so 内版本号严格一致）的 `OrtApi` 成员顺序机械导出，并且用
///   「413 = ORT_API2_STATUS(351) + 裸函数指针(32) + ORT_CLASS_RELEASE(30)」
///   做了交叉校验（见 `直播/_matting_work/parse2.py`）。
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';


// ------------------------------------------------------------------ 下标表
const int kOrtApiVersion = 28; // ORT_API_VERSION（ORT 1.28.2 → 28）

const int _iGetErrorCode = 1;
const int _iGetErrorMessage = 2;
const int _iCreateEnv = 3;
const int _iCreateSession = 7;
const int _iRun = 9;
const int _iCreateSessionOptions = 10;
const int _iSetSessionExecutionMode = 13;
const int _iEnableMemPattern = 16;
const int _iEnableCpuMemArena = 18;
const int _iSetSessionLogSeverityLevel = 22;
const int _iSetSessionGraphOptimizationLevel = 23;
const int _iSetIntraOpNumThreads = 24;
const int _iSetInterOpNumThreads = 25;
const int _iSessionGetInputTypeInfo = 33;
const int _iSessionGetOutputTypeInfo = 34;
const int _iSessionGetInputName = 36;
const int _iSessionGetOutputName = 37;
const int _iCreateTensorWithDataAsOrtValue = 49;
const int _iCastTypeInfoToTensorInfo = 55;
const int _iGetTensorElementType = 60;
const int _iGetDimensionsCount = 61;
const int _iGetDimensions = 62;
const int _iCreateCpuMemoryInfo = 69;
const int _iAllocatorFree = 76;
const int _iGetAllocatorWithDefaultOptions = 78;
const int _iReleaseEnv = 92;
const int _iReleaseStatus = 93;
const int _iReleaseMemoryInfo = 94;
const int _iReleaseSession = 95;
const int _iReleaseValue = 96;
const int _iReleaseSessionOptions = 100;
const int _iGetAvailableProviders = 125;
const int _iReleaseAvailableProviders = 126;
const int _iAddFreeDimensionOverrideByName = 124;
const int _iSessionOptionsAppendExecutionProvider = 216;

// OrtApiBase 成员顺序：GetApi(0), GetVersionString(1)
const int _iApiBaseGetApi = 0;
const int _iApiBaseGetVersionString = 1;

/// ONNX 张量元素类型
const int kOrtTypeFloat = 1;
const int kOrtTypeUint8 = 2;
const int kOrtTypeInt8 = 3;

/// 元素类型 → 字节数（只覆盖我们可能遇到的三种）
int ortElemBytes(int t) => t == kOrtTypeFloat ? 4 : 1;

// 各类枚举
const int _ortLoggingError = 3;
const int _ortEnableAll = 99;
const int _ortArenaAllocator = 1;
const int _ortMemTypeDefault = 0;

// ---------------------------------------------------- 函数指针签名（C 侧）
// ffigen 风格：`_N*` 是原生签名（Int32/IntPtr/Uint32），`_D*` 是 Dart 侧签名
// （对应的位置必须是 int，否则 asFunction 会报 argument_type_not_assignable）。
typedef _NGetApi = Pointer<Void> Function(Uint32);
typedef _NGetVersion = Pointer<Uint8> Function();
typedef _NStatusA = Pointer<Void> Function(Pointer<Void>);
typedef _NStatusAI = Pointer<Void> Function(Pointer<Void>, Int32);
typedef _NStatusOut = Pointer<Void> Function(Pointer<Pointer<Void>>);
typedef _NStatusAOut = Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _NStatusAIAOut = Pointer<Void> Function(
    Pointer<Void>, IntPtr, Pointer<Pointer<Void>>);
typedef _NStatusAI32AOut = Pointer<Void> Function(
    Pointer<Void>, IntPtr, Pointer<Void>, Pointer<Pointer<Uint8>>);
typedef _NStatusI32AOut =
    Pointer<Void> Function(Int32, Pointer<Uint8>, Pointer<Pointer<Void>>);
typedef _NStatusCreateSession = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _NStatusI32I32Out =
    Pointer<Void> Function(Int32, Int32, Pointer<Pointer<Void>>);
typedef _NStatusAIPOut = Pointer<Void> Function(Pointer<Void>, Pointer<IntPtr>);
typedef _NStatusAI32POut = Pointer<Void> Function(Pointer<Void>, Pointer<Int32>);
typedef _NStatusPInt64I = Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, IntPtr);
typedef _NStatusTensorData = Pointer<Void> Function(Pointer<Void>, Pointer<Void>,
    IntPtr, Pointer<Int64>, IntPtr, Int32, Pointer<Pointer<Void>>);
typedef _NRun = Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Uint8>>,
    Pointer<Pointer<Void>>,
    IntPtr,
    Pointer<Pointer<Uint8>>,
    IntPtr,
    Pointer<Pointer<Void>>);
typedef _NStatusEp = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>,
    Pointer<Pointer<Uint8>>, Pointer<Pointer<Uint8>>, IntPtr);
typedef _NStr = Pointer<Uint8> Function(Pointer<Void>);
typedef _NInt32 = Int32 Function(Pointer<Void>);
typedef _NStatusProviders =
    Pointer<Void> Function(Pointer<Pointer<Pointer<Uint8>>>, Pointer<Int32>);
typedef _NVoidA = Void Function(Pointer<Void>);
typedef _NVoidAI = Void Function(Pointer<Void>, Int32);
typedef _NVoidAA = Void Function(Pointer<Void>, Pointer<Void>);

/// int64 形参的 Status 函数（AddFreeDimensionOverrideByName）
typedef _NStatusAI64 = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, Int64);

// ---------------------------------------------------- 函数指针签名（Dart 侧）
typedef _DGetApi = Pointer<Void> Function(int);
typedef _DGetVersion = Pointer<Uint8> Function();
typedef _DStatusA = Pointer<Void> Function(Pointer<Void>);
typedef _DStatusAI = Pointer<Void> Function(Pointer<Void>, int);
typedef _DStatusOut = Pointer<Void> Function(Pointer<Pointer<Void>>);
typedef _DStatusAOut = Pointer<Void> Function(Pointer<Void>, Pointer<Pointer<Void>>);
typedef _DStatusAIAOut = Pointer<Void> Function(
    Pointer<Void>, int, Pointer<Pointer<Void>>);
typedef _DStatusAI32AOut = Pointer<Void> Function(
    Pointer<Void>, int, Pointer<Void>, Pointer<Pointer<Uint8>>);
typedef _DStatusI32AOut =
    Pointer<Void> Function(int, Pointer<Uint8>, Pointer<Pointer<Void>>);
typedef _DStatusCreateSession = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _DStatusI32I32Out =
    Pointer<Void> Function(int, int, Pointer<Pointer<Void>>);
typedef _DStatusAIPOut = Pointer<Void> Function(Pointer<Void>, Pointer<IntPtr>);
typedef _DStatusAI32POut = Pointer<Void> Function(Pointer<Void>, Pointer<Int32>);
typedef _DStatusPInt64I = Pointer<Void> Function(Pointer<Void>, Pointer<Int64>, int);
typedef _DStatusTensorData = Pointer<Void> Function(Pointer<Void>, Pointer<Void>,
    int, Pointer<Int64>, int, int, Pointer<Pointer<Void>>);
typedef _DRun = Pointer<Void> Function(
    Pointer<Void>,
    Pointer<Void>,
    Pointer<Pointer<Uint8>>,
    Pointer<Pointer<Void>>,
    int,
    Pointer<Pointer<Uint8>>,
    int,
    Pointer<Pointer<Void>>);
typedef _DStatusEp = Pointer<Void> Function(Pointer<Void>, Pointer<Uint8>,
    Pointer<Pointer<Uint8>>, Pointer<Pointer<Uint8>>, int);
typedef _DStr = Pointer<Uint8> Function(Pointer<Void>);
typedef _DInt32 = int Function(Pointer<Void>);
typedef _DStatusProviders =
    Pointer<Void> Function(Pointer<Pointer<Pointer<Uint8>>>, Pointer<Int32>);
typedef _DVoidA = void Function(Pointer<Void>);
typedef _DVoidAI = void Function(Pointer<Void>, int);
typedef _DVoidAA = void Function(Pointer<Void>, Pointer<Void>);
typedef _DStatusAI64 = Pointer<Void> Function(
    Pointer<Void>, Pointer<Uint8>, int);

// ------------------------------------------------------------------ 内存与字符串
final DynamicLibrary _libc = DynamicLibrary.process();

final Pointer<Void> Function(int) _malloc = _libc.lookupFunction<
    Pointer<Void> Function(IntPtr),
    Pointer<Void> Function(int)>('malloc');

final void Function(Pointer<Void>) _memFree = _libc.lookupFunction<
    Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('free');

/// 申请 n 字节（native 内存，**永不被 Dart GC 移动**）并清零。
/// ★绝不能把 Dart 堆上 `TypedData` 的地址交给 ORT：GC 会移动它。
Pointer<Void> ortMalloc(int n) {
  final p = _malloc(n);
  final b = p.cast<Uint8>();
  for (int i = 0; i < n; i++) {
    b[i] = 0;
  }
  return p;
}

void ortFree(Pointer<NativeType>? p) {
  if (p != null && p != nullptr) _memFree(p.cast<Void>());
}

Pointer<Uint8> ortCStr(String s) {
  final bytes = utf8.encode(s);
  final p = ortMalloc(bytes.length + 1).cast<Uint8>();
  for (int i = 0; i < bytes.length; i++) {
    p[i] = bytes[i];
  }
  return p;
}

String _readCStr(Pointer<Uint8> p, {int max = 255}) {
  if (p == nullptr) return '';
  final out = <int>[];
  for (int i = 0; i < max; i++) {
    final c = p[i];
    if (c == 0) break;
    out.add(c);
  }
  return utf8.decode(out, allowMalformed: true);
}

/// 8 字节壳指针 → `T**`（承接一个 `T*`）
Pointer<Pointer<Void>> _pp(Pointer<Void> p) => p.cast<Pointer<Void>>();

/// 8 字节壳指针 → `char**`
Pointer<Pointer<Uint8>> _ppChar(Pointer<Void> p) => p.cast<Pointer<Uint8>>();

// ------- 取 OrtApi 里第 idx 个函数指针（按签名各绑一个）-------
// 说明：`Pointer<NativeFunction<T>>` 的 T 必须是编译期常量类型，
// 所以没法用泛型助手，只能一个签名写一个。

_DStatusA _dStatusA(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusA>>.fromAddress(api[idx].address)
        .asFunction<_DStatusA>();

_DStatusAI _dStatusAI(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAI>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAI>();

_DStatusOut _dStatusOut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusOut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusOut>();

_DStatusAOut _dStatusAOut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAOut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAOut>();

_DStatusAIAOut _dStatusAIAOut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAIAOut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAIAOut>();

_DStatusAI32AOut _dStatusAI32AOut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAI32AOut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAI32AOut>();

_DStatusI32AOut _dStatusI32AOut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusI32AOut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusI32AOut>();

_DStatusCreateSession _dStatusCreateSession(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusCreateSession>>.fromAddress(api[idx].address)
        .asFunction<_DStatusCreateSession>();

_DStatusI32I32Out _dStatusI32I32Out(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusI32I32Out>>.fromAddress(api[idx].address)
        .asFunction<_DStatusI32I32Out>();

_DStatusAIPOut _dStatusAIPOut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAIPOut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAIPOut>();

_DStatusAI32POut _dStatusAI32POut(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAI32POut>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAI32POut>();

_DStatusPInt64I _dStatusPInt64I(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusPInt64I>>.fromAddress(api[idx].address)
        .asFunction<_DStatusPInt64I>();

_DStatusTensorData _dStatusTensorData(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusTensorData>>.fromAddress(api[idx].address)
        .asFunction<_DStatusTensorData>();

_DRun _dRun(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NRun>>.fromAddress(api[idx].address)
        .asFunction<_DRun>();

_DStatusEp _dStatusEp(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusEp>>.fromAddress(api[idx].address)
        .asFunction<_DStatusEp>();

_DStr _dStr(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStr>>.fromAddress(api[idx].address)
        .asFunction<_DStr>();

_DInt32 _dInt32(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NInt32>>.fromAddress(api[idx].address)
        .asFunction<_DInt32>();

_DStatusAI64 _dStatusAI64(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusAI64>>.fromAddress(api[idx].address)
        .asFunction<_DStatusAI64>();

_DStatusProviders _dStatusProviders(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NStatusProviders>>.fromAddress(api[idx].address)
        .asFunction<_DStatusProviders>();

_DVoidA _dVoidA(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NVoidA>>.fromAddress(api[idx].address)
        .asFunction<_DVoidA>();

_DVoidAI _dVoidAI(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NVoidAI>>.fromAddress(api[idx].address)
        .asFunction<_DVoidAI>();

_DVoidAA _dVoidAA(Pointer<Pointer<Void>> api, int idx) =>
    Pointer<NativeFunction<_NVoidAA>>.fromAddress(api[idx].address)
        .asFunction<_DVoidAA>();

// ==================================================================
// 推理会话
// ==================================================================

/// 一个装好模型的 ORT 会话。
///
/// 约定：**所有对外方法都不抛异常**；失败返回 null，错误文本放在 [lastError]，
/// 只许进 debugPrint，绝不冒到 UI。
class OrtSession {
  OrtSession._(this._env, this._opts, this._session, this._memInfo, this._allocator);

  final Pointer<Void> _env;
  final Pointer<Void> _opts;
  final Pointer<Void> _session;
  final Pointer<Void> _memInfo;
  final Pointer<Void> _allocator;

  /// 模型输入张量元素类型：1=float32, 2=uint8, 3=int8
  int inputElementType = kOrtTypeFloat;

  /// 输出张量元素类型（实测两种权重都是 FLOAT，但按实测走更稳）
  int outputElementType = kOrtTypeFloat;

  /// 模型输入张量的高 / 宽（NCHW 的 [2]、[3]）。**支持非方形**。
  ///
  /// ★为什么必须支持非方形：手机画面是 9:16，而模型要方形输入，只有两条路，都试过：
  ///   · 居中裁方 → 画面上下各 22% 模型根本看不到 → 一律抠成背景，人被切头切肩
  ///   · 留边填灰 → 模型没见过这种分布 → 直接输出一坨怪块（真机实测）
  ///   MODNet 的 ONNX 本来就是动态轴，直接喂 9:16 最干净：不裁、不留、细节也不丢。
  int inputH = 0;
  int inputW = 0;

  /// 兼容旧写法（= 高）。新代码请用 inputH / inputW。
  int get inputSize => inputH;

  /// 输出张量元素个数（= inputH × inputW）
  int outputElementCount = 0;

  String inputName = '';
  String outputName = '';
  String ortVersion = '';
  String activeProvider = 'CPUExecutionProvider';
  String lastError = '';

  /// ★open() 失败的原因。失败时实例会被丢弃，只能靠静态字段把错误带出来
  /// （容器里没有 logcat，端侧排障全靠这一个字符串）。
  static String lastOpenError = '';

  /// 输入缓冲：native 内存 + Dart 侧视图，跨帧复用。
  late final Float32List inputF32;
  late final Uint8List inputU8;

  Pointer<Void> _inValue = nullptr;
  Pointer<Void> _inData = nullptr;
  Pointer<Void> _outValue = nullptr;
  Pointer<Void> _outData = nullptr;
  Pointer<Void> _inNames = nullptr;
  Pointer<Void> _outNames = nullptr;
  Pointer<Void> _inSlots = nullptr;
  Pointer<Void> _outSlots = nullptr;
  Pointer<Uint8> _inNameC = nullptr;
  Pointer<Uint8> _outNameC = nullptr;

  late final _DRun _runFn;
  late final _DStr _getErrMsgFn;
  late final _DVoidA _releaseStatusFn;
  late final _DVoidA _releaseValueFn;
  late final _DVoidA _releaseSessionFn;
  late final _DVoidA _releaseMemInfoFn;
  late final _DVoidA _releaseOptsFn;
  late final _DVoidA _releaseEnvFn;
  late final _DVoidAA _allocatorFreeFn;

  bool _ok = false;

  /// 打开模型。[preferSize] / [preferW] / [preferH] 只在模型输入是动态轴时生效。
  /// 不传 preferW/preferH 时退回正方形 preferSize。
  static OrtSession? open(String modelPath,
      {int threads = 3,
      int preferSize = 512,
      int? preferW,
      int? preferH,
      String preferProvider = 'XNNPACK',
      bool parMode = false}) {
    lastOpenError = '';
    final base = _openApiBase();
    if (base == nullptr) {
      lastOpenError = 'libonnxruntime 未加载（so 找不到）';
      return null;
    }
    final getApi = Pointer<NativeFunction<_NGetApi>>.fromAddress(
            base.cast<Pointer<Void>>()[_iApiBaseGetApi].address)
        .asFunction<_DGetApi>();
    // ---- ★运行时自检 1：读 OrtApiBase 的版本串 ----
    // GetVersionString 是 OrtApiBase 的固定成员（下标 1）。若我们对 ABI 的假设
    // 有误，这里会读到乱码 → 立刻判定不可用，交上层降级到色布/实景。
    final verRaw = _readCStr(Pointer<NativeFunction<_NGetVersion>>.fromAddress(
            base.cast<Pointer<Void>>()[_iApiBaseGetVersionString].address)
        .asFunction<_DGetVersion>()());
    final vm = RegExp(r'^(\d+)\.(\d+)\.').firstMatch(verRaw);
    if (vm == null) return null;
    if (int.parse(vm.group(2)!) < kOrtApiVersion) return null;
    // ---- ★运行时自检 2：取 OrtApi ----
    // ORT 明确承诺 OrtApi 结构体「只追加、不改动」，且对**高于自身**的版本号返回 null。
    // 所以 GetApi(28) 非空 ⇒ 本文件下表里所有下标（最大 216 < 413）都是正确位置。
    // 设备上 sherpa 自带的 .so 版本串是 VERS_1.28.2，与之严格对应。
    final apiAddr = getApi(kOrtApiVersion);
    if (apiAddr == nullptr) return null;
    final api = apiAddr.cast<Pointer<Void>>();

    Pointer<Void> env = nullptr;
    Pointer<Void> opts = nullptr;
    Pointer<Void> session = nullptr;
    Pointer<Void> memInfo = nullptr;
    Pointer<Uint8> tmpCStr = nullptr;
    // 成功把 self 交出去之后置 true；没交出去就在 finally 里把资源还回去
    var handedOver = false;

    // 少量 8 字节壳指针（输出槽），统一在 finally 回收
    final shell = <Pointer<Void>>[];
    Pointer<Void> newShell() {
      final p = ortMalloc(8);
      shell.add(p);
      return p;
    }

    /// 只取错误文本（释放 Status），**不写 lastOpenError** —— 用于"可以失败"
    /// 的调用，但我们需要知道原因（诊断用）。
    String errText(Pointer<Void> st) {
      if (st == nullptr) return '';
      final code = _dInt32(api, _iGetErrorCode)(st);
      final msg = _readCStr(_dStr(api, _iGetErrorMessage)(st), max: 400);
      _dVoidA(api, _iReleaseStatus)(st);
      return '[$code] $msg';
    }

    String takeErr(Pointer<Void> st) {
      if (st == nullptr) return '';
      final code = _dInt32(api, _iGetErrorCode)(st);
      final msg = _readCStr(_dStr(api, _iGetErrorMessage)(st));
      _dVoidA(api, _iReleaseStatus)(st);
      lastOpenError = '[$code] $msg'; // ★失败原因带出去
      return '[$code] $msg';
    }

    try {
      // ---- Env ----
      tmpCStr = ortCStr('live_toolbox');
      final envOut = newShell();
      final e1 = takeErr(_dStatusI32AOut(api, _iCreateEnv)(
          _ortLoggingError, tmpCStr, _pp(envOut)));
      ortFree(tmpCStr);
      tmpCStr = nullptr;
      if (e1.isNotEmpty) return null;
      env = _pp(envOut).value;

      // ---- SessionOptions ----
      final soOut = newShell();
      final e2 = takeErr(_dStatusOut(
          api, _iCreateSessionOptions)(_pp(soOut)));
      if (e2.isNotEmpty) return null;
      opts = _pp(soOut).value;

      _dStatusAI(
          api, _iSetSessionLogSeverityLevel)(opts, _ortLoggingError);
      _dStatusAI(api, _iSetIntraOpNumThreads)(opts, threads);
      _dStatusAI(api, _iSetInterOpNumThreads)(opts, 1);
      _dStatusAI(
          api, _iSetSessionGraphOptimizationLevel)(opts, _ortEnableAll);
      // ★执行模式：0=顺序(ORT_SEQUENTIAL) / 1=并行(ORT_PARALLEL)。
      //   MODNet 的图里有多条可并行的分支，并行模式有时能吃到好处 ——
      //   但也可能因线程竞争更慢，所以由上层**实测**决定（parMode）。
      _dStatusAI(api, _iSetSessionExecutionMode)(opts, parMode ? 1 : 0);
      _dStatusA(api, _iEnableCpuMemArena)(opts);
      _dStatusA(api, _iEnableMemPattern)(opts);

      // 按 preferProvider 挂执行提供器：'NNAPI'（NPU/GPU 加速）、'XNNPACK'（ARM
      // 向量优化）、'CPU'（不挂任何 EP，走 ORT 默认 CPU）。
      // ★挂不上时**直接返回 null**（由上层换组合），不再静默回落 CPU —— 详见下面。
      // ★★★ 顺序很重要：**先钉动态轴，再挂执行提供器**。
      //   ① 轴没钉住的组合，挂上了也没意义（硬件 EP 分区不了"形状未知"的算子）；
      //   ② 上一版把它放在挂载之后 —— 而挂载一失败就提前 return，导致 HUD 上
      //      `钉轴[]` 永远是"无"，把"轴名写错"这条线索自己藏起来了。
      // ---- ★把动态轴钉死（NNAPI 生效的**必要条件**）----
      // 硬件 EP 无法为"形状未知"的算子分配资源：模型输入是 [batch,3,height,width]
      // 符号轴时，它们会整段退回 CPU（挂了等于没挂），有的直接拒绝。
      // 模型里轴的 dim_param 名实测为 batch / height / width。
      // 名字对不上时 ORT 只会返回错误 Status，静默丢掉即可（dropErr）。
      lastPinLog = '';
      lastPinErr = '';
      if (preferW != null && preferW > 0 && preferH != null && preferH > 0) {
        // ★轴名必须是模型里**真实的 dim_param**。上一版把 batch 写成了 'batch'
        //   （这个名字根本不存在）→ batch_size 仍是动态轴 → **NNAPI 照样拒绝分区**。
        //   实测（直接解析 assets/models/modnet.onnx）：
        //     input  [ 'batch_size', 3, 'height', 'width' ]
        //     output [ 'batch_size', 1, 'height', 'width' ]
        // 钉成功的项记进 lastPinLog 上 HUD —— 空串就说明一个都没钉上。
        final pins = <String>[];
        for (final d in <List<Object>>[
          <Object>['batch_size', 1],
          <Object>['height', preferH],
          <Object>['width', preferW],
          <Object>['batch', 1], // 兼容别处导出的写法（不存在时 ORT 只回错误 Status）
        ]) {
          tmpCStr = ortCStr(d[0] as String);
          final st = _dStatusAI64(api, _iAddFreeDimensionOverrideByName)(
              opts, tmpCStr, d[1] as int);
          ortFree(tmpCStr);
          tmpCStr = nullptr;
          if (st == nullptr) {
            pins.add('${d[0]}=${d[1]}');
          } else {
            // ★不再静默丢掉：把 ORT 的原始报错留下（上一次就是被吞了才白猜）
            lastPinErr = '${d[0]}: ${errText(st)}';
          }
        }
        lastPinLog = pins.join(',');
      }

      var provider = 'CPUExecutionProvider';
      // ---- ★运行时枚举执行提供器（决定性诊断 + 修复挂载）----
      // 以前直接把 'NNAPI' / 'XNNPACK' 交给 AppendExecutionProvider，**一直失败**
      // （HUD 上永远是 CPUExecutionProvider）→ 全程白跑纯 CPU，这也是"抠像不如
      // 别家清晰"的根：CPU 根本算不动更高分辨率的输入。
      // 不同 ORT 版本对名字写法要求不一（'NNAPI' / 'NnapiExecutionProvider' / 大小写），
      // 所以这里不猜：先问运行时"你到底注册了哪些"，再按**真实注册名**挂。
      final avail = _listProviders(api);
      lastProviders = avail;
      if (preferProvider.toUpperCase() != 'CPU') {
        final want = preferProvider.toLowerCase();
        final cands = <String>[];
        for (final n in avail) {
          if (n.toLowerCase().contains(want)) cands.add(n);
        }
        cands.add('${preferProvider}ExecutionProvider');
        cands.add(preferProvider);
        final tried = <String>{};
        for (final name in cands) {
          if (!tried.add(name)) continue;
          tmpCStr = ortCStr(name);
          final st = _dStatusEp(
              api, _iSessionOptionsAppendExecutionProvider)(
              opts, tmpCStr, nullptr, nullptr, 0);
          ortFree(tmpCStr);
          tmpCStr = nullptr;
          if (st == nullptr) {
            provider = name;
            lastEpErr = '';
            break;
          }
          // ★留最后一条真实报错：它才说明"为什么挂不上"
          //   （库在不在、名字对不对、EP 自己的 preload 失败……都在这句里）
          lastEpErr = '$name: ${errText(st)}';
        }
        if (provider == 'CPUExecutionProvider') {
          // ★挂不上就**立刻判本次组合失败，不建 session**：
          //   照旧建下去只会拿到一个纯 CPU 的 session，白白加载一次 25MB 模型、
          //   还让上层误以为"这组可用"。
          lastOpenError = '执行提供器 $preferProvider 挂不上'
              '${lastEpErr.isEmpty ? '' : ' → $lastEpErr'}'
              '（本机可用: ${avail.isEmpty ? "枚举失败" : avail.join("/")}）';
          return null;
        }
      }

      // ---- Session ----
      tmpCStr = ortCStr(modelPath);
      final sOut = newShell();
      final e3 = takeErr(_dStatusCreateSession(
          api, _iCreateSession)(env, tmpCStr, opts, _pp(sOut)));
      ortFree(tmpCStr);
      tmpCStr = nullptr;
      if (e3.isNotEmpty) return null;
      session = _pp(sOut).value;

      // ---- CPU MemInfo（一次） ----
      final miOut = newShell();
      final e4 = takeErr(_dStatusI32I32Out(
              api, _iCreateCpuMemoryInfo)(
          _ortArenaAllocator, _ortMemTypeDefault, _pp(miOut)));
      if (e4.isNotEmpty) return null;
      memInfo = _pp(miOut).value;

      // ---- 默认 allocator ----
      final allocOut = newShell();
      if (takeErr(_dStatusOut(
              api, _iGetAllocatorWithDefaultOptions)(_pp(allocOut)))
          .isNotEmpty) {
        return null;
      }
      final allocator = _pp(allocOut).value;

      final self = OrtSession._(env, opts, session, memInfo, allocator);
      self.activeProvider = provider;
      self.ortVersion = verRaw;

      // ---- 输入/输出名（ORT 用默认 allocator 分配，dispose 时交还） ----
      final nameOut = newShell();
      if (takeErr(_dStatusAI32AOut(
              api, _iSessionGetInputName)(
          session, 0, allocator, _ppChar(nameOut))).isNotEmpty) {
        return null;
      }
      self._inNameC = _ppChar(nameOut).value;
      self.inputName = _readCStr(self._inNameC);

      final outNameOut = newShell();
      if (takeErr(_dStatusAI32AOut(
              api, _iSessionGetOutputName)(
          session, 0, allocator, _ppChar(outNameOut))).isNotEmpty) {
        return null;
      }
      self._outNameC = _ppChar(outNameOut).value;
      self.outputName = _readCStr(self._outNameC);

      // ---- 输入类型/形状 ----
      final tiOut = newShell();
      if (takeErr(_dStatusAIAOut(
              api, _iSessionGetInputTypeInfo)(session, 0, _pp(tiOut)))
          .isNotEmpty) {
        return null;
      }
      final ti = _pp(tiOut).value;
      final tsOut = newShell();
      if (takeErr(_dStatusAOut(
              api, _iCastTypeInfoToTensorInfo)(ti, _pp(tsOut)))
          .isNotEmpty) {
        return null;
      }
      final ts = _pp(tsOut).value;
      final etP = ortMalloc(4).cast<Int32>();
      if (takeErr(_dStatusAI32POut(
              api, _iGetTensorElementType)(ts, etP))
          .isEmpty) {
        self.inputElementType = etP[0];
      }
      ortFree(etP);

      final dcP = ortMalloc(8).cast<IntPtr>();
      final dims = <int>[];
      if (takeErr(_dStatusAIPOut(
              api, _iGetDimensionsCount)(ts, dcP))
          .isEmpty) {
        final dc = dcP[0];
        if (dc > 0) {
          final dP = ortMalloc(8 * dc).cast<Int64>();
          if (takeErr(_dStatusPInt64I(
                  api, _iGetDimensions)(ts, dP, dc))
              .isEmpty) {
            for (int i = 0; i < dc; i++) {
              dims.add(dP[i]);
            }
          }
          ortFree(dP);
        }
      }
      ortFree(dcP);

      if (dims.length != 4) {
        lastOpenError = '模型输入不是 4 维（odc=$dims）';
        return null;
      }
      final h = dims[2] > 0 ? dims[2] : (preferH ?? preferSize);
      final w = dims[3] > 0 ? dims[3] : (preferW ?? preferSize);
      if (h <= 0 || w <= 0) {
        lastOpenError = '输入尺寸解析失败 h=$h w=$w';
        return null;
      } // ★不再要求 h == w
      self.inputH = h;
      self.inputW = w;

      // ---- 输出元素数 ----
      // ★坑（已在 x86 上用 ctypes 预演复现）：MODNet 的输出也是**动态轴**，
      //   此时 `GetTensorShapeElementCount` 会直接返回
      //   `/SafeIntOnOverflow Integer overflow`，拿不到元素数。
      //   正确做法：自己读维度，把负数（动态）维用"我们选定的输入尺寸"补上再相乘。
      final otiOut = newShell();
      if (takeErr(_dStatusAIAOut(
              api, _iSessionGetOutputTypeInfo)(session, 0, _pp(otiOut)))
          .isNotEmpty) {
        return null;
      }
      final oti = _pp(otiOut).value;
      final otsOut = newShell();
      if (takeErr(_dStatusAOut(
              api, _iCastTypeInfoToTensorInfo)(oti, _pp(otsOut)))
          .isNotEmpty) {
        return null;
      }
      final ots = _pp(otsOut).value;
      final oetP = ortMalloc(4).cast<Int32>();
      if (takeErr(_dStatusAI32POut(
              api, _iGetTensorElementType)(ots, oetP))
          .isEmpty) {
        self.outputElementType = oetP[0];
      }
      ortFree(oetP);

      final odcP = ortMalloc(8).cast<IntPtr>();
      var outElems = 0;
      if (takeErr(_dStatusAIPOut(
              api, _iGetDimensionsCount)(ots, odcP))
          .isEmpty) {
        final odc = odcP[0];
        if (odc > 0) {
          final odP = ortMalloc(8 * odc).cast<Int64>();
          if (takeErr(_dStatusPInt64I(
                  api, _iGetDimensions)(ots, odP, odc))
              .isEmpty) {
            outElems = 1;
            for (int i = 0; i < odc; i++) {
              final d = odP[i];
              // 动态维：批维（第 0 维）补 1，空间维按 [2]=高 / [3]=宽 补
              outElems *= d > 0 ? d : (i == 0 ? 1 : (i == 2 ? h : w));
            }
          }
          ortFree(odP);
        }
      }
      ortFree(odcP);
      // 兜底：MODNet 输出就是 1×1×S×S
      if (outElems <= 0) outElems = h * w;
      self.outputElementCount = outElems;

      // ---- 输入张量（native 缓冲，一次建好，跨帧复用） ----
      final inLen = h * w * 3 * ortElemBytes(self.inputElementType);
      self._inData = ortMalloc(inLen);
      if (self.inputElementType == kOrtTypeFloat) {
        self.inputF32 = self._inData.cast<Float>().asTypedList(inLen ~/ 4);
        self.inputU8 = Uint8List(0);
      } else {
        self.inputU8 = self._inData.cast<Uint8>().asTypedList(inLen);
        self.inputF32 = Float32List(0);
      }

      final inShape = ortMalloc(32).cast<Int64>();
      inShape[0] = 1;
      inShape[1] = 3;
      inShape[2] = h;
      inShape[3] = w;
      final inValOut = newShell();
      final e6 = takeErr(_dStatusTensorData(
              api, _iCreateTensorWithDataAsOrtValue)(
          memInfo, self._inData, inLen, inShape, 4, self.inputElementType,
          _pp(inValOut)));
      ortFree(inShape);
      if (e6.isNotEmpty) {
        lastOpenError = '建输入张量失败: $e6';
        return null;
      }
      self._inValue = _pp(inValOut).value;

      // ---- 输出张量（native 缓冲，一次建好） ----
      final outLen =
          self.outputElementCount * ortElemBytes(self.outputElementType);
      self._outData = ortMalloc(outLen);
      final outShape = ortMalloc(32).cast<Int64>();
      outShape[0] = 1;
      outShape[1] = 1;
      outShape[2] = h;
      outShape[3] = w;
      final outValOut = newShell();
      final e7 = takeErr(_dStatusTensorData(
              api, _iCreateTensorWithDataAsOrtValue)(
          memInfo, self._outData, outLen, outShape, 4, self.outputElementType,
          _pp(outValOut)));
      ortFree(outShape);
      if (e7.isNotEmpty) {
        lastOpenError = '建输出张量失败: $e7';
        return null;
      }
      self._outValue = _pp(outValOut).value;

      // ---- Run 用到的数组 ----
      self._inNames = ortMalloc(8);
      self._outNames = ortMalloc(8);
      self._inSlots = ortMalloc(8);
      self._outSlots = ortMalloc(8);
      self._inNames.cast<Pointer<Uint8>>()[0] = self._inNameC;
      self._outNames.cast<Pointer<Uint8>>()[0] = self._outNameC;
      self._inSlots.cast<Pointer<Void>>()[0] = self._inValue;
      self._outSlots.cast<Pointer<Void>>()[0] = self._outValue;

      // ---- 热路径函数指针 ----
      self._runFn = _dRun(api, _iRun);
      self._getErrMsgFn = _dStr(api, _iGetErrorMessage);
      self._releaseStatusFn = _dVoidA(api, _iReleaseStatus);
      self._releaseValueFn = _dVoidA(api, _iReleaseValue);
      self._releaseSessionFn = _dVoidA(api, _iReleaseSession);
      self._releaseMemInfoFn = _dVoidA(api, _iReleaseMemoryInfo);
      self._releaseOptsFn = _dVoidA(api, _iReleaseSessionOptions);
      self._releaseEnvFn = _dVoidA(api, _iReleaseEnv);
      self._allocatorFreeFn = _dVoidAA(api, _iAllocatorFree);

      self._ok = true;
      handedOver = true;
      return self;
    } catch (e) {
      lastOpenError = '异常: $e';
      return null;
    } finally {
      ortFree(tmpCStr);
      for (final p in shell) {
        ortFree(p);
      }
      if (!handedOver) {
        // 失败路径：把已经建好的资源还回去，别在反复重试时把 native 内存漏光
        void rel(int idx, Pointer<Void> h) {
          if (h == nullptr) return;
          _dVoidA(api, idx)(h);
        }

        rel(_iReleaseSession, session);
        rel(_iReleaseMemoryInfo, memInfo);
        rel(_iReleaseSessionOptions, opts);
        rel(_iReleaseEnv, env);
      }
    }
  }

  /// 跑一次推理。输入用 [inputF32]（或 [inputU8]）填好。
  /// 成功返回长度 = [outputElementCount] 的软 alpha（0~1），失败返回 null。
  Float32List? run() {
    if (!_ok) return null;
    try {
      final st = _runFn(
        _session,
        nullptr,
        _inNames.cast<Pointer<Uint8>>(),
        _inSlots.cast<Pointer<Void>>(),
        1,
        _outNames.cast<Pointer<Uint8>>(),
        1,
        _outSlots.cast<Pointer<Void>>(),
      );
      if (st != nullptr) {
        lastError = _readCStr(_getErrMsgFn(st));
        _releaseStatusFn(st);
        return null;
      }
      final n = outputElementCount;
      if (outputElementType == kOrtTypeFloat) {
        return Float32List.fromList(_outData.cast<Float>().asTypedList(n));
      }
      // uint8 / int8 量化输出 → 归一到 0~1
      final view = _outData.cast<Uint8>().asTypedList(n);
      final out = Float32List(n);
      const inv = 1.0 / 255.0;
      for (int i = 0; i < n; i++) {
        out[i] = view[i] * inv;
      }
      return out;
    } catch (e) {
      lastError = '$e';
      return null;
    }
  }

  void dispose() {
    if (!_ok) return;
    _ok = false;
    try {
      _releaseValueFn(_inValue);
      _inValue = nullptr;
      _releaseValueFn(_outValue);
      _outValue = nullptr;

      ortFree(_inData);
      _inData = nullptr;
      ortFree(_outData);
      _outData = nullptr;

      // 名字由 ORT 的默认 allocator 分配，交还它自己释放
      if (_inNameC != nullptr) _allocatorFreeFn(_allocator, _inNameC.cast<Void>());
      if (_outNameC != nullptr) {
        _allocatorFreeFn(_allocator, _outNameC.cast<Void>());
      }
      _inNameC = nullptr;
      _outNameC = nullptr;

      ortFree(_inNames);
      ortFree(_outNames);
      ortFree(_inSlots);
      ortFree(_outSlots);
      _inNames = _outNames = _inSlots = _outSlots = nullptr;

      _releaseSessionFn(_session);
      _releaseMemInfoFn(_memInfo);
      _releaseOptsFn(_opts);
      _releaseEnvFn(_env);
    } catch (_) {}
  }

  /// 最近一次 open() 时**运行时枚举到的执行提供器**（诊断用）。
  /// ★有的机器其实支持 NPU，只是我们以前把名字挂错了 —— 这份列表就是判据。
  static List<String> lastProviders = <String>[];

  /// 最近一次 open() 里"钉动态轴"实际成功的那些（诊断用，直接上 HUD）。
  /// 空串 = 一个都没钉上（那 NNAPI 必然挂不上）。
  static String lastPinLog = '';

  /// 钉轴失败时的**原始 ORT 报错**（上一版把它吞了，害我白猜一轮）。
  static String lastPinErr = '';

  /// 挂执行提供器失败时的**原始 ORT 报错**。
  static String lastEpErr = '';

  /// 运行时枚举已注册的执行提供器（open() 内部用；失败返回空表，不抛）。
  static List<String> _listProviders(Pointer<Pointer<Void>> api) {
    final out = <String>[];
    try {
      final p = ortMalloc(8).cast<Pointer<Pointer<Uint8>>>();
      final lenP = ortMalloc(4).cast<Int32>();
      final st = _dStatusProviders(api, _iGetAvailableProviders)(p, lenP);
      if (st != nullptr) {
        _dVoidA(api, _iReleaseStatus)(st);
        ortFree(p);
        ortFree(lenP);
        return out;
      }
      final arr = p.value;
      final n = lenP[0];
      for (int i = 0; i < n; i++) {
        out.add(_readCStr(arr[i]));
      }
      _dVoidAI(api, _iReleaseAvailableProviders)(arr.cast<Void>(), n);
      ortFree(p);
      ortFree(lenP);
    } catch (_) {}
    return out;
  }

  /// ★诊断：**从 App 进程内**（= 卓易通容器里）到底能 dlopen 到哪些底层库。
  ///
  /// 为什么必须在这里测：hdc shell 看到的是**鸿蒙侧**的 /system，不是容器的
  /// Android 用户态 —— 在鸿蒙侧找不到 libneuralnetworks.so 并不能说明容器里没有。
  /// 库里有什么，才决定"GPU / NNAPI / 厂商 NPU"这条路到底存不存在。
  static String probeRuntimeLibs() {
    const cands = <String>[
      'libneuralnetworks.so', // Android NNAPI（NPU/GPU 的官方入口）
      'libEGL.so', // 容器有没有 GPU 上下文
      'libGLESv3.so',
      'libvulkan.so',
      'libOpenCL.so',
      'libnnrt.so', // 华为 NN Runtime（CANN/达芬奇）
      'libhiai.so', // 华为 HiAI
      'libmindspore_lite.so',
    ];
    final ok = <String>[];
    for (final n in cands) {
      try {
        DynamicLibrary.open(n);
        ok.add(n.substring(3, n.length - 3)); // 去掉 lib/.so
      } catch (_) {}
    }
    return ok.join(',');
  }

  /// 诊断：本机 ORT 实际注册了哪些执行提供器。只应在加载/排障时调一次。
  static List<String> availableProviders() {
    final out = <String>[];
    try {
      final base = _openApiBase();
      if (base == nullptr) return out;
      final getApi = Pointer<NativeFunction<_NGetApi>>.fromAddress(
              base.cast<Pointer<Void>>()[_iApiBaseGetApi].address)
          .asFunction<_DGetApi>();
      final apiAddr = getApi(kOrtApiVersion);
      if (apiAddr == nullptr) return out;
      final api = apiAddr.cast<Pointer<Void>>();

      // char*** out_ptr / int* provider_length
      final p = ortMalloc(8).cast<Pointer<Pointer<Uint8>>>();
      final lenP = ortMalloc(4).cast<Int32>();
      final st = _dStatusProviders(
          api, _iGetAvailableProviders)(p, lenP);
      if (st != nullptr) {
        ortFree(p);
        ortFree(lenP);
        return out;
      }
      final arr = p.value;
      final n = lenP[0];
      for (int i = 0; i < n; i++) {
        out.add(_readCStr(arr[i]));
      }
      _dVoidAI(api, _iReleaseAvailableProviders)(
          arr.cast<Void>(), n);
      ortFree(p);
      ortFree(lenP);
    } catch (_) {}
    return out;
  }
}

Pointer<Void> _openApiBase() {
  // 1) 按 soname 打开 App 自带的 libonnxruntime.so（由 sherpa_onnx 打包进来）
  for (final name in <String>['libonnxruntime.so', 'libonnxruntime.so.1']) {
    try {
      final f = DynamicLibrary.open(name)
          .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
              'OrtGetApiBase');
      final p = f();
      if (p != nullptr) return p;
    } catch (_) {}
  }
  // 2) 兜底：sherpa 加载过 .so 后符号可能已进入全局命名空间
  try {
    final f = DynamicLibrary.process()
        .lookupFunction<Pointer<Void> Function(), Pointer<Void> Function()>(
            'OrtGetApiBase');
    final p = f();
    if (p != nullptr) return p;
  } catch (_) {}
  return nullptr;
}
