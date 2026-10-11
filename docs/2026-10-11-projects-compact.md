# Compact projects

Search moved into ellipsis menu and native form. Four status counters in one flat row; no-project and archive in the second flat row. Empty projects retain progress track. Existing running/review/blocked symbols reused; stale shown by red triangle with cross. Double check represents critic approval and is not used for review.

Project totals preserve server task_count/completed_count. Running requires active/in_progress and not stale; stale separately counted. Other active tasks are shown as unstarted (clock). Removed client-side reclassification of completed tasks based on open checklists.

Live database identified through file descriptors of taskflow-server process. NewTodoist: completed64, active4 (pending2, review1, blocked1). Server notifications: completed4, pending4. XCUITest screenshot agrees with these totals. Separate CLI LAN auth returned404; verification used live database plus authenticated application UI.

Two tests passed: state classification and UI row geometry/search menu. Screenshot and UI test saved alongside.
