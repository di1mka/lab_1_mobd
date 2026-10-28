-- =====================================================================
-- Лабораторная работа №5: Транзакции, целостность данных и серверная логика
-- Студент: Долин Дмитрий Олегович (БВТ2504)
-- =====================================================================

-- =====================================================================
-- ПУНКТ 1. ДЕМОНСТРАЦИЯ РАБОТЫ ТРАНЗАКЦИЙ (BEGIN, COMMIT, ROLLBACK)
-- =====================================================================

-- 1.1. Успешная транзакция (BEGIN ... COMMIT)
-- Проверим остаток товара id = 1 до транзакции
SELECT product_id, quantity AS stock_before_commit FROM stock WHERE product_id = 1;

BEGIN;

-- Создаем новый заказ для пользователя 21
INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (21, 'paid', 36900.40, now());

-- Добавляем позицию в заказ (2 единицы товара id = 1)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
VALUES (currval(pg_get_serial_sequence('orders', 'id')), 1, 2, 18450.20);

-- Уменьшаем складской остаток товара id = 1 на 2 единицы
UPDATE stock
SET quantity = quantity - 2,
    updated_at = now()
WHERE product_id = 1;

COMMIT;

-- Проверим остаток товара id = 1 после COMMIT (уменьшился на 2)
SELECT product_id, quantity AS stock_after_commit FROM stock WHERE product_id = 1;


-- 1.2. Транзакция с отменой изменений (BEGIN ... ROLLBACK)
BEGIN;

-- Пытаемся обнулить остаток товара id = 1 и создать ошибочный заказ
UPDATE stock
SET quantity = 0,
    updated_at = now()
WHERE product_id = 1;

INSERT INTO orders (user_id, status, total_amount, created_at)
VALUES (21, 'pending', 999999.00, now());

-- Проверяем значение внутри незавершенной транзакции (видим 0)
SELECT product_id, quantity AS stock_inside_tx FROM stock WHERE product_id = 1;

-- Откатываем транзакцию из-за ошибки
ROLLBACK;

-- Проверяем остаток после ROLLBACK (изменения отменены, остаток прежний!)
SELECT product_id, quantity AS stock_after_rollback FROM stock WHERE product_id = 1;


-- =====================================================================
-- ПУНКТ 2. ФУНКЦИЯ PL/pgSQL ДЛЯ АТОМАРНОГО ОФОРМЛЕНИЯ ЗАКАЗА
-- =====================================================================

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
    -- Получаем текущую цену товара
    SELECT price INTO v_price
    FROM products
    WHERE id = p_product_id AND is_active = TRUE;

    IF v_price IS NULL THEN
        RAISE EXCEPTION 'Товар с id=% не найден или неактивен', p_product_id;
    END IF;

    -- Проверяем наличие товара на складе (с блокировкой строки FOR UPDATE)
    SELECT quantity INTO v_stock_qty
    FROM stock
    WHERE product_id = p_product_id
    FOR UPDATE;

    IF v_stock_qty IS NULL OR v_stock_qty < p_qty THEN
        RAISE EXCEPTION 'Недостаточно товара на складе (id=%): запрошено %, в наличии %',
            p_product_id, p_qty, COALESCE(v_stock_qty, 0);
    END IF;

    v_total := v_price * p_qty;

    -- Создаем заказ
    INSERT INTO orders (user_id, status, total_amount, created_at)
    VALUES (p_user_id, 'paid', v_total, now())
    RETURNING id INTO v_order_id;

    -- Создаем позицию заказа
    INSERT INTO order_items (order_id, product_id, quantity, unit_price)
    VALUES (v_order_id, p_product_id, p_qty, v_price);

    -- Списываем товар со склада
    UPDATE stock
    SET quantity = quantity - p_qty,
        updated_at = now()
    WHERE product_id = p_product_id;

    RETURN v_order_id;
END;
$$ LANGUAGE plpgsql;

-- 2.1. Успешный вызов функции оформления заказа (покупаем 1 шт. товара id = 2)
SELECT place_order(25, 2, 1) AS created_order_id;

-- 2.2. Вызов функции с нехваткой товара (вызовет RAISE EXCEPTION и откат изменений)
-- Раскомментируйте для демонстрации ошибки в pgAdmin:
-- SELECT place_order(25, 2, 50000);


-- =====================================================================
-- ПУНКТ 3. ФУНКЦИЯ PL/pgSQL, ВОЗВРАЩАЮЩАЯ СВОДНЫЙ ПОКАЗАТЕЛЬ
-- (Выручка продавца за заданный период)
-- =====================================================================

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

-- Демонстрация вызова функции для первых 5 продавцов за последние 90 дней
SELECT 
    s.id AS seller_id,
    s.store_name,
    get_seller_revenue(s.id, now() - interval '90 days', now()) AS revenue_90_days
FROM sellers AS s
WHERE s.id <= 5
ORDER BY revenue_90_days DESC;


-- =====================================================================
-- ПУНКТ 4. ТРИГГЕР АУДИТА ИЗМЕНЕНИЯ ЦЕНЫ ТОВАРА
-- =====================================================================

-- Создаем таблицу журнала аудита цен
CREATE TABLE IF NOT EXISTS product_price_audit (
    audit_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    old_price NUMERIC(12,2) NOT NULL,
    new_price NUMERIC(12,2) NOT NULL,
    changed_by TEXT NOT NULL DEFAULT current_user,
    changed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Триггерная функция для записи старой и новой цены
CREATE OR REPLACE FUNCTION fn_audit_product_price()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.price IS DISTINCT FROM OLD.price THEN
        INSERT INTO product_price_audit (product_id, old_price, new_price, changed_by, changed_at)
        VALUES (OLD.id, OLD.price, NEW.price, current_user, now());
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Создаем триггер на таблице products
DROP TRIGGER IF EXISTS trg_audit_product_price ON products;
CREATE TRIGGER trg_audit_product_price
AFTER UPDATE OF price ON products
FOR EACH ROW
EXECUTE FUNCTION fn_audit_product_price();

-- Демонстрация работы триггера аудита: изменяем цену товаров id = 1 и id = 2
UPDATE products SET price = price + 1500.00 WHERE id IN (1, 2);

-- Проверяем записи в таблице журнала аудита
SELECT 
    audit_id,
    product_id,
    old_price,
    new_price,
    changed_by,
    changed_at
FROM product_price_audit
ORDER BY audit_id DESC;


-- =====================================================================
-- ПУНКТ 5. ТРИГГЕР ПОДДЕРЖАНИЯ ДЕНОРМАЛИЗОВАННОГО ПОЛЯ
-- (Автоматический пересчет среднего рейтинга товара при работе с отзывами)
-- =====================================================================

-- Добавляем денормализованное поле rating в таблицу products
ALTER TABLE products
ADD COLUMN IF NOT EXISTS rating NUMERIC(3,2) NOT NULL DEFAULT 0.00;

-- Первоначальная синхронизация рейтинга по уже существующим отзывам
UPDATE products p
SET rating = COALESCE((
    SELECT ROUND(AVG(r.score), 2)
    FROM reviews r
    WHERE r.product_id = p.id
), 0.00);

-- Триггерная функция пересчета рейтинга товара
CREATE OR REPLACE FUNCTION fn_refresh_product_rating()
RETURNS TRIGGER AS $$
DECLARE
    v_target_product_id BIGINT;
BEGIN
    IF TG_OP = 'DELETE' THEN
        v_target_product_id := OLD.product_id;
    ELSE
        v_target_product_id := NEW.product_id;
    END IF;

    UPDATE products
    SET rating = COALESCE((
        SELECT ROUND(AVG(score), 2)
        FROM reviews
        WHERE product_id = v_target_product_id
    ), 0.00)
    WHERE id = v_target_product_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Создаем триггер на таблице reviews
DROP TRIGGER IF EXISTS trg_refresh_product_rating ON reviews;
CREATE TRIGGER trg_refresh_product_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION fn_refresh_product_rating();

-- Демонстрация работы триггера:
-- Проверим текущий рейтинг товара id = 10 до добавления нового отзыва
SELECT id AS product_id, title, rating AS rating_before FROM products WHERE id = 10;

-- Добавляем новые отзывы к товару id = 10
INSERT INTO reviews (user_id, product_id, score, comment, created_at)
VALUES 
    (50, 10, 5, 'Отличный смартфон, работает быстро!', now()),
    (51, 10, 4, 'Хороший товар за свои деньги', now());

-- Проверим обновленный рейтинг товара id = 10 (пересчитался автоматически!)
SELECT id AS product_id, title, rating AS rating_after FROM products WHERE id = 10;
