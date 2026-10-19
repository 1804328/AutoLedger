#!/usr/bin/env python3
"""为 XcodeGen 生成的 Xcode 工程补一个共享 scheme。

背景
----
XcodeGen 只有在 project.yml 里显式声明 ``scheme:`` 或 ``schemes:`` 时才会生成
``.xcscheme`` 文件。本仓库的 project.yml 没有声明（且该文件不允许改动），
而 ``xcodebuild archive -scheme AutoLedger`` 需要工程里存在同名共享 scheme 才能工作，
否则会报错：``does not contain a scheme named "AutoLedger"``。

因此 CI 与本地构建脚本都会在 ``xcodegen generate`` 之后、``xcodebuild`` 之前调用本脚本：
若共享 scheme 不存在，就根据 ``project.pbxproj`` 里 AutoLedger 这个 PBXNativeTarget
的真实 UUID 生成一个标准共享 scheme。

本脚本只写入 xcodegen 生成出来的 ``*.xcodeproj``（属于构建产物、已被 .gitignore 忽略），
不会修改任何源码 / project.yml / Info.plist / Assets。

用法
----
    python3 tools/ensure_scheme.py [PROJECT_DIR] [--target AutoLedger] [--configuration Release]

- PROJECT_DIR 默认为当前目录，其中应包含 project.yml 以及生成后的 *.xcodeproj
- 若共享 scheme 已存在则直接跳过（幂等）
"""

import argparse
import re
import sys
from pathlib import Path

SCHEME_TEMPLATE = """<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{uuid}"
               BuildableName = "{product}"
               BlueprintName = "{target}"
               ReferencedContainer = "container:{project}">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "{configuration}"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "{configuration}"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

NATIVE_TARGET_SECTION_RE = re.compile(
    r"/\* Begin PBXNativeTarget section \*/(.*?)/\* End PBXNativeTarget section \*/",
    re.S,
)

# 每个 pbxproj 对象的起始行形如：
#     ABCD1234...24位 /* AutoLedger */ = {
OBJECT_START_RE = re.compile(
    r"^\s*([0-9A-Fa-f]{24})\s*(?:/\*.*?\*/\s*)?=\s*\{", re.M
)

NAME_RE = re.compile(r'\b(?:name|productName)\s*=\s*"?([^";\n]+)"?\s*;')


def find_xcodeproj(project_dir, preferred_name):
    """在工程目录中找到需要处理的 *.xcodeproj。"""
    candidates = sorted(p for p in project_dir.glob("*.xcodeproj") if p.is_dir())
    if not candidates:
        sys.exit(
            "[error] %s 下没有找到 *.xcodeproj，请先执行 xcodegen generate" % project_dir
        )

    preferred = project_dir / ("%s.xcodeproj" % preferred_name)
    if preferred.is_dir():
        return preferred
    if len(candidates) == 1:
        return candidates[0]

    names = ", ".join(p.name for p in candidates)
    sys.exit(
        "[error] %s 下存在多个 xcodeproj（%s），无法自动判断，请显式传入 --target"
        % (project_dir, names)
    )


def find_native_target_uuid(pbxproj_text, target_name):
    """从 project.pbxproj 的 PBXNativeTarget 段里取出指定 target 的 24 位 UUID。

    pbxproj 的对象块里可能嵌套字典（如 buildConfigurationList 的注释），
    所以这里按「对象起始行」切分，而不是靠大括号配对，避免误匹配。
    """
    section = NATIVE_TARGET_SECTION_RE.search(pbxproj_text)
    if not section:
        return None

    body = section.group(1)
    starts = list(OBJECT_START_RE.finditer(body))
    for index, match in enumerate(starts):
        block_end = starts[index + 1].start() if index + 1 < len(starts) else len(body)
        block = body[match.end():block_end]
        if "isa = PBXNativeTarget;" not in block:
            continue
        names = [n.strip() for n in NAME_RE.findall(block)]
        if target_name in names:
            return match.group(1)
    return None


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="为 XcodeGen 生成的工程补齐共享 scheme（xcodebuild -scheme 需要）"
    )
    parser.add_argument(
        "project_dir", nargs="?", default=".", help="包含 project.yml 与 *.xcodeproj 的目录"
    )
    parser.add_argument("--target", default="AutoLedger", help="target / scheme 名称")
    parser.add_argument(
        "--product",
        default=None,
        help="产物文件名，默认 <target>.app（对应 PRODUCT_NAME）",
    )
    parser.add_argument(
        "--configuration", default="Release", help="archive/profile 使用的配置"
    )
    args = parser.parse_args(argv)

    project_dir = Path(args.project_dir).resolve()
    if not project_dir.is_dir():
        sys.exit("[error] 目录不存在：%s" % project_dir)

    product = args.product or ("%s.app" % args.target)

    xcodeproj = find_xcodeproj(project_dir, args.target)
    project_name = xcodeproj.name

    scheme_path = xcodeproj / "xcshareddata" / "xcschemes" / ("%s.xcscheme" % args.target)
    if scheme_path.is_file():
        print("[ok] 共享 scheme 已存在，无需创建：%s" % scheme_path.relative_to(project_dir))
        return 0

    pbxproj = xcodeproj / "project.pbxproj"
    if not pbxproj.is_file():
        sys.exit("[error] 找不到 %s" % pbxproj)

    text = pbxproj.read_text(encoding="utf-8", errors="replace")
    uuid = find_native_target_uuid(text, args.target)
    if not uuid:
        sys.exit(
            "[error] 在 %s 的 PBXNativeTarget 段中找不到名为 %r 的 target。\n"
            "        请确认 project.yml 中 targets 下确实存在该 target。"
            % (pbxproj, args.target)
        )

    scheme_path.parent.mkdir(parents=True, exist_ok=True)
    scheme_path.write_text(
        SCHEME_TEMPLATE.format(
            uuid=uuid,
            product=product,
            target=args.target,
            project=project_name,
            configuration=args.configuration,
        ),
        encoding="utf-8",
    )

    print(
        "[ok] 已创建共享 scheme：%s（BlueprintIdentifier=%s, BuildableName=%s）"
        % (scheme_path.relative_to(project_dir), uuid, product)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
