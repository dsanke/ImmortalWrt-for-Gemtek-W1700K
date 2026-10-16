RAMFS_COPY_BIN='fitblk fit_check_sign'

REQUIRE_IMAGE_METADATA=1

. /lib/upgrade/gemtek-ubi.sh

airoha_require_ubi_layout()
{
	local ubidev volume fip_volume

	ubidev="$(nand_find_ubi ubi)"
	[ -n "$ubidev" ] || {
		echo "UBI is not initialized; create the base volumes from U-Boot recovery."
		return 1
	}

	for volume in fip ubootenv ubootenv2 "$@"; do
		if ! nand_find_volume "$ubidev" "$volume" >/dev/null; then
			echo "UBI base volume $volume is missing; repair the layout from U-Boot recovery."
			return 1
		fi
	done

	fip_volume="$(nand_find_volume "$ubidev" fip)"
	[ "$(cat "/sys/class/ubi/$fip_volume/data_bytes")" -gt 0 ] || {
		echo "The fip volume does not contain BL31/U-Boot; install the boot chain first."
		return 1
	}
}

nokia_initial_setup()
{
	[ "$(rootfs_type)" = "tmpfs" ] || return 0

	fw_setenv bootcmd "flash read 0xc0000 0x800000 0x85000000; bootm 0x85000000"
}

platform_check_image() {
	local board=$(board_name)

	[ "$#" -gt 1 ] && return 1

	case "$board" in
	gemtek,w1700k-ubi|\
	gemtek,xr1710g-ubi)
		# Clean UBI installation does not persist OpenWrt's generic
		# compat_version marker. Decide upgrade safety from the real flash
		# layout instead. Old BMT/BBT layouts are never written.
		xr_mtd_size_is() {
			awk -v label="$1" -v expected="$2" '
				$4 == "\"" label "\"" && tolower($2) == expected { found = 1 }
				END { exit(found ? 0 : 1) }
			' /proc/mtd 2>/dev/null
		}
		if ! xr_mtd_size_is vendor 00600000 || \
		   ! xr_mtd_size_is chainloader 00100000 || \
		   ! xr_mtd_size_is ubi 1b700000 || \
		   ! xr_mtd_size_is reserved_bmt 04200000; then
			echo "XR1710G/W1700K UBI 2.0 boundaries are not active; refusing normal sysupgrade." >&2
			echo "Install the corrected chainloader/U-Boot and recreate UBI through recovery first." >&2
			return 1
		fi
		fit_check_image "$1"
		return $?
		;;
	nokia,xg-040g-md)
		nand_do_platform_check "$board" "$1"
		return $?
		;;
	gemtek,xg2010g-ubi|\
	gemtek,xg2010g|\
	gemtek,xg2010g-2g-ubi|\
	gemtek,xg2010g-2g|\
	gemtek,xr1710g-ubi)
		gemtek_ubi_layout_check "$board" || {
			echo "Unsupported Gemtek UBI layout; refusing sysupgrade."
			return 1
		}
		fit_check_image "$1"
		return $?
		;;
	nokia,xg-040g-md-ubi|\
	nokia,xg-040g-tf-ubi|\
	quantum,q1000k-ubi)
		fit_check_image "$1"
		return $?
		;;
	esac

	return 0
}

platform_do_upgrade() {
	local board=$(board_name)

	case "$board" in
		gemtek,xg2010g-ubi|\
		gemtek,xg2010g|\
		gemtek,xg2010g-2g-ubi|\
		gemtek,xg2010g-2g|\
		gemtek,xr1710g-ubi)
			gemtek_ubi_layout_check "$board" &&
				airoha_require_ubi_layout factory && fit_do_upgrade "$1"
			;;
		gemtek,w1700k-ubi|\
		gemtek,xr1710g|\
		nokia,xg-040g-md-ubi|\
		nokia,xg-040g-tf-ubi|\
		quantum,q1000k-ubi)
			case "$board" in
				nokia,xg-040g-md-ubi|nokia,xg-040g-tf-ubi)
					airoha_require_ubi_layout bosa ri && fit_do_upgrade "$1"
					;;
				*)
					fit_do_upgrade "$1"
					;;
			esac
			;;
		gemtek,xr1710g-ubi)
			fit_do_upgrade "$1"
			;;
		*)
			nand_do_upgrade "$1"
			;;
	esac
}

platform_pre_upgrade() {
	local board=$(board_name)

	case "$board" in
	nokia,xg-040g-md)
		nokia_initial_setup
		;;
	*)
		;;
	esac
}
