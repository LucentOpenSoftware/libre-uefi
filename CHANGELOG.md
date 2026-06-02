# Changelog

LibreUEFI firmware-relevant history, mirrored from the libre-vmm
`docs/AUDIT-LOG.md` under audit-round IDs `R1-uefi`, `R6-uefi`,
`R8b-uefi`. Row numbers reference the libre-vmm audit log.

This file lives separately from libre-vmm's history because LibreUEFI
will be picked up + extended on its own; the audit log there continues
to be the canonical record of changes that touched both repos in the
same commit-time window.

The format is loosely [Keep a Changelog](https://keepachangelog.com/),
ordered newest-first, grouped by firmware-version equivalent of
libre-vmm release.

---

## [0.1.1] — 2026-06-02 (libre-vmm v0.1.1)

### Added
- `OvmfPkg/Include/LibreUefi/LibreUefi.{dec,dsc,fdf}.inc` — fork-additions
  overlay. The `.dsc.inc` + `.fdf.inc` consolidate 6 scattered upstream
  hunks (LibreVmmAcpiDxe, the two LibreVmm Reset/Shutdown apps, the
  SECURE_BOOT-gated EnrollDefaultKeys) into single `!include` directives
  in the upstream `OvmfPkgX64.dsc` + `OvmfPkgX64.fdf`. The `.dec.inc`
  ships as a docs-only placeholder because EDK2 BaseTools' `.dec`
  parser rejects `!include` inside `[Guids]` section bodies (see
  libre-vmm audit row #170 for the full diagnosis).
- `Conf/target.txt` template now sets `BUILD_RULE_CONF = Conf/build_rule.txt`
  explicitly. Without that line, `build` fails at `error 0001: File
  open failure: build_rule.txt` on fresh dev environments.

### Verified
- Both `-D SECURE_BOOT_ENABLE` (TRUE, default) and
  `-D SECURE_BOOT_ENABLE=FALSE` (omit the flag) builds pass clean with
  the GCCNOLTO toolchain — 28 s + 24 s respectively on the reference
  Linux Mint x86_64 dev rig, both ending in `- Done -` with full FV
  space summary.

---

## [0.1.0] — 2026-05-31 (libre-vmm v0.1.0)

### Security

- **#088** `SmbiosPlatformDxe.c` — added `NeedSmbiosType1` guard so a
  Type 1 SMBIOS table is installed only when QEMU did not supply one
  (no more spec-violating duplicates). UUID populated from
  `opt/libre-vmm/system-uuid` fw_cfg (16 raw bytes); SerialNumber from
  `opt/libre-vmm/vm-name` fw_cfg (control-char sanitized; falls back to
  `libre-vmm-default` if the host doesn't supply one). Each libre-vmm
  VM now reports a unique SMBIOS identity — Windows activation
  tracking + Linux machine-id seeding work correctly. **Severity: high.**
- **#081** `LibreVmmShutdownApp/LibreVmmShutdown.c` — `CpuDeadLoop()`
  after `ResetSystem(EfiResetShutdown, …)` so a broken-runtime-services
  return cannot silently chain the next BootOrder entry → "shutdown"
  no longer boots the OS instead. Direct mirror of the earlier
  LibreVmmResetApp fix (#039). **Severity: high.**
- **#045** `BdsPlatform.c` — new fw_cfg gate
  `opt/libre-vmm/auto-enroll-default-keys`. Size-bounded ASCII read
  (16-byte cap), trailing-whitespace trim, case-insensitive allowlist
  (`1` / `y` / `yes` / `true` / `on`). Setup-mode + opted-in registers
  the `EnrollDefaultKeys` boot option as before; Setup-mode + NOT
  opted-in logs a diagnostic and skips (Setup Mode stays Setup Mode).
  User-mode unchanged. **Severity: med.**
- **#085** `BdsPlatform.c` — removed the dead BdsPlatform read of
  `opt/libre-vmm/vm-name` since the value now has a real consumer in
  SmbiosPlatformDxe (#088). Reduces fw_cfg attack surface without
  breaking the host-side `-fw_cfg name=opt/libre-vmm/vm-name,string=…`
  contract.

### Bug fixes

- **#039** `LibreVmmResetApp/LibreVmmReset.c` — `CpuDeadLoop()` after
  `ResetSystem` so a broken-platform return cannot silently chain to
  next BootOrder entry. Mirror later shipped for the shutdown app
  (#081).
- **#040** `BdsPlatform.c` — removed dead `display-width` +
  `display-height` fw_cfg reads (DEBUG-printed but never wired to
  `PcdVideoResolution`). Reduces fw_cfg attack surface.
- **#082** `BdsPlatform.c` — F12 keybinding comment + banner
  ("F12 for Network Boot") were lies; binding maps to
  `EfiBootManagerGetBootManagerMenu` (same as F2 / ESC). Renamed
  comment + banner ("ESC or F12 for Boot Menu") to match actual
  behavior. `TODO(libreuefi)` annotates the wire-to-PXE/HTTP follow-up.
- **#083** `OvmfPkgX64.fdf` — `EnrollDefaultKeys.inf` FFS entry now
  gated `!if $(SECURE_BOOT_ENABLE) == TRUE` / `!endif` to match the
  DSC `[Components]` condition.
  `-D SECURE_BOOT_ENABLE=FALSE` builds no longer fail with
  "FDF references INF that DSC didn't compile."

### Style / hygiene

- **#089** `BdsPlatform.c` — boot-timeout fw_cfg read wrapped in scoped
  block with `CHAR8 BootTimeoutStr[16]` + `UINTN TimeoutValue` declared
  at the block's top. Satisfies EDK2 EccCheck's
  `ec_naming_convention` declaration-before-statement rule.

### Vetoed / not shipped (recorded for posterity)

- **V18 / R6.F6** TDX HOB-walk `PhysicalEnd=0` writeback in
  `SecTdxHelper.c` — real bug but upstream EDK2 behavior, not
  fork-introduced. Filed against tianocore; libre-uefi does not carry
  a divergent patch.
- **V19 / R6.F7** `LibreVmmAcpi.asl` `_BST.State=0` was flagged as
  ambiguous; per ACPI 6.5 §10.2.2.6, `State=0` with `_PSR=1` is the
  canonical "full / idle on AC" encoding. Non-bug.
- **V25 / R8b.F7** `AmdSev.c:353` comma-operator typo-class hazard —
  `ApicId = …, SevSnpCreateSaveArea(…)` is valid C; comma operator
  returns the RHS value and produces the call's args in order. Not
  fork-introduced. Style nit only.

---

## Strategic items deferred to later releases

The following items appeared in the libre-vmm audit log as strategic
proposals for LibreUEFI but were intentionally deferred:

- **S01** Host-side test harness that boots OVMF with prepared fw_cfg
  payloads and log-greps for expected output. Every R1-uefi / R6-uefi
  finding becomes a regression test for 1 shell script + 1 log grep.
- **S02** EDK2 `PACKAGES_PATH` overlay — eliminate inline EDK2 patches
  by hosting our additions as `LibreUefiPkg/Override/…`. Single
  highest-leverage change identified in any LibreUEFI audit round.
  Closes the patch-rebase pain when bumping the upstream EDK2 pin.
  ~1-day one-time cost.
- **S12** `LibreFwCfgLib` — typed fw_cfg wrapper exposing
  `LibreFwCfgReadAsciiString` / `ReadBoundedUintn` / `ReadBool`. Kills
  NUL + non-printable smuggling across the fw_cfg trust boundary;
  replaces the 2 existing patterns + the new #045 third pattern. ~+80
  LOC of C; breaks even at 3 callers.
- **S16** Host-side AML / struct validator. Shell scripts at
  `tests/architectural/` run against `output/OVMF_CODE.fd` and assert:
  FFS GUIDs present, AML disassembles cleanly, branding strings
  survive upstream sync, no dead fw_cfg reads (regression guard for
  #040 + R6.F3), shutdown app has `CpuDeadLoop` (regression guard for
  #081). ~+150 shell. 1 day vs. S01 full's 3-5. No QEMU run required.
