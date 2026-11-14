/* =============================================================================
   FILE     : 05_size_and_contribution.sql
   PROJECT  : Yammer case study, Part 1: A Drop in Engagement
   PURPOSE  : Put numbers on the drop (how big?) and on each segment's share of it
              (who contributed how much?). The device and country queries are in
              03_segmentation.sql; this file adds the headline numbers and the
              language and company cuts, then summarises all of them.
   DIALECT  : PostgreSQL

   HOW "BEFORE" AND "AFTER" ARE DEFINED (my choice, state it in the write-up)
     Before = average weekly engaged users over the 4 weeks starting 7, 14, 21, 28 July
     After  = average weekly engaged users over the 4 weeks starting 4, 11, 18, 25 August
     Weekly noise: before the drop, total weekly engaged users typically moved by about
     3% from one week to the next, so changes much larger than that are not noise.
   Averages and percentages below were calculated outside SQL from the query outputs.

   NOTE: the week starting 2014-04-28 (701 users vs about 1,050 the week after) looks like
   a partial week. Check min(occurred_at) from 01_data_audit.sql and ignore that week
   when judging trends.
   ============================================================================= */


/* -----------------------------------------------------------------------------
   E1. Headline: weekly engaged users
   Grain : one row per calendar week
   ----------------------------------------------------------------------------- */

select count(distinct user_id), date_trunc('week', occurred_at):: date as week_start
from events
where event_type='engagement' and occurred_at>='2014-04-28' and occurred_at<='2014-09-01'
group by 2
order by 2;

/*
   Result (from the output)
     Before (avg of 7 Jul to 28 Jul weeks) : 1,376.5 engaged users per week
     After  (avg of 4 Aug to 25 Aug weeks) : 1,219.5 engaged users per week
     Change                                : -157 users per week, -11.4%
     Peak week (28 Jul) 1,443 -> last week (25 Aug) 1,194 : -17.3%
     The week of 4 Aug alone is -12.3% vs the week before, so the drop starts that week
     and does not recover through August.
*/


/* -----------------------------------------------------------------------------
   E2. Language cut (users.language)
   Grain : one row per week per language (one language per user)
   Sanity check : the language counts add up to the E1 total in every week.
   ----------------------------------------------------------------------------- */

SELECT
    DATE_TRUNC('week', e.occurred_at)::date AS week_start,
    COALESCE(u.language,'unknown') AS language,
    COUNT(DISTINCT e.user_id) AS engaged_users
FROM events e
JOIN users u
    ON e.user_id = u.user_id
WHERE e.event_type = 'engagement'
  AND e.occurred_at >= '2014-04-28'
  AND e.occurred_at < '2014-09-01'
GROUP BY 1,2
ORDER BY 2,1;

/*
   Result: before -> after (avg weekly engaged users), share of total loss
     english    706 -> 617   -12.6%   57% of the loss (51% of users)
     french     116 ->  92   -20.5%   15% of the loss ( 8% of users)
     arabic      53 ->  43   -19.0%    6%
     indian      40 ->  32   -18.9%    5%
     german      81 ->  74    -9.5%    5%
     japanese    91 ->  85    -6.1%    4%
     spanish    122 -> 118    -3.3%    3%
     the rest (chinese, italian, korean, portugese): small declines; russian +2%
   Reading: almost every language falls, and English carries its proportional share, so
   it is not a one-language problem. French, Arabic and Indian fall by more in percent,
   but their weekly counts are small (about 40 to 115), so those percentages are noisy.
*/


/* -----------------------------------------------------------------------------
   E3. Company concentration (10 companies with the most registered users)
   Hypothesis : if a few large customers stopped using Yammer, the drop would sit there
   Output     : company_id, then one column per week (w1 = week of 28 Apr ... w18 = 25 Aug)
   Limit      : only the top 10 companies by registered users are shown
   ----------------------------------------------------------------------------- */

WITH top_companies AS (
    SELECT company_id
    FROM users
    GROUP BY 1
    ORDER BY COUNT(*) DESC
    LIMIT 10
),
company_engagement AS (
    SELECT
        u.company_id,
        DATE_TRUNC('week', e.occurred_at)::date AS week_start,
        COUNT(DISTINCT e.user_id) AS engaged_users
    FROM events e
    JOIN users u
        ON e.user_id = u.user_id
    JOIN top_companies tc
        ON tc.company_id = u.company_id
    WHERE e.event_type = 'engagement'
      AND e.occurred_at >= '2014-04-28'
      AND e.occurred_at < '2014-09-01'
    GROUP BY 1,2
)
SELECT
    company_id,
    MAX(CASE WHEN week_start='2014-04-28' THEN engaged_users END) AS w1,
    MAX(CASE WHEN week_start='2014-05-05' THEN engaged_users END) AS w2,
    MAX(CASE WHEN week_start='2014-05-12' THEN engaged_users END) AS w3,
    MAX(CASE WHEN week_start='2014-05-19' THEN engaged_users END) AS w4,
    MAX(CASE WHEN week_start='2014-05-26' THEN engaged_users END) AS w5,
    MAX(CASE WHEN week_start='2014-06-02' THEN engaged_users END) AS w6,
    MAX(CASE WHEN week_start='2014-06-09' THEN engaged_users END) AS w7,
    MAX(CASE WHEN week_start='2014-06-16' THEN engaged_users END) AS w8,
    MAX(CASE WHEN week_start='2014-06-23' THEN engaged_users END) AS w9,
    MAX(CASE WHEN week_start='2014-06-30' THEN engaged_users END) AS w10,
    MAX(CASE WHEN week_start='2014-07-07' THEN engaged_users END) AS w11,
    MAX(CASE WHEN week_start='2014-07-14' THEN engaged_users END) AS w12,
    MAX(CASE WHEN week_start='2014-07-21' THEN engaged_users END) AS w13,
    MAX(CASE WHEN week_start='2014-07-28' THEN engaged_users END) AS w14,
    MAX(CASE WHEN week_start='2014-08-04' THEN engaged_users END) AS w15,
    MAX(CASE WHEN week_start='2014-08-11' THEN engaged_users END) AS w16,
    MAX(CASE WHEN week_start='2014-08-18' THEN engaged_users END) AS w17,
    MAX(CASE WHEN week_start='2014-08-25' THEN engaged_users END) AS w18
FROM company_engagement
GROUP BY company_id
ORDER BY company_id;

/*
   Result
     The 10 companies together are about 16% of weekly engaged users and account for
     about 14% of the loss (220 -> 198 users per week, -9.9%). So the drop is not
     concentrated in the largest companies.
     Companies 6 and 7 fell by about half and company 9 by about a quarter, but their
     weekly counts are tiny (for example 16 -> 8), so this is within noise. Companies 3
     and 8 rose.
   Limit: this checks only the top 10 companies. It cannot rule out a pattern across the
   many smaller ones.
*/


/* =============================================================================
   HOW MUCH EACH SEGMENT CONTRIBUTED (before -> after, avg weekly engaged users)
   Total: 1,376.5 -> 1,219.5 (-157, -11.4%)

   Device (from 03_segmentation.sql; a user can appear in more than one device, so
   shares add up to more than 100%)
     computer   908 -> 885    -2.6%   about as much as normal weekly noise (typically +/-4%)
     phone      590 -> 450   -23.8%
     tablet     238 -> 163   -31.4%
   Country (top 6 by users; columns in 03 are France, Germany, Italy, Japan, UK, US)
     France     67 -> 52     -22.1%
     Germany    92 -> 79     -13.9%
     Italy      53 -> 47     -10.0%
     Japan     100 -> 92      -8.7%
     UK         61 -> 56      -9.0%
     US        394 -> 350    -11.2%   28% of the loss, 29% of users
   The six countries hold 56% of users and 58% of the loss, so no country is out of
   proportion. The US falls by about the same percent as the total.
   Language and company: see E2 and E3 above.

   WHAT THIS MEANS
   - The size of the drop is about 11% (about 160 fewer engaged users a week) and it
     persists through August.
   - It is NOT concentrated in one country, language or large company.
   - It IS concentrated on phone and tablet: computer users barely moved (-2.6%), while
     phone fell about 24% and tablet about 31%.
   - So "the decline is broad across devices" is not accurate. It is broad across countries
     and languages, but concentrated on mobile devices.
   - Together with the email finding (clickthrough down), a possible story is a problem on
     mobile, such as the email-to-app path, an app or mobile-web issue, or both.
     This is a hypothesis to test, not a conclusion.

   NEXT QUERY TO TRY: break phone and tablet down by device model (iphone, nexus,
   samsung galaxy, ...) to see whether the loss sits in one platform or model.
   ============================================================================= */
