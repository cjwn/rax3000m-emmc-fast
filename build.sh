#!/usr/bin/env bash
set -euo pipefail
usage() {
  cat <<'EOF'
Usage: ./build.sh [--frequency 26|52] [--mode highspeed|legacy]
                  [--stage prepare|build] [--jobs N] [--accept-52mhz-risk]
Defaults: 26 MHz highspeed, build, 2 jobs.
prepare: fetch pinned source/feeds, patch device tree, create .config.
build: prepare if needed, download sources and compile; never flashes a router.
Use a separate build directory for each frequency/mode. Resume with the same arguments.
EOF
}
freq=26; mode=highspeed; stage=build; jobs=2; risk=no
while (($#)); do
  case "$1" in
    --frequency|--mode|--stage|--jobs)
      (($# >= 2)) || { usage; exit 2; }
      case "$1" in
        --frequency) freq=$2;; --mode) mode=$2;; --stage) stage=$2;; --jobs) jobs=$2;;
      esac; shift 2;;
    --accept-52mhz-risk) risk=yes; shift;;
    -h|--help) usage; exit 0;;
    *) usage; exit 2;;
  esac
done
[[ $freq == 26 || $freq == 52 ]] || { usage; exit 2; }
[[ $mode == highspeed || $mode == legacy ]] || { usage; exit 2; }
[[ $stage == prepare || $stage == build ]] || { usage; exit 2; }
[[ $jobs =~ ^[1-9][0-9]*$ ]] || { usage; exit 2; }
[[ $freq != 52 || ( $risk == yes && $mode == highspeed ) ]] || {
  echo '52 MHz may cause eMMC I/O errors or boot failure. Add --accept-52mhz-risk explicitly.' >&2; exit 2;
}
[[ $(uname -s) == Linux && $EUID != 0 ]] || {
  echo 'Run as a normal user on Linux (Ubuntu 22.04/24.04 recommended), or use GitHub Actions.' >&2; exit 1;
}
for cmd in git make python3 gcc g++ rsync unzip curl; do
  command -v "$cmd" >/dev/null || { echo "Missing command: $cmd" >&2; exit 1; }
done
kit=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
work="$kit/work/24.10.2-${freq}-${mode}"
[[ $work != *[[:space:]]* ]] || { echo 'Build path must not contain whitespace'; exit 1; }
mkdir -p "$kit/work"
# Test the actual build filesystem, not the Mac host filesystem.
probe=$(mktemp -d "$kit/work/.case-test.XXXXXX")
touch "$probe/lower"
if [[ -e "$probe/LOWER" ]]; then rm -r "$probe"; echo 'Case-sensitive filesystem required'; exit 1; fi
rm -r "$probe"
commit=cee53da5b58c6241eced0ef17956adda5515634b
if [[ ! -e $work ]]; then
  git clone --depth 1 --branch v24.10.2 https://github.com/immortalwrt/immortalwrt.git "$work"
fi
[[ $(git -C "$work" rev-parse HEAD) == "$commit" ]] || { echo 'Source commit mismatch'; exit 1; }
cd "$work"
python3 "$kit/patch-emmc.py" "$work" --frequency "$freq" --mode "$mode"
# v24.10.2 already pins all four feeds by commit. Do not replace with rolling branches.
if [[ ! -f .codex-feeds-ready ]]; then
  ./scripts/feeds update -a
  ./scripts/feeds install -a
  touch .codex-feeds-ready
fi
if [[ ! -f .config ]]; then cp "$kit/seed.config" .config; fi
make defconfig
for symbol in TARGET_mediatek_filogic_DEVICE_cmcc_rax3000m PACKAGE_luci PACKAGE_luci-app-ksmbd PACKAGE_ksmbd-server; do
  grep -qx "CONFIG_${symbol}=y" .config || { echo "Required config not selected: $symbol"; exit 1; }
done
if [[ $stage == prepare ]]; then
  echo "Prepared: $work"
  echo 'Optional: run make menuconfig inside that directory, then run this script again with the same options.'
  exit 0
fi
mkdir -p "$kit/output/${freq}-${mode}"
out="$kit/output/${freq}-${mode}"
make -j"$jobs" download 2>&1 | tee "$out/download.log"
# Fail visibly: do not hide the original error behind an automatic rebuild.
make -j"$jobs" V=s 2>&1 | tee "$out/build.log"
images=bin/targets/mediatek/filogic
shopt -s nullglob
firmware=("$images"/*cmcc_rax3000m-squashfs-sysupgrade.itb)
((${#firmware[@]} == 1)) || { echo 'Expected exactly one RAX3000M sysupgrade image'; exit 1; }
cp "${firmware[0]}" "$out/"
cp .config "$out/full.config"
./scripts/diffconfig.sh > "$out/diffconfig"
git diff -- target/linux/mediatek/dts/mt7981b-cmcc-rax3000m-emmc.dtso > "$out/emmc.patch"
cp feeds.conf.default "$out/feeds.lock"
printf 'source=%s\nfrequency=%s MHz\nmode=%s\n' "$commit" "$freq" "$mode" > "$out/build-info.txt"
for feed in packages luci routing telephony; do
  printf '%s=%s\n' "$feed" "$(git -C "feeds/$feed" rev-parse HEAD)" >> "$out/build-info.txt"
done
(cd "$out" && sha256sum ./*.itb > SHA256SUMS)
echo "Build complete: $out (not flashed)"
