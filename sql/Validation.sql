/* =====================================================================
   File: sql/02_validation.sql
   Purpose: Data profiling, key uniqueness checks, orphan FK checks,
            anomaly detection, and creating documented analytical views.
   Database: Olist_BI_Project (SQL Server)
   ===================================================================== */

USE Olist_BI_Project;
GO

/* =====================================================================
   0. Header-Row Hygiene Check (Wizard Import Safeguard)
   Purpose: Ensure no CSV column header row was accidentally imported as data.
   ===================================================================== */
DELETE FROM dbo.customers            WHERE customer_id = 'customer_id';
DELETE FROM dbo.orders               WHERE order_id = 'order_id';
DELETE FROM dbo.order_items          WHERE order_id = 'order_id';
DELETE FROM dbo.products             WHERE product_id = 'product_id';
DELETE FROM dbo.sellers              WHERE seller_id = 'seller_id';
DELETE FROM dbo.order_payments       WHERE order_id = 'order_id';
DELETE FROM dbo.order_reviews        WHERE review_id = 'review_id';
DELETE FROM dbo.category_translation WHERE product_category_name = 'product_category_name';
GO

/* =====================================================================
   1. Imported Row Counts Across All 8 Tables
   Purpose: Verify imported row counts against the original Kaggle CSV files.
   ===================================================================== */
SELECT 'customers'            AS table_name, COUNT(*) AS imported_row_count FROM dbo.customers
UNION ALL
SELECT 'orders',                             COUNT(*) FROM dbo.orders
UNION ALL
SELECT 'order_items',                        COUNT(*) FROM dbo.order_items
UNION ALL
SELECT 'products',                           COUNT(*) FROM dbo.products
UNION ALL
SELECT 'sellers',                            COUNT(*) FROM dbo.sellers
UNION ALL
SELECT 'order_payments',                     COUNT(*) FROM dbo.order_payments
UNION ALL
SELECT 'order_reviews',                      COUNT(*) FROM dbo.order_reviews
UNION ALL
SELECT 'category_translation',               COUNT(*) FROM dbo.category_translation
ORDER BY table_name ASC;
GO

/* =====================================================================
   2. Candidate Key Uniqueness & Duplicate Checks
   Purpose: Test candidate keys across all tables and profile multiple
            reviews per order in dbo.order_reviews.
   ===================================================================== */
SELECT 'customers (customer_id)'                   AS key_tested, COUNT(*) AS total_rows, COUNT(DISTINCT customer_id) AS distinct_keys, COUNT(*) - COUNT(DISTINCT customer_id) AS duplicate_rows FROM dbo.customers
UNION ALL
SELECT 'orders (order_id)',                                       COUNT(*), COUNT(DISTINCT order_id), COUNT(*) - COUNT(DISTINCT order_id) FROM dbo.orders
UNION ALL
SELECT 'products (product_id)',                                   COUNT(*), COUNT(DISTINCT product_id), COUNT(*) - COUNT(DISTINCT product_id) FROM dbo.products
UNION ALL
SELECT 'sellers (seller_id)',                                     COUNT(*), COUNT(DISTINCT seller_id), COUNT(*) - COUNT(DISTINCT seller_id) FROM dbo.sellers
UNION ALL
SELECT 'category_translation (product_category_name)',            COUNT(*), COUNT(DISTINCT product_category_name), COUNT(*) - COUNT(DISTINCT product_category_name) FROM dbo.category_translation
UNION ALL
SELECT 'order_reviews (review_id)',                               COUNT(*), COUNT(DISTINCT review_id), COUNT(*) - COUNT(DISTINCT review_id) FROM dbo.order_reviews
UNION ALL
SELECT 'order_reviews (order_id)',                                COUNT(*), COUNT(DISTINCT order_id), COUNT(*) - COUNT(DISTINCT order_id) FROM dbo.order_reviews;

-- Exact count of orders having more than one source review row (Required for report)
SELECT
    COUNT(*) AS orders_with_multiple_reviews,
    SUM(rev_cnt) AS total_rows_for_multi_review_orders
FROM (
    SELECT order_id, COUNT(*) AS rev_cnt
    FROM dbo.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) AS multi_reviews;
GO

/* =====================================================================
   3. Unmatched Foreign Keys / Orphan Records Check
   Purpose: Inspect join coverage before writing analytical queries.
   ===================================================================== */
SELECT
    (SELECT COUNT(*) FROM dbo.orders o LEFT JOIN dbo.customers c ON o.customer_id = c.customer_id WHERE c.customer_id IS NULL) AS orders_missing_customer,
    (SELECT COUNT(*) FROM dbo.orders o LEFT JOIN dbo.order_items oi ON o.order_id = oi.order_id WHERE oi.order_id IS NULL) AS orders_without_items,
    (SELECT COUNT(*) FROM dbo.orders o LEFT JOIN dbo.order_payments op ON o.order_id = op.order_id WHERE op.order_id IS NULL) AS orders_without_payments,
    (SELECT COUNT(*) FROM dbo.orders o LEFT JOIN dbo.order_reviews r ON o.order_id = r.order_id WHERE r.order_id IS NULL) AS orders_without_reviews,
    (SELECT COUNT(*) FROM dbo.order_items oi LEFT JOIN dbo.products p ON oi.product_id = p.product_id WHERE p.product_id IS NULL) AS items_missing_product,
    (SELECT COUNT(*) FROM dbo.order_items oi LEFT JOIN dbo.sellers s ON oi.seller_id = s.seller_id WHERE s.seller_id IS NULL) AS items_missing_seller,
    (SELECT COUNT(*) FROM dbo.products p LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name WHERE p.product_category_name IS NOT NULL AND ct.product_category_name IS NULL) AS products_untranslated_category;
GO

/* =====================================================================
   4. Missing Values (NULLs) & Invalid / Impossible Values Check
   Purpose: Profile NULLs, invalid review scores, and negative/impossible values.
   ===================================================================== */
SELECT
    (SELECT COUNT(*) FROM dbo.products WHERE product_category_name IS NULL OR LTRIM(RTRIM(product_category_name)) = '') AS products_null_category,
    (SELECT COUNT(*) FROM dbo.products WHERE product_weight_g IS NULL OR product_weight_g <= 0) AS products_null_or_zero_weight,
    (SELECT COUNT(*) FROM dbo.order_items WHERE price <= 0) AS items_zero_or_negative_price,
    (SELECT COUNT(*) FROM dbo.order_items WHERE freight_value < 0) AS items_negative_freight,
    (SELECT COUNT(*) FROM dbo.order_payments WHERE payment_value < 0 OR payment_installments < 0) AS payments_negative_values,
    (SELECT COUNT(*) FROM dbo.order_reviews WHERE review_score IS NULL OR review_score NOT BETWEEN 1 AND 5) AS reviews_invalid_score,
    (SELECT COUNT(*) FROM dbo.orders WHERE order_status = 'delivered' AND (order_delivered_customer_date IS NULL OR order_purchase_timestamp IS NULL)) AS delivered_missing_timestamps,
    (SELECT COUNT(*) FROM dbo.orders WHERE order_status = 'delivered' AND order_delivered_customer_date < order_purchase_timestamp) AS delivered_before_purchase_anomaly;
GO

/* =====================================================================
   5. Date Range & Analysis Scope Window Profiling
   Purpose: Check full dataset date boundaries vs. project scope
            [2017-01-01 inclusive, 2018-09-01 exclusive].
   ===================================================================== */
SELECT
    MIN(order_purchase_timestamp) AS min_purchase_timestamp,
    MAX(order_purchase_timestamp) AS max_purchase_timestamp,
    COUNT(*) AS total_all_orders,
    SUM(CASE WHEN order_purchase_timestamp >= '2017-01-01' AND order_purchase_timestamp < '2018-09-01' THEN 1 ELSE 0 END) AS orders_in_project_scope,
    SUM(CASE WHEN order_purchase_timestamp < '2017-01-01' OR order_purchase_timestamp >= '2018-09-01' OR order_purchase_timestamp IS NULL THEN 1 ELSE 0 END) AS orders_outside_scope,
    SUM(CASE WHEN order_purchase_timestamp >= '2017-01-01' AND order_purchase_timestamp < '2018-09-01' AND order_status = 'delivered' THEN 1 ELSE 0 END) AS delivered_orders_in_scope
FROM dbo.orders;
GO

/* =====================================================================
   6. Analytical View 1: One Review Per Order (dbo.vw_one_review_per_order)
   Purpose: Select a single valid review (score 1-5) per order while
            preserving raw rows in dbo.order_reviews.
   Tie-Breaking Rule: Latest non-null review_answer_timestamp first
            (NULLs treated as oldest), then latest review_creation_date,
            then review_id DESC for deterministic tie resolution.
   Output Grain: One row per valid reviewed order_id.
   ===================================================================== */
CREATE OR ALTER VIEW dbo.vw_one_review_per_order AS
WITH RankedReviews AS (
    SELECT
        r.order_id,
        r.review_id,
        r.review_score,
        r.review_creation_date,
        r.review_answer_timestamp,
        COUNT(*) OVER (PARTITION BY r.order_id) AS source_review_count_for_order,
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id
            ORDER BY
                CASE WHEN r.review_answer_timestamp IS NULL THEN 1 ELSE 0 END ASC,
                r.review_answer_timestamp DESC,
                CASE WHEN r.review_creation_date IS NULL THEN 1 ELSE 0 END ASC,
                r.review_creation_date DESC,
                r.review_id DESC
        ) AS rn
    FROM dbo.order_reviews r
    WHERE r.review_score BETWEEN 1 AND 5
)
SELECT
    order_id,
    review_id,
    review_score,
    CASE WHEN review_score IN (1, 2) THEN 1 ELSE 0 END AS is_low_rating,
    review_creation_date,
    review_answer_timestamp,
    source_review_count_for_order
FROM RankedReviews
WHERE rn = 1;
GO

/* =====================================================================
   7. Analytical View 2: Order-Level Item Totals (dbo.vw_order_item_totals)
   Purpose: Pre-aggregate item prices, freight, and counts at the order_id
            grain before joining to orders, payments, or reviews to prevent
            many-to-many fan-out duplication.
   Output Grain: One row per order_id present in dbo.order_items.
   ===================================================================== */
CREATE OR ALTER VIEW dbo.vw_order_item_totals AS
SELECT
    oi.order_id,
    COUNT(*)                         AS item_count,
    COUNT(DISTINCT oi.product_id)    AS distinct_products,
    COUNT(DISTINCT oi.seller_id)     AS distinct_sellers,
    SUM(oi.price)                    AS merchandise_value_brl,
    SUM(oi.freight_value)            AS freight_value_brl,
    SUM(oi.price + oi.freight_value) AS total_billed_brl
FROM dbo.order_items oi
GROUP BY oi.order_id;
GO

/* =====================================================================
   8. Post-View Grain Verification
   Purpose: Confirm zero duplicate order_ids exist in both analytical views.
   ===================================================================== */
SELECT
    (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM dbo.vw_one_review_per_order) AS duplicate_orders_in_review_view,
    (SELECT COUNT(*) - COUNT(DISTINCT order_id) FROM dbo.vw_order_item_totals)    AS duplicate_orders_in_item_totals_view;
GO