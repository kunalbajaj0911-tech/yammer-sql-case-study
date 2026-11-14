# Yammer Case Study in SQL: Why Did User Engagement Drop?

An investigation in PostgreSQL of a fall in weekly engaged users, based on Mode Analytics' three-part Yammer SQL case study. The focus is on method: write hypotheses first, audit the data, confirm the drop is real, then segment to find who and what changed.

> **Status: Part 1 in progress.** Data audit, drop validation, segmentation, email, activation, retention and day-of-week analysis are done. Still to come: the one-page write-up with a recommendation. Parts 2 and 3 are not started.

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
4. **Follow the user journey:** activation of new users, week-to-week retention, lapsed users, and how many engaged users clicked an email.
5. **Check timing:** daily and day-of-week patterns.

## Findings so far

| Step | Finding |
| --- | --- |
| Data audit | No orphan events, no events before user creation, user_id is unique. Nine duplicate event groups in about 310,000 events (under 0.01%), judged immaterial. |
| Is the drop real? | Yes. It shows up in the rolling 7-day metric, the calendar-week metric and daily users. Daily unique users stayed lower than July all through August (peaking near 400), with the decline beginning around 4 August. |
| Size of the drop | Weekly engaged users fell from about 1,377 (average of the 4 weeks to 28 July) to about 1,220 (4 weeks from 4 August): about 11% lower, and it did not recover through August. |
| Device | The drop is concentrated on mobile: phone -24% and tablet -31%, while computer barely moved (-3%, about normal weekly noise). Some users use several devices, so the segments overlap. |
| Phone models | The big phone models all fall by roughly 18% to 35%, across iOS, Android and Windows Phone, so the mobile drop is not isolated to one platform. |
| Tenure | The whole drop is among older users (more than 28 days since signup): about -20%, while new users are flat (+1%). This points to a retention problem, not an acquisition problem. |
| Signup flow | Only engagement events fell; signup events did not. |
| Event type, country, language, company | All engagement events fall, so it is not one broken feature. All six top countries fall by similar percentages, almost every language falls, and the 10 largest companies account for only about 14% of the loss. No single country, language or large company explains it. |
| Email | Digest sends and opens stay broadly stable while email clickthrough declines around the same time engagement falls. The share of engaged users who clicked an email also falls around the week of 4 August. This is an association, not shown to be a cause. |
| Activation and retention | Weekly activation stays stable, which does not point to an acquisition problem. Week-to-week retention weakens (about 58% to 55%) and lapsed users rise; this accounts for about half of the drop. The other half is fewer users arriving who were not engaged the week before. |
| Day of week | The decline shows on most weekdays, not one recurring day. |
| A failed attempt | My first email-to-engagement join multiplied rows because both tables have many rows per user. It is kept in `04_...sql` with an explanation of the grain mismatch and how I rebuilt it. |

These are descriptive findings about *where* the drop is. They do not yet establish *why*, and the cause is not claimed here.

## Repository structure

```
part1_engagement_drop/
  01_data_audit.sql          audit checks and the device-type view (run first)
  02_was_the_drop_real.sql   rebuild and validate the chart
  03_segmentation.sql        who and what dropped
  04_funnels_retention_timing.sql   email vs engagement, activation, retention, day of week
  05_size_and_contribution.sql      size of the drop, language and company cuts, segment contributions
```

Each query has a comment giving the question it answers, what result would matter, and what was found.

## How to run

1. Load the four Mode tables into PostgreSQL as `users`, `events`, `emails`, `experiments` (the queries have no schema prefix).
2. Run the files in numeric order. `01_data_audit.sql` creates the view `events_with_device_type`, which `03_segmentation.sql` uses.

## Next steps

- [ ] Finish Part 1: ranked conclusion and one-page memo (what the data cannot tell me, recommendation, how we would know it worked)
- [ ] Part 2: understanding search (adoption, sessions, quality, recommendation)
- [ ] Part 3: validating the A/B test (assignment checks, replication, decision)

## Source

Mode Analytics SQL tutorial: *A Drop in Engagement*, *Understanding Search*, *The Best A/B Test Ever*. All analysis and queries here are my own work on that dataset.
