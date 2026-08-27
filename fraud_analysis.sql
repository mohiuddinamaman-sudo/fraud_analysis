-- A.1: GAIA Transaction View

SELECT
    t.USER_ID,
    u.COUNTRY,
    t.AMOUNT
FROM transactions t
LEFT JOIN users u
    ON t.USER_ID = u.ID
WHERE t.SOURCE = 'GAIA';



-- A.2: Transaction Success Rate

WITH first_card_payment AS (
    SELECT
        t.USER_ID,
        t.CREATED_DATE,
        t.AMOUNT,
        t.CURRENCY,
        ROW_NUMBER() OVER (
            PARTITION BY t.USER_ID
            ORDER BY t.CREATED_DATE
        ) AS rn
    FROM transactions t
    WHERE t.TYPE = 'CARD_PAYMENT'
      AND t.STATE = 'COMPLETED'
)

SELECT
    COUNT(*) AS successful_users,
    (SELECT COUNT(*) FROM users) AS total_users,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM users) AS success_rate
FROM first_card_payment f
JOIN currency_details c
    ON f.CURRENCY = c.CURRENCY
JOIN fx_rates r
    ON r.BASE_CCY = 'EUR'
   AND r.CCY = 'USD'
WHERE f.rn = 1
  AND (f.AMOUNT / POWER(10, c.EXPONENT)) * r.RATE > 10;

-- Fraudster Analysis
-- Step 1: Exclude users already in the known fraudsters list

SELECT
    t.*
FROM transactions t
LEFT JOIN fraudsters f
    ON t.USER_ID = f.user_id
WHERE f.user_id IS NULL;


-- Step 2: Create transaction metrics for each user

SELECT
    t.USER_ID,
    COUNT(*) AS total_transactions,
    SUM(t.AMOUNT) AS total_amount,
    AVG(t.AMOUNT) AS avg_amount,
    SUM(CASE WHEN t.STATE = 'DECLINED' THEN 1 ELSE 0 END) AS declined_transactions
FROM transactions t
LEFT JOIN fraudsters f
    ON t.USER_ID = f.user_id
WHERE f.user_id IS NULL
GROUP BY t.USER_ID;

-- Step 3: Compare known fraudsters with other users

SELECT
    CASE
        WHEN f.user_id IS NOT NULL THEN 'KNOWN FRAUDSTERS'
        ELSE 'OTHER USERS'
    END AS user_group,
    COUNT(DISTINCT t.USER_ID) AS users,
    AVG(t.AMOUNT) AS avg_transaction_amount,
    MAX(t.AMOUNT) AS max_transaction_amount,
    COUNT(*) AS total_transactions,
    SUM(CASE WHEN t.STATE = 'DECLINED' THEN 1 ELSE 0 END) AS declined_transactions,
    SUM(CASE WHEN t.STATE = 'REVERTED' THEN 1 ELSE 0 END) AS reverted_transactions
FROM transactions t
LEFT JOIN fraudsters f
    ON t.USER_ID = f.user_id
GROUP BY
    CASE
        WHEN f.user_id IS NOT NULL THEN 'KNOWN FRAUDSTERS'
        ELSE 'OTHER USERS'
    END;


-- Steps 4 & 5: Convert transaction amounts to EUR,
-- calculate fraud indicators and identify the top 5 users

WITH transaction_eur AS (
    SELECT
        t.USER_ID,
        t.STATE,
        CASE
            WHEN t.CURRENCY = 'EUR'
                THEN t.AMOUNT / POWER(10, c.exponent)
            ELSE
                (t.AMOUNT / POWER(10, c.exponent)) * r.rate
        END AS amount_eur
    FROM transactions t
    LEFT JOIN fraudsters f
        ON t.USER_ID = f.user_id
    LEFT JOIN currencies c
        ON t.CURRENCY = c.currency
    LEFT JOIN rates r
        ON r.base_ccy = 'EUR'
        AND r.ccy = t.CURRENCY
    WHERE f.user_id IS NULL
),

user_metrics AS (
    SELECT
        USER_ID,
        AVG(amount_eur) AS avg_amount_eur,
        MAX(amount_eur) AS max_amount_eur,
        SUM(amount_eur) AS total_amount_eur,
        COUNT(*) AS transactions,
        SUM(CASE WHEN STATE = 'DECLINED' THEN 1 ELSE 0 END) AS declined,
        SUM(CASE WHEN STATE = 'REVERTED' THEN 1 ELSE 0 END) AS reverted
    FROM transaction_eur
    GROUP BY USER_ID
),

scored_users AS (
    SELECT
        USER_ID,
        avg_amount_eur,
        max_amount_eur,
        total_amount_eur,
        transactions,
        declined,
        reverted,
        (
            CASE WHEN avg_amount_eur > 1000 THEN 1 ELSE 0 END +
            CASE WHEN max_amount_eur > 5000 THEN 1 ELSE 0 END +
            CASE WHEN total_amount_eur > 100000 THEN 1 ELSE 0 END +
            CASE WHEN declined >= 10 THEN 1 ELSE 0 END +
            CASE WHEN reverted >= 10 THEN 1 ELSE 0 END
        ) AS fraud_score
    FROM user_metrics
)

SELECT *
FROM scored_users
ORDER BY fraud_score DESC, total_amount_eur DESC
LIMIT 5;
