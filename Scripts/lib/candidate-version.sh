#!/usr/bin/env bash

akuo_version_declaration_count() {
    local source_path="$1"
    local declaration_name="$2"

    awk -v name="$declaration_name" '
        $0 ~ "^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+" name "([[:space:]]|=)" {
            count += 1
        }
        END { print count + 0 }
    ' "$source_path"
}

akuo_version_literal() {
    local source_path="$1"
    local declaration_name="$2"

    sed -E -n \
        's/^[[:space:]]*public[[:space:]]+static[[:space:]]+let[[:space:]]+'"$declaration_name"'[[:space:]]*=[[:space:]]*"([^"]+)"[[:space:]]*$/\1/p' \
        "$source_path"
}

akuo_read_version_literal() {
    local source_path="$1"
    local declaration_name="$2"
    local display_name="$3"
    local declaration_count
    local literal

    declaration_count="$(akuo_version_declaration_count "$source_path" "$declaration_name")"
    if [[ "$declaration_count" -eq 0 ]]; then
        printf 'missing authoritative %s declaration in %s\n' \
            "$display_name" "$source_path" >&2
        return 1
    fi
    if [[ "$declaration_count" -gt 1 ]]; then
        printf 'duplicate authoritative %s declarations in %s\n' \
            "$display_name" "$source_path" >&2
        return 1
    fi

    literal="$(akuo_version_literal "$source_path" "$declaration_name")"
    if [[ -z "$literal" || "$literal" == *$'\n'* ]]; then
        printf 'malformed authoritative %s declaration in %s\n' \
            "$display_name" "$source_path" >&2
        return 1
    fi
    printf '%s\n' "$literal"
}

akuo_read_candidate_identity() {
    local source_path="$1"
    local version
    local build

    version="$(akuo_read_version_literal "$source_path" current current)" || return 1
    build="$(akuo_read_version_literal "$source_path" build build)" || return 1
    if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        printf 'malformed authoritative current declaration in %s\n' "$source_path" >&2
        return 1
    fi
    if [[ ! "$build" =~ ^[1-9][0-9]*$ ]]; then
        printf 'malformed authoritative build declaration in %s\n' "$source_path" >&2
        return 1
    fi

    AKUO_CANDIDATE_VERSION="$version"
    AKUO_CANDIDATE_BUILD="$build"
}

akuo_read_revision_identity() {
    local project_root="$1"
    local revision="$2"
    local revision_tmp
    local source_path
    local plist_path
    local version
    local build_count
    local build
    local plist_version

    revision_tmp="$(mktemp -d "${TMPDIR:-/tmp}/akuo-version-revision.XXXXXX")"
    source_path="$revision_tmp/AkuoCoreVersion.swift"
    plist_path="$revision_tmp/Akuo-Info.plist"
    if ! git -C "$project_root" show \
        "$revision:Sources/AkuoCore/AkuoCoreVersion.swift" >"$source_path"; then
        rm -rf -- "$revision_tmp"
        printf 'cannot inspect candidate identity at Git revision %s\n' "$revision" >&2
        return 1
    fi

    version="$(akuo_read_version_literal "$source_path" current current)" || {
        rm -rf -- "$revision_tmp"
        return 1
    }
    if [[ ! "$version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
        rm -rf -- "$revision_tmp"
        printf 'malformed authoritative current declaration at Git revision %s\n' \
            "$revision" >&2
        return 1
    fi

    build_count="$(akuo_version_declaration_count "$source_path" build)"
    if [[ "$build_count" -gt 1 ]]; then
        rm -rf -- "$revision_tmp"
        printf 'duplicate authoritative build declarations at Git revision %s\n' \
            "$revision" >&2
        return 1
    fi
    if [[ "$build_count" -eq 1 ]]; then
        build="$(akuo_read_version_literal "$source_path" build build)" || {
            rm -rf -- "$revision_tmp"
            return 1
        }
    else
        if ! git -C "$project_root" show \
            "$revision:Configuration/Akuo-Info.plist" >"$plist_path"; then
            rm -rf -- "$revision_tmp"
            printf 'cannot inspect legacy candidate plist at Git revision %s\n' \
                "$revision" >&2
            return 1
        fi
        if ! plist_version="$(
            plutil -extract CFBundleShortVersionString raw -o - "$plist_path" 2>/dev/null
        )" || ! build="$(
            plutil -extract CFBundleVersion raw -o - "$plist_path" 2>/dev/null
        )"; then
            rm -rf -- "$revision_tmp"
            printf 'cannot inspect legacy candidate identity at Git revision %s\n' \
                "$revision" >&2
            return 1
        fi
        if [[ "$plist_version" != "$version" ]]; then
            rm -rf -- "$revision_tmp"
            printf 'legacy candidate identity drift at Git revision %s\n' "$revision" >&2
            return 1
        fi
    fi
    rm -rf -- "$revision_tmp"

    if [[ ! "$build" =~ ^[1-9][0-9]*$ ]]; then
        printf 'malformed authoritative build declaration at Git revision %s\n' \
            "$revision" >&2
        return 1
    fi
    AKUO_REVISION_VERSION="$version"
    AKUO_REVISION_BUILD="$build"
}

akuo_build_is_greater() {
    local candidate="$1"
    local previous="$2"
    local LC_ALL=C

    if [[ "${#candidate}" -gt "${#previous}" ]]; then
        return 0
    fi
    if [[ "${#candidate}" -lt "${#previous}" ]]; then
        return 1
    fi
    [[ "$candidate" > "$previous" ]]
}

akuo_validate_candidate_history() {
    local project_root="$1"
    local head_commit
    local tag
    local tag_commit
    local exact_release=false
    local parent_commit

    if ! head_commit="$(git -C "$project_root" rev-parse --verify HEAD 2>/dev/null)"; then
        echo 'candidate packaging requires a Git worktree with a committed HEAD' >&2
        return 1
    fi

    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        tag_commit="$(git -C "$project_root" rev-parse "$tag^{commit}")"
        akuo_read_revision_identity "$project_root" "$tag^{commit}" || return 1
        if [[ "$AKUO_REVISION_VERSION" == "$AKUO_CANDIDATE_VERSION" && \
            "$AKUO_REVISION_BUILD" == "$AKUO_CANDIDATE_BUILD" ]]; then
            if [[ "$tag_commit" == "$head_commit" ]]; then
                exact_release=true
            else
                printf 'candidate identity %s (%s) was already released by %s\n' \
                    "$AKUO_CANDIDATE_VERSION" "$AKUO_CANDIDATE_BUILD" "$tag" >&2
                return 1
            fi
        fi
    done < <(git -C "$project_root" tag --list 'v*')

    if [[ "$exact_release" == true ]]; then
        return 0
    fi
    if ! parent_commit="$(git -C "$project_root" rev-parse --verify HEAD^ 2>/dev/null)"; then
        return 0
    fi
    akuo_read_revision_identity "$project_root" "$parent_commit" || return 1
    if ! akuo_build_is_greater "$AKUO_CANDIDATE_BUILD" "$AKUO_REVISION_BUILD"; then
        printf '%s\n' \
            'new source revision must advance the authoritative build identity' >&2
        return 1
    fi
}

akuo_assert_versionless_template() {
    local plist_path="$1"

    if plutil -extract CFBundleShortVersionString raw -o - "$plist_path" \
        >/dev/null 2>&1 || \
        plutil -extract CFBundleVersion raw -o - "$plist_path" \
        >/dev/null 2>&1; then
        echo 'committed plist must not declare CFBundleShortVersionString or CFBundleVersion' >&2
        return 1
    fi
}

akuo_verify_candidate_plist() {
    local plist_path="$1"
    local plist_version
    local plist_build

    if ! plist_version="$(
        plutil -extract CFBundleShortVersionString raw -o - "$plist_path" 2>/dev/null
    )" || ! plist_build="$(
        plutil -extract CFBundleVersion raw -o - "$plist_path" 2>/dev/null
    )" || [[ "$plist_version" != "$AKUO_CANDIDATE_VERSION" || \
        "$plist_build" != "$AKUO_CANDIDATE_BUILD" ]]; then
        echo 'candidate plist identity does not match authoritative declaration' >&2
        return 1
    fi
}

akuo_verify_runtime_identity() {
    local executable_path="$1"
    local runtime_identity
    local expected_identity

    expected_identity="${AKUO_CANDIDATE_VERSION}"$'\t'"${AKUO_CANDIDATE_BUILD}"
    if ! runtime_identity="$("$executable_path" --candidate-identity)" || \
        [[ "$runtime_identity" != "$expected_identity" ]]; then
        echo 'runtime candidate identity does not match authoritative declaration' >&2
        return 1
    fi
}
