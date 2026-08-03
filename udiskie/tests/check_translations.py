#!/usr/bin/env python3
import json
import os
import sys

def main():
    plugin_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    trans_file = os.path.join(plugin_dir, "translations", "en.json")

    if not os.path.exists(trans_file):
        print(f"Error: Translation file not found at {trans_file}")
        sys.exit(1)

    with open(trans_file, "r", encoding="utf-8") as f:
        translations = json.load(f)

    def flatten_keys(d, prefix=""):
        keys = []
        for k, v in d.items():
            full_key = f"{prefix}.{k}" if prefix else k
            if isinstance(v, dict):
                keys.extend(flatten_keys(v, full_key))
            else:
                keys.append(full_key)
        return keys

    all_keys = set(flatten_keys(translations))

    # Code and manifest files to scan
    scan_files = ["plugin.toml", "service.luau", "status.luau", "panel.luau"]
    combined_content = ""

    for fname in scan_files:
        fpath = os.path.join(plugin_dir, fname)
        if os.path.exists(fpath):
            with open(fpath, "r", encoding="utf-8") as f:
                combined_content += f.read() + "\n"

    missing_keys = []
    for key in sorted(list(all_keys)):
        # Setting label_key and description_key append .label and .description automatically
        base_key = key.replace(".label", "").replace(".description", "")
        if key not in combined_content and base_key not in combined_content:
            missing_keys.append(key)

    if missing_keys:
        print(f"Unused translation key(s) found in translations/en.json:")
        for k in missing_keys:
            print(f"  - {k}")
        sys.exit(1)
    else:
        print(f"✓ All {len(all_keys)} translation keys in translations/en.json are active and used in codebase.")

if __name__ == "__main__":
    main()
