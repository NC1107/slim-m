// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#include "linux_tray_probe_channel.h"

#include <gio/gio.h>

namespace {

const char* kChannelName = "top.npcserver.slimm/linux_tray_probe";
const char* kWatcherBusName = "org.kde.StatusNotifierWatcher";
const char* kWatcherObjectPath = "/StatusNotifierWatcher";
const char* kWatcherInterface = "org.kde.StatusNotifierWatcher";
const char* kHostRegisteredProperty = "IsStatusNotifierHostRegistered";

// A blocking call, deliberately: this only ever runs once, on a close
// click, and a local session-bus property read is a few milliseconds at
// most - simpler and safer than tracking a GDBusConnection's lifetime
// across an async callback for a call this infrequent.
void HandleIsHostRegistered(FlMethodCall* call) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);

  gboolean registered = FALSE;
  if (bus != nullptr) {
    g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
        bus, kWatcherBusName, kWatcherObjectPath,
        "org.freedesktop.DBus.Properties", "Get",
        g_variant_new("(ss)", kWatcherInterface, kHostRegisteredProperty),
        G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 2000, nullptr,
        nullptr);
    if (reply != nullptr) {
      g_autoptr(GVariant) boxed = nullptr;
      g_variant_get(reply, "(v)", &boxed);
      if (boxed != nullptr && g_variant_is_of_type(boxed, G_VARIANT_TYPE_BOOLEAN)) {
        registered = g_variant_get_boolean(boxed);
      }
    }
  }

  g_autoptr(FlValue) result = fl_value_new_bool(registered);
  fl_method_call_respond_success(call, result, nullptr);
}

void HandleMethodCall(FlMethodChannel* channel, FlMethodCall* method_call,
                      gpointer user_data) {
  const gchar* method = fl_method_call_get_name(method_call);
  if (g_strcmp0(method, "isHostRegistered") == 0) {
    HandleIsHostRegistered(method_call);
  } else {
    fl_method_call_respond_not_implemented(method_call, nullptr);
  }
}

}  // namespace

void linux_tray_probe_channel_register(FlBinaryMessenger* messenger) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  // Deliberately never released: the channel must outlive every call it
  // answers, which in practice means the life of the application.
  FlMethodChannel* channel =
      fl_method_channel_new(messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, HandleMethodCall,
                                            nullptr, nullptr);
}
