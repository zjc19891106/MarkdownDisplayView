# Completion Summary

## Task
Fix "Layout Loop" causing initial freeze and ensure correct rendering height in `MarkdownDisplayView`.

## Diagnosis
1. **Freeze:** Caused by `layoutSubviews` invalidating intrinsic content size, creating an infinite loop with TableView layout logic.
2. **Missing Content:** Caused by unreliable manual frame summation when layout passes hadn't completed.
3. **Stuck Text:** Caused by outdated height reporting during rapid streaming.

## Final Solution
1. **Broken Layout Loop:** Removed `invalidateIntrinsicContentSize()` from `MarkdownDisplayView.layoutSubviews`.
2. **Reliable Height Calculation:** Reverted `notifyHeightChange` to use `systemLayoutSizeFitting`, but added a preliminary `layoutIfNeeded()` to ensure subviews are ready.
3. **Optimized Updates:** `MarkdownTextViewTK2` now intelligently decides when to trigger expensive full-text recalculations (only when text changes or width changes), preventing loops while ensuring accuracy.

## Result
- **No Freeze:** The infinite loop is gone.
- **Correct Height:** Text bubbles expand correctly without clipping or empty space.
- **Smooth Streaming:** Updates are efficient and flicker-free.
