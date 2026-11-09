#!/usr/bin/env bash

# Prepares the LMDZ physics directory (<DIR>/modipsl/modeles/LMDZ/libf/phylmd),
# once the PHYEX and phyex-lmdz source files are put in it, for the compilation:
#  - INCLUDE "shugrad.h" lines are replaced by the content of shugrad.h
#  - with the make build system: files are renamed so that the file names
#    match the module names
#  - without ecrad: some files of the ecrad directory (yom*, abor1, parkind1)
#    are needed by PHYEX, they are linked in the phylmd directory
# The script can be applied several times on the same directory.

set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [-h] [--ecrad] [--make] DIR

Prepares the LMDZ physics source directory DIR/modipsl/modeles/LMDZ/libf/phylmd
for the compilation with PHYEX.

  --ecrad  LMDZ is compiled with ecrad (default: without ecrad)
  --make   LMDZ is compiled with make (default: with fcm)
  DIR      LMDZ directory (the one containing modipsl)
EOF
}

ecrad=0
make=0
dir=""
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0;;
    --ecrad) ecrad=1;;
    --make) make=1;;
    -*) echo "Unknown option: $1" >&2; usage >&2; exit 1;;
    *)
      if [ -n "$dir" ]; then
        echo "Only one directory must be given" >&2; usage >&2; exit 1
      fi
      dir="$1";;
  esac
  shift
done
if [ -z "$dir" ]; then
  echo "The LMDZ directory is missing" >&2; usage >&2; exit 1
fi

target="$dir/modipsl/modeles/LMDZ/libf/phylmd"
if [ ! -d "$target" ]; then
  echo "Directory $target doesn't exist" >&2
  exit 2
fi
cd "$target"

# Moves $1 to $2 only if the files differ, otherwise deletes $1
mvdiff() {
  if [ -e "$2" ] && cmp -s "$1" "$2"; then
    rm -f "$1"
  else
    mv -f "$1" "$2"
  fi
}

#-----------------------------------------------------------------------
# INCLUDE "shugrad.h" replaced by the content of shugrad.h
#-----------------------------------------------------------------------

# Matches an INCLUDE "shugrad.h" line (case insensitive, simple or double quotes)
shugrad_re='^[[:space:]]*[Ii][Nn][Cc][Ll][Uu][Dd][Ee][[:space:]]*["'"'"']shugrad\.h["'"'"'][[:space:]]*$'
files=$(find . \( -type f -o -type l \) \
             \( -name '*.F90' -o -name '*.f90' -o -name '*.F' -o -name '*.f' -o -name '*.h' \) \
             ! -name shugrad.h -print0 | \
        xargs -0 -r grep -s -l -E "$shugrad_re" || true)
if [ -n "$files" ]; then
  if [ ! -f shugrad.h ]; then
    echo "shugrad.h not found in $target" >&2
    exit 3
  fi
  while IFS= read -r file; do
    # The result is written in a new regular file: when the file is a
    # symbolic link, the original file (e.g. in a PHYEX repository) is
    # left untouched
    awk -v re="$shugrad_re" -v inc=shugrad.h '
      $0 ~ re { while ((getline line < inc) > 0) print line; close(inc); next }
      { print }' "$file" > "$file.shugrad_tmp"
    rm -f "$file"
    mv "$file.shugrad_tmp" "$file"
  done <<< "$files"
fi

#-----------------------------------------------------------------------
# make: file names must match module names
#-----------------------------------------------------------------------

if [ $make -eq 1 ]; then
  if [ -e modd_dimphyexn.F90 ]; then
    mvdiff modd_dimphyexn.F90 modd_dimphyex.F90
  fi
  # Modules XXX_n are in files xxxn.F90
  for file in *n.F90; do
    [ -e "$file" ] || continue
    name=${file%n.F90}
    if grep -qiE "^[[:space:]]*END[[:space:]]+MODULE[[:space:]]+${name}_n([[:space:]]|$)" "$file"; then
      mvdiff "$file" "${name}_n.F90"
    fi
  done
  for pair in hypgeo.F90:modi_hypgeo.F90 \
              hypser.F90:modi_hypser.F90 \
              momg.F90:modi_momg.F90 \
              tools.F90:mode_tools.F90 \
              shuman_mf.F90:modi_shuman_mf.F90 \
              shuman_phy.F90:mode_shuman_phy.F90; do
    src=${pair%%:*}
    dst=${pair##*:}
    if [ -e "$src" ]; then
      mvdiff "$src" "$dst"
    fi
  done
fi

#-----------------------------------------------------------------------
# Without ecrad: some ecrad files are needed by PHYEX
#-----------------------------------------------------------------------

if [ $ecrad -eq 0 ]; then
  shopt -s nullglob
  for file in ecrad/yom* ecrad/abor1.F90 ecrad/abor1.intfb.h ecrad/parkind1.F90 \
              ecrad/*/yom* ecrad/*/abor1.F90 ecrad/*/abor1.intfb.h ecrad/*/parkind1.F90; do
    [ -e "$file" ] || continue  # patterns without wildcard are kept by nullglob
    base=$(basename "$file")
    if [ ! -e "$base" ] && [ ! -L "$base" ]; then
      ln -s "$file" "$base"
    fi
  done
  shopt -u nullglob
fi
