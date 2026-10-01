// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#include "clipboard_image_channel.h"

#include <gtk/gtk.h>

namespace {

// Shared with the Dart stub and the mobile implementations.
const char* kChannelName = "top.npcserver.slimm/clipboard_image";

GtkClipboard* DefaultClipboard() {
  return gtk_clipboard_get_default(gdk_display_get_default());
}

// Metadata only, the same exemption UIPasteboard.hasImages and Android's
// ClipboardDescription.hasMimeType rely on: this never blocks on the
// clipboard owner and never surfaces a permission prompt.
void HandleHasImage(FlMethodCall* call) {
  gboolean has_image = gtk_clipboard_wait_is_image_available(DefaultClipboard());
  g_autoptr(FlValue) result = fl_value_new_bool(has_image);
  fl_method_call_respond_success(call, result, nullptr);
}

// Encoded as PNG so the bytes match what the composer's own staging path
// already expects from a picked file or a web paste.
void HandleReadImage(FlMethodCall* call) {
  GdkPixbuf* pixbuf = gtk_clipboard_wait_for_image(DefaultClipboard());
  if (pixbuf == nullptr) {
    fl_method_call_respond_success(call, fl_value_new_null(), nullptr);
    return;
  }

  gchar* buffer = nullptr;
  gsize buffer_size = 0;
  g_autoptr(GError) error = nullptr;
  gboolean saved = gdk_pixbuf_save_to_buffer(
      pixbuf, &buffer, &buffer_size, "png", &error, nullptr);
  g_object_unref(pixbuf);

  if (!saved) {
    fl_method_call_respond_error(
        call, "read_failed", "The clipboard image could not be read.",
        nullptr, nullptr);
    return;
  }

  g_autoptr(FlValue) result = fl_value_new_uint8_list(
      reinterpret_cast<const uint8_t*>(buffer), buffer_size);
  g_free(buffer);
  fl_method_call_respond_success(call, result, nullptr);
}

// The bytes arrive as PNG (the Dart side converts); GTK offers the pixbuf to
// other apps in whatever image formats they ask for.
void HandleWriteImage(FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  if (fl_value_get_type(args) != FL_VALUE_TYPE_UINT8_LIST) {
    fl_method_call_respond_error(call, "write_failed",
                                 "The image could not be copied.", nullptr,
                                 nullptr);
    return;
  }

  GdkPixbufLoader* loader = gdk_pixbuf_loader_new();
  g_autoptr(GError) error = nullptr;
  gboolean decoded =
      gdk_pixbuf_loader_write(loader, fl_value_get_uint8_list(args),
                              fl_value_get_length(args), &error) &&
      gdk_pixbuf_loader_close(loader, &error);
  GdkPixbuf* pixbuf = decoded ? gdk_pixbuf_loader_get_pixbuf(loader) : nullptr;
  if (pixbuf == nullptr) {
    g_object_unref(loader);
    fl_method_call_respond_error(call, "write_failed",
                                 "The image could not be copied.", nullptr,
                                 nullptr);
    return;
  }

  gtk_clipboard_set_image(DefaultClipboard(), pixbuf);
  g_object_unref(loader);
  fl_method_call_respond_success(call, nullptr, nullptr);
}

void HandleMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                      gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "hasImage") == 0) {
    HandleHasImage(method_call);
  } else if (g_strcmp0(method, "readImage") == 0) {
    HandleReadImage(method_call);
  } else if (g_strcmp0(method, "writeImage") == 0) {
    HandleWriteImage(method_call);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

}  // namespace

void clipboard_image_channel_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Deliberately never released: the channel must outlive every call it
  // answers, which in practice means the life of the application.
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, HandleMethodCall,
                                            nullptr, nullptr);
}
