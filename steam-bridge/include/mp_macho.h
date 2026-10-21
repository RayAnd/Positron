// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_MACHO_H
#define MINEPROTON_MACHO_H

#include <stddef.h>
#include <stdint.h>
#include <mach-o/loader.h>

#ifdef __cplusplus
extern "C" {
#endif

// Formats the 16-byte LC_UUID of a 64-bit Mach-O header into a 36-char UUID string + NUL.
// Returns 0 on success, -1 if no LC_UUID command exists.
int mp_macho_get_uuid(const struct mach_header_64 *mh, char out_uuid[37]);

// Finds a named segment (e.g. "__TEXT", "__DATA_CONST") and returns its slid base address and size.
int mp_macho_find_segment(const struct mach_header_64 *mh, intptr_t slide,
                          const char *segname, uintptr_t *out_base, size_t *out_size);

// Finds a named section inside a segment (e.g. "__TEXT", "__text").
int mp_macho_find_section(const struct mach_header_64 *mh, intptr_t slide,
                          const char *segname, const char *sectname,
                          uintptr_t *out_base, size_t *out_size);

// Locates a unique NUL-terminated C string across __TEXT / __DATA_CONST / __DATA.
// Returns the slid virtual address or 0 if not found or ambiguous.
uintptr_t mp_macho_find_Unique_cstring(const struct mach_header_64 *mh, intptr_t slide,
                                       const char *needle);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_MACHO_H
