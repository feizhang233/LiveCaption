#!/bin/bash
# Source-only helpers for the macOS App integration harnesses. Callers own
# argument validation, temporary-directory cleanup and test execution.

compile_app_test_harness() {
    local project_dir="$1"
    local check_dir="$2"
    local products_dir="$3"
    local test_source="$4"
    local output_file="$5"

    if [[ -z "$products_dir" ]]; then
        CLANG_MODULE_CACHE_PATH="$check_dir/cache" SWIFTPM_MODULECACHE_OVERRIDE="$check_dir/swift-cache" \
            swift build --package-path "$project_dir/Packages/CaptionCore" \
                --scratch-path "$check_dir/core" --product CaptionCore >&2
        products_dir="$check_dir/core/out/Products/Debug"
    fi

    local whisper_framework="$project_dir/Packages/CaptionCore/Frameworks/whisper.xcframework/macos-arm64_x86_64"
    local sources=(
        "$project_dir"/App/Models/*.swift
        "$project_dir"/App/Media/*.swift
        "$project_dir"/App/Session/*.swift
        "$project_dir"/App/UI/*.swift
        "$project_dir"/App/Platform/macOS/*.swift
    )
    xcrun swiftc -swift-version 5 -target arm64-apple-macos26.0 -module-cache-path "$check_dir/cache" \
        -I "$products_dir" -L "$products_dir" -lCaptionCore -F "$whisper_framework" -framework whisper \
        -Xlinker -rpath -Xlinker "$whisper_framework" \
        "${sources[@]}" "$test_source" -o "$output_file"
}
