#!/usr/bin/env bash

akuo_expected_designated_requirement() {
    local team_id="$1"
    local requirement_source

    requirement_source="designated => anchor apple generic and identifier \"app.akuo.Akuo\" and certificate leaf[subject.OU] = \"$team_id\""
    csreq -r "=$requirement_source" -t
}

akuo_requirement_matches_policy() {
    local actual_requirement="$1"
    local team_id="$2"
    local expected_requirement

    expected_requirement="$(akuo_expected_designated_requirement "$team_id")"
    [[ "$actual_requirement" == "$expected_requirement" ]]
}
