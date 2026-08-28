# Changelog

## [0.58.1](https://github.com/NC1107/slim-m/compare/client-v0.58.0...client-v0.58.1) (2026-08-28)


### Bug Fixes

* **client:** bound the custom emoji list to a lazy view ([#942](https://github.com/NC1107/slim-m/issues/942)) ([7cfba24](https://github.com/NC1107/slim-m/commit/7cfba243166651fc99794c6853da1a4a7ce63a33))
* **client:** keep report card mentions highlighted when members refetch fails ([#946](https://github.com/NC1107/slim-m/issues/946)) ([c843601](https://github.com/NC1107/slim-m/commit/c84360134cc23bb53d35736f8f2b132d386fbaeb))
* **client:** retry a rate-limited emoji image fetch instead of caching it broken ([#945](https://github.com/NC1107/slim-m/issues/945)) ([02b2fef](https://github.com/NC1107/slim-m/commit/02b2fefa2f98233be2a00a5b4dd407c2cca83816))
* **client:** stop the desktop splash size from being saved as the window geometry ([#943](https://github.com/NC1107/slim-m/issues/943)) ([1767091](https://github.com/NC1107/slim-m/commit/1767091c9a15d2442fae08047e4f4adf95c0778f))

## [0.58.0](https://github.com/NC1107/slim-m/compare/client-v0.57.0...client-v0.58.0) (2026-08-27)


### Features

* **client:** clear status with an inline x, fix stale member row ([#927](https://github.com/NC1107/slim-m/issues/927)) ([383a5ed](https://github.com/NC1107/slim-m/commit/383a5ed0a50a4536d10589ec98a1f1c94d3ae93f))
* **client:** drag and drop files onto the composer and the emoji import card ([#931](https://github.com/NC1107/slim-m/issues/931)) ([f82dae3](https://github.com/NC1107/slim-m/commit/f82dae3d31a96eede5716e5adf567f12e1688e52))
* **client:** enable strict analyzer flags across the workspace ([#921](https://github.com/NC1107/slim-m/issues/921)) ([1f04422](https://github.com/NC1107/slim-m/commit/1f04422c33c125f4b37cbf78e39b47600706b112))
* **client:** make the desktop splash a real small window ([#934](https://github.com/NC1107/slim-m/issues/934)) ([79b672d](https://github.com/NC1107/slim-m/commit/79b672d1d74ae56d366c3c8bda83460ec5f57e36))
* **client:** split a Space performance section out of Analytics ([#930](https://github.com/NC1107/slim-m/issues/930)) ([30e77d2](https://github.com/NC1107/slim-m/commit/30e77d2afb17380bb9749a56edf3af278c008cef))
* **server:** bulk-add custom emoji in one rate-limit charge ([#932](https://github.com/NC1107/slim-m/issues/932)) ([8243bac](https://github.com/NC1107/slim-m/commit/8243bacb1b92d62f55eb18a24f16b617433ea9e0))
* **server:** bulk-delete a raider's recent messages by author and window ([#922](https://github.com/NC1107/slim-m/issues/922)) ([1b9ee57](https://github.com/NC1107/slim-m/commit/1b9ee57893aeb60f5dcd828b2280f86b51d73728))
* **server:** let a reporter check their own report's status ([#923](https://github.com/NC1107/slim-m/issues/923)) ([5ebae4d](https://github.com/NC1107/slim-m/commit/5ebae4d74ba5f95ebdf2d5cc6634aa0869c0819c))


### Bug Fixes

* **client:** add a right-click menu to canvas presence tiles ([#938](https://github.com/NC1107/slim-m/issues/938)) ([be0271c](https://github.com/NC1107/slim-m/commit/be0271cfed73e6b7a0c0d96e0fd0eb957024f971))
* **client:** add hand-rolled edge/corner resize to the frameless Linux window ([#939](https://github.com/NC1107/slim-m/issues/939)) ([cf55e6c](https://github.com/NC1107/slim-m/commit/cf55e6c9e104cef8e128dfc77f8a80394dd27da3))
* **client:** compose the desktop startup screen instead of shrinking the window ([#926](https://github.com/NC1107/slim-m/issues/926)) ([3b40eda](https://github.com/NC1107/slim-m/commit/3b40eda574d4f543ae96f30c326671e8da1883c2))
* **client:** stop a Linux MissingPluginException from skipping the tray menu build ([#928](https://github.com/NC1107/slim-m/issues/928)) ([ff1fa12](https://github.com/NC1107/slim-m/commit/ff1fa123f1396ee22431621cbe73752a8cc0d84f))
* **client:** stop faux-bolding avatar initials text ([#929](https://github.com/NC1107/slim-m/issues/929)) ([3a4c2ad](https://github.com/NC1107/slim-m/commit/3a4c2ad9a5a9e29e863f610935f9fd9787132ccb))
* **client:** stop mipmap blur on photo avatars, keep the low path ([#935](https://github.com/NC1107/slim-m/issues/935)) ([dcf300a](https://github.com/NC1107/slim-m/commit/dcf300ac54d0c5a1a7691b16fb4fc4335fb08778))
* **client:** stop pinned/threads sheets relaying out the whole backlog ([#936](https://github.com/NC1107/slim-m/issues/936)) ([7b239b8](https://github.com/NC1107/slim-m/commit/7b239b8994b7e2d2e4c32dd951f2b49f739cfdf9))

## [0.57.0](https://github.com/NC1107/slim-m/compare/client-v0.56.0...client-v0.57.0) (2026-08-27)


### Features

* **client:** double the desktop splash floor to 560ms ([#913](https://github.com/NC1107/slim-m/issues/913)) ([1976939](https://github.com/NC1107/slim-m/commit/197693991136ebedc5c7036a6c656704b47fe526))
* **client:** finish three motion gaps and share the call-duration split ([#918](https://github.com/NC1107/slim-m/issues/918)) ([61c882d](https://github.com/NC1107/slim-m/commit/61c882d080289467983be5fdf6430c03f6177cac))
* **client:** trim Channel settings copy and rename Topic to Description ([#914](https://github.com/NC1107/slim-m/issues/914)) ([afc0c8d](https://github.com/NC1107/slim-m/commit/afc0c8dc7e10f5ff6ce6f16157eae4325384da97))


### Bug Fixes

* **client:** gate bulk-select entry on MANAGE_MESSAGES, not canDeleteMessage ([#916](https://github.com/NC1107/slim-m/issues/916)) ([9738ef8](https://github.com/NC1107/slim-m/commit/9738ef83b624e5667d652cc690972c7f16a3d844))

## [0.56.0](https://github.com/NC1107/slim-m/compare/client-v0.55.0...client-v0.56.0) (2026-08-27)


### Features

* **client:** make design_system golden diffing real in CI ([#908](https://github.com/NC1107/slim-m/issues/908)) ([9d75d7e](https://github.com/NC1107/slim-m/commit/9d75d7e88e69f35f350799b077c2528000ce5888))


### Performance Improvements

* **client:** use scoped MediaQuery accessors for keyboard avoidance ([#909](https://github.com/NC1107/slim-m/issues/909)) ([66bdbfc](https://github.com/NC1107/slim-m/commit/66bdbfc6f6cf2a467e564846cff796a0706cb080))

## [0.55.0](https://github.com/NC1107/slim-m/compare/client-v0.54.1...client-v0.55.0) (2026-08-27)


### Features

* **client:** clear status in one click, edit inline on desktop ([#903](https://github.com/NC1107/slim-m/issues/903)) ([884903c](https://github.com/NC1107/slim-m/commit/884903c94ee88d9f6415b8bd9078598c0f007d5d))
* **client:** give the desktop startup screen a minimum visible duration ([#901](https://github.com/NC1107/slim-m/issues/901)) ([559457c](https://github.com/NC1107/slim-m/commit/559457c3179051c0cf56653c6e6a1e487d46b77b))


### Bug Fixes

* **client:** stop a hang-up made while the canvas is open from rejoining the call ([#902](https://github.com/NC1107/slim-m/issues/902)) ([624bdb3](https://github.com/NC1107/slim-m/commit/624bdb3b4472517975f29ab4adbc2a66417222ba))

## [0.54.1](https://github.com/NC1107/slim-m/compare/client-v0.54.0...client-v0.54.1) (2026-08-26)


### Bug Fixes

* **client:** add value equality to UserProfile ([#893](https://github.com/NC1107/slim-m/issues/893)) ([65a5914](https://github.com/NC1107/slim-m/commit/65a59146775d8ae236078882e40eabdb76b47d0f))
* **client:** guard four unhandled-future races in desktop/composer/rtc/sign-in ([#896](https://github.com/NC1107/slim-m/issues/896)) ([494d821](https://github.com/NC1107/slim-m/commit/494d8215a2766e1ec15a95d6cacfa559d76a60fd))

## [0.54.0](https://github.com/NC1107/slim-m/compare/client-v0.53.0...client-v0.54.0) (2026-08-26)


### Features

* **client:** skip the sign-in toggle for a first official-space join ([#885](https://github.com/NC1107/slim-m/issues/885)) ([2ac2135](https://github.com/NC1107/slim-m/commit/2ac21352598041873fb83e6a2eb1a3ccd43863c7))


### Bug Fixes

* **client:** render a member's custom status as a two-line row ([#882](https://github.com/NC1107/slim-m/issues/882)) ([1e688e6](https://github.com/NC1107/slim-m/commit/1e688e66f09f38b6f6c3aa6485d638639efc9704))
* **client:** size sheets to content on desktop, use AppErrorState, close token drift ([#880](https://github.com/NC1107/slim-m/issues/880)) ([b2c7080](https://github.com/NC1107/slim-m/commit/b2c70803c643c84c99273b45e1724eb8d928f6bc))
* **client:** theme native launch screens to the dark surface color ([#881](https://github.com/NC1107/slim-m/issues/881)) ([bd7d776](https://github.com/NC1107/slim-m/commit/bd7d7766bcea737c4a08f03af0aaed3b1a06477c))
* prevent reset from deleting failed sends, purge avatar on account delete, real reconnect jitter ([#877](https://github.com/NC1107/slim-m/issues/877)) ([f6895f4](https://github.com/NC1107/slim-m/commit/f6895f494c1ad3558470345ba88a93b36f0810f0))
* restore the avatar purge, failed-send-safe reset, and real jitter ([#889](https://github.com/NC1107/slim-m/issues/889)) ([1548449](https://github.com/NC1107/slim-m/commit/154844900d1e3f8d6e14824047ce43c926fc95cb))


### Performance Improvements

* **client:** restore per-author select on message rows and reply chrome ([#887](https://github.com/NC1107/slim-m/issues/887)) ([f9855b0](https://github.com/NC1107/slim-m/commit/f9855b0d52c3f344ddcf44611615392fae88eee0))
* **client:** restore the stream cache, shell keep-alive, and canvas order cache ([#890](https://github.com/NC1107/slim-m/issues/890)) ([4ed2521](https://github.com/NC1107/slim-m/commit/4ed25211aade1279ea47d4da728334b1bd34f7ac))
* **client:** scope transcript/shell rebuilds and cache channel streams ([#879](https://github.com/NC1107/slim-m/issues/879)) ([72a38c8](https://github.com/NC1107/slim-m/commit/72a38c8a0f5484118dfe48f35a975a0139360109))

## [0.53.0](https://github.com/NC1107/slim-m/compare/client-v0.52.0...client-v0.53.0) (2026-08-25)


### Features

* a space-wide screen-share quality ceiling ([#874](https://github.com/NC1107/slim-m/issues/874)) ([22292e2](https://github.com/NC1107/slim-m/commit/22292e2ff54f6e7f26a42033cde726b8155de440))
* **a11y:** name search hits, emoji tiles, and announce result counts ([#875](https://github.com/NC1107/slim-m/issues/875)) ([d00016d](https://github.com/NC1107/slim-m/commit/d00016d14d6d6afb055447160d1c6aba3930f553))
* **client:** a useful tray menu - presence, call controls, settings ([#870](https://github.com/NC1107/slim-m/issues/870)) ([82e5016](https://github.com/NC1107/slim-m/commit/82e50162ba86b868a99e1ad04b45d634ebf56dd9))
* **client:** continuation-line time shows on hover, not in the left gutter ([#864](https://github.com/NC1107/slim-m/issues/864)) ([a84419e](https://github.com/NC1107/slim-m/commit/a84419e8c1c60b22c09f06933d59a2f45f08e964))


### Bug Fixes

* **client:** a cleaner create-channel form ([#867](https://github.com/NC1107/slim-m/issues/867)) ([2cd699c](https://github.com/NC1107/slim-m/commit/2cd699ccbeae97310913f96d4d273f68576c358d))
* **client:** a rounder, tighter reply bar that handles attachment replies ([#873](https://github.com/NC1107/slim-m/issues/873)) ([b9b027c](https://github.com/NC1107/slim-m/commit/b9b027cae5cd9ca70493d1ec85d9620845596cad))
* **client:** drop the scan-text item from the composer selection menu ([#863](https://github.com/NC1107/slim-m/issues/863)) ([7869a1f](https://github.com/NC1107/slim-m/commit/7869a1fd66128b4ac9d65a7cf96b529c49fe5d30))
* **client:** presence menu becomes a bottom sheet on a phone ([#869](https://github.com/NC1107/slim-m/issues/869)) ([4382f2f](https://github.com/NC1107/slim-m/commit/4382f2fca3a5851d38622f62cf8092a852c8725e))
* **client:** stable kebab padding and continuous row highlight on hover ([#872](https://github.com/NC1107/slim-m/issues/872)) ([ed38f2f](https://github.com/NC1107/slim-m/commit/ed38f2f71cc72e18c01ac925bc2f5e4ac3dfdd32))

## [0.52.0](https://github.com/NC1107/slim-m/compare/client-v0.51.0...client-v0.52.0) (2026-08-25)


### Features

* **client:** a softer, level-normalized notification sound ([#857](https://github.com/NC1107/slim-m/issues/857)) ([94843cd](https://github.com/NC1107/slim-m/commit/94843cde64a170e70863531e2568c1507c9f8490))
* **client:** command palette becomes a full-width pull-down on a phone ([#860](https://github.com/NC1107/slim-m/issues/860)) ([e56ff8b](https://github.com/NC1107/slim-m/commit/e56ff8b08841762c5aa5c8251d4fd25495b9867d))
* **client:** show success confirmations as toasts ([#859](https://github.com/NC1107/slim-m/issues/859)) ([335c5c1](https://github.com/NC1107/slim-m/commit/335c5c104e6a0098f06aed83995d4fcf86d0f626))
* **client:** skip the server-address step when a default server is configured ([#858](https://github.com/NC1107/slim-m/issues/858)) ([879cff5](https://github.com/NC1107/slim-m/commit/879cff5853b232858664263a7411e6071cccc691))


### Bug Fixes

* **design:** light-theme menu edge clears WCAG 3:1 ([#855](https://github.com/NC1107/slim-m/issues/855)) ([b92acf5](https://github.com/NC1107/slim-m/commit/b92acf58662666a077582a905d5e6a16e95e9920))

## [0.51.0](https://github.com/NC1107/slim-m/compare/client-v0.50.0...client-v0.51.0) (2026-08-25)


### Features

* **client:** a toast layer for transient confirmations ([#851](https://github.com/NC1107/slim-m/issues/851)) ([7cfb1db](https://github.com/NC1107/slim-m/commit/7cfb1db3772cf2e8ffa61d7973bb8e8d16425093))
* **client:** bulk-upload emoji from a zip ([#850](https://github.com/NC1107/slim-m/issues/850)) ([8a1b270](https://github.com/NC1107/slim-m/commit/8a1b2701f0e8a7d19b064e9b84e5f0e2012f0811))
* **client:** set a custom status from the sidebar avatar ([#849](https://github.com/NC1107/slim-m/issues/849)) ([a54b468](https://github.com/NC1107/slim-m/commit/a54b4683ae1b31fb1a3ab40d635939998dde6519))

## [0.50.0](https://github.com/NC1107/slim-m/compare/client-v0.49.0...client-v0.50.0) (2026-08-25)


### Features

* **client:** let a reader choose the channel history page size ([#845](https://github.com/NC1107/slim-m/issues/845)) ([9d4504e](https://github.com/NC1107/slim-m/commit/9d4504e7c3d1b04c097bf898023df5b5941719c5))
* make the per-channel canvas object cap a space setting ([#844](https://github.com/NC1107/slim-m/issues/844)) ([55b123a](https://github.com/NC1107/slim-m/commit/55b123a30c0a80e230c2216d56438bd668b34162))

## [0.49.0](https://github.com/NC1107/slim-m/compare/client-v0.48.0...client-v0.49.0) (2026-08-25)


### Features

* **client:** add an attachment preview quality setting, in a Performance pane ([#840](https://github.com/NC1107/slim-m/issues/840)) ([a06947c](https://github.com/NC1107/slim-m/commit/a06947cb2bef86958a767c72bd650d5338fc9ede))
* **client:** add Auto-download media and Autoplay GIFs to the Performance pane ([#841](https://github.com/NC1107/slim-m/issues/841)) ([010e37f](https://github.com/NC1107/slim-m/commit/010e37fe3845e9a5a1e14de2cbbe37f08ebd994b))
* **client:** desktop dropdown for settings pickers, and readable footnotes ([#839](https://github.com/NC1107/slim-m/issues/839)) ([9b7d2b2](https://github.com/NC1107/slim-m/commit/9b7d2b2fad95fe63612a17019b41feae45757a55))


### Bug Fixes

* **client:** render profile photos crisp, not soft, when scaled to an avatar ([#838](https://github.com/NC1107/slim-m/issues/838)) ([ba091ba](https://github.com/NC1107/slim-m/commit/ba091ba67dc99c4d40d2d1a639d9a98bf0e65f6a))

## [0.48.0](https://github.com/NC1107/slim-m/compare/client-v0.47.0...client-v0.48.0) (2026-08-25)


### Features

* **client:** cover a phone's first connect with a boot splash ([#832](https://github.com/NC1107/slim-m/issues/832)) ([db8acaf](https://github.com/NC1107/slim-m/commit/db8acafe976b1d09f8c4784b87fd0ec9688688f5))
* **client:** dock a cold-opened thread too, not only an in-app one ([#829](https://github.com/NC1107/slim-m/issues/829)) ([9a0dcc2](https://github.com/NC1107/slim-m/commit/9a0dcc205a0856c4d9d6d1127d4277cfa597bd06))
* **client:** dock a thread beside the transcript on desktop instead of over it ([#824](https://github.com/NC1107/slim-m/issues/824)) ([7d151fc](https://github.com/NC1107/slim-m/commit/7d151fc3c23d7472faac8e5023cd67b6feb580d0))
* **client:** keep mic, deafen and settings reachable on a collapsed rail (UX2) ([#738](https://github.com/NC1107/slim-m/issues/738)) ([901fed8](https://github.com/NC1107/slim-m/commit/901fed808302772a117b932eb75eaf45afac71c7))
* **client:** orient the onboarding panel with one honest value line ([#831](https://github.com/NC1107/slim-m/issues/831)) ([85b2498](https://github.com/NC1107/slim-m/commit/85b24984f7ffec0cb2e6671d956829dc419beca5))
* **client:** round and compact the reply banner, name attachment-only parents ([#830](https://github.com/NC1107/slim-m/issues/830)) ([d06666a](https://github.com/NC1107/slim-m/commit/d06666a49e44a99c57eb975f0bd551c21ec9cf6e))
* **client:** show the correspondent's avatar in a DM header ([#748](https://github.com/NC1107/slim-m/issues/748)) ([38fcf6d](https://github.com/NC1107/slim-m/commit/38fcf6d7107fde19f6db5cff881ea501fb542b7a))
* **moderation:** server foundation for report history and live sync (MOD4, MOD7) ([#732](https://github.com/NC1107/slim-m/issues/732)) ([882ebcd](https://github.com/NC1107/slim-m/commit/882ebcd32ed44c2aee9d047cc5c9dcc996071a6b))
* **moderation:** show a timed-out member the reason and expiry (MOD6) ([#736](https://github.com/NC1107/slim-m/issues/736)) ([d0ef529](https://github.com/NC1107/slim-m/commit/d0ef5299a1c2ef5a476b2c9c61ed2ea521d94805))


### Bug Fixes

* address SonarQube security and code-quality findings ([#722](https://github.com/NC1107/slim-m/issues/722)) ([d6bdbc5](https://github.com/NC1107/slim-m/commit/d6bdbc59398ae02e1fb898cc578be316e1d0c0ab))
* **canvas:** stop the empty hint contradicting live tiles, soften the tile lift ([#823](https://github.com/NC1107/slim-m/issues/823)) ([e5d82c0](https://github.com/NC1107/slim-m/commit/e5d82c0d0372fd5cdc5ad329c91317d30b1d207c))
* **client:** guard the incoming-call notification channel call ([#751](https://github.com/NC1107/slim-m/issues/751)) ([80b38c0](https://github.com/NC1107/slim-m/commit/80b38c0acd72344be79c5357bd9cfe48b29e9232))
* **client:** let a REST refetch clear a reaction removed to zero (CQ3) ([#759](https://github.com/NC1107/slim-m/issues/759)) ([f999dba](https://github.com/NC1107/slim-m/commit/f999dbaa068177ec9ed304b8f3cf21a0c04f872f))
* **client:** narrow the onboarding brand rail so it stops reading as unfinished ([#833](https://github.com/NC1107/slim-m/issues/833)) ([5202d7a](https://github.com/NC1107/slim-m/commit/5202d7a33d79da800afe62fc66b2bc8d4b8e5761))
* **client:** re-hydrate channel extras on an in-place channel switch ([#750](https://github.com/NC1107/slim-m/issues/750)) ([6c5060c](https://github.com/NC1107/slim-m/commit/6c5060c365165ae9a100f98a89e0eb7b9a918746))
* **client:** render an unset presence status as "Not set", not "Unknown" ([#815](https://github.com/NC1107/slim-m/issues/815)) ([071f5c1](https://github.com/NC1107/slim-m/commit/071f5c1a0bb8ad461b285493d0986e73c7d6ca71))
* **design:** clear AA contrast on the mention pill and operator chip (UX3) ([#733](https://github.com/NC1107/slim-m/issues/733)) ([1df51b0](https://github.com/NC1107/slim-m/commit/1df51b0f023f3c9322d63d0d40ea691b5f61d352))


### Performance Improvements

* **client:** batch catch-up message writes into one transaction ([#747](https://github.com/NC1107/slim-m/issues/747)) ([7aa0000](https://github.com/NC1107/slim-m/commit/7aa0000be0d30bfba1ef138cae0f7b2d18d5d658))
* **client:** cache a cursor's laid-out name label across frames ([#744](https://github.com/NC1107/slim-m/issues/744)) ([e2b360b](https://github.com/NC1107/slim-m/commit/e2b360b2212fe0fab077a0dc07cd9bc66debe8e7))
* **client:** cache a note's laid-out text across frames ([#746](https://github.com/NC1107/slim-m/issues/746)) ([4bac46b](https://github.com/NC1107/slim-m/commit/4bac46beaf66e8c1ffc7d75c040f86cc8f1bf694))
* **client:** rebuild a video tile only for its own participant's events ([#742](https://github.com/NC1107/slim-m/issues/742)) ([29d1afe](https://github.com/NC1107/slim-m/commit/29d1afee514cd6386ce1f9cc3b2937536b8d864f))
* **client:** scope HomeShell's voice watch so a call's churn stops rebuilding it ([#817](https://github.com/NC1107/slim-m/issues/817)) ([ec0d146](https://github.com/NC1107/slim-m/commit/ec0d14637545d95afd534d1a826f7f52e2562d7d))
* **client:** scope the member pane's presence watch per row (CS1) ([#734](https://github.com/NC1107/slim-m/issues/734)) ([823e01d](https://github.com/NC1107/slim-m/commit/823e01d4f42b21acf980754f9a3a62a5721fdcd7))
* **client:** split a finished stroke without re-encoding it each probe ([#743](https://github.com/NC1107/slim-m/issues/743)) ([a3bada6](https://github.com/NC1107/slim-m/commit/a3bada6a28860493b928852be041ff400c8f9c57))
* **client:** stop rebuilding the channel rail on every message (CP8) ([#735](https://github.com/NC1107/slim-m/issues/735)) ([d554cf5](https://github.com/NC1107/slim-m/commit/d554cf5b981af978c3864e02ff32789044389ac4))
* **client:** watch one channel row by id, not the whole table ([#749](https://github.com/NC1107/slim-m/issues/749)) ([327a6fb](https://github.com/NC1107/slim-m/commit/327a6fbdbe81f312fd65daad3b193935f1a0a2e4))

## [0.47.0](https://github.com/NC1107/slim-m/compare/client-v0.46.1...client-v0.47.0) (2026-08-19)


### Features

* **client:** push-to-talk joins a call with the mic closed ([#712](https://github.com/NC1107/slim-m/issues/712)) ([a3be33c](https://github.com/NC1107/slim-m/commit/a3be33c43ed58cc36041be7328e4735a8f17633e))
* **client:** view a message's edit history from the edited marker ([#717](https://github.com/NC1107/slim-m/issues/717)) ([64a5815](https://github.com/NC1107/slim-m/commit/64a581568679306cfb0988ee6880c14820503524))
* **server:** store and serve a message's edit history ([#716](https://github.com/NC1107/slim-m/issues/716)) ([54ad86c](https://github.com/NC1107/slim-m/commit/54ad86cd92ece1b2592dfc6bcd89e2dfec8b2bc6))

## [0.46.1](https://github.com/NC1107/slim-m/compare/client-v0.46.0...client-v0.46.1) (2026-08-19)


### Bug Fixes

* **canvas:** sort sent-to-back tiles beneath front ones so their controls stop overlapping ([#708](https://github.com/NC1107/slim-m/issues/708)) ([a069b98](https://github.com/NC1107/slim-m/commit/a069b9884bd22c63acc70d235638201587454472))
* **desktop:** bound applyInitialGeometry so a stuck native call cannot freeze launch ([#707](https://github.com/NC1107/slim-m/issues/707)) ([6b6ea7b](https://github.com/NC1107/slim-m/commit/6b6ea7b9d6d4c63beb355326c576052985f519f3))

## [0.46.0](https://github.com/NC1107/slim-m/compare/client-v0.45.0...client-v0.46.0) (2026-08-18)


### Features

* **channels:** manage a category from its own context menu ([#703](https://github.com/NC1107/slim-m/issues/703)) ([43985b6](https://github.com/NC1107/slim-m/commit/43985b624f28099d4ff1ae14eead6b315e7810ca))
* **channels:** reach a channel's permissions from its own context menu ([#704](https://github.com/NC1107/slim-m/issues/704)) ([8e1e8ef](https://github.com/NC1107/slim-m/commit/8e1e8efdb13fa8e18c363ca22234b441ec334cd6))
* **diagnostics:** a live memory readout on the debug screen ([#699](https://github.com/NC1107/slim-m/issues/699)) ([5445191](https://github.com/NC1107/slim-m/commit/544519112acfb1257c077f0d4f241774b13f33a7))


### Bug Fixes

* **desktop:** the title bar's window menu had no Overlay to open into ([#702](https://github.com/NC1107/slim-m/issues/702)) ([9e178cf](https://github.com/NC1107/slim-m/commit/9e178cfbd77bb978c29accc89ca097d2f9e033f7))
* **whats-new:** add the 0.45.0 entry the release left main red without ([#700](https://github.com/NC1107/slim-m/issues/700)) ([48eda58](https://github.com/NC1107/slim-m/commit/48eda582f290c6f0353faa053c1f1362ebcda73c))

## [0.45.0](https://github.com/NC1107/slim-m/compare/client-v0.44.0...client-v0.45.0) (2026-08-18)


### Features

* **settings:** a user cap on the decoded-image cache, default 100 MB ([#697](https://github.com/NC1107/slim-m/issues/697)) ([8fd8051](https://github.com/NC1107/slim-m/commit/8fd80517c2787a264a662ce767b9c3047fbe39da))


### Bug Fixes

* **avatars:** decode avatars at a floor so a scaled desktop keeps them crisp ([#695](https://github.com/NC1107/slim-m/issues/695)) ([47a14d2](https://github.com/NC1107/slim-m/commit/47a14d2c7322551a7049aa32931ddbc93c1fc68d))
* **desktop:** the title bar's yellow underline was a missing Material ([#696](https://github.com/NC1107/slim-m/issues/696)) ([3e62cc2](https://github.com/NC1107/slim-m/commit/3e62cc21c4aae01244d551d310122d0403c7e56d))
* **members:** drop the member-pane search box and sort toggle ([#694](https://github.com/NC1107/slim-m/issues/694)) ([df9d04f](https://github.com/NC1107/slim-m/commit/df9d04fc0984289f9c131452a3f20d4c89cfed96))


### Performance Improvements

* **canvas:** a drag repositions an object instead of replacing it ([#686](https://github.com/NC1107/slim-m/issues/686)) ([2e3757a](https://github.com/NC1107/slim-m/commit/2e3757a0af2f682fa9c0bde4d45117207d34c5ff))

## [0.44.0](https://github.com/NC1107/slim-m/compare/client-v0.43.0...client-v0.44.0) (2026-08-16)


### Features

* **messages:** select several messages and delete them at once ([#683](https://github.com/NC1107/slim-m/issues/683)) ([d67e14a](https://github.com/NC1107/slim-m/commit/d67e14ac5aed9c1f9b57801dbf4608d7bd447426))


### Bug Fixes

* **settings:** give each section a shape it earns ([#685](https://github.com/NC1107/slim-m/issues/685)) ([f04b77a](https://github.com/NC1107/slim-m/commit/f04b77a7becf03da466eb1cc56684f789b932994))

## [0.43.0](https://github.com/NC1107/slim-m/compare/client-v0.42.2...client-v0.43.0) (2026-08-16)


### Features

* **members:** find a member, and find who just arrived ([#681](https://github.com/NC1107/slim-m/issues/681)) ([e5b1c52](https://github.com/NC1107/slim-m/commit/e5b1c522c9247922f3db444c33d98a879f0258cc))


### Bug Fixes

* **api:** add the bulk delete client method, and let a schema change reach client-ci ([#679](https://github.com/NC1107/slim-m/issues/679)) ([3687bb9](https://github.com/NC1107/slim-m/commit/3687bb9404e117adb1c6b4d3b9fc02600c1f1887))
* **settings:** a heading marks a group, not a single row ([#682](https://github.com/NC1107/slim-m/issues/682)) ([1371e0a](https://github.com/NC1107/slim-m/commit/1371e0a34115db23b7d035a428c0f6bb7c3c56e1))

## [0.42.2](https://github.com/NC1107/slim-m/compare/client-v0.42.1...client-v0.42.2) (2026-08-15)


### Performance Improvements

* stop two per-frame reapplications, and gate the CI docs ([#668](https://github.com/NC1107/slim-m/issues/668)) ([62bfeb5](https://github.com/NC1107/slim-m/commit/62bfeb55a4c0d5cbff791eb187abaede22c28a43))

## [0.42.1](https://github.com/NC1107/slim-m/compare/client-v0.42.0...client-v0.42.1) (2026-08-14)


### Bug Fixes

* **mentions:** a dropped connection no longer unhighlights every mention ([#660](https://github.com/NC1107/slim-m/issues/660)) ([b5b2255](https://github.com/NC1107/slim-m/commit/b5b2255ed28a6354a59ff004aaff64cf00a03e0b))
* **poll:** an option label sits on its row's centre line ([#658](https://github.com/NC1107/slim-m/issues/658)) ([8998ed0](https://github.com/NC1107/slim-m/commit/8998ed0de002b0cded4ecfe8505e73f9a6670445))
* **rail:** a phone keeps the held press for the channel context menu ([#655](https://github.com/NC1107/slim-m/issues/655)) ([70666fe](https://github.com/NC1107/slim-m/commit/70666fe1abb2e81bd682c106fd31f827b773325b))
* **rail:** losing the connection no longer reshapes the channel list ([#657](https://github.com/NC1107/slim-m/issues/657)) ([ce629cf](https://github.com/NC1107/slim-m/commit/ce629cf466ca1087e70429740a9356f01e1cfcf2))
* **transcript:** a minute of silence starts a new message block ([#661](https://github.com/NC1107/slim-m/issues/661)) ([be13b2f](https://github.com/NC1107/slim-m/commit/be13b2f88df8cf95706876ef1641cf3ad680f3f8))
* **voice:** hanging up after the canvas closes no longer rejoins the call ([#653](https://github.com/NC1107/slim-m/issues/653)) ([686d78e](https://github.com/NC1107/slim-m/commit/686d78ec46fae16c6ece3c398d9c41f03f68c99d))

## [0.42.0](https://github.com/NC1107/slim-m/compare/client-v0.41.1...client-v0.42.0) (2026-08-13)


### Features

* **client,server:** forward a message, mass mentions, and a status line ([#645](https://github.com/NC1107/slim-m/issues/645)) ([3da6f6c](https://github.com/NC1107/slim-m/commit/3da6f6c770b7e6b0808384fe49512d0ebfff458a))
* **client:** a CallKit ringtone and call-aware NSE sound selection ([#630](https://github.com/NC1107/slim-m/issues/630)) ([610f9ec](https://github.com/NC1107/slim-m/commit/610f9ec08859c103751eede0971d53dd13ec93f5))
* **client:** a canvas toggle on the in-call dock, so nobody has to hunt the header mid-call ([#640](https://github.com/NC1107/slim-m/issues/640)) ([3d6d82b](https://github.com/NC1107/slim-m/commit/3d6d82b0cfc55d4324571a8d44b22fd602b601d1))
* **client:** a whats-new entry for the nineteen-job release ([#649](https://github.com/NC1107/slim-m/issues/649)) ([3e99d7b](https://github.com/NC1107/slim-m/commit/3e99d7b6889a30529f742edcc3fd08633fd2b127))
* **client:** desktop push-to-talk, and a voice-activity sensitivity floor ([#642](https://github.com/NC1107/slim-m/issues/642)) ([ac174a6](https://github.com/NC1107/slim-m/commit/ac174a63d45aaa8ac969471ba3db93660750bed9))
* **client:** scaffold a Windows desktop target with a compile-only CI job ([#628](https://github.com/NC1107/slim-m/issues/628)) ([2dd0bfa](https://github.com/NC1107/slim-m/commit/2dd0bfaeb0516d75e6bb94183486f9a4b2c71f04))
* **client:** scaffold the macOS desktop target ([#627](https://github.com/NC1107/slim-m/issues/627)) ([9d437c6](https://github.com/NC1107/slim-m/commit/9d437c6f09315feede944ca7322ec54c6ed9c5fb))
* **client:** share this device's audio alongside a screen share ([#644](https://github.com/NC1107/slim-m/issues/644)) ([9f29d6a](https://github.com/NC1107/slim-m/commit/9f29d6a7d4e91c65e590748aea9356529bea9d06))
* **client:** swipe a message row to start a reply ([#641](https://github.com/NC1107/slim-m/issues/641)) ([5698178](https://github.com/NC1107/slim-m/commit/5698178a5534641fea907bfd0980e58989076e5d))
* **client:** versioned Android channels, and calls join Telecom ([#629](https://github.com/NC1107/slim-m/issues/629)) ([4b1ac0c](https://github.com/NC1107/slim-m/commit/4b1ac0cd7c3229baade6ff2b315dc5b588fcde97))
* four thread gaps closed - listing, unread state, a cross-link, and a cap ([#634](https://github.com/NC1107/slim-m/issues/634)) ([4905df3](https://github.com/NC1107/slim-m/commit/4905df3fed131691617a525542d2bfbb12dacd4f))
* GIF search in the composer, proxied through the server ([#639](https://github.com/NC1107/slim-m/issues/639)) ([e2573a6](https://github.com/NC1107/slim-m/commit/e2573a624be1a7475a34eb1f1b7c258b21522543))
* mute a channel, or narrow it to mentions only ([#643](https://github.com/NC1107/slim-m/issues/643)) ([ea855c3](https://github.com/NC1107/slim-m/commit/ea855c35238c8e3fd0947d5e088678c19a630cdf))
* **search:** Slack-style search operators (from:, in:, has:, before:/after:) ([#638](https://github.com/NC1107/slim-m/issues/638)) ([bf2aa7c](https://github.com/NC1107/slim-m/commit/bf2aa7cd29205f98f285c86c91d87f9c2d436028))
* **server:** per-member attachment storage and message retention ([#633](https://github.com/NC1107/slim-m/issues/633)) ([b70fced](https://github.com/NC1107/slim-m/commit/b70fced88cf99778194efae88d049754f4ebb049))


### Bug Fixes

* **client:** retry failed sends on reconnect, announce sending state, add haptics, and grow rows for Dynamic Type ([#637](https://github.com/NC1107/slim-m/issues/637)) ([2245fcc](https://github.com/NC1107/slim-m/commit/2245fcc88e3650933af002c369e209d190b59468))
* **client:** six small review residuals from the onboarding, moderation, voice and canvas passes ([#636](https://github.com/NC1107/slim-m/issues/636)) ([6f07375](https://github.com/NC1107/slim-m/commit/6f07375f3f514c821737307eccbee614989439cf))
* **e2e:** retry the web-asset fetch instead of dying on one 503 ([#623](https://github.com/NC1107/slim-m/issues/623)) ([51fd9cc](https://github.com/NC1107/slim-m/commit/51fd9cccdb3dda23effa6bb2122542873d84d8ff))
* **e2e:** the join-policy scenario taps twice now that space settings is panes ([#625](https://github.com/NC1107/slim-m/issues/625)) ([69ee853](https://github.com/NC1107/slim-m/commit/69ee853dfaf908e2fa22cb4317659daf778f5a6c))
* **ios:** the sound tests learn the envelope's sentAt field ([#648](https://github.com/NC1107/slim-m/issues/648)) ([e86ec32](https://github.com/NC1107/slim-m/commit/e86ec323955927e94b668b16268c2653cd19286a))
* **push:** stamp sent_at inside the sealed envelope and refuse stale previews ([#631](https://github.com/NC1107/slim-m/issues/631)) ([436f0ba](https://github.com/NC1107/slim-m/commit/436f0baa2d9b43af0af998d52f53fb8068da4cdb))


### Performance Improvements

* refresh the server baseline and measure client and canvas numbers nobody had taken ([#635](https://github.com/NC1107/slim-m/issues/635)) ([c020c58](https://github.com/NC1107/slim-m/commit/c020c587c5564505d24d9235ec3c2246da3c2271))

## [0.41.1](https://github.com/NC1107/slim-m/compare/client-v0.41.0...client-v0.41.1) (2026-08-12)


### Bug Fixes

* **client:** clear four of the analyzer's info-level findings in tests ([#619](https://github.com/NC1107/slim-m/issues/619)) ([9d8323b](https://github.com/NC1107/slim-m/commit/9d8323bff544931bf365df8698b17576778ba7dc))

## [0.41.0](https://github.com/NC1107/slim-m/compare/client-v0.40.0...client-v0.41.0) (2026-08-12)


### Features

* **client:** a whats-new entry for the motion overhaul ([#614](https://github.com/NC1107/slim-m/issues/614)) ([7fa7eff](https://github.com/NC1107/slim-m/commit/7fa7effb3170f7ade2005254ba15cab6e4b720a9))
* **client:** breakpoint bridge, a bounded call room, and the lightbox hero ([#615](https://github.com/NC1107/slim-m/issues/615)) ([fbbe679](https://github.com/NC1107/slim-m/commit/fbbe6794e83d238f55f2e8ff9196697decae08c9))
* **client:** call arrivals, pane reveal parity, and the dock's rise ([#611](https://github.com/NC1107/slim-m/issues/611)) ([e4622a5](https://github.com/NC1107/slim-m/commit/e4622a5cd61cab4a583e9e7d9a862e7cd7168c6c))
* **client:** first-run entrances, settings feedback, and a palette that breathes ([#612](https://github.com/NC1107/slim-m/issues/612)) ([5520f89](https://github.com/NC1107/slim-m/commit/5520f893bc2377111703cd853d3bb92c8b7ad6d1))
* **client:** give every bare OverlayPortal menu a real entrance and exit ([#608](https://github.com/NC1107/slim-m/issues/608)) ([6412694](https://github.com/NC1107/slim-m/commit/6412694b7bc3f8c4ee6f1ec5883958b92338bc1f))
* **client:** gliding cursors, breathing waiting states, and canvas arrivals ([#613](https://github.com/NC1107/slim-m/issues/613)) ([e48938f](https://github.com/NC1107/slim-m/commit/e48938f854798078bbc33e3d0a86c6aae504e1d7))
* **client:** one tempo for the design system: animate the states that snapped ([#606](https://github.com/NC1107/slim-m/issues/606)) ([b2d566e](https://github.com/NC1107/slim-m/commit/b2d566ec2cb0814f34e6fc93f81ef586c3a0c0f7))
* **client:** reveal bands and a composer that grows over a beat ([#610](https://github.com/NC1107/slim-m/issues/610)) ([8c746e2](https://github.com/NC1107/slim-m/commit/8c746e222c2b0074141db3897724a8c67accde50))
* **client:** selection that travels in the channel rail ([#616](https://github.com/NC1107/slim-m/issues/616)) ([b520fa4](https://github.com/NC1107/slim-m/commit/b520fa4a8334e5924c4bfe48b9c9bdb67c66c3c1))
* **client:** space settings gets the same nav-and-pane shape as personal settings ([#617](https://github.com/NC1107/slim-m/issues/617)) ([3aec03a](https://github.com/NC1107/slim-m/commit/3aec03a3586b4f57be7978e5df16c56c095e31ed))
* **client:** the transcript's hand-on moments travel instead of hard-cutting ([#609](https://github.com/NC1107/slim-m/issues/609)) ([a910484](https://github.com/NC1107/slim-m/commit/a910484cef3e1ffb296eda7f92af9b88ba447ed8))

## [0.40.0](https://github.com/NC1107/slim-m/compare/client-v0.39.0...client-v0.40.0) (2026-08-12)


### Features

* **client:** open the channel a tapped notification came from ([#591](https://github.com/NC1107/slim-m/issues/591)) ([10a1814](https://github.com/NC1107/slim-m/commit/10a181436f8aa0e8bf659fff67d320b217901c74))
* **server:** a restored member reaches connected clients ([#602](https://github.com/NC1107/slim-m/issues/602)) ([0068eec](https://github.com/NC1107/slim-m/commit/0068eec4c9eeca02d26c21853ed02a23c20d9fc8))


### Bug Fixes

* an empty push preview, and two report columns deletion never cleared ([#584](https://github.com/NC1107/slim-m/issues/584)) ([550d9b0](https://github.com/NC1107/slim-m/commit/550d9b028d5c21a88256907e66ba5a0d11bc621c))
* **client:** keep permission invalidation alive for the whole session ([#600](https://github.com/NC1107/slim-m/issues/600)) ([5e987e6](https://github.com/NC1107/slim-m/commit/5e987e6df89a468b38bf4781de5b5d282656eda4))

## [0.39.0](https://github.com/NC1107/slim-m/compare/client-v0.38.0...client-v0.39.0) (2026-08-11)


### Features

* **client:** decrypt the sealed push preview on a locked iPhone ([#574](https://github.com/NC1107/slim-m/issues/574)) ([9a7ef9e](https://github.com/NC1107/slim-m/commit/9a7ef9e373e9f7854b62276f3a948f1013535229))
* **client:** expand a canvas presence tile to full screen ([#573](https://github.com/NC1107/slim-m/issues/573)) ([b060908](https://github.com/NC1107/slim-m/commit/b060908406dc5f3569e48a0c8026c20b1b28a421))
* **client:** let a person turn on the decrypted push preview ([#577](https://github.com/NC1107/slim-m/issues/577)) ([8277ef4](https://github.com/NC1107/slim-m/commit/8277ef4a28281dc240cd83eccb5b3134ec22eccf))


### Bug Fixes

* **client:** drop the reacted chip's marker dot, lean on fill and weight ([#578](https://github.com/NC1107/slim-m/issues/578)) ([2d0a4b2](https://github.com/NC1107/slim-m/commit/2d0a4b25fd1e5413496eb019c48fe0982a296b32))
* **client:** guard a hang-up that a newer join already superseded ([#580](https://github.com/NC1107/slim-m/issues/580)) ([def6924](https://github.com/NC1107/slim-m/commit/def69248244bd547b4c61f808ef82605d224ab2b))
* **client:** the update notes stopped being written twelve releases ago ([#579](https://github.com/NC1107/slim-m/issues/579)) ([da0e239](https://github.com/NC1107/slim-m/commit/da0e2397175716556eae89b1330f8f3f8b82efda))

## [0.38.0](https://github.com/NC1107/slim-m/compare/client-v0.37.0...client-v0.38.0) (2026-08-11)


### Features

* **client:** reorder channel categories from the categories screen ([#570](https://github.com/NC1107/slim-m/issues/570)) ([59d2f99](https://github.com/NC1107/slim-m/commit/59d2f993fe702392e8693590ce43c4807cb19d69))
* **client:** wrap canvas presence tiles to the pane, and a fullscreen mode ([#568](https://github.com/NC1107/slim-m/issues/568)) ([af6df78](https://github.com/NC1107/slim-m/commit/af6df78382ce2df49d73239390cf14323c33e97a))


### Bug Fixes

* **client:** a call recap now covers a solo call, not just an accompanied one ([#567](https://github.com/NC1107/slim-m/issues/567)) ([e111432](https://github.com/NC1107/slim-m/commit/e1114320ac0d1d4b81fe4f4262b203a10bff6b17))
* **client:** a channel row's context menu was stealing every reorder drag ([#564](https://github.com/NC1107/slim-m/issues/564)) ([68fc897](https://github.com/NC1107/slim-m/commit/68fc897bf19fe4f16d21e92dba983d646a9e23aa))
* **client:** a false camera-switch error, and an unmirrored front preview ([#562](https://github.com/NC1107/slim-m/issues/562)) ([cb82560](https://github.com/NC1107/slim-m/commit/cb82560c53546e561b89055b66cc7126314ce29a))
* **client:** compact the gap between reaction chips ([#565](https://github.com/NC1107/slim-m/issues/565)) ([4f4b721](https://github.com/NC1107/slim-m/commit/4f4b7211fb460e5dd7dda5f24681be757234b622))
* **client:** steady the transcript scrollbar ([#571](https://github.com/NC1107/slim-m/issues/571)) ([3e6cd84](https://github.com/NC1107/slim-m/commit/3e6cd847cb4ba71c00bd2e9be3b276cc96901d72))

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
