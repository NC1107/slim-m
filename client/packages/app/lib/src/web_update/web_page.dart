// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The two things the web-update pill needs from the browser, behind one
/// conditional export so nothing else in the app imports `package:web`.
library;

export 'web_page_stub.dart' if (dart.library.js_interop) 'web_page_web.dart';
