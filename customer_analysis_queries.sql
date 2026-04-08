
/*******************************************************************************
Project: E-commerce Customer Behavior Analysis & RFM Segmentation
Description: Data Cleaning, Exploratory Data Analysis (EDA), 
             RFM Modeling, and Segment KPI Analysis.
*******************************************************************************/

-- 0. Initial Data Inspection
SELECT * FROM ecommerce_customer_behavior_dataset LIMIT 10;

-- 1. Check total record count
SELECT COUNT(*) AS total_records
FROM ecommerce_customer_behavior_dataset;

-- 2. Data Quality Check: Null values identification
SELECT 
    COUNT(*) AS total_records,
    COUNT(*) FILTER (WHERE order_id IS NULL) AS missing_order_id,
    COUNT(*) FILTER (WHERE customer_id IS NULL) AS missing_customer_id,
    COUNT(*) FILTER (WHERE "Date" IS NULL) AS missing_date,
    COUNT(*) FILTER (WHERE age IS NULL) AS missing_age,
    COUNT(*) FILTER (WHERE total_amount IS NULL) AS missing_amount,
    COUNT(*) FILTER (WHERE city IS NULL) AS missing_city
FROM ecommerce_customer_behavior_dataset;

-- 3. Value Range Inspection (Outlier detection)
SELECT 
    MIN(customer_rating) AS min_rating, 
    MAX(customer_rating) AS max_rating,
    MIN(age) AS min_age,
    MAX(age) AS max_age
FROM ecommerce_customer_behavior_dataset;

-- 4. Distribution Check for Categorical Fields (Data consistency check)
SELECT DISTINCT gender FROM ecommerce_customer_behavior_dataset;
SELECT DISTINCT product_category FROM ecommerce_customer_behavior_dataset;
SELECT DISTINCT payment_method FROM ecommerce_customer_behavior_dataset;
SELECT DISTINCT device_type FROM ecommerce_customer_behavior_dataset;

-- 5. Timeframe Inspection
SELECT 
    MIN("Date") AS first_transaction, 
    MAX("Date") AS last_transaction
FROM ecommerce_customer_behavior_dataset;


/*******************************************************************************
Step 1: RFM Model Construction
Description: Calculating Recency, Frequency, and Monetary metrics for each customer.
*******************************************************************************/

-- Set Reference Date: 2024-03-26 (The day after the latest transaction)
CREATE TABLE rfm_results AS
WITH rfm_base AS (
    SELECT
        customer_id,
        DATE '2024-03-26' - MAX("Date") AS recency_days,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(total_amount) AS monetary
    FROM ecommerce_customer_behavior_dataset
    GROUP BY customer_id
),
rfm_scores AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        -- Scoring metrics using quintiles (1-5)
        6 - NTILE(5) OVER(ORDER BY recency_days DESC) AS r_score, 
        NTILE(5) OVER(ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER(ORDER BY monetary ASC) AS m_score
    FROM rfm_base
),
rfm_summary AS (
    SELECT
        *,
        (r_score + f_score + m_score) AS rfm_total
    FROM rfm_scores
)
SELECT 
    *,
    CASE 
        WHEN rfm_total >= 13 THEN 'High Value'
        WHEN rfm_total BETWEEN 9 AND 12 THEN 'Medium Value'
        ELSE 'Low Value'
    END AS segment
FROM rfm_summary;


/*******************************************************************************
Step 2: Segment Behavioral Analysis
Description: Analyzing how different segments behave (Demographics & Behavior).
*******************************************************************************/

-- 1. Segment Profiling: Age, Monetary, Rating, and Gender Ratio
SELECT
    segment,
    ROUND(AVG(age), 2) AS avg_age,
    ROUND(AVG(monetary)::numeric, 2) AS avg_spending,
    ROUND(AVG(customer_rating)::numeric, 2) AS avg_rating,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gender = 'Male') / COUNT(*), 2) AS male_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE gender = 'Female') / COUNT(*), 2) AS female_pct
FROM rfm_results r
JOIN ecommerce_customer_behavior_dataset e ON r.customer_id = e.customer_id
GROUP BY segment
ORDER BY avg_spending DESC;

-- 2. Device Usage Analysis by Segment
SELECT 
    r.segment,
    ROUND(100.0 * COUNT(*) FILTER(WHERE device_type = 'Mobile') / COUNT(*), 2) AS mobile_pct,
    ROUND(100.0 * COUNT(*) FILTER(WHERE device_type = 'Tablet') / COUNT(*), 2) AS tablet_pct,
    ROUND(100.0 * COUNT(*) FILTER(WHERE device_type = 'Desktop') / COUNT(*), 2) AS desktop_pct
FROM rfm_results r
JOIN ecommerce_customer_behavior_dataset e ON r.customer_id = e.customer_id 
GROUP BY r.segment;

-- 3. Top 3 Product Categories by Segment (Revenue focus)
WITH category_revenue AS (
    SELECT
        r.segment,
        e.product_category,
        SUM(e.total_amount) AS total_revenue,
        RANK() OVER (PARTITION BY r.segment ORDER BY SUM(e.total_amount) DESC) AS rank
    FROM rfm_results r
    JOIN ecommerce_customer_behavior_dataset e ON r.customer_id = e.customer_id
    GROUP BY r.segment, e.product_category
)
SELECT segment, product_category, total_revenue
FROM category_revenue
WHERE rank <= 3
ORDER BY segment, total_revenue DESC;


/*******************************************************************************
Step 3: Executive Dashboard KPIs
Description: Final aggregation for high-level business reporting.
*******************************************************************************/

WITH order_level AS (
    SELECT
        customer_id,
        segment,
        order_id,
        SUM(total_amount)::numeric AS order_revenue,
        BOOL_OR(is_returning_customer) AS is_returning
    FROM ecommerce_customer_full_profile
    GROUP BY customer_id, segment, order_id
),
customer_level AS (
    SELECT
        customer_id,
        segment,
        SUM(order_revenue) AS customer_revenue,
        COUNT(order_id) AS orders_count,
        BOOL_OR(is_returning) AS has_repurchased
    FROM order_level
    GROUP BY customer_id, segment
)
SELECT
    segment,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*)::numeric / SUM(COUNT(*)) OVER () * 100, 2) AS customer_share_pct,
    SUM(customer_revenue) AS segment_revenue,
    ROUND(SUM(customer_revenue)::numeric / SUM(SUM(customer_revenue)) OVER () * 100, 2) AS revenue_share_pct,
    ROUND(AVG(customer_revenue / orders_count), 2) AS aov,
    ROUND(AVG(CASE WHEN has_repurchased THEN 1 ELSE 0 END)::numeric * 100, 2) AS retention_rate_pct
FROM customer_level
GROUP BY segment
ORDER BY segment_revenue DESC;