#!/bin/bash

  # 移除主项目 submodules
  git submodule deinit -f librime plum Sparkle
  git rm librime plum Sparkle
  rm -rf .git/modules/librime .git/modules/plum .git/modules/Sparkle

  # 重新克隆为普通目录
  git clone https://github.com/rime/librime.git
  git clone https://github.com/rime/plum.git
  git clone https://github.com/sparkle-project/Sparkle.git

  # 处理 librime 内部依赖
  cd librime
  rm -rf deps/glog deps/leveldb deps/yaml-cpp deps/googletest deps/marisa-trie deps/opencc
  git clone https://github.com/google/glog.git deps/glog
  git clone https://github.com/google/leveldb.git deps/leveldb
  git clone https://github.com/jbeder/yaml-cpp.git deps/yaml-cpp
  git clone https://github.com/google/googletest.git deps/googletest
  git clone https://github.com/rime/marisa-trie.git deps/marisa-trie
  git clone https://github.com/BYVoid/OpenCC.git deps/opencc

  # 清理所有 .git 目录
  rm -rf .git deps/*/.git .gitmodules
  cd ..

  # 清理主项目
  rm -rf librime/.git plum/.git Sparkle/.git .gitmodules

  # 提交更改
  git add .
  git commit -m "Convert all submodules to regular directories"
