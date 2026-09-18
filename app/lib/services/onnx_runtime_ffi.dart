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

  /// 模型输入边长（MODNet 是正方形输入）
  int inputSize = 0;

  /// 输出张量元素个数（= inputSize²）
  int outputElementCount = 0;

  String inputName = '';
  String outputName = '';
  String ortVersion = '';
  String activeProvider = 'CPUExecutionProvider';
  String lastError = '';

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

  /// 打开模型。[preferSize] 只在模型输入是动态轴时生效。
  static OrtSession? open(String modelPath,
      {int threads = 3, int preferSize = 512, String preferProvider = 'XNNPACK'}) {
    final base = _openApiBase();
    if (base == nullptr) return null;
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

    String takeErr(Pointer<Void> st) {
      if (st == nullptr) return '';
      final code = _dInt32(api, _iGetErrorCode)(st);
      final msg = _readCStr(_dStr(api, _iGetErrorMessage)(st));
      _dVoidA(api, _iReleaseStatus)(st);
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
      _dStatusAI(api, _iSetSessionExecutionMode)(opts, 0);
      _dStatusA(api, _iEnableCpuMemArena)(opts);
      _dStatusA(api, _iEnableMemPattern)(opts);

      // 按 preferProvider 名字挂执行提供器：'NNAPI'（NPU/GPU 加速，手机上若
      // 编译进了 NnapiExecutionProvider 就能吃上硬件算力）、'XNNPACK'（优化 CPU）。
      // ORT 里没编进去/名字不对时这里返回错误，静默回落 CPU —— 上层据此判断。
      var provider = 'CPUExecutionProvider';
      tmpCStr = ortCStr(preferProvider);
      final stEp = _dStatusEp(
          api, _iSessionOptionsAppendExecutionProvider)(
          opts, tmpCStr, nullptr, nullptr, 0);
      ortFree(tmpCStr);
      tmpCStr = nullptr;
      if (stEp == nullptr) {
        provider = '${preferProvider}ExecutionProvider';
      } else {
        takeErr(stEp);
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

      if (dims.length != 4) return null;
      final h = dims[2] > 0 ? dims[2] : preferSize;
      final w = dims[3] > 0 ? dims[3] : preferSize;
      if (h <= 0 || h != w) return null;
      self.inputSize = h;

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
              // 动态维：批维（第 0 维）补 1，空间维补我们选定的输入尺寸
              outElems *= d > 0 ? d : (i == 0 ? 1 : self.inputSize);
            }
          }
          ortFree(odP);
        }
      }
      ortFree(odcP);
      // 兜底：MODNet 输出就是 1×1×S×S
      if (outElems <= 0) outElems = self.inputSize * self.inputSize;
      self.outputElementCount = outElems;

      // ---- 输入张量（native 缓冲，一次建好，跨帧复用） ----
      final inLen = self.inputSize * self.inputSize * 3 *
          ortElemBytes(self.inputElementType);
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
      inShape[2] = self.inputSize;
      inShape[3] = self.inputSize;
      final inValOut = newShell();
      final e6 = takeErr(_dStatusTensorData(
              api, _iCreateTensorWithDataAsOrtValue)(
          memInfo, self._inData, inLen, inShape, 4, self.inputElementType,
          _pp(inValOut)));
      ortFree(inShape);
      if (e6.isNotEmpty) return null;
      self._inValue = _pp(inValOut).value;

      // ---- 输出张量（native 缓冲，一次建好） ----
      final outLen =
          self.outputElementCount * ortElemBytes(self.outputElementType);
      self._outData = ortMalloc(outLen);
      final outShape = ortMalloc(32).cast<Int64>();
      outShape[0] = 1;
      outShape[1] = 1;
      outShape[2] = self.inputSize;
      outShape[3] = self.inputSize;
      final outValOut = newShell();
      final e7 = takeErr(_dStatusTensorData(
              api, _iCreateTensorWithDataAsOrtValue)(
          memInfo, self._outData, outLen, outShape, 4, self.outputElementType,
          _pp(outValOut)));
      ortFree(outShape);
      if (e7.isNotEmpty) return null;
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
    } catch (_) {
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
