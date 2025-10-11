#!/usr/bin/env ruby
# 使用 xcodeproj gem 来修改 Xcode 项目文件
# 安装: gem install xcodeproj

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
window_manager_ref = sources_group.new_file('sources/AIPluginWindowManager.swift')
target.source_build_phase.add_file_reference(window_manager_ref)
puts "   ✓ 已添加"

# 2. 创建 AIPlugins 组
puts "\n➕ 创建 AIPlugins 组..."
aiplugins_group = sources_group.new_group('AIPlugins', 'sources/AIPlugins')

# 3. 递归添加 AIPlugins 下的所有 Swift 文件
def add_swift_files_recursively(group, dir_path, target)
  count = 0
  Dir.glob("#{dir_path}/**/*.swift").sort.each do |file_path|
    rel_path = file_path.sub("#{dir_path}/", '')
    file_name = File.basename(file_path)

    # 根据相对路径创建子组
    dir_name = File.dirname(rel_path)
    if dir_name != '.'
      # 创建或获取子组
      subgroup = group
      dir_name.split('/').each do |part|
        subgroup = subgroup[part] || subgroup.new_group(part, "#{dir_path}/#{part}")
      end
      file_ref = subgroup.new_file(file_path)
    else
      file_ref = group.new_file(file_path)
    end

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
aiplugins_resources = resources_group.new_group('AIPlugins', 'Resources/AIPlugins')

# 添加本地化资源
['en.lproj', 'zh-Hans.lproj'].each do |lproj|
  lproj_path = "Resources/AIPlugins/#{lproj}"
  if Dir.exist?(lproj_path)
    variant_group = aiplugins_resources.new_variant_group(lproj.sub('.lproj', ''))
    lproj_ref = aiplugins_resources.new_file(lproj_path)
    target.resources_build_phase.add_file_reference(lproj_ref)
    puts "   ✓ #{lproj}"
  end
end

# 添加其他资源文件
['plugins', 'sdk'].each do |subdir|
  subdir_path = "Resources/AIPlugins/#{subdir}"
  if Dir.exist?(subdir_path)
    subdir_ref = aiplugins_resources.new_file(subdir_path)
    target.resources_build_phase.add_file_reference(subdir_ref)
    puts "   ✓ #{subdir}/"
  end
end

# 添加图标
icon_path = 'Resources/AIPlugins/AppIcon.icns'
if File.exist?(icon_path)
  icon_ref = aiplugins_resources.new_file(icon_path)
  target.resources_build_phase.add_file_reference(icon_ref)
  puts "   ✓ AppIcon.icns"
end

# 5. 保存项目
puts "\n💾 保存项目文件..."
project.save
puts "   ✓ 项目文件已更新"

puts "\n✅ 完成！"
puts "\n📝 后续步骤:"
puts "   1. 运行 `make debug` 或 `make release` 进行编译"
puts "   2. 如果遇到编译错误，检查文件路径是否正确"
