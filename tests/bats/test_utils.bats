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

# extract_last_message

@test "extract_last_message: 末尾のボーダー行をスキップして実質的な最終行を返す" {
    local content=$'hello world\n╰──────────╯'
    run call_python extract_last_message "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "hello world" ]
}

@test "extract_last_message: 末尾の ❯ 行をスキップしてその前の行を返す" {
    local content=$'actual content\n❯  1. choice'
    run call_python extract_last_message "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "actual content" ]
}

@test "extract_last_message: 空のコンテンツは空文字を返す" {
    run call_python extract_last_message ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "extract_last_message: 100文字を超える行は省略記号で切り詰める" {
    local long_line
    long_line="$(python3 -c "print('x' * 110)")"
    run call_python extract_last_message "$long_line"
    [ "$status" -eq 0 ]
    [ "${#output}" -le 100 ]
    [[ "$output" == *"..." ]]
}

@test "extract_last_message: ボーダー文字のみの行（│╰╯─）はスキップする" {
    local content=$'content line\n│──────────│\n╰──────────╯'
    run call_python extract_last_message "$content"
    [ "$status" -eq 0 ]
    [ "$output" = "content line" ]
}
