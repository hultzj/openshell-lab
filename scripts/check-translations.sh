#!/usr/bin/env bash
# Keeps each translation (content-<lang>) in step with the English guide (content), which is the one
# verified on a live cluster: same pages, byte-identical commands and assertions, one localized
# Expected result per English one, the same attributes, and media taken from the English component.
# Usage: bash scripts/check-translations.sh [lang...]   (default: ja ko zh)
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

en=content/modules/ROOT/pages
en_only=92-facilitator-guide.adoc  # facilitators read English; translations link to it
failed=0
fail() { printf 'check-translations: %s\n' "$*" >&2; failed=1; }

marker() { case $1 in ja) echo '期待される結果:' ;; ko) echo '예상 결과:' ;; zh) echo '预期结果:' ;; esac; }
page_lang() { case $1 in zh) echo zh-CN ;; *) echo "$1" ;; esac; }
# Every [source] line plus every line of every listing (----) or literal (....) block, in order. A fence is
# four or more of the same character and closes only on an identical line. Lines starting with marker $2 (the
# Expected result label) appear as @expected, or @expected-empty if nothing follows the label, so a translated
# Expected result must keep its place among the commands and say something.
code() { awk -v mk="$2" '
  fence == "" && /^\[source/ { print; next }
  fence == "" && /^(----+|\.\.\.\.+)$/ { fence = $0; print; next }
  fence != "" { print; if ($0 == fence) fence = ""; next }
  index($0, mk) == 1 { rest = substr($0, length(mk) + 1); print (rest ~ /[^ \t]/ ? "@expected" : "@expected-empty") }' "$1"; }
attrs() { awk '/^asciidoc:/ { a = 1 } a' "$1" | grep -v '^    page-lang:'; }

langs=("$@"); [[ $# -eq 0 ]] && langs=(ja ko zh)
for lang in "${langs[@]}"; do
  root=content-$lang
  tr=$root/modules/ROOT/pages
  nav=$root/modules/ROOT/nav.adoc
  mk=$(marker "$lang")
  [[ -n $mk ]] || { fail "$lang: no Expected result marker defined in this script"; continue; }
  [[ -d $tr && -f $nav && -f $root/antora.yml ]] || { fail "$root is incomplete (antora.yml, nav.adoc, pages/)"; continue; }

  grep -qx "name: $lang" "$root/antora.yml" || fail "$root/antora.yml: name must be $lang"
  grep -qx "    page-lang: $(page_lang "$lang")" "$root/antora.yml" || fail "$root/antora.yml: needs page-lang: $(page_lang "$lang")"
  diff <(attrs content/antora.yml) <(attrs "$root/antora.yml") >&2 ||
    fail "$root/antora.yml: asciidoc attributes differ from content/antora.yml"
  grep -Fq "xref:modules::$en_only[" "$nav" || fail "$nav must link the English xref:modules::$en_only[]"
  grep -qs '^// UNVERIFIED' "$tr"/*.adoc && fail "$tr: // UNVERIFIED steps"

  for page in "$en"/*.adoc; do
    name=$(basename "$page")
    [[ $name == "$en_only" ]] && continue
    t=$tr/$name
    [[ -f $t ]] || { fail "$t is missing"; continue; }
    grep -Fq "xref:$name[" "$nav" || fail "$t is not in $nav"
    diff <(code "$page" 'Expected result:') <(code "$t" "$mk") >&2 ||
      fail "$t: commands, assertions or Expected results ($mk) differ from $page"
    ne=$(grep -c '^\[%collapsible\]' "$page"); nt=$(grep -c '^\[%collapsible\]' "$t")
    [[ $ne == "$nt" ]] || fail "$t: $nt collapsible blocks, English has $ne"
    grep -Fq "xref:$en_only[" "$t" && fail "$t: link the facilitator guide as xref:modules::$en_only[]"
    # Media lives once, in the English component.
    while IFS= read -r ref; do
      [[ -f content/modules/ROOT/assets/images/$ref ]] || fail "$t: media $ref is not in the English assets"
    done < <(grep -oE '^image::modules::[^[]+' "$t" | sed 's/^image::modules:://'
             grep -oE '^video::\.\./\.\./modules/_images/[^[]+' "$t" | sed 's#.*/_images/##'
             grep -oE 'poster=\.\./\.\./modules/_images/[^],]+' "$t" | sed 's#.*/_images/##')
    awk '(/^image::/ && !/^image::modules::/) || (/^video::/ && !/^video::\.\.\/\.\.\/modules\/_images\//) ||
         (/poster=/ && !/poster=\.\.\/\.\.\/modules\/_images\//) { print FILENAME ":" FNR ": " $0; bad = 1 }
         END { exit !bad }' "$t" >&2 &&
      fail "$t: use image::modules::<file>[] and video::../../modules/_images/<file>[poster=../../modules/_images/<file>]"
  done
  for t in "$tr"/*.adoc; do
    [[ -f $en/$(basename "$t") && $(basename "$t") != "$en_only" ]] || fail "$t has no English page to translate"
  done
done

[[ $failed -eq 0 ]] && echo "check-translations: OK"
exit "$failed"
