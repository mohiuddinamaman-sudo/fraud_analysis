-- A.1: GAIA Transaction View

SELECT
    t.USER_ID,
    u.COUNTRY,
    t.AMOUNT
FROM transactions t
LEFT JOIN users u
    ON t.USER_ID = u.ID
WHERE t.SOURCE = 'GAIA';


-- A.2: First Successful Card Payment Over $10

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
),

first_payment_amount AS (
    SELECT
        f.USER_ID,
        (f.AMOUNT / POWER(10, c.EXPONENT)) AS amount_actual,
        f.CURRENCY,
        fx.RATE AS eur_to_currency_rate
    FROM first_card_payment f
    JOIN currency_details c
        ON f.CURRENCY = c.CURRENCY
    LEFT JOIN fx_rates fx
        ON fx.BASE_CCY = 'EUR'
       AND fx.CCY = f.CURRENCY
    WHERE f.rn = 1
),

converted AS (
    SELECT
        USER_ID,
        CASE
            WHEN CURRENCY = 'EUR'
                THEN amount_actual
            ELSE amount_actual / eur_to_currency_rate
        END AS amount_eur
    FROM first_payment_amount
),

converted_usd AS (
    SELECT
        USER_ID,
        amount_eur / (
            SELECT RATE
            FROM fx_rates
            WHERE BASE_CCY = 'EUR'
              AND CCY = 'USD'
        ) AS amount_usd
    FROM converted
)

SELECT
    COUNT(*) AS users_over_10_usd,
    (SELECT COUNT(*) FROM users) AS total_users,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM users) AS percentage_users
FROM converted_usd
WHERE amount_usd > 10;


-- Fraudster Analysis
-- Step 1: Remove users already in the known fraudsters list

SELECT
    t.*
FROM transactions t
LEFT JOIN fraudsters f
    ON t.USER_ID = f.USER_ID
WHERE f.USER_ID IS NULL;


-- Step 2: Create user-level transaction metrics

WITH transaction_eur AS (
    SELECT
        t.USER_ID,
        t.STATE,
        CASE
            WHEN t.CURRENCY = 'EUR'
                THEN t.AMOUNT / POWER(10, c.EXPONENT)
            ELSE
                (t.AMOUNT / POWER(10, c.EXPONENT)) / fx.RATE
        END AS amount_eur
    FROM transactions t
    LEFT JOIN fraudsters f
        ON t.USER_ID = f.USER_ID
    JOIN currency_details c
        ON t.CURRENCY = c.CURRENCY
    LEFT JOIN fx_rates fx
        ON fx.BASE_CCY = 'EUR'
       AND fx.CCY = t.CURRENCY
    WHERE f.USER_ID IS NULL
)

SELECT
    USER_ID,
    AVG(amount_eur) AS avg_amount_eur,
    MAX(amount_eur) AS max_amount_eur,
    SUM(amount_eur) AS total_amount_eur,
    COUNT(*) AS transactions,
    SUM(CASE WHEN STATE = 'DECLINED' THEN 1 ELSE 0 END) AS declined,
    SUM(CASE WHEN STATE = 'REVERTED' THEN 1 ELSE 0 END) AS reverted
FROM transaction_eur
GROUP BY USER_ID;


-- Step 3: Compare known fraudsters with other users

WITH transaction_eur AS (
    SELECT
        t.USER_ID,
        t.STATE,
        CASE
            WHEN t.CURRENCY = 'EUR'
                THEN t.AMOUNT / POWER(10, c.EXPONENT)
            ELSE
                (t.AMOUNT / POWER(10, c.EXPONENT)) / fx.RATE
        END AS amount_eur
    FROM transactions t
    JOIN currency_details c
        ON t.CURRENCY = c.CURRENCY
    LEFT JOIN fx_rates fx
        ON fx.BASE_CCY = 'EUR'
       AND fx.CCY = t.CURRENCY
)

SELECT
    CASE
        WHEN f.USER_ID IS NOT NULL THEN 'KNOWN FRAUDSTERS'
        ELSE 'OTHER USERS'
    END AS user_group,
    COUNT(DISTINCT t.USER_ID) AS users,
    AVG(t.amount_eur) AS avg_amount_eur,
    MAX(t.amount_eur) AS max_amount_eur,
    SUM(t.amount_eur) AS total_amount_eur,
    COUNT(*) AS transactions,
    SUM(CASE WHEN t.STATE = 'DECLINED' THEN 1 ELSE 0 END) AS declined,
    SUM(CASE WHEN t.STATE = 'REVERTED' THEN 1 ELSE 0 END) AS reverted
FROM transaction_eur t
LEFT JOIN fraudsters f
    ON t.USER_ID = f.USER_ID
GROUP BY
    CASE
        WHEN f.USER_ID IS NOT NULL THEN 'KNOWN FRAUDSTERS'
        ELSE 'OTHER USERS'
    END;


-- Step 4 & 5: Calculate fraud indicators and rank users

WITH transaction_eur AS (
    SELECT
        t.USER_ID,
        t.STATE,
        CASE
            WHEN t.CURRENCY = 'EUR'
                THEN t.AMOUNT / POWER(10, c.EXPONENT)
            ELSE
                (t.AMOUNT / POWER(10, c.EXPONENT)) / fx.RATE
        END AS amount_eur
    FROM transactions t
    LEFT JOIN fraudsters f
        ON t.USER_ID = f.USER_ID
    JOIN currency_details c
        ON t.CURRENCY = c.CURRENCY
    LEFT JOIN fx_rates fx
        ON fx.BASE_CCY = 'EUR'
       AND fx.CCY = t.CURRENCY
    WHERE f.USER_ID IS NULL
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
            CASE WHEN avg_amount_eur > 1000 THEN 1 ELSE 0 END
            + CASE WHEN max_amount_eur > 5000 THEN 1 ELSE 0 END
            + CASE WHEN total_amount_eur > 100000 THEN 1 ELSE 0 END
            + CASE WHEN declined >= 10 THEN 1 ELSE 0 END
            + CASE WHEN reverted >= 10 THEN 1 ELSE 0 END
        ) AS fraud_score
    FROM user_metrics
)

SELECT *
FROM scored_users
ORDER BY fraud_score DESC, total_amount_eur DESC
LIMIT 5;
