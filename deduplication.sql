-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 2: XỬ LÝ DỮ LIỆU NÂNG CAO & ANALYTICAL SQL (ADVANCED DATA PIPELINE & ANALYTICAL SQL)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 1: DEDUPLICATION (KHỬ TRÙNG LẶP DỮ LIỆU)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 1]: LẤY BẢN GHI MỚI NHẤT & BẢN GHI ĐẦU TIÊN
-- ------------------------------------------------------------------------------------------

-- Câu 1.1.1:
-- Chứng minh sự khác biệt và rủi ro giữa các hàm xếp hạng khi thực hiện khử trùng lặp dữ liệu:
-- Xây dựng một kịch bản dữ liệu có các bản ghi trùng nhau hoàn toàn về mốc thời gian cập nhật.
-- Chỉ ra hàm xếp hạng nào sẽ loại bỏ triệt để bản ghi trùng, và hàm nào vẫn để lọt dữ liệu trùng lặp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1.1 TẠI ĐÂY:

with handle_duplicate as (
    select 
        o.order_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        row_number() over(partition by o.order_id order by o.order_approved_at desc) as rn
    from dbo.olist_orders_dataset o
)
select 
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
from handle_duplicate
where rn = 1;

with handle_duplicate as (
    select 
        o.order_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        dense_rank() over(partition by o.order_id order by o.order_approved_at desc) as dr
    from dbo.olist_orders_dataset o
)
select 
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
from handle_duplicate
where dr = 1;

with mock_orders as (
    SELECT 'O_001' AS order_id, 'delivered' AS order_status, CAST('2023-01-01 10:00:00' AS DATETIME) AS order_approved_at
    UNION ALL
    SELECT 'O_001' AS order_id, 'delivered' AS order_status, CAST('2023-01-01 10:00:00' AS DATETIME) AS order_approved_at
    UNION ALL
    SELECT 'O_002' AS order_id, 'shipped'   AS order_status, CAST('2023-01-02 15:30:00' AS DATETIME) AS order_approved_at
),
ranking_demo as (
    select 
        mo.order_id,
        mo.order_status,
        mo.order_approved_at,
        row_number() over(partition by mo.order_id order by mo.order_approved_at desc) as rn,
        dense_rank() over(partition by mo.order_id order by mo.order_approved_at desc) as dr,
        rank() over(partition by mo.order_id order by mo.order_approved_at desc) as rk
    from mock_orders mo
)
select * from ranking_demo 

-- KẾT LUẬN & CHỨNG MINH RỦI RO:
-- 1. ROW_NUMBER(): Luôn sinh ra giá trị duy nhất (1, 2) dù thời gian trùng nhau.
--    => Lọc `WHERE rn = 1` sẽ LOẠI BỎ TRIỆT ĐỂ bản ghi trùng lặp (chỉ giữ đúng 1 bản ghi).
--
-- 2. RANK() & DENSE_RANK(): Khi thời gian trùng nhau hoàn toàn, cả 2 bản ghi đều nhận hạng 1.
--    => Lọc `WHERE dr = 1` hoặc `WHERE rk = 1` VẪN ĐỂ LỌT CẢ 2 BẢN GHI (thất bại trong việc khử trùng lặp).


-- ------------------------------------------------------------------------------------------
-- Câu 1.1.2:
-- Một đơn hàng có thể nhận được nhiều lần đánh giá từ khách hàng.
-- Hãy viết truy vấn trích xuất nội dung đánh giá của các đơn hàng sao cho mỗi đơn hàng
-- chỉ lấy DUY NHẤT một bản ghi phản hồi cuối cùng gần đây nhất của khách hàng đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1.2 TẠI ĐÂY:

;with review_rank as (
    select 
        o.order_id,
        r.review_id,
        r.review_score,
        r.review_comment_title,
        r.review_comment_message,
        r.review_creation_date,
        r.review_answer_timestamp,
        row_number() over(partition by o.order_id order by r.review_answer_timestamp desc, r.review_creation_date desc) as rn
    from dbo.olist_orders_dataset o
    inner join dbo.olist_order_reviews_dataset r on o.order_id = r.order_id
)
select 
    r.order_id,
    r.review_id,
    r.review_score,
    r.review_comment_title,
    r.review_comment_message,
    r.review_creation_date,
    r.review_answer_timestamp
from review_rank r
where r.rn = 1;


-- ------------------------------------------------------------------------------------------
-- Câu 1.1.3:
-- Để phục vụ chiến dịch phân tích kênh thu hút khách hàng mới (Customer Acquisition),
-- hãy tìm đơn đặt hàng ĐẦU TIÊN trong lịch sử của từng khách hàng thực tế.
-- Đảm bảo mỗi khách hàng duy nhất chỉ xuất hiện đúng một dòng đại diện cho giao dịch đầu tiên.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1.3 TẠI ĐÂY:


with find_first_customer as (
    select 
        c.customer_unique_id,
        o.customer_id,
        o.order_id,
        o.order_purchase_timestamp,
        row_number() over(partition by c.customer_unique_id order by o.order_purchase_timestamp asc) as rn
    from dbo.olist_customers_dataset c 
    inner join dbo.olist_orders_dataset o on c.customer_id = o.customer_id
)
select 
    ffc.customer_unique_id,
    ffc.customer_id,
    ffc.order_id,
    ffc.order_purchase_timestamp
from find_first_customer ffc
where ffc.rn = 1;


-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 2]: PHÁT HIỆN VÀ ĐO LƯỜNG MỨC ĐỘ TRÙNG LẶP DỮ LIỆU
-- ------------------------------------------------------------------------------------------

-- Câu 1.2.1:
-- Quét toàn bộ bảng đánh giá để tìm các mã đơn hàng bị xuất hiện từ 2 lần trở lên.
-- Cho biết số lần xuất hiện, điểm đánh giá cao nhất, điểm thấp nhất, và cờ đánh dấu
-- đơn hàng đó có bị khách hàng thay đổi điểm số qua các lần đánh giá hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2.1 TẠI ĐÂY:

with table_review as (
    select
        r.order_id,
        count(*) as review_id_count,
        min(r.review_score) as min_review_score,
        max(r.review_score) as max_review_score,
        case 
            when min(r.review_score) <> max(r.review_score) then 1
            else 0
        end as is_rating_changed
    from dbo.olist_order_reviews_dataset r
    group by r.order_id
    having count(*) > 1
)
select *
from table_review;


-- ------------------------------------------------------------------------------------------
-- Câu 1.2.2:
-- Tìm các bản ghi bị trùng lặp toàn phần (tất cả các cột dữ liệu đều giống hệt nhau)
-- trong bảng Geolocation và thống kê số lần bị nhân bản của các bản ghi đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2.2 TẠI ĐÂY:
with table_geolocation as (
    select 
        g.geolocation_zip_code_prefix,
        g.geolocation_city,
        g.geolocation_state,
        count(*) as geolocation_count
    from dbo.olist_geolocation_dataset g
    group by 
        g.geolocation_zip_code_prefix,
        g.geolocation_city,
        g.geolocation_state
    having count(*) > 1
)
select *
from table_geolocation;

-- ------------------------------------------------------------------------------------------
-- Câu 1.2.3:
-- Viết một truy vấn kiểm toán chất lượng dữ liệu (Data Profiling Audit) cho bảng đánh giá:
-- Tính tổng số dòng hiện có, số lượng đơn hàng duy nhất, số dòng rác bị dư thừa cần loại bỏ,
-- và tỷ lệ phần trăm dữ liệu trùng lặp của toàn bảng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2.3 TẠI ĐÂY:

with table_profiling as (
    select 
        count(*) as total_rows,
        count(distinct r.review_id) as unique_rows,
        count(*) - count(distinct r.review_id) as duplicate_rows,
        cast((count(*) - count(distinct r.review_id)) * 100.0 / count(*) as decimal(5,2)) as duplicate_percentage
    from dbo.olist_order_reviews_dataset r
)
select * from table_profiling;
 
-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 3]: XÓA DỮ LIỆU TRÙNG VẬT LÝ VÀ NẠP DỮ LIỆU SẠCH
-- ------------------------------------------------------------------------------------------

-- Câu 1.3.1:
-- Viết câu lệnh xóa trực tiếp các bản ghi trùng lặp vật lý ra khỏi một bảng dữ liệu tạm,
-- sao cho với mỗi đơn hàng chỉ giữ lại duy nhất bản ghi đánh giá mới nhất,
-- toàn bộ các bản ghi lịch sử cũ hơn đều bị xóa hoàn toàn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3.1 TẠI ĐÂY:
drop table if exists #temp_order_reviews;

select *
into #temp_order_reviews
from dbo.olist_order_reviews_dataset;

select *
from #temp_order_reviews;

with cte_dup as (
    select 
        r.order_id,
        r.review_id,
        r.review_score,
        r.review_comment_title,
        r.review_comment_message,
        r.review_creation_date,
        r.review_answer_timestamp,
        row_number() over(partition by r.order_id order by r.review_answer_timestamp desc) as rn
    from #temp_order_reviews r
)
delete
from cte_dup
where rn > 1;


select 
    o.order_id,
    count(*) as duplicate_count
from #temp_order_reviews o
group by o.order_id
having count(*) > 1;

-- ------------------------------------------------------------------------------------------
-- Câu 1.3.2:
-- Phân tích và chứng minh lý do tại sao từ khóa DISTINCT bị vô hiệu hóa trong việc khử trùng lặp
-- khi dữ liệu nguồn có phát sinh các cột kỹ thuật (như mã lô nạp dữ liệu batch_id hoặc thời điểm ingest khác nhau).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3.2 TẠI ĐÂY:

-- 1. XÂY DỰNG KỊCH BẢN DỮ LIỆU NẠP (MOCK INGESTION DATA):
-- Cùng một đơn hàng O_001 được nạp 2 lần ở 2 batch khác nhau và mốc thời gian khác nhau.
with mock_ingested_reviews as (
    select 
        'R_001' as review_id,
        'O_001' as order_id,
        5 as review_score,
        'BATCH_101' as batch_id,
        cast('2023-10-01 08:00:00' as datetime) as ingested_at
    union all
    select 
        'R_001' as review_id,
        'O_001' as order_id,
        5 as review_score,
        'BATCH_102' as batch_id,
        cast('2023-10-01 12:00:00' as datetime) as ingested_at
    union all
    select 
        'R_002' as review_id,
        'O_002' as order_id,
        4 as review_score,
        'BATCH_101' as batch_id,
        cast('2023-10-01 08:00:00' as datetime) as ingested_at
)
-- 2. CHỨNG MINH DISTINCT BỊ VÔ HIỆU HÓA:
-- Dù thông tin nghiệp vụ (review_id, order_id, review_score) hoàn toàn trùng lặp ở O_001,
-- nhưng vì có cột kỹ thuật (batch_id, ingested_at) khác nhau, DISTINCT vẫn trả về cả 2 dòng!
select distinct 
    review_id,
    order_id,
    review_score,
    batch_id,
    ingested_at
from mock_ingested_reviews;


-- 3. GIẢI PHÁP THAY THẾ CHUẨN TRONG DATA ENGINEERING (ROW_NUMBER):
with mock_ingested_reviews as (
    select 
        'R_001' as review_id,
        'O_001' as order_id,
        5 as review_score,
        'BATCH_101' as batch_id,
        cast('2023-10-01 08:00:00' as datetime) as ingested_at
    union all
    select 
        'R_001' as review_id,
        'O_001' as order_id,
        5 as review_score,
        'BATCH_102' as batch_id,
        cast('2023-10-01 12:00:00' as datetime) as ingested_at
    union all
    select 
        'R_002' as review_id,
        'O_002' as order_id,
        4 as review_score,
        'BATCH_101' as batch_id,
        cast('2023-10-01 08:00:00' as datetime) as ingested_at
),
dedup_pipeline as (
    select 
        review_id,
        order_id,
        review_score,
        batch_id,
        ingested_at,
        row_number() over(
            partition by order_id 
            order by ingested_at desc
        ) as rn
    from mock_ingested_reviews
)
select 
    review_id,
    order_id,
    review_score,
    batch_id,
    ingested_at
from dedup_pipeline
where rn = 1;

-- ==========================================================================================
-- PHÂN TÍCH VÀ KẾT LUẬN LÝ THUYẾT:
-- 1. Nguyên lý của DISTINCT:
--    - DISTINCT hoạt động trên TOÀN BỘ tổ hợp cột được chọn trong mệnh đề SELECT.
--    - Nó chỉ gộp dòng khi 100% tất cả các cột đều có giá trị giống hệt nhau.
--
-- 2. Lý do DISTINCT bị vô hiệu hóa:
--    - Trong Data Pipeline thực tế, các bảng Raw/Staging thường có cột kỹ thuật (Metadata / Audit Columns)
--      như: batch_id, ingested_at, file_source_name,...
--    - Khi nạp lại (re-ingest / retry), dù dữ liệu nghiệp vụ (order_id) bị trùng lặp,
--      nhưng các cột kỹ thuật mang giá trị khác nhau (khác mã lô batch, khác thời điểm nạp).
--    - Do đó, đối với SQL Server, các dòng này là hoàn toàn "khác biệt" (Distinct),
--      khiến từ khóa DISTINCT bị vô hiệu hóa hoàn toàn và không khử được trùng lặp.
--
-- 3. Giải pháp chuẩn trong Data Engineering:
--    - Bắt buộc dùng Window Function ROW_NUMBER():
--      + PARTITION BY theo khóa nghiệp vụ (Business Key: order_id).
--      + ORDER BY theo mốc thời gian kỹ thuật (Technical Timestamp: ingested_at DESC).
--      + Lọc WHERE rn = 1 để lấy bản ghi mới nhất của đợt nạp gần nhất.
-- ==========================================================================================
-- ------------------------------------------------------------------------------------------
-- Câu 1.3.3:
-- Thay vì xóa vật lý, hãy viết câu lệnh trích xuất và nạp dữ liệu sạch (Clean Ingestion)
-- từ bảng khách hàng sang bảng Dimension đích sao cho mỗi khách hàng duy nhất
-- chỉ được đưa vào đúng một bản ghi thông tin mới nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3.3 TẠI ĐÂY:

drop table if exists #temp_customer;

select *
into #temp_customer
from dbo.olist_customers_dataset;

select 
    count(*) as total_records
from #temp_customer;

drop table if exists dbo.dim_customer;

with clean_customer as (
    select 
        customer_id,
        customer_unique_id,
        customer_zip_code_prefix,
        customer_city,
        customer_state,
        row_number() over(
            partition by customer_unique_id 
            order by order_purchase_timestamp desc
        ) as rn 
    from #temp_customer t
)
select 
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
into dbo.dim_customer
from clean_customer
where rn = 1;

select 
    count(*) as total_records
from dbo.dim_customer;


-- ==========================================================================================
-- GHI CHÚ CÁC LỖI SAI TRONG CÂU QUERY TRÊN:
-- 1. Lỗi Invalid column name 'order_purchase_timestamp':
--    Bảng #temp_customer (sao chép từ olist_customers_dataset) không có cột order_purchase_timestamp.
--    Cột này nằm ở bảng olist_orders_dataset nên bắt buộc phải INNER JOIN với olist_orders_dataset qua customer_id.
--
-- 2. Lỗi PARTITION BY lúc đầu (PARTITION BY customer_id):
--    customer_id là mã của mỗi lần đặt hàng (vốn đã duy nhất trên từng dòng), nên nếu gom nhóm theo nó thì
--    rn luôn bằng 1, kết quả bảng dim_customer vẫn giữ nguyên 99,441 dòng (không khử trùng được khách hàng).
--    Cần PARTITION BY customer_unique_id (mã định danh người mua thực tế, có khoảng 96,096 khách hàng).
--
-- 3. Tạo bảng tạm #temp_customer là bước thừa:
--    Với Clean Ingestion, dữ liệu được trích xuất và lọc trực tiếp từ bảng nguồn sang bảng Dimension,
--    không cần tốn tài nguyên sao chép sang bảng tạm #temp_customer.
-- ==========================================================================================


-- CÂU QUERY HOÀN THIỆN:

drop table if exists dbo.dim_customer;

with clean_customer as (
    select 
        c.customer_unique_id,
        c.customer_id,
        c.customer_zip_code_prefix,
        c.customer_city,
        c.customer_state,
        o.order_purchase_timestamp,
        row_number() over(
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp desc
        ) as rn 
    from dbo.olist_customers_dataset c
    inner join dbo.olist_orders_dataset o on c.customer_id = o.customer_id
)
select 
    customer_unique_id,
    customer_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state,
    order_purchase_timestamp as latest_order_timestamp
into dbo.dim_customer
from clean_customer
where rn = 1;

select count(*) as total_unique_customers from dbo.dim_customer;




-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 4]: KHỬ TRÙNG ĐA THUỘC TÍNH VÀ TIÊU CHÍ ƯU TIÊN CHẤT LƯỢNG
-- ------------------------------------------------------------------------------------------

-- Câu 1.4.1:
-- Trong một đơn hàng, một người bán có thể cung cấp nhiều mặt hàng khác nhau.
-- Hãy viết truy vấn khử trùng lặp ở cấp độ Người bán - Đơn hàng:
-- Với mỗi cặp Đơn hàng và Người bán, chỉ giữ lại duy nhất một mặt hàng có giá trị cao nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.4.1 TẠI ĐÂY:

with cte_dup as (
    select 
        oi.order_id,
        s.seller_id,
        oi.price,
        s.seller_city,
        s.seller_state,
        row_number() over(partition by oi.order_id,s.seller_id order by oi.price desc) as rn 
    from dbo.olist_order_items_dataset oi  
    inner join dbo.olist_sellers_dataset s on oi.seller_id = s.seller_id
)
select *
from cte_dup
where rn = 1;


-- ------------------------------------------------------------------------------------------
-- Câu 1.4.2:
-- Xây dựng cơ chế khử trùng lặp có tiêu chí ưu tiên chất lượng bản ghi (Quality Tie-Breaker):
-- Khi khử trùng dữ liệu đánh giá, nếu có các bản ghi trùng cùng thời điểm,
-- hãy ưu tiên giữ lại bản ghi có đầy đủ lời nhận xét của khách, kế đến là bản ghi có điểm đánh giá cao hơn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.4.2 TẠI ĐÂY:

with table_review as (
    select 
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_comment_message,
        r.review_comment_title,
        r.review_answer_timestamp,
        case
            when r.review_comment_message is not null and len(trim(r.review_comment_message)) > 0 then 1
            else 0
        end as has_message,
        case 
            when r.review_comment_title is not null and len(trim(r.review_comment_title)) > 0 then 1
            else 0
        end as has_title
    from dbo.olist_order_reviews_dataset r
),
quality_tie_breaker as (
    select 
        tr.*,
        row_number() over(
            partition by tr.order_id
            order by  tr.review_answer_timestamp desc,
                tr.has_message desc,
                tr.has_title desc,
                tr.review_score desc
        ) as rn
    from table_review tr
)
select * from quality_tie_breaker where rn = 1;



-- ------------------------------------------------------------------------------------------
-- Câu 1.4.3:
-- Một mã bưu chính có thể có nhiều cách gõ tên thành phố khác nhau do sai sót nhập liệu.
-- Hãy viết truy vấn tự động chọn ra tên thành phố chuẩn nhất cho từng mã bưu chính
-- dựa trên nguyên tắc: tên thành phố nào xuất hiện với tần suất nhiều nhất sẽ được giữ lại.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.4.3 TẠI ĐÂY:

with city_count as (
    select 
        c.customer_zip_code_prefix,
        c.customer_city,
        count(*) as city_frequency 
    from dbo.olist_customers_dataset c
    group by c.customer_zip_code_prefix,
        c.customer_city
),
rank_city as (
    select 
        cc.*,
        row_number() over(
            partition by cc.customer_zip_code_prefix
            order by cc.num_orders desc
        ) as rn
    from city_count cc
)
select * from rank_city where rn = 1;



-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 5]: QUẢN LÝ PHIÊN BẢN & THEO DÕI LỊCH SỬ THAY ĐỔI
-- ------------------------------------------------------------------------------------------

-- Câu 1.5.1:
-- Tự động đánh số thứ tự phiên bản (Version 1, Version 2, ...) cho lịch sử mua sắm
-- của từng khách hàng theo trình tự thời gian đặt đơn.
-- Lọc ra danh sách các khách hàng thân thiết đã có từ 3 phiên bản giao dịch trở lên.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.5.1 TẠI ĐÂY:

with table_customer_order as (
    select 
        customers.customer_unique_id,
        customers.customer_city,
        customers.customer_state,
        orders.order_purchase_timestamp, 
        concat('Version ',row_number() over(
            partition by customers.customer_unique_id 
            order by orders.order_purchase_timestamp asc
        )) as order_version 
    from dbo.olist_orders_dataset orders 
    inner join dbo.olist_customers_dataset customers on orders.customer_id = customers.customer_id
)
select 
    customer_unique_id
from table_customer_order
group by customer_unique_id
having count(order_version) >= 3;



-- ------------------------------------------------------------------------------------------
-- Câu 1.5.2:
-- So sánh dữ liệu giữa phiên bản hiện tại và phiên bản liền trước của từng khách hàng:
-- Phát hiện xem khách hàng có sự thay đổi về địa chỉ thành phố sinh sống giữa các lần mua hàng hay không
-- và gắn cờ cảnh báo đối với các khách hàng đã từng chuyển chỗ ở.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.5.2 TẠI ĐÂY:

with table_customer_order as (
    select 
        customers.customer_unique_id,
        customers.customer_city,
        customers.customer_state,
        orders.order_purchase_timestamp,
        lag(customers.customer_city,1) over (
            partition by customers.customer_unique_id
            order by orders.order_purchase_timestamp asc
        ) as prev_customer_city
    from dbo.olist_orders_dataset orders
    inner join dbo.olist_customers_dataset customers on orders.customer_id = customers.customer_id 
),compare_city as (
    select 
        tco.customer_unique_id,
        tco.customer_city,
        tco.order_purchase_timestamp, 
        tco.prev_customer_city,
        case
            when prev_customer_city is not null and tco.customer_city != tco.prev_customer_city then 1
            else 0
        end as has_moved
    from table_customer_order tco
)
select 
    cc.* 
from compare_city cc
where cc.has_moved = 1


-- ------------------------------------------------------------------------------------------
-- Câu 1.5.3:
-- Xuất báo cáo so sánh hành trình của khách hàng trên cùng một dòng kết quả:
-- Hiển thị thông tin địa điểm của đơn hàng đầu tiên (First State) song song với
-- thông tin địa điểm của đơn hàng gần đây nhất (Latest State) cho từng khách hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.5.3 TẠI ĐÂY:

with table_customer_order as (
    select  
        customers.customer_unique_id,
        customers.customer_city,
        customers.customer_state,
        orders.order_purchase_timestamp,
        first_value(customers.customer_state) over(
            partition by customers.customer_unique_id 
            order by orders.order_purchase_timestamp desc) as first_state,
        last_value(customers.customer_state) over(
            partition by customers.customer_unique_id 
            order by orders.order_purchase_timestamp asc
            rows between unbounded preceding and unbounded following
        ) as last_state 
    from dbo.olist_orders_dataset orders 
    inner join dbo.olist_customers_dataset customers on orders.customer_id = customers.customer_id
)
select distinct 
    tco.customer_unique_id,
    tco.first_state,
    tco.last_state 
from table_customer_order tco



-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 6]: QUẢN LÝ THAY ĐỔI THEO DẠNG CHIỀU SCD (SLOWLY CHANGING DIMENSIONS)
-- ------------------------------------------------------------------------------------------

-- Câu 1.6.1:
-- Triển khai mô hình SCD Type 1: Xây dựng một View danh mục khách hàng luôn luôn phản ánh
-- thông tin địa chỉ mới nhất hiện tại của từng khách hàng duy nhất (ghi đè lịch sử cũ).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.6.1 TẠI ĐÂY:

create or alter view scd_type1_customer_view as 
with scd_type1 as (
select 
    customers.customer_unique_id,
    customers.customer_city,
    customers.customer_state,
    row_number() over(partition by customers.customer_unique_id order by orders.order_purchase_timestamp desc) as rn
from dbo.olist_customers_dataset customers 
inner join dbo.olist_orders_dataset orders on orders.customer_id = customers.customer_id
)
select 
    st.customer_unique_id,
    st.customer_city,
    st.customer_state
from scd_type1 st 
where st.rn = 1;

select *
from dbo.scd_type1_customer_view;

-- GHI CHÚ KIẾN THỨC SCD TYPE 1:
-- 1. Bản chất: Ghi đè (Overwrite) - luôn chỉ phản ánh trạng thái mới nhất, bỏ qua toàn bộ lịch sử cũ.
-- 2. Đặc điểm kết quả: Mỗi khách hàng (customer_unique_id) chỉ có DUY NHẤT 1 dòng đại diện.
-- 3. Kỹ thuật SQL: Dùng ROW_NUMBER() PARTITION BY customer_unique_id ORDER BY timestamp DESC và lọc rn = 1.
-- 4. Ưu / Nhược điểm: Bảng gọn nhẹ, truy vấn nhanh; nhưng mất hoàn toàn dấu vết lịch sử trong quá khứ.



-- ------------------------------------------------------------------------------------------
-- Câu 1.6.2:
-- Triển khai mô hình SCD Type 2: Từ lịch sử thay đổi của khách hàng, hãy xây dựng bảng lịch sử
-- có đầy đủ các trường quản lý hiệu lực theo thời gian: ngày bắt đầu hiệu lực, ngày hết hiệu lực,
-- và cờ đánh dấu bản ghi đó có đang là trạng thái hiệu lực hiện hành hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.6.2 TẠI ĐÂY:
create or alter view scd_type2_customers_view as 
with scd_type2 as (
    select 
        customers.customer_unique_id,
        customers.customer_city,
        customers.customer_state,
        orders.order_purchase_timestamp as start_date,
        LEAD(orders.order_purchase_timestamp, 1) OVER (
            PARTITION BY customers.customer_unique_id 
            ORDER BY orders.order_purchase_timestamp ASC
        ) AS end_date
    from dbo.olist_orders_dataset orders 
    inner join dbo.olist_customers_dataset customers on orders.customer_id = customers.customer_id  
)
select 
    st.customer_unique_id,
    st.customer_city,
    st.customer_state,
    st.start_date,
    st.end_date,
    case
        when st.end_date is null then 1
        else 0
    end as 'is_current'
from scd_type2 st;

select 
    * 
from scd_type2_customers_view;

-- GHI CHÚ KIẾN THỨC SCD TYPE 2:
-- 1. Bản chất: Thêm dòng mới (Add New Row) - lưu trữ trọn vẹn toàn bộ lịch sử thay đổi theo trục thời gian.
-- 2. Đặc điểm kết quả: Một khách hàng có thể có NHIỀU dòng (mỗi dòng tương ứng một khoảng thời gian hiệu lực).
-- 3. Bộ 3 cột quản lý hiệu lực cốt lõi:
--    - start_date : Thời điểm bắt đầu hiệu lực (mốc thời gian đặt đơn hiện tại).
--    - end_date   : Thời điểm hết hiệu lực (dùng LEAD() lấy mốc thời gian của đơn tiếp theo; bản ghi mới nhất là NULL).
--    - is_current : Cờ đánh dấu hiện hành (1 = thông tin mới nhất đang áp dụng ở hiện tại, 0 = lịch sử cũ đã hết hạn).
-- 4. Ứng dụng: Nền tảng phục vụ truy vấn Point-in-Time (xác định chính xác thông tin khách hàng tại bất kỳ thời điểm nào trong quá khứ). 


-- ------------------------------------------------------------------------------------------
-- Câu 1.6.3:
-- Viết truy vấn Point-in-Time: Xác định chính xác trạng thái thông tin của khách hàng
-- tại một mốc thời điểm cụ thể trong quá khứ dựa trên cấu trúc bảng SCD Type 2 vừa tạo ở Câu 1.6.2.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.6.3 TẠI ĐÂY:
declare @target_date datetime = '2017-10-01';

select 
    st.* 
from scd_type2_customers_view st
where 
    st.start_date <= @target_date
    and (st.end_date > @target_date or st.end_date is null); 

-- GHI CHÚ KIẾN THỨC POINT-IN-TIME (TRUY VẤN THỜI ĐIỂM QUÁ KHỨ):
-- 1. Bản chất: Tái hiện lại chính xác trạng thái dữ liệu của đối tượng tại một mốc thời điểm T bất kỳ trong quá khứ.
-- 2. Công thức lọc chuẩn: Mốc thời gian T phải nằm trọn trong khoảng hiệu lực [start_date, end_date):
--    - start_date <= @target_date : Đảm bảo thông tin đã bắt đầu có hiệu lực trước hoặc đúng thời điểm T.
--    - end_date > @target_date OR end_date IS NULL : Đảm bảo thông tin chưa bị thay thế/hết hạn tại thời điểm T.
-- 3. Thực tế vận hành:
--    - Dùng biến (DECLARE @target_date) giúp query linh hoạt, dễ chuyển thành tham số trong Stored Procedure / Báo cáo.
--    - Tính duy nhất: Tại bất kỳ thời điểm T nào, mỗi khách hàng chỉ trả về đúng 1 dòng dữ liệu duy nhất. 


-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 7]: TỰ ĐỘNG HÓA PIPELINE DEDUPLICATION CHUẨN PRODUCTION
-- ------------------------------------------------------------------------------------------

-- Câu 1.7.1:
-- Xây dựng một quy trình nạp dữ liệu từ tầng Staging thô sang tầng Silver:
-- Tự động lọc sạch các bản ghi bị trùng do lỗi truyền tải mạng, chỉ lấy bản ghi cập nhật mới nhất,
-- loại bỏ các bản ghi không đạt chuẩn chất lượng và ghi vào bảng dữ liệu sạch.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.7.1 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.silver_orders;

WITH dedup_orders AS (
    SELECT 
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        ROW_NUMBER() OVER (
            PARTITION BY order_id 
            ORDER BY order_purchase_timestamp DESC, ISNULL(order_approved_at, order_purchase_timestamp) DESC
        ) AS rn
    FROM dbo.olist_orders_dataset
    WHERE order_id IS NOT NULL                   -- Loại bỏ bản ghi thiếu khóa chính
      AND customer_id IS NOT NULL               -- Loại bỏ bản ghi mồ côi khách hàng
      AND order_status IS NOT NULL              -- Loại bỏ bản ghi thiếu trạng thái
)
SELECT 
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    GETDATE() AS silver_ingested_at             -- Cột kỹ thuật audit thời điểm nạp vào Silver
INTO dbo.silver_orders
FROM dedup_orders
WHERE rn = 1;

-- Kiểm tra kết quả tầng Silver:
SELECT COUNT(*) AS total_silver_orders FROM dbo.silver_orders;

-- GHI CHÚ KIẾN THỨC PIPELINE STAGING -> SILVER:
-- 1. Tầng Staging (Bronze): Lưu trữ dữ liệu thô, chấp nhận chứa rác, trùng lặp do network retry.
-- 2. Tầng Silver: Dữ liệu sạch, được làm sạch qua 2 bước:
--    - Data Quality: Lọc WHERE để loại bỏ các trường khóa/bắt buộc bị NULL.
--    - Deduplication: Dùng ROW_NUMBER() PARTITION BY Business Key ORDER BY Timestamp DESC lấy rn = 1.
-- 3. Audit Column: Bổ sung các cột kỹ thuật (ví dụ silver_ingested_at) để theo dõi thời điểm nạp.


-- ------------------------------------------------------------------------------------------
-- Câu 1.7.2:
-- Viết câu lệnh nạp dữ liệu có tính chất Idempotent (chạy lại nhiều lần vẫn cho kết quả nhất quán):
-- Cập nhật dữ liệu mới cho các bản ghi đã tồn tại nếu có thông tin mới hơn,
-- và chèn mới các bản ghi chưa có, đảm bảo không bao giờ sinh ra dòng trùng lặp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.7.2 TẠI ĐÂY:

-- VIẾT QUERY CÂU 1.7.2 TẠI ĐÂY:
-- VIẾT QUERY CÂU 1.7.2 TẠI ĐÂY:
WITH source_staging AS (
    SELECT 
        order_id,
        customer_id,
        order_status,  
        order_purchase_timestamp, 
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        ROW_NUMBER() OVER (
            PARTITION BY order_id 
            ORDER BY 
                COALESCE(order_delivered_customer_date, order_delivered_carrier_date, order_approved_at, order_purchase_timestamp) DESC
        ) AS rn
    FROM dbo.olist_orders_dataset
    WHERE order_id IS NOT NULL 
)
MERGE INTO dbo.silver_orders AS target
USING (
    SELECT 
        order_id,
        customer_id,
        order_status,  
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date
    FROM source_staging 
    WHERE rn = 1
) AS source
ON target.order_id = source.order_id 

-- 1. Nếu bản ghi đã tồn tại và có thông tin trạng thái / ngày giao hàng mới hơn -> CẬP NHẬT
WHEN MATCHED AND (
    ISNULL(target.order_status, '') <> ISNULL(source.order_status, '')
    OR ISNULL(target.order_approved_at, '1900-01-01') <> ISNULL(source.order_approved_at, '1900-01-01')
    OR ISNULL(target.order_delivered_carrier_date, '1900-01-01') <> ISNULL(source.order_delivered_carrier_date, '1900-01-01')
    OR ISNULL(target.order_delivered_customer_date, '1900-01-01') <> ISNULL(source.order_delivered_customer_date, '1900-01-01')
) THEN
    UPDATE SET 
        target.order_status                  = source.order_status,
        target.order_approved_at             = source.order_approved_at,
        target.order_delivered_carrier_date  = source.order_delivered_carrier_date,
        target.order_delivered_customer_date = source.order_delivered_customer_date,
        target.order_estimated_delivery_date = source.order_estimated_delivery_date,
        target.silver_ingested_at            = GETDATE()

-- 2. Nếu đơn hàng mới chưa từng có ở đích -> CHÈN MỚI
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        silver_ingested_at
    )
    VALUES (
        source.order_id,
        source.customer_id,
        source.order_status,
        source.order_purchase_timestamp,
        source.order_approved_at,
        source.order_delivered_carrier_date,
        source.order_delivered_customer_date,
        source.order_estimated_delivery_date,
        GETDATE()
    ); -- Bắt buộc phải có dấu chấm phẩy kết thúc MERGE
GO

-- GHI CHÚ KIẾN THỨC TÍNH CHẤT IDEMPOTENT (LŨY ĐẲNG):
-- 1. Định nghĩa: Một thao tác là Idempotent nếu chạy lại 1 lần hay nhiều lần đều cho kết quả nhất quán không đổi.
-- 2. Ý nghĩa trong Data Engineering: Khi pipeline trên Airflow/ADF bị lỗi mạng và trigger retry tự động,
--    nhờ lệnh MERGE (Upsert) mà dữ liệu đích không bao giờ bị nhân bản (duplicate) thêm dòng.

-- GHI CHÚ BÓC TÁCH CÚ PHÁP LỆNH MERGE (UPSERT) & TÍNH CHẤT IDEMPOTENT:
-- 1. Bản chất UPSERT: Kết hợp UPdate (cập nhật) và inSERT (thêm mới) trong một câu lệnh nguyên tử duy nhất.
-- 2. Tác dụng của từng thành phần cú pháp:
--    - WITH source_staging AS (...) : Khử trùng lặp nguồn trước khi MERGE (Bắt buộc phải lọc rn = 1,
--                                     vì nếu nguồn có 2 dòng trùng order_id thì lệnh MERGE sẽ bị sập lỗi ngay lập tức).
--    - MERGE INTO <target>          : Chỉ định bảng ĐÍCH cần nạp/cập nhật dữ liệu vào (ở đây là dbo.silver_orders).
--    - USING <source>               : Chỉ định tập dữ liệu NGUỒN để đối chiếu so sánh (ở đây là CTE đã lọc sạch).
--    - ON target.key = source.key   : Điều kiện ghép nối khóa (Business Key: order_id) để nhận diện bản ghi đã tồn tại hay chưa.
--    - WHEN MATCHED AND (...)       : Nhánh UPDATE - Kích hoạt khi bản ghi ĐÃ TỒN TẠI trong đích VÀ có dữ liệu mới hơn ở nguồn.
--    - WHEN NOT MATCHED BY TARGET   : Nhánh INSERT - Kích hoạt khi bản ghi HOÀN TOÀN MỚI, chưa từng có trong bảng đích.
--    - Dấu chấm phẩy (;) ở cuối     : Quy định cú pháp BẮT BUỘC của SQL Server đối với lệnh MERGE.
-- 3. Ý nghĩa tính chất Idempotent (Lũy đẳng):
--    - Chạy 1 lần hay nhiều lần đều cho kết quả nhất quán không đổi, không bao giờ sinh ra dòng nhân bản (duplicate).
--    - Đây là tiêu chuẩn vàng khi xây dựng Data Pipeline tự động hóa trên Production (Airflow, Azure Data Factory,...).


-- ------------------------------------------------------------------------------------------
-- Câu 1.7.3:
-- Đóng gói toàn bộ logic khử trùng lặp thành một Stored Procedure:
-- Nhận dữ liệu đầu vào, thực hiện làm sạch dữ liệu trùng lặp và in ra thông số tổng kết:
-- Tổng số dòng ban đầu, số dòng trùng lặp đã bị loại bỏ, và số dòng hợp lệ được lưu lại.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.7.3 TẠI ĐÂY:

GO
CREATE OR ALTER PROCEDURE dbo.usp_dedup_and_load_silver_orders
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. Khai báo các biến đếm kiểm toán (Audit Metrics)
    DECLARE @total_raw_rows INT = 0;
    DECLARE @valid_rows INT = 0;
    DECLARE @rejected_rows INT = 0;

    -- 2. Đếm tổng số dòng thô ban đầu ở tầng Staging
    SELECT @total_raw_rows = COUNT(*) FROM dbo.olist_orders_dataset;

    -- 3. Tạo bảng Silver nếu chưa có
    IF OBJECT_ID('dbo.silver_orders', 'U') IS NULL
    BEGIN
        CREATE TABLE dbo.silver_orders (
            order_id NVARCHAR(50) PRIMARY KEY,
            customer_id NVARCHAR(50),
            order_status NVARCHAR(50),
            order_purchase_timestamp DATETIME,
            order_approved_at DATETIME,
            order_delivered_carrier_date DATETIME,
            order_delivered_customer_date DATETIME,
            order_estimated_delivery_date DATETIME,
            silver_ingested_at DATETIME DEFAULT GETDATE()
        );
    END;

    -- 4. Thực thi lọc sạch và nạp Idempotent qua MERGE
    WITH source_staging AS (
        SELECT 
            order_id,
            customer_id,
            order_status,
            order_purchase_timestamp,
            order_approved_at,
            order_delivered_carrier_date,
            order_delivered_customer_date,
            order_estimated_delivery_date,
            ROW_NUMBER() OVER (
                PARTITION BY order_id 
                ORDER BY order_purchase_timestamp DESC
            ) AS rn
        FROM dbo.olist_orders_dataset
        WHERE order_id IS NOT NULL
          AND customer_id IS NOT NULL
          AND order_status IS NOT NULL
    )
    MERGE INTO dbo.silver_orders AS target
    USING (
        SELECT * FROM source_staging WHERE rn = 1
    ) AS source
    ON target.order_id = source.order_id
    WHEN MATCHED AND source.order_purchase_timestamp > target.order_purchase_timestamp THEN
        UPDATE SET 
            target.order_status = source.order_status,
            target.order_approved_at = source.order_approved_at,
            target.silver_ingested_at = GETDATE()
    WHEN NOT MATCHED BY TARGET THEN
        INSERT (order_id, customer_id, order_status, order_purchase_timestamp, order_approved_at, silver_ingested_at)
        VALUES (source.order_id, source.customer_id, source.order_status, source.order_purchase_timestamp, source.order_approved_at, GETDATE());

    -- 5. Lấy số dòng hợp lệ hiện có trong Silver và tính số dòng bị loại
    SELECT @valid_rows = COUNT(*) FROM dbo.silver_orders;
    SET @rejected_rows = @total_raw_rows - @valid_rows;

    -- 6. Xuất bảng thống kê tổng kết quy trình nạp
    SELECT 
        @total_raw_rows AS [Tổng số dòng Staging ban đầu],
        @rejected_rows  AS [Số dòng trùng lặp / Lỗi đã loại bỏ],
        @valid_rows     AS [Số dòng hợp lệ nạp vào Silver],
        CASE 
            WHEN @rejected_rows = 0 THEN N'Dữ liệu nguồn tuyệt đối sạch'
            ELSE N'Đã lọc sạch thành công các bản ghi trùng/rác'
        END AS [Trạng thái Pipeline];
END;
GO

-- Chạy thử nghiệm Stored Procedure:
EXEC dbo.usp_dedup_and_load_silver_orders;

-- GHI CHÚ KIẾN THỨC STORED PROCEDURE PIPELINE:
-- 1. Đóng gói logic (Encapsulation): Giấu sự phức tạp của ETL/ELT sau một thủ tục có thể tái sử dụng.
-- 2. Audit Tracking: Đo lường chính xác lượng dữ liệu vào, lượng dữ liệu sạch, và lượng dữ liệu bị reject để phục vụ giám sát vận hành (Data Observability).
