-- G1

USE Olist_BI_TrackB;
GO

-- G1: Order Status Analysis

SELECT
    o.order_status,
    COUNT(*) AS order_count,

    CAST(
        100.0 * COUNT(*) /
        NULLIF(
            (
                SELECT COUNT(*)
                FROM dbo.orders
                WHERE order_purchase_timestamp >= '2017-01-01'
                  AND order_purchase_timestamp < '2018-09-01'
            ), 0
        )
        AS DECIMAL(6,2)
    ) AS order_percentage

FROM dbo.orders o

WHERE o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp < '2018-09-01'

GROUP BY o.order_status

ORDER BY order_count DESC;


-- G1: Delivered Orders Summary

SELECT

    COUNT(DISTINCT o.order_id) AS delivered_orders,

    COUNT(DISTINCT c.customer_unique_id)
        AS distinct_customers,

    CAST(
        SUM(oi.price)
        AS DECIMAL(18,2)
    ) AS merchandise_sales_brl,

    CAST(
        SUM(oi.price) /
        NULLIF(COUNT(DISTINCT o.order_id), 0)
        AS DECIMAL(18,2)
    ) AS average_order_value_brl

FROM dbo.orders o

LEFT JOIN dbo.customers c
    ON o.customer_id = c.customer_id

LEFT JOIN dbo.order_items oi
    ON o.order_id = oi.order_id

WHERE o.order_status = 'delivered'

  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp < '2018-09-01';


  -- G2

  
USE Olist_BI_TrackB;
GO

-- G2: Monthly Sales Analysis

;WITH MonthlySales AS
(
    SELECT
        m.month_start,

        COUNT(DISTINCT o.order_id) AS delivered_orders,

        COALESCE(SUM(oi.price), 0) AS merchandise_sales

    FROM (VALUES
        (CAST('2017-01-01' AS DATE)),
        ('2017-02-01'),
        ('2017-03-01'),
        ('2017-04-01'),
        ('2017-05-01'),
        ('2017-06-01'),
        ('2017-07-01'),
        ('2017-08-01'),
        ('2017-09-01'),
        ('2017-10-01'),
        ('2017-11-01'),
        ('2017-12-01'),
        ('2018-01-01'),
        ('2018-02-01'),
        ('2018-03-01'),
        ('2018-04-01'),
        ('2018-05-01'),
        ('2018-06-01'),
        ('2018-07-01'),
        ('2018-08-01')
    ) AS m(month_start)

    LEFT JOIN dbo.orders o
        ON o.order_purchase_timestamp >= m.month_start
        AND o.order_purchase_timestamp < DATEADD(MONTH, 1, m.month_start)
        AND o.order_status = 'delivered'

    LEFT JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    GROUP BY m.month_start
),

MonthlyAnalysis AS
(
    SELECT
        month_start,
        delivered_orders,
        merchandise_sales,

        LAG(merchandise_sales) OVER
        (
            ORDER BY month_start
        ) AS previous_month_sales,

        SUM(merchandise_sales) OVER
        (
            ORDER BY month_start
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS running_sales_total

    FROM MonthlySales
)

SELECT
    month_start,
    delivered_orders,
    merchandise_sales,

    CAST(
        merchandise_sales / NULLIF(delivered_orders, 0)
        AS DECIMAL(18,2)
    ) AS average_order_value,

    CASE
        WHEN previous_month_sales IS NULL
          OR previous_month_sales = 0
        THEN NULL

        ELSE CAST(
            100.0 * (merchandise_sales - previous_month_sales)
            / previous_month_sales
            AS DECIMAL(10,2)
        )
    END AS sales_growth_percentage,

    CAST(running_sales_total AS DECIMAL(18,2))
        AS running_sales_total

FROM MonthlyAnalysis
ORDER BY month_start;


-- G3


-- G3: Monthly Review and Payment Coverage

;WITH DeliveredOrders AS
(
    SELECT
        order_id,

        DATEFROMPARTS(
            YEAR(order_purchase_timestamp),
            MONTH(order_purchase_timestamp),
            1
        ) AS purchase_month

    FROM dbo.orders

    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
),

OrderCoverage AS
(
    SELECT
        d.order_id,
        d.purchase_month,

        CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.order_reviews r
                WHERE r.order_id = d.order_id
                  AND r.review_score BETWEEN 1 AND 5
            )
            THEN 1 ELSE 0
        END AS has_review,

        CASE
            WHEN NOT EXISTS
            (
                SELECT 1
                FROM dbo.order_reviews r
                WHERE r.order_id = d.order_id
                  AND r.review_score BETWEEN 1 AND 5
            )
            THEN 1 ELSE 0
        END AS no_review,

        CASE
            WHEN p.order_id IS NOT NULL
            THEN 1 ELSE 0
        END AS has_payment,

        CASE
            WHEN p.order_id IS NULL
            THEN 1 ELSE 0
        END AS no_payment

    FROM DeliveredOrders d

    LEFT JOIN
    (
        SELECT order_id
        FROM dbo.order_payments
        GROUP BY order_id
    ) p
        ON d.order_id = p.order_id
)

SELECT
    CONVERT(CHAR(7), purchase_month, 120) AS purchase_month,

    COUNT(*) AS delivered_orders,

    SUM(has_review) AS orders_with_review,

    CAST(
        100.0 * SUM(has_review) / COUNT(*)
        AS DECIMAL(6,2)
    ) AS review_coverage_percentage,

    SUM(no_review) AS orders_without_review,

    CAST(
        100.0 * SUM(no_review) / COUNT(*)
        AS DECIMAL(6,2)
    ) AS missing_review_percentage,

    SUM(has_payment) AS orders_with_payment,

    CAST(
        100.0 * SUM(has_payment) / COUNT(*)
        AS DECIMAL(6,2)
    ) AS payment_coverage_percentage,

    SUM(no_payment) AS orders_without_payment,

    CAST(
        100.0 * SUM(no_payment) / COUNT(*)
        AS DECIMAL(6,2)
    ) AS missing_payment_percentage

FROM OrderCoverage

GROUP BY purchase_month

ORDER BY purchase_month;



-- G3: Sample of Missing Reviews and Payments

;WITH DeliveredOrders AS
(
    SELECT
        order_id,
        order_purchase_timestamp
    FROM dbo.orders
    WHERE order_status = 'delivered'
      AND order_purchase_timestamp >= '2017-01-01'
      AND order_purchase_timestamp < '2018-09-01'
)

SELECT TOP 20

    d.order_id,

    CONVERT(CHAR(7), d.order_purchase_timestamp, 120)
        AS purchase_month,

    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM dbo.order_reviews r
            WHERE r.order_id = d.order_id
              AND r.review_score BETWEEN 1 AND 5
        )
        THEN 'Has Valid Review'
        ELSE 'Missing Valid Review'
    END AS review_status,

    CASE
        WHEN p.order_id IS NOT NULL
        THEN 'Has Payment'
        ELSE 'Missing Payment'
    END AS payment_status

FROM DeliveredOrders d

LEFT JOIN
(
    SELECT order_id
    FROM dbo.order_payments
    GROUP BY order_id
) p
    ON d.order_id = p.order_id

WHERE
    NOT EXISTS
    (
        SELECT 1
        FROM dbo.order_reviews r
        WHERE r.order_id = d.order_id
          AND r.review_score BETWEEN 1 AND 5
    )
    OR p.order_id IS NULL

ORDER BY
    d.order_purchase_timestamp,
    d.order_id;



-- B1

-- B1: Category Sales Performance

SELECT

    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    ) AS category,

    CAST(SUM(oi.price) AS DECIMAL(18,2))
        AS category_sales,

    CAST(
        100.0 * SUM(oi.price) /
        NULLIF(SUM(SUM(oi.price)) OVER (), 0)
        AS DECIMAL(8,2)
    ) AS sales_share_percentage,

    RANK() OVER
    (
        ORDER BY SUM(oi.price) DESC
    ) AS category_rank,

    COUNT(*) AS item_count,

    COUNT(DISTINCT oi.order_id) AS distinct_orders

FROM dbo.orders o

INNER JOIN dbo.order_items oi
    ON o.order_id = oi.order_id

INNER JOIN dbo.products p
    ON oi.product_id = p.product_id

LEFT JOIN dbo.category_translation ct
    ON p.product_category_name = ct.product_category_name

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp < '2018-09-01'

GROUP BY
    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    )

ORDER BY
    category_rank,
    category;


--B2


-- B2: Monthly Category Sales and Rankings

;WITH Months AS
(
    SELECT
        DATEADD(MONTH, v.month_number, CAST('2017-01-01' AS DATE))
            AS month_start
    FROM (VALUES
        (0), (1), (2), (3), (4), (5),
        (6), (7), (8), (9), (10), (11),
        (12), (13), (14), (15), (16), (17),
        (18), (19)
    ) v(month_number)
),

Categories AS
(
    SELECT DISTINCT
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    INNER JOIN dbo.products p
        ON oi.product_id = p.product_id

    LEFT JOIN dbo.category_translation ct
        ON p.product_category_name = ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
),

MonthlySales AS
(
    SELECT
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category,

        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        ) AS month_start,

        SUM(oi.price) AS monthly_sales

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    INNER JOIN dbo.products p
        ON oi.product_id = p.product_id

    LEFT JOIN dbo.category_translation ct
        ON p.product_category_name = ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ),
        DATEFROMPARTS(
            YEAR(o.order_purchase_timestamp),
            MONTH(o.order_purchase_timestamp),
            1
        )
),

CategoryMonths AS
(
    SELECT
        c.category,
        m.month_start,
        COALESCE(ms.monthly_sales, 0) AS monthly_sales

    FROM Categories c

    CROSS JOIN Months m

    LEFT JOIN MonthlySales ms
        ON c.category = ms.category
        AND m.month_start = ms.month_start
),

CategoryAnalysis AS
(
    SELECT
        category,
        month_start,
        monthly_sales,

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
)

SELECT
    CONVERT(CHAR(7), month_start, 120) AS purchase_month,

    category,

    CAST(monthly_sales AS DECIMAL(18,2))
        AS monthly_sales,

    category_rank,

    CASE
        WHEN previous_month_sales IS NULL
          OR previous_month_sales = 0
        THEN NULL

        ELSE CAST(
            100.0 * (monthly_sales - previous_month_sales)
            / previous_month_sales
            AS DECIMAL(10,2)
        )
    END AS sales_growth_percentage

FROM CategoryAnalysis

ORDER BY
    month_start,
    category_rank,
    category;


--B3

-- B3: Products Above Category Average

;WITH ProductSales AS
(
    -- Calculate total sales for each product

    SELECT
        p.product_id,

        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category,

        SUM(oi.price) AS total_sales

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    INNER JOIN dbo.products p
        ON oi.product_id = p.product_id

    LEFT JOIN dbo.category_translation ct
        ON p.product_category_name = ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        p.product_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        )
),

ProductComparison AS
(
    -- Compare each product with its category average

    SELECT
        ps.product_id,
        ps.category,
        ps.total_sales,

        (
            SELECT AVG(ps2.total_sales)
            FROM ProductSales ps2
            WHERE ps2.category = ps.category
        ) AS category_product_average

    FROM ProductSales ps
)

SELECT
    product_id,
    category,

    CAST(total_sales AS DECIMAL(18,2))
        AS total_sales,

    CAST(category_product_average AS DECIMAL(18,2))
        AS category_product_average,

    CAST(
        total_sales - category_product_average
        AS DECIMAL(18,2)
    ) AS difference

FROM ProductComparison

WHERE total_sales > category_product_average

ORDER BY difference DESC;


-- B4


USE Olist_BI_TrackB;
GO

-- B4: Sellers Selling Leading Categories

;WITH SellerSales AS
(
    -- Total sales for each seller

    SELECT
        oi.seller_id,
        SUM(oi.price) AS total_sales

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY oi.seller_id
),

SelectedCategorySales AS
(
    -- Sales of each seller in the top 5 categories

    SELECT
        oi.seller_id,
        SUM(oi.price) AS selected_categories_sales

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    INNER JOIN dbo.products p
        ON oi.product_id = p.product_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

      AND p.product_category_name IN
      (
          SELECT TOP 5
              p2.product_category_name

          FROM dbo.orders o2

          INNER JOIN dbo.order_items oi2
              ON o2.order_id = oi2.order_id

          INNER JOIN dbo.products p2
              ON oi2.product_id = p2.product_id

          WHERE o2.order_status = 'delivered'
            AND o2.order_purchase_timestamp >= '2017-01-01'
            AND o2.order_purchase_timestamp < '2018-09-01'

          GROUP BY p2.product_category_name

          ORDER BY SUM(oi2.price) DESC
      )

    GROUP BY oi.seller_id
)

SELECT
    s.seller_id,

    CAST(s.total_sales AS DECIMAL(18,2))
        AS total_sales,

    CAST(sc.selected_categories_sales AS DECIMAL(18,2))
        AS selected_categories_sales,

    CAST(
        100.0 * sc.selected_categories_sales /
        NULLIF(s.total_sales, 0)
        AS DECIMAL(8,2)
    ) AS selected_categories_share

FROM SellerSales s

INNER JOIN SelectedCategorySales sc
    ON s.seller_id = sc.seller_id

ORDER BY selected_categories_sales DESC;


--B5


USE Olist_BI_TrackB;
GO

-- B5: Top 5 Products Sales Concentration

;WITH ProductSales AS
(
    -- Calculate total sales for each product

    SELECT
        p.product_id,

        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category,

        SUM(oi.price) AS product_sales

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    INNER JOIN dbo.products p
        ON oi.product_id = p.product_id

    LEFT JOIN dbo.category_translation ct
        ON p.product_category_name = ct.product_category_name

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        p.product_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        )
),

RankedProducts AS
(
    -- Rank products within each category

    SELECT
        product_id,
        category,
        product_sales,

        ROW_NUMBER() OVER
        (
            PARTITION BY category
            ORDER BY product_sales DESC, product_id
        ) AS product_rank

    FROM ProductSales
)

SELECT
    category,

    COUNT(*) AS product_count,

    CAST(
        SUM(product_sales)
        AS DECIMAL(18,2)
    ) AS total_sales,

    CAST(
        SUM(
            CASE
                WHEN product_rank <= 5
                THEN product_sales
                ELSE 0
            END
        )
        AS DECIMAL(18,2)
    ) AS top5_products_sales,

    CAST(
        100.0 * SUM(
            CASE
                WHEN product_rank <= 5
                THEN product_sales
                ELSE 0
            END
        ) / NULLIF(SUM(product_sales), 0)
        AS DECIMAL(8,2)
    ) AS top5_products_share_percentage,

    CASE
        WHEN COUNT(*) < 5
        THEN 'Fewer than 5 products'
        ELSE '5 or more products'
    END AS product_count_status

FROM RankedProducts

GROUP BY category

ORDER BY
    top5_products_share_percentage DESC,
    category;


--B6


USE Olist_BI_TrackB;
GO

-- B6: Compare Product Sales Between Two Periods

;WITH Sales2017 AS
(
    -- Product sales from January to June 2017

    SELECT
        oi.product_id,
        SUM(oi.price) AS sales_2017

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2017-07-01'

    GROUP BY oi.product_id
),

Sales2018 AS
(
    -- Product sales from January to June 2018

    SELECT
        oi.product_id,
        SUM(oi.price) AS sales_2018

    FROM dbo.orders o

    INNER JOIN dbo.order_items oi
        ON o.order_id = oi.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2018-01-01'
      AND o.order_purchase_timestamp < '2018-07-01'

    GROUP BY oi.product_id
)

SELECT
    COALESCE(s17.product_id, s18.product_id) AS product_id,

    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    ) AS category,

    CAST(
        COALESCE(s17.sales_2017, 0)
        AS DECIMAL(18,2)
    ) AS sales_2017,

    CAST(
        COALESCE(s18.sales_2018, 0)
        AS DECIMAL(18,2)
    ) AS sales_2018,

    CASE
        WHEN s17.product_id IS NOT NULL
         AND s18.product_id IS NOT NULL
            THEN 'Sold in both periods'

        WHEN s17.product_id IS NOT NULL
            THEN 'Only Jan-Jun 2017'

        ELSE 'Only Jan-Jun 2018'
    END AS activity_group

FROM Sales2017 s17

FULL OUTER JOIN Sales2018 s18
    ON s17.product_id = s18.product_id

INNER JOIN dbo.products p
    ON p.product_id = COALESCE(s17.product_id, s18.product_id)

LEFT JOIN dbo.category_translation ct
    ON p.product_category_name = ct.product_category_name

ORDER BY
    activity_group,
    product_id;


--B7


;WITH SelectedReviews AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (
            PARTITION BY order_id
            ORDER BY
                review_answer_timestamp DESC,
                review_creation_date DESC,
                review_id DESC
        ) AS review_rank
    FROM order_reviews
    WHERE review_score BETWEEN 1 AND 5
),

CategoryOrders AS (
    SELECT
        o.order_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ) AS category,

        SUM(oi.price) AS order_category_sales,

        CASE
            WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_estimated_delivery_date IS NOT NULL
            THEN 1
            ELSE 0
        END AS valid_delivery_dates,

        CASE
            WHEN CAST(o.order_delivered_customer_date AS DATE)
               > CAST(o.order_estimated_delivery_date AS DATE)
            THEN 1
            ELSE 0
        END AS is_late,

        r.review_score

    FROM orders o
    JOIN order_items oi
        ON o.order_id = oi.order_id
    JOIN products p
        ON oi.product_id = p.product_id
    LEFT JOIN category_translation ct
        ON p.product_category_name = ct.product_category_name
    LEFT JOIN SelectedReviews r
        ON o.order_id = r.order_id
       AND r.review_rank = 1

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY
        o.order_id,
        COALESCE(
            ct.product_category_name_english,
            p.product_category_name,
            'Unknown / Missing Category'
        ),
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        r.review_score
),

CategorySummary AS (
    SELECT
        category,

        COUNT(*) AS delivered_orders,

        SUM(order_category_sales) AS total_sales,

        SUM(is_late) AS late_orders,

        SUM(valid_delivery_dates) AS valid_delivery_orders,

        SUM(CASE
                WHEN valid_delivery_dates = 0 THEN 1
                ELSE 0
            END) AS missing_delivery_dates,

        SUM(CASE
                WHEN review_score IS NOT NULL THEN 1
                ELSE 0
            END) AS reviewed_orders,

        SUM(CASE
                WHEN review_score IN (1, 2) THEN 1
                ELSE 0
            END) AS low_rating_orders

    FROM CategoryOrders
    GROUP BY category
)

SELECT
    category,

    RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,

    CAST(total_sales AS DECIMAL(18,2)) AS total_sales,

    delivered_orders,

    late_orders,
    valid_delivery_orders,

    CAST(
        100.0 * late_orders /
        NULLIF(valid_delivery_orders, 0)
        AS DECIMAL(8,2)
    ) AS late_delivery_rate,

    missing_delivery_dates,

    reviewed_orders,
    low_rating_orders,

    CAST(
        100.0 * low_rating_orders /
        NULLIF(reviewed_orders, 0)
        AS DECIMAL(8,2)
    ) AS low_rating_rate,

    CASE
        WHEN valid_delivery_orders >= 30 THEN 'Sufficient Sample'
        ELSE 'Exploratory'
    END AS delivery_sample_status,

    CASE
        WHEN reviewed_orders >= 30 THEN 'Sufficient Sample'
        ELSE 'Exploratory'
    END AS review_sample_status

FROM CategorySummary
ORDER BY total_sales DESC;






-- O1 – Average Selling Price per Item


USE Olist_BI_TrackB;
GO

SELECT
    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    ) AS category,

    COUNT(*) AS item_count,

    SUM(oi.price) AS total_sales,

    AVG(oi.price) AS average_item_price

FROM orders o

JOIN order_items oi
    ON o.order_id = oi.order_id

JOIN products p
    ON oi.product_id = p.product_id

LEFT JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name

WHERE o.order_status = 'delivered'
  AND o.order_purchase_timestamp >= '2017-01-01'
  AND o.order_purchase_timestamp < '2018-09-01'

GROUP BY
    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    )

ORDER BY average_item_price DESC;



-- O2 – Products with No Sales


USE Olist_BI_TrackB;
GO

WITH ProductSales AS
(
    SELECT
        oi.product_id,
        SUM(oi.price) AS total_sales

    FROM orders o

    JOIN order_items oi
        ON o.order_id = oi.order_id

    WHERE o.order_status = 'delivered'
      AND o.order_purchase_timestamp >= '2017-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'

    GROUP BY oi.product_id
)

SELECT
    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    ) AS category,

    COUNT(*) AS total_products,

    SUM(
        CASE
            WHEN ps.product_id IS NOT NULL THEN 1
            ELSE 0
        END
    ) AS products_with_sales,

    SUM(
        CASE
            WHEN ps.product_id IS NULL THEN 1
            ELSE 0
        END
    ) AS products_without_sales

FROM products p

LEFT JOIN ProductSales ps
    ON p.product_id = ps.product_id

LEFT JOIN category_translation ct
    ON p.product_category_name = ct.product_category_name

GROUP BY
    COALESCE(
        ct.product_category_name_english,
        p.product_category_name,
        'Unknown / Missing Category'
    )

ORDER BY products_without_sales DESC;
