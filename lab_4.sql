-- =====================================================================
-- Лабораторная работа №4: Оконные функции и аналитика данных
-- Студент: Долин Дмитрий Олегович (БВТ2504)
-- =====================================================================

-- 1. Ранжирующие оконные функции (ROW_NUMBER, RANK, DENSE_RANK)
SELECT 
    c.name AS category_name, 
    p.title AS product_name, 
    p.price,
    ROW_NUMBER() OVER w AS row_num,
    RANK() OVER w AS rnk,
    DENSE_RANK() OVER w AS dense_rnk
FROM products p 
JOIN categories c ON c.id = p.category_id
WINDOW w AS (PARTITION BY p.category_id ORDER BY p.price DESC);

-- 2. Отбор трех самых дорогих товаров в каждой категории через CTE
WITH ranked_products AS (
    SELECT 
        c.name AS category_name, 
        p.title AS product_name, 
        p.price,
        ROW_NUMBER() OVER (PARTITION BY p.category_id ORDER BY p.price DESC) AS rn
    FROM products p
    JOIN categories c ON c.id = p.category_id
)
SELECT category_name, product_name, price
FROM ranked_products
WHERE rn <= 3;

-- 3. Расчет нарастающего итога выручки по дням
SELECT 
    o.created_at::date AS order_day,
    SUM(oi.quantity * oi.unit_price) AS daily_revenue,
    SUM(SUM(oi.quantity * oi.unit_price)) OVER (ORDER BY o.created_at::date) AS running_total
FROM orders o 
JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.created_at::date
ORDER BY order_day;

-- 4. Вычисление доли выручки продавца в своей категории через PARTITION BY
WITH seller_cat_rev AS (
    SELECT 
        p.seller_id, 
        s.store_name, 
        p.category_id, 
        c.name AS category_name,
        SUM(oi.quantity * oi.unit_price) AS seller_revenue
    FROM products p
    JOIN sellers s ON s.id = p.seller_id
    JOIN categories c ON c.id = p.category_id
    JOIN order_items oi ON oi.product_id = p.id
    GROUP BY p.seller_id, s.store_name, p.category_id, c.name
)
SELECT 
    store_name, 
    category_name, 
    seller_revenue,
    SUM(seller_revenue) OVER (PARTITION BY category_id) AS category_total_revenue,
    ROUND((seller_revenue / SUM(seller_revenue) OVER (PARTITION BY category_id)) * 100, 2) AS share_percentage
FROM seller_cat_rev
ORDER BY category_name, seller_revenue DESC;

-- 5. Сравнение выручки текущего дня с предыдущим (LAG и LEAD)
SELECT 
    o.created_at::date AS order_day,
    SUM(oi.quantity * oi.unit_price) AS daily_revenue,
    LAG(SUM(oi.quantity * oi.unit_price)) OVER (ORDER BY o.created_at::date) AS prev_day_revenue,
    LEAD(SUM(oi.quantity * oi.unit_price)) OVER (ORDER BY o.created_at::date) AS next_day_revenue
FROM orders o
JOIN order_items oi ON oi.order_id = o.id
GROUP BY o.created_at::date
ORDER BY order_day;
