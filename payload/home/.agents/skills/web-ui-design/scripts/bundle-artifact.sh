#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f package.json || ! -f index.html ]]; then
  echo "Error: run this script from a Vite project root containing package.json and index.html" >&2
  exit 1
fi

npm install --save-dev --save-exact vite-plugin-singlefile@2.3.3

config_file=".vite-singlefile.config.ts"
output_dir="dist-singlefile"
trap 'rm -f -- "$config_file"' EXIT

cat > "$config_file" <<'EOF'
import path from "node:path";
import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

export default defineConfig({
  plugins: [react(), viteSingleFile()],
  resolve: {
    alias: {
      "@": path.resolve(process.cwd(), "src"),
    },
  },
  build: {
    assetsInlineLimit: 100_000_000,
    emptyOutDir: true,
    outDir: "dist-singlefile",
  },
});
EOF

rm -rf -- "$output_dir"
rm -f -- bundle.html
npm exec -- vite build --config "$config_file"

source_html="$output_dir/index.html"
[[ -s "$source_html" ]] || {
  echo "Error: Vite did not produce $source_html" >&2
  exit 1
}
cp -- "$source_html" bundle.html

if rg -n '<script[^>]+src=|<link[^>]+rel="stylesheet"|<(img|source)[^>]+src="/' bundle.html; then
  echo "Error: bundle.html still contains external script, stylesheet, or absolute image references" >&2
  exit 1
fi

file_size="$(du -h bundle.html | cut -f1)"
printf 'Bundle complete: %s/bundle.html (%s)\n' "$PWD" "$file_size"
