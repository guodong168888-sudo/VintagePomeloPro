#include "dxvk_winehua_mapped_range.h"

#include <cstdint>
#include <iostream>
#include <limits>

namespace {

int failures = 0;
int checks = 0;

void Expect(bool condition, const char* label)
{
    ++checks;
    if (!condition) {
        ++failures;
        std::cerr << "FAIL: " << label << '\n';
    }
}

void ExpectMerge(uint64_t baseOffset, uint64_t baseSize,
                 uint64_t nextOffset, uint64_t nextSize,
                 uint64_t expectedOffset, uint64_t expectedSize,
                 const char* label)
{
    const bool merged = dxvk::winehuaMergeMappedRange(
        baseOffset, baseSize, nextOffset, nextSize);
    Expect(merged, label);
    Expect(baseOffset == expectedOffset, label);
    Expect(baseSize == expectedSize, label);
}

void ExpectSeparate(uint64_t baseOffset, uint64_t baseSize,
                    uint64_t nextOffset, uint64_t nextSize,
                    const char* label)
{
    const uint64_t originalOffset = baseOffset;
    const uint64_t originalSize = baseSize;
    const bool merged = dxvk::winehuaMergeMappedRange(
        baseOffset, baseSize, nextOffset, nextSize);
    Expect(!merged, label);
    Expect(baseOffset == originalOffset, label);
    Expect(baseSize == originalSize, label);
}

}

int main()
{
    constexpr uint64_t whole = std::numeric_limits<uint64_t>::max();

    ExpectMerge(100, 50, 150, 25, 100, 75, "adjacent forward");
    ExpectMerge(100, 100, 50, 75, 50, 150, "overlap reverse");
    ExpectMerge(100, 50, 120, 10, 100, 50, "contained");
    ExpectSeparate(100, 10, 111, 10, "one-byte gap");
    ExpectSeparate(100, whole, 50, 20, "whole range before gap");
    ExpectMerge(100, whole, 50, 60, 50, whole, "whole range overlap");
    ExpectMerge(whole - 8, 16, whole - 12, 8,
                whole - 12, whole, "overflow saturates");
    ExpectSeparate(0, 0, 0, 1, "empty base rejected");
    ExpectSeparate(0, 1, 1, 0, "empty next rejected");

    std::cout << "dxvk_mapped_range_test: " << checks << " checks, "
              << failures << " failures\n";
    return failures ? 1 : 0;
}
