-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 3: KIẾN TRÚC DATA PIPELINE & DATA WAREHOUSING (END-TO-END DATA ENGINEERING)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 1: INCREMENTAL LOAD PIPELINE (TRÍCH XUẤT DỮ LIỆU GIA TĂNG)
-- Luồng chuẩn: Source → Watermark → Extract Changed Data → Transform → Load → Update Watermark
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 1]: FULL LOAD VS INCREMENTAL LOAD CƠ BẢN
-- ------------------------------------------------------------------------------------------

-- Câu 1.1.1:
-- Xây dựng kịch bản khởi tạo dữ liệu ban đầu (Initial Full Load):
-- Trích xuất toàn bộ dữ liệu đơn hàng hợp lệ từ hệ thống nguồn sang bảng lưu trữ phân tích,
-- đồng thời ghi nhận mốc thời gian hoàn tất để thiết lập mốc Watermark khởi điểm cho pipeline.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1.1 TẠI ĐÂY:


-- 1. Tạo Schema 'stg' nếu chưa có (Dùng EXEC vì CREATE SCHEMA yêu cầu batch riêng trong SQL Server)
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'stg')
BEGIN
    EXEC('CREATE SCHEMA stg');
END
GO

-- 2. Initial Full Load: Dùng cú pháp SELECT ... INTO của SQL Server
IF OBJECT_ID('stg.stg_orders', 'U') IS NOT NULL 
    DROP TABLE stg.stg_orders;

SELECT 
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_approved_at,
    orders.order_delivered_carrier_date,
    orders.order_delivered_customer_date,
    orders.order_estimated_delivery_date,
    CURRENT_TIMESTAMP AS loaded_at
INTO stg.stg_orders
FROM dbo.olist_orders_dataset orders
WHERE orders.order_id IS NOT NULL
  AND orders.order_purchase_timestamp IS NOT NULL
  AND orders.order_status NOT IN ('canceled', 'unavailable');
GO

-- 3. Tạo bảng quản lý Watermark (Bắt buộc dùng DATETIME2 thay vì TIMESTAMP)
IF OBJECT_ID('stg.pipeline_watermark', 'U') IS NULL
BEGIN
    CREATE TABLE stg.pipeline_watermark (
        pipeline_name     VARCHAR(100) PRIMARY KEY,
        watermark_column  VARCHAR(50),
        watermark_value   DATETIME2,
        last_run_at       DATETIME2,
        status            VARCHAR(20)
    );
END
GO

-- 4. Ghi nhận Watermark khởi điểm (Dùng VALUES có chữ 's')
INSERT INTO stg.pipeline_watermark (
    pipeline_name,
    watermark_column,
    watermark_value,
    last_run_at,
    status
) 
VALUES (
    'olist_orders_pipeline',
    'order_purchase_timestamp',
    (SELECT MAX(order_purchase_timestamp) FROM stg.stg_orders),
    CURRENT_TIMESTAMP,
    'SUCCESS'
);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (INITIAL FULL LOAD & WATERMARK INITIALIZATION):
-- 1. Bài toán giải quyết ("Khởi động nguội" - Cold Start):
--    - Khi mới xây dựng kho dữ liệu (kho đang trống rỗng), hệ thống bắt buộc phải nạp toàn bộ lịch sử (Full Load)
--      để làm dữ liệu nền tảng ban đầu (Ground Zero).
-- 2. Thiết lập vạch xuất phát (Pipeline Watermark Table):
--    - Tạo bảng quản lý trạng thái stg.pipeline_watermark để ghi nhớ "ký ức" của pipeline (State Management).
--    - Cột watermark_value lưu lại mốc thời gian lớn nhất thực tế của đợt nạp ban đầu,
--      đóng vai trò là "vạch xuất phát" để từ các chu kỳ sau hệ thống tự động chuyển sang chạy gia tăng (Incremental Load).



-- ------------------------------------------------------------------------------------------
-- Câu 1.1.2:
-- Viết truy vấn Incremental Load định kỳ:
-- Chỉ trích xuất các đơn hàng mới phát sinh hoặc có cập nhật kể từ sau mốc chạy thành công
-- gần nhất ('last_successful_timestamp = 2018-06-01 00:00:00').
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1.2 TẠI ĐÂY:

declare @last_successful_timestamp datetime2 = '2018-06-01 00:00:00'

select 
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_approved_at,
    orders.order_delivered_carrier_date,
    orders.order_delivered_customer_date,
    orders.order_estimated_delivery_date,
    CURRENT_TIMESTAMP as loaded_at
from dbo.olist_orders_dataset orders
where orders.order_id is not null
    and orders.order_status not in ('canceled','unavailable')
    and( orders.order_purchase_timestamp > @last_successful_timestamp
        or orders.order_approved_at > @last_successful_timestamp
        or orders.order_delivered_carrier_date > @last_successful_timestamp
        or orders.order_delivered_customer_date > @last_successful_timestamp
        or orders.order_estimated_delivery_date > @last_successful_timestamp);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (INCREMENTAL LOAD ĐỊNH KỲ):
-- 1. Bài toán giải quyết (Tối ưu tài nguyên & Tránh nghẽn hệ thống nguồn):
--    - Thay vì ngày nào cũng quét lại toàn bộ triệu dòng lịch sử, pipeline chỉ quét các bản ghi mới phát sinh
--      hoặc có biến động sau mốc thành công gần nhất (WHERE timestamp > @last_successful_timestamp).
-- 2. Xử lý đa mốc thời gian (Multi-timestamp CDC):
--    - Kiểm tra cả 5 mốc thời gian (purchase, approved, carrier, customer, estimated) giúp bắt trọn
--      những đơn hàng cũ đã tạo từ trước nhưng vừa mới cập nhật trạng thái giao nhận trong đợt quét này.


-- ------------------------------------------------------------------------------------------
-- Câu 1.1.3:
-- Đo lường hiệu năng và tài nguyên giữa hai phương pháp:
-- So sánh số lượng bản ghi phải quét và khối lượng dữ liệu xử lý giữa việc quét Full Load toàn bảng
-- so với việc chỉ quét gia tăng Incremental Load trên cùng bảng đơn hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.1.3 TẠI ĐÂY:

declare @last_successful_timestamp DATETIME2 = '2018-06-01 00:00:00';

WITH metrics AS (
    SELECT 
        COUNT(*) AS full_load_records,
        COUNT(CASE 
            WHEN (orders.order_purchase_timestamp > @last_successful_timestamp
               OR orders.order_approved_at > @last_successful_timestamp
               OR orders.order_delivered_carrier_date > @last_successful_timestamp
               OR orders.order_delivered_customer_date > @last_successful_timestamp
               OR orders.order_estimated_delivery_date > @last_successful_timestamp)
            THEN 1 
        END) AS incremental_load_records
    FROM dbo.olist_orders_dataset orders
    WHERE orders.order_id IS NOT NULL
      AND orders.order_status NOT IN ('canceled', 'unavailable')
)
SELECT 
    full_load_records,
    incremental_load_records,
    (full_load_records - incremental_load_records) AS records_saved,
    ROUND((1.0 - CAST(incremental_load_records AS FLOAT) / full_load_records) * 100, 2) AS pct_resource_saved
FROM metrics;

SET STATISTICS IO ON;
SET STATISTICS TIME ON;

SELECT * FROM dbo.olist_orders_dataset;

SELECT * FROM dbo.olist_orders_dataset
WHERE order_purchase_timestamp > '2018-06-01 00:00:00';

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (BENCHMARK & ĐO LƯỜNG HIỆU QUẢ KINH TẾ):
-- 1. Mục đích sử dụng (Đo kiểm & Bằng chứng định lượng):
--    - Đây là câu truy vấn Benchmark dùng trong môi trường kiểm thử (Testing/Audit) để đo lường định lượng,
--      không phải câu lệnh chạy trong luồng nạp ETL tự động hàng ngày.
-- 2. Giá trị kinh tế & Kỹ thuật:
--    - So sánh trực quan số dòng phải quét: Full Load (~99k dòng) vs Incremental Load (~vài nghìn dòng).
--    - Dùng pct_resource_saved và SET STATISTICS IO/TIME ON để chứng minh mức độ tiết kiệm
--      tài nguyên CPU, RAM và chi phí điện toán đám mây (Cloud Compute Cost) lên tới 80% - 95%.


-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 2]: QUẢN LÝ HIGH-WATER MARK DỘNG
-- ------------------------------------------------------------------------------------------

-- Câu 1.2.1:
-- Sau khi trích xuất thành công một đợt dữ liệu gia tăng từ mốc Watermark cũ:
-- Hãy tính toán và xác định giá trị New High-Water Mark (mốc thời gian lớn nhất thực tế của đợt dữ liệu vừa lấy)
-- để sẵn sàng bàn giao cho lần chạy tiếp theo.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2.1 TẠI ĐÂY:

select 
    max(orders.order_purchase_timestamp) as new_high_watermark
from dbo.olist_orders_dataset orders
where orders.order_purchase_timestamp >  (
    select watermark_value 
    from stg.pipeline_watermark s
    where s.pipeline_name =  'olist_orders_pipeline'
);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (DYNAMIC HIGH-WATER MARK):
-- 1. Mục đích hoạt động:
--    - Sau mỗi chu kỳ nạp gia tăng thành công, hệ thống cần tính toán mốc thời gian lớn nhất thực tế (MAX)
--      của đợt dữ liệu vừa trích xuất để làm vạch xuất phát mới cho chu kỳ tiếp theo.
-- 2. Nguyên tắc an toàn dữ liệu:
--    - Chỉ lấy MAX(timestamp) thực tế của dữ liệu nguồn đã nạp thành công, TUYỆT ĐỐI KHÔNG dùng CURRENT_TIMESTAMP.
--      Vì thời gian hệ thống chạy có thể đi trước thời gian giao dịch thực tế, dễ gây bỏ sót dữ liệu đến trễ (Late-Arriving Data).

-- ------------------------------------------------------------------------------------------
-- Câu 1.2.2:
-- Với các bảng không có cột thời gian cập nhật đáng tin cậy nhưng có khóa chính dạng số nguyên tự tăng:
-- Hãy thiết kế truy vấn Incremental Load dựa trên Numeric / Sequence Watermark
-- để lấy các bản ghi chi tiết mới có số khóa lớn hơn mốc khóa đã xử lý lần trước.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2.2 TẠI ĐÂY:

declare @last_processed_id int = 1

select 
    *
from dbo.olist_order_items_dataset items
where items.order_item_id > @last_processed_id;

-- GHI CHÚ KIẾN TRÚC & ĐIỀU KIỆN ÁP DỤNG (NUMERIC / SEQUENCE WATERMARK):
-- 1. Khi nào sử dụng:
--    - Bảng nguồn hoàn toàn KHÔNG có cột thời gian (created_at / updated_at).
--    - Cột thời gian không đáng tin cậy (sai lệch múi giờ, hệ thống ghi đè mà không cập nhật ngày giờ).
-- 2. Cột ID có bắt buộc là Primary Key không?:
--    - KHÔNG BẮT BUỘC phải là Primary Key.
--    - Nhưng BẮT BUỘC phải thỏa mãn tính chất "TĂNG DẦN ĐỀU THEO THỜI GIAN" (Monotonically Increasing):
--      Bản ghi nào tạo ra sau thì giá trị ID/Sequence luôn lớn hơn bản ghi tạo ra trước.
--    - Trong thực tế 90% chọn Primary Key vì cột này thường có Clustered Index, giúp mệnh đề WHERE > @last_id quét cực nhanh.
-- 3. Hạn chế sống còn & Lưu ý nghiệp vụ:
--    - Chỉ dùng được cho dữ liệu "Chỉ thêm mới" (Append-Only / Insert-Only). Nếu bản ghi cũ bị sửa đổi, cách này sẽ bỏ sót.
--    - Đối với bảng olist_order_items_dataset, `order_item_id` chỉ là số thứ tự món trong từng đơn (1, 2, 3...),
--      trong hệ thống thực tế cần một cột ID tăng dần toàn cục (Global Identity / Sequence) mới làm Watermark độc lập được.


-- ------------------------------------------------------------------------------------------
-- Câu 1.2.3:
-- Xử lý trường hợp đợt chạy không có dữ liệu mới phát sinh (Zero-records Batch):
-- Đảm bảo logic truy vấn không làm thay đổi hay làm mất giá trị mốc Watermark hợp lệ trước đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.2.3 TẠI ĐÂY:

select 
    coalesce(
        max(orders.order_purchase_timestamp), 
        (select watermark_value 
        from stg.pipeline_watermark s1
        where s1.pipeline_name = 'olist_orders_pipeline' )) as safe_high_watermark
from dbo.olist_orders_dataset orders
where orders.order_purchase_timestamp >  (
    select watermark_value 
    from stg.pipeline_watermark s
    where s.pipeline_name =  'olist_orders_pipeline'
);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (ZERO-RECORDS BATCH):
-- 1. Vấn đề thực tế ("Bẫy chết đứng lúc nửa đêm"):
--    - Khi pipeline chạy vào khung giờ thấp điểm (ban đêm) không có đơn hàng nào phát sinh,
--      tập dữ liệu quét được sẽ rỗng (0 dòng) -> Hàm MAX() sẽ trả về giá trị NULL.
--    - Nếu lấy NULL ghi đè vào bảng pipeline_watermark, ở lần chạy kế tiếp mệnh đề WHERE > NULL
--      sẽ luôn trả về False/Unknown, khiến pipeline bị tê liệt vĩnh viễn không thể lấy thêm dữ liệu mới.
-- 2. Giá trị giải pháp mang lại (Hàm COALESCE):
--    - Cơ chế phòng vệ tự động (Self-Healing): Khi MAX() bị NULL, COALESCE lập tức lấy mốc cũ đắp vào để bảo toàn mốc an toàn.
--    - Giúp toàn bộ hệ thống pipeline tự vận hành trơn tru và bền bỉ 24/7 mà không cần kỹ sư can thiệp thủ công.



-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 3]: LOOKBACK WINDOW & BẮT DỮ LIỆU ĐẾN TRỄ (LATE-ARRIVING DATA)
-- ------------------------------------------------------------------------------------------

-- Câu 1.3.1:
-- Để chống thất thoát các giao dịch đang diễn ra dở dang lúc chốt mốc (chưa kịp commit vào DB nguồn):
-- Hãy viết truy vấn trích xuất có cơ chế quét lùi an toàn (Lookback Safety Margin lùi lại 15 phút
-- so với mốc Watermark '2018-05-01 10:00:00', tức quét từ 09:45:00).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3.1 TẠI ĐÂY:

declare @watermark datetime2 =  '2018-05-01 10:00:00' 

select 
*
from dbo.olist_orders_dataset orders 
where orders.order_purchase_timestamp <= @watermark 
    and orders.order_purchase_timestamp >= dateadd(minute, -15, @watermark);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (LOOKBACK SAFETY MARGIN):
-- 1. Vấn đề thực tế (Giao dịch dang dở - In-Flight Transactions):
--    - Trong CSDL OLTP, các giao dịch (Transactions) cần thời gian xử lý (gọi cổng thanh toán, trừ tồn kho...).
--    - Một đơn hàng khởi tạo lúc 09:55:00 nhưng đến 10:02:00 mới hoàn tất COMMIT. Nếu pipeline chạy lúc 10:00:00,
--      do cơ chế phân lập (Read Committed) nên đơn này chưa hiển thị -> Bị bỏ sót vĩnh viễn nếu lần chạy sau chỉ quét từ > 10:00:00 (Silent Data Loss).
-- 2. Giá trị giải pháp mang lại (Cơ chế quét lùi Lookback Window):
--    - Chủ động lùi mốc thời gian bắt đầu quét lại một khoảng an toàn (Safety Margin 15 phút: DATEADD(MINUTE, -15, @watermark)).
--    - Đảm bảo "vớt" trọn vẹn 100% mọi giao dịch được tạo trước thời điểm chốt mốc nhưng bị commit trễ vào hệ thống.
-- 3. Đánh đổi kỹ thuật (Trade-off & Idempotency):
--    - Quét lùi sẽ gây ra hiện tượng quét trùng lặp dữ liệu (Overlapping/Duplicate Records) đối với các đơn đã nạp từ 09:45 đến 10:00.
--    - Bắt buộc tầng Staging/Silver phía sau phải có cơ chế khử trùng lặp (Deduplication / Upsert) để bảo đảm tính lũy thừa (Idempotency).


-- ------------------------------------------------------------------------------------------
-- Câu 1.3.2:
-- Phát hiện dữ liệu đến trễ (Late-Arriving Records):
-- Tìm các đơn hàng có thời gian tạo đơn rơi vào các ngày trước đó nhưng mốc cập nhật hoàn
--  tất giao dịch
-- lại mới xuất hiện trong đợt quét gia tăng của ngày hôm nay.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3.2 TẠI ĐÂY:

DECLARE @batch_start DATETIME2 = '2018-05-01 00:00:00';
DECLARE @batch_end   DATETIME2 = '2018-05-01 23:59:59';

SELECT 
    order_id,
    order_status,
    order_purchase_timestamp,
    order_delivered_customer_date,
    DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date) AS days_delayed
FROM dbo.olist_orders_dataset
WHERE order_delivered_customer_date >= @batch_start 
  AND order_delivered_customer_date <= @batch_end
  AND order_purchase_timestamp < @batch_start;

  -- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (LATE-ARRIVING DATA):
-- 1. Vấn đề thực tế (Độ trễ chu trình nghiệp vụ - Business Lifecycle Lag):
--    - Một đơn hàng thương mại điện tử trải qua nhiều trạng thái (tạo đơn -> thanh toán -> vận chuyển -> giao thành công).
--    - Nếu pipeline trích xuất chỉ dựa vào ngày tạo đơn (`order_purchase_timestamp`), toàn bộ các trạng thái giao hàng
--      hoặc hủy đơn phát sinh nhiều ngày sau đó sẽ BỊ BỎ RƠI HOÀN TOÀN (Lost Updates).
-- 2. Giá trị giải pháp mang lại (Phát hiện dữ liệu đến trễ):
--    - Dùng mốc hoàn tất giao dịch (`order_delivered_customer_date` hoặc `updated_at`) để tóm gọn các bản ghi cũ
--      nhưng có phát sinh trạng thái mới trong ngày hôm nay.
-- 3. Tác động kiến trúc tới Data Warehouse (Bắt buộc dùng UPSERT):
--    - Vì đơn hàng này đã tồn tại trong Data Warehouse từ các ngày trước ở trạng thái cũ, nên khi nạp dữ liệu đợt này,
--      hệ thống BẮT BUỘC phải dùng chiến lược MERGE/UPSERT (thay vì INSERT thuần túy) để cập nhật lại ngày giao và trạng thái `delivered`.

-- ------------------------------------------------------------------------------------------
-- Câu 1.3.3:
-- Kiểm soát việc quét trùng lặp do Lookback Window tạo ra:
-- Viết câu lệnh đảm bảo rằng việc quét lùi 15 phút không làm phát sinh dữ liệu trùng lặp ở tầng Staging tiếp theo.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.3.3 TẠI ĐÂY:

DECLARE @watermark DATETIME2 = '2018-05-01 10:00:00';

MERGE INTO stg.stg_orders AS tgt
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
    FROM dbo.olist_orders_dataset
    WHERE order_purchase_timestamp >= DATEADD(MINUTE, -15, @watermark)
) AS src
ON tgt.order_id = src.order_id
WHEN MATCHED THEN
    UPDATE SET 
        tgt.order_status = src.order_status,
        tgt.order_approved_at = src.order_approved_at,
        tgt.order_delivered_carrier_date = src.order_delivered_carrier_date,
        tgt.order_delivered_customer_date = src.order_delivered_customer_date,
        tgt.loaded_at = CURRENT_TIMESTAMP
WHEN NOT MATCHED THEN
    INSERT (
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp,
        order_approved_at,
        order_delivered_carrier_date,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        loaded_at
    )
    VALUES (
        src.order_id,
        src.customer_id,
        src.order_status,
        src.order_purchase_timestamp,
        src.order_approved_at,
        src.order_delivered_carrier_date,
        src.order_delivered_customer_date,
        src.order_estimated_delivery_date,
        CURRENT_TIMESTAMP
    );

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (CHỐNG TRÙNG LẶP DO LOOKBACK - IDEMPOTENCY):
-- 1. Vấn đề thực tế (Trùng lặp dữ liệu do quét gối đầu - Overlapping Window):
--    - Khi quét lùi 15 phút, toàn bộ các đơn hàng hợp lệ đã nạp ở chu kỳ trước sẽ bị quét lại.
--    - Nếu dùng lệnh `INSERT INTO` thuần túy, bảng Staging sẽ bị lỗi vi phạm khóa chính (Primary Key Violation)
--      hoặc xuất hiện hàng loạt bản ghi trùng lặp (Duplicate Records) làm sai lệch các chỉ số kinh doanh.
-- 2. Giá trị giải pháp mang lại (Cơ chế UPSERT qua lệnh MERGE):
--    - Bản ghi chưa tồn tại (đơn commit muộn vừa vét được) -> Kích hoạt `WHEN NOT MATCHED` để INSERT mới.
--    - Bản ghi đã tồn tại từ đợt chạy trước -> Kích hoạt `WHEN MATCHED` để UPDATE các mốc trạng thái mới nhất.
-- 3. Nguyên lý thiết kế cốt lõi (Tính lũy thừa - Idempotency):
--    - Pipeline thỏa mãn tính chất Idempotent: Dù pipeline có bị chạy lại 1 lần hay 10 lần với cùng một khoảng
--      thời gian Lookback, dữ liệu đích trong bảng Staging vẫn luôn đồng nhất và hoàn toàn không bị nhân đôi.


-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 4]: CREATED_AT VS UPDATED_AT (BẢN GHI MỚI VS BẢN GHI SỬA ĐỔI)
-- ------------------------------------------------------------------------------------------

-- Câu 1.4.1:
-- Phân loại luồng dữ liệu gia tăng:
-- Viết truy vấn trích xuất gia tăng và phân loại rõ ràng từng bản ghi thành 2 nhóm:
-- Nhóm bản ghi mới tạo hoàn toàn, và Nhóm bản ghi cũ đã tồn tại từ trước nhưng có sự thay đổi trạng thái trong đợt này.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.4.1 TẠI ĐÂY:

declare @watermark datetime2  = '2018-01-01 00:00:00'
select 
    orders.order_id,
    orders.order_purchase_timestamp,
    orders.order_status,
    case 
        when orders.order_purchase_timestamp <= @watermark then 'MODIFIED'
        when orders.order_purchase_timestamp > @watermark then 'NEW'
    end as 'record_classification'
    from dbo.olist_orders_dataset orders
where orders.order_id is not null
    and orders.order_status not in ('canceled', 'unavailable')
     and(
        orders.order_purchase_timestamp > @watermark
    or orders.order_delivered_carrier_date > @watermark
    or orders.order_approved_at > @watermark
    or orders.order_delivered_carrier_date > @watermark
    )

    -- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (PHÂN LOẠI LUỒNG GIA TĂNG - INSERT VS UPDATE CLASSIFICATION):
-- 1. Vấn đề thực tế (Độ trễ vòng đời đơn hàng & Nhập nhằng loại biến động):
--    - Trong một chu kỳ trích xuất gia tăng (Incremental Batch), dữ liệu gom được luôn chứa 2 dạng biến động lẫn lộn:
--      đơn hàng mới phát sinh và đơn hàng cũ từ nhiều ngày trước nay mới cập nhật trạng thái giao nhận.
--    - Nếu không phân loại ngay từ tầng trích xuất, pipeline downstream sẽ xử lý mù mờ, không phân biệt được
--      đâu là tăng trưởng kinh doanh mới (New Acquisition) và đâu chỉ là cập nhật trạng thái vận hành (Lifecycle Event).
-- 2. Giá trị giải pháp mang lại (Gắn nhãn phân loại dựa trên ranh giới Watermark):
--    - Dùng mốc tạo gốc (`order_purchase_timestamp`) làm thước đo đối chiếu với vạch xuất phát (`@watermark`):
--      + `> @watermark`: Khẳng định 100% là đơn vừa phát sinh trong chu kỳ này -> Gắn nhãn `NEW`.
--      + `<= @watermark`: Khẳng định là đơn cũ từ các chu kỳ trước, lọt vào đợt này do có mốc trạng thái mới -> Gắn nhãn `MODIFIED`.
--    - Cho phép phân loại chính xác ngay tại nguồn mà không cần thực hiện các phép JOIN tốn kém với bảng đích.
-- 3. Tối ưu hóa chiến lược UPSERT (Phân làn nạp kho - Traffic Splitting):
--    - Bản ghi `NEW` -> Bỏ qua bước so khớp khóa (Matching), nạp thẳng bằng `INSERT INTO` (Bulk Insert) tốc độ cao.
--    - Bản ghi `MODIFIED` -> Chỉ tập dữ liệu nhỏ này mới cần đưa vào khối xử lý `UPDATE` hoặc `MERGE INTO`.
--    - Giúp giảm tải 60% - 80% chi phí CPU và I/O dò tìm khóa chính trên bảng đích so với việc ép 100% dữ liệu phải chạy qua MERGE.
-- 4. Chuẩn hóa kiến trúc (Mô hình hóa Change Data Capture - CDC):
--    - Tái hiện lại trường cờ thao tác chuẩn Enterprise (tương tự cột `__op` ('I'/'U'/'D') trong Debezium, AWS DMS, Fivetran).
--    - Đóng vai trò là "cầu nối dữ liệu" cốt lõi giữa Phần 1 (Incremental Load) và Phần 2 (Upsert Strategy & State Management).
-- ------------------------------------------------------------------------------------------
-- Câu 1.4.2:
-- Xây dựng mốc thời gian cập nhật tổng hợp (Effective Last Modified Timestamp):
-- Khi bảng nguồn không có sẵn một cột `updated_at` duy nhất, hãy xác định thời điểm thay đổi mới nhất
-- dựa trên phân cấp các mốc thời gian thực hiện qua từng chặng của quy trình giao dịch.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.4.2 TẠI ĐÂY:


select 
    orders.*,
    case 
        when orders.order_delivered_customer_date is not null then orders.order_delivered_customer_date
        when orders.order_delivered_carrier_date is not null then orders.order_delivered_carrier_date
        when orders.order_approved_at is not null then orders.order_approved_at
        else orders.order_purchase_timestamp
    end as 'effective_last_modified_at'
from dbo.olist_orders_dataset orders 
where orders.order_id is not null 
    and orders.order_status not in ('canceled', 'unavailable');

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (MỐC THỜI GIAN CẬP NHẬT TỔNG HỢP - EFFECTIVE LAST MODIFIED TIMESTAMP):
-- 1. Vấn đề thực tế (Sự thiếu vắng cột `updated_at` trong CSDL nghiệp vụ):
--    - Rất nhiều CSDL nguồn OLTP không duy trì một cột `updated_at` duy nhất, mà chỉ lưu rời rạc các mốc sự kiện
--      theo từng bước xử lý nghiệp vụ (`purchase`, `approved`, `carrier`, `customer`...).
--    - Điều này khiến pipeline trích xuất gia tăng gặp khó khăn trong việc xác định thời điểm thay đổi mới nhất,
--      dẫn đến mệnh đề lọc WHERE bị phình to với nhiều điều kiện OR phức tạp, gây vô hiệu hóa Index và làm suy giảm hiệu năng quét dữ liệu.
-- 2. Giá trị giải pháp mang lại (Phân cấp thời gian theo tiến trình nghiệp vụ - Waterfall Hierarchy):
--    - Dựa trên quy luật tuần tự của vòng đời đơn hàng: Mua hàng -> Duyệt tiền -> Gửi bưu tá -> Giao cho khách.
--      Chặng nào diễn ra sau cùng và KHÁC NULL thì mốc thời gian của chặng đó chính là thời điểm biến động mới nhất.
--    - Cấu trúc rẽ nhánh `CASE WHEN` (hoặc hàm `COALESCE`) đi ngược từ chặng cuối về chặng đầu giúp bắt trọn
--      mốc sự kiện mới nhất ngay lập tức nhờ cơ chế ngắt sớm (Short-circuit Evaluation).
-- 3. Ứng dụng kiến trúc Downstream (Chuẩn hóa cột Watermark & Tối ưu hóa truy vấn):
--    - Đơn giản hóa toàn diện pipeline: Thay vì phải viết chuỗi so sánh OR dài dòng, các chu kỳ nạp sau chỉ cần
--      lọc duy nhất một điều kiện trực quan: `WHERE effective_last_modified_at > @watermark`.
--    - Chuẩn hóa trường thời gian duy nhất làm tiền đề để đánh chỉ mục (Index / Partitioning) tại tầng Staging/Data Warehouse,
--      giúp tối ưu hóa tài nguyên đọc (I/O) và tốc độ đồng bộ dữ liệu.



-- ------------------------------------------------------------------------------------------
-- Câu 1.4.3:
-- Truy vết các đơn hàng có sự thay đổi về trạng thái giao nhận (ví dụ từ đang giao sang giao thành công
-- hoặc bị hủy đơn) phát sinh sau mốc Watermark để phục vụ việc cập nhật tức thời vào kho dữ liệu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.4.3 TẠI ĐÂY:


DECLARE @watermark DATETIME2 = '2018-01-01 00:00:00';

SELECT 
    order1.order_id,
    order2.order_status AS old_status,  
    order1.order_status AS new_status,
    order1.order_purchase_timestamp,
    order1.order_approved_at,
    order1.order_delivered_carrier_date,
    order1.order_delivered_customer_date,
    COALESCE(
        order1.order_delivered_customer_date,
        order1.order_delivered_carrier_date,
        order1.order_approved_at,
        order1.order_purchase_timestamp
    ) AS status_changed_at
FROM dbo.olist_orders_dataset order1
INNER JOIN stg.stg_orders order2 
    ON order1.order_id = order2.order_id
WHERE order1.order_status <> order2.order_status
  AND COALESCE(
        order1.order_delivered_customer_date,
        order1.order_delivered_carrier_date,
        order1.order_approved_at,
        order1.order_purchase_timestamp
    ) > @watermark;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (TRUY VẾT BIẾN ĐỘNG TRẠNG THÁI - STATE TRANSITION TRACKING):
-- 1. Vấn đề thực tế (Độ trễ cập nhật trạng thái đơn hàng & Thiệt hại tài chính):
--    - Một đơn hàng có thể kéo dài nhiều tuần từ khi đặt hàng tới khi giao thành công hoặc bị hủy.
--    - Nếu kho dữ liệu chỉ nạp đơn mới mà không chủ động "săn tìm" các biến động trạng thái (State Changes),
--      các báo cáo kinh doanh sẽ ghi nhận sai doanh thu thực tế, sai tỷ lệ hoàn hủy và ảnh hưởng đến đối soát công nợ với bưu cục.
-- 2. Giá trị giải pháp mang lại (Cơ chế đối chiếu hai phía Source vs Target):
--    - INNER JOIN trực tiếp giữa bảng Nguồn (`order1`) và bảng Kho (`order2`) trên khóa chính `order_id` để phát hiện
--      sự bất đồng bộ về trạng thái (`order1.order_status <> order2.order_status`).
--    - Kế thừa hàm COALESCE từ Câu 1.4.2 để làm mốc biến động sau `@watermark`, đảm bảo bắt trọn vẹn cả trường hợp
--      đơn chuyển sang giao thành công (`delivered`) lẫn đơn bị hủy (`canceled` - vốn không có ngày giao khách).
-- 3. Ứng dụng kiến trúc Downstream (Cập nhật tức thời & Kích hoạt luồng phản ứng nhanh - Reactive CDC):
--    - Tách riêng tập bản ghi đổi trạng thái để đẩy vào các pipeline ưu tiên cao (High-Priority Pipeline),
--      thực hiện UPDATE tức thì vào Data Warehouse mà không cần chờ chu kỳ chạy lô (Batch Run) cuối ngày.
--    - Phục vụ kiến trúc Microservices/Event-driven: Tự động kích hoạt các webhook hoàn tiền (khi đơn canceled)
--      hoặc gửi thông báo/khảo sát khách hàng (khi đơn delivered) ngay khi phát hiện trạng thái thay đổi.



-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 5]: TRÍCH XUẤT GIA TĂNG TRÊN QUAN HỆ NHIỀU BẢNG (MULTI-TABLE DELTA)
-- ------------------------------------------------------------------------------------------

-- Câu 1.5.1:
-- Bảng chi tiết mặt hàng bán ra không có cột mốc thời gian sửa đổi riêng:
-- Hãy viết truy vấn trích xuất toàn bộ các mặt hàng chi tiết tương ứng với danh sách các đơn hàng
-- vừa được xác định là có cập nhật trong đợt tải gia tăng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.5.1 TẠI ĐÂY:

DECLARE @watermark DATETIME2 = '2018-01-01 00:00:00';

WITH delta_orders AS (
    SELECT 
        orders.order_id
    FROM dbo.olist_orders_dataset orders 
    WHERE orders.order_id IS NOT NULL
      AND orders.order_status NOT IN ('canceled', 'unavailable')
      AND COALESCE(
            orders.order_delivered_customer_date,
            orders.order_delivered_carrier_date,
            orders.order_approved_at,
            orders.order_purchase_timestamp
      ) > @watermark
)
SELECT
    items.order_id,
    items.order_item_id,
    items.product_id,
    items.seller_id,
    items.shipping_limit_date,
    items.price,
    items.freight_value
FROM dbo.olist_order_items_dataset items 
INNER JOIN delta_orders delta 
    ON items.order_id = delta.order_id;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (KẾ THỪA WATERMARK TRÊN BẢNG CON - WATERMARK INHERITANCE):
-- 1. Vấn đề thực tế (Bảng con thiếu cột mốc thời gian biến động):
--    - Trong mô hình dữ liệu quan hệ (OLTP), các bảng chi tiết mặt hàng (`order_items`, `invoice_lines`)
--      thường không lưu trữ cột `updated_at` riêng mà phụ thuộc hoàn toàn vào tiến trình xử lý của bảng cha (`orders`).
--    - Nếu không có cơ chế liên kết bắc cầu, Data Pipeline sẽ không thể xác định dòng nào mới phát sinh,
--      buộc phải quét toàn bộ bảng con (Full Table Scan) hàng triệu dòng, gây tắc nghẽn I/O và lãng phí tài nguyên tính toán.
-- 2. Giá trị giải pháp mang lại (Cơ chế Kế thừa Watermark - Watermark Inheritance):
--    - Sử dụng khóa ngoại `order_id` làm cầu nối, "mượn" bộ lọc gia tăng từ bảng cha (`COALESCE(...) > @watermark`)
--      để kéo theo các bản ghi chi tiết tương ứng trong bảng con qua phép `INNER JOIN`.
--    - Đảm bảo trích xuất đúng và đủ các mặt hàng bị ảnh hưởng trong đợt nạp gia tăng mà bảng con không cần cột thời gian riêng.
-- 3. Yêu cầu kỹ thuật sống còn trong Production (Chỉ mục trên Khóa ngoại - Foreign Key Indexing):
--    - Để truy vấn này đạt hiệu năng tối đa, cột khóa ngoại `order_id` trên bảng con BẮT BUỘC phải có Non-Clustered Index.
--    - Có Index sẽ giúp Database Engine thực hiện phép tìm kiếm chỉ mục (Index Seek) với chi phí cực thấp,
--      tránh việc vô tình kích hoạt quét toàn bảng khi thực hiện phép JOIN.

-- ------------------------------------------------------------------------------------------
-- Câu 1.5.2:
-- Tương tự, hãy trích xuất toàn bộ các thông tin thanh toán phát sinh tương ứng với các đơn hàng
-- có sự thay đổi trong đợt tải gia tăng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.5.2 TẠI ĐÂY:

DECLARE @watermark DATETIME2 = '2018-01-01 00:00:00';

WITH delta_orders AS (
    SELECT 
        orders.order_id
    FROM dbo.olist_orders_dataset orders 
    WHERE orders.order_id IS NOT NULL
      AND orders.order_status NOT IN ('canceled', 'unavailable')
      AND COALESCE(
            orders.order_delivered_customer_date,
            orders.order_delivered_carrier_date,
            orders.order_approved_at,
            orders.order_purchase_timestamp
      ) > @watermark
)
SELECT 
    payments.order_id,
    payments.payment_sequential,
    payments.payment_type,
    payments.payment_installments,
    payments.payment_value
FROM dbo.olist_order_payments_dataset payments
INNER JOIN delta_orders delta 
    ON payments.order_id = delta.order_id;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (CASCADING DELTA TRÊN DỮ LIỆU THANH TOÁN - PAYMENTS CDC):
-- 1. Vấn đề thực tế (Quan hệ 1-N & Thanh toán đa phương thức - Split Payments):
--    - Một đơn hàng có thể có nhiều bản ghi thanh toán (khách kết hợp trả bằng Voucher + Thẻ tín dụng,
--      hoặc thanh toán trả góp nhiều đợt). Bảng payments cũng không có cột modified_at riêng.
--    - Khi đơn hàng phát sinh cập nhật (ví dụ: chuyển từ chờ duyệt sang đã duyệt tiền - approved),
--      toàn bộ các dòng giao dịch thanh toán liên quan cần được đồng bộ ngay sang kho dữ liệu.
-- 2. Giá trị giải pháp mang lại (Đồng bộ số liệu tài chính & Doanh thu tức thời):
--    - Kế thừa bộ lọc thời gian từ bảng cha orders để trích xuất chính xác các bản ghi thanh toán mới/thay đổi.
--    - Phục vụ đối soát doanh thu tài chính (Financial Reconciliation) mà không phải chịu chi phí Full Scan
--      bảng thanh toán với hàng triệu giao dịch.
-- 3. Lưu ý nghiệp vụ mở rộng (Hạch toán đơn hủy - Refund Tracking):
--    - Nếu pipeline phục vụ đội Kế toán/Hoàn tiền, các đơn bị hủy (canceled) vẫn cần được trích xuất thanh toán
--      để đối soát trả lại tiền cho khách hàng (không nên lọc bỏ 'canceled' trong luồng tài chính riêng biệt).


-- ------------------------------------------------------------------------------------------
-- Câu 1.5.3:
-- Đảm bảo tính toàn vẹn phụ thuộc giữa bảng cha và bảng con:
-- Kiểm tra để đảm bảo không xảy ra tình trạng dữ liệu mặt hàng chi tiết được nạp vào kho
-- trong khi đơn hàng tổng quát tương ứng chưa kịp xuất hiện ở kho đích.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.5.3 TẠI ĐÂY:


-- PHƯƠNG PHÁP 1: KIỂM TOÁN TRƯỚC KHI NẠP (PRE-LOAD DATA QUALITY AUDIT)
-- Quét tìm và phát hiện các bản ghi mặt hàng "mồ côi" (cha chưa có ở kho đích)
SELECT 
    items.order_id,
    items.order_item_id,
    items.product_id,
    items.price
FROM dbo.olist_order_items_dataset items
LEFT JOIN stg.stg_orders target_orders 
    ON items.order_id = target_orders.order_id
WHERE target_orders.order_id IS NULL;

-- PHƯƠNG PHÁP 2: TRUY VẤN NẠP GIA TĂNG PHÒNG VỆ (DEFENSIVE INCREMENTAL EXTRACT)
-- Chỉ trích xuất và nạp các mặt hàng khi đơn hàng cha ĐÃ HIỆN DIỆN an toàn ở kho đích
DECLARE @watermark DATETIME2 = '2018-01-01 00:00:00';

WITH delta_items AS (
    SELECT items.*
    FROM dbo.olist_order_items_dataset items
    INNER JOIN dbo.olist_orders_dataset src_orders 
        ON items.order_id = src_orders.order_id
    WHERE COALESCE(
            src_orders.order_delivered_customer_date,
            src_orders.order_delivered_carrier_date,
            src_orders.order_approved_at,
            src_orders.order_purchase_timestamp
          ) > @watermark
)
SELECT 
    di.order_id,
    di.order_item_id,
    di.product_id,
    di.seller_id,
    di.shipping_limit_date,
    di.price,
    di.freight_value
FROM delta_items di
INNER JOIN stg.stg_orders target_orders 
    ON di.order_id = target_orders.order_id;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (BẢO TOÀN PHỤ THUỘC CHA - CON & CHỐNG BẢN GHI MỒ CÔI):
-- 1. Vấn đề thực tế (Bản ghi mồ côi - Orphan Records & Nguy cơ sai lệch tài chính):
--    - Trong pipeline nạp song song (Parallel Ingestion), nếu bảng con (`order_items`) được nạp trước
--      hoặc bảng cha (`orders`) bị trễ/lỗi mạng, dữ liệu con sẽ rơi vào trạng thái "mồ côi"
--      (tồn tại chi tiết mặt hàng nhưng không tìm thấy đơn hàng tương ứng trong kho).
--    - Hậu quả: Nếu kho đích có ràng buộc khóa ngoại (Foreign Key), pipeline lập tức bị sập (FK Violation).
--      Nếu kho không bật ràng buộc (phổ biến ở Data Warehouse/Lakehouse để tối ưu tốc độ ghi),
--      các câu query `INNER JOIN` của đội BI/Analytics sẽ vô tình loại bỏ các dòng mồ côi này,
--      dẫn đến thất thoát doanh thu thực tế trên báo cáo kinh doanh.
-- 2. Giá trị giải pháp mang lại (Mô hình phòng vệ 2 lớp - Two-Layer Defensive Pattern):
--    - Lớp 1 (Data Quality Gate): Dùng `LEFT JOIN ... WHERE target.order_id IS NULL` kiểm toán trước khi nạp.
--      Nếu COUNT(*) > 0, lập tức kích hoạt cảnh báo (Alert) hoặc đưa vào vùng cách ly (Dead-Letter Queue).
--    - Lớp 2 (Defensive Ingestion): Ràng buộc `INNER JOIN stg.stg_orders` chỉ cho phép nạp các mặt hàng
--      khi đơn cha đã được xác nhận hiện diện hợp lệ trong kho đích.
-- 3. Ứng dụng kiến trúc Downstream (Điều phối luồng DAG - Pipeline Orchestration):
--    - Trong các công cụ điều phối (Airflow, Azure Data Factory, Prefect), các kỹ sư dữ liệu luôn phải
--      thiết lập thứ tự phụ thuộc tường minh: `task_load_orders >> task_load_order_items`.
--    - Đảm bảo nguyên tắc vàng: "Cha nạp thành công trước - Con mới được phép nạp sau",
--      duy trì tính toàn vẹn tham chiếu (Referential Integrity) tuyệt đối cho hệ thống Data Warehouse.

-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 6]: NẠP GIA TĂNG THEO PHÂN VÙNG (PARTITIONED INCREMENTAL LOAD)
-- ------------------------------------------------------------------------------------------

-- Câu 1.6.1:
-- Nạp gia tăng có định hướng phân vùng:
-- Tự động xác định danh sách các phân vùng ngày có dữ liệu bị thay đổi trong đợt quét gia tăng,
-- và chỉ thực hiện nạp làm mới dữ liệu trên đúng các phân vùng bị ảnh hưởng đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.6.1 TẠI ĐÂY:

DECLARE @watermark DATETIME2 = '2018-01-01 00:00:00';

WITH delta_orders AS (
    SELECT 
        orders.order_id,
        orders.order_purchase_timestamp,
        COALESCE(
            orders.order_delivered_customer_date,
            orders.order_delivered_carrier_date,
            orders.order_approved_at,
            orders.order_purchase_timestamp
        ) AS effective_last_modified_at
    FROM dbo.olist_orders_dataset orders
    WHERE orders.order_id IS NOT NULL
      AND orders.order_status NOT IN ('canceled', 'unavailable')
      AND COALESCE(
            orders.order_delivered_customer_date,
            orders.order_delivered_carrier_date,
            orders.order_approved_at,
            orders.order_purchase_timestamp
      ) > @watermark
)
SELECT 
    CAST(delta.order_purchase_timestamp AS DATE) AS affected_partition_date,
    COUNT(DISTINCT delta.order_id) AS total_orders_affected,
    MIN(delta.order_purchase_timestamp) AS min_order_timestamp,
    MAX(delta.effective_last_modified_at) AS max_effective_timestamp
FROM delta_orders delta
GROUP BY CAST(delta.order_purchase_timestamp AS DATE)
ORDER BY affected_partition_date ASC;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (NẠP GIA TĂNG ĐỊNH HƯỚNG PHÂN VÙNG - PARTITION-AWARE INCREMENTAL LOAD):
-- 1. Thảm họa thực tế nếu không áp dụng (Nếu không có kỹ thuật này):
--    - Xử lý mù quáng trên toàn bộ bảng (Table-level Scan/Overwrite): Khi có vài đơn hàng cũ thay đổi ngày giao,
--      hệ thống lại quét hoặc ghi đè toàn bộ bảng dữ liệu hàng trăm triệu dòng, gây tốn kém chi phí điện toán đám mây và khóa bảng.
-- 2. Giá trị giải pháp mang lại (Giải quyết vấn đề gì?):
--    - Tự động xác định danh sách các phân vùng ngày (`DISTINCT CAST(order_date AS DATE)`) thực sự có biến động.
--    - Chỉ thực hiện nạp làm mới hoặc ghi đè cục bộ trên đúng các phân vùng bị ảnh hưởng đó (Dynamic Partition Pruning & Overwrite).
-- 3. Ứng dụng kiến trúc Downstream:
--    - Tối ưu hóa tài nguyên vượt bậc trên các hệ thống Big Data (Spark, Delta Lake, Snowflake, BigQuery Partitioning),
--      rút ngắn thời gian nạp kho từ nhiều giờ xuống chỉ còn vài chục giây.

-- ------------------------------------------------------------------------------------------
-- Câu 1.6.2:
-- Xây dựng quy trình Backfill dữ liệu lịch sử theo khoảng thời gian:
-- Viết truy vấn nhận tham số từ ngày đến ngày trong quá khứ để nạp bù dữ liệu cho phân vùng đó
-- mà không làm ảnh hưởng đến mốc Watermark hiện tại của pipeline chạy hàng ngày.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.6.2 TẠI ĐÂY:

DECLARE @backfill_start_date DATETIME2 = '2017-08-01 00:00:00';
DECLARE @backfill_end_date   DATETIME2 = '2017-08-31 23:59:59';

-- Truy vấn trích xuất dữ liệu Backfill cho phân vùng lịch sử độc lập
SELECT 
    orders.order_id,
    orders.customer_id,
    orders.order_status,
    orders.order_purchase_timestamp,
    orders.order_approved_at,
    orders.order_delivered_carrier_date,
    orders.order_delivered_customer_date,
    orders.order_estimated_delivery_date,
    'BACKFILL' AS load_type,
    CURRENT_TIMESTAMP AS loaded_at
FROM dbo.olist_orders_dataset orders
WHERE orders.order_id IS NOT NULL
  AND orders.order_status NOT IN ('canceled', 'unavailable')
  AND orders.order_purchase_timestamp >= @backfill_start_date
  AND orders.order_purchase_timestamp <= @backfill_end_date;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (QUY TRÌNH BACKFILL LỊCH SỬ KHÔNG XÂM LẤN WATERMARK THƯỜNG NHẬT):
-- 1. Thảm họa thực tế nếu không áp dụng (Nếu không có kỹ thuật này):
--    - Khi cần nạp bù dữ liệu tháng trước bị lỗi, nếu dùng chung luồng với pipeline chính, Watermark sẽ bị kéo lùi về tháng trước.
--    - Khi pipeline hàng ngày thức dậy, nó sẽ quét lại toàn bộ dữ liệu từ tháng trước đến nay (hàng triệu dòng),
--      gây nghẽn hệ thống và làm sập pipeline (Pipeline Collision / Watermark Corruption).
-- 2. Giá trị giải pháp mang lại (Giải quyết vấn đề gì?):
--    - Tách biệt hoàn toàn luồng Backfill (Cold Path) và luồng gia tăng hàng ngày (Hot Path):
--      Luồng Backfill nhận tham số `@from_date` và `@to_date` cố định độc lập, chạy riêng biệt và tuyệt đối không ghi đè vào bảng `pipeline_watermark`.
-- 3. Ứng dụng kiến trúc Downstream:
--    - Cho phép kỹ sư dữ liệu tự do vá lỗi dữ liệu lịch sử (Data Patching / Restatement) bất kỳ lúc nào mà không làm gián đoạn pipeline tự động.

-- ------------------------------------------------------------------------------------------
-- Câu 1.6.3:
-- Quét đối soát tính liên tục của các phân vùng sau khi nạp gia tăng:
-- Phát hiện xem có ngày nào bị khuyết thiếu toàn bộ dữ liệu trong chuỗi ngày vận hành hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.6.3 TẠI ĐÂY:

DECLARE @audit_start_date DATE = '2018-01-01';
DECLARE @audit_end_date   DATE = '2018-01-31';

-- 1. Tạo chuỗi ngày lịch liên tục (Date Spine / Calendar Dimension) bằng CTE đệ quy
WITH date_spine AS (
    SELECT @audit_start_date AS calendar_date
    UNION ALL
    SELECT DATEADD(DAY, 1, calendar_date)
    FROM date_spine
    WHERE calendar_date < @audit_end_date
),
-- 2. Thống kê số lượng đơn hàng thực tế nạp được theo từng ngày
daily_orders AS (
    SELECT 
        CAST(order_purchase_timestamp AS DATE) AS order_date,
        COUNT(order_id) AS total_orders
    FROM dbo.olist_orders_dataset
    WHERE order_purchase_timestamp >= CAST(@audit_start_date AS DATETIME2)
      AND order_purchase_timestamp < DATEADD(DAY, 1, CAST(@audit_end_date AS DATETIME2))
    GROUP BY CAST(order_purchase_timestamp AS DATE)
)
-- 3. Phát hiện các ngày bị khuyết thiếu (Data Gaps / Zero Records)
SELECT 
    ds.calendar_date,
    ISNULL(do.total_orders, 0) AS total_orders,
    CASE 
        WHEN do.total_orders IS NULL OR do.total_orders = 0 THEN 'MISSING / GAP DETECTED'
        ELSE 'NORMAL'
    END AS partition_status
FROM date_spine ds
LEFT JOIN daily_orders do 
    ON ds.calendar_date = do.order_date
ORDER BY ds.calendar_date ASC
OPTION (MAXRECURSION 1000);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (QUÉT ĐỐI SOÁT TÍNH LIÊN TỤC CỦA PHÂN VÙNG - PARTITION GAP DETECTION):
-- 1. Thảm họa thực tế nếu không áp dụng (Nếu không có kỹ thuật này):
--    - "Lỗ hổng dữ liệu vô hình" (Data Gaps / Missing Days): Vào một ngày nghỉ lễ hoặc ngày server ETL bị sập,
--      dữ liệu của ngày hôm đó hoàn toàn bị bỏ sót. Không ai phát hiện ra cho đến cuối tháng Giám đốc xem báo cáo thấy doanh thu ngày đó bằng 0.
-- 2. Giá trị giải pháp mang lại (Giải quyết vấn đề gì?):
--    - Tạo bảng chuỗi ngày lịch liên tục (Calendar Table / Date Spine CTE) và `LEFT JOIN` với bảng dữ liệu thực tế
--      để phát hiện ngay lập tức ngày nào bị khuyết thiếu hoàn toàn dữ liệu (`COUNT(*) = 0`).
-- 3. Ứng dụng kiến trúc Downstream:
--    - Hệ thống cảnh báo sớm (Data Quality Alerting): Tự động bắn thông báo qua Slack/Email cho Data Engineer
--      để kích hoạt quy trình Backfill bù ngày bị khuyết ngay trong buổi sáng.

-- ------------------------------------------------------------------------------------------
-- [P1 - NGÀY 7]: TỰ ĐỘNG HÓA PIPELINE TRÍCH XUẤT VỚI BẢNG KIỂM SOÁT WATERMARK
-- ------------------------------------------------------------------------------------------

-- Câu 1.7.1:
-- Thiết kế một bảng kiểm soát trạng thái Pipeline (`etl_watermark_control`) hoàn chỉnh:
-- Lưu trữ tên bảng nguồn, tên cột watermark, giá trị watermark hiện tại, thời gian bắt đầu chạy,
-- thời gian hoàn tất, số bản ghi trích xuất thành công và trạng thái thực thi.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.7.1 TẠI ĐÂY:

IF OBJECT_ID('stg.etl_watermark_control', 'U') IS NOT NULL
    DROP TABLE stg.etl_watermark_control;
GO

CREATE TABLE stg.etl_watermark_control (
    pipeline_id          INT IDENTITY(1, 1) PRIMARY KEY,
    pipeline_name        VARCHAR(100) NOT NULL UNIQUE,
    source_table         VARCHAR(100) NOT NULL,
    target_table         VARCHAR(100) NOT NULL,
    watermark_column     VARCHAR(50)  NOT NULL,
    watermark_value      DATETIME2    NOT NULL,
    last_run_start       DATETIME2    NULL,
    last_run_end         DATETIME2    NULL,
    rows_extracted       INT          DEFAULT 0,
    execution_status     VARCHAR(20)  DEFAULT 'IDLE', -- 'IDLE', 'RUNNING', 'SUCCESS', 'FAILED'
    error_message        NVARCHAR(MAX) NULL
);
GO

-- Khởi tạo mốc cấu hình ban đầu
INSERT INTO stg.etl_watermark_control (
    pipeline_name,
    source_table,
    target_table,
    watermark_column,
    watermark_value,
    last_run_start,
    last_run_end,
    rows_extracted,
    execution_status
)
VALUES (
    'orders_incremental_pipeline',
    'dbo.olist_orders_dataset',
    'stg.stg_orders',
    'effective_last_modified_at',
    '2018-01-01 00:00:00',
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    0,
    'SUCCESS'
);
GO

SELECT * FROM stg.etl_watermark_control;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (THIẾT KẾ BẢNG AUDIT & METADATA KIỂM SOÁT WATERMARK CHUẨN ENTERPRISE):
-- 1. Thảm họa thực tế nếu không áp dụng (Nếu không có kỹ thuật này):
--    - Pipeline vận hành "mù" (Black Box Pipeline): Khi pipeline bị lỗi hoặc dừng đột ngột, không có nhật ký ghi lại
--      đợt chạy trước dừng ở mốc nào, đã nạp được bao nhiêu dòng, thời gian chạy mất bao lâu để tối ưu.
-- 2. Giá trị giải pháp mang lại (Giải quyết vấn đề gì?):
--    - Thiết kế bảng kiểm soát tập trung `etl_watermark_control`: Lưu trữ đầy đủ trạng thái (`RUNNING`, `SUCCESS`, `FAILED`),
--      mốc bắt đầu, mốc kết thúc, số bản ghi trích xuất thành công (`rows_extracted`) và thời gian thực thi.
-- 3. Ứng dụng kiến trúc Downstream:
--    - Cung cấp nền tảng để xây dựng Dashboard giám sát sức khỏe pipeline (Pipeline Observability / SLA Monitoring) cho toàn công ty.

-- ------------------------------------------------------------------------------------------
-- Câu 1.7.2:
-- Xây dựng luồng thực thi an toàn trong một khối Transaction:
-- Đọc Watermark hiện tại $ightarrow$ Trích xuất dữ liệu gia tăng sang bảng tạm Staging $ightarrow$
-- Cập nhật giá trị Watermark mới vào bảng kiểm soát $ightarrow$ Commit Transaction (Rollback nếu xảy ra sự cố).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.7.2 TẠI ĐÂY:

DECLARE @current_watermark DATETIME2;
DECLARE @new_watermark     DATETIME2;
DECLARE @run_start_time    DATETIME2 = CURRENT_TIMESTAMP;
DECLARE @extracted_count   INT = 0;

BEGIN TRANSACTION;

BEGIN TRY
    -- 1. Đọc Watermark hiện tại và khóa dòng kiểm soát (tránh Race Condition khi nhiều Job chạy cùng lúc)
    SELECT @current_watermark = watermark_value
    FROM stg.etl_watermark_control WITH (UPDLOCK, HOLDLOCK)
    WHERE pipeline_name = 'orders_incremental_pipeline';

    -- 2. Cập nhật trạng thái đang chạy
    UPDATE stg.etl_watermark_control
    SET execution_status = 'RUNNING',
        last_run_start   = @run_start_time,
        error_message    = NULL
    WHERE pipeline_name = 'orders_incremental_pipeline';

    -- 3. Trích xuất dữ liệu gia tăng sang bảng Staging bằng UPSERT (MERGE)
    MERGE INTO stg.stg_orders AS tgt
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
            COALESCE(
                order_delivered_customer_date,
                order_delivered_carrier_date,
                order_approved_at,
                order_purchase_timestamp
            ) AS effective_last_modified_at
        FROM dbo.olist_orders_dataset
        WHERE order_id IS NOT NULL
          AND order_status NOT IN ('canceled', 'unavailable')
          AND COALESCE(
                order_delivered_customer_date,
                order_delivered_carrier_date,
                order_approved_at,
                order_purchase_timestamp
          ) > @current_watermark
    ) AS src
    ON tgt.order_id = src.order_id
    WHEN MATCHED THEN
        UPDATE SET 
            tgt.order_status                 = src.order_status,
            tgt.order_approved_at            = src.order_approved_at,
            tgt.order_delivered_carrier_date = src.order_delivered_carrier_date,
            tgt.order_delivered_customer_date= src.order_delivered_customer_date,
            tgt.loaded_at                    = CURRENT_TIMESTAMP
    WHEN NOT MATCHED THEN
        INSERT (
            order_id,
            customer_id,
            order_status,
            order_purchase_timestamp,
            order_approved_at,
            order_delivered_carrier_date,
            order_delivered_customer_date,
            order_estimated_delivery_date,
            loaded_at
        )
        VALUES (
            src.order_id,
            src.customer_id,
            src.order_status,
            src.order_purchase_timestamp,
            src.order_approved_at,
            src.order_delivered_carrier_date,
            src.order_delivered_customer_date,
            src.order_estimated_delivery_date,
            CURRENT_TIMESTAMP
        );

    SET @extracted_count = @@ROWCOUNT;

    -- 4. Tính toán New High-Water Mark an toàn (Dùng COALESCE phòng trường hợp 0 bản ghi)
    SELECT @new_watermark = COALESCE(
        MAX(COALESCE(
            order_delivered_customer_date,
            order_delivered_carrier_date,
            order_approved_at,
            order_purchase_timestamp
        )), 
        @current_watermark
    )
    FROM dbo.olist_orders_dataset
    WHERE COALESCE(
            order_delivered_customer_date,
            order_delivered_carrier_date,
            order_approved_at,
            order_purchase_timestamp
    ) > @current_watermark;

    -- 5. Cập nhật Watermark mới và ghi nhận trạng thái SUCCESS
    UPDATE stg.etl_watermark_control
    SET watermark_value  = @new_watermark,
        last_run_end     = CURRENT_TIMESTAMP,
        rows_extracted   = @extracted_count,
        execution_status = 'SUCCESS'
    WHERE pipeline_name = 'orders_incremental_pipeline';

    -- 6. Hoàn tất toàn bộ giao dịch an toàn
    COMMIT TRANSACTION;

    PRINT 'Pipeline nạp gia tăng thành công: ' + CAST(@extracted_count AS VARCHAR) + ' bản ghi đã xử lý.';
END TRY
BEGIN CATCH
    -- Tự động hoàn tác toàn bộ dữ liệu nếu xảy ra bất kỳ sự cố nào
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- Ghi nhận thông tin lỗi vào bảng kiểm soát
    UPDATE stg.etl_watermark_control
    SET last_run_end     = CURRENT_TIMESTAMP,
        execution_status = 'FAILED',
        error_message    = ERROR_MESSAGE()
    WHERE pipeline_name = 'orders_incremental_pipeline';

    PRINT 'Pipeline thất bại và đã ROLLBACK: ' + ERROR_MESSAGE();
    THROW;
END CATCH;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (GIAO DỊCH AN TOÀN VỚI TRANSACTION & ROLLBACK - TWO-PHASE COMMIT):
-- 1. Thảm họa thực tế nếu không áp dụng (Nếu không có kỹ thuật này):
--    - Trạng thái phân mảnh (Partial Load Failure / Inconsistent State): Dữ liệu vừa nạp được một nửa thì mất mạng hoặc đầy đĩa.
--      Nếu không có Transaction, dữ liệu dở dang đã nằm trong Staging trong khi Watermark chưa cập nhật (hoặc ngược lại).
--      Lần chạy sau sẽ nạp đè dữ liệu rác hoặc bỏ sót vĩnh viễn dữ liệu chưa nạp.
-- 2. Giá trị giải pháp mang lại (Giải quyết vấn đề gì?):
--    - Đóng gói toàn bộ luồng trong khối `BEGIN TRANSACTION ... COMMIT TRANSACTION` và bắt lỗi bằng `BEGIN TRY ... BEGIN CATCH ... ROLLBACK`:
--      Tuân thủ nguyên tắc ACID (Tính nguyên tử) - Hoặc toàn bộ đợt nạp thành công 100%, hoặc hoàn tác sạch sẽ về vạch xuất phát.
-- 3. Ứng dụng kiến trúc Downstream:
--    - Bảo vệ hệ thống luôn trong trạng thái nhất quán và an toàn tuyệt đối, không bao giờ để lại dữ liệu dở dang trong kho.

-- ------------------------------------------------------------------------------------------
-- Câu 1.7.3:
-- Đóng gói toàn bộ luồng trích xuất gia tăng thành một Stored Procedure hoàn chỉnh:
-- Tự động vận hành trích xuất dữ liệu theo đúng chu trình Watermark và in thông báo tổng kết kết quả nạp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 1.7.3 TẠI ĐÂY:

IF OBJECT_ID('stg.sp_run_orders_incremental_pipeline', 'P') IS NOT NULL
    DROP PROCEDURE stg.sp_run_orders_incremental_pipeline;
GO

CREATE PROCEDURE stg.sp_run_orders_incremental_pipeline
    @p_pipeline_name     VARCHAR(100) = 'orders_incremental_pipeline',
    @p_lookback_minutes  INT          = 15
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @v_current_watermark DATETIME2;
    DECLARE @v_new_watermark     DATETIME2;
    DECLARE @v_run_start_time    DATETIME2 = CURRENT_TIMESTAMP;
    DECLARE @v_extracted_count   INT = 0;

    -- Kiểm tra phòng vệ: Tránh chạy trùng lặp khi Job trước vẫn đang xử lý
    IF EXISTS (
        SELECT 1 FROM stg.etl_watermark_control 
        WHERE pipeline_name = @p_pipeline_name AND execution_status = 'RUNNING'
          AND DATEDIFF(MINUTE, last_run_start, CURRENT_TIMESTAMP) < 60
    )
    BEGIN
        PRINT 'CẢNH BÁO: Pipeline ' + @p_pipeline_name + ' đang ở trạng thái RUNNING. Tạm dừng để tránh xung đột.';
        RETURN;
    END

    BEGIN TRANSACTION;

    BEGIN TRY
        -- 1. Đọc Watermark hiện tại từ Metadata Control Table
        SELECT @v_current_watermark = watermark_value
        FROM stg.etl_watermark_control WITH (UPDLOCK, HOLDLOCK)
        WHERE pipeline_name = @p_pipeline_name;

        IF @v_current_watermark IS NULL
        BEGIN
            RAISERROR('Không tìm thấy cấu hình Watermark cho pipeline yêu cầu.', 16, 1);
        END

        -- 2. Cập nhật trạng thái bắt đầu chạy
        UPDATE stg.etl_watermark_control
        SET execution_status = 'RUNNING',
            last_run_start   = @v_run_start_time,
            error_message    = NULL
        WHERE pipeline_name = @p_pipeline_name;

        -- 3. Nạp gia tăng sang Staging với Lookback Safety Margin chống sót giao dịch
        MERGE INTO stg.stg_orders AS tgt
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
                COALESCE(
                    order_delivered_customer_date,
                    order_delivered_carrier_date,
                    order_approved_at,
                    order_purchase_timestamp
                ) AS effective_last_modified_at
            FROM dbo.olist_orders_dataset
            WHERE order_id IS NOT NULL
              AND order_status NOT IN ('canceled', 'unavailable')
              AND COALESCE(
                    order_delivered_customer_date,
                    order_delivered_carrier_date,
                    order_approved_at,
                    order_purchase_timestamp
              ) >= DATEADD(MINUTE, -@p_lookback_minutes, @v_current_watermark)
        ) AS src
        ON tgt.order_id = src.order_id
        WHEN MATCHED THEN
            UPDATE SET 
                tgt.order_status                 = src.order_status,
                tgt.order_approved_at            = src.order_approved_at,
                tgt.order_delivered_carrier_date = src.order_delivered_carrier_date,
                tgt.order_delivered_customer_date= src.order_delivered_customer_date,
                tgt.loaded_at                    = CURRENT_TIMESTAMP
        WHEN NOT MATCHED THEN
            INSERT (
                order_id,
                customer_id,
                order_status,
                order_purchase_timestamp,
                order_approved_at,
                order_delivered_carrier_date,
                order_delivered_customer_date,
                order_estimated_delivery_date,
                loaded_at
            )
            VALUES (
                src.order_id,
                src.customer_id,
                src.order_status,
                src.order_purchase_timestamp,
                src.order_approved_at,
                src.order_delivered_carrier_date,
                src.order_delivered_customer_date,
                src.order_estimated_delivery_date,
                CURRENT_TIMESTAMP
            );

        SET @v_extracted_count = @@ROWCOUNT;

        -- 4. Xác định mốc High-Water Mark mới an toàn
        SELECT @v_new_watermark = COALESCE(
            MAX(COALESCE(
                order_delivered_customer_date,
                order_delivered_carrier_date,
                order_approved_at,
                order_purchase_timestamp
            )), 
            @v_current_watermark
        )
        FROM dbo.olist_orders_dataset
        WHERE COALESCE(
                order_delivered_customer_date,
                order_delivered_carrier_date,
                order_approved_at,
                order_purchase_timestamp
        ) > @v_current_watermark;

        -- 5. Cập nhật Metadata ghi nhận thành công
        UPDATE stg.etl_watermark_control
        SET watermark_value  = @v_new_watermark,
            last_run_end     = CURRENT_TIMESTAMP,
            rows_extracted   = @v_extracted_count,
            execution_status = 'SUCCESS'
        WHERE pipeline_name = @p_pipeline_name;

        COMMIT TRANSACTION;

        -- Báo cáo kết quả thực thi
        SELECT 
            @p_pipeline_name AS pipeline_name,
            @v_current_watermark AS previous_watermark,
            @v_new_watermark AS new_watermark,
            @v_extracted_count AS rows_processed,
            DATEDIFF(SECOND, @v_run_start_time, CURRENT_TIMESTAMP) AS duration_seconds,
            'SUCCESS' AS execution_status;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        UPDATE stg.etl_watermark_control
        SET last_run_end     = CURRENT_TIMESTAMP,
            execution_status = 'FAILED',
            error_message    = ERROR_MESSAGE()
        WHERE pipeline_name = @p_pipeline_name;

        PRINT 'LỖI THỰC THI SP: ' + ERROR_MESSAGE();
        THROW;
    END CATCH;
END;
GO

-- Thực thi chạy thử Stored Procedure hoàn chỉnh:
-- EXEC stg.sp_run_orders_incremental_pipeline @p_lookback_minutes = 15;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (ĐÓNG GÓI STORED PROCEDURE HOÀN CHỈNH CHO PRODUCTION PIPELINE):
-- 1. Thảm họa thực tế nếu không áp dụng (Nếu không có kỹ thuật này):
--    - Viết các câu lệnh SQL trần trụi (Ad-hoc queries) nằm rải rác: Ứng dụng ngoài (Python, Airflow) phải gửi từng dòng code dài lê thê qua mạng,
--      dễ bị tấn công SQL Injection, không thể cấp quyền bảo mật phân tầng và không tận dụng được cơ chế biên dịch trước (Pre-compiled Execution Plan).
-- 2. Giá trị giải pháp mang lại (Giải quyết vấn đề gì?):
--    - Đóng gói toàn bộ quy trình (Đọc Watermark -> Quét Lookback -> Trích xuất -> Cập nhật Metadata -> Ghi log) vào một Stored Procedure:
--      Tối ưu hóa hiệu năng biên dịch của SQL Server, bảo mật phân quyền tuyệt đối và trả về kết quả nạp trực quan.
-- 3. Ứng dụng kiến trúc Downstream:
--    - Biến toàn bộ pipeline thành một hàm API cơ sở dữ liệu (Database API) chuẩn hóa, cho phép các công cụ điều phối (Airflow / Data Factory)
--      gọi thực thi chỉ bằng duy nhất 1 câu lệnh `EXEC sp_run_orders_incremental_pipeline`.
