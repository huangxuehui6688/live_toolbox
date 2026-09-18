package com.livetoolbox.live_toolbox

import android.app.Activity
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLDisplay
import android.opengl.GLES31
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * GPU 可用性探测：验证容器里 OpenGL ES 3.1 的 compute shader 能不能用。
 *
 * 这是「端侧 GPU 加速」的前提——tflite GPU delegate / 任何 GPU 计算都依赖
 * GLES 3.1 compute shader。Flutter 能正常渲染只说明 GLES 基础可用，不代表
 * compute shader 可用，所以必须单独探。
 *
 * 返回一段人类可读的诊断文本（egl 版本 / gles 版本 / compute 能力 / shader 编译结果）。
 */
class GpuProbeChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL_NAME = "live_toolbox/gpu_probe"
        private const val TAG = "GpuProbe"
    }

    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> result.success(probeGpu())
            else -> result.notImplemented()
        }
    }

    private fun probeGpu(): String {
        val sb = StringBuilder()
        try {
            val display: EGLDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) {
                return "no EGL display"
            }
            val ver = IntArray(2)
            if (!EGL14.eglInitialize(display, ver, 0, ver, 1)) {
                return "eglInitialize failed"
            }
            sb.append("EGL ${ver[0]}.${ver[1]}; ")

            val configAttribs = intArrayOf(
                EGL14.EGL_RENDERABLE_TYPE, 0x40, // EGL_OPENGL_ES3_BIT（本 SDK 未暴露常量，直接写值）
                EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
                EGL14.EGL_NONE
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val num = IntArray(1)
            EGL14.eglChooseConfig(display, configAttribs, 0, configs, 0, 1, num, 0)
            if (num[0] == 0) {
                sb.append("no ES3 config")
                EGL14.eglTerminate(display)
                return sb.toString()
            }

            val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 3, EGL14.EGL_NONE)
            val ctx = EGL14.eglCreateContext(display, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
            if (ctx == EGL14.EGL_NO_CONTEXT) {
                sb.append("ES3 ctx create failed")
                EGL14.eglTerminate(display)
                return sb.toString()
            }
            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, ctx)

            val glver = GLES31.glGetString(GLES31.GL_VERSION) ?: "?"
            val glsl = GLES31.glGetString(GLES31.GL_SHADING_LANGUAGE_VERSION) ?: "?"
            sb.append("GLES $glver / GLSL $glsl; ")

            val maxComp = IntArray(1)
            GLES31.glGetIntegerv(GLES31.GL_MAX_COMPUTE_SHARED_MEMORY_SIZE, maxComp, 0)
            sb.append("computeShared=${maxComp[0]}; ")

            // 编译一个最小 compute shader，验证 compute 管线真的能跑
            val src = "#version 310 es\nlayout(local_size_x=1) in;\nvoid main(){}\n"
            val sh = GLES31.glCreateShader(GLES31.GL_COMPUTE_SHADER)
            if (sh == 0) {
                sb.append("compute shader create FAILED")
            } else {
                GLES31.glShaderSource(sh, src)
                GLES31.glCompileShader(sh)
                val status = IntArray(1)
                GLES31.glGetShaderiv(sh, GLES31.GL_COMPILE_STATUS, status, 0)
                sb.append("computeCompile=${if (status[0] == GLES31.GL_TRUE) "OK" else "FAIL"}")
                val log = GLES31.glGetShaderInfoLog(sh)
                if (!log.isNullOrEmpty()) sb.append("; log=${log.take(80)}")
                GLES31.glDeleteShader(sh)
            }

            EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            EGL14.eglDestroyContext(display, ctx)
            EGL14.eglTerminate(display)
        } catch (e: Throwable) {
            sb.append("EXCEPTION ${e.javaClass.simpleName}: ${e.message}")
        }
        Log.d(TAG, "probe result: $sb")
        return sb.toString()
    }
}
