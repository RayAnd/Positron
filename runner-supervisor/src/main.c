// SPDX-License-Identifier: MIT
#include "../include/mp_supervisor.h"
#include "../include/mp_prefix_migrator.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "Usage: positron-run <verb> [args...]\n");
        return 1;
    }

    const char *verb = argv[1];
    const char *compat_data = getenv("STEAM_COMPAT_DATA_PATH");

    if (strcmp(verb, "getcompatpath") == 0) {
        printf("%s\n", compat_data ? compat_data : "");
        return 0;
    }

    if (strcmp(verb, "--version") == 0) {
        printf("positron-run 1.0.0\n");
        return 0;
    }

    mp_launch_config_t cfg = {0};
    const char *app_id_env = getenv("STEAM_COMPAT_APP_ID");
    cfg.app_id = app_id_env ? (uint32_t)strtoul(app_id_env, NULL, 10) : 0;
    const char *runner_env = getenv("POSITRON_RUNNER_ID");
    if (!runner_env) runner_env = getenv("MINEPROTON_RUNNER_ID");
    snprintf(cfg.runner_id, sizeof(cfg.runner_id), "%s",
             runner_env ? runner_env : "crossover-default");
    snprintf(cfg.cx_root, sizeof(cfg.cx_root), "%s",
             getenv("CX_ROOT") ? getenv("CX_ROOT") : "/Applications/CrossOver.app/Contents/SharedSupport/CrossOver");
    if (compat_data) {
        snprintf(cfg.compat_data_path, sizeof(cfg.compat_data_path), "%s", compat_data);
    }
    if (getenv("STEAM_COMPAT_INSTALL_PATH")) {
        snprintf(cfg.install_path, sizeof(cfg.install_path), "%s", getenv("STEAM_COMPAT_INSTALL_PATH"));
    }
    if (getenv("STEAM_COMPAT_LIBRARY_PATHS")) {
        snprintf(cfg.library_paths, sizeof(cfg.library_paths), "%s", getenv("STEAM_COMPAT_LIBRARY_PATHS"));
    }

    const char *xlate_env = getenv("POSITRON_TRANSLATOR");
    if (!xlate_env) xlate_env = getenv("MINEPROTON_TRANSLATOR");
    cfg.translator    = (xlate_env && strcmp(xlate_env, "fex") == 0) ? MP_XLATE_FEX : MP_XLATE_ROSETTA;
    cfg.graphics      = MP_GFX_D3DMETAL;
    cfg.msync         = true;
    cfg.advertise_avx = true;

    bool using_shadow = false;
    char effective_pfx[1024] = {0};
    if (cfg.compat_data_path[0]) {
        const char *home = getenv("HOME");
        char shadow_base[512] = {0};
        if (home) {
            snprintf(shadow_base, sizeof(shadow_base),
                     "%s/Library/Application Support/Positron/external-prefixes", home);
        }
        mp_resolve_effective_prefix_dir(cfg.compat_data_path, cfg.app_id, shadow_base,
                                        MP_FS_APFS, effective_pfx, sizeof(effective_pfx), &using_shadow);
        if (using_shadow && home) {
            // Redirect compat_data_path to the local APFS shadow container while game files stay on S:
            snprintf(cfg.compat_data_path, sizeof(cfg.compat_data_path), "%s/%u", shadow_base, cfg.app_id);
        }

        mp_prefix_stamp_t stamp = {0};
        snprintf(stamp.runner_id, sizeof(stamp.runner_id), "%s", cfg.runner_id);
        snprintf(stamp.arch, sizeof(stamp.arch), "%s",
                 cfg.translator == MP_XLATE_FEX ? "arm64" : "x86_64");
        snprintf(stamp.graphics, sizeof(stamp.graphics), "d3dmetal");

        mp_migration_action_t action = MP_MIGRATE_NONE;
        char backup[1024] = {0};
        mp_prefix_reconcile_and_migrate(cfg.compat_data_path, &stamp, &action, backup, sizeof(backup));
        mp_supervisor_configure_prefix_hives(&cfg);

        if (cfg.install_path[0]) {
            char pfx_dir[1024];
            snprintf(pfx_dir, sizeof(pfx_dir), "%s/pfx", cfg.compat_data_path);
            mp_supervisor_map_game_drive(pfx_dir, cfg.install_path, cfg.library_paths, NULL, 0);
        }
    }

    mp_env_block_t env_block = {0};
    mp_supervisor_build_environment(&cfg, &env_block);
    for (size_t i = 0; i < env_block.count; i++) {
        setenv(env_block.pairs[i].key, env_block.pairs[i].value, 1);
    }

    if (strcmp(verb, "--dry-run") == 0) {
        for (size_t i = 0; i < env_block.count; i++) {
            printf("%s=%s\n", env_block.pairs[i].key, env_block.pairs[i].value);
        }
        return 0;
    }

    const char *loader = mp_env_block_get(&env_block, "WINELOADER");
    if (!loader || argc < 3) {
        return 0;
    }

    execv(loader, &argv[2]);
    perror("positron-run: execv failed");
    return 127;
}