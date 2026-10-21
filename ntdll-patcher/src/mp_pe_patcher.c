// SPDX-License-Identifier: MIT
#include "mp_pe_patcher.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PE_MAGIC_MZ      0x5A4Du
#define PE_SIG_NT        0x00004550u
#define OPT_MAGIC_PE32   0x010Bu
#define OPT_MAGIC_PE32P  0x020Bu

#define IMAGE_SCN_CNT_CODE  0x00000020u
#define IMAGE_SCN_MEM_EXEC  0x20000000u
#define IMAGE_SCN_MEM_READ  0x40000000u

static uint16_t read_u16(const uint8_t *p) {
    return (uint16_t)p[0] | ((uint16_t)p[1] << 8);
}

static uint32_t read_u32(const uint8_t *p) {
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) |
           ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint64_t read_u64(const uint8_t *p) {
    return (uint64_t)read_u32(p) | ((uint64_t)read_u32(p + 4) << 32);
}

static void write_u16(uint8_t *p, uint16_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
}

static void write_u32(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v & 0xFFu);
    p[1] = (uint8_t)((v >> 8) & 0xFFu);
    p[2] = (uint8_t)((v >> 16) & 0xFFu);
    p[3] = (uint8_t)((v >> 24) & 0xFFu);
}

static uint32_t align_up(uint32_t val, uint32_t align) {
    if (align == 0) return val;
    return (val + align - 1u) & ~(align - 1u);
}

static bool rva_to_offset(const uint8_t *data, size_t len,
                          uint32_t sect_table_off, uint16_t num_sects,
                          uint32_t rva, uint32_t *out_off) {
    for (uint16_t i = 0; i < num_sects; i++) {
        uint32_t entry = sect_table_off + (uint32_t)i * 40u;
        if (entry + 40u > len) return false;
        uint32_t virt_size = read_u32(data + entry + 8);
        uint32_t virt_addr = read_u32(data + entry + 12);
        uint32_t raw_size  = read_u32(data + entry + 16);
        uint32_t raw_off   = read_u32(data + entry + 20);
        uint32_t span = virt_size > raw_size ? virt_size : raw_size;
        if (raw_size > 0 && rva >= virt_addr && rva < virt_addr + span) {
            uint32_t delta = rva - virt_addr;
            if (delta < raw_size && raw_off + delta < len) {
                *out_off = raw_off + delta;
                return true;
            }
        }
    }
    return false;
}

int mp_ntdll_analyze_bytes(const uint8_t *data, size_t len, size_t min_cave_bytes,
                           mp_ntdll_analysis_t *out_info) {
    if (!data || len < 0x100 || !out_info) return -1;
    memset(out_info, 0, sizeof(*out_info));

    if (read_u16(data) != PE_MAGIC_MZ) return -1;
    uint32_t lfanew = read_u32(data + 0x3C);
    if (lfanew + 24u > len || read_u32(data + lfanew) != PE_SIG_NT) return -1;

    uint16_t machine   = read_u16(data + lfanew + 4);
    uint16_t num_sects = read_u16(data + lfanew + 6);
    uint16_t opt_size  = read_u16(data + lfanew + 20);
    uint32_t opt_off   = lfanew + 24u;
    if (opt_off + opt_size > len || opt_size < 96u) return -1;

    uint16_t opt_magic = read_u16(data + opt_off);
    bool is_pe32_plus = (opt_magic == OPT_MAGIC_PE32P);
    if (!is_pe32_plus && opt_magic != OPT_MAGIC_PE32) return -1;

    out_info->arch = (mp_pe_arch_t)machine;
    out_info->is_pe32_plus = is_pe32_plus;
    out_info->num_sections = num_sects;
    out_info->image_base = is_pe32_plus ? read_u64(data + opt_off + 24)
                                        : (uint64_t)read_u32(data + opt_off + 28);
    out_info->size_of_image = read_u32(data + opt_off + 56);

    uint32_t sect_table_off = opt_off + opt_size;
    if (sect_table_off + (uint32_t)num_sects * 40u > len) return -1;

    // 1. Parse Export Directory dynamically
    uint32_t data_dir_off = opt_off + (is_pe32_plus ? 112u : 96u);
    if (data_dir_off + 8u <= opt_off + opt_size) {
        uint32_t exp_rva  = read_u32(data + data_dir_off);
        uint32_t exp_size = read_u32(data + data_dir_off + 4);
        uint32_t exp_off  = 0;
        if (exp_rva > 0 && exp_size >= 40u &&
            rva_to_offset(data, len, sect_table_off, num_sects, exp_rva, &exp_off) &&
            exp_off + 40u <= len) {
            uint32_t nfuncs     = read_u32(data + exp_off + 20);
            uint32_t nnames     = read_u32(data + exp_off + 24);
            uint32_t funcs_rva  = read_u32(data + exp_off + 28);
            uint32_t names_rva  = read_u32(data + exp_off + 32);
            uint32_t ords_rva   = read_u32(data + exp_off + 36);

            uint32_t funcs_off = 0, names_off = 0, ords_off = 0;
            if (rva_to_offset(data, len, sect_table_off, num_sects, funcs_rva, &funcs_off) &&
                rva_to_offset(data, len, sect_table_off, num_sects, names_rva, &names_off) &&
                rva_to_offset(data, len, sect_table_off, num_sects, ords_rva, &ords_off)) {
                for (uint32_t i = 0; i < nnames && i < 8192u; i++) {
                    if (names_off + (i + 1) * 4u > len || ords_off + (i + 1) * 2u > len) break;
                    uint32_t name_rva = read_u32(data + names_off + i * 4u);
                    uint16_t ord      = read_u16(data + ords_off + i * 2u);
                    if (ord >= nfuncs || funcs_off + ((uint32_t)ord + 1u) * 4u > len) continue;
                    uint32_t fn_rva   = read_u32(data + funcs_off + (uint32_t)ord * 4u);
                    uint32_t name_off = 0;
                    if (!rva_to_offset(data, len, sect_table_off, num_sects, name_rva, &name_off)) continue;

                    const char *sym = (const char *)(data + name_off);
                    size_t max_rem = len - name_off;
                    if (strnlen(sym, max_rem) == max_rem) continue;

                    if (strcmp(sym, "LdrLoadDll") == 0) out_info->rva_LdrLoadDll = fn_rva;
                    else if (strcmp(sym, "LdrGetDllHandle") == 0) out_info->rva_LdrGetDllHandle = fn_rva;
                    else if (strcmp(sym, "NtProtectVirtualMemory") == 0) out_info->rva_NtProtectVirtualMemory = fn_rva;
                    else if (strcmp(sym, "NtOpenFile") == 0) out_info->rva_NtOpenFile = fn_rva;
                    else if (strcmp(sym, "NtReadFile") == 0) out_info->rva_NtReadFile = fn_rva;
                    else if (strcmp(sym, "NtClose") == 0) out_info->rva_NtClose = fn_rva;
                }
            }
        }
    }

    // 2. Scan sections for existing patch markers or executable code caves
    uint32_t max_rva_end = 0;
    uint32_t max_raw_end = 0;

    for (uint16_t i = 0; i < num_sects; i++) {
        uint32_t entry = sect_table_off + (uint32_t)i * 40u;
        const char *sname = (const char *)(data + entry);
        if (strncmp(sname, ".mpdet", 6) == 0 || strncmp(sname, ".npdet", 6) == 0) {
            out_info->already_patched = true;
        }

        uint32_t virt_size = read_u32(data + entry + 8);
        uint32_t virt_addr = read_u32(data + entry + 12);
        uint32_t raw_size  = read_u32(data + entry + 16);
        uint32_t raw_off   = read_u32(data + entry + 20);
        uint32_t flags     = read_u32(data + entry + 36);

        uint32_t rva_end = virt_addr + align_up(virt_size > raw_size ? virt_size : raw_size, 0x1000u);
        if (rva_end > max_rva_end) max_rva_end = rva_end;
        if (raw_off + raw_size > max_raw_end) max_raw_end = raw_off + raw_size;

        // Check tail padding inside executable sections (.text)
        if ((flags & IMAGE_SCN_MEM_EXEC) && raw_size > 0 && raw_off + raw_size <= len &&
            out_info->cave_strategy == MP_CAVE_NONE) {
            uint8_t pad = data[raw_off + raw_size - 1];
            if (pad == 0x00 || pad == 0xCC) {
                uint32_t run = 0;
                while (run < raw_size && data[raw_off + raw_size - 1 - run] == pad) {
                    run++;
                }
                // Keep 16-byte safety margin and align cave start to 16 bytes
                if (run > min_cave_bytes + 32u) {
                    uint32_t raw_cave_start = (raw_off + raw_size - run + 31u) & ~15u;
                    uint32_t usable = (raw_off + raw_size) - raw_cave_start;
                    if (usable >= min_cave_bytes) {
                        out_info->cave_strategy    = MP_CAVE_PADDING;
                        out_info->cave_file_offset = raw_cave_start;
                        out_info->cave_rva         = virt_addr + (raw_cave_start - raw_off);
                        out_info->cave_size        = usable;
                        out_info->cave_pad_byte    = pad;
                    }
                }
            }
        }
    }

    // 3. Fall back to appending a clean .mpdet executable section if .text padding is too small
    if (out_info->cave_strategy == MP_CAVE_NONE) {
        uint32_t sect_align = read_u32(data + opt_off + 32);
        uint32_t file_align = read_u32(data + opt_off + 36);
        if (sect_align == 0) sect_align = 0x1000u;
        if (file_align == 0) file_align = 0x200u;

        out_info->cave_strategy    = MP_CAVE_SECTION;
        out_info->cave_rva         = align_up(max_rva_end, sect_align);
        out_info->cave_file_offset = align_up((uint32_t)len, file_align);
        out_info->cave_size        = align_up((uint32_t)(min_cave_bytes > 0x1000u ? min_cave_bytes : 0x1000u), sect_align);
        out_info->cave_pad_byte    = 0x00;
    }

    return 0;
}

int mp_ntdll_analyze_file(const char *path, size_t min_cave_bytes,
                          mp_ntdll_analysis_t *out_info) {
    if (!path || !out_info) return -1;
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    if (fseek(f, 0, SEEK_END) != 0) { fclose(f); return -1; }
    long fsize = ftell(f);
    if (fsize <= 0x100 || fsize > (64 * 1024 * 1024)) { fclose(f); return -1; }
    rewind(f);

    uint8_t *buf = malloc((size_t)fsize);
    if (!buf) { fclose(f); return -1; }
    size_t got = fread(buf, 1, (size_t)fsize, f);
    fclose(f);
    if (got != (size_t)fsize) { free(buf); return -1; }

    int rc = mp_ntdll_analyze_bytes(buf, got, min_cave_bytes, out_info);
    free(buf);
    return rc;
}

int mp_ntdll_apply_payload(const uint8_t *src_bytes, size_t src_len,
                           const mp_ntdll_analysis_t *analysis,
                           const uint8_t *payload, size_t payload_len,
                           uint8_t **out_patched, size_t *out_patched_len) {
    if (!src_bytes || !analysis || !payload || payload_len == 0 || !out_patched || !out_patched_len) {
        return -1;
    }
    if (payload_len > analysis->cave_size) return -1;

    uint32_t lfanew    = read_u32(src_bytes + 0x3C);
    uint16_t num_sects = read_u16(src_bytes + lfanew + 6);
    uint16_t opt_size  = read_u16(src_bytes + lfanew + 20);
    uint32_t opt_off   = lfanew + 24u;
    uint32_t table_end = opt_off + opt_size + (uint32_t)num_sects * 40u;

    if (analysis->cave_strategy == MP_CAVE_PADDING) {
        if (analysis->cave_file_offset + payload_len > src_len) return -1;
        uint8_t *dst = malloc(src_len);
        if (!dst) return -1;
        memcpy(dst, src_bytes, src_len);
        memcpy(dst + analysis->cave_file_offset, payload, payload_len);
        *out_patched = dst;
        *out_patched_len = src_len;
        return 0;
    } else if (analysis->cave_strategy == MP_CAVE_SECTION) {
        size_t new_len = (size_t)analysis->cave_file_offset + (size_t)analysis->cave_size;
        uint8_t *dst = calloc(1, new_len);
        if (!dst) return -1;
        memcpy(dst, src_bytes, src_len);

        // Write new section header (.mpdet)
        uint8_t *sh = dst + table_end;
        memcpy(sh, ".mpdet\0\0", 8);
        write_u32(sh + 8,  analysis->cave_size);
        write_u32(sh + 12, analysis->cave_rva);
        write_u32(sh + 16, analysis->cave_size);
        write_u32(sh + 20, analysis->cave_file_offset);
        write_u32(sh + 36, IMAGE_SCN_CNT_CODE | IMAGE_SCN_MEM_EXEC | IMAGE_SCN_MEM_READ);

        // Increment NumberOfSections and update SizeOfImage
        write_u16(dst + lfanew + 6, num_sects + 1u);
        write_u32(dst + opt_off + 56, analysis->cave_rva + analysis->cave_size);

        memcpy(dst + analysis->cave_file_offset, payload, payload_len);
        *out_patched = dst;
        *out_patched_len = new_len;
        return 0;
    }

    return -1;
}
