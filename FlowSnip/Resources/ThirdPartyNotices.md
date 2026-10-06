# FlowSnip 2.0 Third-Party Notices

FlowSnip uses the following open-source projects. Their complete license files are included in the `Licenses` directory beside this document in the distributed application. Package versions and revisions are recorded in the project's Swift package lockfile.

| Project | Version | License | Source |
| --- | --- | --- | --- |
| MLX Swift | 0.32.3 | MIT | https://github.com/ml-explore/mlx-swift |
| MLX Swift LM | 3.32.3 | MIT | https://github.com/ml-explore/mlx-swift-lm |
| Swift Hugging Face | 0.13.0 | Apache-2.0 | https://github.com/huggingface/swift-huggingface |
| Swift Transformers | 1.3.4 | Apache-2.0 | https://github.com/huggingface/swift-transformers |
| Swift Jinja | 2.5.1 | Apache-2.0 | https://github.com/huggingface/swift-jinja |
| EventSource | 1.5.1 | MIT | https://github.com/mattt/EventSource |
| Swift Collections | 1.7.1 | Apache-2.0 with Swift exception | https://github.com/apple/swift-collections |
| Swift Crypto | 4.5.2 | Apache-2.0 with Swift exception and bundled third-party notices | https://github.com/apple/swift-crypto |
| Swift ASN.1 | 1.7.3 | Apache-2.0 with Swift exception | https://github.com/apple/swift-asn1 |
| Swift Numerics | 1.1.1 | Apache-2.0 with Swift exception | https://github.com/apple/swift-numerics |
| yyjson | 0.12.0 | MIT | https://github.com/ibireme/yyjson |

Swift Syntax is a package dependency for optional upstream features but is not linked into FlowSnip's application runtime. FlowSnip does not use third-party build macros or disable Xcode macro validation.

## Local Models

Qwen3.5 and Qwen3.8 model weights are not bundled with this application. A user-confirmed download fetches a pinned vision-model conversion from Hugging Face into FlowSnip's Application Support directory. The Qwen models are distributed under Apache-2.0; applicable license files are retained with the model snapshot.

## Cloud Services

OpenRouter and the chosen model provider are external services, not bundled models. They receive only explicitly selected cloud-scan crops and bounded conversation context after cloud processing is enabled. Their pricing and data policies apply.