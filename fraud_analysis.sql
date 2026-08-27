-- A.1: GAIA Transaction View

SELECT
    t.USER_ID,
    u.COUNTRY,
    t.AMOUNT
FROM transactions t
LEFT JOIN users u
    ON t.USER_ID = u.ID
WHERE t.SOURCE = 'GAIA';
