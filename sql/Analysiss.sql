USE Olist_BI_Project;
GO

/* =====================================================================
   Question G1 (Part 1): Order-Status Distribution
   ===================================================================== */
WITH StatusCounts AS (
    SELECT 
        order_status, 
        COUNT(DISTINCT order_id) AS order_count
    FROM dbo.orders
    WHERE order_purchase_timestamp >= '2017-01-01' AND order_purchase_timestamp < '2018-09-01'
    GROUP BY order_status
),
TotalOrders AS (
    SELECT SUM(order_count) AS total_orders FROM StatusCounts
)
SELECT 
    c.order_status,
    c.order_count,
    CAST((c.order_count * 100.0) / t.total_orders AS DECIMAL(10,2)) AS status_share_pct
FROM StatusCounts c
CROSS JOIN TotalOrders t
ORDER BY c.order_count DESC;
GO

/* =====================================================================
   Question G1 (Part 2): Delivered-Order Summary
   ===================================================================== */
SELECT
    COUNT(DISTINCT o.order_id) AS delivered_orders,
    COUNT(DISTINCT c.customer_unique_id) AS distinct_customers,
    SUM(ISNULL(oit.merchandise_value_brl, 0.00)) AS merchandise_sales_brl,
    CAST(SUM(ISNULL(oit.merchandise_value_brl, 0.00)) / NULLIF(COUNT(DISTINCT o.order_id), 0) AS DECIMAL(18, 2)) AS aov_brl
FROM dbo.orders o
INNER JOIN dbo.customers c ON o.customer_id = c.customer_id
LEFT JOIN dbo.vw_order_item_totals oit ON o.order_id = oit.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01' 
  AND o.order_purchase_timestamp < '2018-09-01' 
  AND o.order_status = 'delivered';
GO

/* =====================================================================
   Question G2: Monthly Sales Trend & Running Total
   ===================================================================== */
WITH MonthlyData AS (
    SELECT
        FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS purchase_month,
        COUNT(DISTINCT o.order_id) AS delivered_orders,
        SUM(ISNULL(oit.merchandise_value_brl, 0.00)) AS merchandise_sales_brl
    FROM dbo.orders o
    LEFT JOIN dbo.vw_order_item_totals oit ON o.order_id = oit.order_id
    WHERE o.order_purchase_timestamp >= '2017-01-01' AND o.order_purchase_timestamp < '2018-09-01' AND o.order_status = 'delivered'
    GROUP BY FORMAT(o.order_purchase_timestamp, 'yyyy-MM')
)
SELECT
    purchase_month,
    delivered_orders,
    merchandise_sales_brl,
    CAST(merchandise_sales_brl / NULLIF(delivered_orders, 0) AS DECIMAL(18, 2)) AS aov_brl,
    
    LAG(merchandise_sales_brl) OVER (ORDER BY purchase_month ASC) AS prev_month_sales,
    
    CAST((merchandise_sales_brl - LAG(merchandise_sales_brl) OVER (ORDER BY purchase_month ASC)) * 100.0 
    / NULLIF(LAG(merchandise_sales_brl) OVER (ORDER BY purchase_month ASC), 0) AS DECIMAL(10,2)) AS mom_growth_pct,
    
    SUM(merchandise_sales_brl) OVER (ORDER BY purchase_month ASC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_sales_total
FROM MonthlyData;
GO

/* =====================================================================
   Question G3 (Part 1): Monthly Review & Payment Coverage
   ===================================================================== */
WITH OrderFlags AS (
    SELECT 
        FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS purchase_month,
        o.order_id,
        CASE WHEN rev.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_review,
        CASE WHEN pay.order_id IS NOT NULL THEN 1 ELSE 0 END AS has_payment
    FROM dbo.orders o
    LEFT JOIN (SELECT DISTINCT order_id FROM dbo.order_reviews WHERE review_score BETWEEN 1 AND 5) rev ON o.order_id = rev.order_id
    LEFT JOIN (SELECT DISTINCT order_id FROM dbo.order_payments) pay ON o.order_id = pay.order_id
    WHERE o.order_purchase_timestamp >= '2017-01-01' AND o.order_purchase_timestamp < '2018-09-01' AND o.order_status = 'delivered'
)
SELECT 
    purchase_month,
    COUNT(order_id) AS delivered_orders,
    
    SUM(has_review) AS orders_with_review,
    CAST(SUM(has_review) * 100.0 / NULLIF(COUNT(order_id), 0) AS DECIMAL(10,2)) AS review_coverage_pct,
    
    SUM(has_payment) AS orders_with_payment,
    CAST(SUM(has_payment) * 100.0 / NULLIF(COUNT(order_id), 0) AS DECIMAL(10,2)) AS payment_coverage_pct
FROM OrderFlags
GROUP BY purchase_month
ORDER BY purchase_month ASC;
GO

/* =====================================================================
   Question G3 (Part 2): Sample Missing Data Orders
   ===================================================================== */
SELECT TOP (20)
    o.order_id,
    FORMAT(o.order_purchase_timestamp, 'yyyy-MM-dd') AS purchase_date,
    oit.merchandise_value_brl,
    CASE WHEN rev.order_id IS NOT NULL THEN 'Has Valid Review' ELSE 'Missing Valid Review' END AS review_status,
    CASE WHEN pay.order_id IS NOT NULL THEN 'Has Payment Record' ELSE 'Missing Payment Record' END AS payment_status
FROM dbo.orders o
LEFT JOIN dbo.vw_order_item_totals oit ON o.order_id = oit.order_id
LEFT JOIN (SELECT DISTINCT order_id FROM dbo.order_reviews WHERE review_score BETWEEN 1 AND 5) rev ON o.order_id = rev.order_id
LEFT JOIN (SELECT DISTINCT order_id FROM dbo.order_payments) pay ON o.order_id = pay.order_id
WHERE o.order_purchase_timestamp >= '2017-01-01' AND o.order_purchase_timestamp < '2018-09-01' AND o.order_status = 'delivered'
  AND (rev.order_id IS NULL OR pay.order_id IS NULL)
ORDER BY purchase_date ASC;
GO

/* =================================================================================
   Track B: Products and categories (B1 - B7) + Team Questions (O1, O2)
   Date Filter: 2017-01-01 to 2018-08-31
   Status: Delivered orders only
================================================================================= */

-- ---------------------------------------------------------------------------------
-- B1: Which categories contribute most to sales?
-- SQL Topic: Window Function (RANK) & Aggregation
-- الشرح: بنجمع المبيعات لكل قسم، وبنستخدم دالة RANK عشان نرتب الأقسام من الأعلى للأقل.
-- ---------------------------------------------------------------------------------
SELECT 
    ISNULL(ct.product_category_name_english, 'Unknown') AS category_name,
    SUM(oi.price) AS total_sales,
    COUNT(DISTINCT oi.order_id) AS distinct_orders,
    RANK() OVER(ORDER BY SUM(oi.price) DESC) AS sales_rank
FROM dbo.order_items oi
INNER JOIN dbo.orders o ON oi.order_id = o.order_id
LEFT JOIN dbo.products p ON oi.product_id = p.product_id
LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01' 
  AND o.order_purchase_timestamp < '2018-09-01'
GROUP BY ct.product_category_name_english
ORDER BY total_sales DESC;
GO

-- ---------------------------------------------------------------------------------
-- B2: How do category rankings change by month?
-- SQL Topic: CTE & Window Function (LAG)
-- الشرح: عملنا جدول وهمي (CTE) بيحسب مبيعات كل شهر. بعدين استخدمنا LAG عشان نجيب مبيعات الشهر اللي قبله ونحسب نسبة النمو.
-- ---------------------------------------------------------------------------------
WITH MonthlySales AS (
    SELECT 
        FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS month_year,
        ISNULL(ct.product_category_name_english, 'Unknown') AS category_name,
        SUM(oi.price) AS current_sales
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON oi.order_id = o.order_id
    LEFT JOIN dbo.products p ON oi.product_id = p.product_id
    LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01' 
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY FORMAT(o.order_purchase_timestamp, 'yyyy-MM'), ct.product_category_name_english
)
SELECT 
    month_year,
    category_name,
    current_sales,
    LAG(current_sales) OVER(PARTITION BY category_name ORDER BY month_year) AS previous_month_sales,
    CAST((current_sales - LAG(current_sales) OVER(PARTITION BY category_name ORDER BY month_year)) 
         / NULLIF(LAG(current_sales) OVER(PARTITION BY category_name ORDER BY month_year), 0) * 100 AS DECIMAL(10,2)) AS growth_percentage
FROM MonthlySales
ORDER BY month_year, current_sales DESC;
GO

-- ---------------------------------------------------------------------------------
-- B3: Which products sell more than their category average?
-- SQL Topic: Correlated Subquery
-- الشرح: بنقارن مبيعات كل منتج (في الكويري الأساسية) بمتوسط مبيعات القسم بتاعه (اللي بنحسبه في الكويري الفرعية).
-- ---------------------------------------------------------------------------------
WITH ProductSales AS (
    SELECT 
        p.product_id,
        ISNULL(ct.product_category_name_english, 'Unknown') AS category_name,
        SUM(oi.price) AS product_total
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON oi.order_id = o.order_id
    INNER JOIN dbo.products p ON oi.product_id = p.product_id
    LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01' 
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY p.product_id, ct.product_category_name_english
)
SELECT 
    ps.product_id,
    ps.category_name,
    ps.product_total,
    (SELECT AVG(sub.product_total) FROM ProductSales sub WHERE sub.category_name = ps.category_name) AS category_avg
FROM ProductSales ps
WHERE ps.product_total > (SELECT AVG(sub.product_total) FROM ProductSales sub WHERE sub.category_name = ps.category_name)
ORDER BY (ps.product_total - (SELECT AVG(sub.product_total) FROM ProductSales sub WHERE sub.category_name = ps.category_name)) DESC;
GO

-- ---------------------------------------------------------------------------------
-- B4: Which sellers sell the leading categories?
-- SQL Topic: Multi-row subquery (IN)
-- الشرح: بنجيب أسماء أفضل 5 أقسام في كويري فرعية، وبعدين بنقول للكويري الأساسية هات البائعين اللي بيبيعوا في الأقسام دي (باستخدام IN).
-- ---------------------------------------------------------------------------------
SELECT 
    oi.seller_id,
    SUM(oi.price) AS total_sales_in_top_categories,
    COUNT(DISTINCT oi.product_id) AS distinct_products_sold
FROM dbo.order_items oi
INNER JOIN dbo.orders o ON oi.order_id = o.order_id
INNER JOIN dbo.products p ON oi.product_id = p.product_id
INNER JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01' 
  AND o.order_purchase_timestamp < '2018-09-01'
  AND ct.product_category_name_english IN (
      -- الكويري الفرعية بتجيب أفضل 5 أقسام
      SELECT TOP 5 ct2.product_category_name_english
      FROM dbo.order_items oi2
      INNER JOIN dbo.products p2 ON oi2.product_id = p2.product_id
      INNER JOIN dbo.category_translation ct2 ON p2.product_category_name = ct2.product_category_name
      GROUP BY ct2.product_category_name_english
      ORDER BY SUM(oi2.price) DESC
  )
GROUP BY oi.seller_id
ORDER BY total_sales_in_top_categories DESC;
GO

-- ---------------------------------------------------------------------------------
-- B5: How concentrated are sales within each category?
-- SQL Topic: Window Function (ROW_NUMBER)
-- الشرح: بندي رقم لكل منتج جوه القسم بتاعه بناءً على المبيعات باستخدام ROW_NUMBER، وبنفلتر عشان ناخد أول 5 منتجات بس.
-- ---------------------------------------------------------------------------------
WITH ProductRankings AS (
    SELECT 
        ISNULL(ct.product_category_name_english, 'Unknown') AS category_name,
        p.product_id,
        SUM(oi.price) AS product_sales,
        ROW_NUMBER() OVER(PARTITION BY ct.product_category_name_english ORDER BY SUM(oi.price) DESC) AS rank_in_category
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON oi.order_id = o.order_id
    LEFT JOIN dbo.products p ON oi.product_id = p.product_id
    LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01' 
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY ct.product_category_name_english, p.product_id
)
SELECT 
    category_name,
    product_id,
    product_sales,
    rank_in_category
FROM ProductRankings
WHERE rank_in_category <= 5
ORDER BY category_name, rank_in_category;
GO

-- ---------------------------------------------------------------------------------
-- B6: Which products appear in one period but not another?
-- SQL Topic: FULL OUTER JOIN
-- الشرح: بنفصل مبيعات 2017 في جدول، ومبيعات 2018 في جدول تاني، وبنعمل دمج شامل (FULL JOIN) عشان نكتشف المنتجات اللي ظهرت في سنة واختفت في التانية.
-- ---------------------------------------------------------------------------------
WITH Sales2017 AS (
    SELECT p.product_id, SUM(oi.price) AS sales_17
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON oi.order_id = o.order_id
    INNER JOIN dbo.products p ON oi.product_id = p.product_id
    WHERE o.order_purchase_timestamp BETWEEN '2017-01-01' AND '2017-06-30'
    GROUP BY p.product_id
),
Sales2018 AS (
    SELECT p.product_id, SUM(oi.price) AS sales_18
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON oi.order_id = o.order_id
    INNER JOIN dbo.products p ON oi.product_id = p.product_id
    WHERE o.order_purchase_timestamp BETWEEN '2018-01-01' AND '2018-06-30'
    GROUP BY p.product_id
)
SELECT 
    ISNULL(s17.product_id, s18.product_id) AS product_id,
    ISNULL(s17.sales_17, 0) AS sales_first_half_2017,
    ISNULL(s18.sales_18, 0) AS sales_first_half_2018
FROM Sales2017 s17
FULL OUTER JOIN Sales2018 s18 ON s17.product_id = s18.product_id
WHERE s17.sales_17 IS NULL OR s18.sales_18 IS NULL;
GO

-- ---------------------------------------------------------------------------------
-- B7: Which high-sales categories also have service problems?
-- SQL Topic: Derived Table (Subquery in FROM)
-- الشرح: بنحسب مبيعات الأقسام وتأخير التوصيل، وبعدين بنفلتر الأقسام اللي مبيعاتها عالية بس نسبة التأخير فيها وحشة.
-- ---------------------------------------------------------------------------------
SELECT 
    category_name,
    total_sales,
    total_orders,
    late_orders,
    CAST((late_orders * 100.0 / total_orders) AS DECIMAL(5,2)) AS late_rate_percentage
FROM (
    SELECT 
        ISNULL(ct.product_category_name_english, 'Unknown') AS category_name,
        SUM(oi.price) AS total_sales,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(CASE WHEN CAST(o.order_delivered_customer_date AS DATE) > CAST(o.order_estimated_delivery_date AS DATE) THEN 1 ELSE 0 END) AS late_orders
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON oi.order_id = o.order_id
    LEFT JOIN dbo.products p ON oi.product_id = p.product_id
    LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01' 
      AND o.order_purchase_timestamp < '2018-09-01'
    GROUP BY ct.product_category_name_english
) AS CategorySummary
WHERE total_orders >= 30
ORDER BY late_rate_percentage DESC;
GO


/* =================================================================================
   Team Additional Questions (O1 & O2)
================================================================================= */

-- ---------------------------------------------------------------------------------
-- O1: Which products are generating sales but have never received any review?
-- SQL Topic: NOT EXISTS
-- الشرح: بنستعلم عن المنتجات اللي اتباعت بفلوس كتير، بس (غير موجود لها) أي تقييم في جدول التقييمات. 
-- ---------------------------------------------------------------------------------
SELECT 
    p.product_id, 
    SUM(oi.price) AS total_sales_without_reviews,
    COUNT(DISTINCT o.order_id) AS total_orders
FROM dbo.order_items oi
INNER JOIN dbo.orders o ON oi.order_id = o.order_id
INNER JOIN dbo.products p ON oi.product_id = p.product_id
WHERE o.order_status = 'delivered'
  AND NOT EXISTS (
      -- الكويري دي بتتأكد إن مفيش ولا ريفيو اتربط برقم الأوردر ده
      SELECT 1 FROM dbo.order_reviews r WHERE r.order_id = o.order_id
  )
GROUP BY p.product_id
ORDER BY total_sales_without_reviews DESC;
GO

-- ---------------------------------------------------------------------------------
-- O2: Which categories have received 5-star reviews?
-- SQL Topic: EXISTS
-- الشرح: بنجيب مبيعات الأقسام، بشرط إن (يوجد) للأوردر بتاعها تقييم 5 نجوم.
-- ---------------------------------------------------------------------------------
SELECT 
    ISNULL(ct.product_category_name_english, 'Unknown') AS category_name,
    SUM(oi.price) AS total_sales_from_5_star_orders
FROM dbo.order_items oi
INNER JOIN dbo.orders o ON oi.order_id = o.order_id
LEFT JOIN dbo.products p ON oi.product_id = p.product_id
LEFT JOIN dbo.category_translation ct ON p.product_category_name = ct.product_category_name
WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01' 
  AND o.order_purchase_timestamp < '2018-09-01'
  AND EXISTS (
      -- الكويري البسيطة دي بتتأكد إن الأوردر واخد 5 نجوم
      SELECT 1 
      FROM dbo.order_reviews r 
      WHERE r.order_id = o.order_id 
        AND r.review_score = 5
  )
GROUP BY ct.product_category_name_english
ORDER BY total_sales_from_5_star_orders DESC;
GO