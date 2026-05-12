package expo.modules.contactless

import android.content.Context
import android.nfc.NfcAdapter
import expo.modules.kotlin.modules.Module
import expo.modules.kotlin.modules.ModuleDefinition

class ContactlessSDKModule : Module() {
  override fun definition() = ModuleDefinition {
    Name("ContactlessSDK")

    AsyncFunction("initialize") { apiKey: String, environment: String ->
      true
    }

    AsyncFunction("isNfcAvailable") {
      val context: Context = appContext.reactContext ?: throw Exception("No React context")
      val adapter = NfcAdapter.getDefaultAdapter(context)
      adapter?.isEnabled ?: false
    }

    AsyncFunction("startPayment") { request: Map<String, Any?> ->
      mapOf(
        "success" to true,
        "transactionId" to "TXN_" + System.currentTimeMillis().toString(),
        "authCode" to "123456",
        "maskedPan" to "4111********1111"
      )
    }
  }
}
