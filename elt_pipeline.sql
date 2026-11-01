-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 3: KIẾN TRÚC DATA PIPELINE & DATA WAREHOUSING (END-TO-END DATA ENGINEERING)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 3: ETL / ELT END-TO-END QUERY (BIẾN ĐỔI LIÊN HOÀN TRONG 1 TRUY VẤN)
-- Luồng chuẩn: RAW → Extract → Clean → Transform → Validate → Dedup → Load
-- Mẫu: WITH cleaned AS (...), transformed AS (...), ranked AS (...), validated AS (...)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 1]: KIẾN TRÚC CTE PHÂN TẦNG (LAYERED CTE PIPELINE)
-- ------------------------------------------------------------------------------------------

-- Câu 3.1.1:
-- Xây dựng một truy vấn biến đổi khép kín 3 tầng cho bảng khách hàng:
-- Tầng 1: Trích xuất các trường dữ liệu thô cần thiết.
-- Tầng 2: Làm sạch khoảng trắng thừa và chuẩn hóa viết hoa tên thành phố.
-- Tầng 3: Chuẩn hóa mã bưu chính về chuỗi 5 chữ số có số 0 ở đầu.
-- Xuất tập dữ liệu sạch sẵn sàng để nạp vào kho.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.1 TẠI ĐÂY:

with raw_customers as (
    select 
        c.customer_id,
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix
    from dbo.olist_customers_dataset c
),
clean_customers as (
    select 
        trim(c.customer_id) as customer_id,
        trim(c.customer_unique_id) as customer_unique_id,
        coalesce(upper(trim(c.customer_city)), 'UNKNOWN') as [city],
        coalesce(upper(trim(c.customer_state)), 'UNKNOWN') as [state],
        c.customer_zip_code_prefix as zip_code
    from raw_customers c
    where c.customer_id is not null 
        and c.customer_unique_id is not null
        
),
standardized_customers AS (
    SELECT 
        c.customer_id,
        c.customer_unique_id, 
        c.city,
        c.state,
        RIGHT(CONCAT('00000', c.zip_code), 5) AS zip_code
    FROM clean_customers c
)
SELECT * FROM standardized_customers;





-- ------------------------------------------------------------------------------------------
-- Câu 3.1.2:
-- Xây dựng truy vấn phân tầng 4 bước cho bảng đánh giá:
-- Trích xuất thô $\rightarrow$ Xử lý nội dung nhận xét bị thiếu $\rightarrow$ Khử trùng lặp chỉ lấy 
-- đánh giá mới nhất của mỗi đơn hàng $\rightarrow$ Xuất tập dữ liệu đạt chuẩn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.2 TẠI ĐÂY:

with raw_reviews as (
    select 
        r.review_id,
        r.order_id,
        r.review_score,
        r.review_comment_message,
        r.review_creation_date,
        r.review_answer_timestamp
    from dbo.olist_order_reviews_dataset r
),
cleaned_reviews as (
    select
            r.review_id,
            r.order_id,
            coalesce(r.review_score, 0) as review_score,
            coalesce(trim(r.review_comment_message), 'No comment') as review_comment_message,
            r.review_creation_date,
            r.review_answer_timestamp
    from raw_reviews r
    where r.review_id is not null
        and r.order_id is not null
        and (r.review_creation_date < r.review_answer_timestamp)
),
dedup_reviews AS (
    SELECT 
        r.*,
        ROW_NUMBER() OVER (
            PARTITION BY r.order_id 
            ORDER BY r.review_creation_date DESC, r.review_answer_timestamp DESC
        ) AS rn
    FROM cleaned_reviews r
)
SELECT 
    r.review_id,
    r.order_id,
    r.review_score,
    r.review_comment_message,
    r.review_creation_date,
    r.review_answer_timestamp
FROM dedup_reviews r
WHERE r.rn = 1;


-- ------------------------------------------------------------------------------------------
-- Câu 3.1.3:
-- Viết truy vấn chứng minh sự khác biệt trong mô hình ELT:
-- Đưa toàn bộ dữ liệu thô vào bảng tạm Staging trước, 
-- sau đó dùng 1 câu lệnh SQL biến đổi trực tiếp trong kho
-- thay vì biến đổi trên đường truyền.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.3 TẠI ĐÂY:

drop table if exists #staging_orders;
select * 
into #staging_orders
from dbo.olist_orders_dataset;

with cleaned_orders as (
    select 
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    from #staging_orders o
    where o.order_id is not null
        and o.customer_id is not null
        and o.order_purchase_timestamp is not null
        and ( o.order_delivered_customer_date is null or
            o.order_delivered_customer_date >= o.order_purchase_timestamp)
)
select * from cleaned_orders;



-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 2]: NHÚNG BƯỚC KIỂM THỬ TỰ ĐỘNG VÀO TRUY VẤN BIẾN ĐỔI (VALIDATION LAYER)
-- ------------------------------------------------------------------------------------------

-- Câu 3.2.1:
-- Tích hợp tầng kiểm tra hợp lệ thời gian (Validation Step) vào giữa pipeline CTE đơn hàng:
-- Phát hiện và đánh dấu các đơn hàng có ngày khách nhận diễn ra trước ngày đặt hàng
-- để loại bỏ khỏi luồng nạp dữ liệu sạch.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.1 TẠI ĐÂY:

;with raw_orders as (
    select 
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    from dbo.olist_orders_dataset o
),
validated_orders as (
    select 
        o.*,
        case 
            when o.order_delivered_customer_date is not null
                and  o.order_delivered_customer_date < o.order_purchase_timestamp then 'Invalid'
            else 'Valid'
        end as validation_status
    from raw_orders o
    where o.order_id is not null
        and o.customer_id is not null
        and o.order_purchase_timestamp is not null
        and o.order_delivered_customer_date is not null
)
select   
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
from validated_orders
where validation_status = 'Valid';

-- ------------------------------------------------------------------------------------------
-- Câu 3.2.2:
-- Nhúng bước kiểm tra tính toàn vẹn tham chiếu trực tiếp trong luồng biến đổi mặt hàng:
-- Tự động loại bỏ các mặt hàng bán ra có mã sản phẩm không tồn tại trong danh mục trước khi xuất kết quả.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.2 TẠI ĐÂY:

with raw_order_items as (
    select 
        oi.order_id,
        oi.order_item_id,
        oi.product_id,
        oi.seller_id,
        oi.shipping_limit_date,
        oi.price,
        oi.freight_value
    from dbo.olist_order_items_dataset oi
),
validated_order_items as (
    select
        oi.*
    from raw_order_items oi
    where exists (
        select 1
        from dbo.olist_products_dataset p
        where p.product_id = oi.product_id
    )
    and oi.order_id is not null
        and oi.order_item_id is not null
        and oi.product_id is not null
)
select 
    order_id,
    order_item_id,
    product_id,
    seller_id,
    shipping_limit_date,
    price,
    freight_value
from validated_order_items;

-- ------------------------------------------------------------------------------------------
-- Câu 3.2.3:
-- Kỹ thuật tách nhánh kết quả (Branching Output) trong cùng 1 truy vấn:
-- Một nhánh trích xuất các bản ghi hợp lệ để nạp kho, một nhánh tập hợp các bản ghi vi phạm quy tắc nghiệp vụ
-- kèm theo lý do lỗi cụ thể để ghi vào bảng cách ly.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.3 TẠI ĐÂY:


-- ------------------------------------------------------------------------------------------
-- Câu 3.2.3:
-- Kỹ thuật tách nhánh kết quả (Branching Output) trong cùng 1 truy vấn:
-- Một nhánh trích xuất các bản ghi hợp lệ để nạp kho, một nhánh tập hợp các bản ghi vi phạm quy tắc nghiệp vụ
-- kèm theo lý do lỗi cụ thể để ghi vào bảng cách ly.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.3 TẠI ĐÂY:

;with raw_orders as (
    select 
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    from dbo.olist_orders_dataset o
),
validated_orders as (
    select 
        o.*,
        -- Tổng hợp tất cả các lỗi vi phạm nghiệp vụ vào chuỗi lý do
        concat_ws('; ',
            case when o.order_delivered_customer_date is not null 
                 and o.order_delivered_customer_date < o.order_purchase_timestamp 
                 then N'Khách nhận trước ngày đặt mua' end,
            case when o.order_approved_at is not null 
                 and o.order_approved_at < o.order_purchase_timestamp 
                 then N'Duyệt thanh toán trước ngày đặt mua' end,
            case when o.order_status = 'delivered' and o.order_delivered_customer_date is null 
                 then N'Đơn delivered nhưng thiếu ngày giao thực tế' end,
            case when o.order_status = 'canceled' and o.order_delivered_customer_date is not null 
                 then N'Đơn canceled nhưng vẫn tồn tại ngày giao' end
        ) as quarantine_reason
    from raw_orders o
    where o.order_id is not null
      and o.customer_id is not null
      and o.order_purchase_timestamp is not null
),
-- Nhánh 1: Dữ liệu sạch đưa vào Data Warehouse
branch_clean as (
    select 
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        cast(null as nvarchar(500)) as quarantine_reason,
        'DATA_WAREHOUSE' as target_destination
    from validated_orders
    where nullif(quarantine_reason, '') is null
),
-- Nhánh 2: Dữ liệu lỗi đưa vào Quarantine Table để kiểm toán
branch_quarantine as (
    select 
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        quarantine_reason,
        'QUARANTINE_TABLE' as target_destination
    from validated_orders
    where nullif(quarantine_reason, '') is not null
)
-- Xuất hợp nhất hai nhánh trong cùng 1 truy vấn
select * from branch_clean
union all
select * from branch_quarantine;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 3]: TÍCH HỢP KHỬ TRÙNG LẶP & ĐA TIÊU CHÍ VÀO LUỒNG BIẾN ĐỔI
-- ------------------------------------------------------------------------------------------

-- Câu 3.3.1:
-- Xây dựng chu trình hoàn chỉnh trong một câu truy vấn duy nhất:
-- Trích xuất đơn hàng thô $\rightarrow$ Chuẩn hóa định dạng $\rightarrow$ Gán số thứ tự phiên bản cập nhật $\rightarrow$
-- Lọc lấy bản ghi mới nhất của từng đơn $\rightarrow$ Chèn trực tiếp vào bảng đích.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.1 TẠI ĐÂY:

with raw_orders as (
    select 
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    from dbo.olist_orders_dataset o
),
standardized_orders as (
    
    select 
        o.order_id,
        o.customer_id,
        upper(trim(o.order_status)) as order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    from raw_orders o
    where o.order_id is not null
        and o.customer_id is not null
        and o.order_purchase_timestamp is not null
),
versioned_orders as (
    select 
        o.*,
        ROW_NUMBER() OVER (
            PARTITION BY o.order_id 
            ORDER BY  coalesce(o.order_approved_at, o.order_purchase_timestamp) desc,
                o.order_purchase_timestamp desc
        ) as version_number
    from standardized_orders o
),
latest_orders as (
    select 
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    from versioned_orders o
    where o.version_number = 1
)
select *
into #target_orders
from latest_orders;

select count(*) as total_clean_orders from #target_orders;
select top 10 * from #target_orders;


-- ------------------------------------------------------------------------------------------
-- Câu 3.3.2:
-- Khử trùng lặp đa nguồn kết hợp trong một truy vấn:
-- Khử trùng bảng Geolocation đưa về một tọa độ đại diện cho từng mã bưu chính,
-- sau đó nối làm giàu thông tin cho hồ sơ khách hàng mà không làm phát sinh thêm dòng trùng lặp nào.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.2 TẠI ĐÂY:

WITH raw_geolocations AS (
    SELECT  
        g.geolocation_zip_code_prefix,
        g.geolocation_lat,
        g.geolocation_lng,
        g.geolocation_city,
        g.geolocation_state
    FROM dbo.olist_geolocation_dataset g
),
dedup_geolocations AS (
    select 
        g.geolocation_zip_code_prefix,
        g.geolocation_lat,
        g.geolocation_lng,
        g.geolocation_city,
        g.geolocation_state,
        ROW_NUMBER() OVER (
            PARTITION BY g.geolocation_zip_code_prefix 
            ORDER BY g.geolocation_lat desc, g.geolocation_lng desc
        ) as rn
    from raw_geolocations g
),
unique_geolocations as (
    select 
        geolocation_zip_code_prefix,
        geolocation_lat,
        geolocation_lng,
        geolocation_city,
        geolocation_state
    from dedup_geolocations 
    where rn = 1
), 
enriched_customers as (
    select 
        c.customer_id,
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        c.customer_zip_code_prefix,
        g.geolocation_lat,
        g.geolocation_lng
    from dbo.olist_customers_dataset c
    left join unique_geolocations g
    on c.customer_zip_code_prefix = g.geolocation_zip_code_prefix
)
select * from enriched_customers;
-- ------------------------------------------------------------------------------------------
-- Câu 3.3.3:
-- Áp dụng cơ chế ưu tiên chất lượng bản ghi (Quality Tie-Breaker) trực tiếp trong tầng CTE khử trùng
-- trước khi chuyển giao dữ liệu sang bước tính toán tiếp theo.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.3 TẠI ĐÂY:

with raw_products as (
    select 
        p.product_id,
        p.product_category_name,
        p.product_name_lenght,
        p.product_description_lenght,
        p.product_photos_qty,
        p.product_weight_g,
        p.product_length_cm,
        p.product_height_cm,
        p.product_width_cm
    from dbo.olist_products_dataset p
),
dedup_products as (
    select 
        p.*,
        ROW_NUMBER() OVER (
            PARTITION BY p.product_id 
            ORDER BY p.product_photos_qty desc, p.product_weight_g desc
        ) as rn
    from raw_products p
),
cleaned_products as (
    select *
    from dedup_products
    where rn = 1
),
transformed_products as (
    select 
        cp.product_id,
        coalesce(cp.product_category_name, 'Unknown') as category_name,
        cp.product_weight_g,
        round(cast(cp.product_length_cm * cp.product_height_cm * cp.product_width_cm as float) / 1000000.0, 4) as volume_m3,
        case 
            when cp.product_weight_g > 5000 or (cp.product_length_cm * cp.product_height_cm * cp.product_width_cm) > 30000 
            then 'Bulky'
            else 'Standard'
        end as package_size_tier
    from cleaned_products cp
)
select * from transformed_products;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 4]: TẠO DATASET BÁN HÀNG TỔNG HỢP (SALES MART PIPELINE)
-- ------------------------------------------------------------------------------------------

-- Câu 3.4.1:
-- Viết một truy vấn liên hoàn biến đổi từ 4 bảng nguồn thô (Đơn hàng, Mặt hàng chi tiết, Thanh toán, Khách hàng)
-- để tạo ra một tập dữ liệu phân tích bán hàng sạch sẽ, bảo toàn đúng số lượng doanh thu và không bị nổ dòng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.1 TẠI ĐÂY:

with raw_orders as (
    select 
        *
    from dbo.olist_orders_dataset o
),
raw_order_items as (
    select 
        oi.order_id,
        sum(oi.price) as total_order_value,
        sum(oi.freight_value) as total_shipping_cost,
        count(*) as total_items
    from dbo.olist_order_items_dataset oi
    where oi.order_id is not null
        and oi.price > 0
        and oi.freight_value >= 0
    group by 
        oi.order_id
),
raw_payments as (
    select 
        p.order_id,
        sum(p.payment_value) as total_payment_value,
        count(*) as payment_method_count
    from dbo.olist_order_payments_dataset p
    where p.order_id is not null
        and p.payment_type is not null
        and p.payment_installments > 0
        and p.payment_value > 0
    group by 
        p.order_id
),
raw_customers as (
    select 
        *
    from dbo.olist_customers_dataset c
),
sales_mart  as (
    select 
        o.order_id,
        c.customer_id,
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        oi.total_order_value,
        oi.total_shipping_cost,
        oi.total_items,
        p.total_payment_value,
        p.payment_method_count
    from raw_orders o
    left join  raw_customers c on o.customer_id = c.customer_id
    left join raw_order_items oi on o.order_id = oi.order_id
    left join raw_payments p on o.order_id = p.order_id
)
select * from sales_mart;



-- ------------------------------------------------------------------------------------------
-- Câu 3.4.2:
-- Xử lý an toàn các phép tính tỷ trọng chi phí và phân bổ giá trị thanh toán
-- ngay trong tầng Transform của truy vấn bán hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.2 TẠI ĐÂY:
with raw_orders as (
    select 
        *
    from dbo.olist_orders_dataset o
),
raw_order_items as (
    select 
        oi.order_id,
        sum(oi.price) as total_order_value,
        sum(oi.freight_value) as total_shipping_cost,
        count(*) as total_items
    from dbo.olist_order_items_dataset oi
    where oi.order_id is not null
        and oi.price > 0
        and oi.freight_value >= 0
    group by 
        oi.order_id
),
raw_payments as (
    select 
        p.order_id,
        sum(p.payment_value) as total_payment_value,
        count(*) as payment_method_count
    from dbo.olist_order_payments_dataset p
    where p.order_id is not null
        and p.payment_type is not null
        and p.payment_installments > 0
        and p.payment_value > 0
    group by 
        p.order_id
),
raw_customers as (
    select 
        *
    from dbo.olist_customers_dataset c
),
sales_mart  as (
    select 
        o.order_id,
        c.customer_id,
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        oi.total_order_value,
        oi.total_shipping_cost,
        oi.total_items,
        p.total_payment_value,
        p.payment_method_count
    from raw_orders o
    left join  raw_customers c on o.customer_id = c.customer_id
    left join raw_order_items oi on o.order_id = oi.order_id
    left join raw_payments p on o.order_id = p.order_id
),
transformed_sales as (SELECT sm.*, 
    CASE 
        WHEN sm.total_order_value > 0 THEN sm.total_shipping_cost / sm.total_order_value
        ELSE NULL
    END AS shipping_cost_ratio,
    CASE 
        WHEN sm.total_payment_value > 0 THEN sm.total_order_value / sm.total_payment_value
        ELSE NULL
    END AS payment_allocation_ratio 
FROM sales_mart sm
)
select 
* from transformed_sales;

-- ------------------------------------------------------------------------------------------
-- Câu 3.4.3:
-- Tự động phân khúc quy mô đơn hàng (Order Tiering) và đánh giá cam kết thời gian giao hàng (SLA)
-- ngay tại tầng tính toán cuối cùng của pipeline bán hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.3 TẠI ĐÂY:


with raw_orders as (
    select 
        *
    from dbo.olist_orders_dataset o
),
raw_order_items as (
    select 
        oi.order_id,
        sum(oi.price) as total_order_value,
        sum(oi.freight_value) as total_shipping_cost,
        count(*) as total_items
    from dbo.olist_order_items_dataset oi
    where oi.order_id is not null
        and oi.price > 0
        and oi.freight_value >= 0
    group by 
        oi.order_id
),
raw_payments as (
    select 
        p.order_id,
        sum(p.payment_value) as total_payment_value,
        count(*) as payment_method_count
    from dbo.olist_order_payments_dataset p
    where p.order_id is not null
        and p.payment_type is not null
        and p.payment_installments > 0
        and p.payment_value > 0
    group by 
        p.order_id
),
raw_customers as (
    select 
        *
    from dbo.olist_customers_dataset c
),
sales_mart  as (
    select 
        o.order_id,
        c.customer_id,
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        oi.total_order_value,
        oi.total_shipping_cost,
        oi.total_items,
        p.total_payment_value,
        p.payment_method_count
    from raw_orders o
    left join  raw_customers c on o.customer_id = c.customer_id
    left join raw_order_items oi on o.order_id = oi.order_id
    left join raw_payments p on o.order_id = p.order_id
),
transformed_sales as (
    select 
        sm.*,
        case 
            when sm.total_order_value < 100 then 'Small'
            when sm.total_order_value between 100 and 500 then 'Medium'
            else 'Large'
        end as order_tier,
        case 
            when sm.order_delivered_customer_date is not null and sm.order_estimated_delivery_date is not null then
                case 
                    when sm.order_delivered_customer_date <= sm.order_estimated_delivery_date then 'On Time'
                    else 'Late'
                end
            else 'Unknown'
        end as delivery_sla_status
    from sales_mart sm
)
select * from transformed_sales;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 5]: TẠO DATASET HỒ SƠ KHÁCH HÀNG TOÀN CẢNH (CUSTOMER 360 PIPELINE)
-- ------------------------------------------------------------------------------------------

-- Câu 3.5.1:
-- Viết truy vấn ELT một bước tổng hợp toàn bộ lịch sử của từng khách hàng:
-- Địa chỉ cập nhật mới nhất, ngày mua đầu, ngày mua cuối, tổng số đơn hàng
--  đã hoàn tất và tổng giá trị chi tiêu trọn đời.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.1 TẠI ĐÂY:

with order_payments as (
    select 
        order_id,
        sum(payment_value) as total_order_value
    from dbo.olist_order_payments_dataset
    group by order_id
),
customer_orders as (
    select 
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.order_id,
        o.order_purchase_timestamp,
        coalesce(p.total_order_value, 0) as order_value,
        row_number() over (
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp desc
        ) as rn
    from dbo.olist_orders_dataset o
    inner join dbo.olist_customers_dataset c on o.customer_id = c.customer_id
    left join order_payments p on o.order_id = p.order_id
    where o.order_status = 'delivered'
),
latest_address as (
    select 
        customer_unique_id,
        customer_city as latest_city,
        customer_state as latest_state
    from customer_orders
    where rn = 1
),
customer_history as (
    select 
        customer_unique_id,
        min(order_purchase_timestamp) as first_purchase_date,
        max(order_purchase_timestamp) as last_purchase_date,
        count(distinct order_id) as total_orders,
        sum(order_value) as lifetime_value
    from customer_orders
    group by customer_unique_id
)
select 
    h.customer_unique_id,
    a.latest_city,
    a.latest_state,
    h.first_purchase_date,
    h.last_purchase_date,
    h.total_orders,
    h.lifetime_value
from customer_history h
inner join latest_address a on h.customer_unique_id = a.customer_unique_id;
-- ------------------------------------------------------------------------------------------
-- Câu 3.5.2:
-- Tích hợp tầng phân nhóm RFM (Recency, Frequency, Monetary) trực tiếp trong truy vấn tổng hợp hồ sơ khách hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.2 TẠI ĐÂY:

with order_payments as (
    select 
        order_id,
        sum(payment_value) as total_order_value
    from dbo.olist_order_payments_dataset
    group by order_id
),
customer_orders as (
    select 
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.order_id,
        o.order_purchase_timestamp,
        coalesce(p.total_order_value, 0) as order_value,
        row_number() over( 
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp desc
        ) as rn
    from dbo.olist_orders_dataset o
    inner join dbo.olist_customers_dataset c on o.customer_id = c.customer_id
    left join order_payments p on o.order_id = p.order_id
    where o.order_status = 'delivered'
),
latest_address  as (
    select 
        customer_unique_id,
        customer_city as latest_city,
        customer_state as latest_state
    from customer_orders
    where rn = 1
),
customer_history as (
    select 
        customer_unique_id,
        min(order_purchase_timestamp) as first_purchase_date,
        max(order_purchase_timestamp) as last_purchase_date,
        count(distinct order_id) as total_orders,
        sum(order_value) as lifetime_value
    from customer_orders
    group by customer_unique_id
),
snapshot_date as (
    select max(order_purchase_timestamp) as snapshot_date
    from dbo.olist_orders_dataset
),
rfm_scores as (
    select 
        h.customer_unique_id,
        datediff(day, h.last_purchase_date, s.snapshot_date) as recency,
        h.total_orders as frequency,
        h.lifetime_value as monetary
    from customer_history h
    cross join snapshot_date s
),
rfm_segments as (
    select 
        r.customer_unique_id,
        r.recency,
        r.frequency,
        r.monetary,
        case 
            when r.recency <= 30 then 'High'
            when r.recency <= 90 then 'Medium'
            else 'Low'
        end as recency_segment,
        case 
            when r.frequency >= 3 then 'High'
            when r.frequency >= 2 then 'Medium'
            else 'Low'
        end as frequency_segment,
        case 
            when r.monetary >= 1000 then 'High'
            when r.monetary >= 500 then 'Medium'
            else 'Low'
        end as monetary_segment
    from rfm_scores r
)
select 
    r.customer_unique_id,
    r.recency,
    r.frequency,
    r.monetary,
    r.recency_segment,
    r.frequency_segment,
    r.monetary_segment
from rfm_segments r
left join latest_address a on r.customer_unique_id = a.customer_unique_id;

-- ------------------------------------------------------------------------------------------
-- Câu 3.5.3:
-- Tính toán khoảng thời gian mua sắm trung bình giữa các đơn hàng và gắn nhãn phân loại khách hàng
-- (khách hàng mới, khách trung thành, hoặc khách có dấu hiệu rời bỏ).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.3 TẠI ĐÂY:

with raw_orders as (
    select 
        o.customer_id,
        o.order_id,
        o.order_purchase_timestamp
    from dbo.olist_orders_dataset o
    where o.order_id is not null
        and o.customer_id is not null
        and o.order_purchase_timestamp is not null
        and o.order_status = 'delivered'
),customer_orders as (
    select 
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        c.customer_id
    from dbo.olist_customers_dataset c
),
customer_order_history as (
    select 
        c.customer_unique_id,
        c.customer_city,
        c.customer_state,
        o.order_id,
        o.order_purchase_timestamp,
        row_number() over (
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp
        ) as order_sequence
    from raw_orders o
    inner join customer_orders c on o.customer_id = c.customer_id
),
customer_order_pre as (
    select 
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        order_sequence,
        lag(order_purchase_timestamp) over (
            partition by customer_unique_id 
            order by order_purchase_timestamp
        ) as previous_order_timestamp
    from customer_order_history
),
customer_order_intervals as (
    select 
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        order_sequence,
        previous_order_timestamp,
        datediff(day, previous_order_timestamp, order_purchase_timestamp) as days_since_last_order
    from customer_order_pre
),customer_order_summary as (
    select 
        customer_unique_id,
        count(order_id) as total_orders,
       round(avg(days_since_last_order * 1.0), 2) as avg_days_between_orders
    from customer_order_intervals
    group by customer_unique_id
),customer_classification as (
    select 
        s.customer_unique_id,
        s.total_orders,
        s.avg_days_between_orders,
        case 
            when s.total_orders = 1 then 'New Customer'
            when s.avg_days_between_orders <= 30 then 'Loyal Customer'
            else 'At-Risk Customer'
        end as customer_classification
    from customer_order_summary s
)
select 
    c.customer_unique_id,
    c.total_orders,
    c.avg_days_between_orders,
    c.customer_classification
from customer_classification c;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 6]: CHUYỂN ĐỔI GIỮA BẢNG TẠM VÀ CTE KHI XỬ LÝ DỮ LIỆU LỚN
-- ------------------------------------------------------------------------------------------

-- Câu 3.6.1:
-- So sánh và chuyển đổi một truy vấn CTE phức tạp nhiều tầng sang chuỗi các bảng tạm (Temp Table Chaining)
-- có đánh Index hỗ trợ để tối ưu bộ nhớ và tránh nghẽn TempDB khi xử lý hàng triệu bản ghi.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.1 TẠI ĐÂY:

-- 1. Dọn dẹp các bảng tạm nếu đã tồn tại
DROP TABLE IF EXISTS #stage_order_items;
DROP TABLE IF EXISTS #stage_payments;
DROP TABLE IF EXISTS #stage_orders;
DROP TABLE IF EXISTS #final_sales_mart;

-- Bước 1: Trích xuất và gom nhóm Order Items vào bảng tạm riêng
SELECT 
    oi.order_id,
    SUM(oi.price) AS total_item_value,
    SUM(oi.freight_value) AS total_freight_value,
    COUNT(*) AS total_items
INTO #stage_order_items
FROM dbo.olist_order_items_dataset oi
WHERE oi.order_id IS NOT NULL
GROUP BY oi.order_id;

-- Đánh Clustered Index trên khóa liên kết order_id để tối ưu hóa phép Join
CREATE CLUSTERED INDEX cidx_stage_items_order_id ON #stage_order_items(order_id);

-- Bước 2: Trích xuất và gom nhóm Payments vào bảng tạm riêng
SELECT 
    p.order_id,
    SUM(p.payment_value) AS total_payment_value,
    COUNT(*) AS payment_installments_count
INTO #stage_payments
FROM dbo.olist_order_payments_dataset p
WHERE p.order_id IS NOT NULL
GROUP BY p.order_id;

-- Đánh Clustered Index trên khóa liên kết order_id
CREATE CLUSTERED INDEX cidx_stage_payments_order_id ON #stage_payments(order_id);

-- Bước 3: Trích xuất và làm sạch Orders
SELECT 
    o.order_id,
    o.customer_id,
    LOWER(TRIM(o.order_status)) AS order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date
INTO #stage_orders
FROM dbo.olist_orders_dataset o
WHERE o.order_id IS NOT NULL 
  AND o.customer_id IS NOT NULL;

-- Đánh Clustered Index trên order_id và Nonclustered Index trên customer_id
CREATE CLUSTERED INDEX cidx_stage_orders_order_id ON #stage_orders(order_id);
CREATE NONCLUSTERED INDEX idx_stage_orders_customer_id ON #stage_orders(customer_id);

-- Bước 4: Ghép nối chuỗi bảng tạm (Temp Table Chaining) thành Sales Mart
SELECT 
    o.order_id,
    o.customer_id,
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,
    o.order_status,
    o.order_purchase_timestamp,
    COALESCE(oi.total_item_value, 0) AS total_item_value,
    COALESCE(oi.total_freight_value, 0) AS total_freight_value,
    COALESCE(oi.total_items, 0) AS total_items,
    COALESCE(p.total_payment_value, 0) AS total_payment_value,
    COALESCE(p.payment_installments_count, 0) AS payment_installments_count
INTO #final_sales_mart
FROM #stage_orders o
INNER JOIN dbo.olist_customers_dataset c ON o.customer_id = c.customer_id
LEFT JOIN #stage_order_items oi ON o.order_id = oi.order_id
LEFT JOIN #stage_payments p ON o.order_id = p.order_id;

-- Kiểm tra kết quả
SELECT COUNT(*) AS total_rows_in_sales_mart FROM #final_sales_mart;
SELECT TOP 10 * FROM #final_sales_mart;


-- ------------------------------------------------------------------------------------------
-- Câu 3.6.2:
-- Thực hiện kiểm toán số dòng (Row Count Audit) qua từng tầng biến đổi trung gian
-- để đảm bảo không bị rơi rụng dữ liệu ngoài ý muốn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.2 TẠI ĐÂY:

-- 1. Khởi tạo bảng kiểm toán số dòng qua từng tầng biến đổi
DROP TABLE IF EXISTS #pipeline_row_count_audit;
CREATE TABLE #pipeline_row_count_audit (
    step_id INT IDENTITY(1,1) PRIMARY KEY,
    pipeline_stage NVARCHAR(100) NOT NULL,
    target_object NVARCHAR(100) NOT NULL,
    row_count INT NOT NULL,
    captured_at DATETIME DEFAULT GETDATE()
);

-- 2. Tầng 1: Đếm số dòng thô ban đầu (Raw Stage)
INSERT INTO #pipeline_row_count_audit (pipeline_stage, target_object, row_count)
SELECT N'1. Raw Extracted', 'dbo.olist_orders_dataset', COUNT(*)
FROM dbo.olist_orders_dataset;

-- Tạo bảng tạm sau khi làm sạch các bản ghi lỗi Null khóa chính / thời gian
DROP TABLE IF EXISTS #audit_clean_orders;
SELECT 
    order_id, customer_id, order_status, 
    order_purchase_timestamp, order_delivered_customer_date
INTO #audit_clean_orders
FROM dbo.olist_orders_dataset
WHERE order_id IS NOT NULL 
  AND customer_id IS NOT NULL 
  AND order_purchase_timestamp IS NOT NULL;

-- 3. Tầng 2: Đếm số dòng sau khi làm sạch lỗi Null (Clean Stage)
INSERT INTO #pipeline_row_count_audit (pipeline_stage, target_object, row_count)
SELECT N'2. Null Key Cleaned', '#audit_clean_orders', COUNT(*)
FROM #audit_clean_orders;

-- Tạo bảng tạm sau khi áp dụng quy tắc nghiệp vụ (Validation Stage)
DROP TABLE IF EXISTS #audit_validated_orders;
SELECT *
INTO #audit_validated_orders
FROM #audit_clean_orders
WHERE (order_delivered_customer_date IS NULL 
       OR order_delivered_customer_date >= order_purchase_timestamp);

-- 4. Tầng 3: Đếm số dòng sau khi kiểm tra tính hợp lệ nghiệp vụ (Validated Stage)
INSERT INTO #pipeline_row_count_audit (pipeline_stage, target_object, row_count)
SELECT N'3. Business Validated', '#audit_validated_orders', COUNT(*)
FROM #audit_validated_orders;

-- Tạo bảng tạm sau khi lọc đơn hoàn tất thành công (Delivered Stage)
DROP TABLE IF EXISTS #audit_delivered_orders;
SELECT *
INTO #audit_delivered_orders
FROM #audit_validated_orders
WHERE order_status = 'delivered';

-- 5. Tầng 4: Đếm số dòng nạp đích thành công (Target Load Stage)
INSERT INTO #pipeline_row_count_audit (pipeline_stage, target_object, row_count)
SELECT N'4. Delivered Orders (Target)', '#audit_delivered_orders', COUNT(*)
FROM #audit_delivered_orders;

-- 6. Xuất báo cáo kiểm toán số dòng và tỷ lệ giữ lại qua từng bước
WITH audit_metrics AS (
    SELECT 
        step_id,
        pipeline_stage,
        target_object,
        row_count,
        LAG(row_count) OVER (ORDER BY step_id) AS prev_row_count,
        captured_at
    FROM #pipeline_row_count_audit
)
SELECT 
    step_id,
    pipeline_stage,
    target_object,
    row_count AS current_rows,
    COALESCE(prev_row_count - row_count, 0) AS dropped_rows,
    CASE 
        WHEN prev_row_count IS NULL THEN 100.0
        ELSE ROUND(CAST(row_count AS FLOAT) * 100.0 / prev_row_count, 2)
    END AS retention_rate_pct,
    CASE 
        WHEN prev_row_count IS NOT NULL AND (prev_row_count - row_count) > 0 
             THEN N'Data Filtered / Dropped'
        ELSE N'Fully Preserved'
    END AS audit_status,
    captured_at
FROM audit_metrics
ORDER BY step_id;


-- ------------------------------------------------------------------------------------------
-- Câu 3.6.3:
-- Áp dụng kỹ thuật đẩy sớm điều kiện lọc (Filter Pushdown) ngay tại tầng trích xuất đầu tiên
-- để giảm tải tối đa khối lượng dữ liệu truyền qua các bước sau.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.3 TẠI ĐÂY:

;WITH raw_orders_pushdown AS (
    -- TẦNG TRÍCH XUẤT ĐẨY SỚM ĐIỀU KIỆN LỌC (FILTER PUSHDOWN)
    SELECT 
        o.order_id,
        o.customer_id,
        o.order_status,
        o.order_purchase_timestamp,
        o.order_delivered_customer_date
    FROM dbo.olist_orders_dataset o
    WHERE o.order_id IS NOT NULL 
      AND o.customer_id IS NOT NULL
      -- Filter Pushdown 1: Chỉ lấy các đơn đã hoàn tất giao hàng
      AND o.order_status = 'delivered'
      -- Filter Pushdown 2: Lọc phân vùng thời gian (ví dụ: các đơn phát sinh trong năm 2018)
      AND o.order_purchase_timestamp >= '2018-01-01'
      AND o.order_purchase_timestamp < '2018-09-01'
      -- Filter Pushdown 3: Loại bỏ ngay dữ liệu lỗi thời gian
      AND (o.order_delivered_customer_date IS NULL 
           OR o.order_delivered_customer_date >= o.order_purchase_timestamp)
),
pushdown_items AS (
    -- Tương tự, chỉ trích xuất các item tương ứng với các đơn đã qua Pushdown
    SELECT 
        oi.order_id,
        SUM(oi.price) AS total_order_value,
        COUNT(*) AS total_items
    FROM dbo.olist_order_items_dataset oi
    WHERE EXISTS (
        SELECT 1 
        FROM raw_orders_pushdown ro 
        WHERE ro.order_id = oi.order_id
    )
    GROUP BY oi.order_id
),
pushdown_sales_summary AS (
    SELECT 
        ro.order_id,
        ro.customer_id,
        ro.order_status,
        ro.order_purchase_timestamp,
        COALESCE(pi.total_order_value, 0) AS total_order_value,
        COALESCE(pi.total_items, 0) AS total_items
    FROM raw_orders_pushdown ro
    LEFT JOIN pushdown_items pi ON ro.order_id = pi.order_id
)
SELECT * 
FROM pushdown_sales_summary;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 7]: ĐÓNG GÓI TOÀN BỘ THÀNH SILVER VIEWS & STORED PROCEDURE ELT
-- ------------------------------------------------------------------------------------------

-- Câu 3.7.1:
-- Đóng gói toàn bộ câu truy vấn biến đổi dữ liệu đơn hàng thành một View tầng Silver `v_silver_orders`
-- chuẩn hóa để tái sử dụng xuyên suốt toàn bộ dự án.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.1 TẠI ĐÂY:

CREATE OR ALTER VIEW dbo.v_silver_orders
AS
WITH raw_orders AS (
    SELECT 
        TRIM(o.order_id) AS order_id,
        TRIM(o.customer_id) AS customer_id,
        LOWER(TRIM(o.order_status)) AS order_status,
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date
    FROM dbo.olist_orders_dataset o
    WHERE o.order_id IS NOT NULL 
      AND o.customer_id IS NOT NULL
      AND o.order_purchase_timestamp IS NOT NULL
),
validated_orders AS (
    SELECT 
        ro.*,
        -- Tính thời gian thực tế khách nhận hàng (ngày)
        DATEDIFF(day, ro.order_purchase_timestamp, ro.order_delivered_customer_date) AS actual_delivery_days,
        -- Tính thời gian giao hàng ước tính (ngày)
        DATEDIFF(day, ro.order_purchase_timestamp, ro.order_estimated_delivery_date) AS estimated_delivery_days,
        -- Cờ kiểm tra giao hàng đúng hạn (SLA)
        CASE 
            WHEN ro.order_delivered_customer_date IS NULL THEN 'Pending / In-Transit'
            WHEN ro.order_delivered_customer_date <= ro.order_estimated_delivery_date THEN 'On-Time'
            ELSE 'Delayed'
        END AS delivery_sla_status,
        -- Cột kiểm toán thời điểm biến đổi tầng Silver
        CAST(GETDATE() AS DATETIME) AS silver_transformed_at
    FROM raw_orders ro
    -- Loại bỏ đơn hàng vi phạm logic thời gian giao hàng
    WHERE (ro.order_delivered_customer_date IS NULL 
           OR ro.order_delivered_customer_date >= ro.order_purchase_timestamp)
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
    actual_delivery_days,
    estimated_delivery_days,
    delivery_sla_status,
    silver_transformed_at
FROM validated_orders;
GO

-- ------------------------------------------------------------------------------------------
-- Câu 3.7.2:
-- Đóng gói truy vấn biến đổi hồ sơ khách hàng thành View tầng Silver `v_silver_customers`.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.2 TẠI ĐÂY:

CREATE OR ALTER VIEW dbo.v_silver_customers
AS
WITH raw_customers AS (
    SELECT 
        TRIM(c.customer_id) AS customer_id,
        TRIM(c.customer_unique_id) AS customer_unique_id,
        COALESCE(UPPER(TRIM(c.customer_city)), 'UNKNOWN') AS customer_city,
        COALESCE(UPPER(TRIM(c.customer_state)), 'UNKNOWN') AS customer_state,
        RIGHT(CONCAT('00000', c.customer_zip_code_prefix), 5) AS customer_zip_code_prefix
    FROM dbo.olist_customers_dataset c
    WHERE c.customer_id IS NOT NULL 
      AND c.customer_unique_id IS NOT NULL
),
dedup_customers AS (
    -- Khử trùng lặp: mỗi khách hàng duy nhất (customer_unique_id) chỉ giữ 1 bản ghi chuẩn nhất
    SELECT 
        rc.customer_unique_id,
        rc.customer_id AS representative_customer_id,
        rc.customer_city,
        rc.customer_state,
        rc.customer_zip_code_prefix,
        ROW_NUMBER() OVER (
            PARTITION BY rc.customer_unique_id 
            ORDER BY rc.customer_id DESC
        ) AS rn
    FROM raw_customers rc
)
SELECT 
    customer_unique_id,
    representative_customer_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix,
    CAST(GETDATE() AS DATETIME) AS silver_transformed_at
FROM dedup_customers
WHERE rn = 1;
GO

-- ------------------------------------------------------------------------------------------
-- Câu 3.7.3:
-- Viết Stored Procedure điều phối toàn bộ quy trình ELT:
-- Thực thi tuần tự các bước trích xuất, làm sạch, kiểm thử chất lượng, nạp dữ liệu đích và ghi nhật ký thời gian hoàn thành.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.3 TẠI ĐÂY:

-- 1. Bảng lưu vết nhật ký thực thi Stored Procedure ELT nếu chưa có
IF OBJECT_ID('dbo.elt_pipeline_execution_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.elt_pipeline_execution_log (
        execution_id INT IDENTITY(1,1) PRIMARY KEY,
        pipeline_name NVARCHAR(100) NOT NULL,
        start_time DATETIME NOT NULL,
        end_time DATETIME NULL,
        duration_seconds INT NULL,
        raw_rows_scanned INT NULL,
        rows_loaded INT NULL,
        execution_status NVARCHAR(50) NOT NULL,
        error_message NVARCHAR(MAX) NULL
    );
END;
GO

-- 2. Tạo bảng Silver Target nếu chưa tồn tại
IF OBJECT_ID('dbo.silver_target_orders', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.silver_target_orders (
        order_id VARCHAR(50) PRIMARY KEY,
        customer_id VARCHAR(50) NOT NULL,
        order_status VARCHAR(50),
        order_purchase_timestamp DATETIME,
        order_approved_at DATETIME,
        order_delivered_carrier_date DATETIME,
        order_delivered_customer_date DATETIME,
        order_estimated_delivery_date DATETIME,
        delivery_sla_status VARCHAR(50),
        silver_loaded_at DATETIME DEFAULT GETDATE()
    );
END;
GO

-- 3. Stored Procedure điều phối toàn bộ quy trình ELT khép kín
CREATE OR ALTER PROCEDURE dbo.usp_orchestrate_elt_pipeline
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @start_time DATETIME = GETDATE();
    DECLARE @end_time DATETIME;
    DECLARE @raw_rows INT = 0;
    DECLARE @rows_loaded INT = 0;
    DECLARE @status NVARCHAR(50) = 'RUNNING';
    DECLARE @execution_id INT;

    -- Ghi nhận khởi động pipeline vào bảng log
    INSERT INTO dbo.elt_pipeline_execution_log (pipeline_name, start_time, execution_status)
    VALUES (N'ELT_Order_Processing_Pipeline', @start_time, @status);
    SET @execution_id = SCOPE_IDENTITY();

    BEGIN TRY
        -- Bước 1: Trích xuất & Đếm số dòng thô
        SELECT @raw_rows = COUNT(*) FROM dbo.olist_orders_dataset;

        -- Bước 2 & 3: Làm sạch, kiểm thử và nạp dữ liệu sạch từ Silver View vào Bảng đích (Idempotent MERGE)
        MERGE INTO dbo.silver_target_orders AS target
        USING (
            SELECT 
                order_id,
                customer_id,
                order_status,
                order_purchase_timestamp,
                order_approved_at,
                order_delivered_carrier_date,
                order_delivered_customer_date,
                order_estimated_delivery_date,
                delivery_sla_status
            FROM dbo.v_silver_orders
        ) AS source
        ON target.order_id = source.order_id
        WHEN MATCHED THEN
            UPDATE SET 
                target.order_status = source.order_status,
                target.order_delivered_customer_date = source.order_delivered_customer_date,
                target.delivery_sla_status = source.delivery_sla_status,
                target.silver_loaded_at = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (
                order_id, customer_id, order_status,
                order_purchase_timestamp, order_approved_at,
                order_delivered_carrier_date, order_delivered_customer_date,
                order_estimated_delivery_date, delivery_sla_status, silver_loaded_at
            )
            VALUES (
                source.order_id, source.customer_id, source.order_status,
                source.order_purchase_timestamp, source.order_approved_at,
                source.order_delivered_carrier_date, source.order_delivered_customer_date,
                source.order_estimated_delivery_date, source.delivery_sla_status, GETDATE()
            );

        SET @rows_loaded = @@ROWCOUNT;
        SET @end_time = GETDATE();
        SET @status = 'SUCCESS';

        -- Cập nhật log thành công
        UPDATE dbo.elt_pipeline_execution_log
        SET end_time = @end_time,
            duration_seconds = DATEDIFF(second, @start_time, @end_time),
            raw_rows_scanned = @raw_rows,
            rows_loaded = @rows_loaded,
            execution_status = @status
        WHERE execution_id = @execution_id;

        PRINT N'=== ELT PIPELINE COMPLETED SUCCESSFULLY ===';
        PRINT CONCAT(N'Thời gian thực thi: ', DATEDIFF(second, @start_time, @end_time), N' giây.');
        PRINT CONCAT(N'Số dòng thô quét: ', @raw_rows);
        PRINT CONCAT(N'Số dòng nạp thành công: ', @rows_loaded);

    END TRY
    BEGIN CATCH
        SET @end_time = GETDATE();
        SET @status = 'FAILED';

        -- Ghi nhận lỗi vào log nếu có sự cố
        UPDATE dbo.elt_pipeline_execution_log
        SET end_time = @end_time,
            duration_seconds = DATEDIFF(second, @start_time, @end_time),
            execution_status = @status,
            error_message = ERROR_MESSAGE()
        WHERE execution_id = @execution_id;

        PRINT CONCAT(N'=== ELT PIPELINE FAILED: ', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO
