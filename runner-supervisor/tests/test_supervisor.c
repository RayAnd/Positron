// SPDX-License-Identifier: MIT
#include "../include/mp_reg_editor.h"
#include "../include/mp_prefix_migrator.h"
#include "../include/mp_supervisor.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static void test_offline_registry_editor(void) {
    const char *initial_reg =
        "WINE REGISTRY Version 2\n"
        "\n"
        "[Software\\\\Wine\\\\Mac Driver] 1700000000\n"
        "\"RetinaMode\"=\"n\"\n"
        "\"LeftoverKey\"=\"keep\"\n"
        "\n"
        "[System\\\\CurrentControlSet\\\\Services\\\\WineBus] 1700000000\n"
        "\"DisableHidraw\"=dword:00000001\n";

    const mp_reg_mutation_t muts[] = {
        {
            .section = "Software\\\\Wine\\\\Mac Driver",
            .key     = "\"RetinaMode\"",
            .value   = "\"y\""
        },
        {
            .section = "System\\\\CurrentControlSet\\\\Services\\\\WineBus",
            .key     = "\"DisableHidraw\"",
            .value   = "-"
        },
        {
            .section = "Control Panel\\\\Desktop",
            .key     = "\"LogPixels\"",
            .value   = "dword:000000c0"
        }
    };

    char *updated = mp_reg_apply_mutations_mem(initial_reg, muts, 3);
    assert(updated != NULL);
    assert(strstr(updated, "\"RetinaMode\"=\"y\"") != NULL);
    assert(strstr(updated, "\"LeftoverKey\"=\"keep\"") != NULL);
    assert(strstr(updated, "DisableHidraw") == NULL);
    assert(strstr(updated, "[Control Panel\\\\Desktop]") != NULL);
    assert(strstr(updated, "\"LogPixels\"=dword:000000c0") != NULL);
    free(updated);
    printf("  [PASS] test_offline_registry_editor\n");
}

static void test_seamless_prefix_auto_migration(void) {
    char tmp_dir[] = "/tmp/mp_prefix_test.XXXXXX";
    assert(mkdtemp(tmp_dir) != NULL);

    mp_prefix_stamp_t stamp_v1 = {
        .runner_id = "crossover-26.3",
        .arch      = "x86_64",
        .graphics  = "d3dmetal"
    };
    mp_migration_action_t action = MP_MIGRATE_NONE;
    char backup[1024] = {0};
    assert(mp_prefix_reconcile_and_migrate(tmp_dir, &stamp_v1, &action, backup, sizeof(backup)) == 0);
    assert(action == MP_MIGRATE_INITIALIZED);

    char save_file[1024];
    snprintf(save_file, sizeof(save_file), "%s/pfx/drive_c/users/steamuser/Documents/savegame.dat", tmp_dir);
    FILE *f = fopen(save_file, "w");
    assert(f != NULL);
    fputs("PLAYER_LEVEL=99", f);
    fclose(f);

    assert(mp_prefix_reconcile_and_migrate(tmp_dir, &stamp_v1, &action, backup, sizeof(backup)) == 0);
    assert(action == MP_MIGRATE_NONE);

    mp_prefix_stamp_t stamp_v2 = {
        .runner_id = "crossover-27.0-fex",
        .arch      = "arm64",
        .graphics  = "dxmt"
    };
    assert(mp_prefix_reconcile_and_migrate(tmp_dir, &stamp_v2, &action, backup, sizeof(backup)) == 0);
    assert(action == MP_MIGRATE_ARCH_TRANSITIONED);
    assert(backup[0] != '\0');

    assert(access(save_file, R_OK) == 0);
    char snap_save[1024];
    snprintf(snap_save, sizeof(snap_save), "%s/Documents/savegame.dat", backup);
    assert(access(snap_save, R_OK) == 0);

    char cleanup[1200];
    snprintf(cleanup, sizeof(cleanup), "rm -rf '%s'", tmp_dir);
    system(cleanup);
    printf("  [PASS] test_seamless_prefix_auto_migration\n");
}

static void test_external_drive_shadow_prefix_and_s_drive(void) {
    char tmp_dir[] = "/tmp/mp_ext_test.XXXXXX";
    assert(mkdtemp(tmp_dir) != NULL);

    // 1. Inspect local APFS volume
    mp_volume_info_t vol = {0};
    assert(mp_inspect_volume(tmp_dir, &vol) == 0);
    assert(vol.kind == MP_FS_APFS);
    assert(vol.needs_apfs_shadow_prefix == false);

    // 2. Simulate an ExFAT external drive compatdata path -> must redirect to APFS shadow prefix!
    char pfx_out[1024] = {0};
    bool using_shadow = false;
    assert(mp_resolve_effective_prefix_dir("/Volumes/ExFatSSD/SteamLibrary/steamapps/compatdata/1151340",
                                           1151340, tmp_dir, MP_FS_EXFAT,
                                           pfx_out, sizeof(pfx_out), &using_shadow) == 0);
    assert(using_shadow == true);
    assert(strstr(pfx_out, "/1151340/pfx") != NULL);

    // 3. Verify external drive S: mapping even when STEAM_COMPAT_LIBRARY_PATHS is empty
    char mapped_target[1024] = {0};
    assert(mp_supervisor_map_game_drive(pfx_out,
                                        "/Volumes/ExFatSSD/SteamLibrary/steamapps/common/Fallout76",
                                        "",
                                        mapped_target, sizeof(mapped_target)) == 0);
    assert(strcmp(mapped_target, "/Volumes/ExFatSSD/SteamLibrary") == 0);

    char cleanup[1200];
    snprintf(cleanup, sizeof(cleanup), "rm -rf '%s'", tmp_dir);
    system(cleanup);
    printf("  [PASS] test_external_drive_shadow_prefix_and_s_drive\n");
}

static void test_supervisor_env_and_drive_mapping(void) {
    char tmp_dir[] = "/tmp/mp_sup_test.XXXXXX";
    assert(mkdtemp(tmp_dir) != NULL);

    mp_launch_config_t cfg = {
        .app_id        = 1091500,
        .graphics      = MP_GFX_D3DMETAL,
        .translator    = MP_XLATE_FEX,
        .msync         = true,
        .retina_mode   = true,
        .metal_hud     = true,
        .advertise_avx = true,
        .disable_hidraw = true
    };
    snprintf(cfg.runner_id, sizeof(cfg.runner_id), "crossover-27.0-fex");
    snprintf(cfg.cx_root, sizeof(cfg.cx_root), "/Applications/CrossOver Preview.app/Contents/SharedSupport/CrossOver");
    snprintf(cfg.compat_data_path, sizeof(cfg.compat_data_path), "%s", tmp_dir);
    snprintf(cfg.install_path, sizeof(cfg.install_path), "/Volumes/Games/SteamLibrary/steamapps/common/Cyberpunk 2077");
    snprintf(cfg.library_paths, sizeof(cfg.library_paths), "/Users/test/Steam:/Volumes/Games/SteamLibrary");

    assert(mp_supervisor_configure_prefix_hives(&cfg) == 0);

    char pfx_dir[1024];
    snprintf(pfx_dir, sizeof(pfx_dir), "%s/pfx", tmp_dir);
    char mapped_target[1024] = {0};
    assert(mp_supervisor_map_game_drive(pfx_dir, cfg.install_path, cfg.library_paths,
                                        mapped_target, sizeof(mapped_target)) == 0);
    assert(strcmp(mapped_target, "/Volumes/Games/SteamLibrary") == 0);

    mp_env_block_t env = {0};
    assert(mp_supervisor_build_environment(&cfg, &env) == 0);
    assert(strcmp(mp_env_block_get(&env, "CX_GRAPHICS_BACKEND"), "dxmt") == 0);
    assert(strcmp(mp_env_block_get(&env, "FEX_X87REDUCEDPRECISION"), "1") == 0);
    assert(mp_env_block_get(&env, "ROSETTA_ADVERTISE_AVX") == NULL);
    assert(strstr(mp_env_block_get(&env, "WINEDLLOVERRIDES"), "vcruntime140=n,b") != NULL);

    char cleanup[1200];
    snprintf(cleanup, sizeof(cleanup), "rm -rf '%s'", tmp_dir);
    system(cleanup);
    printf("  [PASS] test_supervisor_env_and_drive_mapping\n");
}

int main(void) {
    printf("Running Positron runner-supervisor tests...\n");
    test_offline_registry_editor();
    test_seamless_prefix_auto_migration();
    test_external_drive_shadow_prefix_and_s_drive();
    test_supervisor_env_and_drive_mapping();
    printf("All Positron runner-supervisor tests passed!\n");
    return 0;
}