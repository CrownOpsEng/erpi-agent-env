#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:?usage: normalize-python-links.sh MANAGED_PYTHON_ROOT}"
ROOT="$(CDPATH= cd -- "$ROOT" && pwd -P)"

# uv may create top-level managed-Python convenience links whose targets are
# absolute paths inside the same install root. They are useful aliases, but an
# absolute target cannot survive relocation. Convert only in-root targets to
# root-relative targets; refuse anything external instead of hiding it.
while IFS= read -r -d '' link; do
  target="$(readlink "$link")"
  [[ "$target" == /* ]] || continue
  case "$target" in
    "$ROOT"/*)
      relative="${target#"$ROOT"/}"
      rm -f -- "$link"
      ln -s -- "$relative" "$link"
      ;;
    *)
      echo "Managed Python contains external absolute symlink: $link -> $target" >&2
      exit 1
      ;;
  esac
done < <(find "$ROOT" -mindepth 1 -maxdepth 1 -type l -print0)
