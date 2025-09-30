// encoding: utf-8
//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2025-03-17 Charlie Xing <xingchengli@gmail.com>
//
#ifndef RIME_LLM_H_
#define RIME_LLM_H_

#include <rime/common.h>
#include <rime/component.h>
#include <rime/config.h>
#include <rime/processor.h>
#include <rime/segmentor.h>
#include <rime/translator.h>
#include <rime/gear/shape.h>
#include <thread>
#include <atomic>
#include <mutex>
#include <condition_variable>

namespace rime {

class Engine;

class LlmConfig {
 public:
  void LoadConfig(Engine* engine, bool load_symbols = false);

  string llm_pinyin_;
  string url_pinyin_;
  string llm_chat_;
  int llm_start_num_;
};

class Llm : public Processor {
 public:
  Llm(const Ticket& ticket);
  virtual ProcessResult ProcessKeyEvent(const KeyEvent& key_event);

 protected:
  string GetLlmPyResult(const string& input);

  LlmConfig config_;
  bool use_llm_ = true;
  int num_press_ = 0;
  map<an<ConfigItem>, int> oddness_;
};

class LlmTranslator : public Translator {
 public:
  LlmTranslator(const Ticket& ticket);
  ~LlmTranslator();
  virtual an<Translation> Query(const string& input, const Segment& segment);

 protected:
  LlmConfig config_;
  std::chrono::steady_clock::time_point lastInputTime;
  string lastResult;
  string lastProcessedPrompt_;  // 上次已处理的prompt

  // Worker thread for asynchronous LLM calls
  void WorkerLoop();
  std::thread worker_thread_;
  std::mutex worker_mutex_;
  std::condition_variable worker_cv_;
  string request_text_;
  bool shutdown_ = false;
};

class LlmCpp {
    public:
        LlmCpp();
};

}  // namespace rime

#endif  // RIME_LLM_H_
