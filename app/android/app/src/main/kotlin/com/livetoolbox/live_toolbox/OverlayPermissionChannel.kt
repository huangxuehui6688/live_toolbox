package com.livetoolbox.live_toolbox

import android.app.Activity
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 「显示在其他应用上层」（悬浮窗）权限通道。
 *
 * 背景：flutter_overlay_window 的 requestPermission 在华为鸿蒙（卓易通容器）上会落到
 * 「应用列表」页，用户得一个个翻找本应用；且卓易通容器的悬浮窗可能盖不住鸿蒙原生 App、
 * Settings.canDrawOverlays 也可能恒为 false——这些都改不了。本通道只做一件事：把
 * 「授权这一步」做到最顺、最不烦人——
 *
 *  1. 先查后弹：已授权直接返回，绝不弹系统设置页；
 *  2. 自动弹页全局只发生一次（planBFlag 持久化），第二次起交回 Dart 弹中文指引层；
 *  3. 结果驱动探测入口：带包名直达 → 不带包名 → 应用详情 → 华为系统管家，依次
 *     startActivityForResult + try/catch，谁打开算谁，打不开静默跳过（不靠品牌判断）；
 *  4. 同会话「手动重开设置页」只 1 次（manualReopenUsed，会话开始由 Dart 重置）。
 *
 * 返回值（多态字符串，Dart 据此决定下一步）：
 *  - "granted"     已授权
 *  - "denied"      打开了系统页，但用户没给权限（已置 planBFlag，下次不再自动弹）
 *  - "needGuide"   planBFlag 已置位，不应再自动弹，交给 Dart 弹中文指引层
 *  - "guideOnly"   手动重开已达本会话上限，Dart 只显示指引
 *  - "unavailable" 系统里找不到可用的授权页
 */
class OverlayPermissionChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        /** 与 lib/services/overlay_service.dart 里的通道名保持一致，不要单改一边 */
        const val CHANNEL_NAME = "live_toolbox/overlay_permission"

        /** 本类私有的 requestCode，避免和插件（1248）冲突 */
        private const val REQUEST_CODE = 0x4F10

        private const val TAG = "OverlayPermission"

        // 状态机三件套：SharedPreferences 文件名与键
        private const val PREFS_NAME = "overlay_permission_state"
        private const val KEY_PLAN_B = "planBFlag"
        private const val KEY_LAST_ATTEMPT_AT = "lastAttemptAt"
        private const val KEY_MANUAL_REOPEN_USED = "manualReopenUsed"

        private const val RESULT_GRANTED = "granted"
        private const val RESULT_DENIED = "denied"
        private const val RESULT_NEED_GUIDE = "needGuide"
        private const val RESULT_GUIDE_ONLY = "guideOnly"
        private const val RESULT_UNAVAILABLE = "unavailable"
    }

    private var channel: MethodChannel? = null

    /** 系统设置页还没返回时挂起的 Dart 回调 */
    private var pendingResult: MethodChannel.Result? = null

    /** 结果驱动探测的日志字段：本轮入口探测的「前值」，返回时和「后值」一起打日志 */
    private var lastOpenedAction: String = "none"
    private var lastThrew: Boolean = false
    private var canDrawBefore: Boolean = false
    private var planBAtLaunch: Boolean = false

    /**
     * ★必须懒加载：本类是 MainActivity 的属性，属性初始化发生在 Activity 构造阶段，
     *  那时 base context 还没 attach，直接 getSharedPreferences 会 NPE → 启动即闪退。
     *  延迟到首次真正用到时（已在 onCreate 之后）再取。
     */
    private val prefs by lazy { activity.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE) }

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null
        // 不能静默丢弃挂起的回调，否则 Dart 侧的 Future 会永久挂起
        finishPending()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasPermission" -> result.success(hasOverlayPermission())
            "requestPermission" -> requestPermission(result)
            "openManual" -> openManual(result)
            "resetSession" -> resetSession(result)
            else -> result.notImplemented()
        }
    }

    /** Android 6.0（API 23）起才有这个特殊权限，更低版本视为已授权 */
    private fun hasOverlayPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return Settings.canDrawOverlays(activity)
    }

    /**
     * 开启悬浮窗时的权限申请（状态机核心）。
     * 已授权 → granted；planBFlag 已置位 → needGuide；否则首次自动弹（结果驱动探测）。
     */
    private fun requestPermission(result: MethodChannel.Result) {
        // 已授权就别打扰用户：这是「不要一个个去点」的第一道保险
        if (hasOverlayPermission()) {
            result.success(RESULT_GRANTED)
            return
        }
        // 上一个请求还没结算（用户可能把设置页切到后台，永不回调 onResume）：
        // 先按当前真实状态把它结算掉，否则 Dart 侧的 Future 会永久挂起。
        finishPending()

        val planB = prefs.getBoolean(KEY_PLAN_B, false)
        if (planB) {
            // 自动弹页全局只发生一次：第二次起交给 Dart 弹中文指引层
            result.success(RESULT_NEED_GUIDE)
            return
        }

        // 首次自动弹：记录时间，结果驱动探测入口
        prefs.edit().putLong(KEY_LAST_ATTEMPT_AT, System.currentTimeMillis()).apply()
        launchCandidates(result)
    }

    /** 用户主动点「仍然不行？手动打开系统设置页」：同会话只 1 次 */
    private fun openManual(result: MethodChannel.Result) {
        if (hasOverlayPermission()) {
            result.success(RESULT_GRANTED)
            return
        }
        finishPending()

        if (prefs.getBoolean(KEY_MANUAL_REOPEN_USED, false)) {
            // 本会话手动重开已达上限，只让 Dart 显示指引
            result.success(RESULT_GUIDE_ONLY)
            return
        }
        prefs.edit().putBoolean(KEY_MANUAL_REOPEN_USED, true).apply()

        launchCandidates(result)
    }

    /** 会话开始（App 冷启动）时由 Dart 调用：重置「本会话手动重开」标记 */
    private fun resetSession(result: MethodChannel.Result) {
        prefs.edit().putBoolean(KEY_MANUAL_REOPEN_USED, false).apply()
        result.success(null)
    }

    /** 结果驱动探测：依次尝试候选入口，第一个能打开的就是它，打不开静默跳过 */
    private fun launchCandidates(result: MethodChannel.Result) {
        canDrawBefore = hasOverlayPermission()
        planBAtLaunch = prefs.getBoolean(KEY_PLAN_B, false)

        val candidates = listOf(
            "scoped" to scopedIntent(),
            "generic" to genericIntent(),
            "appDetails" to appDetailsIntent(),
            "huaweiSysMgr" to huaweiSysMgrIntent(),
        )

        var opened: String? = null
        var threw = false
        for ((name, intent) in candidates) {
            val ok = try {
                activity.startActivityForResult(intent, REQUEST_CODE)
                true
            } catch (e: Exception) {
                threw = true
                false
            }
            if (ok) {
                opened = name
                break
            }
        }

        lastOpenedAction = opened ?: "none"
        lastThrew = threw

        if (opened == null) {
            result.success(RESULT_UNAVAILABLE)
            return
        }
        pendingResult = result
    }

    /** 直达「本应用」的悬浮窗授权页：只有一个开关，不用在应用列表里翻找 */
    private fun scopedIntent(): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
            data = Uri.parse("package:${activity.packageName}")
        }

    /** 兼容部分 ROM：不带包名的总入口 */
    private fun genericIntent(): Intent =
        Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)

    /** 应用详情页（应用信息 → 权限）：华为/卓易通常能落到这里 */
    private fun appDetailsIntent(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }

    /** 华为系统管家的悬浮窗权限页：打不开（类名不存在）会被 catch 静默跳过 */
    private fun huaweiSysMgrIntent(): Intent =
        Intent().setComponent(
            ComponentName(
                "com.huawei.systemmanager",
                "com.huawei.systemmanager.addviewmonitor.AddViewMonitorActivity"
            )
        )

    /** MainActivity.onActivityResult 转发进来；返回 true 表示是本类的请求 */
    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE) return false
        finishPending()
        return true
    }

    /** MainActivity.onResume 转发进来：部分 ROM 不回调 onActivityResult，这里兜底 */
    fun onResume() {
        finishPending()
    }

    /** 回传真实授权结果；MethodChannel.Result 只能回调一次，所以先清空再回调 */
    private fun finishPending() {
        val result = pendingResult ?: return
        pendingResult = null

        val canDrawAfter = hasOverlayPermission()
        Log.i(
            TAG,
            "openedAction=$lastOpenedAction threw=$lastThrew " +
                "canDrawBefore=$canDrawBefore canDrawAfter=$canDrawAfter " +
                "planBFlag=$planBAtLaunch"
        )

        if (canDrawAfter) {
            result.success(RESULT_GRANTED)
        } else {
            // 这一轮没拿到权限：置 planBFlag，下次不再自动弹，改为指引
            prefs.edit().putBoolean(KEY_PLAN_B, true).apply()
            result.success(RESULT_DENIED)
        }
    }
}
