#!/usr/bin/env bash

akuo_designated_requirement() {
    codesign -d -r- "$1" 2>&1 | \
        awk '{ sub(/^# /, "") } /^designated => / { print; exit }'
}

akuo_require_mutually_compatible() {
    local installed_path="$1"
    local candidate_path="$2"
    local installed_requirement
    local candidate_requirement

    installed_requirement="$(akuo_designated_requirement "$installed_path")"
    candidate_requirement="$(akuo_designated_requirement "$candidate_path")"
    if [[ -z "$installed_requirement" || -z "$candidate_requirement" ]]; then
        echo "cannot compare code identities: designated requirement is missing" >&2
        return 1
    fi

    codesign --verify --deep --strict \
        -R "=${installed_requirement#designated => }" "$candidate_path" &&
        codesign --verify --deep --strict \
            -R "=${candidate_requirement#designated => }" "$installed_path"
}

akuo_restore_backup() {
    local backup_path="$1"
    local install_path="$2"

    if [[ ! -d "$backup_path" ]]; then
        echo "cannot restore Akuo: recovery backup is missing at $backup_path" >&2
        return 1
    fi
    if [[ -e "$install_path" || -L "$install_path" ]]; then
        echo "cannot restore Akuo: recovery target is occupied at $install_path" >&2
        return 1
    fi

    mv -- "$backup_path" "$install_path"
}
