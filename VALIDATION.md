# FlowSnip 2.0 Validation Record

Date: 2026-10-06

## Verified

- Xcode 27.0 (27A266a), macOS SDK 27.0, and Apple's Metal compiler.
- Debug builds and the signed optimized Release app for arm64/macOS 27.
- 40 automated tests passed with no failures. One opt-in live-screen test skipped because the test process lacks Screen Recording permission.
- Native hosted light/dark assistant and local/cloud settings previews. Actual AppKit controls, scroll content, model picker, and source preview render without the unsupported ImageRenderer placeholders.
- Synthetic OCR, streamed assistant response, follow-up, retry without duplicated turns, stop followed by a new question, and private clipboard text/image copying.
- Real pinned Qwen3.5-4B 4-bit vision inference on Apple M5 / 16 GB, using generated error-message, receipt, and chart images.
- Cached/offline inference, cancellation that releases the busy state, and a receipt-image follow-up retaining currency context.
- OpenRouter public catalog refresh, filtering to image-input/text-output models, and the proposed GPT-6 Luna / Gemini 3.8 Flash choices.
- URLSession fixture checks for split network chunks, SSE event boundaries, usage/completion, disconnects, authentication failures, size limits, and no automatic generation retry. No real API key or paid request was used.
- ZIP/DMG packaging, ad-hoc signing verification, version 2.0/build 2, macOS 27 minimum, arm64 architecture, dependency resource bundles, license collection, and DMG checksum verification.

## Local Measurements

The optimized distributed app was tested on the current M5/16 GB Mac. The first synthetic code request included model loading and took approximately 8 seconds to its first token and 9.4 seconds to finish. Warm receipt and chart requests took approximately 0.74-0.75 seconds to their first token and 1.1 seconds to finish. Peak MLX memory was approximately 3.8 GB.

These are three small synthetic crops, not a general speed claim. Larger crops, long questions, extended reasoning, other running apps, and different chips change the results.

Receipt total/currency and highest chart bar matched the basic fixture expectations. The code answer identified the initialization/default-array fix but used "not defined" rather than the exact "undefined" assertion token. That fixture is recorded as not matched; local-model interpretation is not guaranteed to be exact. Verbatim text extraction is separate Apple Vision OCR.

## Remaining External Checks

- Screen Recording is not granted to the validation app/process here, so actual desktop-region capture, normal screenshot shortcut/paste/toast, and the full physical shortcut -> live crop -> answer sequence still need a permission-enabled manual check after installation.
- The second user's M4 configuration and physical external-display arrangement are not available. Hardware recommendations and display-coordinate cases are tested, but that machine is not performance-certified.
- No user OpenRouter key was provided, so real paid generation, account credits, and provider-specific live latency were not tested. The transport and error handling are fixture-tested, and the public catalog is verified.
- The configured hosted GitHub workflow has not been executed remotely. Its YAML/shell steps and documented Xcode 27 runner image were checked locally.
- The app is ad-hoc signed, not Developer ID signed or notarized. Gatekeeper/quarantine and updated Screen Recording/Accessibility approvals may require user action on installation.

## Update Artifacts

- `build/FlowSnip.dmg`: verified drag-to-Applications installer.
- `build/FlowSnip.zip`: signed app ZIP alternative.
- `build/Release/FlowSnip.app`: signed version 2.0 application.

Quit the old running copy before replacing it in Applications. Separately stored model weights, preferences, and screenshot counts are not overwritten by replacing the application.