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
