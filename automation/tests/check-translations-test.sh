#!/usr/bin/env bash
# Self-check for scripts/check-translations.sh on a tiny fake guide: a faithful translation passes, and each
# kind of drift from the verified English guide fails.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd); tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
fail=0

setup() {  # a fresh fake repo with an English guide and a faithful Japanese translation
  rm -rf "$tmp/r"; mkdir -p "$tmp/r/scripts" "$tmp/r/content/modules/ROOT/pages" "$tmp/r/content/modules/ROOT/assets/images" \
    "$tmp/r/content-ja/modules/ROOT/pages"
  cp "$here/../../scripts/check-translations.sh" "$tmp/r/scripts/"
  cd "$tmp/r" || exit 1
  touch content/modules/ROOT/assets/images/{shot.png,clip.mp4,clip-poster.jpg}
  printf 'name: modules\ntitle: Lab\nasciidoc:\n  attributes:\n    lab_user: lab-admin\n' > content/antora.yml
  printf 'name: ja\ntitle: ラボ\nasciidoc:\n  attributes:\n    lab_user: lab-admin\n    page-lang: ja\n' > content-ja/antora.yml
  printf '* xref:01-a.adoc[A]\n* xref:92-facilitator-guide.adoc[F]\n' > content/modules/ROOT/nav.adoc
  printf '* xref:01-a.adoc[A]\n* xref:modules::92-facilitator-guide.adoc[F（英語）]\n' > content-ja/modules/ROOT/nav.adoc
  echo '= F' > content/modules/ROOT/pages/92-facilitator-guide.adoc
  cat > content/modules/ROOT/pages/01-a.adoc <<'EOF'
= A
See xref:92-facilitator-guide.adoc[F].

image::shot.png[A screenshot]

video::clip.mp4[width=800,poster=clip-poster.jpg]

[source,bash,role="execute",subs="attributes+"]
----
oc whoami
----
Expected result: `{lab_user}`.

[%collapsible]
====
----
( oc get pods )
----
====
EOF
  cat > content-ja/modules/ROOT/pages/01-a.adoc <<'EOF'
= A（訳）
xref:modules::92-facilitator-guide.adoc[F（英語）]を参照。

image::modules::shot.png[スクリーンショット]

video::../../modules/_images/clip.mp4[width=800,poster=../../modules/_images/clip-poster.jpg]

[source,bash,role="execute",subs="attributes+"]
----
oc whoami
----
期待される結果: `{lab_user}`。

[%collapsible]
====
----
( oc get pods )
----
====
EOF
}
expect() {  # expect <0|1> <title>
  bash scripts/check-translations.sh ja >/dev/null 2>&1; local got=$?
  [[ $got == "$1" ]] || { echo "FAIL: $2 (got $got, want $1)"; fail=1; }
}
ja=content-ja/modules/ROOT/pages/01-a.adoc
edit() { sed -i.bak "$1" "$2" && rm -f "$2.bak"; }

setup; expect 0 'faithful translation'
setup; edit 's/^oc whoami$/oc whoami --show-token/' $ja; expect 1 'a command was changed'
fence5() { edit 's/^----$/-----/' "$1"; }
setup; fence5 content/modules/ROOT/pages/01-a.adoc; fence5 $ja; expect 0 'five-dash fences, same commands'
setup; fence5 content/modules/ROOT/pages/01-a.adoc; fence5 $ja; edit 's/^oc whoami$/oc delete namespace production/' $ja
expect 1 'a command changed inside five-dash fences'
setup; edit 's/^( oc get pods )$/oc get pods/' $ja; expect 1 'an assertion was changed'
setup; edit 's/role="execute",//' $ja; expect 1 'role="execute" was dropped'
setup; edit 's/^期待される結果:/結果:/' $ja; expect 1 'Expected result marker missing'
setup; edit 's/^期待される結果: .*/期待される結果:/' $ja; expect 1 'Expected result marker left empty'
setup; edit '/^期待される結果:/d' $ja; edit 's/^\[source,bash/期待される結果: `{lab_user}`。\
\
[source,bash/' $ja; expect 1 'Expected result moved before its command'
setup; edit 's/^\[%collapsible\]$//' $ja; expect 1 'collapsible block dropped'
setup; edit 's/^image::modules::/image::/' $ja; expect 1 'image path local to the translation'
setup; edit 's/clip-poster.jpg/nope.jpg/' $ja; expect 1 'poster not in English assets'
setup; edit 's/^video::\.\.\/\.\.\/modules\/_images\//video::/' $ja; expect 1 'video path local to the translation'
setup; edit 's#\.\./\.\./modules/_images/#../#g' $ja; expect 1 'video and poster paths that skip the English component'
setup; edit 's#poster=\.\./\.\./modules/_images/#poster=#' $ja; expect 1 'poster path local to the translation'
setup; edit 's/lab-admin/someone/' content-ja/antora.yml; expect 1 'attributes differ'
setup; edit '/page-lang/d' content-ja/antora.yml; expect 1 'page-lang missing'
setup; edit 's/xref:modules::92/xref:92/' $ja; expect 1 'facilitator guide linked locally'
setup; edit 's/xref:modules::92/xref:92/' content-ja/modules/ROOT/nav.adoc; expect 1 'nav lacks the English facilitator guide'
setup; rm $ja; expect 1 'page missing'
setup; echo '= F' > content-ja/modules/ROOT/pages/92-facilitator-guide.adoc; expect 1 'English-only page translated'
setup; echo '* xref:modules::92-facilitator-guide.adoc[F]' > content-ja/modules/ROOT/nav.adoc; expect 1 'a page is not in the nav'

[[ $fail == 0 ]] && echo PASS
exit $fail
