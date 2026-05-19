# API Design Principles

## Core Contracts

* **Versioning**: Semantic (`major.minor.patch`), ABI-stable within major
* **Thread Safety**: Explicit `@thread_safe` annotations in docs
* **Error Codes**: Enum + human-readable message + stack trace (optional)
* **Async/Sync**: `async` APIs return `Future<Status>`, sync block with timeout

## Example API

    auto engine = AIEngine::create("npu");
    auto model = engine->load("cadex_v3.onnx");
    auto result = model->infer(frame, 30ms);
    if (!result.ok()) log::warn("AI fallback triggered");

## Binding Generation

* SWIG for Python
* FlatBuffers for cross-process IPC
* gRPC for network services 
