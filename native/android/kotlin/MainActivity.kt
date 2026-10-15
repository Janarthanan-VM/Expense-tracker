package com.expensetracker.expense_tracker

import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** Answer for "requestSmsPermission", sent when the user responds. */
    private var pendingSmsResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> handle(call, result) }
        channel = ch
        PaymentEvents.listener = { channel?.invokeMethod("eventsAvailable", null) }
        captureOpenRequest(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureOpenRequest(intent)
        channel?.invokeMethod("eventsAvailable", null)
    }

    override fun onDestroy() {
        PaymentEvents.listener = null
        channel = null
        super.onDestroy()
    }

    private fun captureOpenRequest(intent: Intent?) {
        if (intent?.action != PaymentNotifier.ACTION_OPEN_EVENT) return
        val id = intent.getStringExtra(PaymentNotifier.EXTRA_EVENT_ID) ?: return
        EventStore(this).setOpenRequest(id)
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.cancel(PaymentNotifier.notificationId(id))
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val store = EventStore(this)
        try {
            when (call.method) {
                "getStatus" -> result.success(
                    mapOf(
                        "accessEnabled" to isListenerEnabled(),
                        "enabled" to store.isEnabled(),
                        "canNotify" to canPostNotifications(),
                        "promoDismissed" to store.isPromoDismissed(),
                        "smsPermission" to hasSmsPermission(),
                        "checkLog" to store.checkLog(),
                        "sdk" to Build.VERSION.SDK_INT,
                    ),
                )
                "openAccessSettings" -> {
                    openAccessSettings()
                    result.success(null)
                }
                "openAppInfo" -> {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")),
                    )
                    result.success(null)
                }
                "requestNotificationPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                    ) {
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                    } else if (!canPostNotifications()) {
                        openNotificationSettings()
                    }
                    result.success(null)
                }
                "setEnabled" -> {
                    store.setEnabled(call.arguments as? Boolean ?: true)
                    result.success(null)
                }
                "setPromoDismissed" -> {
                    store.setPromoDismissed(call.arguments as? Boolean ?: true)
                    result.success(null)
                }
                "requestSmsPermission" -> requestSmsPermission(result)
                "importSmsHistory" -> importSmsHistory(call, result)
                "takeEvents" -> result.success(store.takeAll())
                "requeueEvents" -> {
                    val arr = org.json.JSONArray(call.arguments as? String ?: "[]")
                    for (i in 0 until arr.length()) store.upsert(arr.getJSONObject(i))
                    result.success(null)
                }
                "reportSaveError" -> {
                    store.recordCheck(
                        channel = "app",
                        source = "Dripless",
                        outcome = "save_failed",
                        time = System.currentTimeMillis(),
                        message = (call.arguments as? String)?.take(300),
                    )
                    result.success(null)
                }
                "consumeOpenRequest" -> result.success(store.consumeOpenRequest())
                "setCategoryHints" -> {
                    store.setHints(call.arguments as? String ?: "{}")
                    result.success(null)
                }
                "testParse" -> {
                    val text = call.arguments as? String ?: ""
                    val p = UpiParser.parse(text, strict = false)
                    if (p == null) {
                        result.success(null)
                    } else {
                        val o = JSONObject()
                            .put("amountPaise", p.amountPaise)
                            .put("isDebit", p.isDebit)
                            .put("mode", p.mode)
                        p.payeeName?.let { o.put("payeeName", it) }
                        p.payeeVpa?.let { o.put("payeeVpa", it) }
                        p.upiRef?.let { o.put("upiRef", it) }
                        p.account?.let { o.put("account", it) }
                        result.success(o.toString())
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("detection_error", e.message, null)
        }
    }

    // ------------------------------------------------------------ SMS

    private fun hasSmsPermission(): Boolean =
        SMS_PERMISSIONS.all { checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    /**
     * Replies "granted", "denied" (can ask again) or "blocked" (Android will
     * not show the dialog: the user must allow it in App info, and on
     * Android 15+ first allow restricted settings for apps installed from an APK).
     */
    private fun requestSmsPermission(result: MethodChannel.Result) {
        if (hasSmsPermission()) {
            result.success("granted")
            return
        }
        if (pendingSmsResult != null) {
            result.error("busy", "Already asking for SMS permission", null)
            return
        }
        pendingSmsResult = result
        requestPermissions(SMS_PERMISSIONS, REQUEST_SMS)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_SMS) return
        val result = pendingSmsResult ?: return
        pendingSmsResult = null
        val answer = when {
            hasSmsPermission() -> "granted"
            SMS_PERMISSIONS.any { shouldShowRequestPermissionRationale(it) } -> "denied"
            else -> "blocked"
        }
        result.success(answer)
    }

    /** Reads the inbox off the main thread; replies with a JSON array of payments. */
    private fun importSmsHistory(call: MethodCall, result: MethodChannel.Result) {
        if (!hasSmsPermission()) {
            result.error("no_permission", "SMS permission is not granted", null)
            return
        }
        val days = (call.arguments as? Number)?.toInt()?.coerceIn(1, 365) ?: 30
        val since = System.currentTimeMillis() - days * DAY_MS
        val main = Handler(Looper.getMainLooper())
        Thread {
            try {
                val json = SmsInbox.readPayments(applicationContext, since)
                main.post { result.success(json) }
            } catch (e: Exception) {
                main.post { result.error("import_failed", e.message, null) }
            }
        }.start()
    }

    private fun listenerComponent() = ComponentName(this, PaymentNotificationListener::class.java)

    private fun isListenerEnabled(): Boolean {
        val flat = Settings.Secure.getString(contentResolver, "enabled_notification_listeners") ?: return false
        val me = listenerComponent()
        return flat.split(":").any { ComponentName.unflattenFromString(it) == me }
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return if (Build.VERSION.SDK_INT >= 24) nm.areNotificationsEnabled() else true
    }

    private fun openAccessSettings() {
        if (Build.VERSION.SDK_INT >= 30) {
            try {
                startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
                        Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
                        listenerComponent().flattenToString(),
                    ),
                )
                return
            } catch (e: Exception) {
                // Some phones do not have the detail screen; fall back to the list.
            }
        }
        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
    }

    private fun openNotificationSettings() {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    companion object {
        private const val CHANNEL = "expense_tracker/upi_detection"
        private const val REQUEST_SMS = 1002
        private const val DAY_MS = 24L * 60 * 60 * 1000
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
        )
    }
}
