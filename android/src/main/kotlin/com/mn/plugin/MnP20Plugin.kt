package com.mn.plugin

import android.Manifest
import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.content.Context
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import com.amoymn.fuelsdk.MnFuelSdk
import com.amoymn.fuelsdk.OnSdkResultListener
import com.amoymn.sdk.MnLedSdk
import com.amoymn.sdk.MnMdvrSdk
import com.amoymn.sdk.MnP20Sdk
import com.amoymn.sdk.OnCalibPhotoListener
import com.amoymn.sdk.OnCanCallback
import com.amoymn.sdk.OnDsmVideoCallback
import com.amoymn.sdk.OnResultListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.util.concurrent.atomic.AtomicBoolean

private typealias NoArgCall = (OnResultListener) -> Unit
private typealias ArgCall = (String?, OnResultListener) -> Unit

/**
 * Bridges the Magnetic North vendor SDKs (MnP20Sdk / MnMdvrSdk / MnLedSdk / MnFuelSdk)
 * to Flutter.
 *
 * - Method channel: `<facade>.<method>`; one-shot results are returned as the raw
 *   `{code,msg,data}` JSON string produced by the SDK.
 * - Event channel: every listener push is a map tagged with an `event` name.
 *   Native listeners are registered on demand through `subscribe` / `unsubscribe`.
 */
class MnP20Plugin :
    FlutterPlugin,
    ActivityAware,
    PluginRegistry.RequestPermissionsResultListener,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var cameras: MnCameraPreviews

    private var activityBinding: ActivityPluginBinding? = null
    private var pendingCameraPermission: MethodChannel.Result? = null

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    /** event name -> function that unregisters the native listener. */
    private val subscriptions = HashMap<String, () -> Unit>()

    // The vendor singletons are cleared by release(), so always fetch them fresh.
    private fun p20(): MnP20Sdk = checkNotNull(MnP20Sdk.getInstance()) { "MnP20Sdk unavailable" }
    private fun mdvr(): MnMdvrSdk = checkNotNull(MnMdvrSdk.getInstance()) { "MnMdvrSdk unavailable" }
    private fun led(): MnLedSdk = checkNotNull(MnLedSdk.getInstance()) { "MnLedSdk unavailable" }
    private fun fuel(): MnFuelSdk = checkNotNull(MnFuelSdk.getInstance()) { "MnFuelSdk unavailable" }

    // ---------------------------------------------------------------- lifecycle

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        cameras = MnCameraPreviews(context, binding.textureRegistry, ::emit)
        methodChannel = MethodChannel(binding.binaryMessenger, "$CHANNEL/methods")
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, "$CHANNEL/events")
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        eventSink = null
        cameras.closeAll()
        subscriptions.values.forEach { cancel -> runCatching { cancel() } }
        subscriptions.clear()
    }

    /**
     * Cameras are released in onPause and reopened in onResume, so another app
     * (e.g. the system camera) can use them while this one is in the background.
     */
    private val activityLifecycle = object : Application.ActivityLifecycleCallbacks {
        private fun isHost(activity: Activity) = activity === activityBinding?.activity

        override fun onActivityPaused(activity: Activity) {
            if (isHost(activity)) cameras.onHostPaused()
        }

        override fun onActivityResumed(activity: Activity) {
            if (isHost(activity)) cameras.onHostResumed()
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) {}
        override fun onActivityStarted(activity: Activity) {}
        override fun onActivityStopped(activity: Activity) {}
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) {}
        override fun onActivityDestroyed(activity: Activity) {}
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
        binding.activity.application.registerActivityLifecycleCallbacks(activityLifecycle)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) =
        onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        activityBinding?.let { binding ->
            binding.removeRequestPermissionsResultListener(this)
            binding.activity.application.unregisterActivityLifecycleCallbacks(activityLifecycle)
        }
        activityBinding = null
        pendingCameraPermission?.success(false)
        pendingCameraPermission = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != CAMERA_PERMISSION_REQUEST) return false
        pendingCameraPermission?.success(
            grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED,
        )
        pendingCameraPermission = null
        return true
    }

    private fun requestCameraPermission(result: MethodChannel.Result) {
        if (cameras.hasPermission()) return result.success(true)
        val activity: Activity = activityBinding?.activity
            ?: return result.error("MN_NO_ACTIVITY", "No activity to request the permission from", null)
        if (pendingCameraPermission != null) {
            return result.error("MN_CAMERA_PERMISSION", "A permission request is already running", null)
        }
        pendingCameraPermission = result
        activity.requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_PERMISSION_REQUEST)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // ------------------------------------------------------------------ helpers

    private fun onMain(block: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
    }

    private fun emit(event: String, payload: Map<String, Any?>) {
        onMain { eventSink?.success(payload + ("event" to event)) }
    }

    /** One-shot listener: forwards the first SDK callback to Dart, ignores the rest. */
    private fun reply(result: MethodChannel.Result) = object : OnResultListener {
        private val done = AtomicBoolean(false)
        override fun onResult(json: String?) {
            if (done.compareAndSet(false, true)) onMain { result.success(json) }
        }
    }

    private fun fuelReply(result: MethodChannel.Result) = object : OnSdkResultListener {
        private val done = AtomicBoolean(false)
        override fun onResult(json: String?) {
            if (done.compareAndSet(false, true)) onMain { result.success(json) }
        }
    }

    /** Long-lived listener: forwards every SDK callback to the event channel. */
    private fun push(event: String) = object : OnResultListener {
        override fun onResult(json: String?) = emit(event, mapOf("json" to json))
    }

    private fun listen(
        event: String,
        register: (OnResultListener) -> Unit,
        unregister: (OnResultListener) -> Unit,
    ): () -> Unit {
        val listener = push(event)
        register(listener)
        return { unregister(listener) }
    }

    private fun MethodCall.int(key: String): Int =
        argument<Number>(key)?.toInt() ?: throw IllegalArgumentException("Missing int argument '$key'")

    private fun MethodCall.string(key: String): String =
        argument<String>(key) ?: throw IllegalArgumentException("Missing string argument '$key'")

    // ------------------------------------------------------------ method tables

    private val noArgCalls: Map<String, NoArgCall> = mapOf(
        // P20
        "p20.release" to { l -> dropSubscriptions("p20."); p20().release(l) },
        "p20.getVersion" to { l -> p20().getVersion(l) },
        "p20.getP20DeviceIdentifier" to { l -> p20().getP20DeviceIdentifier(l) },
        "p20.ttsStop" to { l -> p20().ttsStop(l) },
        "p20.getStorageInfo" to { l -> p20().getStorageInfo(l) },
        "p20.testEth0" to { l -> p20().testEth0(l) },
        "p20.test4G" to { l -> p20().test4G(l) },
        "p20.queryTmsState" to { l -> p20().queryTmsState(l) },
        // MDVR
        "mdvr.release" to { l -> dropSubscriptions("mdvr."); mdvr().release(l) },
        "mdvr.getMdvrDeviceIdentifier" to { l -> mdvr().getMdvrDeviceIdentifier(l) },
        "mdvr.getMdvrVersion" to { l -> mdvr().getMdvrVersion(l) },
        "mdvr.getMdvrApcInfo" to { l -> mdvr().getMdvrApcInfo(l) },
        "mdvr.closeDriveMic" to { l -> mdvr().closeDriveMic(l) },
        "mdvr.acceptDial" to { l -> mdvr().acceptDial(l) },
        "mdvr.dialOff" to { l -> mdvr().dialOff(l) },
        "mdvr.rebootMdvr" to { l -> mdvr().rebootMdvr(l) },
        "mdvr.switchNext" to { l -> mdvr().switchNext(l) },
        "mdvr.queryRouteStatus" to { l -> mdvr().queryRouteStatus(l) },
        "mdvr.stopServiceVoice" to { l -> mdvr().stopServiceVoice(l) },
        "mdvr.getRouteCount" to { l -> mdvr().getRouteCount(l) },
        "mdvr.resetToDefaultChannel" to { l -> mdvr().resetToDefaultChannel(l) },
        "mdvr.replayVoice" to { l -> mdvr().replayVoice(l) },
        "mdvr.queryStopInfo" to { l -> mdvr().queryStopInfo(l) },
        "mdvr.deleteAllSms" to { l -> mdvr().deleteAllSms(l) },
        "mdvr.queryContacts" to { l -> mdvr().queryContacts(l) },
        "mdvr.queryHostStatus" to { l -> mdvr().queryHostStatus(l) },
        "mdvr.queryHostDetailStatus" to { l -> mdvr().queryHostDetailStatus(l) },
        "mdvr.queryHostInfo" to { l -> mdvr().queryHostInfo(l) },
        "mdvr.queryHandleStatus" to { l -> mdvr().queryHandleStatus(l) },
        "mdvr.queryAdasInfo" to { l -> mdvr().queryAdasInfo(l) },
        "mdvr.queryDsmInfo" to { l -> mdvr().queryDsmInfo(l) },
        "mdvr.setDsmCalib" to { l -> mdvr().setDsmCalib(l) },
        // LED
        "led.release" to { l -> led().release(l) },
        "led.getRouteList" to { l -> led().getRouteList(l) },
        "led.getNonOpStatusList" to { l -> led().getNonOpStatusList(l) },
    )

    private val argCalls: Map<String, ArgCall> = mapOf(
        // P20
        "p20.showSystemBar" to { a, l -> p20().showSystemBar(a, l) },
        "p20.upgradeFirmware" to { a, l -> p20().upgradeFirmware(a, l) },
        "p20.setP20Speaker" to { a, l -> p20().setP20Speaker(a, l) },
        "p20.ttsSpeak" to { a, l -> p20().ttsSpeak(a, l) },
        "p20.controlIOOut" to { a, l -> p20().controlIOOut(a, l) },
        "p20.initFtDriveMode" to { a, l -> p20().initFtDriveMode(a, l) },
        "p20.setFtRainSnowMode" to { a, l -> p20().setFtRainSnowMode(a, l) },
        "p20.setFtEcoMode" to { a, l -> p20().setFtEcoMode(a, l) },
        "p20.setFtPowerMode" to { a, l -> p20().setFtPowerMode(a, l) },
        "p20.setFtDriveMode" to { a, l -> p20().setFtDriveMode(a, l) },
        "p20.setEthDhcp" to { a, l -> p20().setEthDhcp(a, l) },
        "p20.setStaticIpConfig" to { a, l -> p20().setStaticIpConfig(a, l) },
        "p20.execRootShell" to { a, l -> p20().execRootShell(a, l) },
        "p20.setTmsState" to { a, l -> p20().setTmsState(a, l) },
        // MDVR
        "mdvr.openDriveMic" to { a, l -> mdvr().openDriveMic(a, l) },
        "mdvr.setDriveMicVolume" to { a, l -> mdvr().setDriveMicVolume(a, l) },
        "mdvr.dial" to { a, l -> mdvr().dial(a, l) },
        "mdvr.playServiceVoice" to { a, l -> mdvr().playServiceVoice(a, l) },
        "mdvr.switchStop" to { a, l -> mdvr().switchStop(a, l) },
        "mdvr.switchRoute" to { a, l -> mdvr().switchRoute(a, l) },
        "mdvr.queryRouteInfo" to { a, l -> mdvr().queryRouteInfo(a, l) },
        "mdvr.querySmsContent" to { a, l -> mdvr().querySmsContent(a, l) },
        "mdvr.deleteSmsContent" to { a, l -> mdvr().deleteSmsContent(a, l) },
        "mdvr.driverAttendance" to { a, l -> mdvr().driverAttendance(a, l) },
        "mdvr.storeHandleStatus" to { a, l -> mdvr().storeHandleStatus(a, l) },
        "mdvr.setAdasCalib" to { a, l -> mdvr().setAdasCalib(a, l) },
        "mdvr.setBsdParam" to { a, l -> mdvr().setBsdParam(a, l) },
        "mdvr.setBsdCalib" to { a, l -> mdvr().setBsdCalib(a, l) },
        "mdvr.sendSimulatedSpeed" to { a, l -> mdvr().sendSimulatedSpeed(a, l) },
        "mdvr.sendSmsText" to { a, l -> mdvr().sendSmsText(a, l) },
        "mdvr.sendTtsText" to { a, l -> mdvr().sendTtsText(a, l) },
        "mdvr.setHostOperatingStatus" to { a, l -> mdvr().setHostOperatingStatus(a, l) },
        "mdvr.startTrip" to { a, l -> mdvr().startTrip(a, l) },
        "mdvr.endTrip" to { a, l -> mdvr().endTrip(a, l) },
        // LED
        "led.switchRoute" to { a, l -> led().switchRoute(a ?: "{}", l) },
        "led.triggerStopAnnouncement" to { a, l -> led().triggerStopAnnouncement(a ?: "{}", l) },
        "led.sendLedDisplay" to { a, l -> led().sendLedDisplay(a ?: "{}", l) },
        "led.sendImageRegion" to { a, l -> led().sendImageRegion(a ?: "{}", l) },
    )

    // --------------------------------------------------------------- dispatching

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            dispatch(call, result)
        } catch (t: Throwable) {
            result.error("MN_SDK_ERROR", t.message ?: t.javaClass.simpleName, null)
        }
    }

    private fun dispatch(call: MethodCall, result: MethodChannel.Result) {
        val method = call.method

        noArgCalls[method]?.let { it(reply(result)); return }
        argCalls[method]?.let { it(call.argument<String>("arg"), reply(result)); return }

        when (method) {
            "subscribe" -> {
                val event = call.string("event")
                subscriptions.remove(event)?.let { cancel -> runCatching { cancel() } }
                val cancel = subscribe(event)
                    ?: return result.error("MN_UNKNOWN_EVENT", "Unknown event: $event", null)
                subscriptions[event] = cancel
                result.success(null)
            }
            "unsubscribe" -> {
                subscriptions.remove(call.string("event"))?.let { cancel -> runCatching { cancel() } }
                result.success(null)
            }

            // ---- P20
            "p20.init" -> p20().init(context, reply(result))
            "p20.getSdkVersion" -> result.success(p20().sdkVersion)
            "p20.rebootDevice" -> {
                // The device powers down; the vendor callback is never invoked.
                p20().rebootDevice(null)
                result.success(null)
            }
            "p20.canOpen" -> {
                p20().canOpen(call.int("port"), call.int("bitrate"), object : OnCanCallback {
                    override fun canDataReceive(port: Int, type: Int, id: Int, data: ByteArray?) =
                        emit("p20.can", mapOf("port" to port, "type" to type, "id" to id, "data" to data))
                })
                result.success(null)
            }
            "p20.canClose" -> {
                p20().canClose(call.int("port"))
                result.success(null)
            }
            "p20.canDataSend" -> {
                p20().canDataSend(
                    call.int("port"), call.int("type"), call.int("id"), call.argument<ByteArray>("data"),
                )
                result.success(null)
            }

            // ---- MDVR
            "mdvr.init" -> mdvr().init(context, call.string("path"), call.int("baudRate"), reply(result))
            "mdvr.getSdkVersion" -> result.success(mdvr().sdkVersion)
            "mdvr.switchAnalogChannels" ->
                mdvr().switchAnalogChannels(call.argument<IntArray>("channels") ?: IntArray(0), reply(result))
            "mdvr.switchIpcChannel" -> mdvr().switchIpcChannel(call.int("index"), reply(result))
            "mdvr.requestCalibPhoto" -> {
                mdvr().requestCalibPhoto(call.argument<String>("arg"), object : OnCalibPhotoListener {
                    override fun onProgress(progress: Int) =
                        emit("mdvr.calibPhoto", mapOf("status" to "progress", "progress" to progress))

                    override fun onSuccess(filePath: String?) =
                        emit("mdvr.calibPhoto", mapOf("status" to "success", "filePath" to filePath))

                    override fun onError(errorMsg: String?) =
                        emit("mdvr.calibPhoto", mapOf("status" to "error", "error" to errorMsg))
                })
                result.success(null)
            }
            "mdvr.sendFrame" -> {
                mdvr().sendFrame(call.int("type"), call.argument<ByteArray>("data"), call.int("endType"))
                result.success(null)
            }

            // ---- LED
            "led.init" -> led().init(context, call.string("path"), call.int("baudRate"), reply(result))
            "led.getSdkVersion" -> result.success(led().getSdkVersion())

            // ---- Fuel
            "fuel.init" -> fuel().init(context, call.string("path"), call.int("baudRate"), fuelReply(result))
            "fuel.release" -> {
                dropSubscriptions("fuel.")
                fuel().release(fuelReply(result))
            }
            "fuel.getSdkVersion" -> result.success(fuel().sdkVersion)
            "fuel.requestUpdate" -> fuel().requestUpdate(fuelReply(result))
            "fuel.sendCustomCommand" -> fuel().sendCustomCommand(call.string("arg"), fuelReply(result))

            // ---- Camera preview
            "camera.requestPermission" -> requestCameraPermission(result)
            "camera.list" -> result.success(cameras.cameraIds())
            "camera.open" -> cameras.open(call.int("index"), result)
            "camera.close" -> {
                cameras.close(call.argument<Number>("textureId")?.toLong() ?: -1L)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------- subscriptions

    /** release() already removes every listener inside the vendor SDK. */
    private fun dropSubscriptions(prefix: String) {
        subscriptions.keys.removeAll { it.startsWith(prefix) }
    }

    /** Registers the native listener for [event]; returns its unregister function. */
    private fun subscribe(event: String): (() -> Unit)? = when (event) {
        // P20
        "p20.location" -> listen(event,
            { p20().registerP20LocationListener(it) }, { p20().unregisterP20LocationListener(it) })
        "p20.io" -> listen(event, { p20().registerIOListener(it) }, { p20().unregisterIOListener(it) })
        "p20.nfc" -> listen(event, { p20().registerNFCListener(it) }, { p20().unregisterNFCListener(it) })
        "p20.gsensor" -> listen(event,
            { p20().registerGsensorListener(it) }, { p20().unregisterGsensorListener(it) })
        "p20.wifi" -> listen(event,
            { p20().setWifiStatusInfoListener(it) }, { p20().stopWifiStatusListener(it) })
        "p20.dsm" -> subscribeDsm(event)
        // MDVR
        "mdvr.gps" -> listen(event, { mdvr().registerGpsListener(it) }, { mdvr().unregisterGpsListener(it) })
        "mdvr.can" -> listen(event,
            { mdvr().setOnCanDataReceivedListener(it) }, { mdvr().stopCanDataListener(it) })
        "mdvr.apc" -> listen(event, { mdvr().registerApcListener(it) }, { mdvr().unregisterApcListener(it) })
        "mdvr.dial" -> listen(event, { mdvr().registerDialListener(it) }, { mdvr().unregisterDialListener(it) })
        "mdvr.routeStatus" -> listen(event,
            { mdvr().registerRouteStatusListener(it) }, { mdvr().unregisterRouteStatusListener(it) })
        "mdvr.hostDetailStatus" -> listen(event,
            { mdvr().registerHostDetailStatusListener(it) }, { mdvr().unregisterHostDetailStatusListener(it) })
        "mdvr.ups" -> listen(event,
            { mdvr().registerUpsReceivedListener(it) }, { mdvr().unregisterUpsReceivedListener(it) })
        "mdvr.displayMsg" -> listen(event,
            { mdvr().registerDisplayMsgListener(it) }, { mdvr().unregisterDisplayMsgListener(it) })
        "mdvr.alarm" -> listen(event,
            { mdvr().registerAlarmListener(it) }, { mdvr().unregisterAlarmListener(it) })
        // Fuel
        "fuel.level" -> subscribeFuel(event)
        else -> null
    }

    private fun subscribeDsm(event: String): () -> Unit {
        val callback = object : OnDsmVideoCallback {
            override fun onReceived(infoJson: String?, videoBytes: ByteArray?) =
                emit(event, mapOf("info" to infoJson, "video" to videoBytes))
        }
        p20().registerDsmListener(callback)
        return { p20().unregisterDsmListener(callback) }
    }

    private fun subscribeFuel(event: String): () -> Unit {
        val listener = object : OnSdkResultListener {
            override fun onResult(json: String?) = emit(event, mapOf("json" to json))
        }
        fuel().setOnFuelChangeListener(listener)
        return { fuel().unregisterFuelListener(listener) }
    }

    private companion object {
        const val CHANNEL = "com.mn.plugin"
        const val CAMERA_PERMISSION_REQUEST = 0x4D4E
    }
}
