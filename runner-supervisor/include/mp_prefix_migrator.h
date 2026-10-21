// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_PREFIX_MIGRATOR_H
#define MINEPROTON_PREFIX_MIGRATOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MP_MIGRATE_NONE               = 0,
    MP_MIGRATE_INITIALIZED        = 1,
    MP_MIGRATE_RUNNER_UPGRADED    = 2,
    MP_MIGRATE_ARCH_TRANSITIONED  = 3
} mp_migration_action_t;

typedef enum {
    MP_FS_APFS  = 0, // Supports native POSIX symlinks, hardlinks, and clonefile(2)
    MP_FS_HFS   = 1, // Supports POSIX symlinks, no clonefile(2)
    MP_FS_EXFAT = 2, // No reliable Wine symlinks/server socket inodes -> needs APFS shadow prefix
    MP_FS_NTFS  = 3, // Needs APFS shadow prefix
    MP_FS_OTHER = 4
} mp_fs_kind_t;

typedef struct {
    mp_fs_kind_t kind;
    char         fstype_name[32];
    char         mount_point[512];
    bool         is_external_volume;
    bool         needs_apfs_shadow_prefix;
} mp_volume_info_t;

typedef struct {
    char runner_id[64];
    char arch[16];     // "x86_64" or "arm64"
    char graphics[32]; // "d3dmetal", "dxmt", "dxvk", "wined3d"
} mp_prefix_stamp_t;

// Inspects the mount point and filesystem type (APFS, ExFAT, NTFS, etc.) of a path.
int mp_inspect_volume(const char *path, mp_volume_info_t *out_vol);

// Resolves the effective WINEPREFIX directory for a game. On APFS (internal or external),
// uses <compat_data_dir>/pfx directly. On ExFAT/NTFS external drives (where Wine symlinks
// and wineserver inode locks fail), transparently redirects WINEPREFIX to a local APFS
// shadow directory under <shadow_base_dir>/<app_id>/pfx while keeping game data on S:!
int mp_resolve_effective_prefix_dir(const char *compat_data_dir,
                                    uint32_t app_id,
                                    const char *shadow_base_dir,
                                    mp_fs_kind_t override_fs_kind,
                                    char *out_pfx_dir,
                                    size_t pfx_cap,
                                    bool *out_using_shadow);

// Ensures the Steam Cloud user layout (drive_c/users/steamuser + crossover symlink)
// and standard profile folders exist without destructive overwrites.
int mp_prefix_ensure_steamuser_layout(const char *pfx_dir);

// Reads the current prefix stamp (or infers it from ntdll.dll PE machine type).
int mp_prefix_read_stamp(const char *compat_data_dir, mp_prefix_stamp_t *out_stamp);

// Automatically reconciles a game prefix when the user switches runners or switches
// between Rosetta (x86_64) and FEX (arm64).
int mp_prefix_reconcile_and_migrate(const char *compat_data_dir,
                                    const mp_prefix_stamp_t *target_stamp,
                                    mp_migration_action_t *out_action,
                                    char *out_backup_path,
                                    size_t backup_path_cap);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_PREFIX_MIGRATOR_H