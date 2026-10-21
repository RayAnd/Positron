// SPDX-License-Identifier: MIT
#include "mp_resolver.h"
#include "mp_macho.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#define BASELINE_MANAGER_ENABLED_OFF  0x7B0u
#define BASELINE_TOOL_APPID_OFF       0x90u
#define BASELINE_TOOL_INSTALL_OFF     0x98u
#define BASELINE_TOOL_FROM_OSLIST_OFF 0x70u
#define BASELINE_TOOL_TO_OSLIST_OFF   0x78u

bool mp_arm64_is_prologue(uint32_t insn) {
    // SUB SP, SP, #imm
    if ((insn & 0xFF0003FFu) == 0xD10003FFu) return true;
    // STP x29, x30, [SP, #off] or [SP, #off]!
    if ((insn & 0xFFC07FFFu) == 0xA9007BFDu || (insn & 0xFFC07FFFu) == 0xA9807BFDu) return true;
    // STP Xt1, Xt2, [SP, #-imm]! or [SP, #imm]
    if ((insn & 0xFFC003E0u) == 0xA98003E0u || (insn & 0xFFC003E0u) == 0xA90003E0u) return true;
    // STP Dt1, Dt2, [SP, #-imm]! or [SP, #imm]
    if ((insn & 0xFFC003E0u) == 0x6D8003E0u || (insn & 0xFFC003E0u) == 0x6D0003E0u) return true;
    // PACIBSP
    if (insn == 0xD503237Fu) return true;
    return false;
}

static uintptr_t decode_adrp(uintptr_t pc, uint32_t insn, int *out_rd) {
    if ((insn & 0x9F000000u) != 0x90000000u) return 0;
    *out_rd = (int)(insn & 0x1Fu);
    uint32_t immlo = (insn >> 29) & 0x3u;
    uint32_t immhi = (insn >> 5) & 0x7FFFFu;
    uint32_t raw = (immhi << 2) | immlo;
    int64_t signed_pages = (int64_t)(raw ^ 0x100000u) - 0x100000;
    return (pc & ~(uintptr_t)0xFFFu) + (uintptr_t)(signed_pages * 4096);
}

static uintptr_t decode_add_imm(uint32_t insn, int expected_rn, uintptr_t page_base) {
    if ((insn & 0x7F800000u) != 0x11000000u) return 0;
    int rn = (int)((insn >> 5) & 0x1Fu);
    if (rn != expected_rn) return 0;
    uint32_t imm12 = (insn >> 10) & 0xFFFu;
    if ((insn >> 22) & 1u) imm12 <<= 12;
    return page_base + imm12;
}

uintptr_t mp_arm64_find_string_xref_fn(uintptr_t code_base, size_t code_size,
                                       uintptr_t target_va, size_t max_back_insns) {
    if (!code_base || code_size < 8 || !target_va) return 0;
    size_t word_count = code_size / 4;
    const uint32_t *words = (const uint32_t *)code_base;

    uintptr_t xref_site = 0;
    for (size_t i = 0; i + 1 < word_count; i++) {
        int rd = -1;
        uintptr_t page = decode_adrp(code_base + i * 4, words[i], &rd);
        if (!page) continue;

        // Allow the ADD to sit 1..4 instructions after ADRP (handles instruction scheduling)
        for (size_t lookahead = 1; lookahead <= 4 && (i + lookahead) < word_count; lookahead++) {
            uintptr_t resolved = decode_add_imm(words[i + lookahead], rd, page);
            if (resolved == target_va) {
                if (xref_site != 0) return 0; // Ambiguous xref
                xref_site = code_base + i * 4;
                break;
            }
            // Stop if rd is overwritten before matching
            if ((int)(words[i + lookahead] & 0x1Fu) == rd) break;
        }
    }

    if (!xref_site) return 0;

    // Walk backward to find the function prologue.
    // Note: an AArch64 prologue frequently begins with SUB SP, SP, #imm followed by STP ...,
    // or multiple STP instructions, so once we hit a prologue instruction, check if the
    // immediately preceding instruction is ALSO a prologue instruction (e.g. PACIBSP or SUB SP).
    size_t xref_idx = (xref_site - code_base) / 4;
    size_t limit = xref_idx < max_back_insns ? xref_idx : max_back_insns;
    for (size_t back = 0; back <= limit; back++) {
        size_t idx = xref_idx - back;
        if (mp_arm64_is_prologue(words[idx])) {
            while (idx > 0 && mp_arm64_is_prologue(words[idx - 1])) {
                idx--;
            }
            return code_base + idx * 4;
        }
    }
    return 0;
}

uintptr_t mp_aob_scan_unique(uintptr_t base, size_t size, const char *pattern) {
    if (!base || !size || !pattern || !pattern[0]) return 0;

    uint8_t bytes[128];
    uint8_t masks[128];
    size_t pat_len = 0;

    const char *p = pattern;
    while (*p && pat_len < sizeof(bytes)) {
        while (*p && isspace((unsigned char)*p)) p++;
        if (!*p) break;
        if (p[0] == '?' && p[1] == '?') {
            bytes[pat_len] = 0;
            masks[pat_len] = 0;
            pat_len++;
            p += 2;
        } else if (isxdigit((unsigned char)p[0]) && isxdigit((unsigned char)p[1])) {
            char hex[3] = { p[0], p[1], '\0' };
            bytes[pat_len] = (uint8_t)strtoul(hex, NULL, 16);
            masks[pat_len] = 0xFF;
            pat_len++;
            p += 2;
        } else {
            return 0; // Malformed pattern
        }
    }

    if (pat_len == 0 || size < pat_len) return 0;

    const uint8_t *haystack = (const uint8_t *)base;
    uintptr_t hit = 0;
    size_t max_off = size - pat_len;

    for (size_t off = 0; off <= max_off; off++) {
        bool match = true;
        for (size_t k = 0; k < pat_len; k++) {
            if ((haystack[off + k] & masks[k]) != bytes[k]) {
                match = false;
                break;
            }
        }
        if (match) {
            if (hit != 0) return 0; // Not unique
            hit = base + off;
        }
    }
    return hit;
}

static void cache_file_path(const char *cache_dir, const char *module_name,
                            const char *uuid, char *out_path, size_t cap) {
    snprintf(out_path, cap, "%s/%s-%s.cache", cache_dir, module_name, uuid);
}

static bool load_cached_rvas(const char *cache_path, mp_resolution_report_t *report,
                             const mp_signature_spec_t *specs, size_t spec_count,
                             uintptr_t mh_base) {
    FILE *f = fopen(cache_path, "r");
    if (!f) return false;

    char line[256];
    size_t loaded = 0;
    while (fgets(line, sizeof(line), f)) {
        char name[128];
        unsigned long long rva = 0;
        if (sscanf(line, "%127[^=]=0x%llx", name, &rva) == 2) {
            for (size_t i = 0; i < spec_count; i++) {
                if (strcmp(specs[i].name, name) == 0 && rva > 0) {
                    report->entries[i].rva = (uintptr_t)rva;
                    report->entries[i].va = mh_base + (uintptr_t)rva;
                    report->entries[i].resolved = true;
                    report->entries[i].from_cache = true;
                    loaded++;
                    break;
                }
            }
        }
    }
    fclose(f);
    return loaded > 0;
}

static void save_cached_rvas(const char *cache_dir, const char *cache_path,
                             const mp_resolution_report_t *report) {
    if (!cache_dir || !cache_path) return;
    mkdir(cache_dir, 0755);
    FILE *f = fopen(cache_path, "w");
    if (!f) return;
    for (size_t i = 0; i < report->count; i++) {
        if (report->entries[i].resolved && report->entries[i].rva > 0) {
            fprintf(f, "%s=0x%lx\n", report->entries[i].name,
                    (unsigned long)report->entries[i].rva);
        }
    }
    fclose(f);
}

int mp_resolve_module(const struct mach_header_64 *mh, intptr_t slide,
                      const char *module_name,
                      const mp_signature_spec_t *specs, size_t spec_count,
                      const char *cache_dir,
                      mp_resolution_report_t *out_report) {
    if (!mh || !module_name || !specs || !out_report) return -1;
    memset(out_report, 0, sizeof(*out_report));

    if (mp_macho_get_uuid(mh, out_report->uuid) != 0) {
        snprintf(out_report->uuid, sizeof(out_report->uuid), "no-uuid");
    }

    uintptr_t text_base = 0;
    size_t text_size = 0;
    if (mp_macho_find_segment(mh, slide, "__TEXT", &text_base, &text_size) != 0) {
        return -1;
    }

    out_report->entries = calloc(spec_count, sizeof(mp_resolved_entry_t));
    if (!out_report->entries) return -1;
    out_report->count = spec_count;

    for (size_t i = 0; i < spec_count; i++) {
        out_report->entries[i].name = specs[i].name;
        out_report->entries[i].tier = specs[i].tier;
    }

    char cache_path[512] = {0};
    bool used_cache = false;
    if (cache_dir && cache_dir[0] && strcmp(out_report->uuid, "no-uuid") != 0) {
        cache_file_path(cache_dir, module_name, out_report->uuid, cache_path, sizeof(cache_path));
        used_cache = load_cached_rvas(cache_path, out_report, specs, spec_count, (uintptr_t)mh);
    }

    for (size_t i = 0; i < spec_count; i++) {
        const mp_signature_spec_t *s = &specs[i];
        mp_resolved_entry_t *e = &out_report->entries[i];

        if (!e->resolved) {
            uintptr_t va = 0;
            if ((s->kind == MP_ANCHOR_STRING_XREF || s->kind == MP_ANCHOR_STRING_AND_AOB) &&
                s->anchor_string && s->anchor_string[0]) {
                uintptr_t str_va = mp_macho_find_Unique_cstring(mh, slide, s->anchor_string);
                if (str_va) {
                    va = mp_arm64_find_string_xref_fn(text_base, text_size, str_va, 512);
                }
            }
            if (!va && (s->kind == MP_ANCHOR_AOB_PATTERN || s->kind == MP_ANCHOR_STRING_AND_AOB) &&
                s->aob_pattern && s->aob_pattern[0]) {
                uintptr_t hit = mp_aob_scan_unique(text_base, text_size, s->aob_pattern);
                if (hit) {
                    va = hit - (uintptr_t)(intptr_t)s->aob_offset;
                }
            }

            if (va >= text_base && va + 4 <= text_base + text_size && ((va & 3u) == 0)) {
                e->va = va;
                e->rva = va - (uintptr_t)mh;
                e->resolved = true;
                e->from_cache = false;
            }
        }

        switch (s->tier) {
            case MP_TIER_CORE_COMPAT:
                out_report->core_total++;
                if (e->resolved) out_report->core_resolved++;
                break;
            case MP_TIER_WEBUI_RPC:
                out_report->webui_total++;
                if (e->resolved) out_report->webui_resolved++;
                break;
            case MP_TIER_OPTIONAL_UX:
                out_report->optional_total++;
                if (e->resolved) out_report->optional_resolved++;
                break;
        }
    }

    if (!used_cache && cache_path[0] && out_report->core_resolved == out_report->core_total) {
        save_cached_rvas(cache_dir, cache_path, out_report);
    }

    return 0;
}

bool mp_resolution_can_activate_compat(const mp_resolution_report_t *report) {
    if (!report || report->core_total == 0) return false;
    return report->core_resolved == report->core_total;
}

uintptr_t mp_resolution_lookup_va(const mp_resolution_report_t *report, const char *name) {
    if (!report || !name) return 0;
    for (size_t i = 0; i < report->count; i++) {
        if (report->entries[i].resolved && strcmp(report->entries[i].name, name) == 0) {
            return report->entries[i].va;
        }
    }
    return 0;
}

void mp_resolution_free(mp_resolution_report_t *report) {
    if (!report) return;
    free(report->entries);
    memset(report, 0, sizeof(*report));
}

void mp_probe_compat_offsets(uintptr_t bis_enabled_va,
                             uintptr_t local_redirect_va,
                             mp_compat_offsets_t *out_offsets) {
    if (!out_offsets) return;
    out_offsets->manager_enabled_off  = BASELINE_MANAGER_ENABLED_OFF;
    out_offsets->tool_appid_off       = BASELINE_TOOL_APPID_OFF;
    out_offsets->tool_install_off     = BASELINE_TOOL_INSTALL_OFF;
    out_offsets->tool_from_oslist_off = BASELINE_TOOL_FROM_OSLIST_OFF;
    out_offsets->tool_to_oslist_off   = BASELINE_TOOL_TO_OSLIST_OFF;
    out_offsets->tool_struct_shift    = 0;
    out_offsets->probed_enabled       = false;
    out_offsets->probed_tool_layout   = false;

    // 1. Probe CCompatManager::bCompatEnabled offset from BIsCompatibilityToolEnabled
    if (bis_enabled_va && (bis_enabled_va & 3u) == 0) {
        const uint32_t *insns = (const uint32_t *)bis_enabled_va;
        int self_reg = 0; // Default x0 if not moved to callee-saved register
        for (size_t i = 0; i < 16; i++) {
            uint32_t w = insns[i];
            // MOV Xd, X0 (ORR Xd, XZR, X0: 0xAA0003E0)
            if ((w & 0xFFFFFFE0u) == 0xAA0003E0u) {
                self_reg = (int)(w & 0x1Fu);
            }
            // LDRB Wt, [Xn, #imm] (0x39400000)
            if ((w & 0xFFC00000u) == 0x39400000u) {
                int rn = (int)((w >> 5) & 0x1Fu);
                uint32_t off = (w >> 10) & 0xFFFu;
                if ((rn == self_reg || rn == 0) && off >= 0x100u) {
                    out_offsets->manager_enabled_off = off;
                    out_offsets->probed_enabled = true;
                    break;
                }
            }
        }
    }

    // 2. Probe CompatTool struct shift from ResolveCompatToolForApp.local_redirect
    // Expects LDR Wt, [X0, #appid_off] followed by CBZ Wt, <local_branch>
    if (local_redirect_va && (local_redirect_va & 3u) == 0) {
        const uint32_t *insns = (const uint32_t *)local_redirect_va;
        uint32_t w0 = insns[0];
        if ((w0 & 0xFFC003E0u) == 0xB9400000u) {
            uint32_t appid_off = ((w0 >> 10) & 0xFFFu) * 4u;
            int32_t shift = (int32_t)appid_off - (int32_t)BASELINE_TOOL_APPID_OFF;
            out_offsets->tool_struct_shift    = shift;
            out_offsets->tool_appid_off       = appid_off;
            out_offsets->tool_install_off     = (uint32_t)((int32_t)BASELINE_TOOL_INSTALL_OFF + shift);
            out_offsets->tool_from_oslist_off = (uint32_t)((int32_t)BASELINE_TOOL_FROM_OSLIST_OFF + shift);
            out_offsets->tool_to_oslist_off   = (uint32_t)((int32_t)BASELINE_TOOL_TO_OSLIST_OFF + shift);
            out_offsets->probed_tool_layout   = true;
        }
    }
}
