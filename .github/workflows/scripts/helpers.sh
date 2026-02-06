#!/usr/bin/env bash

# Find a single file that matches pattern.
function file_from_pattern() {
    local pattern=$1
    local -a files

    mapfile -t files < <(find . -maxdepth 1 -type f -regextype posix-extended -regex "$pattern" 2>/dev/null)
    if [[ ${#files[@]} -ne 1 ]]; then
        echo ""
        return
    fi
    echo "${files[0]}"
}

function github_assert() {
    if ! eval "$1"; then
        echo "::error::Assertion failed: $1${2:+ - $2}"
        exit 1
    fi
}

function github_error() {
    echo "::error::Error: $1"
    exit 1
}

# Find file based on pattern, compute and record its checksum.
function checksum_single_file() {
    local pattern=$1
    local -n _registry=$2
    local filename=$(file_from_pattern "$pattern")
    github_assert "[[ -n \"$filename\" ]]" "Could not find matching file: $pattern"
    _registry[$filename]=$(shasum -a 256 "$filename" | awk '{print $1}')
}

# Adapt and relax filename patterns.
# This produces regex patterns suitable for use with `find`.
function adapt_patterns() {
    local -n _patterns=$1
    local -a _adapted
    local temp
    for p in ${_patterns[@]}; do
        temp=".*/${p/v?.?.?/v[0-9]+\\.[0-9]+\\.[0-9]+(-[0-9]+-g[0-9a-f]HASHQUALIFIER)?}"
        temp=$(echo "$temp" | sed 's/\(.*\)HASHQUALIFIER/\1{7}/')
        temp=$(echo "$temp" | sed 's/\(.*\)\.deb/\1\\.deb/')
        _adapted+=("$temp")
    done
    _patterns=$_adapted
}

function serialize_registry() {
    local -n _registry=$1
    for key in "${!_registry[@]}"; do
        printf '%s=%s\n' "$key" "${_registry[$key]}"
    done
}

function deserialize_registry() {
    local data=$1
    local -n _registry=$2
    while IFS='=' read -r key value; do
        _registry[$key]="$value"
    done <<< "$data"
}

# Persist data between steps within the same GitHub actions job.
function github_persist() {
    local key=$1
    local value=$2
    echo "$key<<EOF" >> $GITHUB_OUTPUT
    echo "$value" >> $GITHUB_OUTPUT
    echo "EOF" >> $GITHUB_OUTPUT
}

function compare_registries() {
    local -n _first=$1
    local -n _second=$2
    if [[ ${#_first[@]} -ne ${#_second[@]} ]]; then
        echo "Different number of artifacts recorded between runs"
        return 1
    fi
    for key in "${!_first[@]}"; do
        if [[ ! -v _second[$key] ]]; then
            echo "Artifact not observed in second run: $key"
            return 1
        fi
        
        if [[ "${_first[$key]}" != "${_second[$key]}" ]]; then
            echo "Mismatch for $key: expected '${_first[$key]}', actual '${_second[$key]}'"
            return 1
        fi
    done
    return 0
}

function dump_registry() {
    local id=$1
    local -n _registry=$2
    echo "Full contents of \"$id\":"
    for key in "${!_registry[@]}"; do
        echo "$key=${_registry[$key]}"
    done
}
