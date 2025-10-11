#!/usr/bin/env ruby
# 修复资源文件路径问题

require 'xcodeproj'

project_path = 'Squirrel.xcodeproj'
project = Xcodeproj::Project.open(project_path)
target = project.targets.first

puts "📦 修复资源文件路径..."
puts "🎯 目标: #{target.name}"

# 1. 找到并删除错误的资源引用
puts "\n🗑️  删除错误的资源引用..."
resources_to_remove = []
target.resources_build_phase.files.each do |build_file|
  file_ref = build_file.file_ref
  next unless file_ref

  path = file_ref.real_path.to_s
  # 检查是否是 AIPlugins 相关资源且路径错误
  if path.include?('Resources/AIPlugins/Resources/AIPlugins')
    resources_to_remove << build_file
    puts "   - #{file_ref.display_name}"
  end
end

resources_to_remove.each do |build_file|
  target.resources_build_phase.files.delete(build_file)
end

# 2. 查找 Resources/AIPlugins 组
resources_group = project.main_group['Resources']
if resources_group
  aiplugins_group = resources_group['AIPlugins']

  # 删除组内错误的文件引用
  if aiplugins_group
    puts "\n🗑️  清理 AIPlugins 组..."
    files_to_remove = []
    aiplugins_group.files.each do |file_ref|
      path = file_ref.real_path.to_s
      if path.include?('Resources/AIPlugins/Resources/AIPlugins')
        files_to_remove << file_ref
        puts "   - #{file_ref.display_name}"
      end
    end
    files_to_remove.each { |f| f.remove_from_project }

    # 3. 重新添加正确的资源文件
    puts "\n➕ 重新添加资源文件（使用正确路径）..."

    # 添加本地化资源
    ['en.lproj', 'zh-Hans.lproj'].each do |lproj|
      lproj_path = "Resources/AIPlugins/#{lproj}"
      if Dir.exist?(lproj_path)
        # 直接在 AIPlugins 组下创建引用，使用相对于项目根的路径
        lproj_ref = aiplugins_group.new_reference(lproj_path)
        target.resources_build_phase.add_file_reference(lproj_ref)
        puts "   ✓ #{lproj}"
      end
    end

    # 添加其他资源文件夹
    ['plugins', 'sdk'].each do |subdir|
      subdir_path = "Resources/AIPlugins/#{subdir}"
      if Dir.exist?(subdir_path)
        subdir_ref = aiplugins_group.new_reference(subdir_path)
        target.resources_build_phase.add_file_reference(subdir_ref)
        puts "   ✓ #{subdir}/"
      end
    end

    # 添加图标
    icon_path = 'Resources/AIPlugins/AppIcon.icns'
    if File.exist?(icon_path)
      icon_ref = aiplugins_group.new_reference(icon_path)
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
