// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The build identity `appInfoProvider` reads. Call from `setUpAll` in any
/// test that renders a widget on that path - `PackageInfo` otherwise throws
/// on a test binding with no host platform.
library;

import 'package:package_info_plus/package_info_plus.dart';

void mockAppVersion() {
  PackageInfo.setMockInitialValues(
    appName: 'slim-m',
    packageName: 'top.npcserver.slimm',
    version: '0.1.0',
    buildNumber: '1',
    buildSignature: '',
  );
}
