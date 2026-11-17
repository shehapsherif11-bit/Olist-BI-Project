/* ============================================================================
   OLIST E-COMMERCE PROJECT
   TRACK B - PRODUCTS & CATEGORIES

   SCRIPT : 04_dashboard_exports.sql
   DATABASE: Olist_BI_TrackB
   SERVER  : Abdulmalek (default SQL Server instance)
   PURPOSE : Create the SQL-derived CSV datasets for the Excel dashboard.

   ANALYSIS WINDOW:
       Purchase date >= 2017-01-01 (inclusive)
       Purchase date <  2018-09-01 (exclusive)

   BUSINESS DEFINITIONS:
       Merchandise Sales = SUM(order_items.price) for delivered orders.
       Freight is excluded. Currency is BRL.
       AOV = Merchandise Sales / distinct delivered orders.
       Average Item Price = Merchandise Sales / item rows.
       Product units/items are counted as item rows, not SUM(order_item_id).
       Late = actual delivery calendar date > estimated delivery calendar date.
       Low rating = review score 1 or 2.
       One valid review per order: latest answer timestamp, then creation date,
       then review_id. Only valid scores 1-5 are selected.
       Category names: English translation -> original code -> Unknown/Missing.

   EXPORT WORKFLOW:
       1. Run this script in SSMS against Olist_BI_TrackB.
       2. It returns TWO result grids, in this order:
            Result 1 -> KPI_Baseline.csv
            Result 2 -> Dashboard_Master_Monthly_Category.csv
       3. Save each result grid separately:
            Right-click inside the result grid -> Save Results As...
            Save as CSV with the exact filename above.
          Ensure column headers are included in the saved result.
       4. Import both CSV files into Excel using Data -> From Text/CSV.
       5. Load both as Excel Tables. Do not connect to the personal SQL Server
          from the submitted workbook; the imported CSV data must remain
          available offline.

   DASHBOARD MAPPING:
       KPI_Baseline.csv:
           5 KPI cards - G1, B1, O2; fixed full-period baseline.
       Dashboard_Master_Monthly_Category.csv:
           Monthly Sales Trend                 - G2
           Top 10 Categories by Sales          - B1, B2
           Top-5 Product Sales Concentration   - B5
           Average Item Price by Category      - O1
           Late Delivery vs Low Rating         - B7

   DATA GRAIN / FILTER RULES:
       The master export has exactly one row per purchase month x category.
       Month and Category filters can be connected to all five chart PivotTables.
       KPI cards are deliberately fixed to the full-period baseline and must be
       labelled as such. They are not expected to change when slicers change.
       Do NOT sum distinct_orders or service_category_orders across categories:
       a single order may contain products from multiple categories.
       Recalculate average item price as SUM(monthly_sales_brl)/SUM(item_count).
       Recalculate late rate as SUM(late_orders)/SUM(valid_delivery_orders).
       Recalculate low-rating rate as SUM(low_rating_orders)/SUM(reviewed_orders).
       Do NOT average monthly percentage columns for multi-month selections.

   This script contains read-only SELECT statements; it does not modify data.
   ============================================================================ */

USE Olist_BI_TrackB;
GO
SET NOCOUNT ON;
GO

/* ============================================================================
   EXPORT 01 - KPI BASELINE
   OUTPUT FILE: KPI_Baseline.csv
   GRAIN: One row for the complete analysis period.
   QUESTION LINKS: G1, B1, O1, O2.

   KPIs:
       merchandise_sales_brl
       delivered_orders
       average_order_value_brl
       active_products
       active_categories

   These five cards are full-period baseline values (not slicer-responsive).
   ============================================================================ */

;WITH DeliveredItems AS
(
    SELECT
        o.order_id,
        c.customer_unique_id,
        oi.order_item_id,
        oi.product_id,
        oi.price,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category
    FROM dbo.orders AS o
    INNER JOIN dbo.order_items AS oi
        ON oi.order_id = o.order_id
    INNER JOIN dbo.products AS p
        ON p.product_id = oi.product_id
    LEFT JOIN dbo.customers AS c
        ON c.customer_id = o.customer_id
    LEFT JOIN dbo.category_translation AS ct
        ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
)
SELECT
    CAST(SUM(price) AS DECIMAL(18,2)) AS merchandise_sales_brl,
    COUNT(DISTINCT order_id) AS delivered_orders,
    CAST(
        SUM(price) / NULLIF(COUNT(DISTINCT order_id), 0)
        AS DECIMAL(18,2)
    ) AS average_order_value_brl,
    COUNT(DISTINCT product_id) AS active_products,
    COUNT(DISTINCT category) AS active_categories,
    COUNT(DISTINCT customer_unique_id) AS distinct_customers,
    COUNT(*) AS item_count,
    CAST(SUM(price) / NULLIF(COUNT(*), 0) AS DECIMAL(18,2))
        AS average_item_price_brl
FROM DeliveredItems;
GO

/* ============================================================================
   EXPORT 02 - DASHBOARD MASTER (MAIN EXCEL PIVOT SOURCE)
   OUTPUT FILE: Dashboard_Master_Monthly_Category.csv
   GRAIN: Exactly one row per purchase month x category.
   EXPECTED ROWS: 20 months x 74 categories = 1,480 rows.
   QUESTION LINKS: G2, B1, B2, B5, B7, O1.

   This one table supplies all five charts and both slicers. It intentionally
   keeps item-sales measures, concentration measures, and service numerators /
   denominators together only after each has been aggregated to month-category
   grain. This avoids item x review/order multiplication.
   ============================================================================ */

;WITH DeliveredItems AS
(
    SELECT
        o.order_id,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        oi.product_id,
        oi.price,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category
    FROM dbo.orders AS o
    INNER JOIN dbo.order_items AS oi
        ON oi.order_id = o.order_id
    INNER JOIN dbo.products AS p
        ON p.product_id = oi.product_id
    LEFT JOIN dbo.category_translation AS ct
        ON ct.product_category_name = p.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp <  '2018-09-01'
),
Months AS
(
    SELECT
        DATEADD(MONTH, v.month_offset, CAST('2017-01-01' AS DATE)) AS month_start
    FROM (VALUES
        (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),
        (10),(11),(12),(13),(14),(15),(16),(17),(18),(19)
    ) AS v(month_offset)
),
Categories AS
(
    SELECT DISTINCT category
    FROM DeliveredItems
),
MonthlySales AS
(
    SELECT
        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ) AS month_start,
        category,
        SUM(price) AS monthly_sales,
        COUNT(*) AS item_count,
        COUNT(DISTINCT order_id) AS distinct_orders,
        COUNT(DISTINCT product_id) AS active_products
    FROM DeliveredItems
    GROUP BY
        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ),
        category
),
CategoryMonths AS
(
    SELECT
        m.month_start,
        c.category,
        COALESCE(ms.monthly_sales, 0) AS monthly_sales,
        COALESCE(ms.item_count, 0) AS item_count,
        COALESCE(ms.distinct_orders, 0) AS distinct_orders,
        COALESCE(ms.active_products, 0) AS active_products
    FROM Months AS m
    CROSS JOIN Categories AS c
    LEFT JOIN MonthlySales AS ms
        ON ms.month_start = m.month_start
       AND ms.category = c.category
),
CategoryAnalysis AS
(
    SELECT
        month_start,
        category,
        monthly_sales,
        item_count,
        distinct_orders,
        active_products,
        RANK() OVER
        (
            PARTITION BY month_start
            ORDER BY monthly_sales DESC
        ) AS category_rank,
        LAG(monthly_sales) OVER
        (
            PARTITION BY category
            ORDER BY month_start
        ) AS previous_month_sales
    FROM CategoryMonths
),
SelectedReviews AS
(
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER
        (
            PARTITION BY order_id
            ORDER BY
                review_answer_timestamp DESC,
                review_creation_date DESC,
                review_id DESC
        ) AS review_rank
    FROM dbo.order_reviews
    WHERE review_score BETWEEN 1 AND 5
),
OrderCategory AS
(
    /* One row per delivered order-category pair before service aggregation. */
    SELECT
        order_id,
        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ) AS month_start,
        category,
        MAX(order_delivered_customer_date) AS delivered_customer_date,
        MAX(order_estimated_delivery_date) AS estimated_delivery_date
    FROM DeliveredItems
    GROUP BY
        order_id,
        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ),
        category
),
CategoryOrderService AS
(
    SELECT
        oc.order_id,
        oc.month_start,
        oc.category,
        oc.delivered_customer_date,
        oc.estimated_delivery_date,
        sr.review_score
    FROM OrderCategory AS oc
    LEFT JOIN SelectedReviews AS sr
        ON sr.order_id = oc.order_id
       AND sr.review_rank = 1
),
CategoryMonthService AS
(
    SELECT
        month_start,
        category,
        COUNT(*) AS service_category_orders,
        SUM(CASE
            WHEN delivered_customer_date IS NOT NULL
             AND estimated_delivery_date IS NOT NULL
             AND CAST(delivered_customer_date AS DATE)
                 > CAST(estimated_delivery_date AS DATE)
            THEN 1 ELSE 0
        END) AS late_orders,
        SUM(CASE
            WHEN delivered_customer_date IS NOT NULL
             AND estimated_delivery_date IS NOT NULL
            THEN 1 ELSE 0
        END) AS valid_delivery_orders,
        SUM(CASE
            WHEN delivered_customer_date IS NULL
              OR estimated_delivery_date IS NULL
            THEN 1 ELSE 0
        END) AS missing_delivery_dates,
        SUM(CASE WHEN review_score IS NOT NULL THEN 1 ELSE 0 END)
            AS reviewed_orders,
        SUM(CASE WHEN review_score IN (1,2) THEN 1 ELSE 0 END)
            AS low_rating_orders
    FROM CategoryOrderService
    GROUP BY month_start, category
),
ProductMonthSales AS
(
    SELECT
        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ) AS month_start,
        category,
        product_id,
        SUM(price) AS product_sales
    FROM DeliveredItems
    GROUP BY
        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ),
        category,
        product_id
),
RankedProducts AS
(
    SELECT
        month_start,
        category,
        product_id,
        product_sales,
        ROW_NUMBER() OVER
        (
            PARTITION BY month_start, category
            ORDER BY product_sales DESC, product_id
        ) AS product_rank
    FROM ProductMonthSales
),
CategoryMonthConcentration AS
(
    SELECT
        month_start,
        category,
        COUNT(*) AS concentration_product_count,
        SUM(product_sales) AS concentration_total_sales,
        SUM(CASE WHEN product_rank <= 5 THEN product_sales ELSE 0 END)
            AS top5_products_sales
    FROM RankedProducts
    GROUP BY month_start, category
)
SELECT
    ca.month_start AS purchase_month_start,
    YEAR(ca.month_start) AS sales_year,
    MONTH(ca.month_start) AS sales_month_number,
    DATENAME(MONTH, ca.month_start) AS sales_month_name,
    ca.category,

    CAST(ca.monthly_sales AS DECIMAL(18,2)) AS monthly_sales_brl,
    ca.item_count,
    ca.distinct_orders,
    ca.active_products,
    CAST(ca.monthly_sales / NULLIF(ca.item_count, 0) AS DECIMAL(18,2))
        AS average_item_price_brl,
    ca.category_rank,
    CAST(ca.previous_month_sales AS DECIMAL(18,2))
        AS previous_month_sales_brl,
    CASE
        WHEN ca.previous_month_sales IS NULL OR ca.previous_month_sales = 0
            THEN NULL
        ELSE CAST(
            100.0 * (ca.monthly_sales - ca.previous_month_sales)
                / ca.previous_month_sales
            AS DECIMAL(10,2)
        )
    END AS sales_growth_percentage,

    COALESCE(cmc.concentration_product_count, 0)
        AS concentration_product_count,
    CAST(COALESCE(cmc.concentration_total_sales, 0) AS DECIMAL(18,2))
        AS concentration_total_sales_brl,
    CAST(COALESCE(cmc.top5_products_sales, 0) AS DECIMAL(18,2))
        AS top5_products_sales_brl,
    CAST(
        100.0 * cmc.top5_products_sales
            / NULLIF(cmc.concentration_total_sales, 0)
        AS DECIMAL(8,2)
    ) AS top5_products_share_percentage,

    COALESCE(cms.service_category_orders, 0) AS service_category_orders,
    COALESCE(cms.late_orders, 0) AS late_orders,
    COALESCE(cms.valid_delivery_orders, 0) AS valid_delivery_orders,
    CAST(
        100.0 * cms.late_orders / NULLIF(cms.valid_delivery_orders, 0)
        AS DECIMAL(8,2)
    ) AS late_delivery_rate_percentage,
    COALESCE(cms.missing_delivery_dates, 0) AS missing_delivery_dates,
    COALESCE(cms.reviewed_orders, 0) AS reviewed_orders,
    COALESCE(cms.low_rating_orders, 0) AS low_rating_orders,
    CAST(
        100.0 * cms.low_rating_orders / NULLIF(cms.reviewed_orders, 0)
        AS DECIMAL(8,2)
    ) AS low_rating_rate_percentage,
    CASE
        WHEN COALESCE(cms.valid_delivery_orders, 0) >= 30
            THEN 'Sufficient Sample'
        ELSE 'Exploratory'
    END AS delivery_sample_status,
    CASE
        WHEN COALESCE(cms.reviewed_orders, 0) >= 30
            THEN 'Sufficient Sample'
        ELSE 'Exploratory'
    END AS review_sample_status
FROM CategoryAnalysis AS ca
LEFT JOIN CategoryMonthService AS cms
    ON cms.month_start = ca.month_start
   AND cms.category = ca.category
LEFT JOIN CategoryMonthConcentration AS cmc
    ON cmc.month_start = ca.month_start
   AND cmc.category = ca.category
ORDER BY
    ca.month_start,
    ca.category_rank,
    ca.category;
GO

/* ============================================================================
   END OF SCRIPT

   EXPECTED MAIN EXPORTS:
       KPI_Baseline.csv                         -> 1 row
       Dashboard_Master_Monthly_Category.csv   -> 1,480 rows

   BEFORE BUILDING PIVOTS:
       - Confirm KPI baseline against the G1/B1/O2 query outputs.
       - Confirm SUM(monthly_sales_brl) = 13,181,027.13 BRL.
       - Confirm month-category row count = 1,480.
       - Do not add distinct order counts across categories.
   ============================================================================ */
