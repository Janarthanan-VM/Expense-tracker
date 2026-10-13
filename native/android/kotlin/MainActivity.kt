package com.expensetracker.expense_tracker

import android.Manifest
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

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
                "takeEvents" -> result.success(store.takeAll())
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
                        result.success(o.toString())
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("detection_error", e.message, null)
        }
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
    }
}
