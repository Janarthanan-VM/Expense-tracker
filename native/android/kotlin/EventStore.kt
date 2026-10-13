package com.expensetracker.expense_tracker

import android.content.Context
import android.content.SharedPreferences
import org.json.JSONArray
import org.json.JSONObject

/**
 * Small on-device queue between the notification listener (which runs even
 * when the app is closed) and the Flutter app (which owns the encrypted
 * database). Holds only parsed payment fields, never raw notification text.
 *
 * Each queued item is an upsert keyed by "id": the app inserts it as a new
 * transaction, or fills in / categorises the existing one with that id.
 */
class EventStore(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // ------------------------------------------------------------ settings

    fun isEnabled(): Boolean = prefs.getBoolean(KEY_ENABLED, true)
    fun setEnabled(value: Boolean) = prefs.edit().putBoolean(KEY_ENABLED, value).apply()

    fun isPromoDismissed(): Boolean = prefs.getBoolean(KEY_PROMO_DISMISSED, false)
    fun setPromoDismissed(value: Boolean) = prefs.edit().putBoolean(KEY_PROMO_DISMISSED, value).apply()

    fun setOpenRequest(eventId: String?) = prefs.edit().putString(KEY_OPEN, eventId).apply()

    @Synchronized
    fun consumeOpenRequest(): String? {
        val id = prefs.getString(KEY_OPEN, null)
        prefs.edit().remove(KEY_OPEN).apply()
        return id
    }

    // ------------------------------------------------------------ queue

    @Synchronized
    fun upsert(event: JSONObject) {
        val queue = readArray(KEY_QUEUE)
        val id = event.getString("id")
        for (i in 0 until queue.length()) {
            val existing = queue.getJSONObject(i)
            if (existing.optString("id") == id) {
                val keys = event.keys()
                while (keys.hasNext()) {
                    val k = keys.next()
                    val v = event.get(k)
                    // A user's category choice always wins; other fields only fill gaps.
                    if (k == "categoryId" || !existing.has(k) || existing.isNull(k)) {
                        existing.put(k, v)
                    }
                }
                prefs.edit().putString(KEY_QUEUE, queue.toString()).commit()
                return
            }
        }
        queue.put(event)
        prefs.edit().putString(KEY_QUEUE, queue.toString()).commit()
    }

    @Synchronized
    fun takeAll(): String {
        val raw = prefs.getString(KEY_QUEUE, "[]") ?: "[]"
        prefs.edit().putString(KEY_QUEUE, "[]").commit()
        return raw
    }

    // ------------------------------------------------------------ duplicates

    /**
     * Returns true the first time this exact text is seen from this app in the
     * last day (apps often re-post the same notification).
     */
    @Synchronized
    fun markSeen(pkg: String, text: String, now: Long): Boolean {
        val key = "$pkg|${text.hashCode()}"
        val seen = readObject(KEY_SEEN)
        val cutoff = now - DAY_MS
        val names = seen.keys().asSequence().toList()
        for (k in names) if (seen.optLong(k) < cutoff) seen.remove(k)
        if (seen.has(key)) return false
        seen.put(key, now)
        prefs.edit().putString(KEY_SEEN, seen.toString()).apply()
        return true
    }

    /**
     * The same payment usually shows up twice: in the UPI app and as a bank
     * SMS. If a payment with the same amount and direction was seen in the
     * last few minutes, returns its id so the two are merged.
     */
    @Synchronized
    fun matchRecent(amountPaise: Long, isDebit: Boolean, upiRef: String?, now: Long): String? {
        val recent = pruneRecent(now)
        for (i in 0 until recent.length()) {
            val r = recent.getJSONObject(i)
            val sameRef = upiRef != null && r.optString("upiRef") == upiRef
            val sameAmount = r.optLong("amountPaise") == amountPaise &&
                r.optBoolean("isDebit") == isDebit &&
                Math.abs(now - r.optLong("at")) <= MERGE_WINDOW_MS
            if (sameRef || sameAmount) return r.getString("id")
        }
        return null
    }

    @Synchronized
    fun addRecent(id: String, amountPaise: Long, isDebit: Boolean, upiRef: String?, now: Long) {
        val recent = pruneRecent(now)
        recent.put(
            JSONObject()
                .put("id", id)
                .put("amountPaise", amountPaise)
                .put("isDebit", isDebit)
                .put("upiRef", upiRef ?: JSONObject.NULL)
                .put("at", now),
        )
        prefs.edit().putString(KEY_RECENT, recent.toString()).apply()
    }

    private fun pruneRecent(now: Long): JSONArray {
        val recent = readArray(KEY_RECENT)
        val kept = JSONArray()
        for (i in 0 until recent.length()) {
            val r = recent.getJSONObject(i)
            if (now - r.optLong("at") <= RECENT_KEEP_MS) kept.put(r)
        }
        return kept
    }

    // ------------------------------------------------------------ category hints

    /** Written by the app: the two most used categories for paid / received. */
    fun setHints(json: String) = prefs.edit().putString(KEY_HINTS, json).apply()

    /** List of (id, name) pairs to show as notification buttons. */
    fun hints(isDebit: Boolean): List<Pair<String, String>> {
        val fallback = if (isDebit) {
            listOf("food" to "Food & dining", "groceries" to "Groceries")
        } else {
            listOf("received" to "Received from people", "refund" to "Refund")
        }
        val raw = prefs.getString(KEY_HINTS, null) ?: return fallback
        return try {
            val arr = JSONObject(raw).optJSONArray(if (isDebit) "debit" else "credit")
                ?: return fallback
            val list = (0 until arr.length()).map {
                val o = arr.getJSONObject(it)
                o.getString("id") to o.getString("name")
            }
            if (list.isEmpty()) fallback else list.take(2)
        } catch (e: Exception) {
            fallback
        }
    }

    // ------------------------------------------------------------ helpers

    private fun readArray(key: String): JSONArray = try {
        JSONArray(prefs.getString(key, "[]") ?: "[]")
    } catch (e: Exception) {
        JSONArray()
    }

    private fun readObject(key: String): JSONObject = try {
        JSONObject(prefs.getString(key, "{}") ?: "{}")
    } catch (e: Exception) {
        JSONObject()
    }

    companion object {
        private const val PREFS = "upi_detection"
        private const val KEY_ENABLED = "enabled"
        private const val KEY_PROMO_DISMISSED = "promo_dismissed"
        private const val KEY_OPEN = "open_request"
        private const val KEY_QUEUE = "queue"
        private const val KEY_SEEN = "seen"
        private const val KEY_RECENT = "recent"
        private const val KEY_HINTS = "hints"
        private const val DAY_MS = 24L * 60 * 60 * 1000
        private const val MERGE_WINDOW_MS = 5L * 60 * 1000
        private const val RECENT_KEEP_MS = 30L * 60 * 1000
    }
}
