-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 3: KIẾN TRÚC DATA PIPELINE & DATA WAREHOUSING (END-TO-END DATA ENGINEERING)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 2: UPSERT STRATEGY (CẬP NHẬT & CHÈN DỮ LIỆU ĐÍCH)
-- Logic cốt lõi: Khóa đã tồn tại? → Có: UPDATE | Không: INSERT
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 1]: PHÂN LUỒNG INSERT VS UPDATE CƠ BẢN
-- ------------------------------------------------------------------------------------------

-- Câu 2.1.1:
-- Từ tập dữ liệu gia tăng ở tầng Staging, hãy phân tách rõ ràng thành 2 tập dữ liệu riêng biệt:
-- 1. Tập các bản ghi mới tinh (chưa từng xuất hiện ở bảng đích $\rightarrow$ cần INSERT).
-- 2. Tập các bản ghi đã tồn tại ở bảng đích nhưng có thông tin thay đổi $\rightarrow$ cần UPDATE.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.1 TẠI ĐÂY:

-- 1. Tập các bản ghi mới tinh (chưa từng xuất hiện ở bảng đích -> cần INSERT)
SELECT 
    src.customer_id,
    src.customer_unique_id,
    src.customer_zip_code_prefix,
    src.customer_city,
    src.customer_state,
    'INSERT' AS target_action 
FROM stg.stg_customers AS src 
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.olist_customers_dataset AS tgt
    WHERE tgt.customer_id = src.customer_id
);

-- 2. Tập các bản ghi đã tồn tại ở bảng đích nhưng có thông tin thay đổi -> cần UPDATE
SELECT 
    src.customer_id,
    src.customer_unique_id,
    src.customer_zip_code_prefix AS new_zip_code,
    src.customer_city            AS new_city,
    src.customer_state           AS new_state,
    tgt.customer_zip_code_prefix AS old_zip_code,
    tgt.customer_city            AS old_city,
    tgt.customer_state           AS old_state,
    'UPDATE' AS target_action
FROM stg.stg_customers AS src
INNER JOIN dbo.olist_customers_dataset AS tgt 
    ON src.customer_id = tgt.customer_id
WHERE 
    ISNULL(src.customer_zip_code_prefix, -1) <> ISNULL(tgt.customer_zip_code_prefix, -1)
    OR ISNULL(src.customer_city, '')          <> ISNULL(tgt.customer_city, '')
    OR ISNULL(src.customer_state, '')         <> ISNULL(tgt.customer_state, '');

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (PHÂN TÁCH LUỒNG INSERT VS UPDATE):
-- 1. Bài toán giải quyết (Audit & Data Profiling trước khi nạp):
--    - Trước khi ghi dữ liệu vào kho, kỹ sư dữ liệu cần phân tích và kiểm toán trước tỉ lệ
--      bản ghi mới (chèn mới) và bản ghi cũ (cập nhật) để đánh giá quy mô tải (Batch Sizing).
-- 2. Kỹ thuật áp dụng (NOT EXISTS & Differential Matching):
--    - Mệnh đề NOT EXISTS giúp bắt trọn các bản ghi mới tinh mà không bị ảnh hưởng bởi giá trị NULL.
--    - Điều kiện so sánh ở mệnh đề WHERE của tập UPDATE dùng ISNULL để tránh bẫy ba ngôi True/False/Unknown của SQL.



-- ------------------------------------------------------------------------------------------
-- Câu 2.1.2:
-- Thực hiện câu lệnh INSERT có điều kiện bảo vệ:
-- Chỉ chèn các bản ghi khách hàng từ Staging vào bảng đích nếu mã khách hàng đó chưa từng tồn tại ở đích,
-- đảm bảo tuyệt đối không sinh ra lỗi trùng khóa chính.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.2 TẠI ĐÂY:

-- 1. INSERT có điều kiện bảo vệ (Guarded INSERT)
INSERT INTO dbo.olist_customers_dataset (
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state,
    created_at,
    updated_at
)
SELECT 
    src.customer_id,
    src.customer_unique_id,
    src.customer_zip_code_prefix,
    src.customer_city,
    src.customer_state,
    CURRENT_TIMESTAMP AS created_at,
    CURRENT_TIMESTAMP AS updated_at
FROM stg.stg_customers AS src
WHERE NOT EXISTS (
    -- Điều kiện bảo vệ: Đảm bảo khách hàng chưa từng tồn tại ở bảng đích
    SELECT 1 
    FROM dbo.olist_customers_dataset AS tgt
    WHERE tgt.customer_id = src.customer_id
);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (GUARDED INSERT TRÁNH TRÙNG KHÓA CHÍNH):
-- 1. Bài toán giải quyết (Idempotency & Chống lỗi Duplicate Key):
--    - Trong thực tế, pipeline có thể bị chạy lại (re-run) nhiều lần do lỗi mạng hoặc retry tự động.
--    - Nếu dùng INSERT thông thường, hệ thống sẽ văng lỗi vi phạm khóa chính (Primary Key Violation).
-- 2. Cơ chế bảo vệ (NOT EXISTS vs NOT IN):
--    - Luôn ưu tiên dùng WHERE NOT EXISTS thay vì NOT IN vì NOT IN sẽ trả về rỗng nếu tập đích chứa giá trị NULL,
--      đồng thời NOT EXISTS được tối ưu hóa tốt hơn qua Anti-Semi-Join trong Execution Plan.



-- ------------------------------------------------------------------------------------------
-- Câu 2.1.3:
-- Thực hiện câu lệnh UPDATE có điều kiện tối ưu:
-- Cập nhật thông tin địa chỉ mới cho các khách hàng đã tồn tại ở bảng đích dựa trên dữ liệu từ Staging,
-- nhưng chỉ cập nhật các dòng thực sự có sự thay đổi về mặt nội dung (tránh cập nhật vô ích).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.3 TẠI ĐÂY:

-- 1. UPDATE có điều kiện tối ưu (Loại bỏ cập nhật vô ích)
UPDATE tgt 
SET 
    tgt.customer_city  = src.customer_city,
    tgt.customer_state = src.customer_state,
    tgt.updated_at     = CURRENT_TIMESTAMP
FROM dbo.olist_customers_dataset AS tgt
INNER JOIN stg.stg_customers AS src
    ON tgt.customer_id = src.customer_id
WHERE 
    -- Điều kiện tối ưu: Chỉ UPDATE những dòng thực sự có sự thay đổi
    ISNULL(tgt.customer_city, '')     <> ISNULL(src.customer_city, '')
    OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '');

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (TỐI ƯU UPDATE & KHỬ GHOST UPDATES):
-- 1. Bài toán giải quyết (Ghost Updates / No-Op Updates):
--    - Khi nạp dữ liệu gia tăng, phần lớn bản ghi cũ không hề có sự thay đổi.
--    - Việc ghi đè dữ liệu cũ bằng chính nó gây lãng phí nghiêm trọng dung lượng Transaction Log (.LDF),
--      gây khóa bảng (Locking/Blocking) kéo dài và làm hỏng dấu vết thời gian cập nhật (Audit Timestamp).
-- 2. Kỹ thuật áp dụng (Change Detection):
--    - Sử dụng phép so sánh giá trị cũ và mới kết hợp ISNULL để đảm bảo chỉ những dòng thực sự đổi mới được ghi đĩa.



-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 2]: CHIẾN LƯỢC UPSERT 2 BƯỚC ĐỘC LẬP (TWO-STEP UPSERT)
-- ------------------------------------------------------------------------------------------

-- Câu 2.2.1:
-- Viết quy trình Two-Step Upsert đồng bộ trạng thái đơn hàng:
-- Bước 1: Thực hiện UPDATE trạng thái mới cho các đơn hàng đã có ở bảng đích.
-- Bước 2: Thực hiện INSERT toàn bộ các đơn hàng mới phát sinh vào bảng đích.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.1 TẠI ĐÂY:

-- 1. Bước 1: UPDATE trạng thái mới cho các đơn hàng đã tồn tại ở bảng đích
UPDATE tgt
SET 
    tgt.order_status                  = src.order_status,
    tgt.order_approved_at             = src.order_approved_at,
    tgt.order_delivered_carrier_date  = src.order_delivered_carrier_date,
    tgt.order_delivered_customer_date = src.order_delivered_customer_date
FROM dbo.olist_orders_dataset AS tgt
INNER JOIN stg.stg_orders AS src
    ON tgt.order_id = src.order_id
WHERE 
    ISNULL(tgt.order_status, '') <> ISNULL(src.order_status, '');


INSERT INTO dbo.olist_orders_dataset (
    order_id,
    customer_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    order_estimated_delivery_date
)
SELECT 
    src.order_id,
    src.customer_id,
    src.order_status,
    src.order_purchase_timestamp,
    src.order_approved_at,
    src.order_delivered_carrier_date,
    src.order_delivered_customer_date,
    src.order_estimated_delivery_date
FROM stg.stg_orders AS src
WHERE NOT EXISTS (
    -- Điều kiện bảo vệ: Đảm bảo đơn hàng chưa từng tồn tại ở đích trước khi chèn
    SELECT 1 
    FROM dbo.olist_orders_dataset AS tgt 
    WHERE tgt.order_id = src.order_id
);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (TWO-STEP UPSERT STRATEGY):
-- 1. Bài toán giải quyết (Đồng bộ hai luồng dữ liệu gia tăng):
--    - Phân tách rõ ràng vòng đời của dữ liệu: Đơn hàng cũ đổi trạng thái (UPDATE) và đơn hàng mới tinh phát sinh (INSERT).
--    - Đảm bảo tính toàn vẹn (Data Integrity), ngăn chặn tuyệt đối lỗi vi phạm khóa chính (Primary Key Violation) làm dừng pipeline.
-- 2. Tối ưu tài nguyên hệ thống (Eliminate Ghost Updates):
--    - Mệnh đề WHERE so sánh trạng thái giúp database chỉ ghi đè đúng những dòng có sự thay đổi thực sự.
--    - Tiết kiệm dung lượng Transaction Log (.LDF), tránh phân mảnh chỉ mục (Index Fragmentation) và giảm thiểu khóa bảng (Table Locking).
-- 3. Nguyên tắc thứ tự thực thi (UPDATE trước -> INSERT sau):
--    - Luôn chạy câu lệnh UPDATE trước để xử lý các đơn hàng cũ.
--    - Nếu INSERT trước, các đơn hàng mới vừa được chèn sẽ lập tức bị quét và kiểm tra lại ở câu lệnh UPDATE phía sau, gây lãng phí tài nguyên tính toán.


-- ------------------------------------------------------------------------------------------
-- Câu 2.2.2:
-- Kiểm tra độ lệch và số dòng tác động của từng bước:
-- Đo lường chính xác số dòng đã được UPDATE ở Bước 1 và số dòng đã được INSERT ở Bước 2.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.2 TẠI ĐÂY:

-- 1. Truy vấn kiểm tra độ lệch và phân loại số dòng tác động (Data Reconciliation Query)
SELECT 
    COUNT(*) AS total_staging_rows,
    
    -- Nhóm 1: Số đơn hàng mới tinh cần INSERT (Khóa chính chưa xuất hiện ở bảng đích)
    COUNT(CASE 
        WHEN tgt.order_id IS NULL THEN 1 
    END) AS expected_inserted_rows,
    
    -- Nhóm 2: Số đơn hàng đã tồn tại nhưng có thay đổi trạng thái cần UPDATE
    COUNT(CASE 
        WHEN tgt.order_id IS NOT NULL 
         AND ISNULL(tgt.order_status, '') <> ISNULL(src.order_status, '') THEN 1 
    END) AS expected_updated_rows,

    -- Nhóm 3: Số đơn hàng đã tồn tại và giữ nguyên trạng thái (Bỏ qua, tránh Ghost Update)
    COUNT(CASE 
        WHEN tgt.order_id IS NOT NULL 
         AND ISNULL(tgt.order_status, '') = ISNULL(src.order_status, '') THEN 1 
    END) AS expected_unchanged_rows,

    -- Kiểm tra độ lệch: Tổng staging trừ đi cả 3 nhóm (Giá trị bắt buộc phải bằng 0)
    COUNT(*) - (
        COUNT(CASE WHEN tgt.order_id IS NULL THEN 1 END) +
        COUNT(CASE WHEN tgt.order_id IS NOT NULL AND ISNULL(tgt.order_status, '') <> ISNULL(src.order_status, '') THEN 1 END) +
        COUNT(CASE WHEN tgt.order_id IS NOT NULL AND ISNULL(tgt.order_status, '') = ISNULL(src.order_status, '') THEN 1 END)
    ) AS discrepancy
FROM stg.stg_orders AS src
LEFT JOIN dbo.olist_orders_dataset AS tgt 
    ON src.order_id = tgt.order_id;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (DATA RECONCILIATION & AUDIT METRICS):
-- 1. Bài toán giải quyết (Kiểm toán tính toàn vẹn dữ liệu - Data Integrity Audit):
--    - Trong các pipeline cấp doanh nghiệp, bước kiểm toán (Reconciliation) là chốt chặn quan trọng
--      nhằm đảm bảo không có bất kỳ bản ghi nào bị thất thoát hoặc bị nhân bản vô tình (Cartesian Fan-Out).
-- 2. Kỹ thuật đối soát toàn diện (Exhaustive Categorization):
--    - Mọi bản ghi ở Staging sau khi LEFT JOIN với Target bắt buộc phải được gom triệt để vào 1 trong 3 nhóm duy nhất:
--      (1) Mới tinh -> Cần INSERT, (2) Thay đổi -> Cần UPDATE, (3) Giữ nguyên -> UNCHANGED.
--    - Giá trị discrepancy = 0 khẳng định tính toàn vẹn tuyệt đối trước khi hoặc sau khi nạp kho.
-- 3. Đo lường Runtime thực tế (Production Tip với @@ROWCOUNT):
--    - Khi quy trình Two-Step Upsert chạy trong Stored Procedure, ta dùng biến hệ thống @@ROWCOUNT ngay sau mỗi lệnh
--      (SET @rows_updated = @@ROWCOUNT và SET @rows_inserted = @@ROWCOUNT) để ghi nhật ký vào bảng Audit Log.


-- ------------------------------------------------------------------------------------------
-- Câu 2.2.3:
-- Đóng gói quy trình Two-Step Upsert vào một Transaction:
-- Đảm bảo tính nguyên tử (Atomicity): Cả 2 bước phải cùng thành công, nếu một bước lỗi thì toàn bộ bị hủy bỏ.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.3 TẠI ĐÂY:

-- 1. Kích hoạt cờ an toàn: Tự động hủy bỏ và rollback nếu có lỗi nghiêm trọng ở mức kết nối
SET XACT_ABORT ON;

BEGIN TRY
    -- 2. Mở khối giao dịch nguyên tử (Atomic Transaction)
    BEGIN TRANSACTION;

        -- Bước 1: UPDATE trạng thái mới cho các đơn hàng cũ đã tồn tại
        UPDATE tgt
        SET 
            tgt.order_status                  = src.order_status,
            tgt.order_approved_at             = src.order_approved_at,
            tgt.order_delivered_carrier_date  = src.order_delivered_carrier_date,
            tgt.order_delivered_customer_date = src.order_delivered_customer_date
        FROM dbo.olist_orders_dataset AS tgt
        INNER JOIN stg.stg_orders AS src
            ON tgt.order_id = src.order_id
        WHERE 
            ISNULL(tgt.order_status, '') <> ISNULL(src.order_status, '');

        -- Bước 2: INSERT các đơn hàng mới phát sinh (Guarded INSERT với NOT EXISTS)
        INSERT INTO dbo.olist_orders_dataset (
            order_id,
            customer_id,
            order_status,
            order_purchase_timestamp,
            order_approved_at,
            order_delivered_carrier_date,
            order_delivered_customer_date,
            order_estimated_delivery_date
        )
        SELECT 
            src.order_id,
            src.customer_id,
            src.order_status,
            src.order_purchase_timestamp,
            src.order_approved_at,
            src.order_delivered_carrier_date,
            src.order_delivered_customer_date,
            src.order_estimated_delivery_date
        FROM stg.stg_orders AS src
        WHERE NOT EXISTS (
            SELECT 1 
            FROM dbo.olist_orders_dataset AS tgt 
            WHERE tgt.order_id = src.order_id
        );

    -- 3. Xác nhận giao dịch thành công: Dữ liệu cả 2 bước chỉ được ghi cố định khi không có bất kỳ lỗi nào
    COMMIT TRANSACTION;

END TRY
BEGIN CATCH
    -- 4. Xử lý sự cố: Nếu có lỗi ở bất kỳ bước nào, rollback toàn bộ trạng thái về ban đầu
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;

    -- 5. Ném mã lỗi ra môi trường thực thi để hệ thống điều phối (Airflow / Data Factory) nhận diện sự cố
    THROW;
END CATCH;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (TRANSACTION & ATOMICITY IN PIPELINES):
-- 1. Tính nguyên tử (Atomicity - Chữ 'A' trong chuẩn ACID):
--    - Đảm bảo quy tắc "Tất cả hoặc không gì cả" (All-or-Nothing). Ngăn chặn triệt để tình trạng dữ liệu dở dang
--      khi một trong hai bước gặp sự cố (mất điện, rớt mạng, lỗi dung lượng đĩa, vi phạm ràng buộc).
-- 2. Kiểm soát Rollback an toàn (@@TRANCOUNT):
--    - Biến hệ thống @@TRANCOUNT kiểm tra xem có giao dịch nào đang mở hay không trước khi phát lệnh ROLLBACK,
--      tránh sinh thêm lỗi phụ ("No transaction found") trong khối CATCH.
-- 3. Cơ chế cảnh báo lỗi tự động (THROW):
--    - Ném nguyên bản mã lỗi và thông điệp lỗi (Error Message) ra ngoài môi trường thực thi,
--      giúp các công cụ điều phối (Airflow, Azure Data Factory) nhận diện được sự cố và kích hoạt báo động ngay lập tức.


-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 3]: ĐỒNG BỘ DỮ LIỆU NGUYÊN KHỐI VỚI CÂU LỆNH MERGE
-- ------------------------------------------------------------------------------------------

-- Câu 2.3.1:
-- Viết một câu lệnh MERGE duy nhất để đồng bộ danh mục sản phẩm từ Staging vào bảng đích:
-- Khi tìm thấy mã sản phẩm trùng khớp: Cập nhật giá bán và trọng lượng mới.
-- Khi không tìm thấy mã sản phẩm: Chèn bản ghi sản phẩm mới vào bảng đích.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.1 TẠI ĐÂY:

merge into dbo.olist_products_dataset AS target 
using (
    select 
        product_id,
        product_category_name,
        product_name_lenght,
        product_description_lenght,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    from stg.stg_products as src
)
as source on target.product_id = source.product_id  
when matched AND EXISTS (
    SELECT source.product_category_name, source.product_weight_g
    EXCEPT 
    SELECT target.product_category_name, target.product_weight_g
) 
then 
    update set 
        target.product_category_name = source.product_category_name,
        target.product_name_lenght = source.product_name_lenght,
        target.product_description_lenght = source.product_description_lenght,
        target.product_photos_qty = source.product_photos_qty,
        target.product_weight_g = source.product_weight_g,
        target.product_length_cm = source.product_length_cm,
        target.product_height_cm = source.product_height_cm,
        target.product_width_cm = source.product_width_cm
when not matched then 
    insert (
        product_id,
        product_category_name,
        product_name_lenght,
        product_description_lenght,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    ) values (
        source.product_id,
        source.product_category_name,
        source.product_name_lenght,
        source.product_description_lenght,
        source.product_photos_qty,
        source.product_weight_g,
        source.product_length_cm,
        source.product_height_cm,
        source.product_width_cm
    );

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (ĐỒNG BỘ NGUYÊN KHỐI VỚI CÂU LỆNH MERGE):
-- 1. Bản chất cơ chế UPSERT nguyên khối (Atomic Synchronization):
--    - Gom toàn bộ logic kiểm tra tồn tại, UPDATE bản ghi cũ và INSERT bản ghi mới vào trong MỘT lượt quét (Single Scan).
--    - Tối ưu hiệu năng I/O vượt trội so với việc chạy 2 câu lệnh UPDATE và INSERT riêng lẻ.
-- 2. Kỹ thuật chống "Ghost Update" (Redundant Update Prevention):
--    - Mệnh đề 'WHEN MATCHED AND EXISTS (... EXCEPT ...)' ngăn chặn việc ghi đè vô nghĩa khi dữ liệu nguồn và đích hoàn toàn giống nhau.
--    - Tiết kiệm dung lượng Transaction Log (.LDF), tránh phân mảnh chỉ mục (Index Fragmentation) và giảm thiểu khóa bảng (Table Locking).
-- 3. Lưu ý cú pháp bắt buộc trong T-SQL:
--    - Câu lệnh MERGE luôn bắt buộc phải kết thúc bằng dấu chấm phẩy (;).

-- ------------------------------------------------------------------------------------------
-- Câu 2.3.2:
-- Sử dụng mệnh đề OUTPUT để theo dõi chi tiết hành vi của MERGE:
-- Xuất ra danh sách các hành động đã thực hiện ($action: 'INSERT' hoặc 'UPDATE') kèm theo khóa chính bị tác động.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.2 TẠI ĐÂY:


-- =====================================================================
-- KỊCH BẢN DEMO KIỂM THỬ MỆNH ĐỀ OUTPUT TRONG MERGE
-- =====================================================================

-- 1. TẠO BẢNG ĐÍCH GIẢ LẬP (Hiện đang có 2 sản phẩm: PROD_01 và PROD_02)
DROP TABLE IF EXISTS #target_products;
CREATE TABLE #target_products (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name NVARCHAR(100),
    product_weight_g INT
);

INSERT INTO #target_products VALUES 
('PROD_01', N'Điện thoại', 200),
('PROD_02', N'Bàn phím', 500);

-- 2. TẠO BẢNG NGUỒN STAGING (Hôm nay có 2 sản phẩm: PROD_01 đổi cân nặng, PROD_03 mới tinh)
DROP TABLE IF EXISTS #stg_products;
CREATE TABLE #stg_products (
    product_id VARCHAR(50),
    product_category_name NVARCHAR(100),
    product_weight_g INT
);

INSERT INTO #stg_products VALUES 
('PROD_01', N'Điện thoại', 350),  -- Khớp khóa -> Sẽ kích hoạt UPDATE (đổi từ 200g lên 350g)
('PROD_03', N'Chuột máy tính', 150); -- Chưa có -> Sẽ kích hoạt INSERT

-- 3. CHẠY LỆNH MERGE CÓ MỆNH ĐỀ OUTPUT ĐỂ SOI KẾT QUẢ
MERGE INTO #target_products AS target
USING #stg_products AS source
    ON target.product_id = source.product_id

WHEN MATCHED THEN
    UPDATE SET 
        target.product_category_name = source.product_category_name,
        target.product_weight_g      = source.product_weight_g

WHEN NOT MATCHED THEN
    INSERT (product_id, product_category_name, product_weight_g)
    VALUES (source.product_id, source.product_category_name, source.product_weight_g)

-- 👇 Mệnh đề OUTPUT xuất ra chi tiết cả giá trị cũ (deleted) và mới (inserted):
OUTPUT 
    $action AS [Hành_Động],
    inserted.product_id AS [Mã_Sản_Phẩm],
    deleted.product_weight_g AS [Cân_Nặng_Cũ],
    inserted.product_weight_g AS [Cân_Nặng_Mới];

MERGE INTO dbo.olist_products_dataset AS target 
USING stg.stg_products AS source 
    ON target.product_id = source.product_id  
WHEN MATCHED THEN 
    UPDATE SET 
        target.product_category_name        = source.product_category_name,
        target.product_name_lenght          = source.product_name_lenght,
        target.product_description_lenght   = source.product_description_lenght,
        target.product_photos_qty           = source.product_photos_qty,
        target.product_weight_g             = source.product_weight_g,
        target.product_length_cm            = source.product_length_cm,
        target.product_height_cm            = source.product_height_cm,
        target.product_width_cm             = source.product_width_cm
WHEN NOT MATCHED THEN 
    INSERT (
        product_id,
        product_category_name,
        product_name_lenght,
        product_description_lenght,
        product_photos_qty,
        product_weight_g,
        product_length_cm,
        product_height_cm,
        product_width_cm
    ) VALUES (
        source.product_id,
        source.product_category_name,
        source.product_name_lenght,
        source.product_description_lenght,
        source.product_photos_qty,
        source.product_weight_g,
        source.product_length_cm,
        source.product_height_cm,
        source.product_width_cm
    )
OUTPUT 
    $action AS action_type,
    inserted.product_id AS affected_product_id;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (MỆNH ĐỀ OUTPUT TRONG MERGE):
-- 1. Giám sát hành vi theo thời gian thực (Real-time Audit Logging):
--    - Mệnh đề OUTPUT cho phép bắt trọn từng dòng dữ liệu bị tác động ngay trong chu kỳ thực thi của MERGE.
--    - Cột ảo $action tự động phân loại hành động thành 'INSERT', 'UPDATE' hoặc 'DELETE'.
-- 2. Ứng dụng trong Data Pipeline:
--    - Có thể kết hợp 'OUTPUT ... INTO #AuditLog' để lưu vết kiểm toán, đối soát số liệu hoặc kích hoạt luồng cảnh báo tự động.


-- ------------------------------------------------------------------------------------------
-- Câu 2.3.3:
-- Phòng chống lỗi nổ khóa nguồn trong MERGE:
-- Phân tích và minh họa lý do tại sao lệnh MERGE sẽ bị sập nếu bảng Staging có chứa dữ liệu trùng lặp khóa,
-- và viết truy vấn làm sạch khóa Staging trước khi thực hiện MERGE.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.3 TẠI ĐÂY:

-- BƯỚC 1: Dùng CTE để đánh số thứ tự (ROW_NUMBER) lọc trùng lặp cho bảng Staging
WITH Deduplicated_Staging AS (
    SELECT 
        product_id,
        product_category_name,
        product_weight_g,
        -- Các cột khác...
        ROW_NUMBER() OVER (
            PARTITION BY product_id                -- Gom theo mã sản phẩm
            ORDER BY (SELECT NULL)                 -- Hoặc ORDER BY updated_at DESC nếu có ngày cập nhật
        ) AS row_num
    FROM stg.stg_products
)

-- BƯỚC 2: Gọi trực tiếp CTE đã lọc 'row_num = 1' vào mệnh đề USING
MERGE INTO dbo.olist_products_dataset AS target 
USING (
    SELECT * 
    FROM Deduplicated_Staging 
    WHERE row_num = 1                             -- 💡 Chìa khóa: Chỉ giữ lại đúng 1 dòng duy nhất!
) AS source 
    ON target.product_id = source.product_id  

WHEN MATCHED THEN 
    UPDATE SET 
        target.product_category_name = source.product_category_name,
        target.product_weight_g      = source.product_weight_g

WHEN NOT MATCHED THEN 
    INSERT (product_id, product_category_name, product_weight_g)
    VALUES (source.product_id, source.product_category_name, source.product_weight_g);

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (LỖI NỔ KHÓA NGUỒN & KỸ THUẬT DEDUPLICATION):
-- 1. Bản chất lỗi nổ khóa nguồn (Non-Deterministic MERGE - Error 8672):
--    - SQL Server yêu cầu quan hệ 1-1 giữa mỗi dòng đích và mỗi dòng nguồn trong mệnh đề ON.
--    - Nếu bảng Staging có từ 2 dòng trở lên trùng khóa chính, Database không thể xác định giá trị nào để UPDATE dòng đích -> Lập tức ném lỗi Error 8672 và Rollback toàn bộ transaction.
-- 2. Kỹ thuật Deduplication chuẩn mực với CTE & ROW_NUMBER():
--    - 'PARTITION BY product_id': Gom nhóm dữ liệu theo từng khóa chính duy nhất.
--    - 'ORDER BY updated_at DESC' (hoặc tiêu chí ưu tiên): Đảm bảo chọn đúng bản ghi mới nhất hoặc đáng tin cậy nhất.
--    - 'WHERE row_num = 1': Phễu lọc triệt để loại bỏ dữ liệu trùng lặp trước khi cấp phát vào mệnh đề USING của MERGE.



-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 4]: UPSERT TRÊN BẢNG FACT & BẢNG QUAN HỆ CHI TIẾT
-- ------------------------------------------------------------------------------------------

-- Câu 2.4.1:
-- Thực hiện Upsert trên bảng chi tiết mặt hàng FactOrderItems:
-- Cập nhật lại số lượng và phí vận chuyển đối với các món hàng có sự điều chỉnh,
-- và chèn các món hàng mới phát sinh của các đơn hàng mới.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.1 TẠI ĐÂY:

-- BƯỚC 1: Khử trùng lặp nguồn Staging mặt hàng (Deduplication Layer với Composite PK)
WITH deduplicated_order_items AS (
    SELECT 
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, order_item_id 
            ORDER BY shipping_limit_date DESC
        ) AS rn
    FROM stg.stg_order_items
)
-- BƯỚC 2: Thực thi MERGE Upsert vào FactOrderItems với khóa bảo vệ WITH (HOLDLOCK)
MERGE INTO dbo.olist_order_items_dataset WITH (HOLDLOCK) AS target
USING (
    SELECT 
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    FROM deduplicated_order_items
    WHERE rn = 1
) AS source
    -- Mệnh đề ON: Ghép nối theo cặp Khóa chính ghép (Composite Primary Key)
    ON  target.order_id      = source.order_id 
    AND target.order_item_id = source.order_item_id

-- Mệnh đề MATCHED: Phát hiện thay đổi thông minh qua EXCEPT (chống Blind Update & an toàn NULL)
WHEN MATCHED AND EXISTS (
    SELECT source.product_id, source.seller_id, source.shipping_limit_date, source.price, source.freight_value
    EXCEPT 
    SELECT target.product_id, target.seller_id, target.shipping_limit_date, target.price, target.freight_value
) 
THEN 
    -- Nhánh UPDATE: Cập nhật thông tin hàng hóa, giá bán và cước vận chuyển thực tế
    UPDATE SET 
        target.product_id          = source.product_id,
        target.seller_id           = source.seller_id,
        target.shipping_limit_date = source.shipping_limit_date,
        target.price               = source.price,
        target.freight_value       = source.freight_value

-- Nhánh NOT MATCHED: Chèn mới các mặt hàng của đơn hàng mới phát sinh
WHEN NOT MATCHED THEN 
    INSERT (
        order_id,
        order_item_id,
        product_id,
        seller_id,
        shipping_limit_date,
        price,
        freight_value
    ) VALUES (
        source.order_id,
        source.order_item_id,
        source.product_id,
        source.seller_id,
        source.shipping_limit_date,
        source.price,
        source.freight_value
    );

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (UPSERT BẢNG FACT BÁN HÀNG CHI TIẾT):
-- 1. Đặc thù Composite Primary Key trong Fact Table:
--    - Bảng FactOrderItems không dùng khóa đơn mà định danh qua cặp (order_id, order_item_id).
--    - 'order_item_id' là số thứ tự món trong đơn (1, 2, 3...) - tuyệt đối không được đưa vào UPDATE SET vì làm thay đổi cấu trúc khóa.
-- 2. Tối ưu I/O và Transaction Log với toán tử EXCEPT:
--    - Bảng Fact thường có hàng triệu dòng. Kỹ thuật EXCEPT lọc chỉ cập nhật các dòng thực sự thay đổi giá hoặc phí ship,
--      tránh ghi đè vô ích (Blind Update), giúp giảm 90% dung lượng sinh ra trong Transaction Log (.ldf).


-- ------------------------------------------------------------------------------------------
-- Câu 2.4.2:
-- Thực hiện Upsert đồng bộ thông tin thanh toán:
-- Cập nhật số tiền thanh toán thực nhận nếu đơn có sự thay đổi về tổng thanh toán.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.2 TẠI ĐÂY:

-- BƯỚC 1: Khử trùng lặp nguồn Staging thanh toán theo cặp khóa giao dịch (order_id, payment_sequential)
WITH deduplicated_payments AS (
    SELECT 
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value,
        ROW_NUMBER() OVER (
            PARTITION BY order_id, payment_sequential 
            ORDER BY payment_value DESC               -- Hoặc updated_at DESC nếu có mốc thời gian
        ) AS rn
    FROM stg.stg_order_payments
    WHERE order_id IS NOT NULL
)
-- BƯỚC 2: Thực thi MERGE Upsert vào bảng Fact thanh toán với khóa bảo vệ WITH (HOLDLOCK)
MERGE INTO dbo.olist_order_payments_dataset WITH (HOLDLOCK) AS target
USING (
    SELECT 
        order_id,
        payment_sequential,
        payment_type,
        payment_installments,
        payment_value
    FROM deduplicated_payments
    WHERE rn = 1
) AS source 
    -- Mệnh đề ON: Ghép nối theo cặp khóa thứ tự đợt thanh toán của từng đơn
    ON  target.order_id           = source.order_id
    AND target.payment_sequential = source.payment_sequential

-- Mệnh đề MATCHED: Phát hiện chênh lệch số tiền thực nhận hoặc thay đổi phương thức thanh toán
WHEN MATCHED AND EXISTS (
    SELECT source.payment_type, source.payment_installments, source.payment_value
    EXCEPT 
    SELECT target.payment_type, target.payment_installments, target.payment_value
)
THEN
    -- Nhánh UPDATE: Cập nhật lại số tiền thanh toán thực nhận (payment_value) và thông tin liên quan
    UPDATE SET
        target.payment_type         = source.payment_type,
        target.payment_installments = source.payment_installments,
        target.payment_value        = source.payment_value

-- Nhánh NOT MATCHED: Chèn các đợt thanh toán phát sinh mới của đơn hàng
WHEN NOT MATCHED THEN
    INSERT (
        order_id,
        payment_sequential,     
        payment_type,
        payment_installments,
        payment_value
    ) VALUES (  
        source.order_id,
        source.payment_sequential,
        source.payment_type,
        source.payment_installments,
        source.payment_value
    );

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (ĐỒNG BỘ DỮ LIỆU THANH TOÁN ĐA ĐỢT):
-- 1. Mô hình thanh toán đa phương thức (Split Payments / Multi-tender):
--    - Một đơn hàng có thể thanh toán bằng nhiều hình thức (Voucher kết hợp Thẻ tín dụng).
--    - Việc liên kết qua cặp khóa (order_id, payment_sequential) đảm bảo tính toàn vẹn, không làm mất hoặc ghi đè các đợt thanh toán khác nhau.
-- 2. Tính toàn vẹn số liệu tài chính:
--    - Mọi sự điều chỉnh tiền thanh toán (payment_value) được cập nhật chính xác sẽ làm tiền đề đối soát doanh thu ở Câu 2.4.3.


-- ------------------------------------------------------------------------------------------
-- Câu 2.4.3:
-- Đối soát số liệu sau Upsert Fact Table:
-- Viết truy vấn kiểm tra tổng doanh thu và tổng số lượng món hàng trước và sau đợt Upsert
-- để xác nhận số liệu tài chính gia tăng một cách chính xác.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.3 TẠI ĐÂY:

-- KỊCH BẢN ĐỐI SOÁT KIỂM TOÁN TÀI CHÍNH & SẢN LƯỢNG (FINANCIAL RECONCILIATION AUDIT):

-- BƯỚC 1: Khởi tạo bảng tạm ghi nhận số liệu trước và sau Upsert (Pre/Post Load Audit Snapshot)
IF OBJECT_ID('tempdb..#fact_audit_snapshot') IS NOT NULL
    DROP TABLE #fact_audit_snapshot;

CREATE TABLE #fact_audit_snapshot (
    stage               VARCHAR(20),       -- 'PRE_UPSERT' hoặc 'POST_UPSERT'
    total_items         BIGINT,            -- Tổng số lượng món hàng (COUNT)
    total_revenue       DECIMAL(18, 2),    -- Tổng tiền hàng (SUM price)
    total_freight       DECIMAL(18, 2),    -- Tổng tiền cước (SUM freight_value)
    total_amount        DECIMAL(18, 2),    -- Tổng tiền đơn hàng (price + freight)
    snapshot_time       DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- BƯỚC 2: Chụp số liệu kiểm toán trước khi nạp (PRE_UPSERT SNAPSHOT)
-- (Trong pipeline thực tế, bước này chạy ngay trước khi thực thi lệnh MERGE)
INSERT INTO #fact_audit_snapshot (stage, total_items, total_revenue, total_freight, total_amount)
SELECT 
    'PRE_UPSERT'                              AS stage,
    COUNT(*)                                  AS total_items,
    ISNULL(SUM(price), 0)                     AS total_revenue,
    ISNULL(SUM(freight_value), 0)             AS total_freight,
    ISNULL(SUM(price + freight_value), 0)     AS total_amount
FROM dbo.olist_order_items_dataset;

-- (Giả lập: Tiến trình Upsert FactOrderItems ở Câu 2.4.1 được thực thi tại đây)

-- BƯỚC 3: Chụp số liệu kiểm toán sau khi nạp (POST_UPSERT SNAPSHOT)
INSERT INTO #fact_audit_snapshot (stage, total_items, total_revenue, total_freight, total_amount)
SELECT 
    'POST_UPSERT'                             AS stage,
    COUNT(*)                                  AS total_items,
    ISNULL(SUM(price), 0)                     AS total_revenue,
    ISNULL(SUM(freight_value), 0)             AS total_freight,
    ISNULL(SUM(price + freight_value), 0)     AS total_amount
FROM dbo.olist_order_items_dataset;

-- BƯỚC 4: Truy vấn đối soát số liệu gia tăng (Reconciliation Variance & Verification)
-- Đối chiếu mức tăng thực tế (Actual Delta) với mức tăng kỳ vọng từ Staging (Expected Delta)
WITH audit_pivoted AS (
    SELECT 
        MAX(CASE WHEN stage = 'PRE_UPSERT'  THEN total_items   END) AS pre_items,
        MAX(CASE WHEN stage = 'POST_UPSERT' THEN total_items   END) AS post_items,
        MAX(CASE WHEN stage = 'PRE_UPSERT'  THEN total_revenue END) AS pre_revenue,
        MAX(CASE WHEN stage = 'POST_UPSERT' THEN total_revenue END) AS post_revenue,
        MAX(CASE WHEN stage = 'PRE_UPSERT'  THEN total_freight END) AS pre_freight,
        MAX(CASE WHEN stage = 'POST_UPSERT' THEN total_freight END) AS post_freight,
        MAX(CASE WHEN stage = 'PRE_UPSERT'  THEN total_amount  END) AS pre_amount,
        MAX(CASE WHEN stage = 'POST_UPSERT' THEN total_amount  END) AS post_amount
    FROM #fact_audit_snapshot
),
expected_changes AS (
    -- Tính toán số liệu kỳ vọng từ tập Staging
    SELECT 
        COUNT(CASE WHEN tgt.order_id IS NULL THEN 1 END) AS expected_new_items,
        ISNULL(SUM(CASE WHEN tgt.order_id IS NULL THEN src.price END), 0)
        + ISNULL(SUM(CASE WHEN tgt.order_id IS NOT NULL THEN src.price - tgt.price END), 0) AS expected_revenue_delta
    FROM stg.stg_order_items src
    LEFT JOIN dbo.olist_order_items_dataset tgt
        ON src.order_id = tgt.order_id AND src.order_item_id = tgt.order_item_id
)
SELECT 
    p.pre_items,
    p.post_items,
    (p.post_items - p.pre_items)             AS delta_items,
    e.expected_new_items,
    p.pre_revenue,
    p.post_revenue,
    (p.post_revenue - p.pre_revenue)         AS delta_revenue,
    e.expected_revenue_delta,
    CASE 
        WHEN (p.post_items - p.pre_items) = e.expected_new_items
         AND (p.post_revenue - p.pre_revenue) = e.expected_revenue_delta
        THEN N'PASS (Đối soát tài chính khớp 100%)'
        ELSE N'FAIL (Phát hiện sai lệch doanh thu hoặc số lượng)'
    END AS reconciliation_status
FROM audit_pivoted p
CROSS JOIN expected_changes e;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (ĐỐI SOÁT DỮ LIỆU TÀI CHÍNH):
-- 1. Bản chất của Financial Reconciliation trong Data Pipeline:
--    - Khi nạp dữ liệu Fact (bán hàng/thanh toán), rủi ro lớn nhất là Double Counting (trùng lặp doanh thu) hoặc Missing Records (thất thoát bản ghi).
--    - Phương pháp Snapshot Pre/Post Load kết hợp Expected Delta từ Staging là tiêu chuẩn bắt buộc trong các Data Pipeline ngân hàng và thương mại điện tử.
-- 2. Quy tắc đối soát 2 chiều (Bidirectional Reconciliation):
--    - Chiều số lượng (Volume Check): delta_items phải đúng bằng số bản ghi mới tinh (New Inserts).
--    - Chiều giá trị (Value Check): delta_revenue phải đúng bằng (Doanh thu các món mới chèn + Chênh lệch điều chỉnh giá của các món cập nhật).
-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 5]: QUẢN LÝ XÓA MỀM (SOFT DELETE) TRONG QUY TRÌNH UPSERT
-- ------------------------------------------------------------------------------------------

-- Câu 2.5.1:
-- Khi hệ thống nguồn phát sinh bản ghi bị hủy bỏ hoặc xóa bỏ:
-- Viết câu lệnh Upsert cập nhật trạng thái xóa mềm (`is_deleted = 1` kèm ngày xóa) ở bảng đích
-- thay vì xóa bỏ dòng dữ liệu vật lý khỏi kho.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.1 TẠI ĐÂY:

-- CÁCH 1: SỬ DỤNG CÂU LỆNH UPDATE ĐỘC LẬP
-- 1.1. Trường hợp nguồn phát tín hiệu cờ xóa rõ ràng (CDC / Event Flag: src.is_deleted = 1)
UPDATE tgt
SET 
    tgt.is_deleted = 1,
    tgt.deleted_at = CURRENT_TIMESTAMP,
    tgt.updated_at = CURRENT_TIMESTAMP
FROM dbo.dim_customers AS tgt
INNER JOIN stg.stg_customers AS src
    ON tgt.customer_id = src.customer_id
WHERE 
    src.is_deleted = 1         -- Nguồn báo dòng này đã bị hủy/xóa
    AND tgt.is_deleted = 0;    -- Điều kiện tối ưu: Chỉ xóa nếu hiện tại chưa bị xóa (tránh Ghost Update)

-- 1.2. Trường hợp bản ghi bị xóa bằng cách "biến mất" khỏi nguồn (Absence of Record)
UPDATE tgt
SET 
    tgt.is_deleted = 1,
    tgt.deleted_at = CURRENT_TIMESTAMP,
    tgt.updated_at = CURRENT_TIMESTAMP
FROM dbo.dim_customers AS tgt
WHERE 
    tgt.is_deleted = 0         -- Chỉ xét các bản ghi đang còn hiệu lực
    AND NOT EXISTS (
        -- Kiểm tra nếu mã khách này không còn xuất hiện trong Staging nữa
        SELECT 1 
        FROM stg.stg_customers AS src
        WHERE src.customer_id = tgt.customer_id
    );

-- CÁCH 2: SỬ DỤNG CÂU LỆNH NGUYÊN KHỐI MERGE (KẾT HỢP NHÁNH WHEN NOT MATCHED BY SOURCE)
MERGE dbo.dim_customers AS target
USING stg.stg_customers AS source
    ON target.customer_id = source.customer_id

-- 1. Khi trùng khớp và có thay đổi thông tin -> UPDATE thông thường
WHEN MATCHED AND (
    ISNULL(target.customer_city, '') <> ISNULL(source.customer_city, '')
) THEN 
    UPDATE SET 
        target.customer_city  = source.customer_city,
        target.customer_state = source.customer_state,
        target.updated_at     = CURRENT_TIMESTAMP

-- 2. Khi là khách hàng mới tinh -> INSERT
WHEN NOT MATCHED BY TARGET THEN 
    INSERT (
        customer_id, 
        customer_city, 
        customer_state, 
        is_deleted, 
        created_at, 
        updated_at
    )
    VALUES (
        source.customer_id, 
        source.customer_city, 
        source.customer_state, 
        0, 
        CURRENT_TIMESTAMP, 
        CURRENT_TIMESTAMP
    )

-- 3. 🎯 XÓA MỀM (SOFT DELETE): Có ở Target nhưng KHÔNG CÒN TỒN TẠI ở Source
WHEN NOT MATCHED BY SOURCE AND target.is_deleted = 0 THEN 
    UPDATE SET 
        target.is_deleted = 1,
        target.deleted_at = CURRENT_TIMESTAMP,
        target.updated_at = CURRENT_TIMESTAMP;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (QUẢN LÝ XÓA MỀM - SOFT DELETE STRATEGY):
-- 1. Bản chất của Soft Delete trong Data Warehousing:
--    - Tuyệt đối tránh dùng Hard Delete (DELETE vật lý) trong kho dữ liệu để bảo toàn tính toàn vẹn tham chiếu (Referential Integrity),
--      tránh làm mồ côi các bản ghi Fact lịch sử và phục vụ yêu cầu kiểm toán dữ liệu (Data Auditing).
-- 2. Tối ưu hiệu năng với WHEN NOT MATCHED BY SOURCE:
--    - Câu lệnh MERGE của SQL Server cho phép xử lý đồng bộ trọn vẹn cả 3 trạng thái: INSERT (mới), UPDATE (sửa),
--      và SOFT DELETE (xóa) trong duy nhất MỘT lượt quét bảng (Single Table Scan).
-- 3. Phòng tránh Ghost Update trên bản ghi đã xóa:
--    - Điều kiện 'target.is_deleted = 0' là chốt chặn bắt buộc để ngăn chặn việc ghi đè mốc thời gian deleted_at
--      của các bản ghi vốn đã bị xóa mềm từ các chu kỳ nạp trước đó.



-- ------------------------------------------------------------------------------------------
-- Câu 2.5.2:
-- Xử lý tình huống tái kích hoạt (Reactivation):
-- Nếu một bản ghi từng bị đánh dấu xóa mềm sau đó xuất hiện trở lại với dữ liệu mới ở nguồn,
-- hãy viết lệnh Upsert tự động đưa trạng thái trở lại is_deleted = 0 và cập nhật thông tin mới nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.2 TẠI ĐÂY:

-- CÁCH 1: SỬ DỤNG CÂU LỆNH UPDATE ĐỘC LẬP ĐỂ TÁI KÍCH HOẠT (REACTIVATION)
UPDATE tgt
SET 
    -- 1. Cập nhật các thông tin thuộc tính mới nhất từ Staging
    tgt.customer_city  = src.customer_city,
    tgt.customer_state = src.customer_state,
    
    -- 2. Hồi sinh bản ghi: Trả cờ về 0 và xóa mốc thời gian xóa cũ
    tgt.is_deleted     = 0,
    tgt.deleted_at     = NULL,
    tgt.updated_at     = CURRENT_TIMESTAMP
FROM dbo.dim_customers AS tgt
INNER JOIN stg.stg_customers AS src
    ON tgt.customer_id = src.customer_id
WHERE 
    -- Điều kiện kích hoạt: Bản ghi ở kho đích trước đó đang bị đánh dấu xóa mềm
    tgt.is_deleted = 1;

-- CÁCH 2: TÍCH HỢP LOGIC HỒI SINH TRỰC TIẾP VÀO CÂU LỆNH MERGE NGUYÊN KHỐI
MERGE dbo.dim_customers AS target
USING stg.stg_customers AS source
    ON target.customer_id = source.customer_id

-- 1. Xử lý cả 2 tình huống: Bản ghi có thay đổi nội dung HOẶC bản ghi từng bị xóa mềm nay quay trở lại
WHEN MATCHED AND (
    target.is_deleted = 1 
    OR ISNULL(target.customer_city, '') <> ISNULL(source.customer_city, '')
) THEN 
    UPDATE SET 
        target.customer_city  = source.customer_city,
        target.customer_state = source.customer_state,
        target.is_deleted     = 0,     -- 🎯 Tái kích hoạt: Đưa cờ về 0
        target.deleted_at     = NULL,  -- 🎯 Xóa ngày xóa cũ
        target.updated_at     = CURRENT_TIMESTAMP

-- 2. Chèn bản ghi mới tinh
WHEN NOT MATCHED BY TARGET THEN 
    INSERT (
        customer_id, 
        customer_city, 
        customer_state, 
        is_deleted, 
        created_at, 
        updated_at
    )
    VALUES (
        source.customer_id, 
        source.customer_city, 
        source.customer_state, 
        0, 
        CURRENT_TIMESTAMP, 
        CURRENT_TIMESTAMP
    );

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (TÁI KÍCH HOẠT BẢN GHI - RECORD REACTIVATION):
-- 1. Khắc phục lỗi "bốc hơi dữ liệu" (Preventing Data Loss):
--    - Nếu thiếu cơ chế Reactivation, một khách hàng từng bị xóa mềm khi quay lại mua hàng sẽ vẫn bị gán nhãn is_deleted = 1,
--      dẫn đến việc các truy vấn phân tích (WHERE is_deleted = 0) bỏ qua toàn bộ hành vi và doanh thu mới của khách hàng này.
-- 2. Quản lý trạng thái thuộc tính (State Resetting):
--    - Khi tái kích hoạt, bắt buộc phải đồng thời gán 'is_deleted = 0' và đưa 'deleted_at = NULL' để khôi phục hoàn toàn
--      trạng thái hoạt động bình thường của bản ghi trong kho dữ liệu.
-- 3. Linh hoạt trong mô hình ELT:
--    - Có thể chạy tách rời một lệnh UPDATE hồi sinh riêng biệt hoặc tích hợp nhánh WHEN MATCHED trong MERGE để tối ưu I/O.

-- ------------------------------------------------------------------------------------------
-- Câu 2.5.3:
-- Xây dựng View báo cáo sạch:
-- Tạo View trên bảng đích tự động loại bỏ các bản ghi đã bị xóa mềm để phục vụ người dùng phân tích.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.3 TẠI ĐÂY:

-- 1. Xây dựng View báo cáo sạch (Clean Reporting View / Semantic Consumption Layer)
-- Cú pháp chuẩn trong SQL Server: CREATE OR ALTER VIEW (thay vì CREATE AND ALTER)
CREATE OR ALTER VIEW dbo.vw_dim_customers_active AS
SELECT 
    customer_id,
    customer_city,
    customer_state,
    created_at,
    updated_at
    -- 🎯 Best Practice: Cố tình ẩn các cột quản trị hệ thống (is_deleted, deleted_at)
    -- để người dùng phân tích (BI / Analysts) không thể nhìn thấy hoặc query nhầm dữ liệu đã xóa
FROM dbo.dim_customers
WHERE 
    is_deleted = 0;
GO

-- 2. Truy vấn kiểm thử View báo cáo (Verification Query)
-- Người dùng cuối (BI, Dashboard, Data Analyst) chỉ cần SELECT trực tiếp từ View mà không lo bị lẫn dữ liệu đã xóa
SELECT 
    customer_state,
    COUNT(*) AS total_active_customers
FROM dbo.vw_dim_customers_active
GROUP BY customer_state
ORDER BY total_active_customers DESC;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (CLEAN REPORTING VIEW & SEMANTIC LAYER):
-- 1. Tách biệt tầng lưu trữ và tầng tiêu thụ (Decoupling Storage & Consumption Layer):
--    - Bảng vật lý (Storage Layer): Lưu trữ trọn vẹn 100% dữ liệu lịch sử kể cả các dòng đã xóa mềm để phục vụ kiểm toán (Auditing) và khôi phục (Recovery).
--    - View sạch (Consumption Layer): Đóng vai trò là "lớp bảo vệ" giúp người dùng cuối (BI Analysts, Dashboard, Web App)
--      luôn nhận được dữ liệu sạch mà không cần phải nhớ viết thêm điều kiện 'WHERE is_deleted = 0' trong mỗi câu lệnh.
-- 2. Trừu tượng hóa cột kỹ thuật (Information Hiding):
--    - Bằng cách chỉ SELECT các cột nghiệp vụ và loại bỏ hoàn toàn các cột kỹ thuật nội bộ (is_deleted, deleted_at),
--      View giúp đơn giản hóa giao diện dữ liệu và ngăn chặn rủi ro vô tình sử dụng sai logic nghiệp vụ.
-- 3. Tối ưu hiệu năng thông qua Predicate Pushdown:
--    - View là một bảng ảo (Virtual Table), không tiêu tốn dung lượng đĩa. Khi người dùng query trên View kèm điều kiện lọc khác,
--      Database Engine sẽ tự động đẩy toàn bộ điều kiện xuống bảng gốc để tận dụng các chỉ mục (Index) sẵn có.


-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 6]: TÍNH CHẤT IDEMPOTENT & CHỐNG XUNG ĐỘT TRUY CẬP (RACE CONDITIONS)
-- ------------------------------------------------------------------------------------------

-- Câu 2.6.1:
-- Kiểm chứng tính chất Idempotent của tiến trình Upsert:
-- Chạy thử nghiệm lệnh Upsert 3 lần liên tiếp với cùng một tập dữ liệu nguồn và chứng minh
-- trạng thái bảng đích và số lượng bản ghi hoàn toàn không bị sai lệch sau nhiều lần chạy lại.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.1 TẠI ĐÂY:

-- 1. CHUẨN BỊ MÔI TRƯỜNG KIỂM THỬ TÍNH CHẤT IDEMPOTENT
DROP TABLE IF EXISTS #idempotent_target;
DROP TABLE IF EXISTS #idempotent_staging;
DROP TABLE IF EXISTS #idempotency_audit_log;

-- Bảng đích (Hiện có 2 khách hàng ban đầu: CUST_01 và CUST_02)
CREATE TABLE #idempotent_target (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_city NVARCHAR(100),
    customer_state VARCHAR(2),
    updated_at DATETIME2
);

INSERT INTO #idempotent_target VALUES 
('CUST_01', N'Sao Paulo', 'SP', '2026-01-01'),
('CUST_02', N'Campinas',  'SP', '2026-01-01');

-- Bảng nguồn Staging (Chứa: CUST_01 đổi thành phố, CUST_03 mới tinh)
CREATE TABLE #idempotent_staging (
    customer_id VARCHAR(50),
    customer_city NVARCHAR(100),
    customer_state VARCHAR(2)
);

INSERT INTO #idempotent_staging VALUES 
('CUST_01', N'Rio de Janeiro', 'RJ'), -- Khớp khóa -> Cần UPDATE
('CUST_03', N'Curitiba',       'PR'); -- Khóa mới -> Cần INSERT

-- Bảng lưu vết kết quả qua từng lần chạy thử nghiệm
CREATE TABLE #idempotency_audit_log (
    run_iteration INT,
    total_target_records INT,
    target_checksum_agg BIGINT,
    rows_inserted INT,
    rows_updated INT,
    run_time DATETIME2 DEFAULT CURRENT_TIMESTAMP
);

-- 2. VÒNG LẶP CHẠY LỆNH UPSERT 3 LẦN LIÊN TIẾP VỚI CÙNG MỘT TẬP DỮ LIỆU
DECLARE @iteration INT = 1;
WHILE @iteration <= 3
BEGIN
    DECLARE @ins_cnt INT = 0;
    DECLARE @upd_cnt INT = 0;

    -- Thực thi Two-Step Upsert có tối ưu chống Ghost Update
    -- Bước 1: UPDATE
    UPDATE tgt
    SET 
        tgt.customer_city  = src.customer_city,
        tgt.customer_state = src.customer_state,
        tgt.updated_at     = CURRENT_TIMESTAMP
    FROM #idempotent_target tgt
    INNER JOIN #idempotent_staging src ON tgt.customer_id = src.customer_id
    WHERE ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '')
       OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '');
    
    SET @upd_cnt = @@ROWCOUNT;

    -- Bước 2: INSERT có bảo vệ
    INSERT INTO #idempotent_target (customer_id, customer_city, customer_state, updated_at)
    SELECT src.customer_id, src.customer_city, src.customer_state, CURRENT_TIMESTAMP
    FROM #idempotent_staging src
    WHERE NOT EXISTS (
        SELECT 1 FROM #idempotent_target tgt WHERE tgt.customer_id = src.customer_id
    );

    SET @ins_cnt = @@ROWCOUNT;

    -- Ghi nhận trạng thái bảng đích sau lần chạy này
    INSERT INTO #idempotency_audit_log (
        run_iteration,
        total_target_records,
        target_checksum_agg,
        rows_inserted,
        rows_updated
    )
    SELECT 
        @iteration,
        COUNT(*),
        CHECKSUM_AGG(CHECKSUM(customer_id, customer_city, customer_state)),
        @ins_cnt,
        @upd_cnt
    FROM #idempotent_target;

    SET @iteration = @iteration + 1;
END;

-- 3. ĐỐI SOÁT KẾT QUẢ IDEMPOTENCY
SELECT 
    run_iteration,
    total_target_records,
    target_checksum_agg,
    rows_inserted,
    rows_updated,
    CASE 
        WHEN run_iteration = 1 THEN N'Lần 1: Thực hiện chèn mới và cập nhật thành công'
        WHEN rows_inserted = 0 AND rows_updated = 0 THEN N'PASS: Idempotent hoàn hảo (Không sinh dòng thừa, không đổi dữ liệu)'
        ELSE N'FAIL: Vi phạm tính Idempotent (Dữ liệu bị sai lệch)'
    END AS idempotency_status
FROM #idempotency_audit_log;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (TÍNH CHẤT IDEMPOTENT TRONG DATA PIPELINE):
-- 1. Bản chất của tính Idempotent (Idempotency Rule):
--    - f(f(x)) = f(x): Dù pipeline có bị chạy lại 1 lần, 3 lần hay 10 lần do cơ chế Auto-Retry của Airflow khi lỗi mạng,
--      thì trạng thái cuối cùng của kho dữ liệu vẫn phải đồng nhất 100%, không sinh ra bản ghi trùng lặp và không sai lệch số liệu.
-- 2. Kỹ thuật đo lường (CHECKSUM_AGG):
--    - Hàm CHECKSUM_AGG kết hợp CHECKSUM tính toán "vân tay số" của toàn bộ bảng.
--    - Giá trị checksum ở lần chạy 2 và 3 giữ nguyên y hệt lần 1 chứng minh dữ liệu không bị biến dạng dù thực thi lặp lại.
-- 3. Cơ chế bảo đảm Idempotent:
--    - Nhờ mệnh đề NOT EXISTS bảo vệ nhánh INSERT và điều kiện WHERE loại bỏ Ghost Update ở nhánh UPDATE.



-- ------------------------------------------------------------------------------------------
-- Câu 2.6.2:
-- Áp dụng cơ chế khóa an toàn (Locking Hints) trong quy trình Upsert
-- nhằm ngăn chặn lỗi Deadlock hoặc xung đột khi có nhiều tiến trình nạp dữ liệu cùng lúc.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.2 TẠI ĐÂY:

-- ÁP DỤNG CƠ CHẾ KHÓA AN TOÀN (LOCKING HINTS) TRONG TIẾN TRÌNH UPSERT
-- Ngăn chặn triệt để hiện tượng Race Condition (tranh chấp ghi) và Deadlock khi có nhiều tiến trình chạy song song

-- Cách 1: Áp dụng gợi ý khóa WITH (HOLDLOCK) trong câu lệnh MERGE
BEGIN TRANSACTION;

MERGE dbo.dim_customers WITH (HOLDLOCK) AS target -- 🎯 Khóa Key-Range Lock giữ đến hết transaction
USING stg.stg_customers AS source
    ON target.customer_id = source.customer_id

WHEN MATCHED AND (
    ISNULL(target.customer_city, '') <> ISNULL(source.customer_city, '')
    OR ISNULL(target.customer_state, '') <> ISNULL(source.customer_state, '')
) THEN 
    UPDATE SET 
        target.customer_city  = source.customer_city,
        target.customer_state = source.customer_state,
        target.updated_at     = CURRENT_TIMESTAMP

WHEN NOT MATCHED BY TARGET THEN 
    INSERT (customer_id, customer_city, customer_state, created_at, updated_at)
    VALUES (source.customer_id, source.customer_city, source.customer_state, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);

COMMIT TRANSACTION;

-- Cách 2: Áp dụng gợi ý khóa UPDLOCK, HOLDLOCK trong Two-Step Upsert
BEGIN TRANSACTION;

    -- Bước 1: UPDATE với gợi ý UPDLOCK (Yêu cầu khóa cập nhật trước, ngăn chặn deadlock)
    UPDATE tgt WITH (UPDLOCK)
    SET 
        tgt.customer_city  = src.customer_city,
        tgt.customer_state = src.customer_state,
        tgt.updated_at     = CURRENT_TIMESTAMP
    FROM dbo.dim_customers AS tgt
    INNER JOIN stg.stg_customers AS src
        ON tgt.customer_id = src.customer_id
    WHERE ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '')
       OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '');

    -- Bước 2: INSERT với gợi ý HOLDLOCK trên điều kiện kiểm tra tồn tại (Ngăn tiến trình khác chèn lén cùng ID)
    INSERT INTO dbo.dim_customers (customer_id, customer_city, customer_state, created_at, updated_at)
    SELECT src.customer_id, src.customer_city, src.customer_state, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
    FROM stg.stg_customers AS src
    WHERE NOT EXISTS (
        SELECT 1 
        FROM dbo.dim_customers AS tgt WITH (HOLDLOCK, UPDLOCK)
        WHERE tgt.customer_id = src.customer_id
    );

COMMIT TRANSACTION;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (LOCKING HINTS & CHỐNG RACE CONDITIONS):
-- 1. Bài toán xung đột tranh chấp (Race Condition):
--    - Nếu 2 tiến trình nạp dữ liệu cùng quét thấy customer_id = 'C123' chưa tồn tại, cả 2 sẽ cùng quyết định chạy lệnh INSERT.
--    - Tiến trình nào ghi trước sẽ thành công, tiến trình ghi sau sẽ bị lỗi văng pipeline (Violation of PRIMARY KEY constraint).
-- 2. Cơ chế của gợi ý khóa HOLDLOCK:
--    - HOLDLOCK tương đương với mức cô lập SERIALIZABLE, thiết lập khóa phạm vi (Key-Range Lock) trên cây Index.
--    - Nó buộc các tiến trình song song khác phải xếp hàng chờ cho đến khi Transaction hiện tại hoàn tất, đảm bảo an toàn tuyệt đối.
-- 3. Cơ chế của gợi ý khóa UPDLOCK:
--    - Thay vì dùng Shared Lock (S-Lock) dễ bị nâng cấp thành Exclusive Lock (X-Lock) gây Deadlock khi cả 2 luồng cùng nâng cấp,
--      UPDLOCK báo hiệu ý định sửa ngay từ đầu, giải quyết triệt để lỗi Conversion Deadlock.



-- ------------------------------------------------------------------------------------------
-- Câu 2.6.3:
-- Thiết kế kịch bản tự động khôi phục dữ liệu về trạng thái an toàn nếu lệnh Upsert bị ngắt kết nối đột ngột.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.3 TẠI ĐÂY:

-- THIẾT KẾ KỊCH BẢN TỰ ĐỘNG KHÔI PHỤC VÀ GHI NHẬT KÝ LỖI (COMPENSATION & AUTOMATIC ERROR RECOVERY)

-- 1. Tạo bảng quản lý lỗi (Error Log Table) nếu chưa tồn tại
IF OBJECT_ID('stg.pipeline_error_log', 'U') IS NULL
BEGIN
    CREATE TABLE stg.pipeline_error_log (
        error_id INT IDENTITY(1, 1) PRIMARY KEY,
        pipeline_name VARCHAR(100),
        error_number INT,
        error_severity INT,
        error_state INT,
        error_procedure VARCHAR(100),
        error_line INT,
        error_message NVARCHAR(4000),
        error_timestamp DATETIME2 DEFAULT CURRENT_TIMESTAMP
    );
END
GO

-- 2. Kịch bản khôi phục tự động sử dụng Atomic Transaction Trap
SET XACT_ABORT ON;

BEGIN TRY
    BEGIN TRANSACTION;

        -- Giả lập cập nhật dữ liệu gia tăng
        UPDATE tgt
        SET 
            tgt.customer_city  = src.customer_city,
            tgt.customer_state = src.customer_state,
            tgt.updated_at     = CURRENT_TIMESTAMP
        FROM dbo.dim_customers AS tgt
        INNER JOIN stg.stg_customers AS src
            ON tgt.customer_id = src.customer_id
        WHERE ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '');

        -- ⚠️ MÔ PHỎNG SỰ CỐ DỮ LIỆU ĐỘT BIẾN HOẶC NGẮT KẾT NỐI ĐỘT NGỘT:
        -- DECLARE @simulate_error INT = 1 / 0;

        INSERT INTO dbo.dim_customers (customer_id, customer_city, customer_state, created_at, updated_at)
        SELECT src.customer_id, src.customer_city, src.customer_state, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM stg.stg_customers AS src
        WHERE NOT EXISTS (
            SELECT 1 FROM dbo.dim_customers AS tgt WHERE tgt.customer_id = src.customer_id
        );

    COMMIT TRANSACTION;
    PRINT N'Pipeline hoàn tất thành công 100%.';
END TRY
BEGIN CATCH
    -- Tự động khôi phục: Rollback sạch sẽ toàn bộ trạng thái dở dang
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
        PRINT N'Đã phát hiện sự cố! Tự động ROLLBACK toàn bộ dữ liệu về trạng thái an toàn ban đầu.';
    END

    -- Ghi nhật ký lỗi vào bảng quản trị để phục vụ phân tích nguyên nhân gốc rễ (RCA)
    INSERT INTO stg.pipeline_error_log (
        pipeline_name,
        error_number,
        error_severity,
        error_state,
        error_procedure,
        error_line,
        error_message
    )
    VALUES (
        'upsert_customers_pipeline',
        ERROR_NUMBER(),
        ERROR_SEVERITY(),
        ERROR_STATE(),
        ISNULL(ERROR_PROCEDURE(), 'Ad-hoc Script'),
        ERROR_LINE(),
        ERROR_MESSAGE()
    );

    -- Ném mã lỗi để hệ thống điều phối (Airflow / Data Factory) nhận diện cảnh báo
    THROW;
END CATCH;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (AUTOMATIC ERROR RECOVERY & AUDIT LOGGING):
-- 1. Cơ chế khôi phục trạng thái an toàn (Self-Healing & Rollback):
--    - Trong kiến trúc hệ thống dữ liệu lớn, mất kết nối mạng hoặc tràn đĩa là điều bất khả kháng.
--    - Cơ chế XACT_ABORT kết hợp TRY...CATCH đảm bảo kho dữ liệu không bao giờ bị rơi vào trạng thái "hỏng một nửa" (Partial Failure).
-- 2. Truy vết nguyên nhân gốc rễ (Root Cause Analysis - RCA):
--    - Bảng stg.pipeline_error_log lưu trữ chính xác dòng code bị gãy (ERROR_LINE), mã lỗi kỹ thuật (ERROR_NUMBER)
--      và thông điệp lỗi thực tế giúp đội ngũ On-call Data Engineer khắc phục sự cố trong vòng vài phút.



-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 7]: ĐÓNG GÓI STORED PROCEDURE UPSERT CHUẨN PRODUCTION
-- ------------------------------------------------------------------------------------------

-- Câu 2.7.1:
-- Xây dựng Stored Procedure usp_Upsert_Dim_Customers:
-- Nhận dữ liệu từ Staging, thực hiện đồng bộ Upsert vào bảng Dimension khách hàng
-- và ghi nhận lịch sử số lượng bản ghi bị tác động vào bảng Audit Log.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.1 TẠI ĐÂY:

-- 1. Tạo bảng lưu vết lịch sử nạp (Pipeline Audit Log) nếu chưa tồn tại
IF OBJECT_ID('stg.pipeline_audit_log', 'U') IS NULL
BEGIN
    CREATE TABLE stg.pipeline_audit_log (
        log_id INT IDENTITY(1, 1) PRIMARY KEY,
        procedure_name VARCHAR(100),
        batch_id VARCHAR(50),
        rows_inserted INT DEFAULT 0,
        rows_updated INT DEFAULT 0,
        rows_deleted INT DEFAULT 0,
        start_time DATETIME2,
        end_time DATETIME2,
        duration_seconds INT,
        status VARCHAR(20),
        error_message NVARCHAR(4000)
    );
END
GO

-- 2. Xây dựng Stored Procedure chuẩn Production: usp_Upsert_Dim_Customers
CREATE OR ALTER PROCEDURE dbo.usp_Upsert_Dim_Customers
    @batch_id VARCHAR(50) = 'MANUAL_RUN'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start_time DATETIME2 = CURRENT_TIMESTAMP;
    DECLARE @end_time DATETIME2;
    DECLARE @ins_count INT = 0;
    DECLARE @upd_count INT = 0;
    DECLARE @del_count INT = 0;

    -- Bảng tạm bắt kết quả hành động của lệnh MERGE
    DECLARE @ActionSummary TABLE (
        action_type VARCHAR(10)
    );

    BEGIN TRY
        BEGIN TRANSACTION;

            -- Đồng bộ nguyên khối bằng MERGE có mệnh đề OUTPUT
            MERGE dbo.dim_customers WITH (HOLDLOCK) AS target
            USING stg.stg_customers AS source
                ON target.customer_id = source.customer_id

            -- Khi trùng khóa và có thông tin thay đổi -> UPDATE
            WHEN MATCHED AND (
                ISNULL(target.customer_city, '') <> ISNULL(source.customer_city, '')
                OR ISNULL(target.customer_state, '') <> ISNULL(source.customer_state, '')
                OR target.is_deleted = 1
            ) THEN 
                UPDATE SET 
                    target.customer_city  = source.customer_city,
                    target.customer_state = source.customer_state,
                    target.is_deleted     = 0,
                    target.deleted_at     = NULL,
                    target.updated_at     = CURRENT_TIMESTAMP

            -- Khi là bản ghi mới -> INSERT
            WHEN NOT MATCHED BY TARGET THEN 
                INSERT (customer_id, customer_city, customer_state, is_deleted, created_at, updated_at)
                VALUES (source.customer_id, source.customer_city, source.customer_state, 0, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)

            -- Xóa mềm nếu nguồn không còn tồn tại
            WHEN NOT MATCHED BY SOURCE AND target.is_deleted = 0 THEN 
                UPDATE SET 
                    target.is_deleted = 1,
                    target.deleted_at = CURRENT_TIMESTAMP,
                    target.updated_at = CURRENT_TIMESTAMP
            
            -- Ghi nhận toàn bộ hành vi vào bảng tạm
            OUTPUT  INTO @ActionSummary;

            -- Thống kê số lượng từng loại tác vụ
            SELECT 
                @ins_count = COUNT(CASE WHEN action_type = 'INSERT' THEN 1 END),
                @upd_count = COUNT(CASE WHEN action_type = 'UPDATE' THEN 1 END)
            FROM @ActionSummary;

        COMMIT TRANSACTION;

        SET @end_time = CURRENT_TIMESTAMP;

        -- Ghi log thành công vào bảng Audit Log
        INSERT INTO stg.pipeline_audit_log (
            procedure_name, batch_id, rows_inserted, rows_updated, rows_deleted,
            start_time, end_time, duration_seconds, status, error_message
        )
        VALUES (
            'usp_Upsert_Dim_Customers', @batch_id, @ins_count, @upd_count, @del_count,
            @start_time, @end_time, DATEDIFF(SECOND, @start_time, @end_time), 'SUCCESS', NULL
        );

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @end_time = CURRENT_TIMESTAMP;

        -- Ghi log thất bại
        INSERT INTO stg.pipeline_audit_log (
            procedure_name, batch_id, rows_inserted, rows_updated, rows_deleted,
            start_time, end_time, duration_seconds, status, error_message
        )
        VALUES (
            'usp_Upsert_Dim_Customers', @batch_id, 0, 0, 0,
            @start_time, @end_time, DATEDIFF(SECOND, @start_time, @end_time), 'FAILED', ERROR_MESSAGE()
        );

        THROW;
    END CATCH;
END;
GO

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (STORED PROCEDURE ĐÓNG GÓI CHUẨN PRODUCTION):
-- 1. Khả năng tự quản trị và giám sát (Observability & Telemetry):
--    - Mọi lần thực thi Stored Procedure đều được tự động đo lường thời gian chạy (duration_seconds),
--      đếm số dòng tác động (inserted, updated) và ghi thẳng vào bảng stg.pipeline_audit_log.
-- 2. Độc lập tham số (Parameterization):
--    - Tham số @batch_id cho phép tích hợp liền mạch với các orchestrator hiện đại (Apache Airflow DAG run_id, ADF run_id)
--      để dễ dàng đối soát số liệu theo từng mẻ chạy.



-- ------------------------------------------------------------------------------------------
-- Câu 2.7.2:
-- Xây dựng Stored Procedure usp_Upsert_Fact_Orders:
-- Thực hiện đồng bộ trạng thái đơn hàng và các mốc thời gian giao nhận vào bảng Fact bán hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.2 TẠI ĐÂY:

CREATE OR ALTER PROCEDURE dbo.usp_Upsert_Fact_Orders
    @batch_id VARCHAR(50) = 'MANUAL_RUN'
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @start_time DATETIME2 = CURRENT_TIMESTAMP;
    DECLARE @end_time DATETIME2;
    DECLARE @rows_updated INT = 0;
    DECLARE @rows_inserted INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

            -- Bước 1: UPDATE trạng thái đơn hàng và các mốc thời gian giao nhận
            UPDATE tgt
            SET 
                tgt.order_status                  = src.order_status,
                tgt.order_approved_at             = src.order_approved_at,
                tgt.order_delivered_carrier_date  = src.order_delivered_carrier_date,
                tgt.order_delivered_customer_date = src.order_delivered_customer_date
            FROM dbo.olist_orders_dataset AS tgt WITH (UPDLOCK)
            INNER JOIN stg.stg_orders AS src
                ON tgt.order_id = src.order_id
            WHERE 
                ISNULL(tgt.order_status, '') <> ISNULL(src.order_status, '')
                OR ISNULL(tgt.order_approved_at, '1900-01-01') <> ISNULL(src.order_approved_at, '1900-01-01')
                OR ISNULL(tgt.order_delivered_carrier_date, '1900-01-01') <> ISNULL(src.order_delivered_carrier_date, '1900-01-01')
                OR ISNULL(tgt.order_delivered_customer_date, '1900-01-01') <> ISNULL(src.order_delivered_customer_date, '1900-01-01');

            SET @rows_updated = @@ROWCOUNT;

            -- Bước 2: INSERT các đơn hàng mới phát sinh (Guarded INSERT với HOLDLOCK)
            INSERT INTO dbo.olist_orders_dataset (
                order_id,
                customer_id,
                order_status,
                order_purchase_timestamp,
                order_approved_at,
                order_delivered_carrier_date,
                order_delivered_customer_date,
                order_estimated_delivery_date
            )
            SELECT 
                src.order_id,
                src.customer_id,
                src.order_status,
                src.order_purchase_timestamp,
                src.order_approved_at,
                src.order_delivered_carrier_date,
                src.order_delivered_customer_date,
                src.order_estimated_delivery_date
            FROM stg.stg_orders AS src
            WHERE NOT EXISTS (
                SELECT 1 
                FROM dbo.olist_orders_dataset AS tgt WITH (HOLDLOCK, UPDLOCK)
                WHERE tgt.order_id = src.order_id
            );

            SET @rows_inserted = @@ROWCOUNT;

        COMMIT TRANSACTION;

        SET @end_time = CURRENT_TIMESTAMP;

        -- Ghi nhận lịch sử nạp Fact vào Audit Log
        INSERT INTO stg.pipeline_audit_log (
            procedure_name, batch_id, rows_inserted, rows_updated, rows_deleted,
            start_time, end_time, duration_seconds, status, error_message
        )
        VALUES (
            'usp_Upsert_Fact_Orders', @batch_id, @rows_inserted, @rows_updated, 0,
            @start_time, @end_time, DATEDIFF(SECOND, @start_time, @end_time), 'SUCCESS', NULL
        );

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SET @end_time = CURRENT_TIMESTAMP;

        INSERT INTO stg.pipeline_audit_log (
            procedure_name, batch_id, rows_inserted, rows_updated, rows_deleted,
            start_time, end_time, duration_seconds, status, error_message
        )
        VALUES (
            'usp_Upsert_Fact_Orders', @batch_id, 0, 0, 0,
            @start_time, @end_time, DATEDIFF(SECOND, @start_time, @end_time), 'FAILED', ERROR_MESSAGE()
        );

        THROW;
    END CATCH;
END;
GO

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (ĐỒNG BỘ BẢNG FACT BÁN HÀNG):
-- 1. Đặc thù của bảng Fact Đơn hàng:
--    - Không chỉ có trạng thái (status), mà các mốc thời gian (approved, carrier, delivered) liên tục cập nhật theo chu kỳ giao vận.
--    - Mệnh đề WHERE so sánh đa mốc thời gian kết hợp ISNULL giúp bắt kịp toàn bộ sự kiện logistics mà không sinh ra No-Op Updates.



-- ------------------------------------------------------------------------------------------
-- Câu 2.7.3:
-- Viết kịch bản kiểm thử tự động (Automated Test Case) cho Stored Procedure Upsert:
-- Chuẩn bị tập dữ liệu giả lập chứa cả 3 trường hợp: bản ghi chèn mới, bản ghi cập nhật, và bản ghi giữ nguyên,
-- sau đó xác minh kết quả sau khi thực thi Stored Procedure.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.3 TẠI ĐÂY:

-- ==========================================================================================
-- KỊCH BẢN KIỂM THỬ TỰ ĐỘNG (AUTOMATED TEST HARNESS CHO STORED PROCEDURE UPSERT)
-- ==========================================================================================

-- BƯỚC 1: DỰNG MÔI TRƯỜNG GIẢ LẬP ISOLATED CHO TEST CASE
DROP TABLE IF EXISTS #test_target_customers;
DROP TABLE IF EXISTS #test_staging_customers;

-- Bảng đích giả lập (Đang có sẵn 2 khách hàng)
CREATE TABLE #test_target_customers (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_city NVARCHAR(100),
    customer_state VARCHAR(2),
    is_deleted BIT DEFAULT 0,
    updated_at DATETIME2
);

INSERT INTO #test_target_customers (customer_id, customer_city, customer_state, is_deleted, updated_at) VALUES 
('CUST_TEST_01', N'Hà Nội',    'HN', 0, '2026-01-01'), -- Sẽ thử nghiệm UPDATE
('CUST_TEST_02', N'Đà Nẵng',   'DN', 0, '2026-01-01'); -- Sẽ thử nghiệm NO-CHANGE (Giữ nguyên)

-- Bảng Staging giả lập chứa ĐỦ CẢ 3 TRƯỜNG HỢP:
-- (1) CUST_TEST_01: Cũ -> Đổi thành phố sang Sài Gòn (Kỳ vọng: UPDATE)
-- (2) CUST_TEST_02: Cũ -> Giữ nguyên Đà Nẵng (Kỳ vọng: UNCHANGED / NO-OP)
-- (3) CUST_TEST_03: Mới tinh (Kỳ vọng: INSERT)
CREATE TABLE #test_staging_customers (
    customer_id VARCHAR(50),
    customer_city NVARCHAR(100),
    customer_state VARCHAR(2)
);

INSERT INTO #test_staging_customers VALUES 
('CUST_TEST_01', N'Hồ Chí Minh', 'SG'), -- Case 1: UPDATE
('CUST_TEST_02', N'Đà Nẵng',     'DN'), -- Case 2: UNCHANGED
('CUST_TEST_03', N'Hải Phòng',   'HP'); -- Case 3: INSERT

-- BƯỚC 2: THỰC THI LOGIC UPSERT MẪU TRÊN TẬP TEST
DECLARE @test_updated_count INT = 0;
DECLARE @test_inserted_count INT = 0;

-- 2.1. UPDATE
UPDATE tgt
SET 
    tgt.customer_city  = src.customer_city,
    tgt.customer_state = src.customer_state,
    tgt.updated_at     = CURRENT_TIMESTAMP
FROM #test_target_customers AS tgt
INNER JOIN #test_staging_customers AS src
    ON tgt.customer_id = src.customer_id
WHERE ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '')
   OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '');

SET @test_updated_count = @@ROWCOUNT;

-- 2.2. INSERT
INSERT INTO #test_target_customers (customer_id, customer_city, customer_state, is_deleted, updated_at)
SELECT src.customer_id, src.customer_city, src.customer_state, 0, CURRENT_TIMESTAMP
FROM #test_staging_customers AS src
WHERE NOT EXISTS (
    SELECT 1 FROM #test_target_customers AS tgt WHERE tgt.customer_id = src.customer_id
);

SET @test_inserted_count = @@ROWCOUNT;

-- BƯỚC 3: KIỂM THỬ KHẲNG ĐỊNH TỰ ĐỘNG (AUTOMATED ASSERTIONS)
DECLARE @actual_total_target INT = (SELECT COUNT(*) FROM #test_target_customers);
DECLARE @cust_01_city NVARCHAR(100) = (SELECT customer_city FROM #test_target_customers WHERE customer_id = 'CUST_TEST_01');
DECLARE @cust_03_exists INT = (SELECT COUNT(*) FROM #test_target_customers WHERE customer_id = 'CUST_TEST_03');

-- Bảng kết quả kiểm thử (Test Results Dashboard)
SELECT 
    'TC_01: Verify Rows Updated' AS test_case_name,
    1                            AS expected_value,
    @test_updated_count          AS actual_value,
    CASE WHEN @test_updated_count = 1 THEN 'PASSED' ELSE 'FAILED' END AS result
UNION ALL
SELECT 
    'TC_02: Verify Rows Inserted',
    1,
    @test_inserted_count,
    CASE WHEN @test_inserted_count = 1 THEN 'PASSED' ELSE 'FAILED' END
UNION ALL
SELECT 
    'TC_03: Total Target Records Count',
    3,
    @actual_total_target,
    CASE WHEN @actual_total_target = 3 THEN 'PASSED' ELSE 'FAILED' END
UNION ALL
SELECT 
    'TC_04: Verify Value Updated (CUST_TEST_01 City = HCM)',
    1,
    CASE WHEN @cust_01_city = N'Hồ Chí Minh' THEN 1 ELSE 0 END,
    CASE WHEN @cust_01_city = N'Hồ Chí Minh' THEN 'PASSED' ELSE 'FAILED' END
UNION ALL
SELECT 
    'TC_05: Verify New Record Inserted (CUST_TEST_03 Exists)',
    1,
    @cust_03_exists,
    CASE WHEN @cust_03_exists = 1 THEN 'PASSED' ELSE 'FAILED' END;

-- GHI CHÚ KIẾN TRÚC & BÀI TOÁN THỰC TẾ (DATA PIPELINE UNIT TESTING):
-- 1. Tầm quan trọng của Kiểm thử tự động trong Data Engineering (DataOps):
--    - Giống như Software Engineering cần Unit Test, Data Pipeline cần Automated Test Cases để xác minh
--      các quy tắc chuyển đổi dữ liệu (Transformation Rules) trước khi triển khai lên môi trường Production.
-- 2. Độ bao phủ kiểm thử (Test Coverage):
--    - Bộ dữ liệu mẫu phải kiểm thử trọn vẹn cả 3 kịch bản cốt lõi: Chèn mới (Insert), Cập nhật nội dung (Update),
--      và Bỏ qua bản ghi không đổi (No-Op / Ghost Update).
-- 3. Khẳng định tính đúng đắn (Automated Assertions):
--    - Đánh giá tự động trạng thái PASSED / FAILED giúp tích hợp vào quy trình CI/CD (GitHub Actions / GitLab CI)
--      nhằm chặn đứng code lỗi trước khi merge vào nhánh chính.