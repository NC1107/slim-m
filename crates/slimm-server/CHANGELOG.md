# Changelog

## [1.0.0](https://github.com/NC1107/slim-m/compare/server-v0.8.0...server-v1.0.0) (2026-07-26)


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
