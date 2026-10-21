// SPDX-License-Identifier: MIT
#include "mp_supervisor.h"
#include "mp_reg_editor.h"
#include "mp_prefix_migrator.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void env_set(mp_env_block_t *env, const char *key, const char *val) {
    if (!env || !key || !val) return;
    for (size_t i = 0; i < env->count; i++) {
        if (strcmp(env->pairs[i].key, key) == 0) {
            snprintf(env->pairs[i].value, sizeof(env->pairs[i].value), "%s", val);
            return;
        }
    }
    if (env->count < sizeof(env->pairs) / sizeof(env->pairs[0])) {
        snprintf(env->pairs[env->count].key, sizeof(env->pairs[0].key), "%s", key);
        snprintf(env->pairs[env->count].value, sizeof(env->pairs[0].value), "%s", val);
        env->count++;
    }
}

const char *mp_env_block_get(const mp_env_block_t *env, const char *key) {
    if (!env || !key) return NULL;
    for (size_t i = 0; i < env->count; i++) {
        if (strcmp(env->pairs[i].key, key) == 0) {
            return env->pairs[i].value;
        }
    }
    return NULL;
}

int mp_supervisor_configure_prefix_hives(const mp_launch_config_t *cfg) {
    if (!cfg || !cfg->compat_data_path[0]) return -1;

    char pfx_dir[1024];
    snprintf(pfx_dir, sizeof(pfx_dir), "%s/pfx", cfg->compat_data_path);
    if (mp_prefix_ensure_steamuser_layout(pfx_dir) != 0) return -1;

    char system_reg[1024];
    char user_reg[1024];
    snprintf(system_reg, sizeof(system_reg), "%s/system.reg", pfx_dir);
    snprintf(user_reg, sizeof(user_reg), "%s/user.reg", pfx_dir);

    const mp_reg_mutation_t sys_muts[] = {
        {
            .section = "Software\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\AeDebug",
            .key     = "\"Auto\"",
            .value   = "\"0\""
        },
        {
            .section = "Software\\\\Wow6432Node\\\\Microsoft\\\\Windows NT\\\\CurrentVersion\\\\AeDebug",
            .key     = "\"Auto\"",
            .value   = "\"0\""
        },
        {
            .section = "Software\\\\Valve\\\\Steam",
            .key     = "\"InstallPath\"",
            .value   = "\"C:\\\\Program Files (x86)\\\\Steam\""
        },
        {
            .section = "System\\\\CurrentControlSet\\\\Services\\\\WineBus",
            .key     = "\"DisableHidraw\"",
            .value   = cfg->disable_hidraw ? "dword:00000001" : "-"
        }
    };

    if (mp_reg_apply_mutations_file(system_reg, sys_muts,
                                    sizeof(sys_muts) / sizeof(sys_muts[0])) != 0) {
        return -1;
    }

    const mp_reg_mutation_t user_muts[] = {
        {
            .section = "Software\\\\Wine\\\\WineDbg",
            .key     = "\"ShowCrashDialog\"",
            .value   = "dword:00000000"
        },
        {
            .section = "Software\\\\Wine\\\\Mac Driver",
            .key     = "\"RetinaMode\"",
            .value   = cfg->retina_mode ? "\"y\"" : "\"n\""
        },
        {
            .section = "Control Panel\\\\Desktop",
            .key     = "\"LogPixels\"",
            .value   = cfg->retina_mode ? "dword:000000c0" : "dword:00000060"
        }
    };

    if (mp_reg_apply_mutations_file(user_reg, user_muts,
                                    sizeof(user_muts) / sizeof(user_muts[0])) != 0) {
        return -1;
    }

    return 0;
}

int mp_supervisor_map_game_drive(const char *pfx_dir,
                                 const char *install_path,
                                 const char *library_paths,
                                 char *out_mapped_target,
                                 size_t target_cap) {
    if (!pfx_dir || !install_path || !install_path[0]) return -1;

    char best_lib[1024] = {0};
    if (library_paths && library_paths[0]) {
        char libs_copy[1024];
        snprintf(libs_copy, sizeof(libs_copy), "%s", library_paths);
        char *save = NULL;
        for (char *tok = strtok_r(libs_copy, ":", &save); tok; tok = strtok_r(NULL, ":", &save)) {
            size_t tlen = strlen(tok);
            while (tlen > 1 && tok[tlen - 1] == '/') tok[--tlen] = '\0';
            if (tlen == 0) continue;
            if (strncmp(install_path, tok, tlen) == 0 &&
                (install_path[tlen] == '/' || install_path[tlen] == '\0')) {
                if (tlen > strlen(best_lib)) {
                    snprintf(best_lib, sizeof(best_lib), "%s", tok);
                }
            }
        }
    }

    // Fallback: infer external/internal library root from <LibraryRoot>/steamapps/common/<Game>
    if (!best_lib[0]) {
        const char *marker = strstr(install_path, "/steamapps/common/");
        if (marker && marker > install_path) {
            size_t len = (size_t)(marker - install_path);
            if (len < sizeof(best_lib)) {
                memcpy(best_lib, install_path, len);
                best_lib[len] = '\0';
            }
        }
    }

    if (!best_lib[0]) return -1;

    char dosdevices[1024];
    snprintf(dosdevices, sizeof(dosdevices), "%s/dosdevices", pfx_dir);
    mkdir(dosdevices, 0755);

    char s_drive[1024];
    snprintf(s_drive, sizeof(s_drive), "%s/s:", dosdevices);
    unlink(s_drive);
    if (symlink(best_lib, s_drive) != 0) return -1;

    if (out_mapped_target && target_cap > 0) {
        snprintf(out_mapped_target, target_cap, "%s", best_lib);
    }
    return 0;
}

int mp_supervisor_build_environment(const mp_launch_config_t *cfg,
                                    mp_env_block_t *out_env) {
    if (!cfg || !out_env) return -1;
    memset(out_env, 0, sizeof(*out_env));

    char pfx[1024];
    snprintf(pfx, sizeof(pfx), "%s/pfx", cfg->compat_data_path);
    env_set(out_env, "WINEPREFIX", pfx);
    env_set(out_env, "CX_ROOT", cfg->cx_root);
    env_set(out_env, "WINEMSYNC", cfg->msync ? "1" : "0");
    env_set(out_env, "WINEDEBUG", "-all");

    const char *unix_dir = (cfg->translator == MP_XLATE_FEX) ? "aarch64-unix" : "x86_64-unix";
    char loader[1024];
    char server[1024];
    if (cfg->translator == MP_XLATE_FEX) {
        snprintf(loader, sizeof(loader), "%s/lib/wine/%s/wine.app/Contents/MacOS/wine",
                 cfg->cx_root, unix_dir);
        snprintf(server, sizeof(server), "%s/bin/wineserver-arm64", cfg->cx_root);
    } else {
        snprintf(loader, sizeof(loader), "%s/lib/wine/%s/wine", cfg->cx_root, unix_dir);
        snprintf(server, sizeof(server), "%s/bin/wineserver", cfg->cx_root);
    }
    env_set(out_env, "WINELOADER", loader);
    env_set(out_env, "WINESERVER", server);

    mp_graphics_backend_t gfx = cfg->graphics;
    if (cfg->translator == MP_XLATE_FEX && gfx == MP_GFX_D3DMETAL) {
        gfx = MP_GFX_DXMT;
    }

    switch (gfx) {
        case MP_GFX_D3DMETAL:
            env_set(out_env, "CX_GRAPHICS_BACKEND", "d3dmetal");
            break;
        case MP_GFX_DXMT:
            env_set(out_env, "CX_GRAPHICS_BACKEND", "dxmt");
            break;
        case MP_GFX_DXVK:
            env_set(out_env, "CX_GRAPHICS_BACKEND", "dxvk");
            break;
        case MP_GFX_WINED3D:
            env_set(out_env, "CX_GRAPHICS_BACKEND", "wined3d");
            break;
    }

    if (cfg->translator == MP_XLATE_FEX) {
        env_set(out_env, "FEX_X87REDUCEDPRECISION", "1");
    } else if (cfg->advertise_avx) {
        env_set(out_env, "ROSETTA_ADVERTISE_AVX", "1");
    }

    if (cfg->metal_hud) {
        env_set(out_env, "MTL_HUD_ENABLED", "1");
        if (gfx == MP_GFX_DXMT) {
            env_set(out_env, "DXMT_HUD", "fps,devinfo");
        }
    }

    char overrides[512] = "steamclient=n;steamclient64=n;lsteamclient=b";
    if (cfg->app_id == 38410) {
        strncat(overrides, ";ddraw=n,b;dinput=n,b;dinput8=n,b",
                sizeof(overrides) - strlen(overrides) - 1);
    } else if (cfg->app_id == 292030 || cfg->app_id == 1091500 || cfg->app_id == 1245620 ||
               cfg->app_id == 1086940 || cfg->app_id == 3105440 || cfg->app_id == 323190 ||
               cfg->app_id == 1286830 || cfg->app_id == 412020) {
        strncat(overrides, ";vcruntime140=n,b;vcruntime140_1=n,b;msvcp140=n,b;d3dcompiler_47=n,b",
                sizeof(overrides) - strlen(overrides) - 1);
        if (cfg->translator == MP_XLATE_ROSETTA) {
            env_set(out_env, "ROSETTA_ADVERTISE_AVX", "1");
        }
    } else if (cfg->app_id == 1151340 || cfg->app_id == 377160 || cfg->app_id == 489830) {
        strncat(overrides, ";xaudio2_7=n,b;vcruntime140=n,b;vcruntime140_1=n,b;msvcp140=n,b;d3dcompiler_47=n,b",
                sizeof(overrides) - strlen(overrides) - 1);
        if (cfg->translator == MP_XLATE_ROSETTA) {
            env_set(out_env, "ROSETTA_ADVERTISE_AVX", "1");
        }
    }
    env_set(out_env, "WINEDLLOVERRIDES", overrides);

    char app_id_str[32];
    snprintf(app_id_str, sizeof(app_id_str), "%u", cfg->app_id);
    env_set(out_env, "SteamAppId", app_id_str);
    env_set(out_env, "SteamGameId", app_id_str);

    return 0;
}