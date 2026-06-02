# Toolchain & build notes

This document captures the dev-environment requirements + the
non-obvious gotchas LibreUEFI dev hit on the reference Linux Mint
x86_64 host. Read before reporting a "won't build" bug.

## Reference host

- Linux Mint 22 (Ubuntu 24.04 base), kernel 6.17, glibc 2.39
- Python 3.12 (BaseTools requires `>= 3.8`)
- GCC 13.3 host compiler

The CI workflow at `.github/workflows/build-ovmf.yml` matches this with
`ubuntu-24.04` runners; if you reproduce the build there and it works,
your local install is the variable.

## Required apt packages (Debian / Ubuntu / Mint)

```bash
sudo apt install \
    build-essential \
    nasm \
    acpica-tools \
    uuid-dev \
    python3 \
    python3-distutils-extra \
    git
```

Distributions other than Debian-derivatives need equivalent packages;
the package names will differ but the set is small. On Fedora /
Rocky / Alma:

```bash
sudo dnf install \
    gcc gcc-c++ make \
    nasm \
    iasl \
    libuuid-devel \
    python3 \
    git
```

## Toolchain — why GCCNOLTO, not GCC5

EDK2's `Conf/tools_def.txt` defines `GCC5`, `GCCNOLTO`, and several
older `GCC{44,45,46,47,48}` profiles. The default upstream `build.sh`
selected `GCC5`, which on modern glibc + GCC 13 fails at the toolchain
detection stage:

```
build: : warning: Tool chain [GCC5] is not defined
build.py...
 : error 4000: Not available
	[GCC5] not defined. No toolchain available for build!
```

The `GCC5` profile assumes a specific link-time-optimization (LTO)
config that isn't present on stock GCC 13. The `GCCNOLTO` profile is
the supported "modern GCC, LTO disabled" target and is what the
LibreUEFI `build.sh` ships with.

If you must use `GCC5` (e.g. you're cross-building with a specific
toolchain tarball), edit `Conf/target.txt` after the first `build.sh`
run, set `TOOL_CHAIN_TAG = GCC5`, and re-run.

## The `BUILD_RULE_CONF` gotcha

EDK2's `build` resolves the build-rules file from `Conf/target.txt`'s
`BUILD_RULE_CONF` key. Upstream `Conf/target.template` ships with:

```
BUILD_RULE_CONF = Conf/build_rule.txt
```

…but historically, `libreuefi/build.sh` synthesized `Conf/target.txt`
from a heredoc that **omitted** this key. Without it, the build hits:

```
build.py...
 : error 0001: File open failure
	build_rule.txt
```

because `build` falls back to opening the literal string
`build_rule.txt` as a relative path, which doesn't exist (the actual
file lives at `Conf/build_rule.txt`).

**Resolution shipped in libre-vmm v0.1.1 / LibreUEFI 0.1.1**:
`build.sh` now writes `BUILD_RULE_CONF = Conf/build_rule.txt` into the
generated `Conf/target.txt`. If you ever inherit a stale `target.txt`
from a previous EDK2 checkout, delete `Conf/target.txt` and re-run
`build.sh` — it regenerates with the correct content.

## The FDF preprocessor comment gotcha

EDK2's FDF preprocessor scans `.fdf.inc` files for `!include`
directives **without first stripping comments**. This means any literal
`!include` token inside a comment block is misparsed as a real include
directive:

```
GenFds.FdfParser.Warning: The include file does not exist under below directories:
  ...
  near line 10, column 0: #  the three scattered hunks into one !include block
```

The `LibreUefi.fdf.inc` and `LibreUefi.dsc.inc` files in this fork use
the literal phrase `include directive` in comment bodies (instead of
the backtick form `` `!include` ``) to sidestep this. If you add new
comments referring to `!include`, write the word "include" instead.

## `.dec` parser + `!include` limitation

EDK2 BaseTools' `.dec` parser rejects `!include` directives inside
`[Guids]` section bodies (`error 3000: No GUID name or value
specified` — the parser tries to interpret `!include …` as a
`<CName> = <GuidValueInCFormat>` row). This is a BaseTools-version
constraint, not an EDK2-spec rule. As a result,
`OvmfPkg/Include/LibreUefi/LibreUefi.dec.inc` ships as a docs-only
placeholder; the 3 fork GUIDs stay inline in `OvmfPkg/OvmfPkg.dec`.
When BaseTools gains support for section-body `!include` in `.dec`,
the swap is a single-line edit.

## Bumping the upstream EDK2 pin

LibreUEFI tracks tianocore/edk2 at a deliberately-pinned commit.
Bumping the pin is a four-step ritual:

1. `cd edk2 && git fetch origin && git checkout <new-tag-or-sha>`
2. Re-apply LibreUEFI patches (`git status` should show only the
   expected `OvmfPkg/*` + `MdeModulePkg/Logo/*` files modified). If
   upstream renamed any of the patch targets, resolve manually +
   document in the CHANGELOG.
3. Run `./build.sh` with `-D SECURE_BOOT_ENABLE` AND with the flag
   omitted (the latter is the R6.A4 challenger conditional). Both must
   end in `- Done -`.
4. Bump the `pin` comment in this file and in `README.md`'s
   "Vendoring strategy" section.

If a future libre-vmm release needs new firmware features (e.g. a new
fw_cfg key), the corresponding R-round audit row gets logged in
libre-vmm's `docs/AUDIT-LOG.md` and the firmware change lands in this
fork's history. The libre-vmm side then bumps its bundled-firmware
version pin.

## The `NETWORK_TLS_ENABLE` `-Werror=maybe-uninitialized` failure

Upstream `CryptoPkg/Library/TlsLib/TlsConfig.c:266` has a
`maybe-uninitialized` GCC warning on `OpensslCipher` that modern GCC
(13+) escalates with the EDK2 default `-Werror`:

```
TlsConfig.c: In function 'TlsSetCipherList':
TlsConfig.c:266:29: error: 'OpensslCipher' may be used uninitialized
                          [-Werror=maybe-uninitialized]
```

Upstream tianocore has a fix queued; LibreUEFI v0.1.1 sidesteps it by
**not enabling NETWORK_TLS** at build time (and by extension neither
HTTP_BOOT nor IP6, which depend on it). The downside: HTTPS Boot from
firmware is unavailable. libre-vmm doesn't use HTTPS Boot today
(network boot happens after OS hand-off), so the trade-off is
acceptable.

To re-enable later: cherry-pick the upstream tianocore fix for
`TlsConfig.c` and add `-D NETWORK_TLS_ENABLE -D NETWORK_HTTP_BOOT_ENABLE
-D NETWORK_IP6_ENABLE` back to `build.sh`.

## CI

The GitHub Actions workflow at `.github/workflows/build-ovmf.yml`
runs the same `build.sh` on `ubuntu-24.04` for every push and pull
request. On version tags (`v0.1.*`, `v0.2.*`, etc.) it additionally
uploads `LIBREUEFI_CODE.fd` + `LIBREUEFI_VARS.fd` as release assets so
downstream consumers (libre-vmm's packaging step, distro packagers)
can pull pre-built artifacts without setting up the toolchain
themselves.
