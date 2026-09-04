#!/usr/bin/env bash
set -euo pipefail

AKUO_BUNDLE_ROOT="${1:-}"
AKUO_DIGEST_TMP=""

akuo_cleanup_digest() {
    if [[ -n "$AKUO_DIGEST_TMP" && -d "$AKUO_DIGEST_TMP" ]]; then
        rm -rf -- "$AKUO_DIGEST_TMP"
    fi
}
trap akuo_cleanup_digest EXIT

if [[ "$#" -ne 1 || ! -d "$AKUO_BUNDLE_ROOT" ]]; then
    echo "usage: $0 BUNDLE_PATH" >&2
    exit 2
fi

AKUO_BUNDLE_ROOT="$(cd -- "$AKUO_BUNDLE_ROOT" && pwd -P)"
AKUO_DIGEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/akuo-bundle-digest.XXXXXX")"
AKUO_PATHS="$AKUO_DIGEST_TMP/paths"
AKUO_RECORDS="$AKUO_DIGEST_TMP/records"

find "$AKUO_BUNDLE_ROOT" -mindepth 1 -print0 >"$AKUO_PATHS"
: >"$AKUO_RECORDS"

while IFS= read -r -d '' akuo_path; do
    akuo_relative_path="${akuo_path#"$AKUO_BUNDLE_ROOT"/}"
    akuo_path_hex="$(
        printf '%s' "$akuo_relative_path" |
            od -An -v -tx1 |
            tr -d ' \n'
    )"
    akuo_mode="0000$(stat -f '%Lp' "$akuo_path")"
    akuo_mode="${akuo_mode: -4}"

    if [[ -L "$akuo_path" ]]; then
        printf 'unsupported symbolic link in bundle: %s\n' \
            "$akuo_relative_path" >&2
        exit 1
    elif [[ -d "$akuo_path" ]]; then
        printf '%s\tD %s %s\n' \
            "$akuo_path_hex" "$akuo_mode" "$akuo_path_hex" >>"$AKUO_RECORDS"
    elif [[ -f "$akuo_path" ]]; then
        akuo_size="$(stat -f '%z' "$akuo_path")"
        akuo_file_sha256="$(shasum -a 256 "$akuo_path" | awk '{ print $1 }')"
        printf '%s\tF %s %s %s %s\n' \
            "$akuo_path_hex" "$akuo_mode" "$akuo_path_hex" \
            "$akuo_size" "$akuo_file_sha256" >>"$AKUO_RECORDS"
    else
        printf 'unsupported filesystem entry in bundle: %s\n' \
            "$akuo_relative_path" >&2
        exit 1
    fi
done <"$AKUO_PATHS"

{
    printf '%s\n' 'akuo-bundle-content-v1'
    LC_ALL=C sort -t $'\t' -k1,1 "$AKUO_RECORDS" | cut -f2-
} | shasum -a 256 | awk '{ print $1 }'
