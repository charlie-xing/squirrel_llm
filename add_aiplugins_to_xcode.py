#!/usr/bin/env python3
"""
自动将 AIPlugins 文件添加到 Xcode 项目中
"""

import os
import uuid
import re

def generate_uuid():
    """生成 Xcode 格式的 24 位十六进制 UUID"""
    return uuid.uuid4().hex[:24].upper()

def find_all_swift_files(directory):
    """递归查找所有 Swift 文件"""
    swift_files = []
    for root, dirs, files in os.walk(directory):
        for file in files:
            if file.endswith('.swift'):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, directory)
                swift_files.append(rel_path)
    return sorted(swift_files)

def find_all_resource_files(directory):
    """递归查找所有资源文件"""
    resource_files = []
    extensions = ['.lproj', '.strings', '.js', '.py', '.json', '.icns']

    for root, dirs, files in os.walk(directory):
        # 处理 .lproj 目录
        if root.endswith('.lproj'):
            rel_path = os.path.relpath(root, directory)
            resource_files.append((rel_path, 'folder'))
            continue

        for file in files:
            # 检查文件扩展名
            if any(file.endswith(ext) for ext in extensions):
                full_path = os.path.join(root, file)
                rel_path = os.path.relpath(full_path, directory)
                resource_files.append((rel_path, 'file'))

    return sorted(resource_files)

def read_pbxproj(path):
    """读取 pbxproj 文件"""
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def write_pbxproj(path, content):
    """写入 pbxproj 文件"""
    with open(path, 'w', encoding='utf-8') as f:
        f.write(content)

def add_files_to_project():
    """添加文件到项目"""
    project_root = '/Users/xcl/rime/squirrel_llm'
    pbxproj_path = f'{project_root}/Squirrel.xcodeproj/project.pbxproj'

    print("📁 读取项目文件...")
    content = read_pbxproj(pbxproj_path)

    # 1. 查找所有需要添加的文件
    aiplugins_dir = f'{project_root}/sources/AIPlugins'
    window_manager = 'sources/AIPluginWindowManager.swift'
    resources_dir = f'{project_root}/Resources/AIPlugins'

    print("\n🔍 扫描 AIPlugins 源文件...")
    swift_files = find_all_swift_files(aiplugins_dir)
    print(f"   找到 {len(swift_files)} 个 Swift 文件")

    print("\n🔍 扫描 AIPlugins 资源文件...")
    resource_files = find_all_resource_files(resources_dir)
    print(f"   找到 {len(resource_files)} 个资源文件/目录")

    # 2. 生成 PBXFileReference
    file_references = []
    build_file_refs = []

    # 添加窗口管理器
    wm_uuid = generate_uuid()
    wm_build_uuid = generate_uuid()
    file_references.append(
        f"\t\t{wm_uuid} /* AIPluginWindowManager.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = AIPluginWindowManager.swift; path = sources/AIPluginWindowManager.swift; sourceTree = \"<group>\"; }};"
    )
    build_file_refs.append(
        f"\t\t{wm_build_uuid} /* AIPluginWindowManager.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {wm_uuid} /* AIPluginWindowManager.swift */; }};"
    )

    # 添加 AIPlugins Swift 文件
    swift_uuid_map = {}
    for swift_file in swift_files:
        file_name = os.path.basename(swift_file)
        file_uuid = generate_uuid()
        build_uuid = generate_uuid()
        swift_uuid_map[swift_file] = file_uuid

        file_references.append(
            f"\t\t{file_uuid} /* {file_name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {file_name}; path = sources/AIPlugins/{swift_file}; sourceTree = \"<group>\"; }};"
        )
        build_file_refs.append(
            f"\t\t{build_uuid} /* {file_name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_uuid} /* {file_name} */; }};"
        )

    # 3. 插入到文件中
    print("\n✏️  修改项目文件...")

    # 在 PBXFileReference section 中添加
    ref_section_match = re.search(r'(/\* Begin PBXFileReference section \*/.*?)(\n/\* End PBXFileReference section \*/)', content, re.DOTALL)
    if ref_section_match:
        ref_content = ref_section_match.group(1)
        new_ref_content = ref_content + '\n' + '\n'.join(file_references) + '\n'
        content = content.replace(ref_section_match.group(1), new_ref_content)
        print("   ✓ 添加文件引用")

    # 在 PBXBuildFile section 中添加
    build_section_match = re.search(r'(/\* Begin PBXBuildFile section \*/.*?)(\n/\* End PBXBuildFile section \*/)', content, re.DOTALL)
    if build_section_match:
        build_content = build_section_match.group(1)
        new_build_content = build_content + '\n' + '\n'.join(build_file_refs) + '\n'
        content = content.replace(build_section_match.group(1), new_build_content)
        print("   ✓ 添加编译引用")

    # 在 Sources group 中添加
    sources_group_match = re.search(r'(080E96DDFE201D6D7F000001 /\* Sources \*/ = \{.*?children = \()(.*?)(\);)', content, re.DOTALL)
    if sources_group_match:
        children = sources_group_match.group(2)
        # 添加窗口管理器
        new_child = f"\n\t\t\t\t{wm_uuid} /* AIPluginWindowManager.swift */,"
        new_children = children + new_child
        content = content.replace(sources_group_match.group(2), new_children)
        print("   ✓ 添加到 Sources 组")

    # 在 Sources build phase 中添加
    sources_phase_match = re.search(r'(8D11072C0486CEB800E47090 /\* Sources \*/ = \{.*?files = \()(.*?)(\);)', content, re.DOTALL)
    if sources_phase_match:
        files = sources_phase_match.group(2)
        # 添加所有编译文件
        new_files_list = [f"\n\t\t\t\t{wm_build_uuid} /* AIPluginWindowManager.swift in Sources */,"]
        for swift_file in swift_files:
            file_name = os.path.basename(swift_file)
            # 从 build_file_refs 中找到对应的 UUID
            for ref in build_file_refs:
                if file_name in ref and ' in Sources ' in ref:
                    uuid_match = re.search(r'([A-F0-9]{24})', ref)
                    if uuid_match:
                        new_files_list.append(f"\n\t\t\t\t{uuid_match.group(1)} /* {file_name} in Sources */,")
                    break

        new_files = files + ''.join(new_files_list)
        content = content.replace(sources_phase_match.group(2), new_files)
        print("   ✓ 添加到编译阶段")

    # 4. 保存文件
    print("\n💾 保存项目文件...")
    write_pbxproj(pbxproj_path, content)
    print("   ✓ 项目文件已更新")

    print("\n✅ 完成！")
    print(f"\n📊 统计:")
    print(f"   - 添加源文件: {len(swift_files) + 1} 个")
    print(f"   - 添加资源: {len(resource_files)} 个")

if __name__ == '__main__':
    try:
        add_files_to_project()
    except Exception as e:
        print(f"\n❌ 错误: {e}")
        import traceback
        traceback.print_exc()
