# Yammer Case Study in SQL: Why Did User Engagement Drop?

An investigation in PostgreSQL of a fall in weekly engaged users, based on Mode Analytics' three-part Yammer SQL case study. The focus is on method: write hypotheses first, audit the data, confirm the drop is real, then segment to find who and what changed.

> **Status: Part 1 in progress.** Data audit, drop validation and segmentation are done. The email analysis result, a ranked conclusion and a one-page write-up are still to come. Parts 2 and 3 are not started.

## The question

Engagement on the weekly dashboard dips sharply at the end of the period (late summer 2014). What happened, why, and what should the company do?

## Data

Four tables from Mode's public Yammer tutorial dataset (fictional data modelled on a real product). The data is not stored in this repo; it is available from Mode's tutorial.

| Table | One row is | Main columns |
| --- | --- | --- |
| `users` | one user | user_id, created_at, state, activated_at, company_id, language |
| `events` | one user action | user_id, occurred_at, event_type, event_name, location, device |
| `emails` | one email event | user_id, occurred_at, action |
| `experiments` | one user per experiment | used in Part 3 |

**Definition used:** an *engaged user* has at least one event with `event_type = 'engagement'`, counted with `COUNT(DISTINCT user_id)`.

## Approach

1. **Audit the data** before analysing it: row counts, date ranges, NULLs, key uniqueness, orphan events, impossible timestamps, duplicates.
2. **Check the drop is real** by rebuilding the chart (rolling 7-day users) and recomputing it as calendar weeks and daily users, and checking the last week is complete.
3. **Segment** the weekly count by event, device, country, user tenure, signup flow and email activity, one hypothesis per cut.

## Findings so far

| Step | Finding |
| --- | --- |
| Data audit | No orphan events, no events before user creation, user_id is unique. Nine duplicate event groups in about 310,000 events (under 0.01%), judged immaterial. |
| Is the drop real? | Yes. It shows up in the rolling 7-day metric, the calendar-week metric and daily users. Daily unique users stayed lower than July all through August (peaking near 400), with the decline beginning around 4 August. |
| Device | Engagement fell relatively more on phone and tablet than on computer. Some users use several devices, so the segments overlap. |
| Tenure | Older users did not return while newer users recovered, which points to a retention problem more than an acquisition problem. |
| Signup flow | Only engagement events fell; signup events did not. |
| Event type, country, email | Queries are written; results not yet summarised. |

These are descriptive findings about *where* the drop is. They do not yet establish *why*, and the cause is not claimed here.

## Repository structure

```
part1_engagement_drop/
  01_data_audit.sql          audit checks and the device-type view (run first)
  02_was_the_drop_real.sql   rebuild and validate the chart
  03_segmentation.sql        who and what dropped
```

Each query has a comment giving the question it answers, what result would matter, and what was found.

## How to run

1. Load the four Mode tables into PostgreSQL as `users`, `events`, `emails`, `experiments` (the queries have no schema prefix).
2. Run the files in numeric order. `01_data_audit.sql` creates the view `events_with_device_type`, which `03_segmentation.sql` uses.

## Next steps

- [ ] Finish Part 1: email result, share of the change by segment, ranked conclusion, one-page memo
- [ ] Part 2: understanding search (adoption, sessions, quality, recommendation)
- [ ] Part 3: validating the A/B test (assignment checks, replication, decision)

## Source

Mode Analytics SQL tutorial: *A Drop in Engagement*, *Understanding Search*, *The Best A/B Test Ever*. All analysis and queries here are my own work on that dataset.
