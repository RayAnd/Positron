// SPDX-License-Identifier: MIT
#include "mp_web_inject.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static const char MP_RUNTIME_UI_SCRIPT[] =
    "(function(){if(globalThis.__POSITRON_UI_ACTIVE__)return;"
    "globalThis.__POSITRON_UI_ACTIVE__=true;"
    "const cfg=globalThis.__POSITRON_CONFIG__||{defaultTool:'positron-proton-default',tools:[]};"
    "function syncStores(){"
    "try{if(globalThis.settingsStore&&globalThis.settingsStore.settings){"
    "globalThis.settingsStore.settings.bCompatEnabled=true;"
    "if(!globalThis.settingsStore.settings.strCompatTool)"
    "globalThis.settingsStore.settings.strCompatTool=cfg.defaultTool;}}catch(_){}"
    "try{const apps=globalThis.SteamClient&&globalThis.SteamClient.Apps;"
    "if(apps&&!apps.__positronWrapped){apps.__positronWrapped=true;"
    "if(typeof apps.GetAvailableCompatTools==='function'){"
    "const orig=apps.GetAvailableCompatTools.bind(apps);"
    "apps.GetAvailableCompatTools=async function(id){"
    "const list=(await orig(id).catch(()=>[]))||[];"
    "return list.length?list:cfg.tools.map((t,i)=>({strToolName:t.name,strDisplayName:t.display,bIsDefault:i===0}));"
    "};}}}catch(_){}}"
    "syncStores();setInterval(syncStores,1000);})();";

bool mp_web_is_html_entry(const char *path) {
    if (!path) return false;
    const char *steamui = strstr(path, "/steamui/");
    if (!steamui) return false;
    const char *base = strrchr(path, '/');
    base = base ? base + 1 : path;
    return strcmp(base, "index.html") == 0;
}

char *mp_web_inject_html(const char *html_src, size_t html_len,
                         const mp_compat_tool_desc_t *tools, size_t tool_count,
                         size_t *out_len) {
    if (!html_src || html_len == 0) return NULL;
    if (strstr(html_src, "__POSITRON_UI_ACTIVE__") != NULL) {
        return NULL;
    }

    char tools_json[4096];
    size_t json_pos = 0;
    tools_json[json_pos++] = '[';
    for (size_t i = 0; i < tool_count; i++) {
        int written = snprintf(tools_json + json_pos, sizeof(tools_json) - json_pos,
                               "%s{\"name\":\"%s\",\"display\":\"%s\",\"flavor\":\"%s\"}",
                               i > 0 ? "," : "",
                               tools[i].name, tools[i].display_name, tools[i].flavor);
        if (written < 0 || (size_t)written >= sizeof(tools_json) - json_pos) break;
        json_pos += (size_t)written;
    }
    tools_json[json_pos++] = ']';
    tools_json[json_pos] = '\0';

    const char *default_tool = (tool_count > 0 && tools[0].name[0]) ? tools[0].name : "positron-proton-default";

    char script_tag[8192];
    int tag_len = snprintf(script_tag, sizeof(script_tag),
                           "<script>window.__POSITRON_CONFIG__={\"defaultTool\":\"%s\",\"tools\":%s};%s</script>",
                           default_tool, tools_json, MP_RUNTIME_UI_SCRIPT);
    if (tag_len <= 0 || (size_t)tag_len >= sizeof(script_tag)) return NULL;

    const char *anchor = strstr(html_src, "</head>");
    if (!anchor) anchor = strstr(html_src, "</body>");

    size_t total_len = html_len + (size_t)tag_len;
    char *out = malloc(total_len + 1);
    if (!out) return NULL;

    if (anchor) {
        size_t prefix_len = (size_t)(anchor - html_src);
        memcpy(out, html_src, prefix_len);
        memcpy(out + prefix_len, script_tag, (size_t)tag_len);
        memcpy(out + prefix_len + (size_t)tag_len, anchor, html_len - prefix_len);
    } else {
        memcpy(out, html_src, html_len);
        memcpy(out + html_len, script_tag, (size_t)tag_len);
    }
    out[total_len] = '\0';
    if (out_len) *out_len = total_len;
    return out;
}

int mp_compat_format_vdf(const mp_compat_tool_desc_t *tool,
                         char *out_compat_vdf, size_t compat_cap,
                         char *out_manifest_vdf, size_t manifest_cap) {
    if (!tool || !tool->name[0] || !out_compat_vdf || !out_manifest_vdf) return -1;

    int n1 = snprintf(out_compat_vdf, compat_cap,
                      "\"compatibilitytools\"\n"
                      "{\n"
                      "  \"compat_tools\"\n"
                      "  {\n"
                      "    \"%s\"\n"
                      "    {\n"
                      "      \"install_path\" \".\"\n"
                      "      \"display_name\" \"%s\"\n"
                      "      \"from_oslist\" \"windows\"\n"
                      "      \"to_oslist\" \"macos\"\n"
                      "    }\n"
                      "  }\n"
                      "}\n",
                      tool->name,
                      tool->display_name[0] ? tool->display_name : tool->name);
    if (n1 <= 0 || (size_t)n1 >= compat_cap) return -1;

    int n2 = snprintf(out_manifest_vdf, manifest_cap,
                      "\"manifest\"\n"
                      "{\n"
                      "  \"version\" \"2\"\n"
                      "  \"commandline\" \"/positron-run %%verb%%\"\n"
                      "}\n");
    if (n2 <= 0 || (size_t)n2 >= manifest_cap) return -1;

    return 0;
}