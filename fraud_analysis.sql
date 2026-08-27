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
