#!/usr/bin/env bats

load "helpers/common"

# shorten_dir

@test "shorten_dir: ホームディレクトリ以下のパスはチルダで省略される" {
    local home_dir
    home_dir="$(python3 -c 'from pathlib import Path; print(Path.home())')"
    run call_python shorten_dir "$home_dir/project"
    [ "$status" -eq 0 ]
    [[ "$output" == "~/project" ]]
}

@test "shorten_dir: 30文字を超えるパスは先頭が省略記号になる" {
    run call_python shorten_dir "/very/long/path/that/exceeds/thirty/char/limit"
    [ "$status" -eq 0 ]
    [[ "$output" == "..."* ]]
    [ "${#output}" -le 30 ]
}

@test "shorten_dir: 短いパスはそのまま返す" {
    run call_python shorten_dir "/tmp/x"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/x" ]
}

