// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_REG_EDITOR_H
#define MINEPROTON_REG_EDITOR_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    const char *section; // e.g. "Software\\Wine\\Mac Driver"
    const char *key;     // e.g. ""RetinaMode"" or "@"; NULL to delete entire section
    const char *value;   // e.g. ""y"" or "dword:00000060"; NULL or "-" to delete key
} mp_reg_mutation_t;

// Applies a batch of registry mutations directly to a Wine .reg file on disk
// atomically (via temp file + rename), avoiding any need to spawn 'wine reg import'
// or restart 'wineserver -k/-w' before launching a game.
int mp_reg_apply_mutations_file(const char *reg_path,
                                const mp_reg_mutation_t *mutations,
                                size_t mutation_count);

// Applies a batch of registry mutations to an in-memory Wine .reg text buffer.
// Caller frees the returned string.
char *mp_reg_apply_mutations_mem(const char *src_text,
                                 const mp_reg_mutation_t *mutations,
                                 size_t mutation_count);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_REG_EDITOR_H
