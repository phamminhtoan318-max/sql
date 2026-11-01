-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 1: CÁC NỀN TẢNG XỬ LÝ VÀ PHÂN TÍCH DỮ LIỆU CỐT LÕI (CORE DATA PIPELINE FOUNDATIONS)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 1: DATA EXTRACTION (TRUY VẤN LẤY DỮ LIỆU)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 1]: FULL EXTRACTION & XỬ LÝ DỮ LIỆU NGUỒN CƠ BẢN
-- ------------------------------------------------------------------------------------------

-- Câu 1.1:
-- Để chuẩn bị nạp dữ liệu khách hàng vào Data Warehouse, hãy trích xuất toàn bộ danh sách
-- khách hàng hợp lệ (loại bỏ các khách hàng không có mã định danh duy nhất).
-- Yêu cầu chuẩn hóa tên thành phố về chữ in hoa và loại bỏ khoảng trắng thừa hai đầu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1 TẠI ĐÂY:

select 
    customers.customer_id,
    customers.customer_unique_id,
    customers.customer_zip_code_prefix,
    upper(trim(customers.customer_city)) as customer_city,
    upper(trim(customers.customer_state)) as customer_state
from dbo.olist_customers_dataset customers
where customers.customer_unique_id is not null


-- ------------------------------------------------------------------------------------------
-- Câu 1.2:
-- Thực hiện Full Extraction trích xuất các đơn hàng đã 
-- hoàn tất giao dịch (đã giao thành công
-- hoặc đang trên đường vận chuyển) để nạp bảng Fact ban đầu.
-- Loại bỏ các đơn hàng bị thiếu thông tin ngày đặt mua. 
-- Sắp xếp dữ liệu theo thứ tự thời gian đặt hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2 TẠI ĐÂY:

select 
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_estimated_delivery_date,
    orders.order_delivered_customer_date
from dbo.olist_orders_dataset orders 
where orders.order_status in ('delivered', 'shipped')
    and orders.order_purchase_timestamp is not null
order by orders.order_purchase_timestamp

SET STATISTICS IO, TIME ON;

-- Câu truy vấn của bạn
SELECT *
FROM dbo.olist_customers_dataset;

SET STATISTICS IO, TIME OFF;

SET SHOWPLAN_XML ON;
GO
SELECT * FROM dbo.olist_customers_dataset;
GO
SET SHOWPLAN_XML OFF;

-- ------------------------------------------------------------------------------------------
-- Câu 1.3:
-- Trích xuất danh mục sản phẩm duy nhất để xây dựng Dimension Product.
-- Đảm bảo mỗi sản phẩm chỉ xuất hiện đúng một lần trong tập kết quả.
-- Với các sản phẩm chưa có thông tin ngành hàng, hãy gán giá trị mặc định là 'Unknown'.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3 TẠI ĐÂY:

select distinct 
    products.product_id,
    coalesce(products.product_category_name, 'Unknown') as product_category_name,
    products.product_weight_g,
    products.product_length_cm,
    products.product_height_cm,
    products.product_width_cm
from dbo.olist_products_dataset products



-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 2]: TIME-BASED EXTRACTION & KHOẢNG THỜI GIAN CỐ ĐỊNH
-- ------------------------------------------------------------------------------------------

-- Câu 2.1:
-- Viết truy vấn trích xuất toàn bộ đơn hàng phát sinh trong năm 2017.
-- Yêu cầu câu truy vấn phải tối ưu cho việc tận dụng Index trên cột ngày 
-- tháng (chuẩn SARGable).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1 TẠI ĐÂY:

-- Quy tắc ghi nhớ nhanh: Cứ chỗ nào 
-- cần "tìm kiếm" (ở WHERE, ON) thì tuyệt đối 
-- không bọc hàm quanh tên cột. Còn chỗ nào chỉ 
-- để "hiển thị" (ở SELECT) thì dùng hàm thoải mái.

select 
    orders.*
from dbo.olist_orders_dataset orders 
where orders.order_purchase_timestamp >= '2017-01-01'
    and orders.order_purchase_timestamp < '2018-01-01'

-- ------------------------------------------------------------------------------------------
-- Câu 2.2:
-- Viết truy vấn trích xuất dữ liệu đơn hàng của riêng 
-- tháng 08 năm 2017 phục vụ quy trình Backfill.
-- Bổ sung thêm một cột đánh dấu phân vùng (partition)
--  có giá trị chuỗi là '2017-08'.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2 TẠI ĐÂY:

select 
    *,
    '2017-08' as 'partition_key'
from dbo.olist_orders_dataset orders 
where orders.order_purchase_timestamp >= '2017-08-01'
    and orders.order_purchase_timestamp < '2017-09-01'


-- ------------------------------------------------------------------------------------------
-- Câu 2.3:
-- Kiểm tra và đối chiếu số lượng đơn hàng đặt trong tháng 08/2017 giữa 2 phương pháp lọc:
-- Phương pháp A: Dùng toán tử BETWEEN từ '2017-08-01' đến '2017-08-31'.
-- Phương pháp B: Dùng điều kiện so sánh mở `>= '2017-08-01'` và `< '2017-09-01'`.
-- Cho biết số lượng đơn hàng chênh lệch giữa hai cách và giải thích lý do.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3 TẠI ĐÂY:


select 
    count(order1.order_id) as total_orders
from dbo.olist_orders_dataset order1
where order1.order_purchase_timestamp between '2017-08-01' and '2017-09-01'

select 
    count(order1.order_id) as total_orders
from dbo.olist_orders_dataset order1
where order1.order_purchase_timestamp >= '2017-08-01' and
    order1.order_purchase_timestamp < '2017-09-01'

/* 
=============================================================================================
GIẢI THÍCH LÝ DO CHÊNH LỆCH & QUY TẮC LỌC DATETIME TRONG DATA ENGINEERING:
---------------------------------------------------------------------------------------------
1. Nguyên nhân chênh lệch:
   - Cột `order_purchase_timestamp` chứa cả Giờ:Phút:Giây (DATETIME).
   - Khi viết chuỗi ngày '2017-08-31', SQL Server sẽ tự động ép kiểu ngầm định (Implicit Cast) 
     về mốc: '2017-08-31 00:00:00.000' (0 giờ đầu ngày).
   - Toán tử BETWEEN tương đương với: >= '2017-08-01 00:00:00' VÀ <= '2017-08-31 00:00:00'.
   => HẬU QUẢ: Toàn bộ đơn hàng phát sinh trong ngày 31/08/2017 từ 00:00:01 đến 23:59:59 
      đều bị BỎ SÓT hoàn toàn.

2. Tại sao khoảng nửa mở [>=, <) là Chuẩn Vàng (Best Practice)?
   - Điều kiện: >= '2017-08-01' AND < '2017-09-01'
   - Lấy từ giây đầu tiên của tháng 8 (2017-08-01 00:00:00) cho đến trước 00:00:00 ngày 01/09,
     tức bao trọn vẹn đến từng mili-giây cuối cùng của ngày 31/08 (23:59:59.999...).
   - Đảm bảo 100% không sót dữ liệu, không lo tròn mili-giây (như ở kiểu DATETIME cũ), 
     đồng thời chuẩn SARGable (tận dụng tối đa Index).
=============================================================================================
*/

-- 💡 Quy tắc thực chiến Data Engineering
-- Tuyệt đối tránh dùng BETWEEN cho cột có thời gian (Datetime/Timestamp).
-- Luôn sử dụng khoảng nửa mở (Half-open Interval):
-- sql
-- col >= 'Ngày_Bắt_Đầu' AND col < 'Ngày_Kế_Tiếp'
-- Cách viết này vừa an toàn tuyệt đối với mọi kiểu dữ liệu (DATE, DATETIME, DATETIME2), vừa đảm bảo chuẩn SARGable giúp tối ưu index scan/seek.

-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 3]: DYNAMIC TIME EXTRACTION & CỬA SỔ TRƯỢT (SLIDING WINDOW)
-- ------------------------------------------------------------------------------------------

-- Câu 3.1:
-- Viết truy vấn Daily Batch tự động trích xuất toàn bộ đơn hàng phát sinh trong "ngày hôm qua".
-- Điều kiện thời gian phải tính toán hoàn toàn tự động dựa trên ngày hiện tại khi pipeline kích hoạt,
-- không fix cứng chuỗi ngày tháng.
-- (Nếu cần kiểm thử trên tập dữ liệu lịch sử, bạn có thể khai báo một biến ngày chạy giả định).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1 TẠI ĐÂY:

declare @batch_date datetime = cast(getdate() as date); 

SELECT 
    orders.* 
FROM dbo.olist_orders_dataset orders
where orders.order_purchase_timestamp >= dateadd(day, -1, @batch_date)
    and orders.order_purchase_timestamp < @batch_date;

/* 
=============================================================================================
GIẢI THÍCH TRUY VẤN DAILY BATCH:
- Dateadd(day, -1, @batch_date): Hàm chuẩn SQL Server lấy ngày trước đó so với ngày hiện tại.
- Giả sử @batch_date là 2026-10-03 (hôm nay), câu lệnh sẽ lọc đơn hàng từ:
  2026-10-02 00:00:00 (đầu ngày hôm qua)
  đến 2026-10-03 00:00:00 (trước 0 giờ hôm nay)
  Đảm bảo chính xác 24 giờ của ngày hôm qua, không thừa, không thiếu.
=============================================================================================
*/

-- ------------------------------------------------------------------------------------------
-- Câu 3.2:
-- Viết truy vấn trích xuất đơn hàng theo cửa sổ trượt 7 ngày gần nhất (Sliding Lookback Window)
-- tính từ mốc thời gian chạy batch '@batch_date = 2018-05-10 00:00:00'.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2 TẠI ĐÂY:

declare @batch_time datetime = '2018-05-10 00:00:00'

select 
    orders.* 
from dbo.olist_orders_dataset orders 
where orders.order_purchase_timestamp >= dateadd(day, -7, @batch_time) 
    and orders.order_purchase_timestamp < @batch_time


/* 
=============================================================================================
GIẢI THÍCH TRUY VẤN DAILY BATCH:
- Dateadd(day, -1, @batch_date): Hàm chuẩn SQL Server lấy ngày trước đó so với ngày hiện tại.
- Giả sử @batch_date là 2026-10-03 (hôm nay), câu lệnh sẽ lọc đơn hàng từ:
  2026-10-02 00:00:00 (đầu ngày hôm qua)
  đến 2026-10-03 00:00:00 (trước 0 giờ hôm nay)
  Đảm bảo chính xác 24 giờ của ngày hôm qua, không thừa, không thiếu.
=============================================================================================
*/

-- ------------------------------------------------------------------------------------------
-- Câu 3.3:
-- Trích xuất danh sách tất cả các đơn hàng được giao thành công tới tay khách hàng trong tháng 03/2018
-- (không phụ thuộc vào việc đơn đó được đặt mua vào thời gian nào).
-- Kết quả cần hiển thị thêm số ngày giao hàng thực tế kể từ lúc đặt hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3 TẠI ĐÂY:

select 
    orders.*,
    datediff(day, orders.order_purchase_timestamp, orders.order_delivered_customer_date) AS day_diff
from dbo.olist_orders_dataset orders 
where orders.order_delivered_customer_date >= '2018-03-01 00:00:00'
    and orders.order_delivered_customer_date < '2018-04-01 00:00:00'
    and orders.order_status = 'delivered'
    and orders.order_purchase_timestamp is not null 
    and orders.order_delivered_customer_date is not null



-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 4]: HIGH-WATER MARK & INCREMENTAL EXTRACTION CƠ BẢN
-- ------------------------------------------------------------------------------------------

-- Câu 4.1:
-- Khai báo mốc Watermark lần chạy trước là '2018-06-01 00:00:00'.
-- Viết câu lệnh Incremental Extraction chỉ trích xuất các đơn hàng mới phát 
-- sinh sau mốc này.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1 TẠI ĐÂY:

declare @watermark datetime = '2018-06-01 00:00:00'

select *
from dbo.olist_orders_dataset orders 
where orders.order_purchase_timestamp > @watermark
order by orders.order_purchase_timestamp asc;


-- ------------------------------------------------------------------------------------------
-- Câu 4.2:
-- Từ đợt trích xuất Incremental theo mốc Watermark '2018-06-01 00:00:00' ở Câu 4.1:
-- Hãy tính toán:
-- 1. Tổng số bản ghi mới lấy được.
-- 2. Giá trị New High-Water Mark cần ghi nhận lại cho lần chạy kế tiếp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2 TẠI ĐÂY:

declare @watermark datetime = '2018-06-01 00:00:00';
with Incremental_orders as (
    select 
        orders.order_id,
        orders.order_purchase_timestamp,
        orders.order_status
    from dbo.olist_orders_dataset orders
    where orders.order_purchase_timestamp > @watermark
)
select 
    count(order_id) as Total_Rows,
    max(order_purchase_timestamp) as New_High_Water_Mark
from Incremental_orders

-- ------------------------------------------------------------------------------------------
-- Câu 4.3:
-- Viết truy vấn Incremental Extraction lấy các đánh giá (Reviews) mới phát sinh sau ngày '2018-01-01'.
-- Đồng thời xác định mốc thời gian đánh giá mới nhất và tổng số lượng đánh giá trong đợt tải này.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3 TẠI ĐÂY:

declare @watermark datetime = '2018-01-01 00:00:00';

with review_in as (
    select 
        reviews.review_id,
        reviews.review_score,
        reviews.review_comment_message,
        reviews.review_creation_date,
        reviews.review_answer_timestamp
    from dbo.olist_order_reviews_dataset reviews
    where reviews.review_creation_date > @watermark
)
select 
    count(r.review_id) as total_rows,
    max(r.review_creation_date) as new_high_water_mark
from review_in r

<<<<<<< HEAD
=======

>>>>>>> elt/main
-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 5]: INCREMENTAL VỚI CREATED_AT VS UPDATED_AT (XỬ LÝ DỮ LIỆU ĐỔI TRẠNG THÁI)
-- ------------------------------------------------------------------------------------------

-- Câu 5.1:
-- Khi hệ thống nguồn phát sinh cập nhật đơn hàng (đổi trạng thái giao dịch), nếu chỉ lọc theo
-- ngày tạo đơn thì pipeline sẽ bỏ sót các bản ghi này.
-- Hãy viết truy vấn trích xuất toàn bộ các đơn hàng có BẤT KỲ sự thay đổi nào sau mốc '2018-08-01'
-- dựa trên mốc cập nhật gần nhất của từng đơn hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 5.1 TẠI ĐÂY:

declare @incremental datetime = '2018-08-01 00:00:00';


SELECT 
    orders.*,
    update_info.last_updated_at
FROM dbo.olist_orders_dataset orders
CROSS APPLY (
    SELECT MAX(event_time) AS last_updated_at
    FROM (VALUES 
        (orders.order_purchase_timestamp),
        (orders.order_approved_at),
        (orders.order_delivered_carrier_date),
        (orders.order_delivered_customer_date)
    ) AS status_events(event_time)
) update_info
WHERE update_info.last_updated_at >= @incremental
ORDER BY update_info.last_updated_at ASC;


-- ------------------------------------------------------------------------------------------
-- Câu 5.2:
-- Trích xuất tất cả các đơn hàng phát sinh trạng thái HỦY BỎ hoặc SỰ CỐ sau mốc Watermark '2018-01-01'
-- để phục vụ luồng cập nhật trạng thái đơn hàng vào Data Warehouse.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 5.2 TẠI ĐÂY:

declare @watermark datetime = '2018-01-01 00:00:00'; 

select 
    orders.*
from dbo.olist_orders_dataset orders
cross apply (
    select MAX(event_time) as last_updated_at
    from (values 
        (orders.order_purchase_timestamp),
        (orders.order_approved_at),
        (orders.order_delivered_carrier_date),
        (orders.order_delivered_customer_date)
    ) as status_events(event_time)
) update_info
where update_info.last_updated_at >= @watermark
    and orders.order_status in ('canceled', 'unavailable')
    

-- ------------------------------------------------------------------------------------------
-- Câu 5.3:
-- Nhằm tránh thất thoát các giao dịch đang trong tiến trình xử lý (chưa kịp commit vào DB nguồn
-- tại thời điểm chốt Watermark), hãy viết truy vấn trích xuất đơn hàng có cơ chế cửa sổ an toàn
-- (Lookback Safety Window lùi lại 2 giờ so với mốc Watermark '2018-05-01 12:00:00').
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 5.3 TẠI ĐÂY:

declare @watermark datetime = '2018-05-01 12:00:00';
declare @safe_window datetime = dateadd(hour, -2, @watermark);

SELECT 
    orders.*,
    update_info.last_updated_at
FROM dbo.olist_orders_dataset orders
CROSS APPLY (
    SELECT MAX(event_time) AS last_updated_at
    FROM (VALUES 
        (orders.order_purchase_timestamp),
        (orders.order_approved_at),
        (orders.order_delivered_carrier_date),
        (orders.order_delivered_customer_date)
    ) AS status_events(event_time)
) update_info
WHERE update_info.last_updated_at >= @safe_window
ORDER BY update_info.last_updated_at ASC;


-- Cần ôn lại cross apply
-- Cross apply hoạt động tương tự như một vòng lặp (FOR LOOP) trong SQL Server
-- Nó áp dụng table-valued function (nếu dùng TVF) hoặc subquery (nếu dùng CROSS APPLY trực tiếp)
-- cho từng dòng của bảng bên trái (parent table).
-- Kết quả là sự kết hợp giữa tất cả các hàng từ bảng trái và các hàng tương ứng từ vế phải.
-- Trong truy vấn trên:
-- - Bảng bên trái là dbo.olist_orders_dataset (orders).
-- - Vế phải là subquery với VALUES chứa 4 cột thời gian trạng thái của đơn hàng.
-- - SQL Server xử lý từng hàng của 'orders', sau đó thực hiện subquery để tìm ra thời gian cập nhật gần nhất (last_updated_at).
-- - Cuối cùng, nó kết hợp cột 'orders.*' với 'last_updated_at' và lọc theo điều kiện thời gian.
-- - Điều này cho phép xử lý logic 

-- Câu 6.1:
-- Thiết kế một bảng lưu trữ metadata kiểm soát Watermark cho các pipeline ETL.
-- Bảng cần lưu: tên bảng nguồn, cột dùng làm watermark, giá trị watermark hiện tại,
-- thời điểm chạy gần nhất và số dòng đã trích xuất của đợt chạy trước.
-- Khởi tạo dữ liệu mẫu cho bảng đơn hàng với mốc khởi điểm '2016-01-01 00:00:00'.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 6.1 TẠI ĐÂY:

declare @watermark datetime = '2016-01-01 00:00:00';
declare @current_timestamp datetime = getdate();

CREATE TABLE dbo.Pipeline_Control (
    pipeline_name NVARCHAR(255) NOT NULL,
    source_table NVARCHAR(255) NOT NULL,
    watermark_column NVARCHAR(255) NOT NULL,
    current_watermark DATETIME,
    last_execution_time DATETIME,
    rows_extracted_last_run INT,
    PRIMARY KEY (pipeline_name, source_table)
);

INSERT INTO dbo.Pipeline_Control (
    pipeline_name, source_table, watermark_column, current_watermark, last_execution_time, rows_extracted_last_run
) VALUES (
    'Incremental_Orders_Pipeline', 'olist_orders_dataset', 'order_purchase_timestamp', @watermark, @current_timestamp, 0
);

SELECT * FROM dbo.Pipeline_Control;


-- ------------------------------------------------------------------------------------------
-- Câu 6.2:
-- Viết luồng xử lý:
-- 1. Lấy giá trị Watermark hiện tại từ bảng metadata đã tạo ở Câu 6.1.
-- 2. Trích xuất các bản ghi mới từ bảng đơn hàng vào một bảng tạm Staging.
-- 3. Kiểm tra số lượng bản ghi đã nạp vào Staging.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 6.2 TẠI ĐÂY:

declare @watermark datetime;

select @watermark = current_watermark
from dbo.Pipeline_Control
where pipeline_name = 'Incremental_Orders_Pipeline' 
    and source_table = 'olist_orders_dataset';

-- Xóa bảng tạm nếu đã tồn tại trước đó và trích xuất dữ liệu mới vào Staging
drop table if exists #staging_new_orders;

-- Trích xuất dữ liệu mới vào Staging
select *
into #staging_new_orders
from dbo.olist_orders_dataset
where order_purchase_timestamp >= @watermark; 

-- Kiểm tra số lượng bản ghi đã nạp vào Staging
SELECT COUNT(*) AS total_rows_staged FROM #staging_new_orders;

SELECT TOP 10 * FROM #staging_new_orders;


-- ------------------------------------------------------------------------------------------
-- Câu 6.3:
-- Viết câu lệnh cập nhật lại giá trị Watermark mới và số lượng bản ghi đã xử lý vào bảng metadata
-- sau khi bước trích xuất ở Câu 6.2 hoàn thành (đảm bảo không làm hỏng giá trị cũ nếu đợt nạp không có dữ liệu mới).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 6.3 TẠI ĐÂY:

-- 1. Khai báo biến
DECLARE @new_watermark DATETIME;
DECLARE @rows_extracted INT;

-- 2. Lấy đồng thời mốc thời gian lớn nhất và số lượng dòng từ Staging
SELECT 
    @new_watermark = MAX(order_purchase_timestamp),
    @rows_extracted = COUNT(*)
FROM #staging_new_orders;

-- 3. Cập nhật bảng metadata
UPDATE dbo.Pipeline_Control
SET 
    -- Nếu @new_watermark là NULL (không có dòng nào), giữ nguyên current_watermark
    current_watermark = ISNULL(@new_watermark, current_watermark),
    last_execution_time = GETDATE(),
    rows_extracted_last_run = @rows_extracted
WHERE pipeline_name = 'Incremental_Orders_Pipeline'
  AND source_table = 'olist_orders_dataset';

-- 4. Kiểm tra lại bảng metadata sau khi update
SELECT * FROM dbo.Pipeline_Control;




-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 7]: TỔNG HỢP VÀ TỰ ĐỘNG HÓA PIPELINE TRÍCH XUẤT
-- ------------------------------------------------------------------------------------------

-- Câu 7.1:
-- Bảng chi tiết mặt hàng không có cột thời gian cập nhật riêng.
-- Hãy viết truy vấn trích xuất toàn bộ chi tiết mặt hàng tương ứng với các đơn hàng mới phát sinh
-- sau mốc Watermark '2018-07-01'.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 7.1 TẠI ĐÂY:

select 
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    i.shipping_limit_date,
    i.price,
    i.freight_value
from dbo.olist_order_items_dataset i
inner join dbo.olist_orders_dataset o 
    on i.order_id = o.order_id
where o.order_purchase_timestamp >= '2018-07-01';

-- ------------------------------------------------------------------------------------------
-- Câu 7.2:
-- Xây dựng một khối lệnh SQL có khả năng tự động nhận diện chế độ tải:
-- - Nếu tham số Watermark đầu vào bị rỗng/NULL: Tự động kích hoạt quy trình Full Extraction.
-- - Nếu tham số Watermark đã có giá trị: Tự động chuyển sang quy trình Incremental Extraction.
-- In thông báo trạng thái chế độ nạp tương ứng ra màn hình.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 7.2 TẠI ĐÂY:

declare @watermark datetime = '2018-06-01'; -- Gán = NULL để chạy Full Extraction

if @watermark is null
begin
    print N'>>> KÍCH HOẠT CHẾ ĐỘ: FULL EXTRACTION (Trích xuất toàn bộ dữ liệu)';
    select * 
    from dbo.olist_orders_dataset;
end
else
begin
    print N'>>> KÍCH HOẠT CHẾ ĐỘ: INCREMENTAL EXTRACTION từ mốc: ' + cast(@watermark as varchar);
    select * 
    from dbo.olist_orders_dataset
    where order_purchase_timestamp >= @watermark;
end;

-- ------------------------------------------------------------------------------------------
-- Câu 7.3:
-- Đóng gói quy trình trích xuất đơn hàng thành một Stored Procedure hoàn chỉnh:
-- - Nhận tham số: mốc Watermark đầu vào và giới hạn số lượng bản ghi mỗi đợt (batch size).
-- - Trả về tập dữ liệu delta được sắp xếp tăng dần theo thời gian.
-- - Trả về giá trị New Watermark cao nhất của đợt dữ liệu đó thông qua tham số OUTPUT.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 7.3 TẠI ĐÂY:

create or alter procedure dbo.usp_extract_orders_delta
    @p_watermark datetime,
    @p_batch_size int = 1000,
    @p_new_watermark datetime output
as
begin
    set nocount on;

    -- Trả về tập dữ liệu delta được sắp xếp tăng dần theo thời gian
    select top (@p_batch_size) *
    from dbo.olist_orders_dataset
    where order_purchase_timestamp >= isnull(@p_watermark, '1900-01-01')
    order by order_purchase_timestamp asc;

    -- Lấy New Watermark cao nhất của đợt vừa lấy
    select @p_new_watermark = max(order_purchase_timestamp)
    from (
        select top (@p_batch_size) order_purchase_timestamp
        from dbo.olist_orders_dataset
        where order_purchase_timestamp >= isnull(@p_watermark, '1900-01-01')
        order by order_purchase_timestamp asc
    ) as batch;
end;
go
