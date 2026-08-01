// SPDX-License-Identifier: Apache-2.0
package top.npcserver.slimm

import android.content.ClipboardManager
import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The app half of the composer's mobile paste bridge; the Dart half is
 * `composer_clipboard_image_stub.dart`, which owns the channel name.
 *
 * Android's `ClipboardManager` needs no consent prompt to read an image, unlike
 * iOS's pasteboard, so both methods below run unconditionally. What can still
 * fail is the read itself: a clipboard item copied from another app is usually
 * a `content://` URI, and opening it throws `SecurityException` when that app
 * never set `FLAG_GRANT_READ_URI_PERMISSION`. That is the source app's doing,
 * not something a retry fixes, so it is reported back as a real error rather
 * than swallowed as "no image".
 */
class ClipboardImageChannel(private val context: Context) : MethodChannel.MethodCallHandler {
  companion object {
    const val NAME = "top.npcserver.slimm/clipboard_image"
  }

  fun attach(messenger: BinaryMessenger) {
    MethodChannel(messenger, NAME).setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "hasImage" -> result.success(hasImage())
      "readImage" -> readImage(result)
      else -> result.notImplemented()
    }
  }

  private fun clipboardManager() =
    context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager

  private fun hasImage(): Boolean =
    clipboardManager().primaryClipDescription?.hasMimeType("image/*") == true

  private fun readImage(result: MethodChannel.Result) {
    val clip = clipboardManager().primaryClip
    val uri = if (clip != null && clip.itemCount > 0) clip.getItemAt(0).uri else null
    if (uri == null) {
      result.success(null)
      return
    }
    try {
      val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
      result.success(bytes)
    } catch (e: SecurityException) {
      result.error(
        "read_failed",
        "The app that copied this image did not allow it to be read.",
        null,
      )
    } catch (e: Exception) {
      result.error("read_failed", "The clipboard image could not be read.", null)
    }
  }
}
