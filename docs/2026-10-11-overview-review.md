# Overview review activity

Heatmap uses first task_events agent_state transition to review per task, including archived and child tasks. Counts one submitted task once, in local calendar day. completed_at is no longer used. Existing task detail API supplies immutable events; at most four requests concurrently, per-task revision cache avoids reloading unchanged histories. Initial/connection/task event recovery retained, no timer. Errors expose retry.

Live database contains33 first submissions on Oct5-10 (UTC dates); no review records before October. This change does not fabricate historical dates.

Weekly summary moved into shared navigation card using same TFListRow. Search button removed; all navigation chevrons removed. No new tests per owner request; device build and phone review.
