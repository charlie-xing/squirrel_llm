// encoding: utf-8
//
// Copyright RIME Developers
// Distributed under the BSD License
//
// 2025-03-17 Charlie Xing <xingchengli@gmail.com>
//
#include <utf8.h>
#include <rime/commit_history.h>
#include <rime/common.h>
#include <rime/composition.h>
#include <rime/context.h>
#include <rime/engine.h>
#include <rime/key_event.h>
#include <rime/key_table.h>
#include <rime/menu.h>
#include <rime/schema.h>
#include <rime/translation.h>
#include <rime/gear/llm.h>
#include <iostream>
#include "rime/processor.h"
#include "rime_api.h"
#include <rime/llmchain.h>

namespace rime {
void LlmConfig::LoadConfig(Engine* engine, bool load_symbols) {
  Config* config = engine->schema()->config();
  {
    string configured;
    if (config->GetString("llm/llm_pinyin",&configured)){
        llm_pinyin_ = configured;
    }
  }
  {
    string configured;
    if (config->GetString("llm/url_pinyin",&configured)){
        url_pinyin_ = configured;
    }
  }
  {
    string configured;
    if (config->GetString("llm/llm_chat",&configured)){
        llm_chat_ = configured;
    }
  }

  config->GetInt("llm/llm_start_num",&llm_start_num_);
  if (llm_start_num_ < 1){
      llm_start_num_ = 5;
  }
}

Llm::Llm(const Ticket& ticket) : Processor(ticket) {
  Config* config = engine_->schema()->config();
  if (config) {
    config->GetBool("Llm/use_llm", &use_llm_);
  }
  LOG(INFO) << "LLM config loaded ... ...";
  std::cout << "Llm llm_pinyin:" <<config_.llm_pinyin_ << std::endl;
  std::cout << "Llm url_pinyin:" <<config_.url_pinyin_ << std::endl;
  std::cout << "Llm llm_chat:" <<config_.llm_chat_ << std::endl;
  std::cout << "Llm llm_start_num:" <<config_.llm_start_num_ << std::endl;
}

//进入大模型输入状态
//1:候选词部分开始拼音模型交互进行更新
//2:进入这种状态后输入的字母不在进行其他ProcessKeyEvent
//3:拼音和标点符号允许进行输入，不再做为autocommit触发
ProcessResult Llm::ProcessKeyEvent(const KeyEvent& key_event) {
  return kNoop;
  if (key_event.release() || key_event.ctrl() || key_event.alt() ||
      key_event.super())
    return kNoop;
  int ch = key_event.keycode();
  string key(1, ch);
  std::cout << "Llm Process: '" << key << "'" << std::endl;
  num_press_++;
  std::cout << "Llm num_press:'"<< num_press_ <<"'" << std::endl;

  if (ch < 0x20 || ch >= 0x7f)
    return kNoop;

  Context* ctx = engine_->context();
  string prompt=ctx->GetPreedit().text;
  int len=prompt.length();
  std::cout<<"Prompt:"<<prompt<<std::endl;
  std::cout<<"Len:"<<len<<std::endl;
  std::cout<<"DICT RETURN:"<<ctx->GetCommitText()<<std::endl;

  const Composition& comp = ctx->composition();
  std::cout << "comp.  : [" << comp.GetDebugText() << "]" << std::endl;

  if (len >= config_.llm_start_num_ * 4) {
    std::cout<<ctx->GetPreedit().text<<std::endl;
    prompt.erase(std::remove(prompt.begin(), prompt.end(), ' '), prompt.end());
    string result = py_generate(config_.url_pinyin_, config_.llm_pinyin_, prompt,true);
    std::cout << "Final result: " << result << std::endl;
    ctx->Clear();
    ctx->PushInput(result) && ctx->Commit();
    return kAccepted;
  }

  return kNoop;
  }

  LlmTranslator::LlmTranslator(const Ticket& ticket): Translator(ticket) {
    config_.LoadConfig(engine_, "Llm/use_llm");
    lastResult = "";
    lastProcessedPrompt_ = "";
    worker_thread_ = std::thread(&LlmTranslator::WorkerLoop, this);
    firstLlm_=0;
  }

  LlmTranslator::~LlmTranslator() {
    {
      std::lock_guard<std::mutex> lock(worker_mutex_);
      shutdown_ = true;
      worker_cv_.notify_one();
    }
    if (worker_thread_.joinable()) {
      worker_thread_.join();
    }
    firstLlm_=0;
  }

  void LlmTranslator::WorkerLoop() {
    while (true) {
      string prompt_to_process;
      {
        std::unique_lock<std::mutex> lock(worker_mutex_);
        // Wait until there is a new request or shutdown is signaled.
        worker_cv_.wait(lock, [this] { return !request_text_.empty() || shutdown_; });

        if (shutdown_) return;

        // Debounce: Keep consuming incoming requests until there's a 500ms pause.
        prompt_to_process = request_text_;
        request_text_.clear();
        while(true) {
          // Wait for 500ms. If we time out, break and process.
          // If we get notified with a new request, consume it and restart the timer.
          if (firstLlm_ == 1){
              break;
          }

          if (worker_cv_.wait_for(lock, std::chrono::milliseconds(500)) == std::cv_status::timeout) {
            break; // Inactivity detected, proceed to process.
          }
          if (shutdown_) return;

          prompt_to_process = request_text_;
          request_text_.clear();
        }
      } // Unlock mutex before slow operation.

      // Process the last valid prompt received after the debounce period.
      if (prompt_to_process.empty() || prompt_to_process == lastProcessedPrompt_) {
        continue;
      }

      std::cout << "[Worker] Calling LLM for: \"" << prompt_to_process << "\"" << std::endl;
      string result = py_generate(config_.url_pinyin_, config_.llm_pinyin_, prompt_to_process, true);

      if (result != "__BAD__" && result != "__TIMEOUT__" && !result.empty()) {
        // No lock needed for lastResult if we assume string assignment is atomic enough for this use case.
        // The main thread only reads, worker thread only writes.
        lastResult = result;
        lastProcessedPrompt_ = prompt_to_process;

        std::cout << "[Worker] LLM result updated: " << result << std::endl;

        // Trigger UI update on the main thread.
        if (engine_ && engine_->context()) {
          Context* ctx = engine_->context();
          std::cout << "[Worker] Attempting to update candidate list..." << std::endl;
          std::cout << "[Worker] Composition empty: " << ctx->composition().empty() << std::endl;

          // 直接更新第一个候选词的内容
          if (!ctx->composition().empty()) {
            Segment& seg = ctx->composition().back();
            std::cout << "[Worker] Segment has menu: " << (seg.menu ? "yes" : "no") << std::endl;
            if (seg.menu) {
              std::cout << "[Worker] Candidate count: " << seg.menu->candidate_count() << std::endl;
            }

            if (seg.menu && seg.menu->candidate_count() > 0) {
              auto cand = seg.menu->GetCandidateAt(0);
              std::cout << "[Worker] Got candidate at 0: " << (cand ? "yes" : "no") << std::endl;

              if (cand) {
                std::cout << "[Worker] Original candidate text: " << cand->text() << std::endl;
                std::cout << "[Worker] Original candidate type: " << cand->type() << std::endl;

                // 尝试转换为 SimpleCandidate 以便修改
                auto simple_cand = As<SimpleCandidate>(cand);
                std::cout << "[Worker] Cast to SimpleCandidate: " << (simple_cand ? "success" : "failed") << std::endl;

                if (simple_cand) {
                  simple_cand->set_text(result);
                  std::cout << "[Worker] Updated first candidate text to: " << result << std::endl;
                  std::cout << "[Worker] Verification - new text: " << simple_cand->text() << std::endl;
                }
              }
            }
          }
          // 通知UI更新
          std::cout << "[Worker] Calling update_notifier..." << std::endl;
          ctx->update_notifier()(ctx);
          std::cout << "[Worker] Update notifier called successfully" << std::endl;
        }
      } else {
        std::cout << "[Worker] LLM call failed, keeping old cache" << std::endl;
      }
    }
  }

  an<Candidate> CreateLlmCandidate(const string& punct,
                                     const Segment& segment) {
    std::cout<<"Segment start:"<<segment.start<<std::endl;
    std::cout<<"Segment end:"<<segment.end<<std::endl;
    std::cout<<"Segment prompt:"<<segment.prompt<<std::endl;
    return New<SimpleCandidate>("abc", segment.start, segment.end, punct,"","");
  }

  an<Translation> LlmTranslator::Query(const string& input,
                                         const Segment& segment) {
    int len = input.length();
    string prompt = input;

    // 核心判断：只有达到最小长度阈值才处理
    if (len >= config_.llm_start_num_ * 4) {
      if (len == config_.llm_start_num_ * 4 ){
          firstLlm_ = 1;
      }else{
          firstLlm_ = 0;
      }

      prompt.erase(std::remove(prompt.begin(), prompt.end(), ' '), prompt.end());

      // If the core prompt hasn't changed, or is now empty, do nothing.
      // The worker thread might still be processing the old prompt.
      if (prompt == lastProcessedPrompt_ || prompt.empty()) {
        if (!lastResult.empty()) {
            return New<UniqueTranslation>(CreateLlmCandidate(lastResult, segment));
        }
        return nullptr;
      }

      // The prompt has changed. Submit it to the worker thread.
      {
        std::lock_guard<std::mutex> lock(worker_mutex_);
        request_text_ = prompt;
        worker_cv_.notify_one();
      }

      // Immediately return the last known good result to keep UI responsive.
      if (!lastResult.empty()) {
        std::cout << "[Query] Returning cached result while worker is processing: " << lastResult << std::endl;
        return New<UniqueTranslation>(CreateLlmCandidate(lastResult, segment));
      }
    }

    // Input is too short or no cached result is available yet.
    lastResult = "";
    return nullptr;
  }
}  // namespace rime
