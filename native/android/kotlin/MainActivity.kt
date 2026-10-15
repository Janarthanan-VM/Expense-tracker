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
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.codescanner.GmsBarcodeScannerOptions
import com.google.mlkit.vision.codescanner.GmsBarcodeScanning
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /** Answer for "requestSmsPermission", sent when the user responds. */
    private var pendingSmsResult: MethodChannel.Result? = null

    /** Waiting for the file picker or a UPI app to come back. */
    private var pendingActivity: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        ch.setMethodCallHandler { call, result -> handle(call, result) }
        channel = ch
        PaymentEvents.listener = { channel?.invokeMethod("eventsAvailable", null) }
        captureOpenRequest(intent)
    }

    override fun onResume() {
        super.onResume()
        // If Android unbound the notification reader in the background,
        // opening the app asks for it to be connected again.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isListenerEnabled()) {
            try {
                android.service.notification.NotificationListenerService.requestRebind(listenerComponent())
            } catch (e: Exception) {
                // Nothing to do: the user can toggle access in settings.
            }
        }
    }

    /** True when payment alerts can pop up (channel not lowered by the user). */
    private fun alertsPopUp(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        val nm = getSystemService(NotificationManager::class.java) ?: return true
        val channel = nm.getNotificationChannel("payment_alerts") ?: return true
        return channel.importance >= NotificationManager.IMPORTANCE_HIGH
    }

    private fun openAlertSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                .putExtra(Settings.EXTRA_CHANNEL_ID, "payment_alerts")
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        try {
            startActivity(intent)
        } catch (e: Exception) {
            openNotificationSettings()
        }
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
                        "keepSkippedText" to store.keepSkippedText(),
                        "alertsPopUp" to alertsPopUp(),
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
                "saveDocument" -> saveDocument(call, result)
                "setKeepSkippedText" -> {
                    store.setKeepSkippedText(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "openAlertSettings" -> {
                    openAlertSettings()
                    result.success(null)
                }
                "openDocument" -> openDocument(result)
                "scanQr" -> scanQr(result)
                "payUpi" -> payUpi(call, result)
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

    // ------------------------------------------------------------ files, QR, UPI

    private fun startForResult(intent: Intent, code: Int, result: MethodChannel.Result) {
        if (pendingActivity != null) {
            result.error("busy", "Another screen is already open", null)
            return
        }
        pendingActivity = result
        try {
            startActivityForResult(intent, code)
        } catch (e: Exception) {
            pendingActivity = null
            pendingSaveBytes = null
            result.error("no_app", e.message, null)
        }
    }

    /** Lets the user pick where to save (phone, Google Drive, ...). Replies true when written. */
    private fun saveDocument(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name") ?: "dripless"
        val mime = call.argument<String>("mime") ?: "application/octet-stream"
        val bytes = call.argument<ByteArray>("bytes")
        if (bytes == null) {
            result.error("no_data", "Nothing to save", null)
            return
        }
        pendingSaveBytes = bytes
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mime)
            .putExtra(Intent.EXTRA_TITLE, name)
        startForResult(intent, REQUEST_SAVE, result)
    }

    /** Lets the user pick a file; replies with its bytes, or null if cancelled. */
    private fun openDocument(result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType("*/*")
        startForResult(intent, REQUEST_OPEN, result)
    }

    /** Google's QR scanner: no camera permission needed. Replies with the text, or null. */
    private fun scanQr(result: MethodChannel.Result) {
        val options = GmsBarcodeScannerOptions.Builder()
            .setBarcodeFormats(Barcode.FORMAT_QR_CODE)
            .enableAutoZoom()
            .build()
        var answered = false
        fun reply(block: () -> Unit) {
            if (!answered) {
                answered = true
                block()
            }
        }
        GmsBarcodeScanning.getClient(this, options).startScan()
            .addOnSuccessListener { code -> reply { result.success(code.rawValue) } }
            .addOnCanceledListener { reply { result.success(null) } }
            .addOnFailureListener { e -> reply { result.error("scan_failed", e.message, null) } }
    }

    /**
     * Opens the user's UPI app with a upi://pay link. Replies with
     * {"resultCode": Int, "response": String?}; the response is the UPI app's
     * "txnId=...&Status=SUCCESS&..." text when it sends one.
     */
    private fun payUpi(call: MethodCall, result: MethodChannel.Result) {
        val uri = call.arguments as? String
        if (uri == null || !uri.startsWith("upi://")) {
            result.error("bad_link", "Not a UPI payment link", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        if (packageManager.queryIntentActivities(intent, 0).isEmpty()) {
            result.error("no_upi_app", "No UPI app is installed", null)
            return
        }
        startForResult(Intent.createChooser(intent, "Pay with"), REQUEST_PAY, result)
    }

    @Deprecated("Uses the platform API that FlutterActivity forwards")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_SAVE && requestCode != REQUEST_OPEN && requestCode != REQUEST_PAY) return
        val result = pendingActivity ?: return
        pendingActivity = null
        val main = Handler(Looper.getMainLooper())
        when (requestCode) {
            REQUEST_SAVE -> {
                val bytes = pendingSaveBytes
                pendingSaveBytes = null
                val uri = data?.data
                if (resultCode != RESULT_OK || uri == null || bytes == null) {
                    result.success(false)
                    return
                }
                Thread {
                    try {
                        contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                            ?: throw IllegalStateException("Could not open the file")
                        main.post { result.success(true) }
                    } catch (e: Exception) {
                        main.post { result.error("write_failed", e.message, null) }
                    }
                }.start()
            }
            REQUEST_OPEN -> {
                val uri = data?.data
                if (resultCode != RESULT_OK || uri == null) {
                    result.success(null)
                    return
                }
                Thread {
                    try {
                        val bytes = contentResolver.openInputStream(uri)?.use { input ->
                            val out = java.io.ByteArrayOutputStream()
                            val buf = ByteArray(64 * 1024)
                            var total = 0
                            while (true) {
                                val n = input.read(buf)
                                if (n < 0) break
                                total += n
                                if (total > MAX_FILE_BYTES) throw IllegalStateException("The file is too large")
                                out.write(buf, 0, n)
                            }
                            out.toByteArray()
                        } ?: throw IllegalStateException("Could not open the file")
                        main.post { result.success(bytes) }
                    } catch (e: Exception) {
                        main.post { result.error("read_failed", e.message, null) }
                    }
                }.start()
            }
            REQUEST_PAY -> {
                val response = data?.getStringExtra("response")
                    ?: data?.getStringExtra("Status")?.let { "Status=$it" }
                result.success(mapOf("resultCode" to resultCode, "response" to response))
            }
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
        private const val REQUEST_SAVE = 1101
        private const val REQUEST_OPEN = 1102
        private const val REQUEST_PAY = 1103
        private const val MAX_FILE_BYTES = 50 * 1024 * 1024
        private const val DAY_MS = 24L * 60 * 60 * 1000
        private val SMS_PERMISSIONS = arrayOf(
            Manifest.permission.RECEIVE_SMS,
            Manifest.permission.READ_SMS,
        )
    }
}
