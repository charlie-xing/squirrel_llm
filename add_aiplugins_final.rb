#!/usr/bin/env ruby
# 正确添加 AIPlugins 文件到 Xcode 项目

require 'xcodeproj'

project_path = 'Squirrel.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

puts "📦 项目: #{project.path.basename}"
puts "🎯 目标: #{target.name}"

# 查找 Sources 组
sources_group = project.main_group['Sources'] || project.main_group.new_group('Sources')

# 1. 添加 AIPluginWindowManager.swift
puts "\n➕ 添加 AIPluginWindowManager.swift..."
window_manager_ref = sources_group.new_reference('sources/AIPluginWindowManager.swift')
target.source_build_phase.add_file_reference(window_manager_ref)
puts "   ✓ 已添加"

# 2. 创建 AIPlugins 组（不设置 path，让子组和文件设置自己的path）
puts "\n➕ 创建 AIPlugins 组..."
aiplugins_group = sources_group.new_group('AIPlugins')

# 3. 递归添加 AIPlugins 下的所有 Swift 文件
def add_swift_files_recursively(project_root_group, base_dir_path, target)
  count = 0
  Dir.glob("#{base_dir_path}/**/*.swift").sort.each do |file_path|
    rel_path = file_path.sub("#{base_dir_path}/", '')
    file_name = File.basename(file_path)
    dir_parts = File.dirname(rel_path).split('/').reject { |p| p == '.' }

    # 从根组开始，逐级找到或创建子组
    current_group = project_root_group
    dir_parts.each do |part|
      existing_group = current_group.children.find { |child| child.display_name == part && child.is_a?(Xcodeproj::Project::Object::PBXGroup) }
      if existing_group
        current_group = existing_group
      else
        # 创建新组，不设置 path - 让 Xcode 自动处理
        current_group = current_group.new_group(part)
      end
    end

    # 在当前组中添加文件引用，使用完整的相对路径
    file_ref = current_group.new_reference(file_path)
    file_ref.name = file_name
    target.source_build_phase.add_file_reference(file_ref)
    count += 1
    puts "   ✓ #{rel_path}"
  end
  count
end

swift_count = add_swift_files_recursively(aiplugins_group, 'sources/AIPlugins', target)
puts "\n   📊 共添加 #{swift_count} 个 Swift 文件"

# 4. 添加资源文件
puts "\n➕ 添加 AIPlugins 资源..."
resources_group = project.main_group['Resources'] || project.main_group.new_group('Resources')

# 直接在 Resources 组下添加资源文件，不创建 AIPlugins 子组
['en.lproj', 'zh-Hans.lproj'].each do |lproj|
  lproj_path = "Resources/AIPlugins/#{lproj}"
  if Dir.exist?(lproj_path)
    lproj_ref = resources_group.new_reference(lproj_path)
    lproj_ref.name = lproj
    target.resources_build_phase.add_file_reference(lproj_ref)
    puts "   ✓ #{lproj}"
  end
end

['plugins', 'sdk'].each do |subdir|
  subdir_path = "Resources/AIPlugins/#{subdir}"
  if Dir.exist?(subdir_path)
    subdir_ref = resources_group.new_reference(subdir_path)
    subdir_ref.name = subdir
    target.resources_build_phase.add_file_reference(subdir_ref)
    puts "   ✓ #{subdir}/"
  end
end

icon_path = 'Resources/AIPlugins/AppIcon.icns'
if File.exist?(icon_path)
  icon_ref = resources_group.new_reference(icon_path)
  icon_ref.name = 'AIPlugins_AppIcon.icns'
  target.resources_build_phase.add_file_reference(icon_ref)
  puts "   ✓ AppIcon.icns"
end

# 5. 保存项目
puts "\n💾 保存项目文件..."
project.save
puts "   ✓ 项目文件已更新"

puts "\n✅ 完成！"
puts "\n📝 现在可以编译:"
puts "   make release"
