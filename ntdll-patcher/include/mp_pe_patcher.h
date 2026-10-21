// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_PE_PATCHER_H
#define MINEPROTON_PE_PATCHER_H

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MP_PE_ARCH_UNKNOWN = 0,
    MP_PE_ARCH_I386    = 0x014c,
    MP_PE_ARCH_X86_64  = 0x8664,
    MP_PE_ARCH_ARM64   = 0xaa64
} mp_pe_arch_t;

typedef enum {
    MP_CAVE_NONE    = 0,
    MP_CAVE_PADDING = 1, // Uses existing section slack/padding
    MP_CAVE_SECTION = 2  // Appends a new executable .mpdet PE section
} mp_cave_strategy_t;

typedef struct {
    mp_pe_arch_t       arch;
    bool               is_pe32_plus;
    uint64_t           image_base;
    uint32_t           size_of_image;
    uint16_t           num_sections;
    // Dynamically resolved export RVAs (0 if not present)
    uint32_t           rva_LdrLoadDll;
    uint32_t           rva_LdrGetDllHandle;
    uint32_t           rva_NtProtectVirtualMemory;
    uint32_t           rva_NtOpenFile;
    uint32_t           rva_NtReadFile;
    uint32_t           rva_NtClose;
    // Dynamically discovered code cave or section placement
    mp_cave_strategy_t cave_strategy;
    uint32_t           cave_rva;
    uint32_t           cave_file_offset;
    uint32_t           cave_size;
    uint8_t            cave_pad_byte;
    // Whether the binary already carries a Positron or NotProton detour section
    bool               already_patched;
} mp_ntdll_analysis_t;

// Dynamically analyzes any PE32/PE32+ ntdll.dll buffer (x86_64, i386, or aarch64)
// without requiring a hardcoded SHA-256 allowlist.
int mp_ntdll_analyze_bytes(const uint8_t *data, size_t len, size_t min_cave_bytes,
                           mp_ntdll_analysis_t *out_info);

// Analyzes an ntdll.dll file on disk.
int mp_ntdll_analyze_file(const char *path, size_t min_cave_bytes,
                          mp_ntdll_analysis_t *out_info);

// Applies a position-independent payload into the discovered code cave (or appends a
// new .mpdet executable section if padding is insufficient) and writes the output buffer.
// Caller frees *out_patched.
int mp_ntdll_apply_payload(const uint8_t *src_bytes, size_t src_len,
                           const mp_ntdll_analysis_t *analysis,
                           const uint8_t *payload, size_t payload_len,
                           uint8_t **out_patched, size_t *out_patched_len);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_PE_PATCHER_H
