#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
promoter = root / ".github/version-identity-promote.py"
text = promoter.read_text(encoding="utf-8")
start_marker = '''replace_once(
    ".github/workflows/build-dist.yml",
    ''' + "'''      - name: Write acceptance metadata"
end_marker = "\n\n# Builder documentation: current-state portability, compatibility contract, and unambiguous package identity."
start = text.index(start_marker)
end = text.index(end_marker, start)
replacement = r'''# Replace the metadata step by stable step-name boundaries instead of matching
# shell continuation syntax inside a Python triple-quoted anchor.
workflow = read(".github/workflows/build-dist.yml")
step_start = workflow.index("      - name: Write acceptance metadata\n")
step_end = workflow.index("      - name: Upload distribution\n", step_start)
new_step_lines = [
    "      - name: Write acceptance metadata",
    "        id: metadata",
    "        shell: bash",
    "        env:",
    "          ACCEPTED_SOURCE_SHA: ${{ steps.source.outputs.sha }}",
    "        run: |",
    "          set -euo pipefail",
    "          sidecar=\"$(printf '%s\\n' dist/*.tar.gz.sha256)\"",
    "          python3 scripts/write-acceptance-metadata.py \\",
    "            --sidecar \"$sidecar\" \\",
    "            --output dist/acceptance.json \\",
    "            --source-sha \"$ACCEPTED_SOURCE_SHA\" \\",
    "            --repository \"$GITHUB_REPOSITORY\" \\",
    "            --workflow \"$GITHUB_WORKFLOW\" \\",
    "            --run-id \"$GITHUB_RUN_ID\" \\",
    "            --run-attempt \"$GITHUB_RUN_ATTEMPT\" \\",
    "            --event \"$GITHUB_EVENT_NAME\" \\",
    "            --release-tag \"$RELEASE_TAG\"",
    "          archive_name=\"$(jq -er '.artifact.filename' dist/acceptance.json)\"",
    "          echo \"name=${archive_name%.tar.gz}\" >> \"$GITHUB_OUTPUT\"",
    "          cat \"$sidecar\"",
    "          {",
    "            echo '```json'",
    "            cat dist/acceptance.json",
    "            echo '```'",
    "          } >> \"$GITHUB_STEP_SUMMARY\"",
    "",
]
write(".github/workflows/build-dist.yml", workflow[:step_start] + "\n".join(new_step_lines) + workflow[step_end:])
'''
promoter.write_text(text[:start] + replacement + text[end:], encoding="utf-8")
Path(__file__).unlink()
print("Qualification transformer repaired.")
