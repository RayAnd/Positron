// SPDX-License-Identifier: MIT
#ifndef MINEPROTON_WEB_INJECT_H
#define MINEPROTON_WEB_INJECT_H

#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    char name[64];
    char display_name[128];
    char runner_id[64];
    char flavor[16]; // "fex" or "rosetta"
} mp_compat_tool_desc_t;

// Returns true if 'path' is a Steam HTML entrypoint (e.g., index.html in steamui)
// suitable for clean <script> runtime injection rather than brittle minified JS byte-patching.
bool mp_web_is_html_entry(const char *path);

// Injects the Positron runtime store/Fiber script and tool configuration JSON
// before </head> or </body> in an HTML document. Caller frees the returned buffer.
char *mp_web_inject_html(const char *html_src, size_t html_len,
                         const mp_compat_tool_desc_t *tools, size_t tool_count,
                         size_t *out_len);

// Generates the Valve compatibilitytool.vdf and toolmanifest.vdf content for a tool.
int mp_compat_format_vdf(const mp_compat_tool_desc_t *tool,
                         char *out_compat_vdf, size_t compat_cap,
                         char *out_manifest_vdf, size_t manifest_cap);

#ifdef __cplusplus
}
#endif

#endif // MINEPROTON_WEB_INJECT_H
