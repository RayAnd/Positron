// SPDX-License-Identifier: MIT
#include "mp_prefix_migrator.h"
#include "mp_pe_patcher.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/clonefile.h>
#include <sys/mount.h>
#include <sys/param.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

static int mkdir_p(const char *path) {
    char tmp[1024];
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (len == 0) return -1;
    if (tmp[len - 1] == '/') tmp[len - 1] = '\0';
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    struct stat st;
    if (stat(tmp, &st) == 0 && S_ISDIR(st.st_mode)) return 0;
    return mkdir(tmp, 0755);
}

int mp_inspect_volume(const char *path, mp_volume_info_t *out_vol) {
    if (!path || !path[0] || !out_vol) return -1;
    memset(out_vol, 0, sizeof(*out_vol));

    // Walk up to an existing ancestor directory so statfs succeeds even before pfx is created
    char probe[1024];
    snprintf(probe, sizeof(probe), "%s", path);
    struct statfs sfs;
    while (statfs(probe, &sfs) != 0) {
        char *slash = strrchr(probe, '/');
        if (!slash || slash == probe) {
            if (statfs("/", &sfs) != 0) return -1;
            break;
        }
        *slash = '\0';
    }

    snprintf(out_vol->fstype_name, sizeof(out_vol->fstype_name), "%s", sfs.f_fstypename);
    snprintf(out_vol->mount_point, sizeof(out_vol->mount_point), "%s", sfs.f_mntonname);
    out_vol->is_external_volume = (strncmp(sfs.f_mntonname, "/Volumes/", 9) == 0);

    if (strcasecmp(sfs.f_fstypename, "apfs") == 0) {
        out_vol->kind = MP_FS_APFS;
        out_vol->needs_apfs_shadow_prefix = false;
    } else if (strcasecmp(sfs.f_fstypename, "hfs") == 0) {
        out_vol->kind = MP_FS_HFS;
        out_vol->needs_apfs_shadow_prefix = false;
    } else if (strcasecmp(sfs.f_fstypename, "exfat") == 0) {
        out_vol->kind = MP_FS_EXFAT;
        out_vol->needs_apfs_shadow_prefix = true;
    } else if (strcasecmp(sfs.f_fstypename, "ntfs") == 0 ||
               strcasecmp(sfs.f_fstypename, "ufsd_ntfs") == 0 ||
               strcasecmp(sfs.f_fstypename, "tuxera_ntfs") == 0 ||
               strcasecmp(sfs.f_fstypename, "msdos") == 0) {
        out_vol->kind = MP_FS_NTFS;
        out_vol->needs_apfs_shadow_prefix = true;
    } else {
        out_vol->kind = MP_FS_OTHER;
        out_vol->needs_apfs_shadow_prefix = false;
    }

    return 0;
}

int mp_resolve_effective_prefix_dir(const char *compat_data_dir,
                                    uint32_t app_id,
                                    const char *shadow_base_dir,
                                    mp_fs_kind_t override_fs_kind,
                                    char *out_pfx_dir,
                                    size_t pfx_cap,
                                    bool *out_using_shadow) {
    if (!compat_data_dir || !out_pfx_dir || pfx_cap == 0) return -1;
    if (out_using_shadow) *out_using_shadow = false;

    mp_volume_info_t vol = {0};
    if (override_fs_kind != MP_FS_APFS) {
        vol.kind = override_fs_kind;
        vol.needs_apfs_shadow_prefix = (override_fs_kind == MP_FS_EXFAT || override_fs_kind == MP_FS_NTFS);
    } else {
        mp_inspect_volume(compat_data_dir, &vol);
    }

    if (vol.needs_apfs_shadow_prefix && shadow_base_dir && shadow_base_dir[0]) {
        snprintf(out_pfx_dir, pfx_cap, "%s/%u/pfx", shadow_base_dir, app_id);
        if (mkdir_p(out_pfx_dir) != 0) return -1;
        if (out_using_shadow) *out_using_shadow = true;
        return 0;
    }

    snprintf(out_pfx_dir, pfx_cap, "%s/pfx", compat_data_dir);
    if (mkdir_p(out_pfx_dir) != 0) return -1;
    return 0;
}

int mp_prefix_ensure_steamuser_layout(const char *pfx_dir) {
    if (!pfx_dir || !pfx_dir[0]) return -1;

    static const char *const user_dirs[] = {
        "drive_c/users/steamuser/Documents",
        "drive_c/users/steamuser/Desktop",
        "drive_c/users/steamuser/AppData/Local",
        "drive_c/users/steamuser/AppData/Roaming",
        "drive_c/users/steamuser/Saved Games",
        "drive_c/windows/system32",
        "drive_c/windows/syswow64",
        "dosdevices"
    };

    char path[1024];
    for (size_t i = 0; i < sizeof(user_dirs) / sizeof(user_dirs[0]); i++) {
        snprintf(path, sizeof(path), "%s/%s", pfx_dir, user_dirs[i]);
        if (mkdir_p(path) != 0) return -1;
    }

    char crossover_link[1024];
    snprintf(crossover_link, sizeof(crossover_link), "%s/drive_c/users/crossover", pfx_dir);
    struct stat st;
    if (lstat(crossover_link, &st) != 0) {
        symlink("steamuser", crossover_link);
    }

    char alias_path[1024];
    snprintf(alias_path, sizeof(alias_path), "%s/drive_c/users/steamuser/My Documents", pfx_dir);
    if (lstat(alias_path, &st) != 0) symlink("./Documents", alias_path);

    snprintf(alias_path, sizeof(alias_path), "%s/drive_c/users/steamuser/Application Data", pfx_dir);
    if (lstat(alias_path, &st) != 0) symlink("./AppData/Roaming", alias_path);

    // Ensure dosdevices/c: and z: exist
    snprintf(alias_path, sizeof(alias_path), "%s/dosdevices/c:", pfx_dir);
    if (lstat(alias_path, &st) != 0) symlink("../drive_c", alias_path);
    snprintf(alias_path, sizeof(alias_path), "%s/dosdevices/z:", pfx_dir);
    if (lstat(alias_path, &st) != 0) symlink("/", alias_path);

    return 0;
}

int mp_prefix_read_stamp(const char *compat_data_dir, mp_prefix_stamp_t *out_stamp) {
    if (!compat_data_dir || !out_stamp) return -1;
    memset(out_stamp, 0, sizeof(*out_stamp));

    char stamp_file[1024];
    snprintf(stamp_file, sizeof(stamp_file), "%s/mineproton-prefix.stamp", compat_data_dir);
    FILE *f = fopen(stamp_file, "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            line[strcspn(line, "\r\n")] = '\0';
            if (strncmp(line, "runner_id=", 10) == 0) {
                snprintf(out_stamp->runner_id, sizeof(out_stamp->runner_id), "%s", line + 10);
            } else if (strncmp(line, "arch=", 5) == 0) {
                snprintf(out_stamp->arch, sizeof(out_stamp->arch), "%s", line + 5);
            } else if (strncmp(line, "graphics=", 9) == 0) {
                snprintf(out_stamp->graphics, sizeof(out_stamp->graphics), "%s", line + 9);
            }
        }
        fclose(f);
        if (out_stamp->runner_id[0] && out_stamp->arch[0]) return 0;
    }

    char ntdll_path[1024];
    snprintf(ntdll_path, sizeof(ntdll_path), "%s/pfx/drive_c/windows/system32/ntdll.dll", compat_data_dir);
    mp_ntdll_analysis_t pe_info = {0};
    if (mp_ntdll_analyze_file(ntdll_path, 64, &pe_info) == 0) {
        snprintf(out_stamp->runner_id, sizeof(out_stamp->runner_id), "legacy-untracked");
        snprintf(out_stamp->arch, sizeof(out_stamp->arch), "%s",
                 pe_info.arch == MP_PE_ARCH_ARM64 ? "arm64" : "x86_64");
        snprintf(out_stamp->graphics, sizeof(out_stamp->graphics), "d3dmetal");
        return 0;
    }

    return -1;
}

static int write_stamp(const char *compat_data_dir, const mp_prefix_stamp_t *stamp) {
    char stamp_file[1024];
    snprintf(stamp_file, sizeof(stamp_file), "%s/mineproton-prefix.stamp", compat_data_dir);
    FILE *f = fopen(stamp_file, "w");
    if (!f) return -1;
    fprintf(f, "runner_id=%s\narch=%s\ngraphics=%s\n",
            stamp->runner_id, stamp->arch,
            stamp->graphics[0] ? stamp->graphics : "d3dmetal");
    fclose(f);
    return 0;
}

int mp_prefix_reconcile_and_migrate(const char *compat_data_dir,
                                    const mp_prefix_stamp_t *target_stamp,
                                    mp_migration_action_t *out_action,
                                    char *out_backup_path,
                                    size_t backup_path_cap) {
    if (!compat_data_dir || !target_stamp || !target_stamp->runner_id[0] || !target_stamp->arch[0]) {
        return -1;
    }
    if (out_action) *out_action = MP_MIGRATE_NONE;
    if (out_backup_path && backup_path_cap > 0) out_backup_path[0] = '\0';

    char pfx_dir[1024];
    snprintf(pfx_dir, sizeof(pfx_dir), "%s/pfx", compat_data_dir);
    if (mp_prefix_ensure_steamuser_layout(pfx_dir) != 0) return -1;

    mp_prefix_stamp_t current = {0};
    if (mp_prefix_read_stamp(compat_data_dir, &current) != 0) {
        if (write_stamp(compat_data_dir, target_stamp) != 0) return -1;
        if (out_action) *out_action = MP_MIGRATE_INITIALIZED;
        return 0;
    }

    bool arch_changed   = (strcmp(current.arch, target_stamp->arch) != 0);
    bool runner_changed = (strcmp(current.runner_id, target_stamp->runner_id) != 0);

    if (!arch_changed && !runner_changed) {
        if (strcmp(current.graphics, target_stamp->graphics) != 0) {
            write_stamp(compat_data_dir, target_stamp);
        }
        return 0;
    }

    char snap_dir[1024];
    snprintf(snap_dir, sizeof(snap_dir), "%s/steamuser.snapshot.%s.%s",
             compat_data_dir, current.runner_id, current.arch);
    unlink(snap_dir);

    char steamuser_dir[1024];
    snprintf(steamuser_dir, sizeof(steamuser_dir), "%s/drive_c/users/steamuser", pfx_dir);

    if (clonefile(steamuser_dir, snap_dir, 0) != 0) {
        char cmd[2560];
        snprintf(cmd, sizeof(cmd), "rm -rf '%s' && cp -R '%s' '%s' 2>/dev/null",
                 snap_dir, steamuser_dir, snap_dir);
        system(cmd);
    }

    if (out_backup_path && backup_path_cap > 0) {
        snprintf(out_backup_path, backup_path_cap, "%s", snap_dir);
    }

    if (arch_changed) {
        char stale_ntdll[1024];
        snprintf(stale_ntdll, sizeof(stale_ntdll), "%s/drive_c/windows/system32/ntdll.dll", pfx_dir);
        unlink(stale_ntdll);
    }

    char update_ts[1024];
    snprintf(update_ts, sizeof(update_ts), "%s/.update-timestamp", pfx_dir);
    unlink(update_ts);

    if (write_stamp(compat_data_dir, target_stamp) != 0) return -1;
    if (out_action) {
        *out_action = arch_changed ? MP_MIGRATE_ARCH_TRANSITIONED : MP_MIGRATE_RUNNER_UPGRADED;
    }
    return 0;
}