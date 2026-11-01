-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 3: KIẾN TRÚC DATA PIPELINE & DATA WAREHOUSING (END-TO-END DATA ENGINEERING)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 4: DATA WAREHOUSE PIPELINE: STAGING → DIMENSION → FACT
-- Kiến trúc chuẩn: RAW → STAGING → DIMENSION → FACT
-- Áp dụng cho Project Olist E-Commerce
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 1]: THIẾT KẾ & NẠP TẦNG STAGING (STAGING LAYER)
-- ------------------------------------------------------------------------------------------

-- Câu 4.1.1:
-- Thiết kế bảng Staging đơn hàng `stg_orders` và viết câu lệnh nạp làm sạch từ bảng nguồn thô:
-- Chuẩn hóa trạng thái đơn, định dạng ngày giờ chuẩn ISO, và loại bỏ các bản ghi không hợp lệ.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1.1 TẠI ĐÂY:

-- 1. Tạo Schema 'stg' nếu chưa có
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'stg')
BEGIN
    EXEC('CREATE SCHEMA stg');
END;

-- 2. Xóa bảng Staging cũ nếu đã tồn tại
DROP TABLE IF EXISTS stg.stg_orders;

-- 3. Chu trình CTE làm sạch và nạp trực tiếp vào bảng Staging
;WITH raw_orders AS (
    SELECT 
        o.order_id, 
        o.customer_id, 
        o.order_status, 
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
standardized_orders AS (
    SELECT 
        TRIM(order_id) AS order_id, 
        TRIM(customer_id) AS customer_id, 
        LOWER(TRIM(order_status)) AS order_status,
        CONVERT(VARCHAR(19), order_purchase_timestamp, 120) AS order_purchase_timestamp,
        CONVERT(VARCHAR(19), order_approved_at, 120) AS order_approved_at,
        CONVERT(VARCHAR(19), order_delivered_carrier_date, 120) AS order_delivered_carrier_date,
        CONVERT(VARCHAR(19), order_delivered_customer_date, 120) AS order_delivered_customer_date,
        CONVERT(VARCHAR(19), order_estimated_delivery_date, 120) AS order_estimated_delivery_date
    FROM raw_orders o
    WHERE o.order_status IS NOT NULL
      AND (o.order_delivered_customer_date IS NULL 
           OR o.order_delivered_customer_date >= o.order_purchase_timestamp)
)
SELECT *
INTO stg.stg_orders
FROM standardized_orders;

-- Kiểm tra kết quả nạp vào Staging
SELECT COUNT(*) AS total_stg_orders FROM stg.stg_orders;
SELECT TOP 10 * FROM stg.stg_orders;
-- ------------------------------------------------------------------------------------------
-- Câu 4.1.2:
-- Thiết kế bảng Staging khách hàng `stg_customers` và viết câu lệnh nạp:
-- Chuẩn hóa tên thành phố, mã bang, mã bưu chính và khử trùng lặp đưa về 1 dòng cho mỗi khách hàng duy nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1.2 TẠI ĐÂY:

-- 1. Xóa bảng Staging cũ nếu đã tồn tại
DROP TABLE IF EXISTS stg.stg_customers;

-- 2. Chu trình CTE chuẩn hóa và khử trùng lặp khách hàng
;WITH raw_customers AS (
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
    -- Khử trùng lặp: mỗi khách hàng duy nhất (customer_unique_id) chỉ giữ 1 bản ghi đại diện
    SELECT 
        rc.customer_id,
        rc.customer_unique_id,
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
    customer_id,
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix
INTO stg.stg_customers
FROM dedup_customers
WHERE rn = 1;

-- Kiểm tra kết quả nạp vào Staging
SELECT COUNT(*) AS total_stg_customers FROM stg.stg_customers;
SELECT TOP 10 * FROM stg.stg_customers;


-- ------------------------------------------------------------------------------------------
-- Câu 4.1.3:
-- Thiết kế bảng Staging sản phẩm `stg_products`:
-- Chuẩn hóa tên ngành hàng, quy đổi trọng lượng sang kg và kích thước sang m3, gán giá trị mặc định cho dữ liệu thiếu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1.3 TẠI ĐÂY:

-- 1. Xóa bảng Staging cũ nếu đã tồn tại
DROP TABLE IF EXISTS stg.stg_products;

-- 2. Chu trình CTE chuẩn hóa sản phẩm, quy đổi trọng lượng/thể tích và xử lý giá trị thiếu
;WITH raw_products AS (
    SELECT 
        TRIM(p.product_id) AS product_id,
        COALESCE(LOWER(TRIM(p.product_category_name)), 'unknown') AS product_category_name,
        COALESCE(p.product_name_lenght, 0) AS product_name_length,
        COALESCE(p.product_description_lenght, 0) AS product_description_length,
        COALESCE(p.product_photos_qty, 0) AS product_photos_qty,
        COALESCE(p.product_weight_g, 0) AS product_weight_g,
        COALESCE(p.product_length_cm, 0) AS product_length_cm,
        COALESCE(p.product_height_cm, 0) AS product_height_cm,
        COALESCE(p.product_width_cm, 0) AS product_width_cm
    FROM dbo.olist_products_dataset p
    WHERE p.product_id IS NOT NULL
),
transformed_products AS (
    SELECT 
        rp.product_id,
        rp.product_category_name,
        rp.product_name_length,
        rp.product_description_length,
        rp.product_photos_qty,
        rp.product_weight_g,
        -- Quy đổi trọng lượng từ gram sang kg (chia 1000.0)
        ROUND(CAST(rp.product_weight_g AS FLOAT) / 1000.0, 3) AS product_weight_kg,
        rp.product_length_cm,
        rp.product_height_cm,
        rp.product_width_cm,
        -- Quy đổi kích thước sang m3 (dài * rộng * cao / 1,000,000.0)
        ROUND(CAST(rp.product_length_cm * rp.product_height_cm * rp.product_width_cm AS FLOAT) / 1000000.0, 6) AS product_volume_m3
    FROM raw_products rp
)
SELECT *
INTO stg.stg_products
FROM transformed_products;

-- Kiểm tra kết quả nạp vào Staging
SELECT COUNT(*) AS total_stg_products FROM stg.stg_products;
SELECT TOP 10 * FROM stg.stg_products;





-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 2]: XÂY DỰNG BẢNG CHIỀU KHÁCH HÀNG (DIM_CUSTOMER)
-- ------------------------------------------------------------------------------------------

-- Câu 4.2.1:
-- Thiết kế cấu trúc bảng `dim_customer` chuẩn Data Warehouse:
-- Bao gồm khóa đại diện tự tăng (`customer_key INT IDENTITY(1,1)` làm Primary Key),
-- khóa tự nhiên nghiệp vụ (`customer_unique_id`), và các thuộc tính địa bàn đã chuẩn hóa.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2.1 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.dim_customer;

CREATE TABLE dbo.dim_customer (
    customer_key INT IDENTITY(1,1),
    customer_unique_id VARCHAR(50) NOT NULL UNIQUE,
    customer_city NVARCHAR(100), 
    customer_state VARCHAR(20), 
    customer_zip_code_prefix VARCHAR(10),
    created_at DATETIME DEFAULT GETDATE(),
    updated_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT pk_customers PRIMARY KEY (customer_key)
);

-- ------------------------------------------------------------------------------------------
-- Câu 4.2.2:
-- Viết câu lệnh nạp dữ liệu từ `stg_customers` vào `dim_customer`:
-- Đảm bảo có thêm bản ghi đại diện mặc định mang khóa `customer_key = -1` ('Unknown Customer')
-- để dự phòng cho các đơn hàng mồ côi không tìm thấy thông tin khách.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2.2 TẠI ĐÂY:

-- 1. Chèn bản ghi đại diện mặc định (Unknown Member) mang khóa customer_key = -1
IF NOT EXISTS (SELECT 1 FROM dbo.dim_customer WHERE customer_key = -1)
BEGIN
    SET IDENTITY_INSERT dbo.dim_customer ON;

    INSERT INTO dbo.dim_customer (
        customer_key,
        customer_unique_id,
        customer_city,
        customer_state,
        customer_zip_code_prefix
    )
    VALUES (
        -1,
        'UNKNOWN',
        N'Unknown Customer',
        'NA',
        '00000'
    );

    SET IDENTITY_INSERT dbo.dim_customer OFF;
END;

-- 2. Nạp dữ liệu khách hàng thật từ tầng Staging (stg.stg_customers)
INSERT INTO dbo.dim_customer (
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix
)
SELECT 
    src.customer_unique_id,
    src.customer_city,
    src.customer_state,
    src.customer_zip_code_prefix
FROM stg.stg_customers src
WHERE NOT EXISTS (
    SELECT 1 
    FROM dbo.dim_customer tgt 
    WHERE tgt.customer_unique_id = src.customer_unique_id
);

-- Kiểm tra kết quả sau khi nạp
SELECT COUNT(*) AS total_dim_customers FROM dbo.dim_customer;
SELECT TOP 10 * FROM dbo.dim_customer ORDER BY customer_key ASC;




-- ------------------------------------------------------------------------------------------
-- Câu 4.2.3:
-- Áp dụng cơ chế cập nhật thông tin địa chỉ mới nhất cho khách hàng trong bảng Dimension (SCD Type 1).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2.3 TẠI ĐÂY:

-- CÁCH 1: SỬ DỤNG LỆNH MERGE NGUYÊN KHỐI (UPSERT - SCD TYPE 1)
MERGE INTO dbo.dim_customer AS tgt
USING stg.stg_customers AS src
    ON tgt.customer_unique_id = src.customer_unique_id
-- 1. Nếu khách hàng đã tồn tại VÀ có sự thay đổi về địa chỉ -> Cập nhật ghi đè (SCD Type 1)
WHEN MATCHED AND tgt.customer_key <> -1 AND (
    ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '')
    OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '')
    OR ISNULL(tgt.customer_zip_code_prefix, '') <> ISNULL(src.customer_zip_code_prefix, '')
) THEN
    UPDATE SET 
        tgt.customer_city = src.customer_city,
        tgt.customer_state = src.customer_state,
        tgt.customer_zip_code_prefix = src.customer_zip_code_prefix,
        tgt.updated_at = GETDATE()
-- 2. Nếu khách hàng chưa có trong Dimension -> Chèn mới
WHEN NOT MATCHED BY TARGET THEN
    INSERT (
        customer_unique_id,
        customer_city,
        customer_state,
        customer_zip_code_prefix,
        created_at,
        updated_at
    )
    VALUES (
        src.customer_unique_id,
        src.customer_city,
        src.customer_state,
        src.customer_zip_code_prefix,
        GETDATE(),
        GETDATE()
    );


-- CÁCH 2: TÁCH 2 LỆNH UPDATE VÀ INSERT ĐỘC LẬP (AN TOÀN, DỄ DEBUG)
-- Bước 1: Cập nhật địa chỉ mới cho những khách hàng có thay đổi (SCD Type 1)
UPDATE tgt
SET 
    tgt.customer_city = src.customer_city,
    tgt.customer_state = src.customer_state,
    tgt.customer_zip_code_prefix = src.customer_zip_code_prefix,
    tgt.updated_at = GETDATE()
FROM dbo.dim_customer tgt
INNER JOIN stg.stg_customers src
    ON tgt.customer_unique_id = src.customer_unique_id
WHERE tgt.customer_key <> -1
  AND (
      ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '')
      OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '')
      OR ISNULL(tgt.customer_zip_code_prefix, '') <> ISNULL(src.customer_zip_code_prefix, '')
  );

-- Bước 2: Chèn thêm những khách hàng mới chưa tồn tại trong Dimension
INSERT INTO dbo.dim_customer (
    customer_unique_id,
    customer_city,
    customer_state,
    customer_zip_code_prefix,
    created_at,
    updated_at
)
SELECT 
    src.customer_unique_id,
    src.customer_city,
    src.customer_state,
    src.customer_zip_code_prefix,
    GETDATE(),
    GETDATE()
FROM stg.stg_customers src
WHERE NOT EXISTS (
    SELECT 1 
    FROM dbo.dim_customer tgt 
    WHERE tgt.customer_unique_id = src.customer_unique_id
);



-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 3]: XÂY DỰNG DIMENSION SẢN PHẨM & ĐỊA ĐIỂM (DIM_PRODUCT & DIM_LOCATION)
-- ------------------------------------------------------------------------------------------

-- Câu 4.3.1:
-- Thiết kế và viết câu lệnh nạp dữ liệu cho bảng `dim_product`:
-- Tạo khóa đại diện `product_key`, lưu mã sản phẩm, ngành hàng, phân khúc trọng lượng và phân khúc thể tích.
-- Bổ sung bản ghi mặc định `product_key = -1` ('Unknown Product').
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3.1 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.dim_product;

CREATE TABLE dbo.dim_product (
    product_key INT IDENTITY(1,1) NOT NULL,
    product_id VARCHAR(50) NOT NULL UNIQUE,
    product_category_name VARCHAR(100),
    product_weight_kg FLOAT,
    weight_tier VARCHAR(20),
    product_volume_m3 FLOAT,
    volume_tier VARCHAR(20),
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT pk_dim_products PRIMARY KEY (product_key)
);

-- 1. Chèn bản ghi mặc định product_key = -1 ('Unknown Product')
IF NOT EXISTS (SELECT 1 FROM dbo.dim_product WHERE product_key = -1)
BEGIN
    SET IDENTITY_INSERT dbo.dim_product ON;

    INSERT INTO dbo.dim_product (
        product_key,
        product_id,
        product_category_name,
        product_weight_kg,
        weight_tier,
        product_volume_m3,
        volume_tier
    )
    VALUES (
        -1,
        'UNKNOWN',
        N'Unknown Product',
        0,
        'Unknown',
        0,
        'Unknown'
    );

    SET IDENTITY_INSERT dbo.dim_product OFF;
END;

-- 2. Nạp dữ liệu sản phẩm từ Staging kèm phân khúc trọng lượng & thể tích
INSERT INTO dbo.dim_product (
    product_id,
    product_category_name,
    product_weight_kg,
    weight_tier,
    product_volume_m3,
    volume_tier
)
SELECT 
    p.product_id,
    p.product_category_name,
    p.product_weight_kg,
    CASE 
        WHEN p.product_weight_kg <= 0 THEN 'Unknown'
        WHEN p.product_weight_kg < 1.0 THEN 'Light'
        WHEN p.product_weight_kg <= 5.0 THEN 'Medium'
        ELSE 'Heavy'
    END AS weight_tier,
    p.product_volume_m3,
    CASE 
        WHEN p.product_volume_m3 <= 0 THEN 'Unknown'
        WHEN p.product_volume_m3 < 0.01 THEN 'Small'
        WHEN p.product_volume_m3 <= 0.05 THEN 'Medium'
        ELSE 'Bulky'
    END AS volume_tier
FROM stg.stg_products p
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.dim_product tgt WHERE tgt.product_id = p.product_id
);


-- ------------------------------------------------------------------------------------------
-- Câu 4.3.2:
-- Thiết kế và nạp bảng danh mục địa điểm `dim_location`:
-- Khử trùng lặp bảng Geolocation để tạo danh mục địa bàn duy nhất theo mã bưu chính kèm tọa độ trung bình đại diện.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3.2 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.dim_location;

CREATE TABLE dbo.dim_location (
    location_key INT IDENTITY(1,1) NOT NULL,
    zip_code_prefix VARCHAR(10) NOT NULL UNIQUE,
    city NVARCHAR(100),
    state VARCHAR(20),
    avg_lat FLOAT,
    avg_lng FLOAT,
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT pk_dim_location PRIMARY KEY (location_key)
);

-- Khử trùng lặp bảng Geolocation theo mã bưu chính và nạp vào dim_location
;WITH dedup_geo AS (
    SELECT 
        RIGHT(CONCAT('00000', g.geolocation_zip_code_prefix), 5) AS zip_code_prefix,
        COALESCE(UPPER(TRIM(MAX(g.geolocation_city))), 'UNKNOWN') AS city,
        COALESCE(UPPER(TRIM(MAX(g.geolocation_state))), 'UNKNOWN') AS state,
        ROUND(AVG(g.geolocation_lat), 6) AS avg_lat,
        ROUND(AVG(g.geolocation_lng), 6) AS avg_lng
    FROM dbo.olist_geolocation_dataset g
    WHERE g.geolocation_zip_code_prefix IS NOT NULL
    GROUP BY RIGHT(CONCAT('00000', g.geolocation_zip_code_prefix), 5)
)
INSERT INTO dbo.dim_location (
    zip_code_prefix,
    city,
    state,
    avg_lat,
    avg_lng
)
SELECT 
    dg.zip_code_prefix,
    dg.city,
    dg.state,
    dg.avg_lat,
    dg.avg_lng
FROM dedup_geo dg
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.dim_location tgt WHERE tgt.zip_code_prefix = dg.zip_code_prefix
);


-- ------------------------------------------------------------------------------------------
-- Câu 4.3.3:
-- Bổ sung bản ghi mặc định `location_key = -1` ('Unknown Location') vào bảng địa điểm.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3.3 TẠI ĐÂY:

IF NOT EXISTS (SELECT 1 FROM dbo.dim_location WHERE location_key = -1)
BEGIN
    SET IDENTITY_INSERT dbo.dim_location ON;

    INSERT INTO dbo.dim_location (
        location_key,
        zip_code_prefix,
        city,
        state,
        avg_lat,
        avg_lng
    )
    VALUES (
        -1,
        '00000',
        N'Unknown Location',
        'NA',
        0.0,
        0.0
    );

    SET IDENTITY_INSERT dbo.dim_location OFF;
END;


-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 4]: XÂY DỰNG BẢNG CHIỀU THỜI GIAN (DIM_DATE)
-- ------------------------------------------------------------------------------------------

-- Câu 4.4.1:
-- Thiết kế bảng chiều thời gian `dim_date` hoàn chỉnh:
-- Khóa chính `date_key INT` (dạng số nguyên YYYYMMDD), ngày chuẩn ISO, năm, quý, tháng, tuần trong năm,
-- tên thứ và cờ phân biệt ngày cuối tuần (`is_weekend`).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.4.1 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.dim_date;

CREATE TABLE dbo.dim_date (
    date_key INT NOT NULL,
    full_date DATE NOT NULL UNIQUE,
    [year] INT NOT NULL,
    [quarter] INT NOT NULL,
    [month] INT NOT NULL,
    month_name VARCHAR(20) NOT NULL,
    week_of_year INT NOT NULL,
    day_of_month INT NOT NULL,
    day_of_week_name VARCHAR(20) NOT NULL,
    is_weekend BIT NOT NULL,
    CONSTRAINT pk_dim_date PRIMARY KEY (date_key)
);

-- Chèn bản ghi mặc định date_key = -1 phòng trường hợp đơn hàng thiếu ngày
IF NOT EXISTS (SELECT 1 FROM dbo.dim_date WHERE date_key = -1)
BEGIN
    INSERT INTO dbo.dim_date (
        date_key, full_date, [year], [quarter], [month], 
        month_name, week_of_year, day_of_month, day_of_week_name, is_weekend
    )
    VALUES (-1, '1900-01-01', 1900, 1, 1, 'Unknown', 1, 1, 'Unknown', 0);
END;


-- ------------------------------------------------------------------------------------------
-- Câu 4.4.2:
-- Viết câu lệnh SQL tự động sinh toàn bộ danh mục ngày tháng từ ngày 2016-01-01 đến 2020-12-31
-- để nạp sẵn dữ liệu cho bảng `dim_date`.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.4.2 TẠI ĐÂY:

;WITH date_series AS (
    SELECT CAST('2016-01-01' AS DATE) AS cal_date
    UNION ALL
    SELECT DATEADD(DAY, 1, cal_date)
    FROM date_series
    WHERE cal_date < '2020-12-31'
)
INSERT INTO dbo.dim_date (
    date_key,
    full_date,
    [year],
    [quarter],
    [month],
    month_name,
    week_of_year,
    day_of_month,
    day_of_week_name,
    is_weekend
)
SELECT 
    CAST(CONVERT(VARCHAR(8), cal_date, 112) AS INT) AS date_key,
    cal_date AS full_date,
    YEAR(cal_date) AS [year],
    DATEPART(QUARTER, cal_date) AS [quarter],
    MONTH(cal_date) AS [month],
    DATENAME(MONTH, cal_date) AS month_name,
    DATEPART(WEEK, cal_date) AS week_of_year,
    DAY(cal_date) AS day_of_month,
    DATENAME(WEEKDAY, cal_date) AS day_of_week_name,
    CASE 
        WHEN DATENAME(WEEKDAY, cal_date) IN ('Saturday', 'Sunday') THEN 1 
        ELSE 0 
    END AS is_weekend
FROM date_series ds
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.dim_date d WHERE d.full_date = ds.cal_date
)
OPTION (MAXRECURSION 0);


-- ------------------------------------------------------------------------------------------
-- Câu 4.4.3:
-- Viết câu lệnh tra cứu (Lookup) chuyển đổi từ mốc thời gian timestamp của đơn hàng
-- sang khóa ngoại `date_key` tương ứng trong bảng `dim_date`.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.4.3 TẠI ĐÂY:

SELECT TOP 50
    o.order_id,
    o.order_purchase_timestamp,
    COALESCE(d.date_key, -1) AS purchase_date_key,
    d.full_date,
    d.day_of_week_name,
    d.is_weekend
FROM stg.stg_orders o
LEFT JOIN dbo.dim_date d
    ON CAST(o.order_purchase_timestamp AS DATE) = d.full_date;


-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 5]: XÂY DỰNG BẢNG FACT BÁN HÀNG CHI TIẾT (FACT_SALES)
-- ------------------------------------------------------------------------------------------

-- Câu 4.5.1:
-- Xác định Grain hạt nhân của bảng Fact:
-- Thiết kế bảng `fact_sales` ở cấp độ: 1 dòng tương ứng với 1 mặt hàng bán ra trong đơn hàng (`order_id, order_item_id`).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.5.1 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.fact_sales;

CREATE TABLE dbo.fact_sales (
    sales_key BIGINT IDENTITY(1,1) NOT NULL,
    order_id VARCHAR(50) NOT NULL,
    order_item_id INT NOT NULL,
    customer_key INT NOT NULL,
    product_key INT NOT NULL,
    location_key INT NOT NULL,
    purchase_date_key INT NOT NULL,
    quantity INT NOT NULL DEFAULT 1,
    unit_price DECIMAL(18,2) NOT NULL DEFAULT 0,
    freight_value DECIMAL(18,2) NOT NULL DEFAULT 0,
    total_item_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT pk_fact_sales PRIMARY KEY (sales_key),
    CONSTRAINT uq_fact_sales_grain UNIQUE (order_id, order_item_id),
    CONSTRAINT fk_fact_sales_customer FOREIGN KEY (customer_key) REFERENCES dbo.dim_customer(customer_key),
    CONSTRAINT fk_fact_sales_product FOREIGN KEY (product_key) REFERENCES dbo.dim_product(product_key),
    CONSTRAINT fk_fact_sales_location FOREIGN KEY (location_key) REFERENCES dbo.dim_location(location_key),
    CONSTRAINT fk_fact_sales_date FOREIGN KEY (purchase_date_key) REFERENCES dbo.dim_date(date_key)
);


-- ------------------------------------------------------------------------------------------
-- Câu 4.5.2:
-- Viết câu lệnh nạp dữ liệu vào `fact_sales` thực hiện tra cứu khóa ngoại (Dimension Key Lookup):
-- Nối dữ liệu mặt hàng với các bảng Dimension (`DimCustomer`, `DimProduct`, `DimLocation`, `DimDate`)
-- để lấy các Surrogate Key tương ứng (gán khóa -1 nếu không tìm thấy Dimension khớp).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.5.2 TẠI ĐÂY:

-- Truy vấn kiểm tra Dimension Key Lookup trước khi nạp
SELECT TOP 50
    oi.order_id,
    oi.order_item_id,
    COALESCE(dc.customer_key, -1) AS customer_key,
    COALESCE(dp.product_key, -1) AS product_key,
    COALESCE(dl.location_key, -1) AS location_key,
    COALESCE(dd.date_key, -1) AS purchase_date_key
FROM dbo.olist_order_items_dataset oi
INNER JOIN stg.stg_orders o 
    ON oi.order_id = o.order_id
LEFT JOIN dbo.olist_customers_dataset raw_c 
    ON o.customer_id = raw_c.customer_id
LEFT JOIN dbo.dim_customer dc 
    ON raw_c.customer_unique_id = dc.customer_unique_id
LEFT JOIN dbo.dim_product dp 
    ON oi.product_id = dp.product_id
LEFT JOIN dbo.dim_location dl 
    ON RIGHT(CONCAT('00000', raw_c.customer_zip_code_prefix), 5) = dl.zip_code_prefix
LEFT JOIN dbo.dim_date dd 
    ON CAST(o.order_purchase_timestamp AS DATE) = dd.full_date;


-- ------------------------------------------------------------------------------------------
-- Câu 4.5.3:
-- Nạp các chỉ số tài chính cộng dồn được (Additive Measures) vào `fact_sales`:
-- Số lượng, đơn giá, tiền cước vận chuyển và tổng giá trị thanh toán của từng mặt hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.5.3 TẠI ĐÂY:

INSERT INTO dbo.fact_sales (
    order_id,
    order_item_id,
    customer_key,
    product_key,
    location_key,
    purchase_date_key,
    quantity,
    unit_price,
    freight_value,
    total_item_amount
)
SELECT 
    oi.order_id,
    oi.order_item_id,
    COALESCE(dc.customer_key, -1) AS customer_key,
    COALESCE(dp.product_key, -1) AS product_key,
    COALESCE(dl.location_key, -1) AS location_key,
    COALESCE(dd.date_key, -1) AS purchase_date_key,
    1 AS quantity,
    CAST(COALESCE(oi.price, 0) AS DECIMAL(18,2)) AS unit_price,
    CAST(COALESCE(oi.freight_value, 0) AS DECIMAL(18,2)) AS freight_value,
    CAST(COALESCE(oi.price, 0) + COALESCE(oi.freight_value, 0) AS DECIMAL(18,2)) AS total_item_amount
FROM dbo.olist_order_items_dataset oi
INNER JOIN stg.stg_orders o 
    ON oi.order_id = o.order_id
LEFT JOIN dbo.olist_customers_dataset raw_c 
    ON o.customer_id = raw_c.customer_id
LEFT JOIN dbo.dim_customer dc 
    ON raw_c.customer_unique_id = dc.customer_unique_id
LEFT JOIN dbo.dim_product dp 
    ON oi.product_id = dp.product_id
LEFT JOIN dbo.dim_location dl 
    ON RIGHT(CONCAT('00000', raw_c.customer_zip_code_prefix), 5) = dl.zip_code_prefix
LEFT JOIN dbo.dim_date dd 
    ON CAST(o.order_purchase_timestamp AS DATE) = dd.full_date
WHERE NOT EXISTS (
    SELECT 1 
    FROM dbo.fact_sales fs 
    WHERE fs.order_id = oi.order_id 
      AND fs.order_item_id = oi.order_item_id
);


-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 6]: XÂY DỰNG BẢNG FACT ĐƠN HÀNG TỔNG QUÁT (FACT_ORDERS)
-- ------------------------------------------------------------------------------------------

-- Câu 4.6.1:
-- Thiết kế bảng Fact thứ hai `fact_orders` ở cấp độ Grain: 1 dòng tương ứng với 1 đơn hàng nguyên vẹn (`order_id`).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.6.1 TẠI ĐÂY:

DROP TABLE IF EXISTS dbo.fact_orders;

CREATE TABLE dbo.fact_orders (
    order_key BIGINT IDENTITY(1,1) NOT NULL,
    order_id VARCHAR(50) NOT NULL UNIQUE,
    customer_key INT NOT NULL,
    location_key INT NOT NULL,
    purchase_date_key INT NOT NULL,
    order_status VARCHAR(50),
    primary_payment_type VARCHAR(50),
    total_items INT NOT NULL DEFAULT 0,
    total_item_price DECIMAL(18,2) NOT NULL DEFAULT 0,
    total_freight_value DECIMAL(18,2) NOT NULL DEFAULT 0,
    total_order_amount DECIMAL(18,2) NOT NULL DEFAULT 0,
    delivery_days INT NULL,
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT pk_fact_orders PRIMARY KEY (order_key),
    CONSTRAINT fk_fact_orders_customer FOREIGN KEY (customer_key) REFERENCES dbo.dim_customer(customer_key),
    CONSTRAINT fk_fact_orders_location FOREIGN KEY (location_key) REFERENCES dbo.dim_location(location_key),
    CONSTRAINT fk_fact_orders_date FOREIGN KEY (purchase_date_key) REFERENCES dbo.dim_date(date_key)
);


-- ------------------------------------------------------------------------------------------
-- Câu 4.6.2:
-- Nạp dữ liệu vào `fact_orders` từ tầng Staging:
-- Tính tổng số món hàng, tổng tiền hàng, tổng cước phí, hình thức thanh toán chính,
-- và số ngày hoàn tất giao hàng của từng đơn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.6.2 TẠI ĐÂY:

;WITH agg_items AS (
    SELECT 
        order_id,
        COUNT(*) AS total_items,
        CAST(SUM(COALESCE(price, 0)) AS DECIMAL(18,2)) AS total_item_price,
        CAST(SUM(COALESCE(freight_value, 0)) AS DECIMAL(18,2)) AS total_freight_value,
        CAST(SUM(COALESCE(price, 0) + COALESCE(freight_value, 0)) AS DECIMAL(18,2)) AS total_order_amount
    FROM dbo.olist_order_items_dataset
    GROUP BY order_id
),
ranked_payments AS (
    SELECT 
        order_id,
        payment_type,
        ROW_NUMBER() OVER (
            PARTITION BY order_id 
            ORDER BY SUM(payment_value) DESC
        ) AS rn
    FROM dbo.olist_order_payments_dataset
    GROUP BY order_id, payment_type
)
INSERT INTO dbo.fact_orders (
    order_id,
    customer_key,
    location_key,
    purchase_date_key,
    order_status,
    primary_payment_type,
    total_items,
    total_item_price,
    total_freight_value,
    total_order_amount,
    delivery_days
)
SELECT 
    o.order_id,
    COALESCE(dc.customer_key, -1) AS customer_key,
    COALESCE(dl.location_key, -1) AS location_key,
    COALESCE(dd.date_key, -1) AS purchase_date_key,
    o.order_status,
    COALESCE(rp.payment_type, 'unknown') AS primary_payment_type,
    COALESCE(ai.total_items, 0) AS total_items,
    COALESCE(ai.total_item_price, 0) AS total_item_price,
    COALESCE(ai.total_freight_value, 0) AS total_freight_value,
    COALESCE(ai.total_order_amount, 0) AS total_order_amount,
    DATEDIFF(DAY, CAST(o.order_purchase_timestamp AS DATETIME), CAST(o.order_delivered_customer_date AS DATETIME)) AS delivery_days
FROM stg.stg_orders o
LEFT JOIN dbo.olist_customers_dataset raw_c 
    ON o.customer_id = raw_c.customer_id
LEFT JOIN dbo.dim_customer dc 
    ON raw_c.customer_unique_id = dc.customer_unique_id
LEFT JOIN dbo.dim_location dl 
    ON RIGHT(CONCAT('00000', raw_c.customer_zip_code_prefix), 5) = dl.zip_code_prefix
LEFT JOIN dbo.dim_date dd 
    ON CAST(o.order_purchase_timestamp AS DATE) = dd.full_date
LEFT JOIN agg_items ai 
    ON o.order_id = ai.order_id
LEFT JOIN ranked_payments rp 
    ON o.order_id = rp.order_id AND rp.rn = 1
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.fact_orders fo WHERE fo.order_id = o.order_id
);


-- ------------------------------------------------------------------------------------------
-- Câu 4.6.3:
-- Đối soát tính toàn vẹn giữa hai bảng Fact:
-- So sánh tổng doanh thu tính từ `fact_sales` (cấp mặt hàng) và `fact_orders` (cấp đơn hàng)
-- để đảm bảo hai bảng Fact hoàn toàn khớp nhau về số liệu tài chính.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.6.3 TẠI ĐÂY:

WITH sales_agg AS (
    SELECT 
        SUM(unit_price) AS total_item_revenue,
        SUM(freight_value) AS total_freight,
        SUM(total_item_amount) AS total_gross_revenue
    FROM dbo.fact_sales
),
orders_agg AS (
    SELECT 
        SUM(total_item_price) AS total_item_revenue,
        SUM(total_freight_value) AS total_freight,
        SUM(total_order_amount) AS total_gross_revenue
    FROM dbo.fact_orders
)
SELECT 
    s.total_gross_revenue AS fact_sales_gross_revenue,
    o.total_gross_revenue AS fact_orders_gross_revenue,
    (s.total_gross_revenue - o.total_gross_revenue) AS variance_amount,
    CASE 
        WHEN ABS(s.total_gross_revenue - o.total_gross_revenue) = 0 THEN 'MATCHED (100% RECONCILED)'
        ELSE 'MISMATCH DETECTED'
    END AS reconciliation_status
FROM sales_agg s
CROSS JOIN orders_agg o;


-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 7]: ĐIỀU PHỐI TOÀN BỘ QUY TRÌNH DATA WAREHOUSE (END-TO-END ORCHESTRATION)
-- ------------------------------------------------------------------------------------------

-- Câu 4.7.1:
-- Xây dựng kịch bản điều phối thực thi trọn vẹn theo đúng trình tự phụ thuộc:
-- Bước 1: Nạp Staging $\rightarrow$ Bước 2: Nạp các Dimension $\rightarrow$ Bước 3: Nạp các Fact Table.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.7.1 TẠI ĐÂY:

-- Kịch bản điều phối chuẩn (Chạy tuần tự theo phụ thuộc khóa ngoại)
-- Bước 1: Làm sạch Staging (stg_orders, stg_customers, stg_products)
PRINT N'>>> BƯỚC 1: Kiểm tra và đảm bảo dữ liệu tầng Staging đã sẵn sàng...';
SELECT COUNT(*) AS stg_orders_count FROM stg.stg_orders;
SELECT COUNT(*) AS stg_customers_count FROM stg.stg_customers;
SELECT COUNT(*) AS stg_products_count FROM stg.stg_products;

-- Bước 2: Nạp / Cập nhật các bảng Dimension (Phải có trước khi nạp Fact)
PRINT N'>>> BƯỚC 2: Đảm bảo các bảng Dimension (Customer, Product, Location, Date) đã cập nhật...';
-- (Thực thi logic SCD Type 1 cho dim_customer và nạp mới các Dim còn lại)

-- Bước 3: Nạp dữ liệu vào các bảng Fact (fact_sales, fact_orders) sau khi có đủ Surrogate Keys
PRINT N'>>> BƯỚC 3: Nạp dữ liệu vào Fact Tables (fact_sales, fact_orders)...';
SELECT COUNT(*) AS fact_sales_count FROM dbo.fact_sales;
SELECT COUNT(*) AS fact_orders_count FROM dbo.fact_orders;


-- ------------------------------------------------------------------------------------------
-- Câu 4.7.2:
-- Bổ sung các bài kiểm tra toàn vẹn tự động sau khi nạp kho (DW Quality Assertions):
-- Kiểm tra không có bất kỳ dòng Fact nào mang khóa ngoại bị NULL (phải trỏ tới khóa hợp lệ hoặc khóa -1).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.7.2 TẠI ĐÂY:

SELECT 
    'fact_sales' AS table_name,
    SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END) AS null_customer_keys,
    SUM(CASE WHEN product_key IS NULL THEN 1 ELSE 0 END) AS null_product_keys,
    SUM(CASE WHEN location_key IS NULL THEN 1 ELSE 0 END) AS null_location_keys,
    SUM(CASE WHEN purchase_date_key IS NULL THEN 1 ELSE 0 END) AS null_date_keys,
    CASE 
        WHEN SUM(CASE WHEN customer_key IS NULL OR product_key IS NULL OR location_key IS NULL OR purchase_date_key IS NULL THEN 1 ELSE 0 END) = 0 
             THEN 'PASS' 
        ELSE 'FAIL' 
    END AS assertion_status
FROM dbo.fact_sales
UNION ALL
SELECT 
    'fact_orders' AS table_name,
    SUM(CASE WHEN customer_key IS NULL THEN 1 ELSE 0 END),
    0 AS null_product_keys,
    SUM(CASE WHEN location_key IS NULL THEN 1 ELSE 0 END),
    SUM(CASE WHEN purchase_date_key IS NULL THEN 1 ELSE 0 END),
    CASE 
        WHEN SUM(CASE WHEN customer_key IS NULL OR location_key IS NULL OR purchase_date_key IS NULL THEN 1 ELSE 0 END) = 0 
             THEN 'PASS' 
        ELSE 'FAIL' 
    END AS assertion_status
FROM dbo.fact_orders;


-- ------------------------------------------------------------------------------------------
-- Câu 4.7.3:
-- Đóng gói toàn bộ quy trình xây dựng Data Warehouse thành một Master Stored Procedure:
-- `usp_Build_Olist_DataWarehouse`:
-- Tự động vận hành toàn bộ từ Staging đến Fact, ghi nhận lịch sử thực thi và số bản ghi của từng bảng vào bảng nhật ký.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.7.3 TẠI ĐÂY:

IF OBJECT_ID('dbo.dw_execution_log', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.dw_execution_log (
        log_id INT IDENTITY(1,1) PRIMARY KEY,
        step_name NVARCHAR(100) NOT NULL,
        target_table NVARCHAR(100) NOT NULL,
        rows_affected INT DEFAULT 0,
        status NVARCHAR(20) NOT NULL,
        error_message NVARCHAR(MAX) NULL,
        executed_at DATETIME DEFAULT GETDATE()
    );
END;
GO

CREATE OR ALTER PROCEDURE dbo.usp_Build_Olist_DataWarehouse
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @rows INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Cập nhật Dimension Customer (SCD Type 1)
        MERGE INTO dbo.dim_customer AS tgt
        USING stg.stg_customers AS src
            ON tgt.customer_unique_id = src.customer_unique_id
        WHEN MATCHED AND tgt.customer_key <> -1 AND (
            ISNULL(tgt.customer_city, '') <> ISNULL(src.customer_city, '')
            OR ISNULL(tgt.customer_state, '') <> ISNULL(src.customer_state, '')
            OR ISNULL(tgt.customer_zip_code_prefix, '') <> ISNULL(src.customer_zip_code_prefix, '')
        ) THEN
            UPDATE SET 
                tgt.customer_city = src.customer_city,
                tgt.customer_state = src.customer_state,
                tgt.customer_zip_code_prefix = src.customer_zip_code_prefix,
                tgt.updated_at = GETDATE()
        WHEN NOT MATCHED BY TARGET THEN
            INSERT (customer_unique_id, customer_city, customer_state, customer_zip_code_prefix)
            VALUES (src.customer_unique_id, src.customer_city, src.customer_state, src.customer_zip_code_prefix);

        SET @rows = @@ROWCOUNT;
        INSERT INTO dbo.dw_execution_log (step_name, target_table, rows_affected, status)
        VALUES (N'Load Dimension', 'dbo.dim_customer', @rows, 'SUCCESS');

        -- 2. Nạp bổ sung Dimension Product
        INSERT INTO dbo.dim_product (
            product_id, product_category_name, product_weight_kg, weight_tier, product_volume_m3, volume_tier
        )
        SELECT 
            p.product_id, p.product_category_name, p.product_weight_kg,
            CASE WHEN p.product_weight_kg <= 0 THEN 'Unknown' WHEN p.product_weight_kg < 1.0 THEN 'Light' WHEN p.product_weight_kg <= 5.0 THEN 'Medium' ELSE 'Heavy' END,
            p.product_volume_m3,
            CASE WHEN p.product_volume_m3 <= 0 THEN 'Unknown' WHEN p.product_volume_m3 < 0.01 THEN 'Small' WHEN p.product_volume_m3 <= 0.05 THEN 'Medium' ELSE 'Bulky' END
        FROM stg.stg_products p
        WHERE NOT EXISTS (SELECT 1 FROM dbo.dim_product tgt WHERE tgt.product_id = p.product_id);

        SET @rows = @@ROWCOUNT;
        INSERT INTO dbo.dw_execution_log (step_name, target_table, rows_affected, status)
        VALUES (N'Load Dimension', 'dbo.dim_product', @rows, 'SUCCESS');

        -- 3. Nạp Fact Sales (Incremental / Idempotent)
        INSERT INTO dbo.fact_sales (
            order_id, order_item_id, customer_key, product_key, location_key, purchase_date_key,
            quantity, unit_price, freight_value, total_item_amount
        )
        SELECT 
            oi.order_id, oi.order_item_id,
            COALESCE(dc.customer_key, -1), COALESCE(dp.product_key, -1),
            COALESCE(dl.location_key, -1), COALESCE(dd.date_key, -1),
            1, CAST(COALESCE(oi.price, 0) AS DECIMAL(18,2)),
            CAST(COALESCE(oi.freight_value, 0) AS DECIMAL(18,2)),
            CAST(COALESCE(oi.price, 0) + COALESCE(oi.freight_value, 0) AS DECIMAL(18,2))
        FROM dbo.olist_order_items_dataset oi
        INNER JOIN stg.stg_orders o ON oi.order_id = o.order_id
        LEFT JOIN dbo.olist_customers_dataset raw_c ON o.customer_id = raw_c.customer_id
        LEFT JOIN dbo.dim_customer dc ON raw_c.customer_unique_id = dc.customer_unique_id
        LEFT JOIN dbo.dim_product dp ON oi.product_id = dp.product_id
        LEFT JOIN dbo.dim_location dl ON RIGHT(CONCAT('00000', raw_c.customer_zip_code_prefix), 5) = dl.zip_code_prefix
        LEFT JOIN dbo.dim_date dd ON CAST(o.order_purchase_timestamp AS DATE) = dd.full_date
        WHERE NOT EXISTS (SELECT 1 FROM dbo.fact_sales fs WHERE fs.order_id = oi.order_id AND fs.order_item_id = oi.order_item_id);

        SET @rows = @@ROWCOUNT;
        INSERT INTO dbo.dw_execution_log (step_name, target_table, rows_affected, status)
        VALUES (N'Load Fact', 'dbo.fact_sales', @rows, 'SUCCESS');

        COMMIT TRANSACTION;
        PRINT N'=== DATA WAREHOUSE BUILD COMPLETED SUCCESSFULLY ===';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        INSERT INTO dbo.dw_execution_log (step_name, target_table, rows_affected, status, error_message)
        VALUES (N'Master Pipeline', 'ALL', 0, 'FAILED', ERROR_MESSAGE());
        THROW;
    END CATCH;
END;
GO

-- Chạy Master Procedure và kiểm tra log:
EXEC dbo.usp_Build_Olist_DataWarehouse;
SELECT * FROM dbo.dw_execution_log ORDER BY log_id DESC;



