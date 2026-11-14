/* =============================================================================
   FILE     : 04_funnels_retention_timing.sql
   PROJECT  : Yammer case study, Part 1: A Drop in Engagement
   PURPOSE  : 03 showed WHERE engagement fell (all events, several countries, more on
              phone/tablet, older users, email clicks). This file tests WHY it might be
              happening by looking at the user journey: email -> engagement, activation,
              week-to-week retention, and the day-of-week pattern.
   DIALECT  : PostgreSQL
   WINDOW   : weeks starting 2014-04-28 up to (not including) 2014-09-01

   Sections
     D0 Email action inventory
     D1 Email -> engagement, attempt 1 (WRONG: grain mismatch, kept as a lesson)
     D2 Email -> engagement, attempt 2 (UNRESOLVED, kept as a record)
     D3 Activation of new users (is acquisition healthy?)
     D4 Weekly retention (self-join)
     D5 Lapsed users (two versions: lapsed only, then retention + lapsed together)
     D6 Share of engaged users who clicked an email (replaces D1 and D2)
     D7 Day-of-week pattern (daily users, then pivoted)

   Rule I learned in this file: decide the OUTPUT GRAIN of a query before writing it,
   and aggregate each table to a common grain BEFORE joining.

   ============================================================================= */


/* -----------------------------------------------------------------------------
   D0. Email actions present
   ----------------------------------------------------------------------------- */

select distinct action from emails;


/* -----------------------------------------------------------------------------
   D1. Do email clicks lead to engagement? ATTEMPT 1: WRONG, DO NOT RELY ON IT
   Intended output grain : 1 row = 1 week
   Problem               : events (1 row = 1 user event) was joined to emails
                           (1 row = 1 user email action) on user_id alone.
   ----------------------------------------------------------------------------- */

-- checking how much of email clickthrough affects user engagement

select date_trunc('week',events.occurred_at):: date as week,
count(distinct events.user_id) as total_users_that_week,
count(distinct case when emails.action='sent_weekly_digest' then emails.user_id end) as total_weekly_digest_that_week,
count(distinct case when emails.action='email_open' then emails.user_id end) as total_email_open_that_week,
count(distinct case when emails.action='sent_reengagement_email' then emails.user_id end) as total_reengagement_email_that_week,
count(distinct case when emails.action='email_clickthrough' then emails.user_id end) as total_email_clickthrough_that_week,
count(distinct case when emails.action='email_clickthrough' and events.event_type='engagement' then emails.user_id end ) as total_clciked_email_engaged,
count(distinct case when emails.action='email_clickthrough' and events.event_type='signup_flow' then emails.user_id end ) as total_clciked_email_signup_flow,
count(distinct case when emails.action='email_clickthrough' and events.event_type='engagement' and events.occurred_at>emails.occurred_at then emails.user_id end) as
engaged_post_email,
count(distinct case when emails.action='email_clickthrough' and events.event_type='engagement' and events.occurred_at<emails.occurred_at then emails.user_id end) as
engaged_pre_email
from events
join emails
on emails.user_id=events.user_id
where events.occurred_at >='2014-04-28' and events.occurred_at<'2014-09-01'
group by 1
order by 1;

/*
   Why D1 is wrong (grain mismatch)
   The query looks fine but it is wrong.

   Grain of events table : 1 row = 1 user event
   Grain of emails table : 1 row = 1 user email action

   Both tables have many rows per user, so joining on user_id alone is many-to-many:
   every event of a user is matched to every email of the same user.
   Example: user A has 5 engagement events and 3 email actions -> 15 rows for that user.

   So a condition like events.occurred_at > emails.occurred_at does not mean "this click
   led to this event". It only tests whether ANY event happened after ANY email for the
   same user (an event on 1 Aug can be paired with an email click on 10 Aug).
   COUNT(DISTINCT user_id) stops the same user being counted twice, but the before/after
   timing logic is still unreliable.

   Better approach: first aggregate both tables to a common grain (for example user-week),
   or explicitly pair each email action with the relevant events, and only then join.

   Lesson: write down the expected output grain and each table's grain BEFORE the query.
     Expected output grain : 1 row = 1 week
     Events table grain    : 1 row = 1 event
     Emails table grain    : 1 row = 1 email action
     Plan                  : aggregate both to user-week before joining
*/


/* -----------------------------------------------------------------------------
   D2. ATTEMPT 2: both tables reduced to user-week keys via CTEs. UNRESOLVED.
   It still joins event rows to email rows (now on user_id AND week), so the counts
   are still not clean. I stopped here and rebuilt the question in small steps (D3 to D6).
   ----------------------------------------------------------------------------- */

WITH engagement_events AS (
    SELECT
        user_id,
        occurred_at,
        DATE_TRUNC('week', occurred_at)::date AS week,
        event_type
    FROM events
    WHERE occurred_at >= '2014-04-28'
      AND occurred_at < '2014-09-01'
),
email_events AS (
    SELECT
        user_id,
        occurred_at,
        DATE_TRUNC('week', occurred_at)::date AS week,
        action
    FROM emails
    WHERE occurred_at >= '2014-04-28'
      AND occurred_at < '2014-09-01'
)
SELECT
    e.week,
COUNT(DISTINCT e.user_id) AS total_users_that_week,
COUNT(DISTINCT CASE
        WHEN em.action = 'sent_weekly_digest'
        THEN em.user_id
    END) AS total_weekly_digest_that_week,
COUNT(DISTINCT CASE
        WHEN em.action = 'email_open'
        THEN em.user_id
    END) AS total_email_open_that_week,
COUNT(DISTINCT CASE
        WHEN em.action = 'sent_reengagement_email'
        THEN em.user_id
    END) AS total_reengagement_email_that_week,
COUNT(DISTINCT CASE
        WHEN em.action = 'email_clickthrough'
        THEN em.user_id
    END) AS total_email_clickthrough_that_week,
COUNT(DISTINCT CASE
        WHEN em.action = 'email_clickthrough'
         AND e.event_type = 'engagement'
        THEN e.user_id
    END) AS total_clicked_email_engaged,
COUNT(DISTINCT CASE
        WHEN em.action = 'email_clickthrough'
         AND e.event_type = 'signup_flow'
        THEN e.user_id
    END) AS total_clicked_email_signup_flow,
COUNT(DISTINCT CASE
        WHEN em.action = 'email_clickthrough'
         AND e.event_type = 'engagement'
         AND e.occurred_at > em.occurred_at
        THEN e.user_id
    END) AS engaged_post_email,
COUNT(DISTINCT CASE
        WHEN em.action = 'email_clickthrough'
         AND e.event_type = 'engagement'
         AND e.occurred_at < em.occurred_at
        THEN e.user_id
    END) AS engaged_pre_email
FROM engagement_events e
LEFT JOIN email_events em
    ON e.user_id = em.user_id
   AND e.week = em.week
GROUP BY e.week
ORDER BY e.week;
-- Result: the results are still not appropriate, something is inflating the counts.
-- Decision: do not use this query. Come back to it only if D6 shows an interesting pattern;
-- timestamp-level (before/after click) analysis is complicated and only worth it then.

-- Summary of the email -> engagement attempts (D1 and D2)
-- Goal    : determine whether email clickthroughs lead to engagement.
-- Finding : the event-level join produced a grain mismatch (many-to-many on user_id), which
--           inflates the number of comparisons.
-- Conclusion: results from D1 and D2 are unsuitable for causal interpretation and should not
--           be relied upon.


/* -----------------------------------------------------------------------------
   D3. Activation of new users, by signup week
   Hypothesis : if fewer new users activated, acquisition (not retention) is the problem
   Grain      : one row per signup week; users table only, so no join and no fan-out
   Rate       : activation_rate = users with an activation date / users created
   ----------------------------------------------------------------------------- */

--checking new users and activation rate
select date_trunc('week', created_at)::date as week,
count(*) as total_new_users,
count(activated_at) as total_activated_users,
round(100.0*count(activated_at)/count(*),2) as activation_rate
from users
where created_at >= '2014-04-28' and created_at < '2014-09-01'
group by 1
order by 1;
-- Result: weekly activation rates stay relatively stable, moreover they have increased relatively despite the
-- decline in engagement. New users keep activating, which is more evidence that acquisition
-- is not the main problem.


/* -----------------------------------------------------------------------------
   D4. Weekly retention: of users engaged in week X, how many engaged again in week X+1?
   Grain      : the CTE has one row per user per week (SELECT DISTINCT). Joining
                the CTE to itself therefore cannot multiply rows.
   Method     : self-join with b.week_start = a.week_start + 7 (the next week).
   Why LEFT JOIN : an INNER JOIN would keep only users who returned, giving 100% retention.
   Why +7     : retention is attributed to the starting week X and asks whether users
                came back in week X+1. Using -7 would instead ask who was present last
                week, which answers a different question.
   Known issues (queries left unchanged):
     - 100*count(...)/count(*) is integer division, so the rate is truncated to a whole
       number before round(). Use 100.0 to keep decimals.
     - The last week has no next-week data (data ends 31 Aug), so its rate shows 0.
       Ignore that row when reading the trend.
   ----------------------------------------------------------------------------- */

-- checking in the engaged users on how many were retaining next week as well
with user_weeks as(
select distinct user_id,
date_trunc('week', occurred_at):: date as week_start
from events
where event_type='engagement'
)
select a.week_start,
count(*) as total_users_engaged,
count(b.user_id) as engaged_next_week,
round(100*count(b.user_id)/count(*),2) as retention_rate_for_week
from user_weeks as a
left join user_weeks as b
on b.user_id=a.user_id
and b.week_start=a.week_start+7
where a.week_start >= '2014-04-28' AND a.week_start < '2014-09-01'
GROUP BY a.week_start
ORDER BY a.week_start;

-- Notes
-- left join over inner join because using an inner join will produce 100% retention rate.
-- left join will make sure that the user will stay in the current week irrespective of him appearing in the next week or not such that the active user count doesnt go wrong
-- we used a self join here
-- use nullif when we use such ratio and divisions to avoid crashing
-- the last row will be null because there are no new users or more accurately no data beyond 31 august so the retention rate will be 0 post that. because there is no info about sep 1 to 7
-- Using +7 because retention is attributed to the starting week (week X) and checks whether users returned in week X+1.
-- even -7 days is a metric but that reveals the number of users that were present last week and now
-- what we wanted is the ones present rn how many of those returned next week


/* -----------------------------------------------------------------------------
   D5a. Lapsed users: active in week X but not in week X+1 (first version)
   Known issue: the nullif is misplaced (see the note after D5b), and this version is
   superseded by D5b. Kept to show the progression.
   ----------------------------------------------------------------------------- */

-- lapsed users
-- the users that are active on week x but not x+1
with user_weeks as (
select distinct user_id,
date_trunc('week', occurred_at):: date as week_start
from events
where event_type='engagement'
)
select a.week_start,
count(*) as total_users,
(count(*)-count(b.user_id)) as lasped_users,
round(nullif(100*(count(*)-count(b.user_id))/(count(*)),2)) as lasped_rate
from user_weeks a
left join user_weeks b
on a.user_id=b.user_id
and b.week_start=a.week_start+7
where a.week_start >= '2014-04-28' AND a.week_start < '2014-09-01'
group by 1
order by 1;

-- alternative for lasped could be
/*
sum(
    case
        when b.user_id is null then 1
        else 0
    end
) as lapsed_users
*/


/* -----------------------------------------------------------------------------
   D5b. Retention and lapsed users together (use this one)
   Columns: engaged_next_week = retained; lasped_users = not retained;
            retention_to_lasped = retained per lapsed user (a ratio, not a percentage)
   ----------------------------------------------------------------------------- */

-- a query for lasped, retention, rate of both

with user_weeks as (
select distinct user_id,
date_trunc('week', occurred_at):: date as week_start
from events
where event_type='engagement'
)
select a.week_start,
count(*) as total_users,
count(b.user_id) as engaged_next_week,
round(nullif(100*count(b.user_id)/count(*),0),2) as retention_rate_for_week,
(count(*)-count(b.user_id)) as lasped_users,
round(nullif(100*(count(*)-count(b.user_id))/(count(*)),0),2) as lasped_rate,
--round(nullif(100*(count(b.user_id)/count(*))/(nullif((count(*)-count(b.user_id))/(count(*)),0)),0),2) as retention_to_lapsed
round(100 * count(b.user_id)/nullif((count(*) - count(b.user_id)),0),2) as retention_to_lasped
from user_weeks a
left join user_weeks b
on a.user_id=b.user_id
and b.week_start=a.week_start+7
where a.week_start >= '2014-04-28' AND a.week_start < '2014-09-01'
group by 1
order by 1;

-- Lessons from this query
-- always look at both counts and percentage because percentages may remain stable but count may decline, so think of multiple angles
-- the ratio was over-complicated. 100 * count(b.user_id) / (count(*) - count(b.user_id)) does the same thing
-- nullif is used the wrong way in the first columns: it must be numerator / nullif(denominator, 0).
--   nullif exists to stop the DENOMINATOR from being 0, not the value itself.
--   (retention_to_lasped is the one column that uses it correctly.)

-- Results
-- D4: weekly retention falls gradually, from about 58% (avg of last 4 weeks before drop)to about 54%(avg of last 4 weeks after drop, the last week was filled using mode impuation) over the period.
-- D5: lapsed-user rates rise moderately as retention falls.
-- Interpretation: retention weakens and more users fail to return week to week. Whether that
--   is "too small to explain the drop" is NOT proven yet: a fall from 58% to 54% is less than 10%
--   lower in relative terms (54/58). Compare that with the percentage fall in weekly engaged
--   users before claiming it is minor.


/* -----------------------------------------------------------------------------
   D6. Share of engaged users who also clicked an email that week
   This replaces D1 and D2 with a safe grain.
   Grain      : both CTEs are one row per user per week (SELECT DISTINCT), so the
                LEFT JOIN on (user_id, week) cannot multiply rows.
   Metric     : percentage_click = clicked_users / engaged_users, per week
   Known issue (query unchanged): 100*count(...)/nullif(count(*),0) is integer division,
                so percentage_click is a whole number. Use 100.0 for decimals.
   Plan       : if I find an interesting pattern here, then try timestamp analysis;
                if not, skip it because it is too complicated.
   ----------------------------------------------------------------------------- */

-- coming back to the complicated engagement query
-- lets execute it in steps

with eng as(
select distinct user_id ,
date_trunc('week', occurred_at):: date as week_start
from events
where event_type='engagement'
),
clicked_as as(
select distinct user_id,
date_trunc('week',occurred_at):: date as week_sent
from emails
where action='email_clickthrough'
)
select e.week_start,
count(*) as engaged_users,
count(c.user_id) as clicked_users,
round(100*count(c.user_id)/nullif(count(*),0),2) as percentage_click
from eng as e
left join clicked_as c
on e.user_id=c.user_id
and e.week_start=c.week_sent
where e.week_start >= '2014-04-28' AND e.week_start < '2014-09-01'
group by  e.week_start
order by e.week_start;
-- Result: the share of engaged users who also clicked an email falls
-- sharply around the week of 4 August, from about 43% before to about 34% just after.
-- Interpretation: one of the strongest associations seen so far; engagement and email
-- clickthrough weaken at about the same time.
-- Caveat: association is not causation. This cannot show whether email clicks drove
-- engagement, or whether highly engaged users simply click emails more. A click is also
-- itself a form of engagement, so the two numbers are not independent.
--doing timestamp analysis is complicating, because the grain of the table is not being defined properly with respect ot the current schema of database. 


/* -----------------------------------------------------------------------------
   D7. Day-of-week pattern
   Hypothesis : if the drop is tied to one weekday (a scheduled job, a weekly workflow),
                it should show on that day only
   ----------------------------------------------------------------------------- */

-- D7a. Daily active users
-- daily pattern

select occurred_at:: date as day,
to_char(occurred_at :: date, 'Dy') as weekday,
count(distinct user_id) as DAU
from events
where event_type='engagement'
and occurred_at>='2014-04-28' and occurred_at <'2014-09-01'
group by 1,2
order by 1;

-- D7b. Same data pivoted: one row per week, one column per weekday
-- Note: this query starts at 2014-04-25 (a Friday, the others start 2014-04-28), so the
--       first row (week of 21 Apr) only has Fri to Sun. Ignore that row.
-- pivoting the daily trend

WITH daily_engagement AS (
    SELECT
        DATE_TRUNC('week', occurred_at)::date AS week_start,
        TO_CHAR(occurred_at, 'Dy') AS weekday,
        COUNT(DISTINCT user_id) AS engaged_users
    FROM events
    WHERE event_type = 'engagement'
      AND occurred_at >= '2014-04-25'
      AND occurred_at <  '2014-09-01'
    GROUP BY 1, 2
)
SELECT
    week_start,
	MAX(CASE WHEN weekday = 'Mon' THEN engaged_users END) AS mon,
    MAX(CASE WHEN weekday = 'Tue' THEN engaged_users END) AS tue,
    MAX(CASE WHEN weekday = 'Wed' THEN engaged_users END) AS wed,
    MAX(CASE WHEN weekday = 'Thu' THEN engaged_users END) AS thu,
    MAX(CASE WHEN weekday = 'Fri' THEN engaged_users END) AS fri,
    MAX(CASE WHEN weekday = 'Sat' THEN engaged_users END) AS sat,
    MAX(CASE WHEN weekday = 'Sun' THEN engaged_users END) AS sun
FROM daily_engagement
GROUP BY week_start
ORDER BY week_start;
-- Result: the decline shows on most weekdays rather than on one
-- recurring day, so it looks broad-based, not tied to one workflow or scheduled job.
-- Observation: Friday engagement looks relatively resilient compared with other
-- weekdays; worth asking the business why.


/* =============================================================================
   FINAL INVESTIGATION SUMMARY

   1. Weekly engagement begins declining around the week of 2014-08-04.
   2. The decline is broad across engagement event types, countries, languages and
      weekdays, but concentrated on phone and tablet (computer barely moved). About -11%
      overall, about 160 fewer engaged users a week (see 05).
   3. Signup activity and activation rates remain stable, so acquisition looks healthy.
   4. Retention weakens and lapsed users increase. Whether this explains the decline is not
      yet established (see the note after D5b).
   5. Email sends and opens remain stable, moreover increases while email clickthrough decreases materially.
   6. The share of engaged users who also click emails declines around the same time
      engagement falls.
   7. The most notable pattern associated with the decline is reduced email clickthrough.
      This is an association; it does not show what caused it.

   WHAT THE DATA CANNOT TELL ME
   - Whether anything changed in the product, the emails or the app around 4 August
     (release notes, email template or send-time changes). That needs Product/Engineering.
   - Whether email clicks cause engagement or just track it.

  continued in file 05_size_abd_contribution.sql
   ============================================================================= */
