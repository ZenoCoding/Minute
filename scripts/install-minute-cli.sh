#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
install_dir="${HOME}/.local/bin"

mkdir -p "$install_dir"
ln -sfn "$repo_root/bin/minute" "$install_dir/minute"

printf 'Installed %s\n' "$install_dir/minute"
case ":${PATH}:" in
    *":${install_dir}:"*) ;;
    *) printf 'Add %s to PATH to run minute directly.\n' "$install_dir" ;;
esac
