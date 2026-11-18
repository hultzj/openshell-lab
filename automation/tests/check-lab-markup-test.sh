#!/usr/bin/env bash
# Self-check for check-lab.sh's literal_markup: backticks or *text* left in rendered prose are caught, the same
# characters inside pre, code or script are not.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for fn in literal_markup cjk_gaps; do
  eval "$(sed -n "/^$fn() {/,/^}/p" "$here/../../scripts/check-lab.sh")"
  declare -F $fn >/dev/null || { echo "FAIL: $fn not found in check-lab.sh"; exit 1; }
done
fail=0
expect() {  # expect <0 = flagged|1 = clean> <html> <title>
  rm -rf "$tmp/www"; mkdir -p "$tmp/www/ja"; printf '%s\n' "$2" > "$tmp/www/ja/page.html"
  literal_markup "$tmp/www" >/dev/null; local got=$?
  [[ $got == "$1" ]] || { echo "FAIL: $3 (got $got, want $1)"; fail=1; }
}
expect 0 '<p>期待される結果: `key length: ` に続いて</p>' 'literal backticks in prose'
expect 0 '<p><code>oc</code>를 실행하고 *Start*를 클릭합니다</p>' 'literal bold next to a Korean particle'
expect 1 '<p>Run <code>oc whoami</code> and click <strong>Start</strong>.</p>' 'converted markup'
expect 1 '<pre class="highlight"><code class="language-bash">echo `date` *.yaml *x*</code></pre>' 'markup characters inside pre'
expect 1 '<p>See <code>`backtick`</code> and <code>secret/*</code> or <code>*x*</code></p>' 'markup characters inside code'
expect 1 '<script>var a = `x`; b = *c*;</script><p>ok</p>' 'markup characters inside script'
expect 1 '<p>5 * 3 = 15</p>' 'a lone asterisk'
expect 0 "<p>한글*$(printf '긴%.0s' {1..30})*를 클릭</p>" 'a long unrecognised Korean bold span'
gaps() {  # gaps <0 = flagged|1 = clean> <article html> <title>
  rm -rf "$tmp/www"; mkdir -p "$tmp/www/ja"; printf '<nav>メニュー\n  項目</nav><article class="doc">%s</article>\n' "$2" > "$tmp/www/ja/page.html"
  cjk_gaps "$tmp/www" >/dev/null; local got=$?
  [[ $got == "$1" ]] || { echo "FAIL: $3 (got $got, want $1)"; fail=1; }
}
gaps 0 $'<p>負荷がかかったときの\n動作は測定しません。</p>' 'a line break between Japanese characters'
gaps 0 '<p>角色。  如果登录失败</p>' 'a kept indent between Chinese characters'
gaps 1 '<p>負荷がかかったときの動作は測定しません。</p>' 'joined text'
gaps 1 '<p>OpenShift 上で 1 つの</p>' 'spaces next to Latin text and digits'
gaps 1 $'<p><strong>開始</strong> を</p>' 'space after an element boundary'
gaps 1 $'<pre>メニュー\n  項目</pre><p>ok</p>' 'line breaks inside pre'
rm -rf "$tmp/www"; mkdir -p "$tmp/www"; printf '<p>ok</p>\n' > "$tmp/www/a.html"; printf '<p>`x`</p>\n' > "$tmp/www/b.html"
literal_markup "$tmp/www" >/dev/null || { echo "FAIL: a hit in the second of two files was missed"; fail=1; }
[[ $fail == 0 ]] && echo PASS
exit $fail
