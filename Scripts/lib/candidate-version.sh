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

akuo_capture_clean_source_revision() {
    local project_root="$1"
    local worktree_status

    if ! AKUO_SOURCE_REVISION="$(
        git -C "$project_root" rev-parse --verify HEAD 2>/dev/null
    )"; then
        echo 'candidate packaging requires a Git worktree with a committed HEAD' >&2
        return 1
    fi
    if ! worktree_status="$(
        git -C "$project_root" status --porcelain=v1 --untracked-files=all
    )"; then
        echo 'cannot inspect candidate source worktree state' >&2
        return 1
    fi
    if [[ -n "$worktree_status" ]]; then
        echo 'candidate source worktree must be clean' >&2
        return 1
    fi
}

akuo_assert_source_unchanged() {
    local project_root="$1"
    local expected_revision="$2"
    local current_revision
    local worktree_status

    if ! current_revision="$(
        git -C "$project_root" rev-parse --verify HEAD 2>/dev/null
    )" || ! worktree_status="$(
        git -C "$project_root" status --porcelain=v1 --untracked-files=all
    )" || [[ "$current_revision" != "$expected_revision" || -n "$worktree_status" ]]; then
        echo 'candidate source changed during packaging' >&2
        return 1
    fi
}

akuo_require_complete_release_tags() {
    local project_root="$1"
    local local_tags
    local local_inventory=""
    local origin_response
    local origin_inventory
    local tag
    local tag_object

    if ! origin_response="$(
        git -C "$project_root" ls-remote --tags --refs origin 'refs/tags/v*'
    )"; then
        echo 'cannot query release tags from origin' >&2
        return 1
    fi
    if [[ -z "$origin_response" ]]; then
        echo 'origin has no release tags' >&2
        return 1
    fi
    if ! origin_inventory="$(printf '%s\n' "$origin_response" | awk '
        $0 !~ /^[0-9a-f]{40}[[:space:]]+refs\/tags\/v[^[:space:]]+$/ { invalid = 1 }
        { print $1 "\t" $2 }
        END { if (NR == 0 || invalid) exit 1 }
    ')"; then
        echo 'cannot prove complete released-tag provenance: malformed origin response' >&2
        return 1
    fi
    if ! local_tags="$(git -C "$project_root" tag --list 'v*')"; then
        echo 'cannot enumerate local release tags' >&2
        return 1
    fi
    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        if ! tag_object="$(
            git -C "$project_root" rev-parse --verify "refs/tags/$tag" 2>/dev/null
        )"; then
            echo 'cannot resolve a local release tag' >&2
            return 1
        fi
        local_inventory+="${tag_object}"$'\t'"refs/tags/${tag}"$'\n'
    done <<<"$local_tags"

    local_inventory="$(printf '%s' "$local_inventory" | LC_ALL=C sort)"
    origin_inventory="$(printf '%s\n' "$origin_inventory" | LC_ALL=C sort)"
    if [[ "$local_inventory" != "$origin_inventory" ]]; then
        echo 'local release tags do not match origin' >&2
        return 1
    fi
    AKUO_RELEASE_TAGS="$local_tags"
}

akuo_validate_candidate_history() {
    local project_root="$1"
    local shallow_state
    local head_commit
    local tag
    local tag_commit
    local exact_release=false
    local revisions
    local revision

    if ! head_commit="$(git -C "$project_root" rev-parse --verify HEAD 2>/dev/null)"; then
        echo 'candidate packaging requires a Git worktree with a committed HEAD' >&2
        return 1
    fi
    if ! shallow_state="$(
        git -C "$project_root" rev-parse --is-shallow-repository 2>/dev/null
    )" || [[ "$shallow_state" != false ]]; then
        echo 'candidate packaging requires complete, non-shallow history' >&2
        return 1
    fi
    akuo_require_complete_release_tags "$project_root" || return 1

    while IFS= read -r tag; do
        [[ -n "$tag" ]] || continue
        if ! tag_commit="$(
            git -C "$project_root" rev-parse --verify "$tag^{commit}" 2>/dev/null
        )"; then
            printf 'cannot inspect release tag %s\n' "$tag" >&2
            return 1
        fi
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
    done <<<"$AKUO_RELEASE_TAGS"

    if ! revisions="$(git -C "$project_root" rev-list --all --reflog)"; then
        echo 'cannot enumerate candidate source history' >&2
        return 1
    fi
    while IFS= read -r revision; do
        [[ -n "$revision" && "$revision" != "$head_commit" ]] || continue
        akuo_read_revision_identity "$project_root" "$revision" || return 1
        if [[ "$exact_release" == true && \
            "$AKUO_REVISION_VERSION" == "$AKUO_CANDIDATE_VERSION" && \
            "$AKUO_REVISION_BUILD" == "$AKUO_CANDIDATE_BUILD" ]]; then
            printf 'candidate identity %s (%s) is assigned to another source revision\n' \
                "$AKUO_CANDIDATE_VERSION" "$AKUO_CANDIDATE_BUILD" >&2
            return 1
        fi
        if [[ "$exact_release" != true ]] && \
            ! akuo_build_is_greater "$AKUO_CANDIDATE_BUILD" "$AKUO_REVISION_BUILD"; then
            printf 'build identity %s is already assigned to another source revision\n' \
                "$AKUO_CANDIDATE_BUILD" >&2
            return 1
        fi
    done <<<"$revisions"
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

akuo_verify_candidate_source_revision() {
    local plist_path="$1"
    local source_revision

    if ! source_revision="$(
        plutil -extract AkuoSourceRevision raw -o - "$plist_path" 2>/dev/null
    )" || [[ "$source_revision" != "$AKUO_SOURCE_REVISION" ]]; then
        echo 'candidate source revision does not match committed HEAD' >&2
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

akuo_verify_runtime_source_revision() {
    local executable_path="$1"
    local runtime_source_revision

    if ! runtime_source_revision="$("$executable_path" --candidate-source-revision)" || \
        [[ "$runtime_source_revision" != "$AKUO_SOURCE_REVISION" ]]; then
        echo 'runtime source revision does not match committed HEAD' >&2
        return 1
    fi
}
