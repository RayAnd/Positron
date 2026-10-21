// SPDX-License-Identifier: MIT
#include "mp_macho.h"
#include <stdio.h>
#include <string.h>

int mp_macho_get_uuid(const struct mach_header_64 *mh, char out_uuid[37]) {
    if (!mh || !out_uuid || mh->magic != MH_MAGIC_64) {
        return -1;
    }

    const uint8_t *ptr = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        if (lc->cmdsize < sizeof(struct load_command)) {
            return -1;
        }
        if (lc->cmd == LC_UUID && lc->cmdsize >= sizeof(struct uuid_command)) {
            const struct uuid_command *uc = (const struct uuid_command *)lc;
            const uint8_t *u = uc->uuid;
            snprintf(out_uuid, 37,
                     "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
                     u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7],
                     u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]);
            return 0;
        }
        ptr += lc->cmdsize;
    }
    return -1;
}

int mp_macho_find_segment(const struct mach_header_64 *mh, intptr_t slide,
                          const char *segname, uintptr_t *out_base, size_t *out_size) {
    if (!mh || !segname || mh->magic != MH_MAGIC_64) {
        return -1;
    }

    const uint8_t *ptr = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, segname, 16) == 0) {
                if (out_base) *out_base = (uintptr_t)seg->vmaddr + (uintptr_t)slide;
                if (out_size) *out_size = (size_t)seg->vmsize;
                return 0;
            }
        }
        ptr += lc->cmdsize;
    }
    return -1;
}

int mp_macho_find_section(const struct mach_header_64 *mh, intptr_t slide,
                          const char *segname, const char *sectname,
                          uintptr_t *out_base, size_t *out_size) {
    if (!mh || !segname || !sectname || mh->magic != MH_MAGIC_64) {
        return -1;
    }

    const uint8_t *ptr = (const uint8_t *)(mh + 1);
    for (uint32_t i = 0; i < mh->ncmds; i++) {
        const struct load_command *lc = (const struct load_command *)ptr;
        if (lc->cmd == LC_SEGMENT_64) {
            const struct segment_command_64 *seg = (const struct segment_command_64 *)lc;
            if (strncmp(seg->segname, segname, 16) == 0) {
                const struct section_64 *sects = (const struct section_64 *)(seg + 1);
                for (uint32_t s = 0; s < seg->nsects; s++) {
                    if (strncmp(sects[s].sectname, sectname, 16) == 0) {
                        if (out_base) *out_base = (uintptr_t)sects[s].addr + (uintptr_t)slide;
                        if (out_size) *out_size = (size_t)sects[s].size;
                        return 0;
                    }
                }
            }
        }
        ptr += lc->cmdsize;
    }
    return -1;
}

uintptr_t mp_macho_find_Unique_cstring(const struct mach_header_64 *mh, intptr_t slide,
                                       const char *needle) {
    if (!mh || !needle || !needle[0]) return 0;
    static const char *const segs[] = { "__TEXT", "__DATA_CONST", "__DATA" };
    size_t needle_len = strlen(needle);

    for (size_t s = 0; s < sizeof(segs) / sizeof(segs[0]); s++) {
        uintptr_t base = 0;
        size_t size = 0;
        if (mp_macho_find_segment(mh, slide, segs[s], &base, &size) != 0) continue;
        if (size <= needle_len) continue;

        const char *region = (const char *)base;
        uintptr_t hit = 0;
        for (size_t off = 0; off + needle_len < size; off++) {
            if (region[off] != needle[0]) continue;
            if (memcmp(region + off, needle, needle_len) != 0) continue;
            if (region[off + needle_len] != '\0') continue;
            if (hit != 0) return 0; // Ambiguous within segment
            hit = base + off;
            off += needle_len;
        }
        if (hit != 0) return hit;
    }
    return 0;
}
