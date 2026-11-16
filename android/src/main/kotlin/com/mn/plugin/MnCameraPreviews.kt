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
 */
internal class MnCameraPreviews(
    private val context: Context,
    private val textures: TextureRegistry,
) {
    private class Preview(val producer: TextureRegistry.SurfaceProducer) {
        var device: CameraDevice? = null
        var session: CameraCaptureSession? = null
    }

    private val manager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

    // Camera callbacks only carry state changes (frames go straight to the
    // surface), so everything runs on the main thread and needs no locking.
    private val handler = Handler(Looper.getMainLooper())
    private val previews = HashMap<Long, Preview>()

    fun hasPermission(): Boolean =
        context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED

    fun cameraIds(): List<String> = manager.cameraIdList.toList()

    /** Opens the camera at [index] and replies with `{textureId, width, height}`. */
    @SuppressLint("MissingPermission")
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
        val preview = Preview(producer)
        previews[textureId] = preview

        val replied = AtomicBoolean(false)
        fun succeed() {
            if (replied.compareAndSet(false, true)) {
                result.success(
                    mapOf("textureId" to textureId, "width" to size.width, "height" to size.height),
                )
            }
        }
        fun fail(message: String) {
            close(textureId)
            if (replied.compareAndSet(false, true)) result.error("MN_CAMERA_ERROR", message, null)
        }

        producer.setCallback(object : TextureRegistry.SurfaceProducer.Callback {
            // The surface is torn down in the background and recreated on resume.
            override fun onSurfaceAvailable() {
                if (preview.device != null && preview.session == null) {
                    startSession(preview, {}, {})
                }
            }

            override fun onSurfaceCleanup() {
                preview.session?.close()
                preview.session = null
            }
        })

        try {
            manager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) {
                    if (previews[textureId] !== preview) {
                        // Closed from Dart while the camera was still opening.
                        device.close()
                        return
                    }
                    preview.device = device
                    startSession(preview, ::succeed) { fail("Failed to configure the preview session") }
                }

                override fun onDisconnected(device: CameraDevice) {
                    device.close()
                    preview.device = null
                    fail("Camera $cameraId disconnected")
                }

                override fun onError(device: CameraDevice, error: Int) {
                    device.close()
                    preview.device = null
                    fail("Camera $cameraId error $error")
                }
            }, handler)
        } catch (e: Exception) {
            fail(e.message ?: e.javaClass.simpleName)
        }
    }

    fun close(textureId: Long) {
        val preview = previews.remove(textureId) ?: return
        runCatching { preview.session?.close() }
        runCatching { preview.device?.close() }
        preview.session = null
        preview.device = null
        preview.producer.release()
    }

    fun closeAll() {
        previews.keys.toList().forEach(::close)
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
                            session.close()
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
}
