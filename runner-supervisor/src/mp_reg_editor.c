// SPDX-License-Identifier: MIT
#include "mp_reg_editor.h"
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static bool str_ieq(const char *a, const char *b) {
    while (*a && *b) {
        if (tolower((unsigned char)*a) != tolower((unsigned char)*b)) return false;
        a++;
        b++;
    }
    return *a == *b;
}

static bool extract_section_header(const char *line, char *out_sec, size_t cap) {
    if (line[0] != '[') return false;
    const char *close = strchr(line, ']');
    if (!close) return false;
    size_t len = (size_t)(close - (line + 1));
    if (len >= cap) len = cap - 1;
    memcpy(out_sec, line + 1, len);
    out_sec[len] = '\0';
    return true;
}

static bool line_matches_key(const char *line, const char *key) {
    size_t klen = strlen(key);
    if (strncmp(line, key, klen) != 0) return false;
    const char *p = line + klen;
    while (*p == ' ' || *p == '\t') p++;
    return *p == '=';
}

typedef struct {
    char  *data;
    size_t len;
    size_t cap;
} strbuf_t;

static void sb_append(strbuf_t *sb, const char *s, size_t n) {
    if (sb->len + n + 1 > sb->cap) {
        size_t new_cap = sb->cap ? sb->cap * 2 : 4096;
        while (new_cap < sb->len + n + 1) new_cap *= 2;
        char *grown = realloc(sb->data, new_cap);
        if (!grown) return;
        sb->data = grown;
        sb->cap  = new_cap;
    }
    memcpy(sb->data + sb->len, s, n);
    sb->len += n;
    sb->data[sb->len] = '\0';
}

static void sb_append_cstr(strbuf_t *sb, const char *s) {
    sb_append(sb, s, strlen(s));
}

static void flush_unapplied_for_section(strbuf_t *sb, const char *current_sec,
                                        const mp_reg_mutation_t *mutations,
                                        size_t count, bool *applied) {
    if (!current_sec[0]) return;
    for (size_t i = 0; i < count; i++) {
        if (applied[i]) continue;
        if (!mutations[i].section || !str_ieq(current_sec, mutations[i].section)) continue;
        applied[i] = true;
        if (!mutations[i].key || !mutations[i].value || strcmp(mutations[i].value, "-") == 0) {
            continue;
        }
        char row[1024];
        snprintf(row, sizeof(row), "%s=%s\n", mutations[i].key, mutations[i].value);
        sb_append_cstr(sb, row);
    }
}

char *mp_reg_apply_mutations_mem(const char *src_text,
                                 const mp_reg_mutation_t *mutations,
                                 size_t mutation_count) {
    const char *input = (src_text && src_text[0]) ? src_text : "WINE REGISTRY Version 2\n\n";
    bool *applied = calloc(mutation_count ? mutation_count : 1, sizeof(bool));
    if (!applied) return NULL;

    strbuf_t sb = {0};
    char current_sec[512] = {0};
    bool drop_current_sec = false;

    const char *p = input;
    while (*p) {
        const char *eol = strchr(p, '\n');
        size_t line_len = eol ? (size_t)(eol - p) : strlen(p);
        size_t trimmed_len = (line_len > 0 && p[line_len - 1] == '\r') ? line_len - 1 : line_len;

        char line[1024];
        size_t copy_len = trimmed_len < sizeof(line) - 1 ? trimmed_len : sizeof(line) - 1;
        memcpy(line, p, copy_len);
        line[copy_len] = '\0';

        char new_sec[512];
        if (extract_section_header(line, new_sec, sizeof(new_sec))) {
            if (!drop_current_sec && current_sec[0]) {
                flush_unapplied_for_section(&sb, current_sec, mutations, mutation_count, applied);
            }
            snprintf(current_sec, sizeof(current_sec), "%s", new_sec);
            drop_current_sec = false;
            for (size_t i = 0; i < mutation_count; i++) {
                if (mutations[i].section && str_ieq(current_sec, mutations[i].section) &&
                    mutations[i].key == NULL) {
                    drop_current_sec = true;
                    applied[i] = true;
                }
            }
            if (!drop_current_sec) {
                sb_append(&sb, line, copy_len);
                sb_append_cstr(&sb, "\n");
            }
        } else if (!drop_current_sec) {
            bool handled_line = false;
            if (current_sec[0] && (line[0] == '"' || line[0] == '@')) {
                for (size_t i = 0; i < mutation_count; i++) {
                    if (!mutations[i].section || !mutations[i].key) continue;
                    if (!str_ieq(current_sec, mutations[i].section)) continue;
                    if (line_matches_key(line, mutations[i].key)) {
                        applied[i] = true;
                        handled_line = true;
                        if (mutations[i].value && strcmp(mutations[i].value, "-") != 0) {
                            char row[1024];
                            snprintf(row, sizeof(row), "%s=%s\n", mutations[i].key, mutations[i].value);
                            sb_append_cstr(&sb, row);
                        }
                        break;
                    }
                }
            }
            if (!handled_line) {
                sb_append(&sb, line, copy_len);
                sb_append_cstr(&sb, "\n");
            }
        }

        if (!eol) break;
        p = eol + 1;
    }

    if (!drop_current_sec && current_sec[0]) {
        flush_unapplied_for_section(&sb, current_sec, mutations, mutation_count, applied);
    }

    // Append any new sections that did not exist in the original file
    for (size_t i = 0; i < mutation_count; i++) {
        if (applied[i]) continue;
        if (!mutations[i].section || !mutations[i].key || !mutations[i].value ||
            strcmp(mutations[i].value, "-") == 0) {
            applied[i] = true;
            continue;
        }
        const char *sec = mutations[i].section;
        char hdr[600];
        snprintf(hdr, sizeof(hdr), "\n[%s] 1700000000\n", sec);
        sb_append_cstr(&sb, hdr);
        flush_unapplied_for_section(&sb, sec, mutations, mutation_count, applied);
    }

    free(applied);
    return sb.data;
}

int mp_reg_apply_mutations_file(const char *reg_path,
                                const mp_reg_mutation_t *mutations,
                                size_t mutation_count) {
    if (!reg_path || !mutations) return -1;

    char *existing = NULL;
    FILE *in = fopen(reg_path, "rb");
    if (in) {
        if (fseek(in, 0, SEEK_END) == 0) {
            long sz = ftell(in);
            rewind(in);
            if (sz >= 0 && sz < (32 * 1024 * 1024)) {
                existing = malloc((size_t)sz + 1);
                if (existing) {
                    size_t n = fread(existing, 1, (size_t)sz, in);
                    existing[n] = '\0';
                }
            }
        }
        fclose(in);
    }

    char *updated = mp_reg_apply_mutations_mem(existing, mutations, mutation_count);
    free(existing);
    if (!updated) return -1;

    char tmp_path[1024];
    snprintf(tmp_path, sizeof(tmp_path), "%s.mp.tmp.%d", reg_path, (int)getpid());
    FILE *out = fopen(tmp_path, "wb");
    if (!out) {
        free(updated);
        return -1;
    }
    size_t len = strlen(updated);
    bool ok = (fwrite(updated, 1, len, out) == len);
    fclose(out);
    free(updated);

    if (!ok || rename(tmp_path, reg_path) != 0) {
        unlink(tmp_path);
        return -1;
    }
    return 0;
}
