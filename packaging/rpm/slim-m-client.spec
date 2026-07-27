# SPDX-License-Identifier: Apache-2.0
# Fedora package for the slim-m Linux desktop client, built and hosted on COPR.
# Install steps and how to cut a new COPR build: README.md alongside this file.

%global debug_package %{nil}
%global appid     top.npcserver.slimm
%global bundledir %{_libdir}/%{name}

# The Flutter engine and its plugin .so files are private to this app, not distro
# libraries: rpm must neither advertise them nor try to resolve them elsewhere.
%global __provides_exclude_from ^%{bundledir}/.*\\.so$
%global __requires_exclude ^lib(flutter_linux_gtk|webrtc|flutter_webrtc_plugin|flutter_secure_storage_linux_plugin|livekit_client_plugin|sqlite3_flutter_libs_plugin)\\.so

Name:           slim-m-client
# Bumped by hand for a COPR rebuild; the release workflow stamps the tag's
# version over this line, so the .rpm on a release always matches its tag.
Version:        0.4.0
Release:        1%{?dist}
Summary:        Desktop client for the slim-m self-hosted messaging platform

License:        Apache-2.0
URL:            https://github.com/NC1107/slim-m
# The portable release tarball. Repackaged rather than built from source: a
# Flutter build needs network for pub, which a COPR/mock buildroot has not.
Source0:        https://github.com/NC1107/slim-m/releases/download/client-v%{version}/slim-m-client-%{version}-linux-amd64.tar.gz
Source1:        top.npcserver.slimm.desktop

# The upstream Flutter engine and the bundled libwebrtc are x86_64-only builds.
ExclusiveArch:  x86_64

BuildRequires:  tar
BuildRequires:  gzip
BuildRequires:  desktop-file-utils
BuildRequires:  patchelf

# Only what is dlopen'd, so rpm's ELF scan cannot see it. libwebrtc opens its
# audio and screencast backends by soname, and libepoxy opens GL the same way.
Requires:       libEGL.so.1()(64bit)
Requires:       libGL.so.1()(64bit)
Requires:       libasound.so.2()(64bit)
Requires:       libpulse.so.0()(64bit)
Requires:       libpipewire-0.3.so.0()(64bit)

# Services rather than libraries, and each backs one feature rather than the app:
# no portal means no screen share, no secret service means no remembered sign-in.
Recommends:     xdg-desktop-portal
Recommends:     gnome-keyring

%description
The slim-m desktop client: text channels, voice, screen share and direct
messages against a slim-m home server, either one you run yourself or one
you were invited to. One deployment is one community.

This package repackages the official Linux release rather than building from
source. The Flutter engine, the WebRTC library and the app's plugins ship
inside it, the way upstream builds them; GTK, audio, graphics and the secret
service come from the system.

%prep
%setup -q -n %{name}-%{version}

%build
# Nothing to build - the bundle is prebuilt.

%install
install -d %{buildroot}%{bundledir}
cp -a slimm_app data lib %{buildroot}%{bundledir}/

# Flutter links its plugins against absolute paths inside the build tree, which
# check-rpaths rejects. Every one of them only ever needs its own directory.
for so in %{buildroot}%{bundledir}/lib/*.so; do
    patchelf --set-rpath '$ORIGIN' "${so}"
done

# Flutter writes its shared objects 0644; a shared library is expected to carry
# the executable bit, and rpm's own scanners key off it.
chmod 0755 %{buildroot}%{bundledir}/lib/*.so

# The runner resolves data/ and lib/ against /proc/self/exe, which reports the
# link target rather than the link, so a symlink works where a PATH shim does not.
install -d %{buildroot}%{_bindir}
ln -s ../%{_lib}/%{name}/slimm_app %{buildroot}%{_bindir}/slim-m

desktop-file-install --dir=%{buildroot}%{_datadir}/applications %{SOURCE1}

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/%{appid}.desktop
# The runner is useless without these two, and a bundle that lost them would
# otherwise package cleanly and fail at launch on the user's machine.
test -x %{buildroot}%{bundledir}/slimm_app
test -f %{buildroot}%{bundledir}/data/icudtl.dat

%files
%license LICENSE
%doc README.md
%{_bindir}/slim-m
%{bundledir}/
%{_datadir}/applications/%{appid}.desktop

%changelog
* Mon Jul 27 2026 NC1107 <nickpconn@gmail.com> - 0.4.0-1
- Initial COPR packaging (repackage of the official Linux release tarball).
