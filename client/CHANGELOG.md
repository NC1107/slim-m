# Changelog

## [0.37.0](https://github.com/NC1107/slim-m/compare/client-v0.36.0...client-v0.37.0) (2026-08-11)


### Features

* **client:** a camera-on-join preference, the last piece of the pre-toggle ([#546](https://github.com/NC1107/slim-m/issues/546)) ([b832162](https://github.com/NC1107/slim-m/commit/b83216222bd89c62258a0a884d05649f6116f6ba))
* **client:** build the desktop window shell decision 0012 designed ([#533](https://github.com/NC1107/slim-m/issues/533)) ([506b82a](https://github.com/NC1107/slim-m/commit/506b82a71d855c6d1d913acc285d94d0d0f7feba))
* **client:** one container system for settings and administration ([#532](https://github.com/NC1107/slim-m/issues/532)) ([076a6ed](https://github.com/NC1107/slim-m/commit/076a6ed868d75f118c59d5eed88d8dad6a44cd72))
* **client:** unsubscribe canvas video for tiles outside the viewport ([#558](https://github.com/NC1107/slim-m/issues/558)) ([bd1d644](https://github.com/NC1107/slim-m/commit/bd1d64408d94ed60286217668212a2f890c6209c))


### Bug Fixes

* **ci:** close comment-defeatable blind spots in source-reading gates ([#553](https://github.com/NC1107/slim-m/issues/553)) ([1b13496](https://github.com/NC1107/slim-m/commit/1b1349601f63a6b6694c2de1539e5171337eae50))
* **client:** a second launch focuses the running window instead of spawning a duplicate ([#539](https://github.com/NC1107/slim-m/issues/539)) ([397674e](https://github.com/NC1107/slim-m/commit/397674e3946bcd9ce598b3c40e7903d8d06e6221))
* **client:** close the second-tier findings from the screen-review pass ([#542](https://github.com/NC1107/slim-m/issues/542)) ([2275fe9](https://github.com/NC1107/slim-m/commit/2275fe9d522d947f970e708ebb7cc28dce0e734d))
* **client:** close the shadow artifact that fooled five review passes ([#543](https://github.com/NC1107/slim-m/issues/543)) ([deaba8e](https://github.com/NC1107/slim-m/commit/deaba8e99a137b4697d7df5cc93e3a26ab5b72cc))
* **client:** close the sharp findings from the screen-review pass ([#535](https://github.com/NC1107/slim-m/issues/535)) ([f5b1d13](https://github.com/NC1107/slim-m/commit/f5b1d13fa06c02b89daabc726f83146cdf676a0f))
* **client:** give a desktop with no tray a real way to quit ([#544](https://github.com/NC1107/slim-m/issues/544)) ([debb349](https://github.com/NC1107/slim-m/commit/debb3492b7cd5977092f6226f47cc03d07cac610))
* **client:** give the composer field its own stable accessible name ([#550](https://github.com/NC1107/slim-m/issues/550)) ([37585e7](https://github.com/NC1107/slim-m/commit/37585e737a0fa23f8a4929c9925cf201c39fc845))
* **client:** shrink the canvas call dock's call controls at pointer width ([#537](https://github.com/NC1107/slim-m/issues/537)) ([27947da](https://github.com/NC1107/slim-m/commit/27947dae7bb76b6718706e1ba112c1ed6b411540))
* **client:** stop the canvas image hydrator eviction test from flaking under load ([#534](https://github.com/NC1107/slim-m/issues/534)) ([308bc58](https://github.com/NC1107/slim-m/commit/308bc588f77af85367d2ec97368ef8d98a1eac19))
* **client:** tell the true story on the no-tray minimise fallback ([#541](https://github.com/NC1107/slim-m/issues/541)) ([7e4cd0d](https://github.com/NC1107/slim-m/commit/7e4cd0dc95a35aef96825c8858329c4fcb5365a4))
* **client:** the report card's reporter row overflows a long name at phone width ([#545](https://github.com/NC1107/slim-m/issues/545)) ([4a637d2](https://github.com/NC1107/slim-m/commit/4a637d225bbab93404295ee7688645d441db140e))

## [0.36.0](https://github.com/NC1107/slim-m/compare/client-v0.35.1...client-v0.36.0) (2026-08-10)


### Features

* **client:** add channelPermissionsProvider, unused by any call site yet ([#521](https://github.com/NC1107/slim-m/issues/521)) ([e4f3d12](https://github.com/NC1107/slim-m/commit/e4f3d1236e0378cb1f9917e3339ebe0a4319105f))


### Bug Fixes

* **canvas:** a presence tile's opaque hit test silently ate every wheel event ([#529](https://github.com/NC1107/slim-m/issues/529)) ([a9692ca](https://github.com/NC1107/slim-m/commit/a9692ca98f1e3bc2734e3aa42d72ebf96d9f492c))
* **canvas:** reveal tile controls on focus too, and prove depth by pixel ([#526](https://github.com/NC1107/slim-m/issues/526)) ([62d16e6](https://github.com/NC1107/slim-m/commit/62d16e6d38835fc13fa102dca1f2d64603a4ffdc))
* **canvas:** the background grid was mounted childless in a Stack with no fit, so it never painted ([#515](https://github.com/NC1107/slim-m/issues/515)) ([7a328d9](https://github.com/NC1107/slim-m/commit/7a328d93a0108e817d3b5907c19eaaa2ba1f46da))
* **canvas:** the ctrl+wheel zoom test could not tell a real fix from a broken one ([#525](https://github.com/NC1107/slim-m/issues/525)) ([7ddb0b2](https://github.com/NC1107/slim-m/commit/7ddb0b227a31276c19f6292a15d5ff12a12ebba3))
* **canvas:** the grid painted over a sent-back tile, and a small object could not be dragged ([#505](https://github.com/NC1107/slim-m/issues/505)) ([1283670](https://github.com/NC1107/slim-m/commit/128367092ea6e9676d2dc6a7f900f83a08e5618a))
* **client:** a DM offered a member pane, a canvas button and a channel hash ([#504](https://github.com/NC1107/slim-m/issues/504)) ([b5f4d65](https://github.com/NC1107/slim-m/commit/b5f4d652c1550dc3d5bdb1f148d9f99ab43c30ef))
* **client:** draw one ring for a reacted reaction chip, not two ([#531](https://github.com/NC1107/slim-m/issues/531)) ([496cf8e](https://github.com/NC1107/slim-m/commit/496cf8ef488765d38a7e421bdef6e66d060bbc04))
* **client:** gate the transcript and canvas on per-channel permissions ([#522](https://github.com/NC1107/slim-m/issues/522)) ([0e73d25](https://github.com/NC1107/slim-m/commit/0e73d251ccc8105e87c1848b8c0726745a7152ab))
* **client:** pin the voice snapshot to its connecting state instead of a blank auto-join ([#513](https://github.com/NC1107/slim-m/issues/513)) ([1f80ad2](https://github.com/NC1107/slim-m/commit/1f80ad2e16d60a8e49d001ba38ac70c5fc33af38))
* **client:** read per-channel permissions in moderation and settings sites ([#523](https://github.com/NC1107/slim-m/issues/523)) ([220d30f](https://github.com/NC1107/slim-m/commit/220d30fdd312a223e9da3b17c7337fe84010e246))
* **client:** redesign the poll composer and the rendered poll card ([#530](https://github.com/NC1107/slim-m/issues/530)) ([0fb7853](https://github.com/NC1107/slim-m/commit/0fb785342a00d513f841243431d426a406abfb02))
* **client:** rename yourself lives in Account & presence, and the nav gets icons ([#503](https://github.com/NC1107/slim-m/issues/503)) ([d6ca9a5](https://github.com/NC1107/slim-m/commit/d6ca9a5af2ad5d61da5dfe282a983dfebc67104c))
* **client:** stop the screen capture when a call ends, not just the publish ([#528](https://github.com/NC1107/slim-m/issues/528)) ([7afd03e](https://github.com/NC1107/slim-m/commit/7afd03e0d17f7bb9c7f65c10b66312ea28855252))

## [0.35.1](https://github.com/NC1107/slim-m/compare/client-v0.35.0...client-v0.35.1) (2026-08-09)


### Bug Fixes

* **client:** a snackbar could cover the leave-call button, and both new gates had holes ([#501](https://github.com/NC1107/slim-m/issues/501)) ([88a1931](https://github.com/NC1107/slim-m/commit/88a1931715effde01fe6b12137aaefb50041c6b1))
* **client:** a SnackBar ignored the in-app motion setting, the same gap showAppSheet already closed ([#496](https://github.com/NC1107/slim-m/issues/496)) ([0669245](https://github.com/NC1107/slim-m/commit/0669245b4e7ee4e66a5b72905896239027b6a885))
* **client:** a snackbar shown before the call dock appears stayed stranded on top of it, and two more gate holes ([#502](https://github.com/NC1107/slim-m/issues/502)) ([7889dd4](https://github.com/NC1107/slim-m/commit/7889dd4e5e2743266838a89364e8aec43a0c4609))
* **client:** a thread's composer showed a dangling "Message #" hint ([#495](https://github.com/NC1107/slim-m/issues/495)) ([18d1c02](https://github.com/NC1107/slim-m/commit/18d1c02b5ba49bb35afe8cdfaa298b96e0cb7da7))
* **client:** three Flutter-owned entrances ignored the in-app motion setting ([#492](https://github.com/NC1107/slim-m/issues/492)) ([864fd5d](https://github.com/NC1107/slim-m/commit/864fd5dd57a42dac0920c49042a052589b4db8b7))
* **client:** three picker failures go inline, and the error gate had no real coverage ([#498](https://github.com/NC1107/slim-m/issues/498)) ([810f2e3](https://github.com/NC1107/slim-m/commit/810f2e3cfd70754822cfa6824cdd6eed15e8be4e))
* **client:** Unblock stopped sharing Block's ban glyph, and icon sizes reached for a name ([#497](https://github.com/NC1107/slim-m/issues/497)) ([8c1ef35](https://github.com/NC1107/slim-m/commit/8c1ef35a944ab891915e6ab6a2a691f8293f7696))


### Performance Improvements

* **client:** starting one edit re-parsed every visible message's markdown ([#499](https://github.com/NC1107/slim-m/issues/499)) ([091dac0](https://github.com/NC1107/slim-m/commit/091dac0cb2ab25b2278f51b37ecbf7e5e3f63873))

## [0.35.0](https://github.com/NC1107/slim-m/compare/client-v0.34.0...client-v0.35.0) (2026-08-09)


### Features

* **canvas:** media tile placement is shared and persists between calls ([#471](https://github.com/NC1107/slim-m/issues/471)) ([a16267b](https://github.com/NC1107/slim-m/commit/a16267bb47cc7a7a6c2997f207619ce11f2fc738))


### Bug Fixes

* **canvas:** a reconnect while the canvas stayed open never refetched shared media-slot positions ([#474](https://github.com/NC1107/slim-m/issues/474)) ([d3612d0](https://github.com/NC1107/slim-m/commit/d3612d02d7aa09f79d5b7a22d5405983ca95e9ce))
* **client:** a channel switch mid-join could corrupt a different call's state ([#487](https://github.com/NC1107/slim-m/issues/487)) ([53e73f0](https://github.com/NC1107/slim-m/commit/53e73f0cc608f0e9e11f378b0ee646cd6ed2fb2a))
* **client:** a failed background refresh threw away data the app still had ([#483](https://github.com/NC1107/slim-m/issues/483)) ([2a5c090](https://github.com/NC1107/slim-m/commit/2a5c090f5b4c5450a2bbed064b773abbaf7975c3))
* **client:** a join and a share hand-off both remounted the call stage ([#479](https://github.com/NC1107/slim-m/issues/479)) ([48dd630](https://github.com/NC1107/slim-m/commit/48dd630472a774c0d2488f8cf9db34a7beed0589))
* **client:** a poll, a spoiler and an author name could not be reached by keyboard ([#486](https://github.com/NC1107/slim-m/issues/486)) ([89be465](https://github.com/NC1107/slim-m/commit/89be4654133c3fa60fc5e5466d2cb8de00feb906))
* **client:** Escape did nothing in three popovers, and two source sheets used the wrong row ([#482](https://github.com/NC1107/slim-m/issues/482)) ([2a0063c](https://github.com/NC1107/slim-m/commit/2a0063c0968ed682649682fdbe430bc7c6d36084))
* **client:** five ways an overlay disagreed with every other overlay ([#481](https://github.com/NC1107/slim-m/issues/481)) ([b6925bc](https://github.com/NC1107/slim-m/commit/b6925bc5f206553e83e767195513da6f837cc3c7))
* **client:** five ways the transcript overflowed or misrendered real content ([#478](https://github.com/NC1107/slim-m/issues/478)) ([f657b98](https://github.com/NC1107/slim-m/commit/f657b98cc5a205ce5e314aff6bb5b5b3322a0a5f))
* **client:** sweep design-system token literals and add a regression gate ([#485](https://github.com/NC1107/slim-m/issues/485)) ([8235219](https://github.com/NC1107/slim-m/commit/8235219269d1d6f022c1274d59953fea3610cf54))
* **client:** the admin picker sheets and account rows used a bare ListTile ([#484](https://github.com/NC1107/slim-m/issues/484)) ([354d5e9](https://github.com/NC1107/slim-m/commit/354d5e965825bad38dd2aacf5e58007f3e403234))
* **client:** three settings surfaces still showed a failed write as a vanishing toast ([#489](https://github.com/NC1107/slim-m/issues/489)) ([2064a36](https://github.com/NC1107/slim-m/commit/2064a36d76366fdaa10a1cc657012a9b1627feed))
* **design_system:** a bare ListTile lost the product's own font ([#477](https://github.com/NC1107/slim-m/issues/477)) ([56fa541](https://github.com/NC1107/slim-m/commit/56fa541532132b44b8396f75532fbdf2973efb6f))
* **design_system:** every focusable control draws the app's own focus ring ([#488](https://github.com/NC1107/slim-m/issues/488)) ([509b86b](https://github.com/NC1107/slim-m/commit/509b86bbcb01ae10c0a2a3d5fe6aece8bfe0c219))

## [0.34.0](https://github.com/NC1107/slim-m/compare/client-v0.33.0...client-v0.34.0) (2026-08-08)


### Features

* **canvas:** camera and screen-share tiles as movable AR objects ([#470](https://github.com/NC1107/slim-m/issues/470)) ([3eb30c5](https://github.com/NC1107/slim-m/commit/3eb30c5f7b8befb73fc0913b2b8ce62abffdeac3))


### Bug Fixes

* **canvas:** a full-surface phantom tap node was silently eating gestures under accessibility ([#465](https://github.com/NC1107/slim-m/issues/465)) ([8421ecc](https://github.com/NC1107/slim-m/commit/8421ecca2e261d433689401112da6dd9b304068c))
* **canvas:** a second pointer's own grab button could steal an in-progress pan ([#467](https://github.com/NC1107/slim-m/issues/467)) ([283964e](https://github.com/NC1107/slim-m/commit/283964eba45109a7614b82840af81c68c9314583))
* **canvas:** four defects in the interaction code nobody had reviewed ([#463](https://github.com/NC1107/slim-m/issues/463)) ([f91f808](https://github.com/NC1107/slim-m/commit/f91f8089b2a88dba955b37580583d3d77ddcaef3))
* **canvas:** the dock covered the self bubble at a band of widths nobody rendered ([#462](https://github.com/NC1107/slim-m/issues/462)) ([586297a](https://github.com/NC1107/slim-m/commit/586297a2a88dc864a4b9349f0db41fce3da562f5))
* **client:** a stale join could resurrect a call already left, and re-clicking a channel stranded you ([#469](https://github.com/NC1107/slim-m/issues/469)) ([7ee1733](https://github.com/NC1107/slim-m/commit/7ee1733d59e24538012b42052de0620f91a43f78))
* **client:** replace the voice screen's three call boxes with one stage and a filmstrip ([#468](https://github.com/NC1107/slim-m/issues/468)) ([795b220](https://github.com/NC1107/slim-m/commit/795b2207a2f333f5cb4ef9b1980593be666c84ae))

## [0.33.0](https://github.com/NC1107/slim-m/compare/client-v0.32.1...client-v0.33.0) (2026-08-06)


### Features

* **canvas:** one floating dock, so a call keeps its controls while you draw ([#460](https://github.com/NC1107/slim-m/issues/460)) ([978d2e3](https://github.com/NC1107/slim-m/commit/978d2e3bc891586388e3bab49f1855cd97c0b001))


### Bug Fixes

* **canvas:** grab the canvas with the middle button, and make shift-scroll actually pan ([#455](https://github.com/NC1107/slim-m/issues/455)) ([70e46be](https://github.com/NC1107/slim-m/commit/70e46be1ca736d22ad17341e28bdb96db5abd099))
* **canvas:** move your own camera bubble, or hide it ([#459](https://github.com/NC1107/slim-m/issues/459)) ([c407673](https://github.com/NC1107/slim-m/commit/c40767375c78b2c2ff94b169194f004333057a5d))
* **client/app:** let the rail and the pane touch the divider line ([#458](https://github.com/NC1107/slim-m/issues/458)) ([84c2070](https://github.com/NC1107/slim-m/commit/84c207036dc51afaa1526f7cf0263e156bb5c56f))
* **client/app:** select what you just placed, and add a right-click menu per object ([#456](https://github.com/NC1107/slim-m/issues/456)) ([0301151](https://github.com/NC1107/slim-m/commit/0301151ee8d0308b7730c68af27f4273c0b64288))

## [0.32.1](https://github.com/NC1107/slim-m/compare/client-v0.32.0...client-v0.32.1) (2026-08-06)


### Bug Fixes

* **canvas:** a pinch no longer erases whatever the first finger touched ([#449](https://github.com/NC1107/slim-m/issues/449)) ([09ca591](https://github.com/NC1107/slim-m/commit/09ca591528d9e3590c7095c1f59e181279edd07d))
* **canvas:** a way back when you are lost, and the key everybody presses to delete ([#444](https://github.com/NC1107/slim-m/issues/444)) ([6dd195a](https://github.com/NC1107/slim-m/commit/6dd195afd074f93f971b409dbcb66b90f6330c8b))
* **canvas:** cap an in-flight draft, and measure a note in the bytes the wire actually counts ([#438](https://github.com/NC1107/slim-m/issues/438)) ([8279d8f](https://github.com/NC1107/slim-m/commit/8279d8f9aca6abd9b0f4971598fe6ab872f10955))
* **canvas:** look at what the painters actually draw, and fix the three things that were wrong ([#440](https://github.com/NC1107/slim-m/issues/440)) ([58b9d5a](https://github.com/NC1107/slim-m/commit/58b9d5a930f27b8cc7475f91a7fb4958e99604ae))
* **canvas:** two tools were off the edge of the bar at phone width ([#447](https://github.com/NC1107/slim-m/issues/447)) ([6f92037](https://github.com/NC1107/slim-m/commit/6f92037cc474135c8fdc3f5580279bb62f1cb29c))

## [0.32.0](https://github.com/NC1107/slim-m/compare/client-v0.31.1...client-v0.32.0) (2026-08-06)


### Features

* **canvas:** lift an object while it is being moved, and let a stroke be reordered ([#431](https://github.com/NC1107/slim-m/issues/431)) ([4d8ed66](https://github.com/NC1107/slim-m/commit/4d8ed66c1aa2f1b745b1f7e30b457b2c28eb1977))
* **canvas:** the note and shape tools decision 0004 named ([#435](https://github.com/NC1107/slim-m/issues/435)) ([bd532de](https://github.com/NC1107/slim-m/commit/bd532de88f3a9d2416f3f8519614a302f9e15e18))
* **canvas:** watch somebody draw, rather than watching their stroke appear ([#434](https://github.com/NC1107/slim-m/issues/434)) ([5024ab0](https://github.com/NC1107/slim-m/commit/5024ab03f4380777e8513b64d639248aa8532300))

## [0.31.1](https://github.com/NC1107/slim-m/compare/client-v0.31.0...client-v0.31.1) (2026-08-05)


### Bug Fixes

* **canvas:** a visible cursor rim, the product's own font, and the stripe placeholder ([#427](https://github.com/NC1107/slim-m/issues/427)) ([05f24b1](https://github.com/NC1107/slim-m/commit/05f24b16516a1e4ed590c521478e108990656749))
* **canvas:** make the canvas say what it can do ([#422](https://github.com/NC1107/slim-m/issues/422)) ([5095b54](https://github.com/NC1107/slim-m/commit/5095b547f0a535a3978b8e060814967bb5fcd73b))
* **test:** drop two imports the rebase left unused ([#428](https://github.com/NC1107/slim-m/issues/428)) ([98d6c1a](https://github.com/NC1107/slim-m/commit/98d6c1af72e8c2b9d6e56b81e3c8cd5d3d6fe9e7))

## [0.31.0](https://github.com/NC1107/slim-m/compare/client-v0.30.0...client-v0.31.0) (2026-08-05)


### Features

* **canvas:** a text activity log, and proof the canvas really lets go on close ([#417](https://github.com/NC1107/slim-m/issues/417)) ([a4c7034](https://github.com/NC1107/slim-m/commit/a4c7034739a81899dc09e54a8d103a2d0a7d1d5b))
* **canvas:** camera bubbles for a channel's call, positioned in world space ([#413](https://github.com/NC1107/slim-m/issues/413)) ([21ff1f4](https://github.com/NC1107/slim-m/commit/21ff1f42d8bf0efa495c701d4cfb2c156478d8d9))
* **canvas:** resize a placed image, and control what sits on top ([#416](https://github.com/NC1107/slim-m/issues/416)) ([8d388f8](https://github.com/NC1107/slim-m/commit/8d388f88eaff6b1d646e90297f7ded5d885347de))
* **client:** show a call recap on hang-up instead of a bare screen ([#404](https://github.com/NC1107/slim-m/issues/404)) ([1def50d](https://github.com/NC1107/slim-m/commit/1def50deb2d74fc6ea20e4e101c24bc0081e91b1))
* paste an image onto the canvas and drag it around ([#410](https://github.com/NC1107/slim-m/issues/410)) ([b07e263](https://github.com/NC1107/slim-m/commit/b07e2637e7259091ba1b8e65ce01dabe616217a4))


### Bug Fixes

* **client:** stabilise the transcript's paging anchor, and make call video fullscreenable ([#408](https://github.com/NC1107/slim-m/issues/408)) ([4a20df5](https://github.com/NC1107/slim-m/commit/4a20df5a78789b30bbc8858ce48168f516fafcd1))
* **client:** tighten reaction chip spacing to existing tokens ([#414](https://github.com/NC1107/slim-m/issues/414)) ([1fdb007](https://github.com/NC1107/slim-m/commit/1fdb0079dff773942ea72ec0ea379a0228e52418))
* **scripts:** have the seeder vote on the polls it sends ([1fdb007](https://github.com/NC1107/slim-m/commit/1fdb0079dff773942ea72ec0ea379a0228e52418))
* **test:** give the snapshot harness a silent sound player ([#409](https://github.com/NC1107/slim-m/issues/409)) ([7cf12b0](https://github.com/NC1107/slim-m/commit/7cf12b01bfc7c9a83f8b80629ee27d422bb54344))

## [0.30.0](https://github.com/NC1107/slim-m/compare/client-v0.29.1...client-v0.30.0) (2026-08-05)


### Features

* a per-account notification preference, including mentions only ([#397](https://github.com/NC1107/slim-m/issues/397)) ([9c756f8](https://github.com/NC1107/slim-m/commit/9c756f8fb5c003af1792fe8706cbf52e8635f2a5))
* **client:** open a profile from a message author, and fix the poll's selection cue ([#390](https://github.com/NC1107/slim-m/issues/390)) ([0890e00](https://github.com/NC1107/slim-m/commit/0890e00f8e77dd8d2c03dd2897edbbf4ef783c5a))
* **client:** play the notification sounds that have been sitting unused since july ([#394](https://github.com/NC1107/slim-m/issues/394)) ([9d2ebba](https://github.com/NC1107/slim-m/commit/9d2ebba39098648af23b11e6072c26245ed10c1f))
* multi-user canvas cursors, live and ephemeral ([#400](https://github.com/NC1107/slim-m/issues/400)) ([b4f6b8c](https://github.com/NC1107/slim-m/commit/b4f6b8cc75601cc0c88224c01a50e78a6370dcfb))
* Space usage analytics, off by default ([#401](https://github.com/NC1107/slim-m/issues/401)) ([f140ca8](https://github.com/NC1107/slim-m/commit/f140ca8154607fe27c68e4e22d7828d3123660a0))


### Bug Fixes

* **client:** dock the member pane at half-desktop width, and close the rail handle's gap ([#387](https://github.com/NC1107/slim-m/issues/387)) ([b3661d7](https://github.com/NC1107/slim-m/commit/b3661d75f8cf6922f9e69babbcaaa2ec69f11478))
* **client:** drop the newline hint and gate the jump arrow on direction ([#388](https://github.com/NC1107/slim-m/issues/388)) ([fe3759a](https://github.com/NC1107/slim-m/commit/fe3759a3b0ddb129bb6a885329cc0728558ff9e1))
* **client:** tell a missing camera apart from a refused one, and highlight the message under the cursor ([#396](https://github.com/NC1107/slim-m/issues/396)) ([3f762b6](https://github.com/NC1107/slim-m/commit/3f762b6cb82b7d834234f3a4e23ad9a1c18f23e9))
* **scripts:** drive the e2e voice scenarios through direct join, not the removed lobby ([#383](https://github.com/NC1107/slim-m/issues/383)) ([7f8c377](https://github.com/NC1107/slim-m/commit/7f8c3773e8b3b5b8914caf66e89882496211291e))

## [0.29.1](https://github.com/NC1107/slim-m/compare/client-v0.29.0...client-v0.29.1) (2026-08-04)


### Bug Fixes

* **client:** a thread reached by URL showed the parent channel's chrome ([#376](https://github.com/NC1107/slim-m/issues/376)) ([1ced11f](https://github.com/NC1107/slim-m/commit/1ced11f209d66213dbc357964ec2b68449c08338))
* **client:** raise the iOS deployment target to 15.0 ([#380](https://github.com/NC1107/slim-m/issues/380)) ([0c5915e](https://github.com/NC1107/slim-m/commit/0c5915eefa64c9ce7b8c7a04cf0f8d8c8fdaa978))
* **release:** stop client-app from swallowing client's changelog ([#381](https://github.com/NC1107/slim-m/issues/381)) ([42bb983](https://github.com/NC1107/slim-m/commit/42bb98350d7e779f7148e687a7aae0b68fe0e2fc))
* widen the mention charset to match what a username can be ([#374](https://github.com/NC1107/slim-m/issues/374)) ([901e712](https://github.com/NC1107/slim-m/commit/901e712e54788f75a3a066c08a2844c126bf6ad9))

## [0.29.0](https://github.com/NC1107/slim-m/compare/client-v0.28.0...client-v0.29.0) (2026-08-04)


### Bug Fixes

* **client:** camera-refusal diagnostics, an instant call-leave, and one screen-share picker on Linux ([#369](https://github.com/NC1107/slim-m/issues/369)) ([a1f353c](https://github.com/NC1107/slim-m/commit/a1f353cc5fe3b803f74bb654eee1159f67cdca39))
* three left-rail backlog items - toggle over drag, a CHANNELS header, and the app's real version ([#370](https://github.com/NC1107/slim-m/issues/370)) ([2d2044d](https://github.com/NC1107/slim-m/commit/2d2044d933605251f06b46c393f1cdcb737dfcd5))

## [0.28.0](https://github.com/NC1107/slim-m/compare/client-v0.27.0...client-v0.28.0) (2026-08-04)


### Features

* a live in-app signal when a DM call starts or ends ([#358](https://github.com/NC1107/slim-m/issues/358)) ([4f34b57](https://github.com/NC1107/slim-m/commit/4f34b577a86ef69a7238df3160314784723154f2))


### Bug Fixes

* eight findings from the 2026-08-04 multi-agent audit ([#362](https://github.com/NC1107/slim-m/issues/362)) ([2d954d3](https://github.com/NC1107/slim-m/commit/2d954d3453ec156382cdf33df4c822e2081cee71))

## [0.27.0](https://github.com/NC1107/slim-m/compare/client-v0.26.0...client-v0.27.0) (2026-08-04)


### Features

* channel categories you can drag any channel into ([#355](https://github.com/NC1107/slim-m/issues/355)) ([b34cd78](https://github.com/NC1107/slim-m/commit/b34cd786656c10d9b6de150f947642cdb81ceb53))
* **client:** 12/24h clock, reduce-motion override, high contrast, settings cards, header connection status ([#351](https://github.com/NC1107/slim-m/issues/351)) ([91ca790](https://github.com/NC1107/slim-m/commit/91ca7902b458e0663352e1aeb9b70a1679fe3e5e))
* **client:** paste an image on the Linux desktop build, including Ctrl+V ([#353](https://github.com/NC1107/slim-m/issues/353)) ([a5630f4](https://github.com/NC1107/slim-m/commit/a5630f4e18169e724f6e416180b427164b32a4d0))


### Bug Fixes

* **client:** a thread's empty state and its missing header divider ([#356](https://github.com/NC1107/slim-m/issues/356)) ([6775b26](https://github.com/NC1107/slim-m/commit/6775b2663aeaa4cfe44e01bb8fa0c70acb16295d))
* **client:** context menus on member, DM and channel rows, and menu position ([#349](https://github.com/NC1107/slim-m/issues/349)) ([4a87fe6](https://github.com/NC1107/slim-m/commit/4a87fe6fa0c11b1473134c1efcdd2ef6f405c8c8))
* **client:** empty-thread anchoring, the phone header divider, poll layout, and update-note copy ([#346](https://github.com/NC1107/slim-m/issues/346)) ([fae96b4](https://github.com/NC1107/slim-m/commit/fae96b4c2d86797dd4c31d06918de3dd49df3a37))
* **client:** four Linux voice/RTC bugs (device freeze, share dialogs, quality setting) ([#348](https://github.com/NC1107/slim-m/issues/348)) ([f9e6503](https://github.com/NC1107/slim-m/commit/f9e6503090076755046946b4b73eefe414f88d77))
* **client:** name why a message failed to send, and refuse it before it does ([#345](https://github.com/NC1107/slim-m/issues/345)) ([e20e9ab](https://github.com/NC1107/slim-m/commit/e20e9ab922f8eb20889cb1aaff4ffb0fddcf13e8))
* **client:** self camera/screen preview, live camera controls, and direct voice join ([#354](https://github.com/NC1107/slim-m/issues/354)) ([d190a71](https://github.com/NC1107/slim-m/commit/d190a711b67520efc63388f86f1e53a145ac65ca))

## [0.26.0](https://github.com/NC1107/slim-m/compare/client-v0.25.0...client-v0.26.0) (2026-08-03)


### Features

* **client:** a per-channel draft for unsent composer text ([#341](https://github.com/NC1107/slim-m/issues/341)) ([52cc70c](https://github.com/NC1107/slim-m/commit/52cc70c5b53faf80afb051d09cef92eb8023860a))
* **client:** replace the sidebar collapse button with an edge drag handle ([#340](https://github.com/NC1107/slim-m/issues/340)) ([a7655d4](https://github.com/NC1107/slim-m/commit/a7655d4a3e604af1421dc0d45e2fdd8f892983d2))
* **client:** show a picked attachment immediately, with a thumbnail ([#342](https://github.com/NC1107/slim-m/issues/342)) ([b514871](https://github.com/NC1107/slim-m/commit/b514871e2d855f21073168fbaa70efebdb1d84e8))
* **client:** show this build's version in the Space header ([#343](https://github.com/NC1107/slim-m/issues/343)) ([87c8d7a](https://github.com/NC1107/slim-m/commit/87c8d7a6dc0a3502572cb1c65e196dad08be4f1e))


### Bug Fixes

* **client:** a thread carried the channel header stacked under its own bar ([#338](https://github.com/NC1107/slim-m/issues/338)) ([ac8d2fa](https://github.com/NC1107/slim-m/commit/ac8d2fa8b5c2deb923589868c3999bd7f5834ad4))
* **client:** drop the static self-hosted label from the Space header ([#344](https://github.com/NC1107/slim-m/issues/344)) ([95eb34b](https://github.com/NC1107/slim-m/commit/95eb34bd7ebc9cd3e9b28c1529cb26d95a9b5d72))

## [0.25.0](https://github.com/NC1107/slim-m/compare/client-v0.24.3...client-v0.25.0) (2026-08-03)


### Features

* live signal for a thread opening or gaining a reply ([#329](https://github.com/NC1107/slim-m/issues/329)) ([2fe2c9f](https://github.com/NC1107/slim-m/commit/2fe2c9ff3084701575bbacf41c27f27ae81d2e88))

## [0.24.3](https://github.com/NC1107/slim-m/compare/client-v0.24.2...client-v0.24.3) (2026-08-02)


### Bug Fixes

* **client:** make the web build compile again, and gate it in CI ([#324](https://github.com/NC1107/slim-m/issues/324)) ([1c809eb](https://github.com/NC1107/slim-m/commit/1c809eb7d15c3d775137b26a972866972c11c3f7))

## [0.24.2](https://github.com/NC1107/slim-m/compare/client-v0.24.1...client-v0.24.2) (2026-08-02)


### Bug Fixes

* **client:** force the system edit menu's Paste item for a clipboard image ([#319](https://github.com/NC1107/slim-m/issues/319)) ([e62c3a9](https://github.com/NC1107/slim-m/commit/e62c3a9babf6c71bbcb53281c4ca3dd87959fff4))

## [0.24.1](https://github.com/NC1107/slim-m/compare/client-v0.24.0...client-v0.24.1) (2026-08-02)


### Bug Fixes

* **client:** stop the jump arrow appearing on a channel you have not scrolled ([#317](https://github.com/NC1107/slim-m/issues/317)) ([972f557](https://github.com/NC1107/slim-m/commit/972f5576bc75a959f17dc420373cbfecbab156f2))

## [0.24.0](https://github.com/NC1107/slim-m/compare/client-v0.23.0...client-v0.24.0) (2026-08-02)


### Features

* a reply-count affordance on threaded messages ([#315](https://github.com/NC1107/slim-m/issues/315)) ([a5d0524](https://github.com/NC1107/slim-m/commit/a5d05245162cdd5decacde3d487dd13e5053c955))
* threads, a channel with a parent (docs/decisions/0005-threads.md) ([#312](https://github.com/NC1107/slim-m/issues/312)) ([dc5e624](https://github.com/NC1107/slim-m/commit/dc5e624b496c8a4c5cd4d39a0c4758791ac6f61f))

## [0.23.0](https://github.com/NC1107/slim-m/compare/client-v0.22.0...client-v0.23.0) (2026-08-01)


### Features

* calling in a DM ([#306](https://github.com/NC1107/slim-m/issues/306)) ([6823474](https://github.com/NC1107/slim-m/commit/68234746807e080edb7f5e0b0ee4ebb2ecf95115))
* **client:** fade the canvas pane swap and the identity-confirmation push ([#309](https://github.com/NC1107/slim-m/issues/309)) ([34c4715](https://github.com/NC1107/slim-m/commit/34c471539280a65d46efde70fefa356719574347))
* reply to a message, and write up threads instead of building them ([#308](https://github.com/NC1107/slim-m/issues/308)) ([dffcdaa](https://github.com/NC1107/slim-m/commit/dffcdaa1747eae05e61c858c6dcc17380fe990d8))


### Bug Fixes

* **client:** stop reduce motion from crashing AnimatedSize in the rail ([#310](https://github.com/NC1107/slim-m/issues/310)) ([634f2ac](https://github.com/NC1107/slim-m/commit/634f2ac298d79c3a04895eaef47d25f189e920ab))

## [0.22.0](https://github.com/NC1107/slim-m/compare/client-v0.21.3...client-v0.22.0) (2026-08-01)


### Features

* **client:** an actionable report queue ([#304](https://github.com/NC1107/slim-m/issues/304)) ([2733e0d](https://github.com/NC1107/slim-m/commit/2733e0d26ffde640896b72d784b160fc512fbee3))
* **client:** swipe from the left edge to open the channel rail ([#301](https://github.com/NC1107/slim-m/issues/301)) ([ae4a31b](https://github.com/NC1107/slim-m/commit/ae4a31b81b614682bd3b7ae29474e7404582cce1))


### Bug Fixes

* **client:** centre the settings avatar and add a tap-to-change badge ([#303](https://github.com/NC1107/slim-m/issues/303)) ([720f450](https://github.com/NC1107/slim-m/commit/720f450eca98809dcdf3d1ac77f580e0092e7d65))
* **client:** jump button size, reaction spacing, and the member pane not closing ([#302](https://github.com/NC1107/slim-m/issues/302)) ([e7bdf39](https://github.com/NC1107/slim-m/commit/e7bdf39955c64f2dd718f0afaf6d70583eb7d7b2))
* **client:** restore the composer's Paste image fallback on iOS ([#299](https://github.com/NC1107/slim-m/issues/299)) ([74661b1](https://github.com/NC1107/slim-m/commit/74661b1626c8109675767b422721157618de1f48))

## [0.21.3](https://github.com/NC1107/slim-m/compare/client-v0.21.2...client-v0.21.3) (2026-08-01)


### Bug Fixes

* **client:** make saving a message edit reachable on a phone ([#298](https://github.com/NC1107/slim-m/issues/298)) ([a15164e](https://github.com/NC1107/slim-m/commit/a15164e0f22e4fef757e6fdc51b25fba9718a0ed))
* **client:** mobile sheets no longer nest a floating AppMenu card ([#297](https://github.com/NC1107/slim-m/issues/297)) ([f2faae5](https://github.com/NC1107/slim-m/commit/f2faae52deb5d4228936b7609f8831f5ab9c6c24))
* **ios:** stop the paste bridge referencing a class the engine does not export ([#295](https://github.com/NC1107/slim-m/issues/295)) ([c76cc93](https://github.com/NC1107/slim-m/commit/c76cc93340213bf83c441eb771d382ed55f88ab8))

## [0.21.2](https://github.com/NC1107/slim-m/compare/client-v0.21.1...client-v0.21.2) (2026-08-01)


### Bug Fixes

* **client:** paste an image on iOS via the long-press edit menu, prompt-free ([#292](https://github.com/NC1107/slim-m/issues/292)) ([4b07872](https://github.com/NC1107/slim-m/commit/4b07872b086d1012385c5a5f0b0e6ea7016757ff))

## [0.21.1](https://github.com/NC1107/slim-m/compare/client-v0.21.0...client-v0.21.1) (2026-08-01)


### Bug Fixes

* **client:** center the composer hint and add a Material to the image viewer ([#291](https://github.com/NC1107/slim-m/issues/291)) ([2cd1e8b](https://github.com/NC1107/slim-m/commit/2cd1e8b85a91dd5ce39268dfebc3a8b0f99920bd))
* reconcile a display name across already-cached messages ([#288](https://github.com/NC1107/slim-m/issues/288)) ([7ed4906](https://github.com/NC1107/slim-m/commit/7ed4906fd6aa4e3c0c4cda81f1a315e2917ce2b1))

## [0.21.0](https://github.com/NC1107/slim-m/compare/client-v0.20.2...client-v0.21.0) (2026-08-01)


### Features

* **client:** paste an image into the composer on iPhone and Android ([#286](https://github.com/NC1107/slim-m/issues/286)) ([55e97e3](https://github.com/NC1107/slim-m/commit/55e97e308744048d2fbc671d3e2f2c72b9831431))


### Bug Fixes

* **client:** let the composer's attach button reach the photo library ([#284](https://github.com/NC1107/slim-m/issues/284)) ([10363d1](https://github.com/NC1107/slim-m/commit/10363d1dc6acd527eee79b14461c25212e3233ca))

## [0.20.2](https://github.com/NC1107/slim-m/compare/client-v0.20.1...client-v0.20.2) (2026-08-01)


### Bug Fixes

* **client:** a blocked DM says so and offers Unblock ([#282](https://github.com/NC1107/slim-m/issues/282)) ([244c47d](https://github.com/NC1107/slim-m/commit/244c47d9e938814f32f7869c690bbcb2e2a1a72b))

## [0.20.1](https://github.com/NC1107/slim-m/compare/client-v0.20.0...client-v0.20.1) (2026-08-01)


### Bug Fixes

* **client:** a day divider flashes when a send races the first catch-up ([#278](https://github.com/NC1107/slim-m/issues/278)) ([345d41a](https://github.com/NC1107/slim-m/commit/345d41aa4c0cfafcfee9a57a9d77c535e6cdbeb7))

## [0.20.0](https://github.com/NC1107/slim-m/compare/client-v0.19.0...client-v0.20.0) (2026-08-01)


### Features

* **client:** jump to message from search, pins and the command palette ([#273](https://github.com/NC1107/slim-m/issues/273)) ([72f1a36](https://github.com/NC1107/slim-m/commit/72f1a36de0c12243a38a41f8e7d931f5780ba21d))
* drag to reorder channels, ordered deployment-wide ([#271](https://github.com/NC1107/slim-m/issues/271)) ([753b3d4](https://github.com/NC1107/slim-m/commit/753b3d4521908186ffe811dda712993fe20ed1aa))

## [0.19.0](https://github.com/NC1107/slim-m/compare/client-v0.18.0...client-v0.19.0) (2026-08-01)


### Features

* **client:** markdown formatting, lists and spoilers in messages ([#267](https://github.com/NC1107/slim-m/issues/267)) ([531d133](https://github.com/NC1107/slim-m/commit/531d1332ee06450fbfeb69e5b7a561ae733a625f))

## [0.18.0](https://github.com/NC1107/slim-m/compare/client-v0.17.2...client-v0.18.0) (2026-08-01)


### Features

* **client:** device-use polish, a what's-new screen, and a dead-code sweep ([#256](https://github.com/NC1107/slim-m/issues/256)) ([cd927ac](https://github.com/NC1107/slim-m/commit/cd927ac993bdaca37a5ccc31041e6f44009f46cd))


### Bug Fixes

* **client:** give 0.18.0 its own what's-new entry ([#259](https://github.com/NC1107/slim-m/issues/259)) ([9f9d478](https://github.com/NC1107/slim-m/commit/9f9d47853c7fc017b0c34c3c84a6b788fc003dbc))

## [0.17.2](https://github.com/NC1107/slim-m/compare/client-v0.17.1...client-v0.17.2) (2026-08-01)


### Bug Fixes

* **client:** a message you sent never raises the unread divider ([#255](https://github.com/NC1107/slim-m/issues/255)) ([13f5278](https://github.com/NC1107/slim-m/commit/13f52780d3a43a9f2522b842e6750569571e2f2a))
* **client:** hover actions overlay the message row instead of resizing it ([#251](https://github.com/NC1107/slim-m/issues/251)) ([3807840](https://github.com/NC1107/slim-m/commit/38078409b66f49599a402263bb6f40c752a5d37e))
* **client:** stop two channels overlaying during a switch, and cap inline images ([#253](https://github.com/NC1107/slim-m/issues/253)) ([d9d7854](https://github.com/NC1107/slim-m/commit/d9d7854d854bfcfcb6221d92b7adc236c0d4f512))

## [0.17.1](https://github.com/NC1107/slim-m/compare/client-v0.17.0...client-v0.17.1) (2026-07-31)


### Bug Fixes

* **client:** shorten the direct messages empty state ([#243](https://github.com/NC1107/slim-m/issues/243)) ([bc2fdb5](https://github.com/NC1107/slim-m/commit/bc2fdb5aac9138f03524df98a3290c30393208bb))

## [0.17.0](https://github.com/NC1107/slim-m/compare/client-v0.16.0...client-v0.17.0) (2026-07-31)


### Features

* **client:** an op cursor and the message-op wire model ([#236](https://github.com/NC1107/slim-m/issues/236)) ([7ecdcde](https://github.com/NC1107/slim-m/commit/7ecdcdebd3d0932efb2d45c40580d1177c0869b0))
* **client:** apply message ops, closing the reconciliation debt ([#238](https://github.com/NC1107/slim-m/issues/238)) ([fad73a2](https://github.com/NC1107/slim-m/commit/fad73a211beec7d34fbda6d8d573e773a1f8c1ab))
* **client:** eject from a call, rename yourself, a camera pre-toggle, and CallKit for UI-joined calls ([#231](https://github.com/NC1107/slim-m/issues/231)) ([33c0fec](https://github.com/NC1107/slim-m/commit/33c0fec3df35711867e98a70a379f0c563dab8d8))


### Bug Fixes

* **client:** the pin action matches its neighbours and drops the counter ([#242](https://github.com/NC1107/slim-m/issues/242)) ([7a88b91](https://github.com/NC1107/slim-m/commit/7a88b9144045a51639392617d728715f0215444a))
* take manual control of iOS screen share publication ([#227](https://github.com/NC1107/slim-m/issues/227)) ([9257ede](https://github.com/NC1107/slim-m/commit/9257edec8b448b8f15d5fe0199b8b121cdc18084))

## [0.16.0](https://github.com/NC1107/slim-m/compare/client-v0.15.0...client-v0.16.0) (2026-07-31)


### Features

* **client:** canvas eraser, undo and clear controls ([#223](https://github.com/NC1107/slim-m/issues/223)) ([5869f9e](https://github.com/NC1107/slim-m/commit/5869f9e0301b14104d723a1d0f87a258d0eecd49))


### Bug Fixes

* a restore frame with no ids must ask the feed, not be applied as empty ([#225](https://github.com/NC1107/slim-m/issues/225)) ([d97f41f](https://github.com/NC1107/slim-m/commit/d97f41f64d3ce215e1062bd430d9d187aded0eab))

## [0.15.0](https://github.com/NC1107/slim-m/compare/client-v0.14.0...client-v0.15.0) (2026-07-31)


### Features

* **client:** canvas op-stream reconciliation, no UI wired yet ([#222](https://github.com/NC1107/slim-m/issues/222)) ([8669a4c](https://github.com/NC1107/slim-m/commit/8669a4cf253f1ea4567c1d4fbed7b75dc904b832))
* **voice_canvas:** grid removal, document tombstones, and an eraser hit test ([#217](https://github.com/NC1107/slim-m/issues/217)) ([eb63da0](https://github.com/NC1107/slim-m/commit/eb63da0ef9c959085fb7c07cf1b6cf2c85cc9265))


### Bug Fixes

* a relaunched client no longer shows itself as still on a call ([#205](https://github.com/NC1107/slim-m/issues/205)) ([2aa141d](https://github.com/NC1107/slim-m/commit/2aa141dafc3861be4cdae859a5c95237fdb8bde7))
* **ci:** stop latest from rolling backwards, lock two more builds, and make the e2e checks honest ([#206](https://github.com/NC1107/slim-m/issues/206)) ([97a61af](https://github.com/NC1107/slim-m/commit/97a61af055970e173862441dcb7f6779a623fe11))
* close five session and store lifecycle gaps ([#211](https://github.com/NC1107/slim-m/issues/211)) ([9736c8b](https://github.com/NC1107/slim-m/commit/9736c8b96bb67be15282362342806bd52f76ad58))
* confirm channel overwrites, bind the shortcut table, and explain a blocked DM ([#213](https://github.com/NC1107/slim-m/issues/213)) ([5aad293](https://github.com/NC1107/slim-m/commit/5aad293f9c84a9a181a1c3356043bf15f3659d08))

## [0.14.0](https://github.com/NC1107/slim-m/compare/client-v0.13.3...client-v0.14.0) (2026-07-31)


### Features

* a personal space, opened by DMing yourself ([#204](https://github.com/NC1107/slim-m/issues/204)) ([951d1b3](https://github.com/NC1107/slim-m/commit/951d1b341ebc3e7c1985211407ec05e9ce44e1f1))


### Bug Fixes

* canvas safe area and the two stacked call docks on phone ([#203](https://github.com/NC1107/slim-m/issues/203)) ([1100e65](https://github.com/NC1107/slim-m/commit/1100e65c4a51cdf2f96aca458a2a1f180f5e1b52))
* scale the draft stroke's width by the live camera zoom ([#207](https://github.com/NC1107/slim-m/issues/207)) ([b34938d](https://github.com/NC1107/slim-m/commit/b34938dc197d2e0ddf44f72ab633e4c234f22e55))

## [0.13.3](https://github.com/NC1107/slim-m/compare/client-v0.13.2...client-v0.13.3) (2026-07-30)


### Bug Fixes

* **canvas:** a web z-index truncation, an unbounded refetch loop, and stacked headers ([#198](https://github.com/NC1107/slim-m/issues/198)) ([5875cc4](https://github.com/NC1107/slim-m/commit/5875cc4d57e999dc5b9364204c829d2139a2be6d))
* **client:** follow the read marker to where the user actually is ([#189](https://github.com/NC1107/slim-m/issues/189)) ([7533ed9](https://github.com/NC1107/slim-m/commit/7533ed9b1868320c93d9c057d800e31988057535))
* **client:** give per-message context actions a keyboard route ([#195](https://github.com/NC1107/slim-m/issues/195)) ([bab2b2e](https://github.com/NC1107/slim-m/commit/bab2b2e80109ea8970f0afca2e2339eb652d5dcd))
* **client:** name devices by platform and host, and validate invite uses ([#192](https://github.com/NC1107/slim-m/issues/192)) ([c42ca1b](https://github.com/NC1107/slim-m/commit/c42ca1b794b0c24af0209bf594c54d5ce742a4f6))
* **client:** page channel history and stop claiming the start of it ([#197](https://github.com/NC1107/slim-m/issues/197)) ([e471acd](https://github.com/NC1107/slim-m/commit/e471acda86b9633afca19302f29e06e6a5f4bb17))
* **client:** restore presence on refusal and cap image decode size ([#193](https://github.com/NC1107/slim-m/issues/193)) ([cb32f34](https://github.com/NC1107/slim-m/commit/cb32f34831b3c4aa032707031a282cc73eb3590d))
* **client:** show the connection bar on phone and gate role assignment by permission ([#190](https://github.com/NC1107/slim-m/issues/190)) ([ab9d418](https://github.com/NC1107/slim-m/commit/ab9d41855de4e4bf31382204fc2d7dccf24e64c2))

## [0.13.2](https://github.com/NC1107/slim-m/compare/client-v0.13.1...client-v0.13.2) (2026-07-30)


### Bug Fixes

* **api:** give wire enums a tolerant parse instead of values.byName ([#185](https://github.com/NC1107/slim-m/issues/185)) ([aaedfee](https://github.com/NC1107/slim-m/commit/aaedfee9d711d53d74cd729d6e7df09a4a303eb0))

## [0.13.1](https://github.com/NC1107/slim-m/compare/client-v0.13.0...client-v0.13.1) (2026-07-30)


### Bug Fixes

* **client:** make five admin/onboarding screens say what is true ([#175](https://github.com/NC1107/slim-m/issues/175)) ([03ac7c9](https://github.com/NC1107/slim-m/commit/03ac7c997f91aaf24d79fbcf95351316d5ab1fc2))
* **client:** page the member roster instead of truncating at 50 ([#181](https://github.com/NC1107/slim-m/issues/181)) ([33a99b4](https://github.com/NC1107/slim-m/commit/33a99b4b7164b32d6e57df9d269d29e5404d3076))

## [0.13.0](https://github.com/NC1107/slim-m/compare/client-v0.12.0...client-v0.13.0) (2026-07-30)


### Features

* **client:** a real collapsed call strip in the rail ([#143](https://github.com/NC1107/slim-m/issues/143)) ([b51c7b6](https://github.com/NC1107/slim-m/commit/b51c7b63dac6d6d380f94d1661721636445c4633))
* **client:** inline autocomplete for emoji, mentions and slash commands ([#139](https://github.com/NC1107/slim-m/issues/139)) ([c3d8117](https://github.com/NC1107/slim-m/commit/c3d81177e22e13b32e1865707351531adaf35d3d))
* **client:** onboarding as an installer, not a card ([#140](https://github.com/NC1107/slim-m/issues/140)) ([009767c](https://github.com/NC1107/slim-m/commit/009767cfdb4e60d91ab04fe9951057e2254e17f4))
* **client:** settings as a nav beside a pane ([#142](https://github.com/NC1107/slim-m/issues/142)) ([df0a8ca](https://github.com/NC1107/slim-m/commit/df0a8caec75062386ffec6641260e6b8fa037252))


### Bug Fixes

* **api:** encode request path segments at the transport choke point ([#153](https://github.com/NC1107/slim-m/issues/153)) ([98564eb](https://github.com/NC1107/slim-m/commit/98564eb2900adfed9a1bd6cd6194c140bb14b9e4))
* bound the two reads that answered with everything ([#148](https://github.com/NC1107/slim-m/issues/148)) ([eb352cd](https://github.com/NC1107/slim-m/commit/eb352cd26a3c2578c14b0d9685442650b0f28f5d))
* **client:** bind the identity check to connecting, and the https rule to ([#155](https://github.com/NC1107/slim-m/issues/155)) ([baf7715](https://github.com/NC1107/slim-m/commit/baf7715d68004d114552050a45ce9eb01a12c2f9))
* **client:** give the snapshot gate real data, real breakpoints and the real app wrapper ([#166](https://github.com/NC1107/slim-m/issues/166)) ([eed75b5](https://github.com/NC1107/slim-m/commit/eed75b5982e10edb640b86b83342bcf61cf25465))
* **client:** hold a handle that outlives the surface before dismissing it ([#159](https://github.com/NC1107/slim-m/issues/159)) ([c352333](https://github.com/NC1107/slim-m/commit/c35233301ee6efbc438b5d82b8bd27a2f706ce93))
* **client:** lint the six unlinted packages, and stop inverting 401 and 403 ([#160](https://github.com/NC1107/slim-m/issues/160)) ([147006e](https://github.com/NC1107/slim-m/commit/147006ebdc99ea90714a76bc1454f37928b07c5a))
* **client:** refuse a plaintext SFU address off a public deployment ([#152](https://github.com/NC1107/slim-m/issues/152)) ([6a27782](https://github.com/NC1107/slim-m/commit/6a27782794a99ea734ba555712a67f83d5073af0))
* **client:** stop rendering raw transport strings, and route failures through one description ([#167](https://github.com/NC1107/slim-m/issues/167)) ([8ae34cd](https://github.com/NC1107/slim-m/commit/8ae34cd4d551ab9a40fc3b004f01690237b9bbe6))
* **client:** window the newest messages, and sort a pending send last ([#154](https://github.com/NC1107/slim-m/issues/154)) ([4ba1795](https://github.com/NC1107/slim-m/commit/4ba1795fd5441aa287abaa73fa7e7c5a02da8da0))
* **design:** pin primary, and give ListTile and inputs the text tokens ([#162](https://github.com/NC1107/slim-m/issues/162)) ([e6bd135](https://github.com/NC1107/slim-m/commit/e6bd1356bbd774d2ce53af4be99eac516a93b0a9))
* make blocking actually hide what it says it hides ([#147](https://github.com/NC1107/slim-m/issues/147)) ([7cf0618](https://github.com/NC1107/slim-m/commit/7cf0618b2f5b1ee4cda59b2df62a0c01611a1338))
* name the subject of a report before asking to close it ([#157](https://github.com/NC1107/slim-m/issues/157)) ([4546722](https://github.com/NC1107/slim-m/commit/45467221e564cf122e3dc8a90ce4f1852e92f27f))
* **rtc:** give captureOptionsFor a platform seam, test both directions ([#172](https://github.com/NC1107/slim-m/issues/172)) ([53b13d4](https://github.com/NC1107/slim-m/commit/53b13d41260648225891f98646774611eda139b4))
* **server:** publish the role, overwrite and channel events nothing published ([#161](https://github.com/NC1107/slim-m/issues/161)) ([bef83ee](https://github.com/NC1107/slim-m/commit/bef83ee1411fd6e97f365f8d688878a2ecf28b97))

## [0.12.0](https://github.com/NC1107/slim-m/compare/client-v0.11.0...client-v0.12.0) (2026-07-29)


### Features

* **client:** per-participant volume, roles, timeout and removal in the member profile ([#138](https://github.com/NC1107/slim-m/issues/138)) ([e746bcd](https://github.com/NC1107/slim-m/commit/e746bcd4c89e1dcd507d49c43ea345d6ea4d83d5))
* **client:** the member profile popover ([#134](https://github.com/NC1107/slim-m/issues/134)) ([4ef62de](https://github.com/NC1107/slim-m/commit/4ef62de3417e6644c5db7501a2f0dc00194614a1))

## [0.11.0](https://github.com/NC1107/slim-m/compare/client-v0.10.1...client-v0.11.0) (2026-07-29)


### Features

* **client:** implement the motion and feedback spec ([#131](https://github.com/NC1107/slim-m/issues/131)) ([4bdc7f0](https://github.com/NC1107/slim-m/commit/4bdc7f02fd1011f6e6f079f564933a06273fd4f3))
* **client:** move raw Material widgets onto the design system ([#129](https://github.com/NC1107/slim-m/issues/129)) ([8136440](https://github.com/NC1107/slim-m/commit/8136440c094fee84610fb21226e44f3474db8f43))
* **client:** the error-states grammar, and the component-audit fixes it converged with ([#132](https://github.com/NC1107/slim-m/issues/132)) ([f2b78f5](https://github.com/NC1107/slim-m/commit/f2b78f5ba2a9c578111b477aa6987f3aa15b4388))

## [0.10.1](https://github.com/NC1107/slim-m/compare/client-v0.10.0...client-v0.10.1) (2026-07-29)


### Bug Fixes

* **client:** the full-screen audit round - settings, admin, entry, and the reading cap ([#126](https://github.com/NC1107/slim-m/issues/126)) ([9d30771](https://github.com/NC1107/slim-m/commit/9d30771a30e06c6819031cc6b268e74cf562bcb0))

## [0.10.0](https://github.com/NC1107/slim-m/compare/client-v0.9.0...client-v0.10.0) (2026-07-29)


### Features

* render peer screen shares, call tiles, and the nine-specialist audit batch ([#123](https://github.com/NC1107/slim-m/issues/123)) ([b34be33](https://github.com/NC1107/slim-m/commit/b34be33bc6b87f68995479f39a440e841cf18170))

## [0.9.0](https://github.com/NC1107/slim-m/compare/client-v0.8.1...client-v0.9.0) (2026-07-29)


### Features

* **client:** motion, haptics, day dividers, and an ios screen-share fix ([#121](https://github.com/NC1107/slim-m/issues/121)) ([ca1669b](https://github.com/NC1107/slim-m/commit/ca1669b3794c05f95a633c494dedbf3680ca83b8))

## [0.8.1](https://github.com/NC1107/slim-m/compare/client-v0.8.0...client-v0.8.1) (2026-07-29)


### Bug Fixes

* close 16 defects a multi-agent audit found, moderation-queue holes first ([#118](https://github.com/NC1107/slim-m/issues/118)) ([b4eab36](https://github.com/NC1107/slim-m/commit/b4eab36e4e0b2b35a180542fe987225677fd82d7))

## [0.8.0](https://github.com/NC1107/slim-m/compare/client-v0.7.0...client-v0.8.0) (2026-07-29)


### Features

* **client:** split personal and Space settings into separate screens ([#109](https://github.com/NC1107/slim-m/issues/109)) ([54357c3](https://github.com/NC1107/slim-m/commit/54357c3b6788438fbe0200779f6be52388356919))


### Bug Fixes

* **client:** make the channel rail reachable to a screen reader ([#112](https://github.com/NC1107/slim-m/issues/112)) ([c5380f3](https://github.com/NC1107/slim-m/commit/c5380f395b76053a45d61f912ddd67bcf4683056))
* **client:** open the document picker for a custom emoji, not just photos ([#108](https://github.com/NC1107/slim-m/issues/108)) ([a76d4bc](https://github.com/NC1107/slim-m/commit/a76d4bc6ed518d761ceec28d49c157730cfa15a7))
* **client:** stop presenting a desktop window as a phone ([#116](https://github.com/NC1107/slim-m/issues/116)) ([573713f](https://github.com/NC1107/slim-m/commit/573713fafc1dff6fbf6f8a5c986c64f6c8ee4d49))
* **ui:** tighten chat density and show a live screen share indicator ([#110](https://github.com/NC1107/slim-m/issues/110)) ([87a9bec](https://github.com/NC1107/slim-m/commit/87a9bec4673f390b555e0b952341a4bf33eeec4c))

## [0.7.0](https://github.com/NC1107/slim-m/compare/client-v0.6.0...client-v0.7.0) (2026-07-28)


### Features

* add a per-channel voice roster so the rail shows who is already there ([#98](https://github.com/NC1107/slim-m/issues/98)) ([06d13d7](https://github.com/NC1107/slim-m/commit/06d13d7b3c96cc5b137a8131fd1da870cc4785b6))
* **android:** give an incoming call a real notification ([#95](https://github.com/NC1107/slim-m/issues/95)) ([e096f12](https://github.com/NC1107/slim-m/commit/e096f129a23b2ac683ff5420a620cd4cbf0a6e7c))
* **client:** surface the device media capability probe in voice settings ([#93](https://github.com/NC1107/slim-m/issues/93)) ([da84b30](https://github.com/NC1107/slim-m/commit/da84b3002f2f2fc6262bd344f29f24bca4d94fb4))


### Bug Fixes

* **ios:** the broadcast extension must embed no frameworks ([#92](https://github.com/NC1107/slim-m/issues/92)) ([949af6b](https://github.com/NC1107/slim-m/commit/949af6be9245aa6cada04dc9e444705625ec9317))
* **ui:** centre every list row's content, and give the pane one gutter ([#99](https://github.com/NC1107/slim-m/issues/99)) ([663d56d](https://github.com/NC1107/slim-m/commit/663d56d361057d24a20f5a7ea6d07d308bfaa0fb))

## [0.6.0](https://github.com/NC1107/slim-m/compare/client-v0.5.1...client-v0.6.0) (2026-07-28)


### Features

* **ios:** land the broadcast upload extension, now that its portal objects exist ([#90](https://github.com/NC1107/slim-m/issues/90)) ([eecf501](https://github.com/NC1107/slim-m/commit/eecf501fb4d08d04952b12f372f1530738792863))
* role-granting invites, a disabled segmented option, and a backlog that was mostly stale ([#87](https://github.com/NC1107/slim-m/issues/87)) ([25b10fb](https://github.com/NC1107/slim-m/commit/25b10fb671e26ecfe5e8d62daa5f1aeafae832a3))

## [0.5.1](https://github.com/NC1107/slim-m/compare/client-v0.5.0...client-v0.5.1) (2026-07-28)


### Bug Fixes

* desktop screen share, colour emoji, rail alignment, and who can join ([#81](https://github.com/NC1107/slim-m/issues/81)) ([4dd1bb1](https://github.com/NC1107/slim-m/commit/4dd1bb13090f2056952743ea397073df4bdb5ba3))

## [0.5.0](https://github.com/NC1107/slim-m/compare/client-v0.4.0...client-v0.5.0) (2026-07-28)


### Features

* **brand:** the off-grid mark, everywhere an icon lives ([#80](https://github.com/NC1107/slim-m/issues/80)) ([40f68ba](https://github.com/NC1107/slim-m/commit/40f68ba6627d4b3d6e0d9027bda59751be713b23))


### Bug Fixes

* **mobile:** image-only sends, fullscreen media, Fedora packaging, and Space naming ([#77](https://github.com/NC1107/slim-m/issues/77)) ([cbf89d4](https://github.com/NC1107/slim-m/commit/cbf89d494fb80e7f14a01677237358eda5c9bbe2))

## [0.4.0](https://github.com/NC1107/slim-m/compare/client-v0.3.0...client-v0.4.0) (2026-07-27)


### Features

* **client:** custom emoji end to end ([#76](https://github.com/NC1107/slim-m/issues/76)) ([c39d953](https://github.com/NC1107/slim-m/commit/c39d9538a247cf49b4af92bbc77a67f6c8cc9acc))


### Bug Fixes

* **mobile:** reaction layout, avatar cropping, and reclaimed space ([#71](https://github.com/NC1107/slim-m/issues/71)) ([b059134](https://github.com/NC1107/slim-m/commit/b059134bd3ae87ccf0cb9ccb0957d20ef00858fc))

## [0.3.0](https://github.com/NC1107/slim-m/compare/client-v0.2.3...client-v0.3.0) (2026-07-27)


### Features

* CORS, moderation and admin UI, message actions, and a web build ([#61](https://github.com/NC1107/slim-m/issues/61)) ([dca58e6](https://github.com/NC1107/slim-m/commit/dca58e690dc66ee5c049e60513982452e042f65e))
* **design:** adopt glacier cyan as the accent ([#66](https://github.com/NC1107/slim-m/issues/66)) ([3613c06](https://github.com/NC1107/slim-m/commit/3613c068190fbc7942ef6b03811a6ace5b30a89c))


### Bug Fixes

* **mobile:** make the client usable on a phone ([#68](https://github.com/NC1107/slim-m/issues/68)) ([56e3ce7](https://github.com/NC1107/slim-m/commit/56e3ce7cfe0f539244fb3d0ac893095d2416bddd))
* router recovery, file_picker 12, and the iOS location purpose string ([#67](https://github.com/NC1107/slim-m/issues/67)) ([91a4258](https://github.com/NC1107/slim-m/commit/91a42580d7b1152e74b7d4110e47f94fd4e0ae0e))
