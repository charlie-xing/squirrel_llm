#include <iostream>
#include <string>
#include <functional>
#include <thread>
#include <chrono>
#include <curl/curl.h>
#include <nlohmann/json.hpp>

using json = nlohmann::json;

// Callback function to handle received data
size_t WriteCallback(char *contents, size_t size, size_t nmemb, void *userp) {
    // Cast the userp pointer to the appropriate function type
    auto callback = static_cast<std::function<void(const std::string&)>*>(userp);

    // Calculate the real size
    size_t realsize = size * nmemb;

    // Process the received chunk
    if (callback && realsize > 0) {
        std::string chunk(contents, realsize);
        (*callback)(chunk);
    }

    return realsize;
}

// Non-blocking API request function
void generateNonBlocking(
    const std::string& url,
    const std::string& model,
    const std::string& prompt,
    std::function<void(const std::string&, bool)> onProgress,
    std::function<void(const std::string&)> onComplete,
    std::function<void(const std::string&)> onError
) {
    // Initialize result string to accumulate responses
    std::string accumulatedResponse;

    // Create a new CURL easy handle
    CURL* curl = curl_easy_init();
    if (!curl) {
        onError("Failed to initialize curl");
        return;
    }

    // Set up the callback function to process data as it arrives
    std::function<void(const std::string&)> processChunk = [&accumulatedResponse, onProgress, onComplete](const std::string& chunk) {
        try {
            // Parse the JSON chunk
            json response = json::parse(chunk);

            // Extract the response text and done flag
            std::string responseText = response["response"].get<std::string>();
            bool done = response["done"].get<bool>();

            // Accumulate response
            accumulatedResponse += responseText;

            // Notify progress with the current chunk and done status
            onProgress(responseText, done);

            // If done is true, call the completion callback
            if (done) {
                onComplete(accumulatedResponse);
            }
        } catch (const std::exception& e) {
            // Handle any parsing errors
            std::cerr << "Error parsing JSON: " << e.what() << std::endl;
            std::cerr << "Problematic chunk: " << chunk << std::endl;
        }
    };

    // Prepare the POST data
    json postData = {
        {"model", model},
        {"prompt", prompt}
    };
    std::string postDataStr = postData.dump();

    // Set the URL
    curl_easy_setopt(curl, CURLOPT_URL, url.c_str());

    // Disable proxy usage - ignore system proxy settings
    curl_easy_setopt(curl, CURLOPT_PROXY, "");

    // Set the POST request
    curl_easy_setopt(curl, CURLOPT_POST, 1L);
    curl_easy_setopt(curl, CURLOPT_POSTFIELDS, postDataStr.c_str());
    curl_easy_setopt(curl, CURLOPT_POSTFIELDSIZE, postDataStr.length());

    // Set up headers
    struct curl_slist* headers = nullptr;
    headers = curl_slist_append(headers, "Content-Type: application/json");
    curl_easy_setopt(curl, CURLOPT_HTTPHEADER, headers);

    // Set up the write callback function
    curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, WriteCallback);
    curl_easy_setopt(curl, CURLOPT_WRITEDATA, &processChunk);

    // Make the request non-blocking by using multi interface
    CURLM* multi_handle = curl_multi_init();
    curl_multi_add_handle(multi_handle, curl);

    // Start the transfer
    int still_running = 1;
    while (still_running) {
        CURLMcode mc = curl_multi_perform(multi_handle, &still_running);
        if (still_running) {
            // Wait for activity on the connection
            mc = curl_multi_poll(multi_handle, nullptr, 0, 1000, nullptr);
        }

        if (mc != CURLM_OK) {
            onError("curl_multi failed, code " + std::to_string(mc));
            break;
        }
    }

    // Clean up
    curl_multi_remove_handle(multi_handle, curl);
    curl_multi_cleanup(multi_handle);
    curl_easy_cleanup(curl);
    curl_slist_free_all(headers);
}

// Synchronous version of the function that returns the final result
std::string py_generate(const std::string& url, const std::string& model, const std::string& prompt, const bool first_flag) {
    std::string finalResult;
    bool completed = false;

    // Set up handlers
    auto onProgress = [](const std::string& chunk, bool done) {
        // Optional: print progress
        // std::cout << "Received chunk: " << chunk << (done ? " (done)" : "") << std::endl;
    };

    auto onComplete = [&finalResult, &completed](const std::string& result) {
        finalResult = result;
        completed = true;
    };

    auto onError = [&completed](const std::string& error) {
        std::cerr << "Error: " << error << std::endl;
        completed = true;
    };

    // The non-blocking function will be called in a separate thread in the timeout section below

    // Call the non-blocking function in a separate thread so we can timeout and interrupt it
    std::thread requestThread([&]() {
        generateNonBlocking(url, model, prompt, onProgress, onComplete, onError);
    });

    // Implement timeout mechanism - return after 0.2 seconds if no response
    auto startTime = std::chrono::steady_clock::now();
    while (!completed) {
        // Check if timeout period has elapsed (200ms)
        auto currentTime = std::chrono::steady_clock::now();
        auto elapsedTime = std::chrono::duration_cast<std::chrono::milliseconds>(currentTime - startTime).count();

        if (elapsedTime > 2000) {
            // Timeout reached, terminate the request thread
            std::cerr << "Request timed out after 100ms, terminating request" << std::endl;
            // Set completed to true to exit this loop
            completed = true;
            // Note: Ideally we would use a more graceful termination method,
            // but for a hard timeout we'll detach the thread and let it be cleaned up by the system
            requestThread.detach();
            finalResult="__BAD__";
            break;
        }

        // Small sleep to prevent CPU hogging
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
    }

    // If the request completed normally (not by timeout), wait for the thread to finish
    if (requestThread.joinable()) {
        requestThread.join();
    }

    return finalResult;
}

// Example usage
/*
int main() {
    std::string url = "http://localhost:11434/api/generate";
    std::string result = py_generate(url, "py3", "weishenme beijing xihuan chi shuanyangrou?");
    std::cout << "Final result: " << result << std::endl;
    return 0;
}
*/
