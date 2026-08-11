# Changelog

## [0.37.0](https://github.com/NC1107/slim-m/compare/server-v0.36.0...server-v0.37.0) (2026-08-11)


### Features

* **client:** decrypt the sealed push preview on a locked iPhone ([#574](https://github.com/NC1107/slim-m/issues/574)) ([9a7ef9e](https://github.com/NC1107/slim-m/commit/9a7ef9e373e9f7854b62276f3a948f1013535229))

## [0.36.0](https://github.com/NC1107/slim-m/compare/server-v0.35.1...server-v0.36.0) (2026-08-11)


### Features

* **server:** seal an optional message preview inside the push envelope ([#569](https://github.com/NC1107/slim-m/issues/569)) ([1084f00](https://github.com/NC1107/slim-m/commit/1084f00cb55e638703ec31eef873c99a2b7ae5f5))

## [0.35.1](https://github.com/NC1107/slim-m/compare/server-v0.35.0...server-v0.35.1) (2026-08-11)


### Bug Fixes

* **ci:** close comment-defeatable blind spots in source-reading gates ([#553](https://github.com/NC1107/slim-m/issues/553)) ([1b13496](https://github.com/NC1107/slim-m/commit/1b1349601f63a6b6694c2de1539e5171337eae50))
* **client:** close the second-tier findings from the screen-review pass ([#542](https://github.com/NC1107/slim-m/issues/542)) ([2275fe9](https://github.com/NC1107/slim-m/commit/2275fe9d522d947f970e708ebb7cc28dce0e734d))
* **client:** close the sharp findings from the screen-review pass ([#535](https://github.com/NC1107/slim-m/issues/535)) ([f5b1d13](https://github.com/NC1107/slim-m/commit/f5b1d13fa06c02b89daabc726f83146cdf676a0f))

## [0.35.0](https://github.com/NC1107/slim-m/compare/server-v0.34.0...server-v0.35.0) (2026-08-10)


### Features

* **server:** add GET /channels/{channel_id}/permissions ([#518](https://github.com/NC1107/slim-m/issues/518)) ([e84431c](https://github.com/NC1107/slim-m/commit/e84431c8af823913b285aa48b46ca8aabf0d554d))
* **server:** carry the caller's permissions onto listChannels and listOpenReports ([#520](https://github.com/NC1107/slim-m/issues/520)) ([823ea67](https://github.com/NC1107/slim-m/commit/823ea674b060767c2112503ddc4ef1323d902c03))

## [0.34.0](https://github.com/NC1107/slim-m/compare/server-v0.33.2...server-v0.34.0) (2026-08-09)


### Features

* **canvas:** media tile placement is shared and persists between calls ([#471](https://github.com/NC1107/slim-m/issues/471)) ([a16267b](https://github.com/NC1107/slim-m/commit/a16267bb47cc7a7a6c2997f207619ce11f2fc738))


### Bug Fixes

* **canvas:** the server never enforced a media tile's lock ([#476](https://github.com/NC1107/slim-m/issues/476)) ([5e39f21](https://github.com/NC1107/slim-m/commit/5e39f21d57dae8f0336dffdfe2cae0afc517c1c7))

## [0.33.2](https://github.com/NC1107/slim-m/compare/server-v0.33.1...server-v0.33.2) (2026-08-06)


### Bug Fixes

* **canvas:** a spent remove op could be replayed to undo somebody else's moderation ([#450](https://github.com/NC1107/slim-m/issues/450)) ([c15e82f](https://github.com/NC1107/slim-m/commit/c15e82f94bd28c99cfd177d363e66c2c07915b25))
* **canvas:** index the two columns the sweep and the op clock scan the whole table for ([#454](https://github.com/NC1107/slim-m/issues/454)) ([4ab71ca](https://github.com/NC1107/slim-m/commit/4ab71ca686a1a16ea094ae621d8b0fe18d1dd5cb))
* **canvas:** seed the op clock from the database, so a restart cannot reopen a closed bypass ([#451](https://github.com/NC1107/slim-m/issues/451)) ([1e51e65](https://github.com/NC1107/slim-m/commit/1e51e655c56e3a392e5067bae9239795493d6de1))

## [0.33.1](https://github.com/NC1107/slim-m/compare/server-v0.33.0...server-v0.33.1) (2026-08-06)


### Bug Fixes

* **canvas:** a clear that wrote rows it never reads, and a millisecond two writes can share ([#448](https://github.com/NC1107/slim-m/issues/448)) ([2a8e5ed](https://github.com/NC1107/slim-m/commit/2a8e5ed829c70fb3f6eee8743883897312eb9006))
* **canvas:** cap an in-flight draft, and measure a note in the bytes the wire actually counts ([#438](https://github.com/NC1107/slim-m/issues/438)) ([8279d8f](https://github.com/NC1107/slim-m/commit/8279d8f9aca6abd9b0f4971598fe6ab872f10955))
* **canvas:** count a restore's own targets against the op feed's byte budget ([#445](https://github.com/NC1107/slim-m/issues/445)) ([687b959](https://github.com/NC1107/slim-m/commit/687b95975188972102882b386bde5819c46a3cd5))

## [0.33.0](https://github.com/NC1107/slim-m/compare/server-v0.32.0...server-v0.33.0) (2026-08-06)


### Features

* **canvas:** compact the op log, and keep a moderation trail that outlives it ([#433](https://github.com/NC1107/slim-m/issues/433)) ([2eb9a10](https://github.com/NC1107/slim-m/commit/2eb9a109030a9db9dae4074ee358fa22a3a4562d))
* **canvas:** the note and shape tools decision 0004 named ([#435](https://github.com/NC1107/slim-m/issues/435)) ([bd532de](https://github.com/NC1107/slim-m/commit/bd532de88f3a9d2416f3f8519614a302f9e15e18))
* **canvas:** watch somebody draw, rather than watching their stroke appear ([#434](https://github.com/NC1107/slim-m/issues/434)) ([5024ab0](https://github.com/NC1107/slim-m/commit/5024ab03f4380777e8513b64d639248aa8532300))


### Bug Fixes

* **canvas:** re-check MANAGE_CANVAS when restoring another's moderation ([#429](https://github.com/NC1107/slim-m/issues/429)) ([18dafd2](https://github.com/NC1107/slim-m/commit/18dafd2ea49ae16a00fa9461d5f475a36fd7d0cd))

## [0.32.0](https://github.com/NC1107/slim-m/compare/server-v0.31.0...server-v0.32.0) (2026-08-05)


### Features

* **canvas:** resize a placed image, and control what sits on top ([#416](https://github.com/NC1107/slim-m/issues/416)) ([8d388f8](https://github.com/NC1107/slim-m/commit/8d388f88eaff6b1d646e90297f7ded5d885347de))
* paste an image onto the canvas and drag it around ([#410](https://github.com/NC1107/slim-m/issues/410)) ([b07e263](https://github.com/NC1107/slim-m/commit/b07e2637e7259091ba1b8e65ce01dabe616217a4))

## [0.31.0](https://github.com/NC1107/slim-m/compare/server-v0.30.0...server-v0.31.0) (2026-08-05)


### Features

* a per-account notification preference, including mentions only ([#397](https://github.com/NC1107/slim-m/issues/397)) ([9c756f8](https://github.com/NC1107/slim-m/commit/9c756f8fb5c003af1792fe8706cbf52e8635f2a5))
* multi-user canvas cursors, live and ephemeral ([#400](https://github.com/NC1107/slim-m/issues/400)) ([b4f6b8c](https://github.com/NC1107/slim-m/commit/b4f6b8cc75601cc0c88224c01a50e78a6370dcfb))
* Space usage analytics, off by default ([#401](https://github.com/NC1107/slim-m/issues/401)) ([f140ca8](https://github.com/NC1107/slim-m/commit/f140ca8154607fe27c68e4e22d7828d3123660a0))

## [0.30.0](https://github.com/NC1107/slim-m/compare/server-v0.29.0...server-v0.30.0) (2026-08-04)


### Features

* **server:** accept video, audio, archives and text as attachments ([#378](https://github.com/NC1107/slim-m/issues/378)) ([76a68bd](https://github.com/NC1107/slim-m/commit/76a68bd82f8939f9ac498bdd271af3fd7a98cd60))


### Bug Fixes

* widen the mention charset to match what a username can be ([#374](https://github.com/NC1107/slim-m/issues/374)) ([901e712](https://github.com/NC1107/slim-m/commit/901e712e54788f75a3a066c08a2844c126bf6ad9))

## [0.29.0](https://github.com/NC1107/slim-m/compare/server-v0.28.0...server-v0.29.0) (2026-08-04)


### Features

* a live in-app signal when a DM call starts or ends ([#358](https://github.com/NC1107/slim-m/issues/358)) ([4f34b57](https://github.com/NC1107/slim-m/commit/4f34b577a86ef69a7238df3160314784723154f2))


### Bug Fixes

* a thread reply wakes the thread, not the whole parent channel ([#357](https://github.com/NC1107/slim-m/issues/357)) ([ebc3d47](https://github.com/NC1107/slim-m/commit/ebc3d47caf0d1dd0e8b1bcf482b259a58ae9d4ed))
* eight findings from the 2026-08-04 multi-agent audit ([#362](https://github.com/NC1107/slim-m/issues/362)) ([2d954d3](https://github.com/NC1107/slim-m/commit/2d954d3453ec156382cdf33df4c822e2081cee71))

## [0.28.0](https://github.com/NC1107/slim-m/compare/server-v0.27.1...server-v0.28.0) (2026-08-04)


### Features

* channel categories you can drag any channel into ([#355](https://github.com/NC1107/slim-m/issues/355)) ([b34cd78](https://github.com/NC1107/slim-m/commit/b34cd786656c10d9b6de150f947642cdb81ceb53))


### Bug Fixes

* **client:** name why a message failed to send, and refuse it before it does ([#345](https://github.com/NC1107/slim-m/issues/345)) ([e20e9ab](https://github.com/NC1107/slim-m/commit/e20e9ab922f8eb20889cb1aaff4ffb0fddcf13e8))

## [0.27.1](https://github.com/NC1107/slim-m/compare/server-v0.27.0...server-v0.27.1) (2026-08-03)


### Bug Fixes

* moderation and blocking reach DM calls and thread reports ([#336](https://github.com/NC1107/slim-m/issues/336)) ([968bdfe](https://github.com/NC1107/slim-m/commit/968bdfe801daadff08c233f79d8d520c412ea4cc))

## [0.27.0](https://github.com/NC1107/slim-m/compare/server-v0.26.0...server-v0.27.0) (2026-08-03)


### Features

* live signal for a thread opening or gaining a reply ([#329](https://github.com/NC1107/slim-m/issues/329)) ([2fe2c9f](https://github.com/NC1107/slim-m/commit/2fe2c9ff3084701575bbacf41c27f27ae81d2e88))

## [0.26.0](https://github.com/NC1107/slim-m/compare/server-v0.25.0...server-v0.26.0) (2026-08-02)


### Features

* a reply-count affordance on threaded messages ([#315](https://github.com/NC1107/slim-m/issues/315)) ([a5d0524](https://github.com/NC1107/slim-m/commit/a5d05245162cdd5decacde3d487dd13e5053c955))

## [0.25.0](https://github.com/NC1107/slim-m/compare/server-v0.24.0...server-v0.25.0) (2026-08-01)


### Features

* threads, a channel with a parent (docs/decisions/0005-threads.md) ([#312](https://github.com/NC1107/slim-m/issues/312)) ([dc5e624](https://github.com/NC1107/slim-m/commit/dc5e624b496c8a4c5cd4d39a0c4758791ac6f61f))

## [0.24.0](https://github.com/NC1107/slim-m/compare/server-v0.23.0...server-v0.24.0) (2026-08-01)


### Features

* calling in a DM ([#306](https://github.com/NC1107/slim-m/issues/306)) ([6823474](https://github.com/NC1107/slim-m/commit/68234746807e080edb7f5e0b0ee4ebb2ecf95115))
* reply to a message, and write up threads instead of building them ([#308](https://github.com/NC1107/slim-m/issues/308)) ([dffcdaa](https://github.com/NC1107/slim-m/commit/dffcdaa1747eae05e61c858c6dcc17380fe990d8))


### Bug Fixes

* reconcile a display name across already-cached messages ([#288](https://github.com/NC1107/slim-m/issues/288)) ([7ed4906](https://github.com/NC1107/slim-m/commit/7ed4906fd6aa4e3c0c4cda81f1a315e2917ce2b1))

## [0.23.0](https://github.com/NC1107/slim-m/compare/server-v0.22.0...server-v0.23.0) (2026-08-01)


### Features

* drag to reorder channels, ordered deployment-wide ([#271](https://github.com/NC1107/slim-m/issues/271)) ([753b3d4](https://github.com/NC1107/slim-m/commit/753b3d4521908186ffe811dda712993fe20ed1aa))


### Bug Fixes

* **test:** stop the attachment fixture leaking a media directory per test ([#263](https://github.com/NC1107/slim-m/issues/263)) ([e5e6a5f](https://github.com/NC1107/slim-m/commit/e5e6a5f66153b7551b351074ca88d97677671bed))

## [0.22.0](https://github.com/NC1107/slim-m/compare/server-v0.21.0...server-v0.22.0) (2026-08-01)


### Features

* **client:** device-use polish, a what's-new screen, and a dead-code sweep ([#256](https://github.com/NC1107/slim-m/issues/256)) ([cd927ac](https://github.com/NC1107/slim-m/commit/cd927ac993bdaca37a5ccc31041e6f44009f46cd))

## [0.21.0](https://github.com/NC1107/slim-m/compare/server-v0.20.0...server-v0.21.0) (2026-07-31)


### Features

* **server:** a message op stream for edits and deletes ([#235](https://github.com/NC1107/slim-m/issues/235)) ([b686736](https://github.com/NC1107/slim-m/commit/b68673696f196440296075554f6e40f2b981ae02))
* **server:** carry message ops on /sync and the two live frames ([#237](https://github.com/NC1107/slim-m/issues/237)) ([16ecb5f](https://github.com/NC1107/slim-m/commit/16ecb5f369b94292237ffb3edc8e845a249cfd04))


### Bug Fixes

* **server:** withhold the canvas moderator's id from the ops feed ([#233](https://github.com/NC1107/slim-m/issues/233)) ([e2e9063](https://github.com/NC1107/slim-m/commit/e2e9063cb697b0167578af93039a4c7dd93d2655))

## [0.20.0](https://github.com/NC1107/slim-m/compare/server-v0.19.0...server-v0.20.0) (2026-07-31)


### Features

* **server:** canvas remove and clear, MANAGE_CANVAS enforcement, and the two new socket events ([#219](https://github.com/NC1107/slim-m/issues/219)) ([1ba6846](https://github.com/NC1107/slim-m/commit/1ba6846177436ad98fd2c28e470f8630f91b7b68))
* **server:** canvas restore, its authorship gate, and the object ceiling ([#221](https://github.com/NC1107/slim-m/issues/221)) ([f847baa](https://github.com/NC1107/slim-m/commit/f847baa9cb0efc586cdb8e92df33b4962892c272))

## [0.19.0](https://github.com/NC1107/slim-m/compare/server-v0.18.5...server-v0.19.0) (2026-07-31)


### Features

* a personal space, opened by DMing yourself ([#204](https://github.com/NC1107/slim-m/issues/204)) ([951d1b3](https://github.com/NC1107/slim-m/commit/951d1b341ebc3e7c1985211407ec05e9ce44e1f1))
* **server:** the canvas op stream, its catch-up feed, and one snapshot for the viewport read ([#218](https://github.com/NC1107/slim-m/issues/218)) ([ba79c07](https://github.com/NC1107/slim-m/commit/ba79c07107fab29b0de531ae116dd7d4ecdd2e9c))


### Bug Fixes

* a relaunched client no longer shows itself as still on a call ([#205](https://github.com/NC1107/slim-m/issues/205)) ([2aa141d](https://github.com/NC1107/slim-m/commit/2aa141dafc3861be4cdae859a5c95237fdb8bde7))
* **server:** four correctness findings in fan-out, presence, devices and member count ([#210](https://github.com/NC1107/slim-m/issues/210)) ([dbe65c3](https://github.com/NC1107/slim-m/commit/dbe65c3abe00b0eaca25fe7b49d0df312e9f9c8e))

## [0.18.5](https://github.com/NC1107/slim-m/compare/server-v0.18.4...server-v0.18.5) (2026-07-31)


### Bug Fixes

* **canvas:** a web z-index truncation, an unbounded refetch loop, and stacked headers ([#198](https://github.com/NC1107/slim-m/issues/198)) ([5875cc4](https://github.com/NC1107/slim-m/commit/5875cc4d57e999dc5b9364204c829d2139a2be6d))

## [0.18.4](https://github.com/NC1107/slim-m/compare/server-v0.18.3...server-v0.18.4) (2026-07-30)


### Bug Fixes

* **server:** make the typing presence gate fail closed on a store error ([#184](https://github.com/NC1107/slim-m/issues/184)) ([9eb1824](https://github.com/NC1107/slim-m/commit/9eb1824e336cbe7c17f0073ac20cc93b97636a9e))
* **server:** rebuild messages onto an explicit rowid alias ([#183](https://github.com/NC1107/slim-m/issues/183)) ([adc009a](https://github.com/NC1107/slim-m/commit/adc009a8252203a9a38fec4fb340560699ebb276))

## [0.18.3](https://github.com/NC1107/slim-m/compare/server-v0.18.2...server-v0.18.3) (2026-07-30)


### Bug Fixes

* **server:** answer a retried poll send after its message was deleted ([#174](https://github.com/NC1107/slim-m/issues/174)) ([b0d3892](https://github.com/NC1107/slim-m/commit/b0d3892b2d00d58c4e2f2b8b9b8e08623fcd05d7))
* **server:** make password recovery revoke sessions atomically ([#178](https://github.com/NC1107/slim-m/issues/178)) ([f2d73e7](https://github.com/NC1107/slim-m/commit/f2d73e7e0434bcf1f09529c13af082a0ffcf4438))

## [0.18.2](https://github.com/NC1107/slim-m/compare/server-v0.18.1...server-v0.18.2) (2026-07-30)


### Performance Improvements

* **ws:** cache VIEW_CHANNEL per connection, invalidated by the events ([#165](https://github.com/NC1107/slim-m/issues/165)) ([f794765](https://github.com/NC1107/slim-m/commit/f794765d61863a6814d1af26d2e287138de7b41b))

## [0.18.1](https://github.com/NC1107/slim-m/compare/server-v0.18.0...server-v0.18.1) (2026-07-30)


### Bug Fixes

* bound the two reads that answered with everything ([#148](https://github.com/NC1107/slim-m/issues/148)) ([eb352cd](https://github.com/NC1107/slim-m/commit/eb352cd26a3c2578c14b0d9685442650b0f28f5d))
* make blocking actually hide what it says it hides ([#147](https://github.com/NC1107/slim-m/issues/147)) ([7cf0618](https://github.com/NC1107/slim-m/commit/7cf0618b2f5b1ee4cda59b2df62a0c01611a1338))
* name the subject of a report before asking to close it ([#157](https://github.com/NC1107/slim-m/issues/157)) ([4546722](https://github.com/NC1107/slim-m/commit/45467221e564cf122e3dc8a90ce4f1852e92f27f))
* **server:** apply the target-level guard to role and voice moderation ([#149](https://github.com/NC1107/slim-m/issues/149)) ([316744a](https://github.com/NC1107/slim-m/commit/316744a61cf3e6017e9e1807e46f825a892c20e0))
* **server:** authorize an attachment reference, not just its existence ([#150](https://github.com/NC1107/slim-m/issues/150)) ([3b19c60](https://github.com/NC1107/slim-m/commit/3b19c602e24b0cea80a42e867ff430344798c708))
* **server:** bound the unauthenticated request surface ([#145](https://github.com/NC1107/slim-m/issues/145)) ([db5bbe7](https://github.com/NC1107/slim-m/commit/db5bbe70fd17253e04a57c0791be080bac1ef2ee))
* **server:** publish the role, overwrite and channel events nothing published ([#161](https://github.com/NC1107/slim-m/issues/161)) ([bef83ee](https://github.com/NC1107/slim-m/commit/bef83ee1411fd6e97f365f8d688878a2ecf28b97))
* **server:** set the two ceilings nobody had set ([#151](https://github.com/NC1107/slim-m/issues/151)) ([3649000](https://github.com/NC1107/slim-m/commit/3649000510e3ccf39b5f434c19ce9d3b20727bbf))

## [0.18.0](https://github.com/NC1107/slim-m/compare/server-v0.17.0...server-v0.18.0) (2026-07-29)


### Features

* **client:** per-participant volume, roles, timeout and removal in the member profile ([#138](https://github.com/NC1107/slim-m/issues/138)) ([e746bcd](https://github.com/NC1107/slim-m/commit/e746bcd4c89e1dcd507d49c43ea345d6ea4d83d5))
* **server:** member timeouts and removal from the Space ([#136](https://github.com/NC1107/slim-m/issues/136)) ([1474ef8](https://github.com/NC1107/slim-m/commit/1474ef89921907bdb1cbf20082249a1a07d11733))

## [0.17.0](https://github.com/NC1107/slim-m/compare/server-v0.16.1...server-v0.17.0) (2026-07-29)


### Features

* render peer screen shares, call tiles, and the nine-specialist audit batch ([#123](https://github.com/NC1107/slim-m/issues/123)) ([b34be33](https://github.com/NC1107/slim-m/commit/b34be33bc6b87f68995479f39a440e841cf18170))

## [0.16.1](https://github.com/NC1107/slim-m/compare/server-v0.16.0...server-v0.16.1) (2026-07-29)


### Bug Fixes

* close 16 defects a multi-agent audit found, moderation-queue holes first ([#118](https://github.com/NC1107/slim-m/issues/118)) ([b4eab36](https://github.com/NC1107/slim-m/commit/b4eab36e4e0b2b35a180542fe987225677fd82d7))

## [0.16.0](https://github.com/NC1107/slim-m/compare/server-v0.15.0...server-v0.16.0) (2026-07-28)


### Features

* add a per-channel voice roster so the rail shows who is already there ([#98](https://github.com/NC1107/slim-m/issues/98)) ([06d13d7](https://github.com/NC1107/slim-m/commit/06d13d7b3c96cc5b137a8131fd1da870cc4785b6))


### Bug Fixes

* **server:** map malformed-body and query rejections to the JSON error contract ([#102](https://github.com/NC1107/slim-m/issues/102)) ([0d06318](https://github.com/NC1107/slim-m/commit/0d063189845c7f20ca48b5857cc911d847b01c36))

## [0.15.0](https://github.com/NC1107/slim-m/compare/server-v0.14.3...server-v0.15.0) (2026-07-28)


### Features

* role-granting invites, a disabled segmented option, and a backlog that was mostly stale ([#87](https://github.com/NC1107/slim-m/issues/87)) ([25b10fb](https://github.com/NC1107/slim-m/commit/25b10fb671e26ecfe5e8d62daa5f1aeafae832a3))


### Bug Fixes

* **server:** carry a message's attachments on its live frame ([#91](https://github.com/NC1107/slim-m/issues/91)) ([7c1a626](https://github.com/NC1107/slim-m/commit/7c1a626638e047cac7f1bdfd19aa81701fb2d319))

## [0.14.3](https://github.com/NC1107/slim-m/compare/server-v0.14.2...server-v0.14.3) (2026-07-28)


### Bug Fixes

* **server:** deleting a message whose image is also an emoji ([#85](https://github.com/NC1107/slim-m/issues/85)) ([2d2644b](https://github.com/NC1107/slim-m/commit/2d2644ba4ea902f0752ba40b06995e4f248e97cf))

## [0.14.2](https://github.com/NC1107/slim-m/compare/server-v0.14.1...server-v0.14.2) (2026-07-28)


### Bug Fixes

* desktop screen share, colour emoji, rail alignment, and who can join ([#81](https://github.com/NC1107/slim-m/issues/81)) ([4dd1bb1](https://github.com/NC1107/slim-m/commit/4dd1bb13090f2056952743ea397073df4bdb5ba3))

## [0.14.1](https://github.com/NC1107/slim-m/compare/server-v0.14.0...server-v0.14.1) (2026-07-28)


### Bug Fixes

* **mobile:** image-only sends, fullscreen media, Fedora packaging, and Space naming ([#77](https://github.com/NC1107/slim-m/issues/77)) ([cbf89d4](https://github.com/NC1107/slim-m/commit/cbf89d494fb80e7f14a01677237358eda5c9bbe2))

## [0.14.0](https://github.com/NC1107/slim-m/compare/server-v0.13.0...server-v0.14.0) (2026-07-27)


### Features

* **server:** bulk emoji import, and fix the orphan sweep it exposed ([#75](https://github.com/NC1107/slim-m/issues/75)) ([4e3e9b1](https://github.com/NC1107/slim-m/commit/4e3e9b11931e591caee1129622771cdbbd861b81))
* **server:** custom emoji ([#72](https://github.com/NC1107/slim-m/issues/72)) ([4823ef7](https://github.com/NC1107/slim-m/commit/4823ef7f4415efb5ad92ea81ad3d0138fef245b9))

## [0.13.0](https://github.com/NC1107/slim-m/compare/server-v0.12.0...server-v0.13.0) (2026-07-27)


### Features

* CORS, moderation and admin UI, message actions, and a web build ([#61](https://github.com/NC1107/slim-m/issues/61)) ([dca58e6](https://github.com/NC1107/slim-m/commit/dca58e690dc66ee5c049e60513982452e042f65e))

## [0.12.0](https://github.com/NC1107/slim-m/compare/server-v0.11.1...server-v0.12.0) (2026-07-27)


### Features

* the Phase 5 canvas de-risking spike ([#59](https://github.com/NC1107/slim-m/issues/59)) ([614aba0](https://github.com/NC1107/slim-m/commit/614aba096348a38662c5bb4c85b9088733c3bde8))

## [0.11.1](https://github.com/NC1107/slim-m/compare/server-v0.11.0...server-v0.11.1) (2026-07-27)


### Bug Fixes

* iOS purpose strings, the Android Kotlin build, and the voice kick ([#55](https://github.com/NC1107/slim-m/issues/55)) ([c7980f2](https://github.com/NC1107/slim-m/commit/c7980f2591e7be93cd9d2da2bdbd71bc9e84014a))

## [0.11.0](https://github.com/NC1107/slim-m/compare/server-v0.10.0...server-v0.11.0) (2026-07-26)


### Features

* align the ui to the design, and build the backends it assumed ([#52](https://github.com/NC1107/slim-m/issues/52)) ([fdc56a8](https://github.com/NC1107/slim-m/commit/fdc56a8067f580e3d8c6a9ba22193cd5e2ecb64e))

## [0.10.0](https://github.com/NC1107/slim-m/compare/server-v0.9.0...server-v0.10.0) (2026-07-26)


### Features

* phase 4 rtc spike, livekit tokens, callkit, and the design review ([#47](https://github.com/NC1107/slim-m/issues/47)) ([719331b](https://github.com/NC1107/slim-m/commit/719331b9d069aa1dcdebce7d123838c6624419ff))

## [0.9.0](https://github.com/NC1107/slim-m/compare/server-v0.8.0...server-v0.9.0) (2026-07-26)


### ⚠ BREAKING CHANGES

* gate registration behind an invite, plus the phase 3 audit fixes ([#42](https://github.com/NC1107/slim-m/issues/42))

### Features

* gate registration behind an invite, plus the phase 3 audit fixes ([#42](https://github.com/NC1107/slim-m/issues/42)) ([06a9397](https://github.com/NC1107/slim-m/commit/06a93975f126f39aec335760ba0712901103b279))

## [0.8.0](https://github.com/NC1107/slim-m/compare/server-v0.7.0...server-v0.8.0) (2026-07-26)


### Features

* surface push reachability during onboarding ([#39](https://github.com/NC1107/slim-m/issues/39)) ([76e4cfd](https://github.com/NC1107/slim-m/commit/76e4cfddf35a86bb678930cf9f850e2f34493f26))

## [0.7.0](https://github.com/NC1107/slim-m/compare/server-v0.6.0...server-v0.7.0) (2026-07-26)


### Features

* android push, sender names, and the envelope contract test ([#33](https://github.com/NC1107/slim-m/issues/33)) ([e689871](https://github.com/NC1107/slim-m/commit/e6898716143160e1c5a3ebc96311d6f094453025))
* **server:** the endpoints the frontend still needs ([#36](https://github.com/NC1107/slim-m/issues/36)) ([a2011fc](https://github.com/NC1107/slim-m/commit/a2011fc8802080992a8f0260968f05f7bd63124c))

## [0.6.0](https://github.com/NC1107/slim-m/compare/server-v0.5.0...server-v0.6.0) (2026-07-25)


### Features

* server-side push, mobile targets, and the TestFlight pipeline ([#30](https://github.com/NC1107/slim-m/issues/30)) ([9799f9d](https://github.com/NC1107/slim-m/commit/9799f9d5a5e82a9699da00b974a2a18c760a0c99))
* **server:** devices, blocking, and report intake ([#24](https://github.com/NC1107/slim-m/issues/24)) ([5046e04](https://github.com/NC1107/slim-m/commit/5046e04c02459b4507ee611397852c770f656b73))
* **server:** invites ([#27](https://github.com/NC1107/slim-m/issues/27)) ([29960a8](https://github.com/NC1107/slim-m/commit/29960a81454fe1afd320a5fca31897dd8916582e))

## [0.5.0](https://github.com/NC1107/slim-m/compare/server-v0.4.0...server-v0.5.0) (2026-07-24)


### Features

* **server:** in-process rate limiting ([#19](https://github.com/NC1107/slim-m/issues/19)) ([7003f46](https://github.com/NC1107/slim-m/commit/7003f46076a30cbc0d09023b5fda2aada11bc7c8))

## [0.4.0](https://github.com/NC1107/slim-m/compare/server-v0.3.0...server-v0.4.0) (2026-07-24)


### Features

* **server:** first-run bootstrap and channel routes ([#16](https://github.com/NC1107/slim-m/issues/16)) ([0dbd743](https://github.com/NC1107/slim-m/commit/0dbd743ca3f5d7419271463d602dcaaa1e991095))

## [0.3.0](https://github.com/NC1107/slim-m/compare/server-v0.2.0...server-v0.3.0) (2026-07-24)


### Features

* complete Phase 0 build-out (CI, release pipeline, perf, gates, compose) ([62bf042](https://github.com/NC1107/slim-m/commit/62bf042a47865f7216416fd54275a6bf14f997b5))
* **db:** add Phase 1 core schema migration ([#3](https://github.com/NC1107/slim-m/issues/3)) ([a35e59f](https://github.com/NC1107/slim-m/commit/a35e59f1f7a7e9189581ab3794489220d0609dc7))
* scaffold Phase 0 foundations ([e7f3028](https://github.com/NC1107/slim-m/commit/e7f3028d2620788f414db953cde2c84db8c07589))
* **server:** account deletion end to end ([#15](https://github.com/NC1107/slim-m/issues/15)) ([cb16f8d](https://github.com/NC1107/slim-m/commit/cb16f8d81073bfa2ff54858ed35329b468b8bc22))
* **server:** auth with Argon2id, opaque tokens, refresh rotation, and WS tickets ([#10](https://github.com/NC1107/slim-m/issues/10)) ([36cf7bf](https://github.com/NC1107/slim-m/commit/36cf7bf1cb920b2d725dcbae1b9ac9881b3aa16a))
* **server:** deny-by-default permission evaluator ([#11](https://github.com/NC1107/slim-m/issues/11)) ([47e297a](https://github.com/NC1107/slim-m/commit/47e297acf0a1897c985ac6f6bc8fe36e22507326))
* **server:** identity and message store (per-scope ordering, idempotent send) ([#8](https://github.com/NC1107/slim-m/issues/8)) ([3e1f37d](https://github.com/NC1107/slim-m/commit/3e1f37d6de5702e2602f5cda13911239eb365cd1))
* **server:** read state and the bundled sync cursor ([#14](https://github.com/NC1107/slim-m/issues/14)) ([df726fc](https://github.com/NC1107/slim-m/commit/df726fc9eedfdabaf98b22a987491765e092e561))
* **server:** REST message endpoints with server-side authorization ([#12](https://github.com/NC1107/slim-m/issues/12)) ([a95063f](https://github.com/NC1107/slim-m/commit/a95063f3a5bd5ca5243b1e41fce7c6e3f5f4ae22))
* **server:** WebSocket envelope and fan-out ([#13](https://github.com/NC1107/slim-m/issues/13)) ([071536e](https://github.com/NC1107/slim-m/commit/071536e230053fd029d67bccf0f61eb0eb5274a9))

## [0.2.0](https://github.com/NC1107/slim-m/compare/server-v0.1.0...server-v0.2.0) (2026-07-24)


### Features

* complete Phase 0 build-out (CI, release pipeline, perf, gates, compose) ([62bf042](https://github.com/NC1107/slim-m/commit/62bf042a47865f7216416fd54275a6bf14f997b5))
* **db:** add Phase 1 core schema migration ([#3](https://github.com/NC1107/slim-m/issues/3)) ([a35e59f](https://github.com/NC1107/slim-m/commit/a35e59f1f7a7e9189581ab3794489220d0609dc7))
* scaffold Phase 0 foundations ([e7f3028](https://github.com/NC1107/slim-m/commit/e7f3028d2620788f414db953cde2c84db8c07589))

## 0.1.0 (2026-07-24)


### Features

* complete Phase 0 build-out (CI, release pipeline, perf, gates, compose) ([62bf042](https://github.com/NC1107/slim-m/commit/62bf042a47865f7216416fd54275a6bf14f997b5))
* **db:** add Phase 1 core schema migration ([#3](https://github.com/NC1107/slim-m/issues/3)) ([a35e59f](https://github.com/NC1107/slim-m/commit/a35e59f1f7a7e9189581ab3794489220d0609dc7))
* scaffold Phase 0 foundations ([e7f3028](https://github.com/NC1107/slim-m/commit/e7f3028d2620788f414db953cde2c84db8c07589))
