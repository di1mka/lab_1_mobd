-- Запрос 1 (Пункт 2 ТЗ): Выборка столбцов без дубликатов (DISTINCT) с псевдонимами (AS)
SELECT DISTINCT 
    category_id AS product_category_id,
    seller_id AS store_seller_id,
    is_active AS is_available_for_sale
FROM products
ORDER BY product_category_id ASC, store_seller_id ASC;

-- Запрос 2 (Пункт 3 ТЗ): Фильтрация по нескольким условиям, объединённым AND и OR со скобками
SELECT 
    id AS product_id,
    title AS product_name,
    category_id,
    price AS regular_price,
    round(price * 0.90, 2) AS discount_price
FROM products
WHERE is_active = TRUE
  AND (
      (category_id = 4 AND price > 30000.00)
      OR 
      (category_id = 5 AND price > 40000.00)
  );

-- Запрос 3.1 (Пункт 4 ТЗ): Применение предикатов IN, BETWEEN и ILIKE
SELECT 
    id AS product_id,
    title AS product_name,
    category_id,
    price
FROM products
WHERE category_id IN (1, 4, 6)
  AND price BETWEEN 2000.00 AND 15000.00
  AND (title ILIKE '%смартфон%' OR title ILIKE '%наушники%')
  AND is_active = TRUE;

-- Запрос 3.2 (Пункт 4 ТЗ): Применение предиката IS NULL и функции COALESCE
SELECT 
    id AS product_id,
    title AS product_name,
    price,
    COALESCE(description, 'Описание временно отсутствует') AS product_description
FROM products
WHERE description IS NULL;

-- Запрос 4 (Пункт 5 ТЗ): Сортировка по двум столбцам в разных направлениях
SELECT 
    category_id,
    title AS product_name,
    price,
    created_at
FROM products
WHERE is_active = TRUE
ORDER BY category_id ASC, price DESC;

-- Запрос 5 (Пункт 6 ТЗ): Постраничный вывод товаров с помощью LIMIT и OFFSET (3-я страница по 10 товаров)
SELECT 
    id AS product_id,
    title AS product_name,
    price,
    seller_id
FROM products
WHERE is_active = TRUE
ORDER BY price DESC, id ASC
LIMIT 10 OFFSET 20;