/* =============================================================================
   FILE     : 03_segmentation.sql
   PROJECT  : Yammer case study, Part 1: A Drop in Engagement
   PURPOSE  : The drop is real (see 02). Now find WHO and WHAT dropped by splitting
              the weekly engaged-user count into segments.
   DIALECT  : PostgreSQL
   REQUIRES : the view events_with_device_type, created in 01_data_audit.sql
   WINDOW   : weeks starting 2014-04-28 up to (not including) 2014-09-01

   Segment cuts, in order, with the hypothesis each one tests
     C1 Event type   : did one behaviour/feature fall (login, inbox, messages ...)?
     C2 Device       : is it a phone/tablet/app problem?
     C3 Country      : is it one region?
     C4 Tenure       : new users vs older users (acquisition vs retention)
     C5 Signup flow  : did people stop signing up?
     C6 Email        : did the email channel weaken?

   Method for every cut: count DISTINCT users per week per segment, then compare the
   segment's weeks before and after the drop (around 4 August).
   ============================================================================= */


/* -----------------------------------------------------------------------------
   C0. Inventory of event names
   ----------------------------------------------------------------------------- */

-- checking who dropped and what dropped
select distinct event_name, event_type from events;

select distinct event_name  from events where event_type='engagement' ;

select distinct event_name  from events where event_type='signup_flow';


/* -----------------------------------------------------------------------------
   C1. WHAT: weekly users by engagement event
   Hypothesis : if only one event fell (for example inbox views), the cause is a
                specific feature or flow rather than general disengagement
   Grain      : one row per week; each column is distinct users doing that event
   Note       : search events are grouped with LIKE 'search%'
   ----------------------------------------------------------------------------- */

--checking counts only for engagement events first by segmenting events
SELECT DATE_TRUNC('week', occurred_at)::date AS week_start,
COUNT(DISTINCT CASE WHEN event_name = 'login' THEN user_id END) AS login_users,
COUNT(DISTINCT CASE WHEN event_name = 'home_page' THEN user_id END) AS home_page_users,
COUNT(DISTINCT CASE WHEN event_name = 'view_inbox' THEN user_id END) AS inbox_users,
COUNT(DISTINCT CASE WHEN event_name = 'send_message' THEN user_id END) AS send_message_users,
COUNT(DISTINCT CASE WHEN event_name = 'like_message' THEN user_id END) AS like_users,
COUNT(DISTINCT CASE WHEN event_name LIKE 'search%' THEN user_id END) AS search_users
FROM events
WHERE event_type = 'engagement'
AND occurred_at >= '2014-04-28' AND occurred_at < '2014-09-01'
GROUP BY 1
ORDER BY 1;


/* -----------------------------------------------------------------------------
   C2. WHO: device type (computer / phone / tablet)
   Hypothesis : if phone and tablet fell but computer did not, suspect a mobile
                app or mobile experience problem
   Uses       : view events_with_device_type from 01_data_audit.sql
   ----------------------------------------------------------------------------- */

--checking counts only for engagement events first by segmenting devices using the view created in auditing

SELECT
    DATE_TRUNC('week', occurred_at)::date AS week_start,
	COUNT(DISTINCT user_id) AS total_users,
	COUNT(DISTINCT CASE WHEN device_type='computer'
                        THEN user_id END) AS computer_users,
	COUNT(DISTINCT CASE WHEN device_type='phone'
                        THEN user_id END) AS phone_users,
	COUNT(DISTINCT CASE WHEN device_type='tablet'
                        THEN user_id END) AS tablet_users
FROM events_with_device_type
WHERE event_type='engagement'
GROUP BY 1
ORDER BY 1;
-- Result: engagement fell, but relatively it fell more across phone and tablet than computer users

-- C2b. Why the device columns do not add up to total_users
-- In the previous query, total_users is smaller than the sum of the three device
-- columns for some weeks. That can only happen if some users use more than one device.
-- Expected: rows returned (users with n_devices > 1)
SELECT
    user_id,
    COUNT(DISTINCT device_type) AS n_devices
FROM events_with_device_type
WHERE event_type='engagement'
GROUP BY user_id
HAVING COUNT(DISTINCT device_type) > 1;
-- Result: users also log in from multiple devices, so device segments overlap
-- (a user is counted once in each device column they used). Do not add them up.


/* -----------------------------------------------------------------------------
   C3. WHO: country (top 6 locations by users)
   Hypothesis : if one country fell and the others did not, suspect a regional
                cause (a launch, a holiday, a local outage)
   ----------------------------------------------------------------------------- */

-- C3a. Long format: weekly users for the six largest locations
--segmenting country wise
select date_trunc('week', occurred_at):: date as week_date,
location,
count(distinct user_id) as weekly_users from events
where event_type='engagement'
and occurred_at>='2014-04-28' and occurred_at<'2014-09-01'
and location in (
select location
from events
WHERE event_type='engagement'
group by location
order by count(distinct user_id) desc
limit 6
)
group by 1,2
order by 2,1;

-- C3b. Pivot: one column per location, easier to read and to chart
-- Note: the six names below were taken from the top-6 result of C3a and are written
--       in by hand. Columns location_1 ... location_6 map to the countries in order:
--       France, Germany, Italy, Japan, United Kingdom, United States.
-- convert to a pivot table

SELECT
    DATE_TRUNC('week', occurred_at)::date AS week_date,
	COUNT(DISTINCT CASE
        WHEN location = 'France'
        THEN user_id
    END) AS location_1,
	COUNT(DISTINCT CASE
        WHEN location = 'Germany'
        THEN user_id
    END) AS location_2,
	COUNT(DISTINCT CASE
        WHEN location = 'Italy'
        THEN user_id
    END) AS location_3,
	COUNT(DISTINCT CASE
        WHEN location = 'Japan'
        THEN user_id
    END) AS location_4,
	COUNT(DISTINCT CASE
        WHEN location = 'United Kingdom'
        THEN user_id
    END) AS location_5,
	COUNT(DISTINCT CASE
        WHEN location = 'United States'
        THEN user_id
    END) AS location_6
FROM events
WHERE event_type = 'engagement'
AND occurred_at >= '2014-04-28'
AND occurred_at < '2014-09-01'
GROUP BY 1
ORDER BY 1;


/* -----------------------------------------------------------------------------
   C4. WHO: tenure (new vs older users)
   Definition : an engagement event counts as "new" if it happened within 28 days of
                the user's created_at, otherwise "older".
                (The tenure label belongs to the event, so one user can appear in both
                columns in a week.)
   Hypothesis : if new users held up but older users fell, it is a RETENTION problem;
                if new users fell, it is an ACQUISITION problem
   Grain      : inner query gives one row per week and tenure; the outer query pivots
                it into columns
   ----------------------------------------------------------------------------- */

-- segment by tenure

select s.week,
max(case when s.tenure= 'new' then s.total_users end) as new,
max(case when s.tenure= 'older' then s.total_users end) as older
from (select date_trunc('week', occurred_at):: date as week ,
case when e.occurred_at<=u.created_at+ interval '28 days' then 'new' else 'older' end as tenure,
count(distinct e.user_id) as total_users
from events e
join  users u
on u.user_id=e.user_id
where e.event_type='engagement'
and e.occurred_at >= '2014-04-28' AND e.occurred_at < '2014-09-01'
group by 1,2)s
group by s.week;
-- Result: it is more of a retention problem than an acquisition problem
-- Newer users recovered but older ones were gone
-- Something happened around 4 August and the days around it; everything changed after that
-- Next check: run the same weekly analysis on signup_flow events to see whether new-user
--             events recovered too (C5)


/* -----------------------------------------------------------------------------
   C5. Signup flow by week
   Hypothesis : if signups had also fallen, this would be an acquisition problem
   ----------------------------------------------------------------------------- */

select date_trunc('week',occurred_at):: date as week,
count(distinct case when event_name='complete_signup' then user_id end) as total_signups_that_week,
count(distinct case when event_name='create_user' then user_id end) as total_users_new_that_week,
count(distinct case when event_name='enter_email'  then user_id end) as total_enter_emails_that_week,
count(distinct case when event_name='enter_info' then user_id end) as total_enter_info_that_week
from events
where event_type='signup_flow'
and occurred_at >='2014-04-28' and occurred_at<'2014-09-01'
group by 1
order by 1;
-- Result: confirmed, only engagement events fell; signup flow did not
-- Also, the week of 4 August stands out: engagement fell across the app that week


/* -----------------------------------------------------------------------------
   C6. Email channel
   Hypothesis : if digest or re-engagement emails were sent less, opened less or
                clicked less, the email channel explains the loss of older users
   Rates      : opening_rate = opens / digests sent; clickthrough_rate = clicks / opens.
                Each is counted in distinct users per week, with NULLIF to avoid
                division by zero, and 100.0 to avoid integer division.
   ----------------------------------------------------------------------------- */

select distinct action from emails limit 10;

-- checking email event counts

select date_trunc('week', occurred_at):: date as week,
count(distinct case when action='sent_weekly_digest' then user_id end) as total_weekly_digest,
count(distinct case when action='sent_reengagement_email' then user_id end) as total_reengagement_email,
count(distinct case when action='email_clickthrough' then user_id end) as total_email_clickthrough,
count(distinct case when action='email_open' then user_id end) as total_email_open,
round(100.0*count(distinct case when action='email_open'then user_id end )/nullif(count(distinct case when action='sent_weekly_digest' then user_id end),0),2) as opening_rate,
round(100.0*count(distinct case when action='email_clickthrough' then user_id end )/nullif(count(distinct case when action='email_open' then user_id end),0),2) as clickthrough_rate
from emails
where occurred_at<'2014-09-01' and occurred_at>='2014-04-28'
group by 1
order by 1;
-- Result: users are receiving emails, opening emails, but the clickthrough event isn't happening, i.e the users are not coming back to the platform.
-- users not coming back despite reading the email could show either user is not perceiving enough value from the emails, to return to the application or there is a recording issue in tracking email clickthrough  


/* =============================================================================
   SUMMARY SO FAR (update as the investigation continues)
   - The drop is real and starts around 4 August 2014 (see 02_was_the_drop_real.sql).
   - Device: engagement fell relatively more on phone and tablet than on computer.
   - Tenure: older users did not come back; newer users recovered. Retention, not
     acquisition.
   - Signup flow: did not fall, which supports the retention reading.
   - Still open: email result (C6), contribution of each segment to the total change,
     and a ranked conclusion with confidence.
   ============================================================================= */
