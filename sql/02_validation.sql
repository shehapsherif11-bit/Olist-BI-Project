
USE Olist_BI_TrackB;
GO

/* ============================================================
   OLIST E-COMMERCE PROJECT
   TRACK B - PRODUCTS & CATEGORIES

   SCRIPT: 01_data_profile.sql
   PURPOSE: Initial Data Quality Audit

   This script checks:
   1. Negative and missing financial values
   2. Invalid review scores
   3. Invalid and missing order dates
   4. Invalid product measurements
   5. Missing product categories
   6. Orders outside the required analysis period

   IMPORTANT:
   This script only profiles the data.
   It does NOT update or delete any records.
   ============================================================ */


/* ============================================================
   SECTION 1: FINANCIAL DATA QUALITY
   Check negative and NULL prices, freight, and payments.
   ============================================================ */

-- 1.1 Order Items: Price and Freight Validation

SELECT
    COUNT(*) AS total_item_rows,

    SUM(CASE
        WHEN price < 0 THEN 1 ELSE 0
    END) AS negative_prices,

    SUM(CASE
        WHEN freight_value < 0 THEN 1 ELSE 0
    END) AS negative_freight,

    SUM(CASE
        WHEN price IS NULL THEN 1 ELSE 0
    END) AS null_prices,

    SUM(CASE
        WHEN freight_value IS NULL THEN 1 ELSE 0
    END) AS null_freight

FROM dbo.order_items;


-- 1.2 Order Payments: Payment Value Validation

SELECT
    COUNT(*) AS total_payment_rows,

    SUM(CASE
        WHEN payment_value < 0 THEN 1 ELSE 0
    END) AS negative_payments,

    SUM(CASE
        WHEN payment_value IS NULL THEN 1 ELSE 0
    END) AS null_payments

FROM dbo.order_payments;


/* ============================================================
   SECTION 2: REVIEW DATA QUALITY
   Valid review scores must be between 1 and 5.
   NULL scores are counted as invalid for this check.
   ============================================================ */

SELECT
    COUNT(*) AS total_reviews,

    SUM(CASE
        WHEN review_score NOT BETWEEN 1 AND 5
             OR review_score IS NULL
        THEN 1 ELSE 0
    END) AS invalid_scores,

    SUM(CASE
        WHEN review_score IS NULL
        THEN 1 ELSE 0
    END) AS null_scores

FROM dbo.order_reviews;


/* ============================================================
   SECTION 3: ORDER DATE VALIDATION
   Check impossible date sequences and missing delivery dates.
   ============================================================ */

-- 3.1 Invalid Date Sequences

SELECT
    COUNT(*) AS invalid_date_sequences

FROM dbo.orders

WHERE
    (order_delivered_customer_date IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_delivered_customer_date < order_purchase_timestamp)

    OR

    (order_delivered_carrier_date IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_delivered_carrier_date < order_purchase_timestamp)

    OR

    (order_approved_at IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_approved_at < order_purchase_timestamp);


-- 3.2 Missing Delivery Dates

SELECT
    COUNT(*) AS total_orders,

    SUM(CASE
        WHEN order_delivered_customer_date IS NULL
        THEN 1 ELSE 0
    END) AS missing_actual_delivery,

    SUM(CASE
        WHEN order_estimated_delivery_date IS NULL
        THEN 1 ELSE 0
    END) AS missing_estimated_delivery

FROM dbo.orders;


/* ============================================================
   SECTION 4: PRODUCT DATA QUALITY
   Check invalid product measurements.
   Measurements must be positive when provided.
   ============================================================ */

SELECT
    COUNT(*) AS total_products,

    SUM(CASE
        WHEN product_weight_g <= 0
        THEN 1 ELSE 0
    END) AS invalid_weight,

    SUM(CASE
        WHEN product_length_cm <= 0
        THEN 1 ELSE 0
    END) AS invalid_length,

    SUM(CASE
        WHEN product_height_cm <= 0
        THEN 1 ELSE 0
    END) AS invalid_height,

    SUM(CASE
        WHEN product_width_cm <= 0
        THEN 1 ELSE 0
    END) AS invalid_width,

    SUM(CASE
        WHEN product_category_name IS NULL
        THEN 1 ELSE 0
    END) AS missing_categories

FROM dbo.products;


/* ============================================================
   SECTION 5: CATEGORY TRANSLATION VALIDATION
   Check products whose categories do not have a translation.
   LEFT JOIN keeps products with missing categories visible.
   ============================================================ */

SELECT
    COUNT(*) AS total_products,

    SUM(CASE
        WHEN p.product_category_name IS NULL
        THEN 1 ELSE 0
    END) AS null_categories,

    SUM(CASE
        WHEN p.product_category_name IS NOT NULL
             AND ct.product_category_name IS NULL
        THEN 1 ELSE 0
    END) AS missing_translations

FROM dbo.products AS p

LEFT JOIN dbo.category_translation AS ct
    ON p.product_category_name = ct.product_category_name;


/* ============================================================
   SECTION 6: ANALYSIS DATE SCOPE
   Required purchase-date window:
   Start: 2017-01-01 (inclusive)
   End:   2018-09-01 (exclusive)

   Original source data remains unchanged.
   ============================================================ */

SELECT
    COUNT(*) AS all_orders,

    SUM(CASE
        WHEN order_purchase_timestamp >= '2017-01-01'
         AND order_purchase_timestamp < '2018-09-01'
        THEN 1 ELSE 0
    END) AS orders_in_scope,

    SUM(CASE
        WHEN order_purchase_timestamp < '2017-01-01'
          OR order_purchase_timestamp >= '2018-09-01'
        THEN 1 ELSE 0
    END) AS orders_outside_scope,

    SUM(CASE
        WHEN order_purchase_timestamp IS NULL
        THEN 1 ELSE 0
    END) AS missing_purchase_dates

FROM dbo.orders;


/* ============================================================
   END OF INITIAL DATA QUALITY AUDIT

   No records have been modified or deleted.
   Review all results before starting data cleaning.
   ============================================================ */







/*****************/


USE Olist_BI_TrackB;
GO

/* ============================================================
   SECTION 7: INVESTIGATE INVALID ORDER DATE SEQUENCES
   Identify exactly which date condition is violated.
   ============================================================ */

SELECT
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,

    CASE
        WHEN order_approved_at < order_purchase_timestamp
        THEN 1 ELSE 0
    END AS approval_before_purchase,

    CASE
        WHEN order_delivered_carrier_date < order_purchase_timestamp
        THEN 1 ELSE 0
    END AS carrier_before_purchase,

    CASE
        WHEN order_delivered_customer_date < order_purchase_timestamp
        THEN 1 ELSE 0
    END AS delivery_before_purchase

FROM dbo.orders

WHERE
    (order_approved_at IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_approved_at < order_purchase_timestamp)

    OR

    (order_delivered_carrier_date IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_delivered_carrier_date < order_purchase_timestamp)

    OR

    (order_delivered_customer_date IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_delivered_customer_date < order_purchase_timestamp)

ORDER BY order_purchase_timestamp;


/* ============================================================
   SECTION 8: INVESTIGATE MISSING DELIVERY DATES
   Check whether missing dates are related to order status.
   ============================================================ */

SELECT
    order_status,
    COUNT(*) AS total_orders,

    SUM(CASE
        WHEN order_delivered_customer_date IS NULL
        THEN 1 ELSE 0
    END) AS missing_actual_delivery,

    SUM(CASE
        WHEN order_estimated_delivery_date IS NULL
        THEN 1 ELSE 0
    END) AS missing_estimated_delivery

FROM dbo.orders

GROUP BY order_status

ORDER BY total_orders DESC;


/* ============================================================
   SECTION 9: INVESTIGATE INVALID PRODUCT WEIGHTS
   Check NULL, zero, and negative weights separately.
   ============================================================ */

SELECT
    product_id,
    product_category_name,
    product_weight_g,

    CASE
        WHEN product_weight_g IS NULL THEN 'NULL'
        WHEN product_weight_g = 0 THEN 'ZERO'
        WHEN product_weight_g < 0 THEN 'NEGATIVE'
        ELSE 'VALID'
    END AS weight_status

FROM dbo.products

WHERE product_weight_g IS NULL
   OR product_weight_g <= 0

ORDER BY product_weight_g;


/* ============================================================
   SECTION 10: INVESTIGATE MISSING PRODUCT CATEGORIES
   Show products without a category.
   ============================================================ */

SELECT
    product_id,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm

FROM dbo.products

WHERE product_category_name IS NULL;


/* ============================================================
   SECTION 11: INVESTIGATE MISSING CATEGORY TRANSLATIONS
   Show category names that have no translation.
   ============================================================ */

SELECT
    p.product_category_name,
    COUNT(*) AS affected_products

FROM dbo.products AS p

LEFT JOIN dbo.category_translation AS ct
    ON p.product_category_name = ct.product_category_name

WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name IS NULL

GROUP BY p.product_category_name

ORDER BY affected_products DESC;


/* ============================================================
   END OF DIAGNOSTIC INVESTIGATION
   No records have been modified or deleted.
   ============================================================ */




/***************/



USE Olist_BI_TrackB;
GO

/* ==========================================
   1. DATE ISSUES SUMMARY
   ========================================== */

SELECT
    COUNT(*) AS total_invalid_orders,

    SUM(CASE WHEN order_approved_at < order_purchase_timestamp
        THEN 1 ELSE 0 END) AS approval_before_purchase,

    SUM(CASE WHEN order_delivered_carrier_date < order_purchase_timestamp
        THEN 1 ELSE 0 END) AS carrier_before_purchase,

    SUM(CASE WHEN order_delivered_customer_date < order_purchase_timestamp
        THEN 1 ELSE 0 END) AS delivery_before_purchase

FROM dbo.orders
WHERE
    (order_approved_at IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_approved_at < order_purchase_timestamp)

    OR

    (order_delivered_carrier_date IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_delivered_carrier_date < order_purchase_timestamp)

    OR

    (order_delivered_customer_date IS NOT NULL
     AND order_purchase_timestamp IS NOT NULL
     AND order_delivered_customer_date < order_purchase_timestamp);


/* ==========================================
   2. DELIVERED ORDERS WITH MISSING DATES
   ========================================== */

SELECT
    COUNT(*) AS delivered_orders,
    SUM(CASE WHEN order_delivered_customer_date IS NULL
        THEN 1 ELSE 0 END) AS missing_actual_delivery,
    SUM(CASE WHEN order_estimated_delivery_date IS NULL
        THEN 1 ELSE 0 END) AS missing_estimated_delivery
FROM dbo.orders
WHERE order_status = 'delivered';


/* ==========================================
   3. PRODUCT WEIGHT SUMMARY
   ========================================== */

SELECT
    COUNT(*) AS total_products,

    SUM(CASE WHEN product_weight_g IS NULL
        THEN 1 ELSE 0 END) AS null_weights,

    SUM(CASE WHEN product_weight_g = 0
        THEN 1 ELSE 0 END) AS zero_weights,

    SUM(CASE WHEN product_weight_g < 0
        THEN 1 ELSE 0 END) AS negative_weights

FROM dbo.products;


/* ==========================================
   4. PRODUCT CATEGORY SUMMARY
   ========================================== */

SELECT
    COUNT(*) AS total_products,

    SUM(CASE WHEN product_category_name IS NULL
        THEN 1 ELSE 0 END) AS null_categories

FROM dbo.products;


/* ==========================================
   5. UNTRANSLATED CATEGORIES
   ========================================== */

SELECT
    p.product_category_name,
    COUNT(*) AS affected_products

FROM dbo.products p

LEFT JOIN dbo.category_translation ct
    ON p.product_category_name = ct.product_category_name

WHERE p.product_category_name IS NOT NULL
  AND ct.product_category_name IS NULL

GROUP BY p.product_category_name

ORDER BY affected_products DESC;
GO


/********************/


USE Olist_BI_TrackB;
GO

-- Check existing Primary Keys
SELECT
    tc.TABLE_NAME,
    tc.CONSTRAINT_NAME,
    STRING_AGG(kcu.COLUMN_NAME, ' + ')
        WITHIN GROUP (ORDER BY kcu.ORDINAL_POSITION) AS primary_key_columns
FROM INFORMATION_SCHEMA.TABLE_CONSTRAINTS tc
JOIN INFORMATION_SCHEMA.KEY_COLUMN_USAGE kcu
    ON tc.CONSTRAINT_NAME = kcu.CONSTRAINT_NAME
    AND tc.TABLE_SCHEMA = kcu.TABLE_SCHEMA
WHERE tc.CONSTRAINT_TYPE = 'PRIMARY KEY'
  AND tc.TABLE_SCHEMA = 'dbo'
GROUP BY
    tc.TABLE_NAME,
    tc.CONSTRAINT_NAME
ORDER BY tc.TABLE_NAME;
GO

-- Check existing Foreign Keys
SELECT
    fk.name AS foreign_key_name,
    OBJECT_NAME(fk.parent_object_id) AS child_table,
    OBJECT_NAME(fk.referenced_object_id) AS parent_table,
    fk.is_disabled
FROM sys.foreign_keys fk
ORDER BY child_table;
GO
