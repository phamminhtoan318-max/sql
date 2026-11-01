-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 2: XỬ LÝ DỮ LIỆU NÂNG CAO & ANALYTICAL SQL (ADVANCED DATA PIPELINE & ANALYTICAL SQL)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 2: DATA QUALITY & PROFILING QUERIES (KIỂM TRA CHẤT LƯỢNG DỮ LIỆU)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 1]: DIMENSION 1 - COMPLETENESS & PHÁT HIỆN THIẾU DỮ LIỆU
-- ------------------------------------------------------------------------------------------

-- Câu 2.1.1:
-- Quét toàn bộ bảng đơn hàng để kiểm tra tính đầy đủ của các trường thông tin cốt lõi
-- (các trường định danh và trạng thái bắt buộc):
-- Đếm tổng số bản ghi và thống kê số lượng bản ghi bị khuyết thiếu dữ liệu ở từng trường quan trọng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.1 TẠI ĐÂY:
with quality as (
    select  
        count(*) as total_rows,
        count(case when orders.order_id is null then 1 end ) as missing_order_id,
        count(case when orders.customer_id is null then 1 end ) as missing_customer_id, 
        count(case when orders.order_status is null then 1 end ) as missing_order_status
    from dbo.olist_orders_dataset orders  
),table_percentage as (
    select 
        total_rows,
        missing_order_id,
        CAST(missing_order_id AS FLOAT) * 100.0 / total_rows AS pct_missing_order_id,
        missing_customer_id,
        CAST(missing_customer_id AS FLOAT) * 100.0 / total_rows AS pct_missing_customer_id,
        missing_order_status,
        CAST(missing_order_status AS FLOAT) * 100.0 / total_rows AS pct_missing_order_status
    from quality  
) 
select *  
from table_percentage;

-- ------------------------------------------------------------------------------------------
-- Câu 2.1.2:1
-- Xây dựng một báo cáo tổng quan (Data Profiling Report) kiểm tra tất cả các cột mốc thời gian
-- trong bảng đơn hàng:
-- Trả về danh sách các cột có tồn tại dữ liệu bị thiếu kèm theo số lượng dòng thiếu
-- và tỷ lệ phần trăm thiếu dữ liệu tương ứng, sắp xếp theo mức độ thiếu từ cao xuống thấp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.2 TẠI ĐÂY:

-- VIẾT QUERY CÂU 2.1.2 TẠI ĐÂY:
WITH base AS (
    SELECT 
        COUNT(*) AS total_rows,
        COUNT(CASE WHEN order_approved_at IS NULL THEN 1 END) AS missing_approved,
        COUNT(CASE WHEN order_purchase_timestamp IS NULL THEN 1 END) AS missing_purchase,
        COUNT(CASE WHEN order_estimated_delivery_date IS NULL THEN 1 END) AS missing_estimated,
        COUNT(CASE WHEN order_delivered_carrier_date IS NULL THEN 1 END) AS missing_carrier,
        COUNT(CASE WHEN order_delivered_customer_date IS NULL THEN 1 END) AS missing_customer
    FROM dbo.olist_orders_dataset
),
profiling_report AS (
    SELECT 'order_approved_at' AS column_name, missing_approved AS missing_rows, CAST(missing_approved AS FLOAT) * 100.0 / total_rows AS pct_missing FROM base
    UNION ALL
    SELECT 'order_purchase_timestamp', missing_purchase, CAST(missing_purchase AS FLOAT) * 100.0 / total_rows FROM base
    UNION ALL
    SELECT 'order_estimated_delivery_date', missing_estimated, CAST(missing_estimated AS FLOAT) * 100.0 / total_rows FROM base
    UNION ALL
    SELECT 'order_delivered_carrier_date', missing_carrier, CAST(missing_carrier AS FLOAT) * 100.0 / total_rows FROM base
    UNION ALL
    SELECT 'order_delivered_customer_date', missing_customer, CAST(missing_customer AS FLOAT) * 100.0 / total_rows FROM base
)
SELECT 
    column_name,
    missing_rows,
    ROUND(pct_missing, 2) AS pct_missing
FROM profiling_report
WHERE missing_rows > 0                
ORDER BY missing_rows DESC;           


-- ------------------------------------------------------------------------------------------
-- Câu 2.1.3:
-- Nhiều hệ thống nguồn lưu trữ dữ liệu bị thiếu dưới dạng chuỗi rỗng hoặc chỉ toàn ký tự khoảng trắng
-- thay vì giá trị NULL thực sự.
-- Hãy viết truy vấn phát hiện tất cả các khách hàng có thông tin địa bàn (thành phố hoặc bang)
-- bị thiếu hoặc chỉ chứa khoảng trắng rỗng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.3 TẠI ĐÂY:
select 
    customers.customer_unique_id,
    customers.customer_city,
    customers.customer_state
from dbo.olist_customers_dataset customers 
where nullif(trim(customers.customer_city), '') is null 
or nullif(trim(customers.customer_state), '') is null


-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 2]: DIMENSION 2 - UNIQUENESS & KIỂM SOÁT TRÙNG LẶP KHÓA
-- ------------------------------------------------------------------------------------------

-- Câu 2.2.1:
-- Thực hiện bài kiểm tra tính duy nhất (Uniqueness Test) cho khóa chính của bảng đánh giá:
-- Phát hiện xem có mã đánh giá nào bị lặp lại nhiều lần hay không và liệt kê chi tiết các mã vi phạm.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.1 TẠI ĐÂY:

with review_duplicate as (
    select 
        reviews.review_id,
        count(*) as duplicates_count
    from dbo.olist_order_reviews_dataset reviews
    group by reviews.review_id 
    having count(*) > 1
)
select 
    rd.review_id,
    rd.duplicates_count
from review_duplicate rd 
where duplicates_count > 1
order by rd.duplicates_count desc;


-- ------------------------------------------------------------------------------------------
-- Câu 2.2.2:
-- Trong bảng chi tiết mặt hàng, mỗi đơn hàng có thể có nhiều sản phẩm nhưng mỗi dòng sản phẩm
-- trong cùng một đơn phải có số thứ tự phân biệt độc nhất.
-- Hãy viết truy vấn kiểm tra xem có bất kỳ sự trùng lặp nào trên cặp khóa tổ hợp này hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.2 TẠI ĐÂY:

with item_number_duplicate as (
    select 
        order_items.order_id,
        order_items.order_item_id,
        count(*) as duplicates_count
    from dbo.olist_order_items_dataset order_items
    group by order_items.order_id, order_items.order_item_id
    having count(*) > 1
)
select 
    rd.order_id,
    rd.order_item_id,
    rd.duplicates_count
from item_number_duplicate rd 
where duplicates_count > 1
order by rd.duplicates_count desc;


-- ------------------------------------------------------------------------------------------
-- Câu 2.2.3:
-- Kiểm tra tính duy nhất của trình tự thanh toán trong bảng thanh toán:
-- Tìm các đơn hàng bị lỗi ghi nhận dữ liệu khiến cho cùng một thứ tự thanh toán
-- lại xuất hiện nhiều hơn một lần trong cùng một đơn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.3 TẠI ĐÂY:

with payment_sequence_duplicate as (
    select 
        payments.order_id,
        payments.payment_sequential,
        count(*) as duplicates_count
    from dbo.olist_order_payments_dataset payments
    group by payments.order_id, payments.payment_sequential
    having count(*) > 1
)
select 
    psd.order_id,
    psd.payment_sequential,
    psd.duplicates_count
from payment_sequence_duplicate psd 
where duplicates_count > 1
order by psd.duplicates_count desc;


-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 3]: DIMENSION 3 - VALIDITY & KIỂM TRA MIỀN GIÁ TRỊ NGOẠI LAI
-- ------------------------------------------------------------------------------------------

-- Câu 2.3.1:
-- Quét toàn bộ bảng chi tiết bán hàng để phát hiện các dòng dữ liệu tài chính bất thường:
-- Tìm các bản ghi có đơn giá hoặc phí vận chuyển mang giá trị âm hoặc bằng không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.1 TẠI ĐÂY:

with table_payment as (
    select 
        items.*
    from dbo.olist_order_items_dataset items 
),
kiem_tra as (
    select 
        *
    from table_payment t
    where (t.price <= 0 or t.price is null)
    or (t.freight_value <= 0 or t.freight_value is null)
)
select *
from kiem_tra


-- ------------------------------------------------------------------------------------------
-- Câu 2.3.2:
-- Kiểm tra tính hợp lệ của danh mục trạng thái đơn hàng (Whitelist Validation):
-- Phát hiện xem trong bảng đơn hàng có tồn tại bất kỳ bản ghi nào mang trạng thái
-- nằm ngoài tập 8 trạng thái tiêu chuẩn được quy định bởi hệ thống hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.2 TẠI ĐÂY:

SELECT *
FROM dbo.olist_orders_dataset orders
WHERE orders.order_status NOT IN (
    'delivered',
    'shipped',
    'canceled',
    'unavailable',
    'invoiced',
    'processing',
    'created',
    'approved'
)
OR orders.order_status IS NULL;

SELECT DISTINCT hehe.order_status 
    FROM dbo.olist_orders_dataset hehe

-- ------------------------------------------------------------------------------------------
-- Câu 2.3.3:
-- Kiểm tra định dạng và thang điểm đo lường:
-- 1. Tìm các đánh giá có điểm số nằm ngoài thang đo chuẩn từ 1 đến 5 sao.
-- 2. Tìm các mã bang trong bảng khách hàng có độ dài ký tự khác với chuẩn quy định 2 chữ cái.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.3 TẠI ĐÂY:

SELECT *
FROM dbo.olist_order_reviews_dataset reviews 
WHERE reviews.review_score NOT BETWEEN 1 AND 5
   OR reviews.review_score IS NULL;

SELECT DISTINCT 
    customers.customer_id,
    customers.customer_state,
    LEN(customers.customer_state) AS state_length
FROM dbo.olist_customers_dataset customers  
WHERE LEN(customers.customer_state) <> 2
   OR customers.customer_state IS NULL;

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 4]: DIMENSION 4 - REFERENTIAL INTEGRITY (TOÀN VẸN THAM CHIẾU)
-- ------------------------------------------------------------------------------------------

-- Câu 2.4.1:
-- Quét các bản ghi mồ côi (Orphan records) giữa bảng chi tiết bán hàng và danh mục sản phẩm:
-- Tìm các mặt hàng đã bán nhưng mã sản phẩm lại hoàn toàn không tồn tại trong danh mục sản phẩm gốc,
-- và tính toán tổng lượng doanh thu đang bị ảnh hưởng bởi lỗi này.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.1 TẠI ĐÂY:

select 
    items.product_id,
    COUNT(*)                         AS total_orphan_records,
    isnull(sum(items.price), 0)      as total_revenue
from dbo.olist_order_items_dataset items 
where not exists (
    select 1
    from dbo.olist_products_dataset products
    where products.product_id = items.product_id
)
group by items.product_id;


-- ------------------------------------------------------------------------------------------
-- Câu 2.4.2:
-- Kiểm tra tính toàn vẹn tham chiếu giữa bảng đơn hàng và bảng khách hàng:
-- Tìm các đơn hàng phát sinh trong hệ thống nhưng mã khách hàng không thể liên kết được
-- với bất kỳ thông tin nào trong hồ sơ khách hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.2 TẠI ĐÂY:

select 
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.order_purchase_timestamp
from dbo.olist_orders_dataset orders
where not exists (
    select 1
    from dbo.olist_customers_dataset customers
    where customers.customer_id = orders.customer_id
)


-- ------------------------------------------------------------------------------------------
-- Câu 2.4.3:
-- Kiểm tra toàn vẹn dòng tiền thanh toán:
-- Tìm các khoản thanh toán thực nhận trong bảng thanh toán mà không thể truy ngược về
-- bất kỳ đơn hàng nào có trong hệ thống, và tính tổng số tiền bị mồ côi này.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.3 TẠI ĐÂY:


select 
    COUNT(DISTINCT payments.order_id)      AS total_orphan_orders,
    COUNT(*)                               AS total_orphan_payment_records,
    isnull(sum(payments.payment_value), 0)      as total_orphan_amount
from dbo.olist_order_payments_dataset payments 
where not exists (
    select 1
    from dbo.olist_orders_dataset orders
    where orders.order_id = payments.order_id   
)
group by payments.order_id

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 5]: DIMENSION 5 - BUSINESS RULES & NGHỊCH LÝ LOGIC NGHIỆP VỤ
-- ------------------------------------------------------------------------------------------

-- Câu 2.5.1:
-- Phát hiện các bản ghi vi phạm tính logic về trình tự thời gian (Temporal Logic Violation):
-- Tìm các đơn hàng có ngày khách nhận hàng trước ngày đặt mua, hoặc ngày duyệt thanh toán
-- lại diễn ra trước thời điểm khách bấm đặt hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.1 TẠI ĐÂY:

select 
    orders.order_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_delivered_customer_date,
    orders.order_approved_at
from dbo.olist_orders_dataset orders
where orders.order_purchase_timestamp > orders.order_delivered_customer_date
or orders.order_purchase_timestamp > orders.order_approved_at


SELECT 
    orders.order_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_delivered_customer_date,
    orders.order_approved_at,
    CASE 
        WHEN orders.order_delivered_customer_date < orders.order_purchase_timestamp 
             AND orders.order_approved_at < orders.order_purchase_timestamp 
            THEN 'Both Violations'
        WHEN orders.order_delivered_customer_date < orders.order_purchase_timestamp 
            THEN 'Delivered Before Purchase'
        WHEN orders.order_approved_at < orders.order_purchase_timestamp 
            THEN 'Approved Before Purchase'
    END AS violation_type
FROM dbo.olist_orders_dataset orders
WHERE orders.order_delivered_customer_date < orders.order_purchase_timestamp
   OR orders.order_approved_at < orders.order_purchase_timestamp;


-- ------------------------------------------------------------------------------------------
-- Câu 2.5.2:
-- Bắt lỗi mâu thuẫn giữa trạng thái đơn hàng và mốc thời gian thực tế:
-- Tìm các đơn hàng đã được gắn mác giao hàng thành công nhưng lại thiếu ngày khách nhận,
-- hoặc các đơn hàng đã bị hủy bỏ nhưng vẫn tồn tại mốc thời gian giao hàng thành công.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.2 TẠI ĐÂY:


select 
    orders.order_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_delivered_customer_date,
    orders.order_approved_at
from dbo.olist_orders_dataset orders
where orders.order_status = 'delivered'
and orders.order_delivered_customer_date is null


select * 
from dbo.olist_orders_dataset orders
where orders.order_status = 'canceled'
and orders.order_delivered_customer_date is not null


-- ------------------------------------------------------------------------------------------
-- Câu 2.5.3:
-- Đối soát tính cân bằng tài chính của từng đơn hàng:
-- Tìm các đơn hàng đã giao thành công mà tổng giá trị hàng bán và cước vận chuyển
-- có sự chênh lệch đáng kể so với tổng số tiền khách hàng đã thanh toán.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.3 TẠI ĐÂY:


with item_totals  as (
    select order_id, sum(price + freight_value) as total_price
    from dbo.olist_order_items_dataset items
    group by items.order_id
    
), payment_totals  as (
    select order_id, sum(payment_value) as total_payment
    from dbo.olist_order_payments_dataset payments
    group by payments.order_id
)
select 
    orders.order_id,
    orders.order_status,
    ROUND(item_totals.total_price, 2)         AS total_price,
    ROUND(payment_totals.total_payment, 2)   AS total_payment,
    ROUND(ABS(item_totals.total_price - payment_totals.total_payment), 2) AS diff_amount
from dbo.olist_orders_dataset orders
inner join item_totals on orders.order_id = item_totals.order_id
inner join payment_totals on orders.order_id = payment_totals.order_id
where orders.order_status = 'delivered'
and abs(item_totals.total_price - payment_totals.total_payment) > 1.0
order by diff_amount desc


-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 6]: ĐÁNH GIÁ CHẤT LƯỢNG VÀ CÁCH LY DỮ LIỆU LỖI (QUARANTINE PIPELINE)
-- ------------------------------------------------------------------------------------------

-- Câu 2.6.1:
-- Xây dựng thang điểm chất lượng dữ liệu (Data Quality Score từ 0 đến 100) cho từng đơn hàng:
-- Đơn hàng đầy đủ thông tin đạt 100 điểm, mỗi vi phạm về mốc thời gian hoặc trạng thái
-- sẽ bị trừ điểm tương ứng. Thống kê số lượng đơn hàng theo từng phân hạng chất lượng (Sạch, Chấp nhận được, Kém).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.1 TẠI ĐÂY:

with score_calc as (
    select    
        orders.order_id,
        orders.order_status,
        orders.order_purchase_timestamp,
        orders.order_delivered_customer_date,
        orders.order_approved_at,
        100 
        - (CASE WHEN orders.order_delivered_customer_date < orders.order_purchase_timestamp THEN 30 ELSE 0 END)
        - (CASE WHEN orders.order_approved_at < orders.order_purchase_timestamp THEN 20 ELSE 0 END)
        - (CASE WHEN orders.order_status = 'delivered' AND orders.order_delivered_customer_date IS NULL THEN 30 ELSE 0 END)
        - (CASE WHEN orders.order_status = 'canceled' AND orders.order_delivered_customer_date IS NOT NULL THEN 40 ELSE 0 END) 
    as dq_score
    from dbo.olist_orders_dataset orders
),
score_range as (
    select 
        score_calc.order_id,
        score_calc.dq_score,
        case
            when score_calc.dq_score = 100 then N'Sạch'
            when score_calc.dq_score between 70 and 90 then N'Chấp nhận được' 
            else N'Kém'
        end as dq_range
    from score_calc
)select 
    score_range.dq_range,
    count(score_range.order_id) as total_orders
from score_range
group by score_range.dq_range



-- ------------------------------------------------------------------------------------------
-- Câu 2.6.2:
-- Áp dụng cơ chế Quarantine Pattern:
-- Viết truy vấn tự động lọc và đẩy toàn bộ các đơn hàng vi phạm quy tắc thời gian hoặc trạng thái
-- vào một bảng cách ly dữ liệu lỗi kèm theo lý do vi phạm cụ thể, tách biệt khỏi luồng dữ liệu sạch.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.2 TẠI ĐÂY:

-- 1. Tạo bảng cách ly nếu chưa tồn tại
IF OBJECT_ID('dbo.quarantine_orders', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.quarantine_orders (
        quarantine_id INT IDENTITY(1,1) PRIMARY KEY,
        order_id VARCHAR(50),
        customer_id VARCHAR(50),
        order_status VARCHAR(50),
        order_purchase_timestamp DATETIME,
        order_approved_at DATETIME,
        order_delivered_carrier_date DATETIME,
        order_delivered_customer_date DATETIME,
        order_estimated_delivery_date DATETIME,
        quarantine_reason NVARCHAR(500),
        quarantined_at DATETIME DEFAULT GETDATE()
    );
END;

-- 2. Đẩy các đơn hàng vi phạm quy tắc thời gian và trạng thái vào bảng cách ly
INSERT INTO dbo.quarantine_orders (
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    quarantine_reason,
    quarantined_at
)
SELECT 
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_approved_at,
    orders.order_delivered_carrier_date,
    orders.order_delivered_customer_date,
    orders.order_estimated_delivery_date,
    CONCAT_WS('; ',
        CASE WHEN orders.order_delivered_customer_date < orders.order_purchase_timestamp THEN N'Khách nhận trước ngày đặt mua' END,
        CASE WHEN orders.order_approved_at < orders.order_purchase_timestamp THEN N'Duyệt thanh toán trước ngày đặt mua' END,
        CASE WHEN orders.order_status = 'delivered' AND orders.order_delivered_customer_date IS NULL THEN N'Đơn delivered nhưng thiếu ngày giao thực tế' END,
        CASE WHEN orders.order_status = 'canceled' AND orders.order_delivered_customer_date IS NOT NULL THEN N'Đơn canceled nhưng vẫn tồn tại ngày giao' END
    ) AS quarantine_reason,
    GETDATE() AS quarantined_at
FROM dbo.olist_orders_dataset orders
WHERE orders.order_delivered_customer_date < orders.order_purchase_timestamp
   OR orders.order_approved_at < orders.order_purchase_timestamp
   OR (orders.order_status = 'delivered' AND orders.order_delivered_customer_date IS NULL)
   OR (orders.order_status = 'canceled' AND orders.order_delivered_customer_date IS NOT NULL);

SELECT * FROM dbo.quarantine_orders;


-- ------------------------------------------------------------------------------------------
-- Câu 2.6.3:
-- Thiết lập cơ chế ngắt mạch tự động (Circuit Breaker):
-- Viết khối lệnh kiểm tra tỷ lệ lỗi dữ liệu của toàn bộ bảng đơn hàng.
-- Nếu tỷ lệ bản ghi lỗi vượt quá ngưỡng 2%, tự động in cảnh báo khẩn cấp và chặn tiến trình pipeline.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.3 TẠI ĐÂY:

DECLARE @total_rows INT;
DECLARE @error_rows INT;
DECLARE @error_rate DECIMAL(5, 2);

-- 1. Tính tổng số dòng và số dòng vi phạm quy tắc nghiệp vụ
SELECT 
    @total_rows = COUNT(*),
    @error_rows = COUNT(CASE 
        WHEN orders.order_delivered_customer_date < orders.order_purchase_timestamp THEN 1
        WHEN orders.order_approved_at < orders.order_purchase_timestamp THEN 1
        WHEN orders.order_status = 'delivered' AND orders.order_delivered_customer_date IS NULL THEN 1
        WHEN orders.order_status = 'canceled' AND orders.order_delivered_customer_date IS NOT NULL THEN 1
        ELSE NULL 
    END)
FROM dbo.olist_orders_dataset orders;

-- 2. Tính tỷ lệ phần trăm lỗi
SET @error_rate = CAST(@error_rows AS FLOAT) * 100.0 / NULLIF(@total_rows, 0);

PRINT CONCAT(N'=== KIỂM TRA CIRCUIT BREAKER ===');
PRINT CONCAT(N'Tổng số đơn: ', @total_rows, N' | Số đơn vi phạm: ', @error_rows, N' | Tỷ lệ lỗi: ', @error_rate, N'%');

-- 3. Ngắt mạch nếu tỷ lệ lỗi vượt ngưỡng 2%
IF @error_rate > 2.0
BEGIN
    PRINT N'[CRITICAL ERROR] Tỷ lệ dữ liệu lỗi vượt ngưỡng an toàn (> 2.0%)!';
    RAISERROR(N'[CIRCUIT BREAKER TRIGGERED] Pipeline bị dừng khẩn cấp để bảo vệ hệ thống!', 16, 1);
    RETURN;
END
ELSE
BEGIN
    PRINT CONCAT(N'[CIRCUIT BREAKER PASSED] Tỷ lệ lỗi trong giới hạn an toàn (', @error_rate, N'% <= 2.0%). Pipeline tiếp tục.');
END;


-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 7]: TỰ ĐỘNG HÓA KIỂM THỬ CHẤT LƯỢNG DỮ LIỆU CHUẨN PRODUCTION
-- ------------------------------------------------------------------------------------------

-- Câu 2.7.1:
-- Xây dựng một View tổng hợp kết quả kiểm tra chất lượng dữ liệu:
-- Tập hợp kết quả kiểm tra của cả 5 trụ cột chất lượng (Tính đầy đủ, Tính duy nhất,
-- Tính hợp lệ miền giá trị, Toàn vẹn tham chiếu, và Quy tắc nghiệp vụ) trên cùng một bảng báo cáo duy nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.1 TẠI ĐÂY:

GO
CREATE OR ALTER VIEW dbo.vw_data_quality_summary AS
-- 1. Completeness (Tính đầy đủ): Kiểm tra các trường khóa và trạng thái bắt buộc
SELECT 
    N'Completeness' AS dimension_name,
    N'Check Mandatory Nulls in Orders' AS test_name,
    N'dbo.olist_orders_dataset' AS target_table,
    COUNT(CASE 
        WHEN order_id IS NULL OR customer_id IS NULL OR order_status IS NULL OR order_purchase_timestamp IS NULL 
        THEN 1 
    END) AS failed_records,
    CASE 
        WHEN COUNT(CASE WHEN order_id IS NULL OR customer_id IS NULL OR order_status IS NULL OR order_purchase_timestamp IS NULL THEN 1 END) = 0 
        THEN 'PASS' ELSE 'FAIL' 
    END AS test_status
FROM dbo.olist_orders_dataset

UNION ALL

-- 2. Uniqueness (Tính duy nhất): Kiểm tra trùng lặp khóa chính review_id
SELECT 
    N'Uniqueness' AS dimension_name,
    N'Check Duplicate Review ID' AS test_name,
    N'dbo.olist_order_reviews_dataset' AS target_table,
    COUNT(*) AS failed_records,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS test_status
FROM (
    SELECT review_id
    FROM dbo.olist_order_reviews_dataset
    GROUP BY review_id
    HAVING COUNT(*) > 1
) dup_reviews

UNION ALL

-- 3. Validity (Tính hợp lệ): Kiểm tra giá bán và cước vận chuyển bất hợp lý
SELECT 
    N'Validity' AS dimension_name,
    N'Check Invalid Price or Freight' AS test_name,
    N'dbo.olist_order_items_dataset' AS target_table,
    COUNT(CASE WHEN price <= 0 OR freight_value < 0 THEN 1 END) AS failed_records,
    CASE WHEN COUNT(CASE WHEN price <= 0 OR freight_value < 0 THEN 1 END) = 0 THEN 'PASS' ELSE 'FAIL' END AS test_status
FROM dbo.olist_order_items_dataset

UNION ALL

-- 4. Referential Integrity (Toàn vẹn tham chiếu): Kiểm tra sản phẩm mồ côi
SELECT 
    N'Referential Integrity' AS dimension_name,
    N'Check Orphan Products in Items' AS test_name,
    N'dbo.olist_order_items_dataset' AS target_table,
    COUNT(*) AS failed_records,
    CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END AS test_status
FROM dbo.olist_order_items_dataset items
WHERE NOT EXISTS (
    SELECT 1 
    FROM dbo.olist_products_dataset products 
    WHERE products.product_id = items.product_id
)

UNION ALL

-- 5. Business Rules (Quy tắc logic nghiệp vụ): Kiểm tra mâu thuẫn thời gian và trạng thái
SELECT 
    N'Business Rules' AS dimension_name,
    N'Check Temporal and Status Logic Violations' AS test_name,
    N'dbo.olist_orders_dataset' AS target_table,
    COUNT(CASE 
        WHEN order_delivered_customer_date < order_purchase_timestamp THEN 1
        WHEN order_approved_at < order_purchase_timestamp THEN 1
        WHEN order_status = 'delivered' AND order_delivered_customer_date IS NULL THEN 1
        WHEN order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL THEN 1
        ELSE NULL 
    END) AS failed_records,
    CASE 
        WHEN COUNT(CASE 
            WHEN order_delivered_customer_date < order_purchase_timestamp THEN 1
            WHEN order_approved_at < order_purchase_timestamp THEN 1
            WHEN order_status = 'delivered' AND order_delivered_customer_date IS NULL THEN 1
            WHEN order_status = 'canceled' AND order_delivered_customer_date IS NOT NULL THEN 1
            ELSE NULL 
        END) = 0 THEN 'PASS' ELSE 'FAIL' 
    END AS test_status
FROM dbo.olist_orders_dataset;
GO

SELECT * FROM dbo.vw_data_quality_summary;


-- ------------------------------------------------------------------------------------------
-- Câu 2.7.2:
-- Thiết kế một bảng nhật ký kiểm thử chất lượng dữ liệu (Audit Log Table) để ghi lại kết quả
-- của các bài kiểm tra mỗi khi pipeline vận hành (tên bài test, đối tượng kiểm tra, số dòng lỗi, trạng thái Pass/Fail).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.2 TẠI ĐÂY:

-- 1. Thiết kế bảng Audit Log lưu lịch sử kiểm thử
IF OBJECT_ID('dbo.data_quality_audit_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.data_quality_audit_log (
        log_id INT IDENTITY(1,1) PRIMARY KEY,
        batch_id UNIQUEIDENTIFIER NOT NULL DEFAULT NEWID(),
        executed_at DATETIME NOT NULL DEFAULT GETDATE(),
        dimension_name NVARCHAR(50) NOT NULL,
        test_name NVARCHAR(100) NOT NULL,
        target_table NVARCHAR(100) NOT NULL,
        failed_records INT NOT NULL,
        test_status VARCHAR(10) NOT NULL,              -- 'PASS' hoặc 'FAIL'
        severity_level VARCHAR(20) DEFAULT 'CRITICAL', -- 'CRITICAL', 'WARNING'
        execution_notes NVARCHAR(255) NULL
    );
END;

-- 2. Ghi nhận nhật ký cho một đợt vận hành pipeline
DECLARE @test_batch_id UNIQUEIDENTIFIER = NEWID();

INSERT INTO dbo.data_quality_audit_log (
    batch_id,
    executed_at,
    dimension_name,
    test_name,
    target_table,
    failed_records,
    test_status,
    severity_level,
    execution_notes
)
SELECT 
    @test_batch_id AS batch_id,
    GETDATE() AS executed_at,
    dimension_name,
    test_name,
    target_table,
    failed_records,
    test_status,
    'CRITICAL' AS severity_level,
    CASE 
        WHEN test_status = 'PASS' THEN N'Kiểm thử thành công (0 bản ghi lỗi)'
        ELSE CONCAT(N'Thất bại: Phát hiện ', failed_records, N' bản ghi không hợp lệ')
    END AS execution_notes
FROM dbo.vw_data_quality_summary;

SELECT * FROM dbo.data_quality_audit_log ORDER BY log_id DESC;


-- ------------------------------------------------------------------------------------------
-- Câu 2.7.3:
-- Đóng gói toàn bộ bộ kiểm thử chất lượng dữ liệu thành một Stored Procedure chạy tự động:
-- Tự động thực thi tất cả các bài kiểm tra chất lượng, ghi nhận lịch sử vào bảng nhật ký,
-- và ném ra ngoại lệ dừng pipeline ngay lập tức nếu phát hiện bài test ở mức độ nghiêm trọng bị thất bại.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.3 TẠI ĐÂY:

GO
CREATE OR ALTER PROCEDURE dbo.usp_Run_Data_Quality_TestSuite
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @batch_id UNIQUEIDENTIFIER = NEWID();
    DECLARE @executed_at DATETIME = GETDATE();
    DECLARE @critical_failures INT = 0;
    
    PRINT CONCAT(N'=== BẮT ĐẦU CHẠY SUITE KIỂM THỬ CHẤT LƯỢNG DỮ LIỆU [BATCH: ', @batch_id, '] ===');
    
    -- 1. Tự động thực thi và ghi nhận lịch sử vào bảng Audit Log
    INSERT INTO dbo.data_quality_audit_log (
        batch_id,
        executed_at,
        dimension_name,
        test_name,
        target_table,
        failed_records,
        test_status,
        severity_level,
        execution_notes
    )
    SELECT 
        @batch_id,
        @executed_at,
        dimension_name,
        test_name,
        target_table,
        failed_records,
        test_status,
        'CRITICAL' AS severity_level,
        CASE 
            WHEN test_status = 'PASS' THEN N'Passed Data Quality Check'
            ELSE CONCAT(N'FAILED: Có ', failed_records, N' dòng lỗi')
        END
    FROM dbo.vw_data_quality_summary;
    
    -- 2. Kiểm tra xem có bài test nghiêm trọng nào bị FAIL không
    SELECT @critical_failures = COUNT(*)
    FROM dbo.data_quality_audit_log
    WHERE batch_id = @batch_id
      AND test_status = 'FAIL'
      AND severity_level = 'CRITICAL';
      
    -- 3. Ném ngoại lệ chặn pipeline nếu phát hiện lỗi nghiêm trọng
    IF @critical_failures > 0
    BEGIN
        DECLARE @error_msg NVARCHAR(500) = CONCAT(
            N'[DATA QUALITY GATEWAY FAILED] Phát hiện ', 
            @critical_failures, 
            N' bài test nghiêm trọng bị thất bại! Tiến trình Pipeline bị dừng khẩn cấp.'
        );
        PRINT @error_msg;
        THROW 51000, @error_msg, 1;
    END
    ELSE
    BEGIN
        PRINT N'[DATA QUALITY GATEWAY PASSED] Toàn bộ 5 trụ cột chất lượng đều đạt chuẩn! Pipeline tiếp tục vận hành.';
    END
END;
GO

-- Chạy thử nghiệm Stored Procedure kiểm thử
-- EXEC dbo.usp_Run_Data_Quality_TestSuite;
