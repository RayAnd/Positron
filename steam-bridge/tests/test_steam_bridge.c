// SPDX-License-Identifier: MIT
#include "mp_macho.h"
#include "mp_resolver.h"
#include "mp_web_inject.h"

#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef struct {
    struct mach_header_64     mh;
    struct uuid_command       uuid_cmd;
    struct segment_command_64 text_seg;
    struct section_64         text_sect;
    uint8_t                   payload[4096];
} synthetic_macho_t;

static void init_synthetic_macho(synthetic_macho_t *img) {
    memset(img, 0, sizeof(*img));
    img->mh.magic      = MH_MAGIC_64;
    img->mh.cputype    = CPU_TYPE_ARM64;
    img->mh.cpusubtype = CPU_SUBTYPE_ARM64_ALL;
    img->mh.filetype   = MH_DYLIB;
    img->mh.ncmds      = 2;
    img->mh.sizeofcmds = sizeof(struct uuid_command) + sizeof(struct segment_command_64) + sizeof(struct section_64);

    img->uuid_cmd.cmd     = LC_UUID;
    img->uuid_cmd.cmdsize = sizeof(struct uuid_command);
    const uint8_t sample_uuid[16] = {
        0x12, 0x34, 0x56, 0x78, 0x9a, 0xbc, 0xde, 0xf0,
        0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88
    };
    memcpy(img->uuid_cmd.uuid, sample_uuid, 16);

    img->text_seg.cmd     = LC_SEGMENT_64;
    img->text_seg.cmdsize = sizeof(struct segment_command_64) + sizeof(struct section_64);
    strncpy(img->text_seg.segname, "__TEXT", 16);
    img->text_seg.vmaddr  = (uint64_t)(uintptr_t)img;
    img->text_seg.vmsize  = sizeof(*img);
    img->text_seg.nsects  = 1;

    strncpy(img->text_sect.sectname, "__text", 16);
    strncpy(img->text_sect.segname, "__TEXT", 16);
    img->text_sect.addr = (uint64_t)(uintptr_t)img->payload;
    img->text_sect.size = sizeof(img->payload);
}

static void test_macho_uuid_and_segments(void) {
    synthetic_macho_t *img = NULL;
    assert(posix_memalign((void **)&img, 4096, sizeof(synthetic_macho_t)) == 0);
    init_synthetic_macho(img);

    char uuid[37] = {0};
    assert(mp_macho_get_uuid(&img->mh, uuid) == 0);
    assert(strcmp(uuid, "12345678-9abc-def0-1122-334455667788") == 0);

    uintptr_t seg_base = 0;
    size_t seg_size = 0;
    assert(mp_macho_find_segment(&img->mh, 0, "__TEXT", &seg_base, &seg_size) == 0);
    assert(seg_base == (uintptr_t)img);
    assert(seg_size == sizeof(*img));

    const char *marker = "CCompatManager::BIsCompatibilityToolEnabled";
    strcpy((char *)(img->payload + 2048), marker);
    uintptr_t found_str = mp_macho_find_Unique_cstring(&img->mh, 0, marker);
    assert(found_str == (uintptr_t)(img->payload + 2048));

    free(img);
    printf("  [PASS] test_macho_uuid_and_segments\n");
}

static void test_arm64_xref_and_tiered_resolution(void) {
    synthetic_macho_t *img = NULL;
    assert(posix_memalign((void **)&img, 4096, sizeof(synthetic_macho_t)) == 0);
    init_synthetic_macho(img);

    uintptr_t str_addr = (uintptr_t)(img->payload + 1024);
    strcpy((char *)str_addr, "STEAM_COMPAT_TOOL_MAPPINGS");

    uint32_t *fn = (uint32_t *)(img->payload + 64);
    uintptr_t fn_va = (uintptr_t)fn;
    fn[0] = 0xD10103FFu;
    fn[1] = 0xA9017BFDu;

    uintptr_t pc = (uintptr_t)&fn[2];
    int64_t page_delta = ((int64_t)(str_addr & ~(uintptr_t)0xFFFu) - (int64_t)(pc & ~(uintptr_t)0xFFFu)) >> 12;
    uint32_t immlo = (uint32_t)(page_delta & 0x3);
    uint32_t immhi = (uint32_t)((page_delta >> 2) & 0x7FFFF);
    fn[2] = 0x90000000u | (immlo << 29) | (immhi << 5) | 0;

    uint32_t page_off = (uint32_t)(str_addr & 0xFFFu);
    fn[3] = 0x91000000u | (page_off << 10) | (0 << 5) | 0;
    fn[4] = 0xD65F03C0u;

    uintptr_t resolved_fn = mp_arm64_find_string_xref_fn((uintptr_t)img->payload, 1024, str_addr, 64);
    assert(resolved_fn == fn_va);

    const mp_signature_spec_t specs[] = {
        {
            .name          = "CCompatManager::Init",
            .module        = "steamclient.dylib",
            .tier          = MP_TIER_CORE_COMPAT,
            .kind          = MP_ANCHOR_STRING_XREF,
            .anchor_string = "STEAM_COMPAT_TOOL_MAPPINGS",
        },
        {
            .name          = "Optional::MissingShortcutHook",
            .module        = "steamclient.dylib",
            .tier          = MP_TIER_OPTIONAL_UX,
            .kind          = MP_ANCHOR_STRING_XREF,
            .anchor_string = "STRING_THAT_DOES_NOT_EXIST_IN_NEW_STEAM_BUILD",
        }
    };

    char tmp_dir[] = "/tmp/positron_cache_test.XXXXXX";
    assert(mkdtemp(tmp_dir) != NULL);

    mp_resolution_report_t report = {0};
    assert(mp_resolve_module(&img->mh, 0, "steamclient.dylib", specs, 2, tmp_dir, &report) == 0);
    assert(report.core_total == 1 && report.core_resolved == 1);
    assert(report.optional_total == 1 && report.optional_resolved == 0);
    assert(mp_resolution_can_activate_compat(&report) == true);
    assert(mp_resolution_lookup_va(&report, "CCompatManager::Init") == fn_va);
    assert(report.entries[0].from_cache == false);
    mp_resolution_free(&report);

    mp_resolution_report_t cached_report = {0};
    assert(mp_resolve_module(&img->mh, 0, "steamclient.dylib", specs, 2, tmp_dir, &cached_report) == 0);
    assert(cached_report.entries[0].resolved == true);
    assert(cached_report.entries[0].from_cache == true);
    assert(mp_resolution_lookup_va(&cached_report, "CCompatManager::Init") == fn_va);
    mp_resolution_free(&cached_report);

    char cleanup_cmd[256];
    snprintf(cleanup_cmd, sizeof(cleanup_cmd), "rm -rf '%s'", tmp_dir);
    system(cleanup_cmd);
    free(img);
    printf("  [PASS] test_arm64_xref_and_tiered_resolution\n");
}

static void test_dynamic_offset_probing(void) {
    uint32_t bis_enabled_code[6] = {
        0xD10043FFu,
        0xAA0003F4u,
        0x39400294u | (0x7D8u << 10),
        0xD65F03C0u
    };

    uint32_t local_redirect_code[4] = {
        0xB9400001u | ((0xA0u / 4u) << 10),
        0x34000041u,
        0xD65F03C0u
    };

    mp_compat_offsets_t offsets = {0};
    mp_probe_compat_offsets((uintptr_t)bis_enabled_code, (uintptr_t)local_redirect_code, &offsets);
    assert(offsets.probed_enabled == true);
    assert(offsets.manager_enabled_off == 0x7D8u);
    assert(offsets.probed_tool_layout == true);
    assert(offsets.tool_struct_shift == 0x10);
    assert(offsets.tool_appid_off == 0xA0u);
    assert(offsets.tool_install_off == 0xA8u);
    printf("  [PASS] test_dynamic_offset_probing\n");
}

static void test_web_injector_and_vdf(void) {
    assert(mp_web_is_html_entry("/Users/test/Library/Application Support/Steam/steamui/index.html") == true);
    assert(mp_web_is_html_entry("/Users/test/Library/Application Support/Steam/steamui/library.js") == false);

    const char *html = "<html><head><title>Steam</title></head><body></body></html>";
    mp_compat_tool_desc_t tool = {
        .name = "positron-proton-cx27-fex",
        .display_name = "Positron (CrossOver 27 FEX)",
        .runner_id = "crossover-27.0",
        .flavor = "fex"
    };

    size_t out_len = 0;
    char *injected = mp_web_inject_html(html, strlen(html), &tool, 1, &out_len);
    assert(injected != NULL);
    assert(strstr(injected, "__POSITRON_CONFIG__") != NULL);
    assert(strstr(injected, "positron-proton-cx27-fex") != NULL);
    assert(strstr(injected, "</head>") != NULL);

    assert(mp_web_inject_html(injected, out_len, &tool, 1, NULL) == NULL);
    free(injected);

    char compat_vdf[512], manifest_vdf[512];
    assert(mp_compat_format_vdf(&tool, compat_vdf, sizeof(compat_vdf), manifest_vdf, sizeof(manifest_vdf)) == 0);
    assert(strstr(compat_vdf, "\"to_oslist\" \"macos\"") != NULL);
    assert(strstr(manifest_vdf, "/positron-run %verb%") != NULL);
    printf("  [PASS] test_web_injector_and_vdf\n");
}

int main(void) {
    printf("Running Positron steam-bridge tests...\n");
    test_macho_uuid_and_segments();
    test_arm64_xref_and_tiered_resolution();
    test_dynamic_offset_probing();
    test_web_injector_and_vdf();
    printf("All Positron steam-bridge tests passed!\n");
    return 0;
}