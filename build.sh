#!/bin/bash
# Build LibreUEFI firmware — fork of OVMF tailored for libre-vmm.
#
# Produces output/LIBREUEFI_CODE.fd + output/LIBREUEFI_VARS.fd from the
# `edk2/` working tree using the GCCNOLTO toolchain. The script is
# idempotent + safe to re-run; pass `-D SECURE_BOOT_ENABLE` (or omit it)
# to flip the secure-boot build. See docs/TOOLCHAIN.md for the
# rationale on toolchain choice + known gotchas.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EDK2_DIR="$SCRIPT_DIR/edk2"
OUTPUT_DIR="$SCRIPT_DIR/output"

# Check dependencies
for cmd in gcc g++ nasm iasl python3 make; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "[!] Missing: $cmd"
        echo "    See docs/TOOLCHAIN.md for the full apt / dnf package list."
        exit 1
    fi
done

echo "[*] Building LibreUEFI (custom OVMF for Libre VMM)..."

cd "$EDK2_DIR"

# Build BaseTools (idempotent — make's mtime check skips when already
# built). Without this, `build` exits at "File open failure:
# build_rule.txt" because the BaseTools binaries that resolve
# Conf paths aren't on PATH.
make -C BaseTools -j"$(nproc)" 2>&1 | tail -3
source edksetup.sh

# Configure build target. GCCNOLTO is the supported "modern GCC, LTO
# disabled" profile — GCC5 doesn't link on stock GCC 13. The
# BUILD_RULE_CONF line is REQUIRED — without it, `build` aborts at
# "error 0001: File open failure: build_rule.txt" because it
# defaults to opening the literal string `build_rule.txt` as a
# relative path. (See docs/TOOLCHAIN.md.)
cat > Conf/target.txt << 'EOF'
ACTIVE_PLATFORM       = OvmfPkg/OvmfPkgX64.dsc
TARGET                = RELEASE
TARGET_ARCH           = X64
TOOL_CHAIN_TAG        = GCCNOLTO
MAX_CONCURRENT_THREAD_NUMBER = 0
BUILD_RULE_CONF       = Conf/build_rule.txt
EOF

# Build OVMF.
#
# Feature flags (intentionally narrow vs. upstream OVMF's full set):
# - FD_SIZE_4MB — 4 MiB CODE volume (enough headroom for our DXE/UEFI
#   additions; matches the upstream OVMF "large" default).
# - TPM_ENABLE — required for Windows 11 TPM 2.0 attestation (libre-vmm
#   wires swtpm for guests that select it).
# - SECURE_BOOT_ENABLE — required for Windows 11 Secure Boot. CI also
#   verifies the SECURE_BOOT_ENABLE=FALSE path (omit the flag here).
#
# Deliberately OMITTED:
# - NETWORK_HTTP_BOOT_ENABLE / IP6 / TLS — modern GCC's
#   -Werror=maybe-uninitialized triggers on upstream
#   `CryptoPkg/Library/TlsLib/TlsConfig.c:266`. Re-enabling requires
#   cherry-picking the upstream tianocore fix; see docs/TOOLCHAIN.md.
#   libre-vmm doesn't currently use HTTPS Boot from firmware level.
build -a X64 -t GCCNOLTO -p OvmfPkg/OvmfPkgX64.dsc -b RELEASE \
    -D FD_SIZE_4MB \
    -D TPM_ENABLE \
    -D SECURE_BOOT_ENABLE \
    -n "$(nproc)"

# Copy output. Build/ paths use the active toolchain tag, so GCCNOLTO
# here matches what we pass to `build` above.
mkdir -p "$OUTPUT_DIR"
cp Build/OvmfX64/RELEASE_GCCNOLTO/FV/OVMF_CODE.fd "$OUTPUT_DIR/LIBREUEFI_CODE.fd"
cp Build/OvmfX64/RELEASE_GCCNOLTO/FV/OVMF_VARS.fd "$OUTPUT_DIR/LIBREUEFI_VARS.fd"
cp Build/OvmfX64/RELEASE_GCCNOLTO/FV/OVMF.fd "$OUTPUT_DIR/LIBREUEFI.fd"

echo ""
echo "[*] Build complete!"
echo "    CODE: $OUTPUT_DIR/LIBREUEFI_CODE.fd"
echo "    VARS: $OUTPUT_DIR/LIBREUEFI_VARS.fd"
echo "    FULL: $OUTPUT_DIR/LIBREUEFI.fd"
echo ""
echo "    To consume from libre-vmm, install to /usr/share/libreuefi/"
echo "    or set vmm-gui Preferences > Firmware path to the OUTPUT path."
