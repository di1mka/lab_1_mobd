-- =====================================================================
-- РАЗДЕЛ 1. ЕДИНЫЙ ВОСПРОИЗВОДИМЫЙ DDL-СКРИПТ СХЕМЫ БД (3НФ + РАСШИРЕНИЯ)
-- =====================================================================

CREATE TABLE IF NOT EXISTS users (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL UNIQUE,
    phone VARCHAR(32) UNIQUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sellers (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    store_name VARCHAR(255) NOT NULL UNIQUE,
    inn VARCHAR(20) NOT NULL UNIQUE,
    rating NUMERIC(3,2) NOT NULL DEFAULT 5.00 CHECK (rating BETWEEN 0.00 AND 5.00),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS categories (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name VARCHAR(255) NOT NULL UNIQUE,
    parent_id BIGINT REFERENCES categories(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS products (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    seller_id BIGINT NOT NULL REFERENCES sellers(id) ON DELETE CASCADE,
    category_id BIGINT NOT NULL REFERENCES categories(id) ON DELETE RESTRICT,
    title VARCHAR(255) NOT NULL,
    price NUMERIC(12,2) NOT NULL CHECK (price >= 0.00),
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    rating NUMERIC(3,2) NOT NULL DEFAULT 0.00,
    metadata JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS stock (
    product_id BIGINT PRIMARY KEY REFERENCES products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS addresses (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    city VARCHAR(120) NOT NULL,
    street VARCHAR(255) NOT NULL,
    postal_code VARCHAR(20)
);

CREATE TABLE IF NOT EXISTS carts (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cart_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    cart_id BIGINT NOT NULL REFERENCES carts(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    UNIQUE (cart_id, product_id)
);

CREATE TABLE IF NOT EXISTS orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE RESTRICT,
    status VARCHAR(32) NOT NULL CHECK (status IN ('pending', 'paid', 'shipped', 'delivered', 'cancelled')),
    total_amount NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0.00),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price NUMERIC(12,2) NOT NULL CHECK (unit_price >= 0.00)
);

CREATE TABLE IF NOT EXISTS payments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    payment_method VARCHAR(50) NOT NULL,
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0.00),
    status VARCHAR(32) NOT NULL,
    paid_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS deliveries (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
    address_id BIGINT REFERENCES addresses(id) ON DELETE SET NULL,
    status VARCHAR(32) NOT NULL,
    tracking_number VARCHAR(100),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS reviews (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    score SMALLINT NOT NULL CHECK (score BETWEEN 1 AND 5),
    comment TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS product_price_audit (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    old_price NUMERIC(12,2) NOT NULL,
    new_price NUMERIC(12,2) NOT NULL,
    changed_by TEXT NOT NULL DEFAULT current_user,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);


-- =====================================================================
-- РАЗДЕЛ 2. КОНТРОЛЬ НАПОЛНЕНИЯ БАЗЫ СОГЛАСОВАННЫМИ ДАННЫМИ (СКРИНШОТ №1)
-- =====================================================================

SELECT 'users' AS table_name, COUNT(*) AS rows_count FROM users
UNION ALL
SELECT 'sellers', COUNT(*) FROM sellers
UNION ALL
SELECT 'categories', COUNT(*) FROM categories
UNION ALL
SELECT 'products', COUNT(*) FROM products
UNION ALL
SELECT 'stock', COUNT(*) FROM stock
UNION ALL
SELECT 'orders', COUNT(*) FROM orders
UNION ALL
SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL
SELECT 'reviews', COUNT(*) FROM reviews
UNION ALL
SELECT 'product_price_audit', COUNT(*) FROM product_price_audit;


-- =====================================================================
-- РАЗДЕЛ 3. АНАЛИТИЧЕСКИЕ SQL-ЗАПРОСЫ: JOIN, CTE, ОКОННЫЕ ФУНКЦИИ (СКРИНШОТ №2)
-- =====================================================================

-- 3.1. Запрос с CTE и оконными функциями: ранжирование продавцов по выручке
-- и расчет доли каждого продавца в общем обороте площадки
WITH seller_stats AS (
    SELECT 
        s.id AS seller_id,
        s.store_name,
        COUNT(DISTINCT o.id) AS orders_count,
        SUM(oi.quantity * oi.unit_price) AS total_revenue
    FROM sellers AS s
    INNER JOIN products AS p ON p.seller_id = s.id
    INNER JOIN order_items AS oi ON oi.product_id = p.id
    INNER JOIN orders AS o ON o.id = oi.order_id
    WHERE o.status <> 'cancelled'
    GROUP BY s.id, s.store_name
)
SELECT 
    seller_id,
    store_name,
    orders_count,
    ROUND(total_revenue, 2) AS total_revenue,
    RANK() OVER (ORDER BY total_revenue DESC) AS revenue_rank,
    ROUND(total_revenue * 100.0 / SUM(total_revenue) OVER (), 2) AS market_share_pct
FROM seller_stats
ORDER BY revenue_rank
LIMIT 10;


-- =====================================================================
-- РАЗДЕЛ 4. АНАЛИТИЧЕСКИЕ ПРЕДСТАВЛЕНИЯ (VIEW) ПЛОЩАДКИ (СКРИНШОТ №3)
-- =====================================================================

-- 4.1. Представление сводной аналитики по категориям товаров
CREATE OR REPLACE VIEW v_category_sales_summary AS
SELECT 
    c.id AS category_id,
    c.name AS category_name,
    COUNT(DISTINCT p.id) AS products_total,
    COALESCE(SUM(oi.quantity), 0) AS units_sold,
    COALESCE(ROUND(SUM(oi.quantity * oi.unit_price), 2), 0.00) AS category_revenue,
    ROUND(AVG(p.rating), 2) AS avg_category_rating
FROM categories AS c
LEFT JOIN products AS p ON p.category_id = c.id
LEFT JOIN order_items AS oi ON oi.product_id = p.id
LEFT JOIN orders AS o ON o.id = oi.order_id AND o.status <> 'cancelled'
GROUP BY c.id, c.name;

-- Проверка работы аналитического представления
SELECT * FROM v_category_sales_summary
ORDER BY category_revenue DESC
LIMIT 10;


-- =====================================================================
-- РАЗДЕЛ 5. СЕРВЕРНАЯ ЛОГИКА НА PL/pgSQL И ТРИГГЕРЫ (СКРИНШОТ №4)
-- =====================================================================

-- 5.1. Транзакционная функция атомарного оформления заказа
CREATE OR REPLACE FUNCTION place_order(
    p_user_id BIGINT,
    p_product_id BIGINT,
    p_qty INTEGER
)
RETURNS BIGINT AS $$
DECLARE
    v_order_id BIGINT;
    v_price NUMERIC(12,2);
    v_stock_qty INTEGER;
    v_total NUMERIC(12,2);
BEGIN
    SELECT price INTO v_price
    FROM products
    WHERE id = p_product_id AND is_active = TRUE;

    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Товар с id=% не найден или неактивен', p_product_id;
    END IF;

    SELECT quantity INTO v_stock_qty
    FROM stock
    WHERE product_id = p_product_id
    FOR UPDATE;

    IF v_stock_qty IS NULL OR v_stock_qty < p_qty THEN
        RAISE EXCEPTION 'Недостаточно товара на складе (id=%): запрошено %, в наличии %',
            p_product_id, p_qty, COALESCE(v_stock_qty, 0);
    END IF;

    v_total := v_price * p_qty;

    INSERT INTO orders (user_id, status, total_amount, created_at)
    VALUES (p_user_id, 'paid', v_total, now())
    RETURNING id INTO v_order_id;

    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_qty, v_price);

    UPDATE stock
    SET quantity = quantity - p_qty,
        updated_at = now()
    WHERE product_id = p_product_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- 5.2. Функция расчета выручки продавца за период
CREATE OR REPLACE FUNCTION get_seller_revenue(
    p_seller_id BIGINT,
    p_start_date TIMESTAMPTZ,
    p_end_date TIMESTAMPTZ
)
RETURNS NUMERIC(12,2) AS $$
DECLARE
    v_revenue NUMERIC(12,2);
BEGIN
    SELECT COALESCE(SUM(oi.quantity * oi.unit_price), 0.00)
    INTO v_revenue
    FROM order_items AS oi
    INNER JOIN orders AS o ON o.id = oi.order_id
    INNER JOIN products AS p ON p.id = oi.product_id
    WHERE p.seller_id = p_seller_id
      AND o.created_at BETWEEN p_start_date AND p_end_date
      AND o.status <> 'cancelled';

    RETURN v_revenue;
END;
$$ LANGUAGE plpgsql;

-- Проверка работы функции и журнала аудита цен
SELECT 
    s.id AS seller_id,
    s.store_name,
    get_seller_revenue(s.id, now() - interval '90 days', now()) AS revenue_90_days
FROM sellers AS s
WHERE s.id <= 5
ORDER BY revenue_90_days DESC;


-- =====================================================================
-- РАЗДЕЛ 6. ХРАНЕНИЕ ХАРАКТЕРИСТИК ТОВАРОВ В JSONB (СКРИНШОТ №5)
-- =====================================================================

SELECT 
    id AS product_id,
    title,
    price,
    metadata->>'brand' AS brand,
    metadata->'specs'->>'color' AS color,
    (metadata->'specs'->>'weight_kg')::numeric AS weight_kg,
    metadata->'tags' AS tags
FROM products
WHERE metadata @> '{"specs": {"color": "черный"}}'::jsonb
  AND metadata->'tags' ? 'хит'
LIMIT 5;


-- =====================================================================
-- РАЗДЕЛ 7. ИНДЕКСИРОВАНИЕ И ОПТИМИЗАЦИЯ EXPLAIN ANALYZE (СКРИНШОТ №6)
-- =====================================================================

CREATE INDEX IF NOT EXISTS idx_products_category_id ON products(category_id);
CREATE INDEX IF NOT EXISTS idx_products_category_price ON products(category_id, price);
CREATE INDEX IF NOT EXISTS idx_products_active_only ON products(id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_products_metadata_gin ON products USING gin (metadata);

EXPLAIN ANALYZE
SELECT id, title, price, metadata->>'brand' AS brand
FROM products
WHERE metadata @> '{"specs": {"color": "черный"}}'::jsonb;