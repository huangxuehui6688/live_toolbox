package com.livetoolbox.live_toolbox

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    /** 自建的悬浮窗权限通道（直达本应用授权页），见 OverlayPermissionChannel.kt */
    private val overlayPermission = OverlayPermissionChannel(this)

    /** GPU 能力探测通道（懒初始化：不在构造期建，避免与 context 初始化时序冲突） */
    private var gpuProbe: GpuProbeChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // 先注册 Flutter 默认插件（flutter_overlay_window 等）
        super.configureFlutterEngine(flutterEngine)
        overlayPermission.register(flutterEngine)
        gpuProbe = GpuProbeChannel(this).also { it.register(flutterEngine) }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 先给 Flutter 引擎转发，保证插件的 Activity 回调正常
        super.onActivityResult(requestCode, resultCode, data)
        // 再处理本类的请求：用户从悬浮窗授权页返回时结算授权结果
        overlayPermission.onActivityResult(requestCode)
    }

    override fun onResume() {
        super.onResume()
        // 兜底：部分 ROM 从设置页返回不回调 onActivityResult
        overlayPermission.onResume()
    }

    override fun onDestroy() {
        overlayPermission.dispose()
        super.onDestroy()
    }
}
