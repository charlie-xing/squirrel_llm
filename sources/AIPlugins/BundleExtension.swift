//
//  BundleExtension.swift
//  Squirrel
//
//  AI Plugins Bundle 资源加载扩展
//

import Foundation

extension Bundle {
    /// AI Plugins 资源 Bundle
    /// 用于替代 SPM 的 .module bundle
    static var aiPlugins: Bundle {
        // 首先尝试从 Resources/AIPlugins 加载
        if let path = Bundle.main.resourcePath,
           let bundle = Bundle(path: path + "/AIPlugins") {
            return bundle
        }

        // 如果找不到,回退到 main bundle
        return Bundle.main
    }
}
