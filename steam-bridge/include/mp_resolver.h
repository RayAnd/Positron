// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_RESOLVER_H
#define MINEPROTON_RESOLVER_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <mach-o/loader.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MP_TIER_CORE_COMPAT = 0, // Must resolve for Windows game launching to work
    MP_TIER_WEBUI_RPC   = 1, // Needed only if Steam build uses Protobuf CompatManager service
    MP_TIER_OPTIONAL_UX = 2  // Icons, non-Steam .exe picker, focus suppression; safe to skip
} mp_hook_tier_t;

typedef enum {
    MP_ANCHOR_STRING_XREF = 0, // Find unique C-string, then ADRP+ADD xref, then walk back to fn prologue
    MP_ANCHOR_AOB_PATTERN = 1, // Scan __text for byte pattern with '??' wildcards
    MP_ANCHOR_STRING_AND_AOB = 2 // Try string xref first, fall back to AOB pattern
} mp_anchor_kind_t;

typedef struct {
    const char      *name;
    const char      *module;
    mp_hook_tier_t   tier;
    mp_anchor_kind_t kind;
    const char      *anchor_string;
    const char      *aob_pattern;
    int32_t          aob_offset;
} mp_signature_spec_t;

typedef struct {
    const char      *name;
    mp_hook_tier_t   tier;
    uintptr_t        rva;        // Offset from Mach-O header base (unslid)
    uintptr_t        va;         // Slid virtual address in current process
    bool             resolved;
    bool             from_cache;
} mp_resolved_entry_t;

typedef struct {
    char                 uuid[37];
    mp_resolved_entry_t *entries;
    size_t               count;
    size_t               core_total;
    size_t               core_resolved;
    size_t               webui_total;
    size_t               webui_resolved;
    size_t               optional_total;
    size_t               optional_resolved;
} mp_resolution_report_t;

typedef struct {
    uint32_t manager_enabled_off;
    uint32_t tool_appid_off;
    uint32_t tool_install_off;
    uint32_t tool_from_oslist_off;
    uint32_t tool_to_oslist_off;
    int32_t  tool_struct_shift;
    bool     probed_enabled;
    bool     probed_tool_layout;
} mp_compat_offsets_t;

// Returns true if the instruction at 'addr' is a valid AArch64 function prologue
bool mp_arm64_is_prologue(uint32_t insn);

// Scans an instruction buffer for an ADRP + ADD pair referencing 'target_va', then walks
// backward up to 'max_back_insns' to find the enclosing function prologue.
uintptr_t mp_arm64_find_string_xref_fn(uintptr_t code_base, size_t code_size,
                                       uintptr_t target_va, size_t max_back_insns);

// Scans a buffer for a hex byte pattern with "??" wildcards. Returns sole match VA or 0.
uintptr_t mp_aob_scan_unique(uintptr_t base, size_t size, const char *pattern);

// Resolves a table of signature specs against an in-memory Mach-O image, using an
// optional LC_UUID-keyed cache directory to skip full binary scans on warm launches.
int mp_resolve_module(const struct mach_header_64 *mh, intptr_t slide,
                      const char *module_name,
                      const mp_signature_spec_t *specs, size_t spec_count,
                      const char *cache_dir,
                      mp_resolution_report_t *out_report);

// Policy gate: returns true as long as all MP_TIER_CORE_COMPAT hooks resolved,
// even if MP_TIER_OPTIONAL_UX or MP_TIER_WEBUI_RPC partially missed.
bool mp_resolution_can_activate_compat(const mp_resolution_report_t *report);

// Looks up a resolved virtual address by signature name.
uintptr_t mp_resolution_lookup_va(const mp_resolution_report_t *report, const char *name);

// Frees entries allocated inside report.
void mp_resolution_free(mp_resolution_report_t *report);

// Dynamically probes CCompatManager and CompatTool struct field offsets from AArch64 instructions,
// falling back to baseline offsets if compiler register allocation changed.
void mp_probe_compat_offsets(uintptr_t bis_enabled_va,
                             uintptr_t local_redirect_va,
                             mp_compat_offsets_t *out_offsets);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_RESOLVER_H
