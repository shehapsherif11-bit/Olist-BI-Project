USE Olist_BI_Project;
GO

/* =================================================================================
   01_schema.sql
   Database Schema Documentation & Constraints Setup
================================================================================= 
   IMPORT DOCUMENTATION (As required by project rubric):
   ----------------------------------------------------
   All 8 tables were imported using the SSMS "Import Flat File" wizard.
   Wizard Settings Used:
   - Source Files: Original CSVs from Olist dataset.
   - Text Encoding: UTF-8 (to safely handle commas and newlines in text).
   - Data Types configured during import:
     * VARCHAR(50) for all entity IDs (customer_id, order_id, product_id, etc.)
     * DATETIME2 for all timestamp columns.
     * DECIMAL(18,2) for price, freight_value, and payment_value.
     * INT for counts, scores, and sequences.
================================================================================= */

-- =================================================================================
-- PART 1: ADDING PRIMARY KEYS
-- =================================================================================

ALTER TABLE dbo.customers 
ADD CONSTRAINT PK_customers PRIMARY KEY (customer_id);
GO

ALTER TABLE dbo.orders 
ADD CONSTRAINT PK_orders PRIMARY KEY (order_id);
GO

ALTER TABLE dbo.products 
ADD CONSTRAINT PK_products PRIMARY KEY (product_id);
GO

ALTER TABLE dbo.sellers 
ADD CONSTRAINT PK_sellers PRIMARY KEY (seller_id);
GO

ALTER TABLE dbo.category_translation 
ADD CONSTRAINT PK_category_translation PRIMARY KEY (product_category_name);
GO

-- Composite Primary Keys
ALTER TABLE dbo.order_items 
ADD CONSTRAINT PK_order_items PRIMARY KEY (order_id, order_item_id);
GO

ALTER TABLE dbo.order_payments 
ADD CONSTRAINT PK_order_payments PRIMARY KEY (order_id, payment_sequential);
GO

-- Review ID is treated as the primary key for the reviews table
ALTER TABLE dbo.order_reviews 
ADD CONSTRAINT PK_order_reviews PRIMARY KEY (review_id);
GO


-- =================================================================================
-- PART 2: ADDING FOREIGN KEYS (WITH NOCHECK)
-- Note: WITH NOCHECK is used to enforce relationships for the ER Diagram 
-- while maintaining the original raw data state (allowing orphaned records).
-- =================================================================================

ALTER TABLE dbo.orders WITH NOCHECK 
ADD CONSTRAINT FK_orders_customers 
FOREIGN KEY (customer_id) REFERENCES dbo.customers(customer_id);
GO

ALTER TABLE dbo.order_items WITH NOCHECK 
ADD CONSTRAINT FK_order_items_orders 
FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id);
GO

ALTER TABLE dbo.order_items WITH NOCHECK 
ADD CONSTRAINT FK_order_items_products 
FOREIGN KEY (product_id) REFERENCES dbo.products(product_id);
GO

ALTER TABLE dbo.order_items WITH NOCHECK 
ADD CONSTRAINT FK_order_items_sellers 
FOREIGN KEY (seller_id) REFERENCES dbo.sellers(seller_id);
GO

ALTER TABLE dbo.order_payments WITH NOCHECK 
ADD CONSTRAINT FK_order_payments_orders 
FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id);
GO

ALTER TABLE dbo.order_reviews WITH NOCHECK 
ADD CONSTRAINT FK_order_reviews_orders 
FOREIGN KEY (order_id) REFERENCES dbo.orders(order_id);
GO

ALTER TABLE dbo.products WITH NOCHECK 
ADD CONSTRAINT FK_products_category 
FOREIGN KEY (product_category_name) REFERENCES dbo.category_translation(product_category_name);
GO