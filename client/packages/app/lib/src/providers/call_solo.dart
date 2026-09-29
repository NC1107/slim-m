// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
/// The one definition of "you are the only one in this call", shared by the
/// stage's calm waiting hint and the local hold music so they cannot disagree.
library;

import 'package:slimm_rtc/rtc.dart';

bool isAloneInCall(List<VoiceParticipant> participants) =>
    participants.length == 1;
