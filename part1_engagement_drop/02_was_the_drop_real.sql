/* =============================================================================
   FILE     : 02_was_the_drop_real.sql
   PROJECT  : Yammer case study, Part 1: A Drop in Engagement
   PURPOSE  : Before asking WHY engagement fell, check that the drop is real and
              not an artefact of how the chart was built.
   DIALECT  : PostgreSQL
   DEFINITION: "Engaged user" = a user with at least one event where
               event_type = 'engagement'. Counted with COUNT(DISTINCT user_id)
               so a heavy user counts once.

   Hypothesis tested here (measurement category):
     H0. The drop is a measurement problem (rolling-window effect, partial last
         week, or a definition issue), not a real change in behaviour.
   If H0 were true I would expect the drop to vanish when I recompute the metric
   a second way, or the last data point to be an incomplete period.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   B1. Rebuild the dashboard chart: rolling 7-day unique engaged users
   Grain    : one row per calendar day (a generated date spine)
   Method   : each day counts distinct users with an engagement event in the 7 days
              ending on that day. generate_series builds the calendar so that
              days with zero activity would not vanish. LEFT JOIN keeps every day.
   Look for : a sharp dip at the end of the series
   ----------------------------------------------------------------------------- */

--generating a rolling table for unique users per rolling week
with days as (
select generate_series(timestamp '2014-05-01', timestamp '2014-08-31', interval '1day'):: date as day
)
select d.day,
count(distinct user_id) as rolling_7d_unique_users
from days d
left join events e
on e.event_type='engagement'
and e.occurred_at>=d.day-6
and e.occurred_at<d.day+1
group by d.day
order by d.day;


/* -----------------------------------------------------------------------------
   B2. Same metric computed a different way: calendar weeks
   Grain    : one row per calendar week (weeks start on Monday in PostgreSQL)
   Purpose  : if the drop is real it should show up in a differently built metric too
   ----------------------------------------------------------------------------- */

--aggregating individual weekly counts according to calender week
SELECT
  DATE_TRUNC('week', occurred_at) AS week_start,
  COUNT(DISTINCT user_id)
FROM events
WHERE event_type='engagement'
GROUP BY 1
ORDER BY 1;


/* -----------------------------------------------------------------------------
   B3. Users, total events and events per user, by calendar week
   Purpose  : separate "fewer people" from "less activity per person"
   Look for : users falling while events per user stays flat means people left;
              both falling means the people who stayed also did less
   ----------------------------------------------------------------------------- */

--users, events, events per user for a calender week
select date_trunc('week', occurred_at)::date as start_of_week,
count(distinct user_id) as unique_users_that_week,
count(*) as total_events_that_week,
round(1.0* count(*)/count(distinct user_id),2) as events_per_user
from events e
where e.event_type='engagement'
group by 1
order by 1;


/* -----------------------------------------------------------------------------
   B4. Is the last week complete?
   Why      : a dashboard can show a partial last week. The week may end on 2 Sep,
              but the data might only run to 31 Aug, which would fake a dip.
   Look for : the latest timestamp vs the end of the last week in B2
   ----------------------------------------------------------------------------- */

-- checking if the last week is complete or not because the dashboard may report partital week data which was submiited to it
-- the week may end on 2 sep but what if in our dashboard data is only till 31 aug so check it first

SELECT MAX(occurred_at)
FROM events;


/* -----------------------------------------------------------------------------
   B5. Pin down the date the decline starts (daily unique users)
   Why      : weekly charts blur the start date; daily data shows it
   ----------------------------------------------------------------------------- */

-- it is observed that decline is somewhere around first week of august, lets plot that particular range and check the exact date

select occurred_at:: date,count(distinct user_id) as total_users_that_day
from events
where occurred_at> '2014-06-30'
group by occurred_at::date
order by occurred_at:: date;


/* =============================================================================
   CONCLUSION OF THIS FILE
   - Daily unique users were relatively lower than in July for all of August; the
     maximum daily level in August stayed around 400.
   - The decline appears to begin around August 4 (approximate, based on daily data).
   - The drop shows up in the rolling metric, the calendar-week metric and the daily
     view, so it is not an artefact of one definition. The dashboard chart is correct.
   - Next question: who and what dropped? See 03_segmentation.sql.

   Original working notes:
   -- i dont know what happened in september but the unique users per day relatively decresed when compared to july for entire august our maximum upper limit was 400
   -- the decline could begin around august 4 as the approximate interval we are reporting
   -- we have now confirmed that the drop is real and the chart they gave us is correct now lets find out who and what dropped
   ============================================================================= */
