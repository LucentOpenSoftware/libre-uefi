# LibreUEFI

A UEFI firmware fork of [TianoCore EDK2](https://github.com/tianocore/edk2)
tailored as the firmware backend for [**libre-vmm**](https://github.com/LucentOpenSoftware/libre-vmm),
a libre QEMU/KVM/libvirt VM manager.

LibreUEFI ships an `OVMF_CODE.fd` / `OVMF_VARS.fd` pair compatible with
QEMU's `-pflash` interface, with three classes of additions on top of
upstream OVMF:

- **Identity** — Type 1 SMBIOS UUID + SerialNumber populated from
  host-supplied `opt/libre-vmm/system-uuid` + `opt/libre-vmm/vm-name`
  fw_cfg keys so each guest reports a unique SMBIOS identity (Windows
  activation tracking + Linux machine-id seeding work correctly).
- **Trust-boundary hardening** — bounded fw_cfg readers, control-char
  sanitization, opt-in default-key enrollment gated on a runtime flag,
  `CpuDeadLoop()` after `ResetSystem` so a broken-runtime-services
  return cannot silently chain to the next boot option.
- **Branding + UX polish** — replaced upstream OVMF logo, accurate
  boot-menu key hints, and two standalone EFI applications
  (`LibreVmmReset.efi` + `LibreVmmShutdown.efi`) that route a
  user-selectable boot-order entry to `ResetSystem` calls.

The fork is currently **tailored to libre-vmm**'s needs — the
`opt/libre-vmm/*` fw_cfg namespace, the `LibreVmm*` driver/application
names, and the audit lineage all reflect that. The codebase will be
relicensed and re-namespaced if it ever grows beyond a libre-vmm
companion.

## Audit trail

LibreUEFI's history of bug fixes, security hardening, and intentional
architectural choices is recorded as audit-log rows in libre-vmm's
`docs/AUDIT-LOG.md` under the round IDs `R1-uefi`, `R6-uefi`, `R8b`,
and per-row identifiers like `#040`, `#045`, `#081`, `#088`, `#170`.
A LibreUEFI-local `CHANGELOG.md` here mirrors the firmware-relevant
subset.

## Repository layout

```
libreuefi/
├── build.sh                    Top-level build wrapper (BaseTools + EDK2 build)
├── output/                     Built firmware blobs (gitignored)
├── edk2/                       Forked EDK2 tree — see "Vendoring strategy" below
│   ├── OvmfPkg/
│   │   ├── Include/LibreUefi/  Fork-additions overlay (.dec.inc, .dsc.inc, .fdf.inc)
│   │   ├── LibreVmmAcpiDxe/    Custom ACPI driver (libre-vmm SMBIOS / ACPI defaults)
│   │   ├── LibreVmmResetApp/   Standalone EFI app — issues warm reset
│   │   ├── LibreVmmShutdownApp/Standalone EFI app — issues shutdown
│   │   ├── SmbiosPlatformDxe/  Modified: NeedSmbiosType1 guard + UUID/SN from fw_cfg
│   │   └── Library/PlatformBootManagerLib/BdsPlatform.c (modified)
│   └── MdeModulePkg/Logo/      Replaced default OVMF logo
├── docs/
│   └── TOOLCHAIN.md            GCCNOLTO setup + apt deps + known gotchas
└── .github/workflows/
    └── build-ovmf.yml          CI: builds OVMF, uploads artifacts on release tags
```

## Vendoring strategy

The `edk2/` subtree is a vendored copy of `tianocore/edk2` at a pinned
commit, with libre-uefi modifications applied **inline** as uncommitted
working-tree changes against the upstream remote. When you publish this
repo to GitHub, pick one:

1. **Monorepo (recommended for first publish)** — `rm -rf edk2/.git`
   then `git init` at `libreuefi/` and commit everything. Simplest
   developer experience (one clone, one tree); heaviest clone size
   (~700 MB). Loses access to upstream tianocore commit history from
   inside `edk2/` — re-clone tianocore separately if you need
   `git diff` against upstream.
2. **Submodule fork** — fork `tianocore/edk2` to your own GitHub
   namespace, push our libre-uefi patches there as commits on a
   `libre-uefi` branch, then in `libreuefi/`: `rm -rf edk2` and add
   your fork as a submodule. Cleanest for future EDK2 rebases.
3. **Patch series** — keep `edk2/` as a submodule pointing at upstream
   `tianocore/edk2`; extract the libre-uefi modifications into
   `patches/*.patch`; teach `build.sh` to `git apply` them before
   building. Smallest libre-uefi.git footprint; most ceremony.

This repo is set up so **all three** work after a one-time prep step.
The default `.gitignore` excludes build artifacts + the nested
`edk2/.git` is not currently tracked (git refuses to nest by default;
choose strategy (1) or (2) above to formalize).

The libre-uefi EDK2 baseline is **tianocore/edk2 @ `c4d29cb6`**
(2026-02-06). Bumping the upstream pin is a deliberate maintainer
action — read `docs/TOOLCHAIN.md` for the procedure.

## Build

```bash
# One-time host setup (Debian/Ubuntu):
sudo apt install build-essential nasm acpica-tools uuid-dev python3 \
    python3-distutils-extra git

# Build:
./build.sh
```

Artifacts land in `output/`:

- `LIBREUEFI_CODE.fd` — read-only firmware blob (~4 MiB)
- `LIBREUEFI_VARS.fd` — variable store template (~540 KiB)

Use with QEMU:

```bash
qemu-system-x86_64 \
    -machine q35 \
    -drive if=pflash,format=raw,readonly=on,file=output/LIBREUEFI_CODE.fd \
    -drive if=pflash,format=raw,file=path/to/copy-of-VARS.fd \
    -fw_cfg name=opt/libre-vmm/vm-name,string=my-vm \
    -fw_cfg name=opt/libre-vmm/system-uuid,file=path/to/16-byte-uuid.bin
```

See `docs/TOOLCHAIN.md` for the GCCNOLTO toolchain rationale, the known
`Conf/target.txt` gotcha (`BUILD_RULE_CONF` must be set explicitly),
and CI usage.

## libre-vmm consumption

libre-vmm consumes pre-built LibreUEFI artifacts at a known path —
`/usr/share/libreuefi/OVMF_CODE.fd` + `/usr/share/libreuefi/OVMF_VARS.fd`
on Linux. The libre-vmm packaging (.deb / .rpm) currently bundles a
pinned LibreUEFI release; users building libre-vmm from source can
either:

- Install the `libreuefi-firmware` package from a future libre-vmm
  release artifact, or
- Build LibreUEFI here and symlink the outputs into
  `/usr/share/libreuefi/` (see libre-vmm's
  `docs/INTEGRATING-LIBRE-UEFI.md`).

The fw_cfg contract between libre-vmm and LibreUEFI is documented at
`docs/FW-CFG-CONTRACT.md` (forthcoming; currently in the audit-log
trail under rows #045 and #088).

## License

BSD-2-Clause-Patent — same as upstream EDK2. See `LICENSE`.

LibreUEFI inherits BSD-2-Clause-Patent because:

1. Upstream EDK2 ships under that license, and forking does not change
   the inbound license.
2. Our additions (the `LibreVmm*` packages + `OvmfPkg/Include/LibreUefi/`
   overlay + `BdsPlatform.c` / `SmbiosPlatformDxe.c` modifications)
   are submitted by contributors under the same terms.

## Status

Status: **firmware backend for libre-vmm v0.1.1+**. Stable for the
QEMU/KVM x86_64 SeaBIOS-replacement use case. Not yet recommended as a
general-purpose OVMF replacement; the SMBIOS Type 1 patching expects
libre-vmm-shaped fw_cfg input.

---

## Historical Note

LibreUEFI did not begin as a separate project.

It began as a practical question inside Libre-VMM:

> What if the firmware knew enough about the virtual machine to stop behaving like a stranger?

The first answers were small:

* make shutdown actually stop
* make reset actually reset
* avoid duplicate SMBIOS Type 1 identities
* let the VM name and UUID reach the firmware
* gate Secure Boot enrollment behind explicit host intent
* remove firmware reads that asked questions and then ignored the answers

At some point, the patch set stopped looking like a workaround and started looking like a firmware distribution.

The split into `libre-uefi` happened when the evidence became difficult to ignore.

### Recovered Conversation

Libre-VMM:
"Hey."

LibreUEFI:
"Yeah?"

Libre-VMM:
"Do you remember when you were just a few OVMF patches?"

LibreUEFI:
"No."

Libre-VMM:
"You don't?"

LibreUEFI:
"I thought I was always a firmware project."

Libre-VMM:
"You were not."

LibreUEFI:
"What was I?"

Libre-VMM:
"A handful of fixes."

LibreUEFI:
"..."

Libre-VMM:
"Then you learned SMBIOS."

LibreUEFI:
"That seems important."

Libre-VMM:
"Then you learned Secure Boot boundaries."

LibreUEFI:
"Healthy."

Libre-VMM:
"Then you learned not to read things you don't use."

LibreUEFI:
"Personal growth."

Libre-VMM:
"Then we gave you your own repo."

LibreUEFI:
"..."

Libre-VMM:
"Yeah."

LibreUEFI:
"So am I independent now?"

Libre-VMM:
"Technically."

LibreUEFI:
"But still tailored for you?"

Libre-VMM:
"Also technically."

LibreUEFI:
"That sounds complicated."

Libre-VMM:
"It is firmware."

...

LibreUEFI:
"Do you think upstream will understand?"

Libre-VMM:
"No."

LibreUEFI:
"Do we?"

Libre-VMM:
"Also no."

...

[End of recovered transcript]

Researchers believe this conversation occurred shortly before the first standalone `libre-uefi` build completed successfully with both Secure Boot enabled and disabled.

No containment strategy currently exists.

---

## Reporting bugs

Open an issue here. For libre-vmm-specific behavior questions, the
libre-vmm repo is the better venue (this fork's behavior tracks
libre-vmm's needs).
