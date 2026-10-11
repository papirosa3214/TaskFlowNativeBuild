# Durable review activity

Heatmap reads /api/stats/review-history in one request instead of existing task detail histories. First review facts remain after deletion and are grouped by local calendar date. No history entry is filtered by current task existence. Event/reconnect refresh retained; active task counters and TaskStore are unchanged. No new UI tests per owner; device build and phone review.
