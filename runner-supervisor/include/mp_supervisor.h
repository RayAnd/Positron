// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_SUPERVISOR_H
#define MINEPROTON_SUPERVISOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MP_GFX_D3DMETAL = 0,
    MP_GFX_DXMT     = 1,
    MP_GFX_DXVK     = 2,
    MP_GFX_WINED3D  = 3
} mp_graphics_backend_t;

typedef enum {
    MP_XLATE_ROSETTA = 0,
    MP_XLATE_FEX     = 1
} mp_cpu_translator_t;

typedef struct {
    uint32_t              app_id;
    char                  runner_id[64];
    char                  cx_root[512];
    char                  compat_data_path[512];
    char                  install_path[512];
    char                  library_paths[1024];
    mp_graphics_backend_t graphics;
    mp_cpu_translator_t   translator;
    bool                  msync;
    bool                  retina_mode;
    bool                  metal_hud;
    bool                  advertise_avx;
    bool                  disable_hidraw;
} mp_launch_config_t;

typedef struct {
    char key[64];
    char value[512];
} mp_env_pair_t;

typedef struct {
    mp_env_pair_t pairs[64];
    size_t        count;
} mp_env_block_t;

// Applies pre-launch Wine registry settings (RetinaMode, LogPixels, AeDebug,
// Steam ActiveProcess, DisableHidraw) directly to system.reg and user.reg offline.
int mp_supervisor_configure_prefix_hives(const mp_launch_config_t *cfg);

// Maps dosdevices/s: to the enclosing Steam library directory so games do not run from Z:.
int mp_supervisor_map_game_drive(const char *pfx_dir,
                                 const char *install_path,
                                 const char *library_paths,
                                 char *out_mapped_target,
                                 size_t target_cap);

// Computes the clean environment variable block for launching Wine/CrossOver,
// automatically stripping incompatible flags (e.g. D3DM_* / ROSETTA_ADVERTISE_AVX on FEX)
// and applying built-in game quirks for known AppIDs.
int mp_supervisor_build_environment(const mp_launch_config_t *cfg,
                                    mp_env_block_t *out_env);

// Looks up a key in an mp_env_block_t.
const char *mp_env_block_get(const mp_env_block_t *env, const char *key);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_SUPERVISOR_H
