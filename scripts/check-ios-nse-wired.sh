#!/usr/bin/env bash
# SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
#
# The iOS Notification Service Extension's own wiring, checked as text on
# an ubuntu runner rather than by a 14-minute macOS build: the target, its
# sources, its entitlements and the Dart side that talks to it all have to
# agree, and a hand-edited project.pbxproj is where they stop agreeing.
#
# Lifted verbatim out of hygiene.yml, which crossed the 500-line hard
# ceiling; the check itself is unchanged, and hygiene still runs it under
# the same step name.
# -e alone, matching the `bash -e {0}` GitHub runs a `run:` block with:
# this was lifted out of one, and -u or pipefail would change what fails.
set -e

ios=client/packages/app/ios
pbx=$ios/Runner.xcodeproj/project.pbxproj
ext=$ios/NotificationService
dart=client/packages/platform/lib/src
fail=0

value() {
  local key="$1"
  local file="$2"
  awk -v k="$key" '$0 ~ "<key>"k"</key>" {
    getline
    gsub(/^[ \t]*<string>|<\/string>[ \t]*$/, "")
    print
    exit
  }' "$file"
}
# The first string under a named key's array, which is where both
# entitlements files keep their keychain group.
keychain_group_in() {
  local file="$1"
  awk '/<key>keychain-access-groups<\/key>/ {f=1; next}
       f && /<string>/ {
         gsub(/^[ \t]*<string>|<\/string>[ \t]*$/, "")
         print
         exit
       }' "$file"
}

point=$(value NSExtensionPointIdentifier "$ext/Info.plist")
[[ "$point" = "com.apple.usernotifications.service" ]] || {
  echo "::error::$ext/Info.plist is not a notification service extension" >&2
  fail=1
}

# The Dart constant is the one a person edits; everything else has to
# agree with it, so it is the source rather than a value in this file.
group=$(sed -n "s/^const pushKeychainAccessGroup = '\(.*\)';$/\1/p" \
  "$dart/persistent_key_store.dart")
[[ -n "$group" ]] || {
  echo "::error::persistent_key_store.dart has no pushKeychainAccessGroup" >&2
  fail=1
}
if [[ -n "$group" ]]; then
  ext_group=$(keychain_group_in "$ext/NotificationService.entitlements")
  [[ "$ext_group" = "$group" ]] || {
    echo "::error::the extension claims '$ext_group', not '$group'" >&2
    fail=1
  }
  # The app's own list is ordered: its first entry is the default
  # group every other secret is already written to, and promoting the
  # push group there would move them all. So the push group must be
  # present and must not be first.
  first=$(keychain_group_in "$ios/Runner/Runner.entitlements")
  [[ "$first" != "$group" ]] || {
    echo "::error::Runner.entitlements lists '$group' first, which would" >&2
    echo "::error::make it the default group every other secret is written to" >&2
    fail=1
  }
  grep -q "<string>$group</string>" "$ios/Runner/Runner.entitlements" || {
    echo "::error::Runner.entitlements does not claim '$group'" >&2
    fail=1
  }
  grep -q "\"$group\"" "$ext/PushKeychain.swift" || {
    echo "::error::PushKeychain.swift does not use '$group'" >&2
    fail=1
  }
  # Declaring the group is not the same as writing into it: without
  # this the constant could stay correct everywhere while the store
  # quietly wrote to the app's default group instead.
  grep -q 'groupId: pushKeychainAccessGroup' \
    "$dart/persistent_key_store.dart" || {
    echo "::error::the push key store does not write into \$group" >&2
    fail=1
  }
fi

# kSecAttrAccount: what the key is filed under on both sides.
handle=$(sed -n \
  "s/^const devicePushKeyHandle = '\(.*\)';$/\1/p" "$dart/device_push_keys.dart")
[[ -n "$handle" ]] || {
  echo "::error::device_push_keys.dart has no devicePushKeyHandle" >&2
  fail=1
}
if [[ -n "$handle" ]]; then
  grep -q "\"$handle\"" "$ext/PushKeychain.swift" || {
    echo "::error::PushKeychain.swift does not read '$handle'" >&2
    fail=1
  }
fi

# kSecAttrService: flutter_secure_storage's own default, which the
# Swift side hardcodes because it has no way to ask. Setting
# accountName on the Dart side would change it and orphan the read.
grep -q '"flutter_secure_storage_service"' "$ext/PushKeychain.swift" || {
  echo "::error::PushKeychain.swift does not use the default kSecAttrService" >&2
  fail=1
}
if grep -q 'accountName' "$dart/persistent_key_store.dart"; then
  echo "::error::persistent_key_store.dart sets accountName, which changes" >&2
  echo "::error::kSecAttrService; PushKeychain.swift would then find nothing" >&2
  fail=1
fi

# kSecAttrAccessible: the two spellings of one attribute. Anything
# but after-first-unlock is unreadable on a locked screen, which is
# the only screen this extension exists for.
grep -q 'first_unlock_this_device' "$dart/persistent_key_store.dart" || {
  echo "::error::the push key store is not first_unlock_this_device;" >&2
  echo "::error::it would be unreadable exactly when a push arrives locked" >&2
  fail=1
}
grep -q 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' \
  "$ext/PushKeychain.swift" || {
  echo "::error::PushKeychain.swift queries a different accessibility" >&2
  fail=1
}

nse_id=$(sed -n \
  's/^[[:space:]]*PRODUCT_BUNDLE_IDENTIFIER = \(.*NotificationService\);$/\1/p' \
  "$pbx" | head -n1)
if [[ -n "$nse_id" ]]; then
  count=$(grep -c "PRODUCT_BUNDLE_IDENTIFIER = $nse_id;" "$pbx")
  [[ "$count" -ge 3 ]] || {
    echo "::error::$pbx does not build $nse_id in all three configs" >&2
    fail=1
  }
  grep -q "<key>$nse_id</key>" "$ios/ExportOptions.plist" || {
    echo "::error::ExportOptions.plist has no profile for $nse_id" >&2
    fail=1
  }
  grep -q "slim-m Notification Service App Store" "$ios/ExportOptions.plist" || {
    echo "::error::ExportOptions.plist does not name the extension's profile" >&2
    fail=1
  }
else
  echo "::error::$pbx builds no NotificationService bundle id" >&2
  fail=1
fi

# The appex has to be embedded or the extension ships nowhere.
copy_phases=$(awk '/Begin PBXCopyFilesBuildPhase section/{f=1}
                   f{print}
                   /End PBXCopyFilesBuildPhase section/{f=0}' "$pbx")
grep -q 'NotificationService.appex in Embed Foundation Extensions' \
  <<<"$copy_phases" || {
  echo "::error::$pbx does not embed NotificationService.appex" >&2
  fail=1
}

# Membership of *this* target, not of any target. The crypto sources
# are deliberately compiled into RunnerTests as well, so a check that
# only asked whether a file appears somewhere in a Sources phase
# would pass while the extension itself had lost it - and losing
# NotificationService.swift that way is silent, since an appex with
# no principal class still builds and only fails on a real device.
native=$(awk '/Begin PBXNativeTarget section/{f=1}
              f{print}
              /End PBXNativeTarget section/{f=0}' "$pbx")
sources_id=$(awk '/\/\* NotificationService \*\/ = \{/{f=1}
                  f && /buildPhases = \(/{p=1; next}
                  p && /\);/{exit}
                  p && /\/\* Sources \*\//{print $1; exit}' <<<"$native")
if [[ -z "$sources_id" ]]; then
  echo "::error::$pbx has no Sources phase on the NotificationService target" >&2
  fail=1
else
  own=$(awk -v id="$sources_id" '$0 ~ "^\t\t"id" " {f=1}
                                 f{print}
                                 f && /^\t\t\};$/{exit}' "$pbx")
  for f in "$ext"/*.swift; do
    grep -qF "$(basename "$f") in Sources" <<<"$own" || {
      echo "::error::$(basename "$f") is not in NotificationService's own Sources" >&2
      fail=1
    }
  done
fi

if [[ $fail -eq 0 ]]; then
  echo "ios notification service extension wired: $nse_id in $group"
fi
exit $fail
