#!/usr/bin/env ruby
# 修复资源文件路径问题 - 直接从 Resources 组引用，不要嵌套在 AIPlugins 组内

require 'xcodeproj'

project_path = 'Squirrel.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

puts "📦 修复资源文件路径..."
puts "🎯 目标: #{target.name}"

# 1. 找到并删除错误的资源引用
puts "\n🗑️  删除所有 AIPlugins 资源引用..."
resources_to_remove = []
target.resources_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  name = file_ref.display_name
  # 删除所有 AIPlugins 相关资源
  if ['en.lproj', 'zh-Hans.lproj', 'plugins', 'sdk', 'AppIcon.icns'].include?(name)
    resources_to_remove << build_file
    puts "   - #{name}"
  end
end

resources_to_remove.each do |build_file|
  target.resources_build_phase.files.delete(build_file)
end

# 2. 从 AIPlugins 组中删除资源文件引用
resources_group = project.main_group['Resources']
if resources_group
  aiplugins_group = resources_group['AIPlugins']

  if aiplugins_group
    puts "\n🗑️  从 AIPlugins 组中移除资源文件..."
    files_to_remove = []
    aiplugins_group.children.each do |child|
      name = child.display_name
      if ['en.lproj', 'zh-Hans.lproj', 'plugins', 'sdk', 'AppIcon.icns'].include?(name)
        files_to_remove << child
        puts "   - #{name}"
      end
    end
    files_to_remove.each { |f| f.remove_from_project }

    # 3. 在 Resources 组下直接添加资源文件
    puts "\n➕ 在 Resources 组下直接添加资源..."

    # 添加本地化资源
    ['en.lproj', 'zh-Hans.lproj'].each do |lproj|
      lproj_path = "Resources/AIPlugins/#{lproj}"
      if Dir.exist?(lproj_path)
        # 直接在 Resources 组下创建引用
        lproj_ref = resources_group.new_reference(lproj_path)
        lproj_ref.name = lproj  # 设置显示名称
        target.resources_build_phase.add_file_reference(lproj_ref)
        puts "   ✓ #{lproj}"
      end
    end

    # 添加其他资源文件夹
    ['plugins', 'sdk'].each do |subdir|
      subdir_path = "Resources/AIPlugins/#{subdir}"
      if Dir.exist?(subdir_path)
        subdir_ref = resources_group.new_reference(subdir_path)
        subdir_ref.name = subdir
        target.resources_build_phase.add_file_reference(subdir_ref)
        puts "   ✓ #{subdir}/"
      end
    end

    # 添加图标
    icon_path = 'Resources/AIPlugins/AppIcon.icns'
    if File.exist?(icon_path)
      icon_ref = resources_group.new_reference(icon_path)
      icon_ref.name = 'AppIcon.icns'
      target.resources_build_phase.add_file_reference(icon_ref)
      puts "   ✓ AppIcon.icns"
    end
  end
end

# 4. 保存项目
puts "\n💾 保存项目文件..."
project.save
puts "   ✓ 项目文件已更新"

puts "\n✅ 修复完成！"
puts "\n📝 现在可以重新编译:"
puts "   make release"
