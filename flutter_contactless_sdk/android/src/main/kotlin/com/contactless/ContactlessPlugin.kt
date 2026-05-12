package com.contactless

import android.app.Activity
import android.nfc.NfcAdapter
import android.nfc.Tag
import android.nfc.tech.IsoDep
import android.os.Bundle
import android.util.Log
import androidx.annotation.NonNull
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import android.content.Context

import java.io.IOException
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** ContactlessPlugin */
class ContactlessPlugin: FlutterPlugin, MethodCallHandler, ActivityAware {
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private var nfcAdapter: NfcAdapter? = null
  private var activity: Activity? = null
  private val executor: ExecutorService = Executors.newSingleThreadExecutor()

  @Volatile private var pendingResult: Result? = null

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "com.contactless/sdk")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
    nfcAdapter = NfcAdapter.getDefaultAdapter(context)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    executor.shutdown()
  }

  override fun onAttachedToActivity(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivityForConfigChanges() {
    activity = null
  }

  override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
    activity = binding.activity
  }

  override fun onDetachedFromActivity() {
    activity = null
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
    when (call.method) {
      "initialize" -> {
        result.success(true)
      }
      "isNfcAvailable" -> {
        result.success(nfcAdapter?.isEnabled ?: false)
      }
      "startPayment" -> {
        startEmvPayment(result)
      }
      else -> {
        result.notImplemented()
      }
    }
  }

  private fun startEmvPayment(result: Result) {
    val currentActivity = activity
    val adapter = nfcAdapter

    if (currentActivity == null) {
      result.error("NO_ACTIVITY", "Plugin is not attached to an Activity", null)
      return
    }
    if (adapter == null) {
      result.error("NFC_UNAVAILABLE", "NFC adapter not available on this device", null)
      return
    }
    if (pendingResult != null) {
      result.error("NFC_BUSY", "An NFC session is already in progress", null)
      return
    }

    pendingResult = result

    val flags = NfcAdapter.FLAG_READER_NFC_A or
      NfcAdapter.FLAG_READER_NFC_B or
      NfcAdapter.FLAG_READER_NFC_F or
      NfcAdapter.FLAG_READER_NFC_V or
      NfcAdapter.FLAG_READER_NFC_BARCODE

    val extras = Bundle()

    adapter.enableReaderMode(
      currentActivity,
      { tag ->
        executor.execute {
          handleTag(adapter, currentActivity, tag)
        }
      },
      flags,
      extras
    )
  }

  private fun handleTag(adapter: NfcAdapter, activity: Activity, tag: Tag) {
    val result = pendingResult
    if (result == null) return

    try {
      val isoDep = IsoDep.get(tag)
      if (isoDep == null) {
        finishWithError(adapter, activity, "UNSUPPORTED_TAG", "Tag is not IsoDep (EMV)")
        return
      }

      isoDep.connect()
      isoDep.timeout = 10_000

      // 1) SELECT PPSE (2PAY.SYS.DDF01)
      val ppse = buildSelectApdu("2PAY.SYS.DDF01")
      val ppseResp = transceiveOrThrow(isoDep, ppse)
      ensureSuccess(ppseResp, "PPSE_SELECT_FAILED")

      val aids = extractAids(ppseResp)
      if (aids.isEmpty()) {
        finishWithError(adapter, activity, "NO_AID", "No AIDs found in PPSE response")
        return
      }

      var pan: String? = null
      // Try AIDs until we can read Track2/PAN
      for (aid in aids) {
        val selectAidResp = transceiveOrThrow(isoDep, buildSelectApdu(aid))
        if (!isSuccess(selectAidResp)) continue

        // 2) GET PROCESSING OPTIONS (empty PDOL)
        val gpoResp = transceiveOrThrow(isoDep, byteArrayOf(
          0x80.toByte(), 0xA8.toByte(), 0x00, 0x00, 0x02, 0x83.toByte(), 0x00, 0x00
        ))
        if (!isSuccess(gpoResp)) continue

        val afl = extractAfl(gpoResp)
        if (afl.isEmpty()) continue

        // 3) READ RECORD(s) from AFL and parse Track2/PAN
        for (entry in afl) {
          val sfi = entry.sfi
          for (record in entry.firstRecord..entry.lastRecord) {
            val p2 = ((sfi shl 3) or 0x04).toByte()
            val readRecord = byteArrayOf(0x00, 0xB2.toByte(), record.toByte(), p2, 0x00)
            val recResp = transceiveOrThrow(isoDep, readRecord)
            if (!isSuccess(recResp)) continue

            val tlv = parseTlvMap(stripStatus(recResp))
            val track2 = tlv[0x57]
            val panBytes = tlv[0x5A]

            val candidate = when {
              track2 != null -> extractPanFromTrack2(bcdToHex(track2))
              panBytes != null -> bcdToHex(panBytes).replace("F", "")
              else -> null
            }

            if (!candidate.isNullOrBlank()) {
              pan = candidate
              break
            }
          }
          if (!pan.isNullOrBlank()) break
        }

        if (!pan.isNullOrBlank()) break
      }

      isoDep.close()

      if (pan.isNullOrBlank()) {
        finishWithError(adapter, activity, "PAN_NOT_FOUND", "Unable to extract PAN from EMV records")
        return
      }

      val maskedPan = maskPan(pan)
      val response = mapOf(
        "success" to true,
        "transactionId" to ("TXN_" + System.currentTimeMillis()),
        "authCode" to "000000",
        "maskedPan" to maskedPan
      )

      finishWithSuccess(adapter, activity, response)
    } catch (e: Throwable) {
      Log.e("ContactlessPlugin", "NFC error", e)
      finishWithError(adapter, activity, "NFC_ERROR", e.message ?: "Unknown error")
    }
  }

  private fun finishWithSuccess(adapter: NfcAdapter, activity: Activity, payload: Map<String, Any?>) {
    val result = pendingResult
    pendingResult = null
    adapter.disableReaderMode(activity)
    activity.runOnUiThread { result?.success(payload) }
  }

  private fun finishWithError(adapter: NfcAdapter, activity: Activity, code: String, message: String) {
    val result = pendingResult
    pendingResult = null
    adapter.disableReaderMode(activity)
    activity.runOnUiThread { result?.error(code, message, null) }
  }

  private fun transceiveOrThrow(isoDep: IsoDep, apdu: ByteArray): ByteArray {
    return try {
      isoDep.transceive(apdu)
    } catch (e: IOException) {
      throw IOException("Transceive failed", e)
    }
  }

  private fun isSuccess(resp: ByteArray): Boolean {
    if (resp.size < 2) return false
    val sw1 = resp[resp.size - 2]
    val sw2 = resp[resp.size - 1]
    return sw1 == 0x90.toByte() && sw2 == 0x00.toByte()
  }

  private fun ensureSuccess(resp: ByteArray, code: String) {
    if (!isSuccess(resp)) {
      throw IllegalStateException(code + ": SW=" + bytesToHex(resp.takeLast(2).toByteArray()))
    }
  }

  private fun stripStatus(resp: ByteArray): ByteArray {
    return if (resp.size > 2) resp.copyOfRange(0, resp.size - 2) else byteArrayOf()
  }

  private fun buildSelectApdu(aidAscii: String): ByteArray {
    return buildSelectApdu(aidAscii.toByteArray(Charsets.US_ASCII))
  }

  private fun buildSelectApdu(aid: ByteArray): ByteArray {
    val header = byteArrayOf(0x00, 0xA4.toByte(), 0x04, 0x00, aid.size.toByte())
    val le = byteArrayOf(0x00)
    return header + aid + le
  }

  private fun extractAids(ppseResponseWithSw: ByteArray): List<ByteArray> {
    val data = stripStatus(ppseResponseWithSw)
    val aids = mutableListOf<ByteArray>()
    // Extremely simple scan for tag 0x4F (AID)
    var i = 0
    while (i < data.size - 2) {
      if (data[i] == 0x4F.toByte()) {
        val len = data[i + 1].toInt() and 0xFF
        val start = i + 2
        if (start + len <= data.size) {
          aids.add(data.copyOfRange(start, start + len))
        }
        i = start + len
      } else {
        i++
      }
    }
    return aids
  }

  private data class AflEntry(val sfi: Int, val firstRecord: Int, val lastRecord: Int)

  private fun extractAfl(gpoResponseWithSw: ByteArray): List<AflEntry> {
    val data = stripStatus(gpoResponseWithSw)
    val tlv = parseTlvMap(data)
    val aflBytes = tlv[0x94] ?: return emptyList()
    if (aflBytes.size % 4 != 0) return emptyList()

    val entries = mutableListOf<AflEntry>()
    var i = 0
    while (i < aflBytes.size) {
      val sfi = (aflBytes[i].toInt() and 0xFF) shr 3
      val first = aflBytes[i + 1].toInt() and 0xFF
      val last = aflBytes[i + 2].toInt() and 0xFF
      entries.add(AflEntry(sfi, first, last))
      i += 4
    }
    return entries
  }

  private fun parseTlvMap(data: ByteArray): Map<Int, ByteArray> {
    val out = mutableMapOf<Int, ByteArray>()
    var i = 0
    while (i < data.size) {
      var tag = data[i].toInt() and 0xFF
      i++
      if ((tag and 0x1F) == 0x1F && i < data.size) {
        tag = (tag shl 8) or (data[i].toInt() and 0xFF)
        i++
      }
      if (i >= data.size) break
      var len = data[i].toInt() and 0xFF
      i++
      if ((len and 0x80) == 0x80) {
        val n = len and 0x7F
        len = 0
        for (j in 0 until n) {
          if (i >= data.size) break
          len = (len shl 8) or (data[i].toInt() and 0xFF)
          i++
        }
      }
      if (i + len > data.size) break
      val value = data.copyOfRange(i, i + len)
      i += len

      // Store primitive tags we care about; ignore constructed recursion for simplicity.
      if (!out.containsKey(tag)) {
        out[tag] = value
      }
    }
    return out
  }

  private fun bcdToHex(bytes: ByteArray): String {
    return bytesToHex(bytes)
  }

  private fun bytesToHex(bytes: ByteArray): String {
    val sb = StringBuilder(bytes.size * 2)
    for (b in bytes) {
      sb.append(String.format("%02X", b))
    }
    return sb.toString()
  }

  private fun extractPanFromTrack2(track2Hex: String): String? {
    // Track2 is PAN + 'D' + expiry/service... (or sometimes 'd')
    val clean = track2Hex.replace("F", "")
    val idx = clean.indexOf('D')
    if (idx <= 0) return null
    return clean.substring(0, idx)
  }

  private fun maskPan(pan: String): String {
    val p = pan.replace("F", "")
    if (p.length <= 10) return p
    val start = p.take(6)
    val end = p.takeLast(4)
    val stars = "*".repeat(p.length - 10)
    return start + stars + end
  }
}
