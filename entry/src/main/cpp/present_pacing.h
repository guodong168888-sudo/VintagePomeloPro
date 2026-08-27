#pragma once

#include <algorithm>
#include <cstdint>
#include <limits>

namespace winehua {

inline constexpr uint64_t kDirectPresentWarmupFrames = 24;
inline constexpr uint64_t kDirectFirstAcquireTimeoutNs = 100000000;
inline constexpr uint64_t kDirectQueueAcquireTimeoutNs = 0;
inline constexpr uint64_t kDefaultPresentFramePeriodNs = 16666667;
inline constexpr uint64_t kMinPresentFramePeriodNs = 4000000;
inline constexpr uint64_t kMaxPresentFramePeriodNs = 33333333;
inline constexpr uint64_t kPresentDispatchLeadNs = 500000;

inline uint64_t NormalizePresentFramePeriodNs(uint64_t framePeriodNs)
{
    if (!framePeriodNs) return kDefaultPresentFramePeriodNs;
    return std::clamp(framePeriodNs, kMinPresentFramePeriodNs,
                      kMaxPresentFramePeriodNs);
}

inline uint64_t PresentPacingPeriodNs(uint64_t displayPeriodNs)
{
    return displayPeriodNs >
            kMinPresentFramePeriodNs + kPresentDispatchLeadNs
        ? displayPeriodNs - kPresentDispatchLeadNs
        : kMinPresentFramePeriodNs;
}

struct PresentPacingDecision {
    bool presentNow = true;
    uint64_t nextDeadlineNs = 0;
};

inline uint64_t SaturatingDeadlineNs(uint64_t baseNs, uint64_t periodNs)
{
    if (periodNs > std::numeric_limits<uint64_t>::max() - baseNs)
        return std::numeric_limits<uint64_t>::max();
    return baseNs + periodNs;
}

inline PresentPacingDecision EvaluatePresentPacing(uint64_t nowNs,
                                                   uint64_t lastPresentNs,
                                                   uint64_t periodNs)
{
    if (!lastPresentNs || !periodNs) return {};
    const uint64_t deadlineNs = SaturatingDeadlineNs(lastPresentNs, periodNs);
    if (nowNs >= deadlineNs) return {};
    return {false, deadlineNs};
}

inline uint64_t NextPresentDeadlineNs(uint64_t presentNs, uint64_t periodNs)
{
    return periodNs ? SaturatingDeadlineNs(presentNs, periodNs) : 0;
}

// Queue-full/fence-timeout is a successful deferred present. Always return a
// future deadline so the guest cannot spin uncapped after no pixels were
// published, matching the Direct NativeWindow reference branch contract.
inline uint64_t RetryPresentDeadlineNs(uint64_t nowNs,
                                      uint64_t lastPresentNs,
                                      uint64_t periodNs)
{
    if (!periodNs) return 0;
    const uint64_t lastDeadline = lastPresentNs
        ? SaturatingDeadlineNs(lastPresentNs, periodNs) : 0;
    if (lastDeadline > nowNs) return lastDeadline;
    return SaturatingDeadlineNs(nowNs, periodNs);
}

inline bool DirectPresentUsesGuestDeadline(uint64_t framesPresented)
{
    return framesPresented >= kDirectPresentWarmupFrames;
}

inline uint64_t DirectPresentAcquireTimeoutNs(uint64_t framesPresented)
{
    return DirectPresentUsesGuestDeadline(framesPresented)
        ? kDirectQueueAcquireTimeoutNs : kDirectFirstAcquireTimeoutNs;
}

} // namespace winehua
