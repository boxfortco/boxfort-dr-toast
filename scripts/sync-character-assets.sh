#!/usr/bin/env bash
# Copy character JPGs from iOS asset catalogs into web/public for Vercel.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IOS_ASSETS="$ROOT/Imposter with Dr. Toast/Assets.xcassets"
WEB_CHAR_DIR="$ROOT/web/public/characters"

mkdir -p "$WEB_CHAR_DIR"

copy_one() {
  local asset_name="$1"
  local src_dir="$IOS_ASSETS/${asset_name}.imageset"
  local dest="$WEB_CHAR_DIR/${asset_name}.jpg"

  if [[ ! -d "$src_dir" ]]; then
    echo "WARN: Missing imageset: $src_dir"
    return 0
  fi

  shopt -s nullglob
  local candidates=("$src_dir"/*.jpg "$src_dir"/*.jpeg "$src_dir"/*.JPG "$src_dir"/*.JPEG)
  shopt -u nullglob

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "WARN: No JPG/JPEG found in $src_dir"
    return 0
  fi

  cp "${candidates[0]}" "$dest"
  echo "Copied $asset_name -> $dest"
}

copy_png() {
  local asset_name="$1"
  local src_dir="$IOS_ASSETS/${asset_name}.imageset"
  local dest="$WEB_CHAR_DIR/${asset_name}.png"

  if [[ ! -d "$src_dir" ]]; then
    echo "WARN: Missing imageset: $src_dir"
    return 0
  fi

  shopt -s nullglob
  local candidates=("$src_dir"/*.png "$src_dir"/*.PNG)
  shopt -u nullglob

  if [[ ${#candidates[@]} -eq 0 ]]; then
    echo "WARN: No PNG found in $src_dir"
    return 0
  fi

  cp "${candidates[0]}" "$dest"
  echo "Copied $asset_name -> $dest"
}

copy_one "detective_toast"
copy_png "detective_toast_logo"
copy_one "burnt_toast"
copy_one "chief_loaf"
copy_one "detective_toast_panic"
copy_one "burnt_toast_won"
copy_one "detectives_won"

echo "Done. Web character assets are ready in $WEB_CHAR_DIR"
