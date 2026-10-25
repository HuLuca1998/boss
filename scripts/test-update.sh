#!/bin/zsh
set -euo pipefail
ROOT=${0:A:h:h}
TEST_DIR=$(mktemp -d)
trap 'rm -rf "$TEST_DIR"' EXIT
python3 - "$TEST_DIR" <<'PY'
import pathlib,sys,zipfile,stat
p=pathlib.Path(sys.argv[1])
for name,entry in [('valid','首领助手.app/Contents/file'),('traversal','首领助手.app/../../escape'),('absolute','/escape'),('outside','evil.app/file')]:
    with zipfile.ZipFile(p/(name+'.zip'),'w') as z:z.writestr(entry,'test')
with zipfile.ZipFile(p/'symlink.zip','w') as z:
    i=zipfile.ZipInfo('首领助手.app/link');i.create_system=3;i.external_attr=(stat.S_IFLNK|0o777)<<16;z.writestr(i,'/tmp')
PY
swiftc "$ROOT/BossAssistant/Sources/UpdatePolicy.swift" "$ROOT/BossAssistant/Tests/UpdatePolicyTests.swift" -o "$TEST_DIR/policy-tests"
"$TEST_DIR/policy-tests" "$TEST_DIR"
python3 - "$ROOT" <<'PY'
import importlib.util,pathlib,sys
p=pathlib.Path(sys.argv[1])/'scripts/release.py';spec=importlib.util.spec_from_file_location('release',p);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
for a,b in [('1.3.8','1.3.9'),('1.3.9','1.4.0'),('1.9.9','2.0.0')]:assert m.next_version(a)==b
print('PASS: release version decimal carry')
PY
if [[ ${1:-} == "--installer" ]]; then
  SIGNING_IDENTITY=$(<"$ROOT/BossAssistant/SigningIdentity.txt")
  APP="$ROOT/BossAssistant/build/首领助手.app"
  CURRENT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
  TEST_VERSION=99.0.0
  [[ -d "$APP" ]] || { print -u2 "请先构建应用";exit 1; }
  swiftc -swift-version 5 -D UPDATE_TESTING "$ROOT/BossAssistant/Sources/UpdatePolicy.swift" "$ROOT/BossAssistant/Updater/main.swift" -o "$TEST_DIR/installer-tests" -framework AppKit -framework Security
  ditto "$APP" "$TEST_DIR/old.app"
  ditto "$APP" "$TEST_DIR/new.app"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $TEST_VERSION" "$TEST_DIR/new.app/Contents/Info.plist"
  codesign --force --sign "$SIGNING_IDENTITY" "$TEST_DIR/new.app"
  "$TEST_DIR/installer-tests" verify "$TEST_DIR/new.app" "$TEST_VERSION"
  if "$TEST_DIR/installer-tests" verify "$TEST_DIR/new.app" 99.0.1; then exit 1; fi
  ditto "$TEST_DIR/new.app" "$TEST_DIR/wrong-signer.app"
  codesign --force --sign - "$TEST_DIR/wrong-signer.app"
  if "$TEST_DIR/installer-tests" verify "$TEST_DIR/wrong-signer.app" "$TEST_VERSION"; then exit 1; fi
  if "$TEST_DIR/installer-tests" test-install "$TEST_DIR/old.app" "$TEST_DIR/new.app" "$TEST_VERSION" fail; then exit 1; fi
  "$TEST_DIR/installer-tests" verify "$TEST_DIR/old.app" "$CURRENT_VERSION"
  "$TEST_DIR/installer-tests" test-install "$TEST_DIR/old.app" "$TEST_DIR/new.app" "$TEST_VERSION" success
  "$TEST_DIR/installer-tests" verify "$TEST_DIR/old.app" "$TEST_VERSION"
  print 'tampered' >> "$TEST_DIR/new.app/Contents/MacOS/BossAssistant"
  if "$TEST_DIR/installer-tests" verify "$TEST_DIR/new.app" "$TEST_VERSION"; then exit 1; fi
  if "$TEST_DIR/installer-tests" test-install "$TEST_DIR/old.app" "$TEST_DIR/new.app" "$TEST_VERSION" success; then exit 1; fi
  "$TEST_DIR/installer-tests" verify "$TEST_DIR/old.app" "$TEST_VERSION"
  print 'PASS: fixed signer/version verification, failed-install rollback, successful replacement, tamper rejection; real installed app untouched'
fi
