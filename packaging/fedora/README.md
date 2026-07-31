# Fedora packaging

The slim-m desktop client ships as a Fedora package, built and hosted on [COPR](https://copr.fedorainfracloud.org/coprs/nc1107/slim-m/) at `nc1107/slim-m`.
The spec is `packaging/rpm/slim-m-client.spec`; this directory holds the operator side of it, matching how `nc1107/sink` is laid out.

It repackages the Linux release tarball rather than building from source: a Flutter build resolves pub dependencies over the network, and a COPR (mock) buildroot has no network at all.

**Not live yet.** The COPR project does not exist until someone creates it, and `dnf copr enable` fails with a 404 until then.
The `.rpm` on the GitHub release arrives on the first client tag cut after this lands; COPR needs the manual step at the bottom of this file as well.

## Install

```bash
sudo dnf copr enable nc1107/slim-m
sudo dnf install slim-m-client
```

Or take the `.rpm` straight from a [client release](https://github.com/NC1107/slim-m/releases) and `sudo dnf install ./slim-m-client-*.rpm` - no COPR needed.
The release also carries a `SHA256SUMS`, and a `SHA256SUMS.asc` when the signing key is configured.

x86_64 only, on purpose.
`release.yml`'s `linux-client` job runs on `ubuntu-latest` and builds one Flutter Linux bundle, so an aarch64 chroot would have no binary to repackage.
The server images and static server binaries are built for both architectures; the desktop client is not, and enabling an arm chroot would produce a build that fails rather than a package nobody uses.

## How a new version reaches COPR

Cutting a client release does it.
The `copr` job in `.github/workflows/release.yml` stamps the release version into the spec, downloads the release tarball into the SRPM with `spectool` (COPR's buildroot cannot fetch it later), and submits with `copr-cli build nc1107/slim-m`.

The job is inert without the `COPR_CONFIG` secret and warns rather than failing, in the same shape as the Android and iOS jobs.
A submit failure is also only a warning: the `.rpm` is already attached to the GitHub release, so COPR being down does not fail a release.

By hand, when that job has skipped or failed:

```bash
sudo dnf install copr-cli rpm-build rpmdevtools
rpmdev-setuptree
cp packaging/rpm/slim-m-client.spec ~/rpmbuild/SPECS/
# spectool fetches remote sources only, so the local ones go by hand: the
# desktop entry and the hicolor icons it names.
cp packaging/rpm/top.npcserver.slimm.desktop ~/rpmbuild/SOURCES/
cp packaging/linux/icons/top.npcserver.slimm*.png \
   packaging/linux/icons/top.npcserver.slimm.svg ~/rpmbuild/SOURCES/
spectool -g -R ~/rpmbuild/SPECS/slim-m-client.spec
rpmbuild -bs ~/rpmbuild/SPECS/slim-m-client.spec
copr-cli build nc1107/slim-m ~/rpmbuild/SRPMS/slim-m-client-*.src.rpm
```

`copr-cli` reads `~/.config/copr`, which is the same file the `COPR_CONFIG` secret holds.
If the spec's `Version:` is a macro rather than a literal, add `-D 'app_version <version>'` to the `spectool` and `rpmbuild` lines; that is the same value the CI job appends to `~/.rpmmacros`.

## Creating the COPR project

One-time, and it needs a browser login, so it cannot be scripted from here.
The full step-by-step, including which chroots to tick and where the API token comes from, is in `human-todos.md` at the repo root under "Create the COPR project".
That file is deliberately untracked, so the short version, for anyone who is not the owner:

- Project name `slim-m` under the account that owns the package.
- Chroots `fedora-43-x86_64`, `fedora-44-x86_64`, `fedora-rawhide-x86_64`, with "follow Fedora branching" on so a new Fedora release adds itself. That is exactly what `nc1107/sink` has enabled.
- Leave "enable internet access during builds" off. The spec is written for a network-free buildroot and turning it on would hide a broken `Source0` instead of failing on it.
- The API token is generated at <https://copr.fedorainfracloud.org/api/> and becomes the `COPR_CONFIG` GitHub secret verbatim, the whole `[copr-cli]` block.

### Upgrading, and why a new release can look missing for two days

`sudo dnf upgrade slim-m-client` answering "Nothing to do" the day a release ships does not mean the repository is disabled or the build failed.

dnf caches repository metadata, and the COPR-generated `.repo` file sets no `metadata_expire`, so dnf's default of **48 hours** applies.
Until that lapses, dnf answers from a cache written before the new build existed and reports, correctly for what it knows, that there is nothing to do.

`sudo dnf copr enable nc1107/slim-m` appears to fix it, which is misleading: it rewrites the `.repo` file, and that invalidates the cache as a side effect.
The repository was enabled the whole time.

Ask for fresh metadata instead:

```
sudo dnf upgrade --refresh slim-m-client
```

Or, to stop having to remember the flag, tell dnf to check this one repository more often:

```
sudo dnf config-manager setopt copr:copr.fedorainfracloud.org:nc1107:slim-m.metadata_expire=1h
```

The cost of the shorter window is one small metadata fetch per hour of use, against a release being invisible for up to two days.
