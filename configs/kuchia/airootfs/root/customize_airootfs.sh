#!/bin/bash
set -e

if [[ -f /root/os-release.kuchia ]]; then
    cp /root/os-release.kuchia /usr/lib/os-release
    rm /root/os-release.kuchia
fi

# Kuchia: auto copy-to-RAM when the system has ~3 GiB of RAM or more
# (upstream archiso only enables copytoram=auto when RAM > image + 2 GiB)
hook=/usr/lib/initcpio/hooks/archiso
if ! grep -q 'MemTotal:' "$hook"; then
    sed_script="$(mktemp)"
    cat >"${sed_script}" <<'SEDEOF'
/estimated available memory/c\
    # * the system has ~3 GiB of RAM or more, and the image fits in the tmpfs (Kuchia)
/MemAvailable:.*fs_img_size + 2097152/c\
            if [ "$fs_img_size" -lt 4194304 ] && [ "$(awk '$1 == "MemTotal:" { print $2 }' /proc/meminfo)" -ge 2800000 ] && [ "$fs_img_size" -lt "$(( $(awk '$1 == "MemTotal:" { print $2 }' /proc/meminfo) * 3 / 4 ))" ]; then
SEDEOF
    sed -i -f "${sed_script}" "$hook"
    rm -f "${sed_script}"
fi
if ! grep -q 'MemTotal:' "$hook"; then
    echo "ERROR: failed to patch copytoram auto condition in ${hook}" >&2
    exit 1
fi

# Regenerate the initramfs so the patched hook is used at boot.
# Kuchia does not ship nbd, so the archiso_pxe_nbd hook reports
# "binary not found"; mkinitcpio still writes the image. Tolerate that one
# known error, but fail on anything else or if the image was not rewritten.
image=/boot/initramfs-linux-zen.img
mkinitcpio_log="$(mktemp)"
mkinitcpio_stamp="$(mktemp)"
if ! mkinitcpio -P >"${mkinitcpio_log}" 2>&1; then
    other_errors="$(grep '^==> ERROR' "${mkinitcpio_log}" | grep -vF "binary not found: 'nbd-client'" || true)"
    if [[ -z "${other_errors}" ]] && ! [[ "${mkinitcpio_stamp}" -nt "${image}" ]]; then
        echo ":: mkinitcpio: only known nbd-client error (pxe-nbd unsupported in Kuchia), image rewritten" >&2
    else
        cat "${mkinitcpio_log}"
        echo "ERROR: mkinitcpio failed" >&2
        rm -f "${mkinitcpio_log}" "${mkinitcpio_stamp}"
        exit 1
    fi
fi
rm -f "${mkinitcpio_log}" "${mkinitcpio_stamp}"
