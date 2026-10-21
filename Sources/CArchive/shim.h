#ifndef CHUNKSEEKIT_CARCHIVE_H
#define CHUNKSEEKIT_CARCHIVE_H

#include <sys/types.h>
#include <stdint.h>
#include <stddef.h>

// The macOS SDK ships libarchive's link stub and man pages, but no headers.
// These narrow public ABI declarations match Apple's archive.h/archive_entry.h:
// https://github.com/apple-oss-distributions/libarchive/tree/5649597e7975dd1f8c24ab0176f131f47a1cdae0/libarchive/libarchive
// Copyright and redistribution notice: LICENSE in this directory.
// See the installed archive_read(3) and archive_entry(3) manuals.
struct archive;
struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_format_zip_seekable(struct archive *);
int archive_read_open_memory(struct archive *, const void *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
ssize_t archive_read_data(struct archive *, void *, size_t);
int archive_read_data_skip(struct archive *);
int archive_read_free(struct archive *);
const char *archive_entry_pathname_utf8(struct archive_entry *);
mode_t archive_entry_filetype(struct archive_entry *);
int64_t archive_entry_size(struct archive_entry *);
int archive_entry_is_encrypted(struct archive_entry *);

#define ARCHIVE_OK 0
#define ARCHIVE_EOF 1
#define AE_IFREG ((mode_t)0100000)

#endif
