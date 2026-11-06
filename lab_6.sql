-- =====================================================================
-- ПУНКТ 1. ДОБАВЛЕНИЕ ПОЛЯ JSONB И РАБОТА С ДОКУМЕНТНЫМИ ДАННЫМИ
-- =====================================================================

-- 1.1. Добавляем колонку metadata типа JSONB в таблицу products
ALTER TABLE products
ADD COLUMN IF NOT EXISTS metadata JSONB;

-- 1.2. Заполняем поле metadata структурированными данными для существующих товаров
UPDATE products
SET metadata = json_build_object(
    'brand', 'Brand_' || (id % 10 + 1),
    'warranty_months', CASE WHEN id % 2 = 0 THEN 12 ELSE 24 END,
    'specs', json_build_object(
        'color', CASE WHEN id % 3 = 0 THEN 'черный' WHEN id % 3 = 1 THEN 'серебристый' ELSE 'белый' END,
        'weight_kg', ROUND((1.0 + (id % 5) * 0.5)::numeric, 2),
        'is_fragile', CASE WHEN id % 4 = 0 THEN true ELSE false END
    ),
    'tags', json_build_array('хит', 'акция', 'новинка')
)::jsonb;

-- 1.3. Примеры запросов с операторами JSONB
-- Поиск по ключу в объекте (оператор ->>)
SELECT 
    id AS product_id,
    title,
    metadata->>'brand' AS brand,
    metadata->'specs'->>'color' AS color
FROM products
WHERE metadata->'specs'->>'color' = 'черный'
LIMIT 5;

-- Поиск по числовому или логическому значению через оператор приведения типа (->>)
SELECT 
    id AS product_id,
    title,
    metadata->'specs'->>'weight_kg' AS weight
FROM products
WHERE (metadata->'specs'->>'weight_kg')::numeric > 2.0
LIMIT 5;

-- Проверка наличия элемента в массиве (оператор ?$)
SELECT 
    id AS product_id,
    title,
    metadata->'tags' AS tags
FROM products
WHERE metadata->'tags' ? 'хит'
LIMIT 5;


-- =====================================================================
-- ПУНКТ 2. СОЗДАНИЕ И ИСПОЛЬЗОВАНИЕ ИНДЕКСОВ (B-Tree, GIN, Partial)
-- =====================================================================

-- 2.1. Стандартный B-Tree индекс по внешнему ключу / часто используемому полю
CREATE INDEX IF NOT EXISTS idx_products_category_id 
ON products(category_id);

-- 2.2. Составной индекс (Composite Index) для частой фильтрации по категории и цене
CREATE INDEX IF NOT EXISTS idx_products_category_price 
ON products(category_id, price);

-- 2.3. Частичный (Partial) индекс для быстрого поиска только активных товаров
CREATE INDEX IF NOT EXISTS idx_products_active_only 
ON products(id) 
WHERE is_active = TRUE;

-- 2.4. GIN-индекс для эффективного поиска по JSONB-полю metadata
CREATE INDEX IF NOT EXISTS idx_products_metadata_gin 
ON products USING gin (metadata);


-- =====================================================================
-- ПУНКТ 3. АНАЛИЗ ПРОИЗВОДИТЕЛЬНОСТИ ЗАПРОСОВ С EXPLAIN ANALYZE
-- =====================================================================

-- 3.1. Анализ запроса с фильтрацией по JSONB-полю (демонстрация работы GIN-индекса)
EXPLAIN ANALYZE
SELECT id, title, metadata->>'brand' AS brand
FROM products
WHERE metadata @> '{"specs": {"color": "черный"}}'::jsonb;

-- 3.2. Анализ составного индекса для фильтрации по категории и диапазону цен
EXPLAIN ANALYZE
SELECT id, title, price, category_id
FROM products
WHERE category_id = 1 
  AND price BETWEEN 5000.00 AND 25000.00
ORDER BY price DESC;

-- 3.3. Анализ частичного индекса по активным товарам
EXPLAIN ANALYZE
SELECT id, title, price
FROM products
WHERE is_active = TRUE
  AND price > 40000.00;