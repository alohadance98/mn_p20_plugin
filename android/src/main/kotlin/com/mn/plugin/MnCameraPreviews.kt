package com.mn.plugin

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraMetadata
import android.hardware.camera2.CaptureRequest
import android.media.MediaRecorder
import android.os.Handler
import android.os.Looper
import android.util.Size
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Camera2 previews rendered into Flutter textures.
 *
 * On the P20 the video inputs (CH1..CH4) are exposed as ordinary Camera2
 * devices, addressed by their position in `CameraManager.cameraIdList` — the
 * same way the vendor demo's CameraActivity opens them.
 *
 * A preview outlives its camera connection: the texture stays registered while
 * the camera is released in the background ([onHostPaused]) or taken by another
 * app, and the camera is reopened into the same texture afterwards. Only when
 * reopening keeps failing is the preview dropped and `camera.lost` emitted.
 */
internal class MnCameraPreviews(
    private val context: Context,
    private val textures: TextureRegistry,
    private val emit: (event: String, payload: Map<String, Any?>) -> Unit,
) {
    private class Preview(val cameraId: String, val producer: TextureRegistry.SurfaceProducer) {
        var device: CameraDevice? = null
        var session: CameraCaptureSession? = null

        /** An openCamera call is in flight. */
        var opening = false

        /** Reopen attempts since the camera was last streaming. */
        var retries = 0
    }

    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    // Camera callbacks only carry state changes (frames go straight to the
    // surface), so everything runs on the main thread and needs no locking.
    private val handler = Handler(Looper.getMainLooper())
    private val previews = HashMap<Long, Preview>()

    /** Whether the host activity is in the foreground; cameras are only held then. */
    private var foreground = true

    fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    fun cameraIds(): List<String> = manager.cameraIdList.toList()

    /** Opens the camera at [index] and replies with `{textureId, width, height}`. */
    fun open(index: Int, result: MethodChannel.Result) {
        if (!hasPermission()) {
            return result.error("MN_CAMERA_PERMISSION", "CAMERA permission not granted", null)
        }
        val ids = manager.cameraIdList
        if (index !in ids.indices) {
            return result.error(
                "MN_CAMERA_NOT_FOUND", "No camera at index $index (${ids.size} available)", null,
            )
        }
        val cameraId = ids[index]
        val size = previewSize(cameraId)

        val producer = textures.createSurfaceProducer()
        producer.setSize(size.width, size.height)
        val textureId = producer.id()
        val preview = Preview(cameraId, producer)
        previews[textureId] = preview

        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            // The surface can be torn down in the background and recreated later.
            override fun onSurfaceAvailable() {
                if (preview.device != null && preview.session == null) startSession(preview, {}, {})
            }

            override fun onSurfaceCleanup() {
                runCatching { preview.session?.close() }
                preview.session = null
            }
        })

        val replied = AtomicBoolean(false)
        openDevice(
            preview,
            onReady = {
                if (replied.compareAndSet(false, true)) {
                    result.success(
                        mapOf("textureId" to textureId, "width" to size.width, "height" to size.height),
                    )
                }
            },
            onFailed = { message ->
                close(textureId)
                if (replied.compareAndSet(false, true)) result.error("MN_CAMERA_ERROR", message, null)
            },
        )
    }

    fun close(textureId: Long) {
        val preview = previews.remove(textureId) ?: return
        releaseCamera(preview)
        preview.producer.release()
    }

    fun closeAll() {
        previews.keys.toList().forEach(::close)
    }

    /**
     * The host activity is leaving the foreground: release every camera so other
     * apps can use them, keeping the textures for [onHostResumed].
     */
    fun onHostPaused() {
        foreground = false
        previews.values.forEach(::releaseCamera)
    }

    /** The host activity is back: reopen the cameras of all surviving previews. */
    fun onHostResumed() {
        foreground = true
        previews.values.toList().forEach { preview ->
            preview.retries = 0
            reopen(preview)
        }
    }

    // ------------------------------------------------------------------ internals

    private fun isActive(preview: Preview) = previews[preview.producer.id()] === preview

    private fun releaseCamera(preview: Preview) {
        val session = preview.session
        val device = preview.device
        preview.session = null
        preview.device = null
        // close() can throw when the camera service already dropped the device.
        runCatching { session?.close() }
        runCatching { device?.close() }
    }

    /**
     * Opens the preview's camera and starts streaming. Exactly one of [onReady] /
     * [onFailed] is invoked for the attempt. A camera lost after [onReady] is
     * handled by [scheduleReopen] instead.
     */
    @SuppressLint("MissingPermission")
    private fun openDevice(preview: Preview, onReady: () -> Unit, onFailed: (String) -> Unit) {
        var settled = false
        fun ready() {
            if (!settled) {
                settled = true
                preview.retries = 0
                onReady()
            }
        }
        fun failed(message: String) {
            if (!settled) {
                settled = true
                onFailed(message)
            }
        }

        fun lost(device: CameraDevice, message: String) {
            preview.opening = false
            if (preview.device === device) {
                preview.session = null
                preview.device = null
            }
            runCatching { device.close() }
            if (settled) {
                // Was streaming: another app took the camera, or the signal dropped.
                if (isActive(preview)) scheduleReopen(preview)
            } else {
                failed(message)
            }
        }

        preview.opening = true
        try {
            manager.openCamera(preview.cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    preview.opening = false
                    if (!isActive(preview) || !foreground) {
                        // Closed from Dart, or sent to the background, while opening.
                        device.close()
                        return failed("Camera ${preview.cameraId} is no longer needed")
                    }
                    preview.device = device
                    startSession(preview, ::ready) {
                        if (preview.device === device) releaseCamera(preview)
                        failed("Failed to configure the preview session")
                    }
                }

                override fun onDisconnected(device: CameraDevice) =
                    lost(device, "Camera ${preview.cameraId} disconnected")

                override fun onError(device: CameraDevice, error: Int) =
                    lost(device, "Camera ${preview.cameraId} error $error")
            }, handler)
        } catch (e: Exception) {
            preview.opening = false
            failed(e.message ?: e.javaClass.simpleName)
        }
    }

    private fun reopen(preview: Preview) {
        if (!isActive(preview) || !foreground || preview.device != null || preview.opening) return
        openDevice(preview, onReady = {}, onFailed = { scheduleReopen(preview) })
    }

    /**
     * Retries after a delay: the app that took the camera may need a moment to
     * release it. In the background nothing is scheduled — [onHostResumed] reopens.
     */
    private fun scheduleReopen(preview: Preview) {
        if (!isActive(preview) || !foreground) return
        if (preview.retries >= MAX_REOPEN_ATTEMPTS) {
            val textureId = preview.producer.id()
            close(textureId)
            emit("camera.lost", mapOf("textureId" to textureId, "cameraId" to preview.cameraId))
            return
        }
        preview.retries++
        handler.postDelayed({ reopen(preview) }, REOPEN_DELAY_MS)
    }

    @Suppress("DEPRECATION") // The Handler-based overload keeps callbacks on the main thread.
    private fun startSession(preview: Preview, onReady: () -> Unit, onFailed: () -> Unit) {
        val device = preview.device ?: return onFailed()
        try {
            val surface = preview.producer.surface
            val request = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW).apply {
                addTarget(surface)
                set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
            }
            device.createCaptureSession(
                listOf(surface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        if (preview.device !== device) {
                            runCatching { session.close() }
                            return
                        }
                        preview.session = session
                        try {
                            session.setRepeatingRequest(request.build(), null, handler)
                            onReady()
                        } catch (e: Exception) {
                            onFailed()
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) = onFailed()
                },
                handler,
            )
        } catch (e: Exception) {
            onFailed()
        }
    }

    /** Largest supported video size, as in the vendor demo; 1280x720 as a fallback. */
    private fun previewSize(cameraId: String): Size = runCatching {
        manager.getCameraCharacteristics(cameraId)
            .get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            ?.getOutputSizes(MediaRecorder::class.java)
            ?.maxByOrNull { it.width.toLong() * it.height }
    }.getOrNull() ?: Size(1280, 720)

    private companion object {
        const val MAX_REOPEN_ATTEMPTS = 5
        const val REOPEN_DELAY_MS = 1000L
    }
}
