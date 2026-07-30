# Changelog

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
