#!/usr/bin/env bash
#
# AutoLedger 本地一键构建未签名 IPA
# ================================
# 逻辑与 .github/workflows/build-ipa.yml 保持一致，在 macOS + Xcode 环境下产出：
#   AutoLedger.ipa        未签名 ipa（zip -qry 打包，保留符号链接与权限）
#   artifact-app/AutoLedger.app   未签名 app（部分签名工具需要 .app 而非 .ipa）
#
# 不涉及任何证书 / 描述文件 / Apple ID，产物 100% 未签名，
# 请使用自己的签名工具（Sideloadly / AltStore / 自签证书等）处理后安装。
#
# 依赖：macOS + 完整 Xcode（只有 Command Line Tools 不够）
#       xcodegen（缺失时脚本会尝试 brew install）
#       python3（macOS 一般自带，用于补共享 scheme）

set -euo pipefail

# ---------------------------------------------------------------- 基本路径
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${PROJECT_DIR}"

# ---------------------------------------------------------------- 参数解析
CONFIGURATION="${CONFIGURATION:-Release}"
CLEAN=0
for arg in "$@"; do
  case "${arg}" in
    -h|--help)
      cat <<'USAGE'
AutoLedger 本地一键构建未签名 IPA

用法:
  ./tools/build_local.sh                 # Release 构建
  ./tools/build_local.sh Debug           # Debug 构建
  ./tools/build_local.sh --clean         # 先清空 build/ 与 .xcodeproj 再构建
  CONFIGURATION=Debug ./tools/build_local.sh

产物:
  AutoLedger.ipa                未签名 ipa
  artifact-app/AutoLedger.app   未签名 app（部分签名工具需要）

依赖: macOS + 完整 Xcode + xcodegen + python3
USAGE
      exit 0
      ;;
    --clean)
      CLEAN=1
      ;;
    Debug|Release)
      CONFIGURATION="${arg}"
      ;;
    *)
      echo "未知参数: ${arg}（可用: Debug | Release | --clean | --help）" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------- 常量
SCHEME_NAME="AutoLedger"
PRODUCT_NAME="AutoLedger"
BUNDLE_ID="com.autoledger.app"
XCODE_PROJECT="AutoLedger.xcodeproj"
BUILD_DIR="build"
ARCHIVE_PATH="${BUILD_DIR}/${PRODUCT_NAME}.xcarchive"
APP_PATH="${ARCHIVE_PATH}/Products/Applications/${PRODUCT_NAME}.app"
IPA_PATH="${PRODUCT_NAME}.ipa"
LOG="${PROJECT_DIR}/build.log"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m OK\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 环境检查
log "检查构建环境"
[ "$(uname -s)" = "Darwin" ] || die "本脚本只能在 macOS 上运行（当前: $(uname -s)）"
xcode-select -p >/dev/null 2>&1 || die "未安装 Xcode，请安装完整 Xcode"
xcodebuild -version >/dev/null 2>&1 \
  || die "xcodebuild 不可用，请安装完整 Xcode 并执行 sudo xcode-select -s /Applications/Xcode.app"
command -v python3 >/dev/null 2>&1 || die "找不到 python3（可 brew install python3）"

# 与 CI 一致的 Xcode 选择策略：默认版本最稳（镜像/系统只为默认版本预装 iOS 平台组件）
log "选择 Xcode"
ls -d /Applications/Xcode*.app 2>/dev/null || true
echo "--- 默认 Xcode ---"
xcodebuild -version || true

DEFAULT_MAJOR="$(xcodebuild -version 2>/dev/null | head -1 | sed -E 's/^Xcode ([0-9]+).*/\1/' || true)"
if [ -n "${DEFAULT_MAJOR:-}" ] && [ "${DEFAULT_MAJOR}" -ge 26 ] 2>/dev/null; then
  echo "默认 Xcode 版本 ${DEFAULT_MAJOR}.x，直接使用"
else
  # 否则挑版本号最大的 26.x（按版本排序，不能按字母序取 head）
  CANDIDATE="$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "${CANDIDATE}" ]; then
    echo "切换到 ${CANDIDATE}"
    sudo xcode-select -s "${CANDIDATE}/Contents/Developer"
  fi
fi
echo "--- 使用中的 Xcode ---"
xcode-select -p
xcodebuild -version
echo "--- iphoneos SDK 版本 ---"
xcrun --sdk iphoneos --show-sdk-version
echo "--- 构建配置 ---"
echo "${CONFIGURATION}"

# ---------------------------------------------------------------- XcodeGen
log "准备 XcodeGen"
if ! command -v xcodegen >/dev/null 2>&1; then
  command -v brew >/dev/null 2>&1 || die "未安装 XcodeGen 且找不到 Homebrew。请执行: brew install xcodegen"
  brew install xcodegen
fi
xcodegen --version

# ---------------------------------------------------------------- 生成工程
[ -f "project.yml" ] || die "在 ${PROJECT_DIR} 下找不到 project.yml"

if [ "${CLEAN}" -eq 1 ]; then
  log "清理 ${BUILD_DIR}/、${XCODE_PROJECT}、${LOG}"
  rm -rf "${BUILD_DIR}" "${XCODE_PROJECT}" "${LOG}" Payload "${IPA_PATH}"
fi

log "xcodegen generate"
xcodegen generate --spec project.yml

# project.yml 未声明 scheme:，XcodeGen 不会生成 .xcscheme，
# 而 xcodebuild -scheme 需要共享 scheme 才能 archive。
# 该脚本只写 *.xcodeproj（构建产物、已被 .gitignore 忽略），幂等，已存在则跳过。
log "确保共享 scheme 存在"
python3 "${SCRIPT_DIR}/ensure_scheme.py" . \
  --target "${SCHEME_NAME}" \
  --product "${PRODUCT_NAME}.app" \
  --configuration "${CONFIGURATION}"

xcodebuild -project "${XCODE_PROJECT}" -list

# ---------------------------------------------------------------- archive
# 完全禁用签名：不传 -allowProvisioningUpdates，不指定 TEAM / 描述文件，
# 保证产物是干净的未签名 app，用户自签时不会与已有签名冲突。
build_once() {
  rm -rf "${ARCHIVE_PATH}" "${BUILD_DIR}/DerivedData"
  mkdir -p "${BUILD_DIR}"
  xcodebuild archive \
    -project "${XCODE_PROJECT}" \
    -scheme "${SCHEME_NAME}" \
    -configuration "${CONFIGURATION}" \
    -destination 'generic/platform=iOS' \
    -archivePath "${ARCHIVE_PATH}" \
    -derivedDataPath "${BUILD_DIR}/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    CODE_SIGN_ENTITLEMENTS="" \
    ONLY_ACTIVE_ARCH=NO \
    2>&1 | tee "${LOG}"
}

summarize() {
  echo "================ 错误摘要 ================"
  grep -nE "error:|fatal error:|❌|Command .* failed|failed with a nonzero exit code" \
    "${LOG}" | tail -n 80 || true
  echo "=========================================="
}

log "编译未签名 .app（archive）"
if build_once; then
  ok "archive 完成（当前 Xcode）"
else
  summarize
  echo "=== 当前 Xcode 构建失败，尝试切换其它 Xcode 重试 ==="
  xcodebuild -showdestinations -project "${XCODE_PROJECT}" -scheme "${SCHEME_NAME}" || true

  BUILT=0
  for XCODE in $(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -Vr); do
    echo "--- 尝试 ${XCODE} ---"
    sudo xcode-select -s "${XCODE}/Contents/Developer" || continue
    xcodebuild -version || true
    if build_once; then
      echo "=== 使用 ${XCODE} 构建成功 ==="
      BUILT=1
      break
    fi
    summarize
  done

  [ "${BUILT}" -eq 1 ] || die "所有候选 Xcode 均构建失败，详见 ${LOG}"
fi

[ -d "${ARCHIVE_PATH}" ] || die "archive 未生成: ${ARCHIVE_PATH}"
[ -d "${APP_PATH}" ]     || die "archive 中找不到 ${PRODUCT_NAME}.app: ${APP_PATH}"

# ---------------------------------------------------------------- 未签名确认
log "确认产物未签名"
if [ -d "${APP_PATH}/_CodeSignature" ]; then
  warn "产物中存在 _CodeSignature 目录，正在移除以保证未签名状态"
  rm -rf "${APP_PATH}/_CodeSignature"
fi
if codesign -dv "${APP_PATH}" >/dev/null 2>&1; then
  warn "检测到残留签名，执行移除"
  codesign --remove-signature "${APP_PATH}" || true
fi
if codesign -dv "${APP_PATH}" >/dev/null 2>&1; then
  die "无法移除签名，产物仍有签名（用户自签会冲突）"
fi
ok "产物为未签名 app"

# ---------------------------------------------------------------- 校验
log "校验 app 内容"
[ -f "${APP_PATH}/${PRODUCT_NAME}" ] || die "缺少可执行文件 ${PRODUCT_NAME}"
file "${APP_PATH}/${PRODUCT_NAME}"

FOUND_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Info.plist")"
echo "     Bundle ID: ${FOUND_BUNDLE_ID}"
[ "${FOUND_BUNDLE_ID}" = "${BUNDLE_ID}" ] || die "bundle id 不是预期的 ${BUNDLE_ID}"
/usr/libexec/PlistBuddy -c 'Print :MinimumOSVersion' "${APP_PATH}/Info.plist" 2>/dev/null || true
ok "app 校验通过"

# ---------------------------------------------------------------- 打包 ipa
log "打包未签名 ipa"
rm -rf Payload
mkdir -p Payload
# ditto 比 cp -R 更完整地保留符号链接 / 权限 / 扩展属性
ditto "${APP_PATH}" "Payload/${PRODUCT_NAME}.app"

# 关键：-y 保留符号链接、-r 递归，不能用普通 zip
rm -f "${IPA_PATH}"
zip -qry "${IPA_PATH}" Payload

[ -f "${IPA_PATH}" ] || die "ipa 生成失败"

# 注意：全程有 pipefail，不能把 unzip 输出管道给 head / grep -q
# （它们会提前退出，导致 unzip 收到 SIGPIPE 被判失败），先落文件再检查。
unzip -l "${IPA_PATH}" > "${BUILD_DIR}/ipa-contents.txt"
grep -q "Payload/${PRODUCT_NAME}.app/" "${BUILD_DIR}/ipa-contents.txt" || die "ipa 结构不正确"
ok "ipa 打包完成"

# ---------------------------------------------------------------- 导出 app 副本
rm -rf artifact-app
mkdir -p artifact-app
ditto "${APP_PATH}" "artifact-app/${PRODUCT_NAME}.app"
if [ -n "$(find "artifact-app/${PRODUCT_NAME}.app" -type l -print -quit)" ]; then
  warn ".app 中存在符号链接，若用 zip 分发会丢失链接，建议改用 tar.gz"
fi

# ---------------------------------------------------------------- 完成
echo
log "构建完成"
printf '  IPA : %s  (%s)\n' "${PROJECT_DIR}/${IPA_PATH}" "$(du -h "${IPA_PATH}" | cut -f1)"
printf '  APP : %s\n' "${PROJECT_DIR}/artifact-app/${PRODUCT_NAME}.app"
printf '  日志: %s\n' "${LOG}"
echo
echo "产物完全未签名，请使用自己的签名工具处理后安装。"
echo "提示：免费 Apple ID 签名仅 7 天有效，且重签会清空 App 本地数据，请提前备份。"
