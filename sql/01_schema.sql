USE Olist_BI_TrackB;
GO

/* Safety check: prevent accidental duplicate creation */
IF OBJECT_ID('dbo.customers', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.orders', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.order_items', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.products', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.sellers', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.order_payments', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.order_reviews', 'U') IS NOT NULL
   OR OBJECT_ID('dbo.category_translation', 'U') IS NOT NULL
BEGIN
    THROW 50001, 'One or more final tables already exist. Stop and inspect before rerunning.', 1;
END;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* 1. Customers */
    CREATE TABLE dbo.customers
    (
        customer_id NVARCHAR(32) NOT NULL,
        customer_unique_id NVARCHAR(32) NOT NULL,
        customer_zip_code_prefix NVARCHAR(10) NULL,
        customer_city NVARCHAR(100) NULL,
        customer_state NVARCHAR(2) NULL,

        CONSTRAINT PK_customers PRIMARY KEY (customer_id)
    );

    /* 2. Orders */
    CREATE TABLE dbo.orders
    (
        order_id NVARCHAR(32) NOT NULL,
        customer_id NVARCHAR(32) NOT NULL,
        order_status NVARCHAR(20) NULL,
        order_purchase_timestamp DATETIME2(7) NULL,
        order_approved_at DATETIME2(7) NULL,
        order_delivered_carrier_date DATETIME2(7) NULL,
        order_delivered_customer_date DATETIME2(7) NULL,
        order_estimated_delivery_date DATETIME2(7) NULL,

        CONSTRAINT PK_orders PRIMARY KEY (order_id),
        CONSTRAINT FK_orders_customers
            FOREIGN KEY (customer_id)
            REFERENCES dbo.customers(customer_id)
    );

    /* 3. Products */
    CREATE TABLE dbo.products
    (
        product_id NVARCHAR(32) NOT NULL,
        product_category_name NVARCHAR(100) NULL,
        product_name_lenght INT NULL,
        product_description_lenght INT NULL,
        product_photos_qty INT NULL,
        product_weight_g INT NULL,
        product_length_cm INT NULL,
        product_height_cm INT NULL,
        product_width_cm INT NULL,

        CONSTRAINT PK_products PRIMARY KEY (product_id)
    );

    /* 4. Sellers */
    CREATE TABLE dbo.sellers
    (
        seller_id NVARCHAR(32) NOT NULL,
        seller_zip_code_prefix NVARCHAR(10) NULL,
        seller_city NVARCHAR(100) NULL,
        seller_state NVARCHAR(2) NULL,

        CONSTRAINT PK_sellers PRIMARY KEY (seller_id)
    );

    /* 5. Category Translation */
    CREATE TABLE dbo.category_translation
    (
        product_category_name NVARCHAR(100) NOT NULL,
        product_category_name_english NVARCHAR(100) NULL,

        CONSTRAINT PK_category_translation
            PRIMARY KEY (product_category_name)
    );

    /* 6. Order Items */
    CREATE TABLE dbo.order_items
    (
        order_id NVARCHAR(32) NOT NULL,
        order_item_id INT NOT NULL,
        product_id NVARCHAR(32) NOT NULL,
        seller_id NVARCHAR(32) NOT NULL,
        shipping_limit_date DATETIME2(7) NULL,
        price DECIMAL(18,2) NULL,
        freight_value DECIMAL(18,2) NULL,

        CONSTRAINT PK_order_items
            PRIMARY KEY (order_id, order_item_id),

        CONSTRAINT FK_order_items_orders
            FOREIGN KEY (order_id)
            REFERENCES dbo.orders(order_id),

        CONSTRAINT FK_order_items_products
            FOREIGN KEY (product_id)
            REFERENCES dbo.products(product_id),

        CONSTRAINT FK_order_items_sellers
            FOREIGN KEY (seller_id)
            REFERENCES dbo.sellers(seller_id)
    );

    /* 7. Order Payments */
    CREATE TABLE dbo.order_payments
    (
        order_id NVARCHAR(32) NOT NULL,
        payment_sequential INT NOT NULL,
        payment_type NVARCHAR(30) NULL,
        payment_installments INT NULL,
        payment_value DECIMAL(18,2) NULL,

        CONSTRAINT PK_order_payments
            PRIMARY KEY (order_id, payment_sequential),

        CONSTRAINT FK_order_payments_orders
            FOREIGN KEY (order_id)
            REFERENCES dbo.orders(order_id)
    );

    /* 8. Order Reviews */
    CREATE TABLE dbo.order_reviews
    (
        review_id NVARCHAR(32) NOT NULL,
        order_id NVARCHAR(32) NOT NULL,
        review_score INT NULL,
        review_comment_title NVARCHAR(MAX) NULL,
        review_comment_message NVARCHAR(MAX) NULL,
        review_creation_date DATETIME2(7) NULL,
        review_answer_timestamp DATETIME2(7) NULL,

        CONSTRAINT PK_order_reviews
            PRIMARY KEY (review_id, order_id),

        CONSTRAINT FK_order_reviews_orders
            FOREIGN KEY (order_id)
            REFERENCES dbo.orders(order_id)
    );

    /* Transfer data from staging tables */
    INSERT INTO dbo.customers
    SELECT customer_id, customer_unique_id,
           customer_zip_code_prefix, customer_city, customer_state
    FROM dbo.stg_customers;

    INSERT INTO dbo.orders
    SELECT order_id, customer_id, order_status,
           order_purchase_timestamp, order_approved_at,
           order_delivered_carrier_date,
           order_delivered_customer_date,
           order_estimated_delivery_date
    FROM dbo.stg_orders;

    INSERT INTO dbo.products
    SELECT product_id, product_category_name,
           product_name_lenght, product_description_lenght,
           product_photos_qty, product_weight_g,
           product_length_cm, product_height_cm, product_width_cm
    FROM dbo.stg_products;

    INSERT INTO dbo.sellers
    SELECT seller_id, seller_zip_code_prefix,
           seller_city, seller_state
    FROM dbo.stg_sellers;

    INSERT INTO dbo.category_translation
    SELECT product_category_name, product_category_name_english
    FROM dbo.stg_category_translation;

    INSERT INTO dbo.order_items
    SELECT order_id, order_item_id, product_id, seller_id,
           shipping_limit_date, price, freight_value
    FROM dbo.stg_order_items;

    INSERT INTO dbo.order_payments
    SELECT order_id, payment_sequential, payment_type,
           payment_installments, payment_value
    FROM dbo.stg_order_payments;

    INSERT INTO dbo.order_reviews
    SELECT review_id, order_id, review_score,
           review_comment_title, review_comment_message,
           review_creation_date, review_answer_timestamp
    FROM dbo.stg_order_reviews;

    COMMIT TRANSACTION;
    PRINT 'Final tables created and populated successfully.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO



/************/



SELECT 'customers' AS table_name,
       (SELECT COUNT(*) FROM dbo.stg_customers) AS staging_rows,
       (SELECT COUNT(*) FROM dbo.customers) AS final_rows

UNION ALL

SELECT 'orders',
       (SELECT COUNT(*) FROM dbo.stg_orders),
       (SELECT COUNT(*) FROM dbo.orders)

UNION ALL

SELECT 'order_items',
       (SELECT COUNT(*) FROM dbo.stg_order_items),
       (SELECT COUNT(*) FROM dbo.order_items)

UNION ALL

SELECT 'products',
       (SELECT COUNT(*) FROM dbo.stg_products),
       (SELECT COUNT(*) FROM dbo.products)

UNION ALL

SELECT 'sellers',
       (SELECT COUNT(*) FROM dbo.stg_sellers),
       (SELECT COUNT(*) FROM dbo.sellers)

UNION ALL

SELECT 'order_payments',
       (SELECT COUNT(*) FROM dbo.stg_order_payments),
       (SELECT COUNT(*) FROM dbo.order_payments)

UNION ALL

SELECT 'order_reviews',
       (SELECT COUNT(*) FROM dbo.stg_order_reviews),
       (SELECT COUNT(*) FROM dbo.order_reviews)

UNION ALL

SELECT 'category_translation',
       (SELECT COUNT(*) FROM dbo.stg_category_translation),
       (SELECT COUNT(*) FROM dbo.category_translation);


/***************/


SELECT
    fk.name AS foreign_key_name,
    OBJECT_NAME(fk.parent_object_id) AS child_table,
    OBJECT_NAME(fk.referenced_object_id) AS parent_table,
    fk.is_disabled
FROM sys.foreign_keys fk
ORDER BY child_table;







ALTER TABLE dbo.products
WITH NOCHECK
ADD CONSTRAINT FK_products_category_translation
FOREIGN KEY (product_category_name)
REFERENCES dbo.category_translation (product_category_name);
GO

