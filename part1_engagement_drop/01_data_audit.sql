/* =============================================================================
   FILE     : 01_data_audit.sql
   PROJECT  : Yammer case study, Part 1: A Drop in Engagement
   PURPOSE  : Find out what I can and cannot trust in the data BEFORE analysing it.
   DIALECT  : PostgreSQL
   TABLES   : users (one row per user), events (one row per user action),
              emails (one row per email event), experiments (one row per user per experiment)
   RUN ORDER: Run this file first. Section 6 creates the view
              events_with_device_type, which 03_segmentation.sql depends on.

   HOW TO READ THIS FILE
   Each query has a label (A1, A2, ...), then:
     Question : what I am checking
     Look for : what result would worry me
     Result   : what I found and what I decided
   ============================================================================= */


/* -----------------------------------------------------------------------------
   SECTION 1: SIZE AND TIME COVERAGE
   ----------------------------------------------------------------------------- */

-- A1. Row count of every table
-- Question : how big is each table, and are the proportions plausible?
-- Look for : an empty table, or far fewer events than users
select 'users' as table_name, count(*) as n_rows from users
union all
select 'emails', count(*) from emails
union all
select 'events' , count(*) from events
union all
select 'experiments', count(*) from experiments;

-- A2. Time range covered by each table
-- Question : where does each table start and end?
-- Look for : a table that stops before the period I need (the drop is in Aug 2014)
select min(created_at) as first_created, max(created_at) as last_created from users
union all
select min(occurred_at) , max(occurred_at) from emails
union all
select min(occurred_at) , max(occurred_at) from events
union all
select min(occurred_at) , max(occurred_at) from experiments;


/* -----------------------------------------------------------------------------
   SECTION 2: USERS TABLE QUALITY
   ----------------------------------------------------------------------------- */

-- A3. NULLs per column in the users table
-- Question : which columns have missing values?
-- Look for : NULL in user_id or created_at (should be none). A NULL in activated_at
--            can be legitimate (user never activated), so check it against state in A5.
select count(*) as total_users,
count(*)-count(user_id) as null_in_user_id,
count(*)-count(created_at) as null_in_created_at,
count(*)-count(company_id) as null_in_company_id,
count(*)-count(language) as null_in_language,
count(*)-count(activated_at) as null_in_activated_at,
count(*)-count(state) as null_in_state
from users;

-- A4. Is user_id really a primary key?
-- Question : does any user_id appear more than once?
-- Look for : any returned row. If there are rows, every join to users would duplicate data.
-- Result   : no rows returned, so user_id is unique and joins to users are safe.
select user_id,count(*) as occurence_count
from users
group by user_id
having count(*)>1;

-- A5. Does state agree with activated_at?
-- Question : how many users are active vs pending, and does activated_at match?
-- Look for : "pending" users with an activation date, or "active" users without one
select state, count(*) as users , count(activated_at) as users_activated
from users
group by state;


/* -----------------------------------------------------------------------------
   SECTION 3: INVENTORY OF CATEGORIES (what values exist?)
   Purpose: I need the exact event names, devices, locations and email actions
   before I can write segmentation queries.
   ----------------------------------------------------------------------------- */

-- A6. Event types and names, with event counts and distinct users
select event_type, event_name, count(*) as n_events, count(distinct user_id) as n_users
from events
group by event_type, event_name
order by event_type, n_events desc;

-- A7. Devices present in the events table
select device, count(*) as n_events
from events
group by device
order by n_events desc;

-- A8. Locations present in the events table
select location, count(*) as n_events
from events
group by location
order by n_events desc;

-- A9. Email actions present in the emails table
select action, count(*) as n_rows, count(distinct user_id) as n_users
from emails
group by action
order by n_rows desc;


/* -----------------------------------------------------------------------------
   SECTION 4: DEVICE GROUPING (a reusable view for later queries)
   Decision: the events table has about 26 raw device names. Segmenting by each one
   is too granular, so I grouped them by hand into computer / phone / tablet.
   Anything not listed falls into 'other', which makes a missing mapping visible.
   ----------------------------------------------------------------------------- */

-- A10. List the raw device names (used to build the mapping below)
select distinct device from events;

-- A11. View: every event row plus a device_type column
-- Note: 'samsumg galaxy tablet' is spelled this way in the source data, so the
--       spelling is kept on purpose.
CREATE or replace VIEW events_with_device_type AS
SELECT *,
CASE
    WHEN device IN (
        'acer aspire desktop',
        'acer aspire notebook',
        'asus chromebook',
        'dell inspiron desktop',
        'dell inspiron notebook',
        'hp pavilion desktop',
        'lenovo thinkpad',
        'mac mini',
        'macbook air',
        'macbook pro'
    ) THEN 'computer'
WHEN device IN (
        'amazon fire phone',
        'htc one',
        'iphone 4s',
        'iphone 5',
        'iphone 5s',
        'nexus 5',
        'nokia lumia 635',
        'samsung galaxy note',
        'samsung galaxy s4'
    ) THEN 'phone'
WHEN device IN (
        'ipad air',
        'ipad mini',
        'kindle fire',
        'nexus 10',
        'nexus 7',
        'samsumg galaxy tablet',
        'windows surface'
    ) THEN 'tablet'
	ELSE 'other'
END AS device_type
from events;


/* -----------------------------------------------------------------------------
   SECTION 5: INTEGRITY CHECKS ON EVENTS
   ----------------------------------------------------------------------------- */

-- A12. Orphan events (events whose user_id is missing from users)
-- Question : would a join to users silently drop any events?
-- Result   : no rows returned, so no orphan events exist.
select e.event_name, e.event_type,e.occurred_at,e.location,e.device
from events e
left join users u
on e.user_id=u.user_id
where u.user_id is null;

-- A13. Impossible order (an event that happened before the user was created)
-- Question : is there a logging or time-zone problem?
-- Result   : no rows returned. All events are recorded after user creation,
--            so no problem was found in the audit so far.
select e.event_name, e.event_type,e.occurred_at,e.location,e.device
from events e
left join users u
on e.user_id=u.user_id
where e.occurred_at< u.created_at;

-- A14. Duplicate events
-- Candidate key for "the same event": (user_id, occurred_at, event_name).
-- Duplicates would inflate event counts, so I test three variations.

-- A14a. Duplicates on (user_id, occurred_at, event_name)
select user_id, occurred_at, event_name, count(*) as n_copies from events
group by user_id, occurred_at,event_name
having count(*)>1
limit 20;

-- A14b. Same, with device added to the key
select user_id, occurred_at, event_name,device, count(*) as n_copies from events
group by user_id, occurred_at,event_name,device
having count(*)>1
limit 20;

-- A14c. For the groups from A14a, how many different devices were involved?
SELECT user_id,
       occurred_at,
       event_name,
       COUNT(DISTINCT device) AS n_devices
FROM events
GROUP BY user_id,
         occurred_at,
         event_name
HAVING COUNT(*) > 1;

-- A14d. Timestamp precision check: occurred_at includes seconds, so the same user
--       using two devices in the same second is very rare.
select occurred_at from events limit 5;

/*
   A14 conclusion
   Duplicate checks were performed using (user_id, occurred_at, event_name) as a candidate event key.
   Nine duplicate event groups were identified.
   When device was added to the grouping criteria, the count reduced to seven groups, indicating that two apparent duplicates differed only by device.
   Given the dataset size (~310,000 events), the duplicate incidence rate is extremely low (<0.01%).
   The seven remaining groups represent potential true duplicates, while the two cross-device cases may reflect logging behavior or rare multi-device activity.
   No material data quality concerns were identified, and the event table is considered suitable for further analysis.
*/


/* =============================================================================
   AUDIT LOG (summary of decisions)
   Check                    | Result                         | Decision
   -------------------------+--------------------------------+---------------------------
   user_id unique (A4)      | no duplicates                  | joins to users are safe
   Orphan events (A12)      | none                           | no events lost on join
   Events before signup(A13)| none                           | timestamps look consistent
   Duplicate events (A14)   | 9 groups in ~310k events       | ignore (<0.01%), flagged here
   Device names (A10)       | 26 raw names                   | grouped into 3 types via view
   ============================================================================= */
