-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 1: CÁC NỀN TẢNG XỬ LÝ VÀ PHÂN TÍCH DỮ LIỆU CỐT LÕI (CORE DATA PIPELINE FOUNDATIONS)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 2: DATA TRANSFORMATION (BIẾN ĐỔI DỮ LIỆU)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 1]: STRING TRANSFORMATION & CLEANING (CHUẨN HÓA DỮ LIỆU CHUỖI)
-- ------------------------------------------------------------------------------------------

-- Câu 2.1.1:
-- Dữ liệu địa chỉ khách hàng nhập tự do từ nguồn thường bị lẫn khoảng trắng thừa hai đầu,
-- ký tự gạch nối/gạch dưới và viết hoa thường lộn xộn.
-- Hãy viết truy vấn chuẩn hóa địa bàn của khách hàng:
-- Tên thành phố và mã bang phải được đưa về dạng chữ in hoa đồng nhất, không còn khoảng trắng thừa,
-- và chuyển các ký tự phân cách lạ ('-', '_') về khoảng trắng chuẩn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.1 TẠI ĐÂY:

SELECT 
    customer_id,
    customer_unique_id,
    customer_city AS raw_city,
    UPPER(TRIM(REPLACE(REPLACE(customer_city, '-', ' '), '_', ' '))) AS cleaned_customer_city,
    customer_state AS raw_state,
    UPPER(TRIM(REPLACE(REPLACE(customer_state, '-', ' '), '_', ' '))) AS cleaned_customer_state
FROM dbo.olist_customers_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.1.2:
-- Mã bưu chính (Zip/Postal Code) ở hệ thống nguồn đang bị lưu dưới dạng số nguyên,
-- khiến cho các mã bắt đầu bằng số 0 bị mất chữ số đầu.
-- Hãy chuẩn hóa toàn bộ mã bưu chính về chuỗi ký tự có độ dài cố định đúng 5 chữ số
-- (tự động bổ sung các chữ số 0 phía trước nếu độ dài chưa đủ 5 ký tự).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.2 TẠI ĐÂY:

SELECT 
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix AS raw_zip_code,
    RIGHT(CONCAT('00000', customer_zip_code_prefix), 5) AS standardized_zip_code_prefix
FROM dbo.olist_customers_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.1.3:
-- Tạo một trường địa chỉ hợp nhất (Full Address) cho khách hàng bao gồm:
-- Tên thành phố, Mã bang và Mã bưu chính đã chuẩn hóa.
-- Đảm bảo câu truy vấn an toàn, không bị biến toàn bộ kết quả thành NULL nếu có bất kỳ thành phần nào bị thiếu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.1.3 TẠI ĐÂY:

SELECT 
    customer_id,
    customer_unique_id,
    CONCAT_WS(' - ', 
        NULLIF(UPPER(TRIM(REPLACE(REPLACE(customer_city, '-', ' '), '_', ' '))), ''),
        NULLIF(UPPER(TRIM(customer_state)), ''),
        RIGHT(CONCAT('00000', customer_zip_code_prefix), 5)
    ) AS full_address
FROM dbo.olist_customers_dataset;

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 2]: DATE & TIME STANDARDIZATION (CHUẨN HÓA NGÀY THÁNG & THỜI GIAN)
-- ------------------------------------------------------------------------------------------

-- Câu 2.2.1:
-- Từ mốc thời gian đặt hàng (timestamp chi tiết giờ phút giây), hãy tạo 3 trường thời gian chuẩn
-- để phục vụ cho các tầng phân tích khác nhau:
-- 1. Ngày mua hàng chỉ giữ lại phần ngày (chuẩn ISO YYYY-MM-DD).
-- 2. Khóa ngày dạng số nguyên (DateKey dạng YYYYMMDD) để liên kết với bảng DimDate.
-- 3. Chuỗi ngày hiển thị thân thiện theo chuẩn ngày/tháng/năm (DD/MM/YYYY).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.1 TẠI ĐÂY:

SELECT 
    order_id,
    order_purchase_timestamp,
    CAST(order_purchase_timestamp AS DATE) AS purchase_date_iso,
    CAST(CONVERT(VARCHAR(8), order_purchase_timestamp, 112) AS INT) AS date_key,
    CONVERT(VARCHAR(10), order_purchase_timestamp, 103) AS purchase_date_dmy
FROM dbo.olist_orders_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.2.2:
-- Từ ngày đặt đơn, hãy phân tách và xây dựng các thuộc tính phân cấp thời gian cho bảng đơn hàng:
-- Năm đặt mua, Quý trong năm, Tháng trong năm, Chuỗi Năm-Tháng ('YYYY-MM'), và Tên thứ trong tuần.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.2 TẠI ĐÂY:

SELECT 
    order_id,
    order_purchase_timestamp,
    YEAR(order_purchase_timestamp) AS order_year,
    DATEPART(QUARTER, order_purchase_timestamp) AS order_quarter,
    MONTH(order_purchase_timestamp) AS order_month,
    FORMAT(order_purchase_timestamp, 'yyyy-MM') AS year_month,
    DATENAME(WEEKDAY, order_purchase_timestamp) AS day_of_week_name
FROM dbo.olist_orders_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.2.3:
-- Khi ingest các tệp dữ liệu thô, cột ngày tháng thường chứa các chuỗi lỗi hoặc không hợp lệ
-- (ví dụ: '2018-02-31', 'Unknown', 'N/A').
-- Hãy viết truy vấn chuyển đổi dữ liệu chuỗi ngày sang kiểu thời gian một cách an toàn:
-- Dòng hợp lệ thì chuyển đổi thành công, dòng bị lỗi format thì gán giá trị NULL và đánh dấu cờ cảnh báo lỗi,
-- tuyệt đối không làm dừng hay sập câu truy vấn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.2.3 TẠI ĐÂY:

SELECT 
    order_id,
    CAST(order_delivered_customer_date AS VARCHAR(50)) AS raw_date_text,
    TRY_CONVERT(DATETIME, order_delivered_customer_date) AS converted_datetime,
    CASE 
        WHEN order_delivered_customer_date IS NULL THEN 'Missing'
        WHEN TRY_CONVERT(DATETIME, order_delivered_customer_date) IS NULL THEN 'Invalid Format / Error'
        ELSE 'Valid'
    END AS date_quality_flag
FROM dbo.olist_orders_dataset;

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 3]: NUMBER STANDARDIZATION & ÉP KIỂU AN TOÀN
-- ------------------------------------------------------------------------------------------

-- Câu 2.3.1:
-- Đơn giá mặt hàng và phí vận chuyển ở nguồn có thể lưu dưới kiểu dữ liệu gần đúng.
-- Hãy chuẩn hóa các trường này về kiểu dữ liệu số thập phân tài chính có độ chính xác cố định (2 chữ số thập phân),
-- đồng thời tính toán tổng giá trị thanh toán của từng mặt hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.1 TẠI ĐÂY:

SELECT 
    order_id,
    order_item_id,
    product_id,
    seller_id,
    CAST(ROUND(price, 2) AS DECIMAL(12, 2)) AS standardized_price,
    CAST(ROUND(freight_value, 2) AS DECIMAL(12, 2)) AS standardized_freight_value,
    CAST(ROUND(price + freight_value, 2) AS DECIMAL(12, 2)) AS total_item_value
FROM dbo.olist_order_items_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.3.2:
-- Bảng danh mục sản phẩm đang lưu trữ trọng lượng theo gram và các kích thước theo cm.
-- Đội ngũ Logistics yêu cầu chuyển đổi đơn vị đo lường:
-- - Khối lượng quy đổi sang Kilogram (làm tròn 2 chữ số thập phân).
-- - Thể tích sản phẩm quy đổi sang Mét khối (m3) (làm tròn 4 chữ số thập phân).
-- Xử lý an toàn các sản phẩm bị thiếu thông tin kích thước.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.2 TẠI ĐÂY:

SELECT 
    product_id,
    product_category_name,
    product_weight_g,
    CAST(ROUND(product_weight_g / 1000.0, 2) AS DECIMAL(10, 2)) AS weight_kg,
    product_length_cm,
    product_height_cm,
    product_width_cm,
    CAST(ROUND((product_length_cm * 1.0 * product_height_cm * product_width_cm) / 1000000.0, 4) AS DECIMAL(12, 4)) AS volume_m3,
    CASE 
        WHEN product_weight_g IS NULL THEN 'Missing Weight'
        WHEN product_length_cm IS NULL OR product_height_cm IS NULL OR product_width_cm IS NULL THEN 'Missing Dimensions'
        ELSE 'Valid'
    END AS dimension_quality_flag
FROM dbo.olist_products_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.3.3:
-- Kiểm tra và chuẩn hóa dữ liệu thanh toán:
-- Ép kiểu an toàn cho số tiền thanh toán, xử lý các trường hợp số tiền bị âm hoặc NULL về 0.00,
-- và bổ sung một trường cờ cảnh báo đối với các bản ghi có số tiền thanh toán bất thường.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.3.3 TẠI ĐÂY:

SELECT 
    order_id,
    payment_sequential,
    payment_type,
    payment_installments,
    payment_value AS raw_payment_value,
    CASE 
        WHEN payment_value IS NULL OR payment_value < 0 THEN 0.00
        ELSE CAST(ROUND(payment_value, 2) AS DECIMAL(12, 2))
    END AS cleaned_payment_value,
    CASE 
        WHEN payment_value IS NULL THEN 'Missing Value'
        WHEN payment_value < 0 THEN 'Negative Value'
        WHEN payment_value = 0 THEN 'Zero Value'
        WHEN payment_value > 5000 THEN 'Extremely High Value'
        ELSE 'Normal'
    END AS payment_warning_flag
FROM dbo.olist_order_payments_dataset;

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 4]: CHIẾN LƯỢC XỬ LÝ DỮ LIỆU THIẾU (NULL STRATEGY)
-- ------------------------------------------------------------------------------------------

-- Câu 2.4.1:
-- Một đơn hàng có nhiều mốc trạng thái thời gian khác nhau (ngày giao khách, ngày bàn giao vận chuyển,
-- ngày duyệt đơn, ngày đặt hàng).
-- Hãy xác định "mốc thời gian hoạt động gần nhất" của từng đơn hàng theo thứ tự ưu tiên giảm dần
-- của tiến trình giao dịch (nếu mốc sau chưa có thì lấy mốc trước đó).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.1 TẠI ĐÂY:

SELECT 
    order_id,
    order_status,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    COALESCE(
        order_delivered_customer_date,
        order_delivered_carrier_date,
        order_approved_at,
        order_purchase_timestamp
    ) AS latest_activity_timestamp,
    CASE 
        WHEN order_delivered_customer_date IS NOT NULL THEN 'Delivered Customer'
        WHEN order_delivered_carrier_date IS NOT NULL THEN 'Delivered Carrier'
        WHEN order_approved_at IS NOT NULL THEN 'Approved'
        ELSE 'Purchased'
    END AS latest_active_milestone
FROM dbo.olist_orders_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.4.2:
-- 1. Tính toán tỷ trọng tiền vận chuyển so với đơn giá sản phẩm, đảm bảo câu lệnh không bị lỗi
--    ngay cả khi có sản phẩm mang giá trị bằng 0.
-- 2. Chuẩn hóa tiêu đề đánh giá của khách hàng: nếu tiêu đề chỉ chứa khoảng trắng rỗng thì
--    chuyển thành giá trị NULL đồng nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.2 TẠI ĐÂY:

-- 1. Tỷ trọng tiền vận chuyển so với đơn giá (an toàn khi đơn giá = 0 bằng NULLIF)
SELECT 
    order_id,
    order_item_id,
    price,
    freight_value,
    ROUND((freight_value * 100.0) / NULLIF(price, 0), 2) AS freight_to_price_ratio_pct
FROM dbo.olist_order_items_dataset;

-- 2. Chuẩn hóa tiêu đề đánh giá: chuỗi rỗng / chỉ chứa khoảng trắng thành NULL
SELECT 
    review_id,
    order_id,
    review_score,
    review_comment_title AS raw_title,
    NULLIF(TRIM(review_comment_title), '') AS cleaned_review_title
FROM dbo.olist_order_reviews_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.4.3:
-- Khi chuẩn bị dữ liệu đánh giá (reviews) phục vụ Dashboard báo cáo, không được để xuất hiện
-- giá trị NULL gây hiểu nhầm cho người xem.
-- Hãy thay thế các tiêu đề và nội dung đánh giá bị thiếu bằng các thông báo mặc định có ý nghĩa,
-- đồng thời tạo thêm một cột đánh dấu khách hàng có để lại nhận xét bằng chữ hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.4.3 TẠI ĐÂY:

SELECT 
    review_id,
    order_id,
    review_score,
    COALESCE(NULLIF(TRIM(review_comment_title), ''), N'Không có tiêu đề') AS display_review_title,
    COALESCE(NULLIF(TRIM(review_comment_message), ''), N'Không có nhận xét chi tiết') AS display_review_message,
    CASE 
        WHEN NULLIF(TRIM(review_comment_title), '') IS NOT NULL 
          OR NULLIF(TRIM(review_comment_message), '') IS NOT NULL 
        THEN 1 
        ELSE 0 
    END AS has_text_feedback
FROM dbo.olist_order_reviews_dataset;

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 5]: PHÂN LOẠI & ÁNH XẠ NGHIỆP VỤ (CATEGORIZATION & BINNING)
-- ------------------------------------------------------------------------------------------

-- Câu 2.5.1:
-- Tính tổng chi tiêu của từng đơn hàng và phân loại các đơn hàng thành 4 phân khúc giá trị:
-- Dưới 50: 'Low Value', từ 50 đến dưới 200: 'Medium Value', từ 200 đến dưới 1000: 'High Value',
-- và từ 1000 trở lên: 'VIP Value'.
-- Đưa ra thống kê số lượng đơn và tổng doanh thu thu được theo từng phân khúc.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.1 TẠI ĐÂY:

WITH order_spending AS (
    SELECT 
        order_id,
        SUM(payment_value) AS order_total_value
    FROM dbo.olist_order_payments_dataset
    GROUP BY order_id
),
order_segments AS (
    SELECT 
        order_id,
        order_total_value,
        CASE 
            WHEN order_total_value < 50 THEN 'Low Value'
            WHEN order_total_value >= 50 AND order_total_value < 200 THEN 'Medium Value'
            WHEN order_total_value >= 200 AND order_total_value < 1000 THEN 'High Value'
            ELSE 'VIP Value'
        END AS value_segment,
        CASE 
            WHEN order_total_value < 50 THEN 1
            WHEN order_total_value >= 50 AND order_total_value < 200 THEN 2
            WHEN order_total_value >= 200 AND order_total_value < 1000 THEN 3
            ELSE 4
        END AS segment_order
    FROM order_spending
)
SELECT 
    value_segment,
    COUNT(order_id) AS total_orders,
    ROUND(SUM(order_total_value), 2) AS total_revenue,
    ROUND(AVG(order_total_value), 2) AS avg_order_value
FROM order_segments
GROUP BY value_segment, segment_order
ORDER BY segment_order;

-- ------------------------------------------------------------------------------------------
-- Câu 2.5.2:
-- Chuyển đổi toàn bộ mã trạng thái đơn hàng kỹ thuật tiếng Anh sang tên gọi trạng thái
-- nghiệp vụ tiếng Việt chuẩn hóa, gom các trạng thái trung gian về nhóm 'Đang xử lý đơn'.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.2 TẠI ĐÂY:

SELECT 
    order_id,
    order_status AS raw_status,
    CASE 
        WHEN order_status = 'delivered' THEN N'Giao hàng thành công'
        WHEN order_status = 'shipped' THEN N'Đang vận chuyển'
        WHEN order_status IN ('invoiced', 'processing', 'created', 'approved') THEN N'Đang xử lý đơn'
        WHEN order_status = 'canceled' THEN N'Đã hủy đơn'
        WHEN order_status = 'unavailable' THEN N'Không khả dụng'
        ELSE N'Trạng thái khác'
    END AS localized_order_status
FROM dbo.olist_orders_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.5.3:
-- Xây dựng chỉ số đánh giá cam kết dịch vụ giao hàng (SLA):
-- So sánh giữa ngày khách hàng thực tế nhận được hàng và ngày giao dự kiến ban đầu để phân loại:
-- Đơn giao đúng/sớm hạn, Đơn giao trễ hạn, hoặc Đơn đã quá hạn dự kiến nhưng vẫn chưa nhận được.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.5.3 TẠI ĐÂY:

SELECT 
    order_id,
    order_status,
    order_delivered_customer_date,
    order_estimated_delivery_date,
    CASE 
        WHEN order_delivered_customer_date IS NOT NULL 
             AND CAST(order_delivered_customer_date AS DATE) <= CAST(order_estimated_delivery_date AS DATE) 
            THEN N'Đơn giao đúng/sớm hạn'
        WHEN order_delivered_customer_date IS NOT NULL 
             AND CAST(order_delivered_customer_date AS DATE) > CAST(order_estimated_delivery_date AS DATE) 
            THEN N'Đơn giao trễ hạn'
        WHEN order_delivered_customer_date IS NULL 
             AND order_status NOT IN ('canceled', 'unavailable')
             AND CAST(order_estimated_delivery_date AS DATE) < CAST(GETDATE() AS DATE) 
            THEN N'Đã quá hạn dự kiến nhưng chưa nhận được'
        WHEN order_status IN ('canceled', 'unavailable') 
            THEN N'Đơn đã bị hủy / Không khả dụng'
        ELSE N'Đang giao trong hạn dự kiến'
    END AS sla_delivery_status
FROM dbo.olist_orders_dataset;

-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 6]: DERIVE METRICS & CHỈ SỐ VÒNG ĐỜI ĐƠN HÀNG
-- ------------------------------------------------------------------------------------------

-- Câu 2.6.1:
-- Đội Vận hành cần theo dõi tốc độ xử lý qua từng chặng của đơn hàng.
-- Hãy tính toán:
-- - Số giờ từ lúc khách bấm đặt mua đến lúc đơn hàng được duyệt thanh toán.
-- - Số ngày từ lúc đơn duyệt đến khi bàn giao cho đơn vị vận chuyển.
-- - Số ngày vận chuyển từ lúc hãng tàu nhận hàng đến khi khách nhận thành công.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.1 TẠI ĐÂY:

SELECT 
    order_id,
    order_purchase_timestamp,
    order_approved_at,
    order_delivered_carrier_date,
    order_delivered_customer_date,
    DATEDIFF(hour, order_purchase_timestamp, order_approved_at) AS hours_purchase_to_approval,
    DATEDIFF(day, order_approved_at, order_delivered_carrier_date) AS days_approval_to_carrier,
    DATEDIFF(day, order_delivered_carrier_date, order_delivered_customer_date) AS days_carrier_to_delivery
FROM dbo.olist_orders_dataset
WHERE order_status = 'delivered';

-- ------------------------------------------------------------------------------------------
-- Câu 2.6.2:
-- Phí vận chuyển quá cao ảnh hưởng lớn đến quyết định mua sắm của khách hàng.
-- Hãy tính tỷ lệ phần trăm tiền cước so với tổng số tiền phải trả của mỗi mặt hàng,
-- và phân loại mức độ gánh nặng cước phí thành 3 cấp độ: Cước hợp lý (< 15%), Trung bình (15% - 30%), và Rất cao (> 30%).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.2 TẠI ĐÂY:

SELECT 
    order_id,
    order_item_id,
    price,
    freight_value,
    ROUND(price + freight_value, 2) AS total_item_cost,
    ROUND((freight_value * 100.0) / NULLIF(price + freight_value, 0), 2) AS freight_percentage,
    CASE 
        WHEN (freight_value * 100.0) / NULLIF(price + freight_value, 0) < 15.0 THEN N'Cước hợp lý'
        WHEN (freight_value * 100.0) / NULLIF(price + freight_value, 0) <= 30.0 THEN N'Trung bình'
        ELSE N'Rất cao'
    END AS freight_burden_level
FROM dbo.olist_order_items_dataset;

-- ------------------------------------------------------------------------------------------
-- Câu 2.6.3:
-- Dựa trên điểm số đánh giá từ 1 đến 5 sao của khách hàng, hãy phân loại cảm nhận của khách
-- thành 4 nhóm cảm xúc (Sentiment) từ bất mãn đến rất hài lòng.
-- Đồng thời tính toán thời gian (số ngày) mà nhân viên hỗ trợ phản hồi lại đánh giá của khách hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.6.3 TẠI ĐÂY:

SELECT 
    review_id,
    order_id,
    review_score,
    CASE 
        WHEN review_score IN (1, 2) THEN N'Bất mãn'
        WHEN review_score = 3 THEN N'Trung lập'
        WHEN review_score = 4 THEN N'Hài lòng'
        WHEN review_score = 5 THEN N'Rất hài lòng'
        ELSE N'Chưa đánh giá'
    END AS sentiment_group,
    review_creation_date,
    review_answer_timestamp,
    DATEDIFF(day, review_creation_date, review_answer_timestamp) AS response_days
FROM dbo.olist_order_reviews_dataset;





-- ------------------------------------------------------------------------------------------
-- [P2 - NGÀY 7]: TỔNG HỢP KIẾN TRÚC TRANSFORMATION PIPELINE
-- ------------------------------------------------------------------------------------------

-- Câu 2.7.1:
-- Viết một truy vấn biến đổi dữ liệu đơn hàng phức tạp áp dụng đúng mô hình kiến trúc phân tầng:
-- Bắt đầu từ tập dữ liệu thô (Raw), qua bước làm sạch (Clean), bước chuẩn hóa định dạng (Standardize),
-- và bước tính toán chỉ số nghiệp vụ (Derive).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.1 TẠI ĐÂY:

with raw_data as (
    select 
        orders.order_id,
        orders.customer_id,
        orders.order_status,
        orders.order_purchase_timestamp,
        orders.order_approved_at,
        orders.order_delivered_carrier_date,
        orders.order_delivered_customer_date,
        orders.order_estimated_delivery_date,
        payments.payment_type,
        payments.payment_installments,
        payments.payment_value,
        items.product_id,
        items.seller_id,
        items.price,
        items.freight_value,
        items.shipping_limit_date
    from dbo.olist_orders_dataset orders
    inner join dbo.olist_order_payments_dataset payments on orders.order_id = payments.order_id
    inner join dbo.olist_order_items_dataset items on orders.order_id = items.order_id
),
clean_data as (
    select 
        rd.order_id,
        rd.customer_id,
        rd.product_id,
        rd.seller_id,
    
        coalesce(rd.order_status,'Unknown') as order_status,
        rd.order_purchase_timestamp,
        rd.order_approved_at,

        case 
            when rd.order_status = 'canceled' then NULL 
            else rd.order_delivered_carrier_date 
        end as order_delivered_carrier_date,
 
        case 
            when rd.order_status = 'canceled' then NULL
            else rd.order_delivered_customer_date 
        end as order_delivered_customer_date,

        case 
            when rd.order_status = 'canceled' then NULL
            else rd.order_estimated_delivery_date 
        end as order_estimated_delivery_date,

        coalesce(rd.payment_type, 'Unknown') as payment_type,
        coalesce(rd.payment_installments, 1) as payment_installments,
        coalesce(rd.payment_value, 0) as payment_value,
        coalesce(rd.price, 0) as price,
        coalesce(rd.freight_value, 0) as freight_value,
        rd.shipping_limit_date
    from raw_data rd 
    where 
        rd.order_id is not null
        and rd.customer_id is not null
        and rd.product_id is not null
        and rd.seller_id is not null
        and rd.order_purchase_timestamp is not null
),
standerlize_data as (
    select 
        cd.order_id,
        cd.customer_id,
        cd.product_id,
        cd.seller_id,
        cd.order_status,
        cast(cd.order_purchase_timestamp as datetime) as order_purchase_timestamp,
        day(cd.order_purchase_timestamp) as day,
        month(cd.order_purchase_timestamp) as month,
        datepart(quarter, cd.order_purchase_timestamp) as quarter,
        year(cd.order_purchase_timestamp) as year,
        datename(weekday, cd.order_purchase_timestamp) as weekday,
        format(cd.order_purchase_timestamp, 'MMMM') as month_name,
        cast(cd.order_approved_at as datetime) as order_approved_at,
        cast(cd.order_delivered_carrier_date as datetime) as order_delivered_carrier_date,
        cast(cd.order_delivered_customer_date as datetime) as order_delivered_customer_date,
        cast(cd.order_estimated_delivery_date as datetime) as order_estimated_delivery_date,
        cd.payment_type,
        cd.payment_installments,
        cast(cd.payment_value as decimal(18,2)) as payment_value,
        cast(cd.price as decimal(18,2)) as price,
        cast(cd.freight_value as decimal(18,2)) as freight_value,
        cast(cd.shipping_limit_date as datetime) as shipping_limit_date 
    from clean_data cd 
    where 
        cd.payment_value > 0
        and cd.price > 0
        and cd.freight_value > 0
        and cd.shipping_limit_date > cd.order_purchase_timestamp
)
select 
    sd.*,
    case 
        when sd.payment_installments = 1 then 'Payment 1 time'
        else 'Payment install'
    end as payment_type_name,
    datediff(day, sd.order_purchase_timestamp, sd.order_delivered_customer_date) as order_delivered_customer_day,
    round(sd.price + sd.freight_value, 2) as total_price
 from standerlize_data sd 


/*
==========================================================================================
2. NHẬN XÉT CHI TIẾT & CÁC LỖI CẦN SỬA TRONG QUERY TRÊN:
==========================================================================================
- [LỖI 1 - TẦNG RAW_DATA]: Bẫy nhân bản dòng (Cartesian Fan-Out) do JOIN 1-N và 1-M
  + Bảng orders nối đồng thời với payments (quan hệ 1 - N) và items (quan hệ 1 - M).
  + Nếu 1 đơn hàng có 2 hình thức thanh toán (voucher + thẻ) và 3 mặt hàng, phép JOIN sẽ sinh ra $2 \times 3 = 6$ dòng.
  + Hậu quả: price, freight_value và payment_value bị nhân đôi/nhân ba, làm thổi phồng doanh thu thực tế.
  + Khắc phục: Nếu bài toán yêu cầu tập dữ liệu bán hàng theo mặt hàng, nên tổng hợp trước bảng payments theo order_id hoặc chỉ lấy thông tin thanh toán tổng hợp.

- [LỖI 2 - TẦNG CLEAN_DATA]: Xử lý sai logic ngày dự kiến giao (order_estimated_delivery_date)
  + Bạn đặt NULL khi order_status = 'canceled'. Thực tế ngày dự kiến giao được hệ thống chốt ngay
    khi khách đặt đơn; kể cả bị hủy, mốc này vẫn cần giữ lại để phân tích (hủy trước hay sau ngày hẹn giao).
  + payment_type nên gán giá trị mặc định chuẩn Olist là 'not_defined' thay vì 'Unknown'.
- [LỖI 3 - TẦNG STANDARDIZE_DATA]: Lỗi nghiêm trọng làm mất đơn hàng Free Ship
  + Điều kiện: `cd.freight_value > 0` sẽ LOẠI BỎ HẾT toàn bộ các đơn hàng Miễn phí vận chuyển (freight_value = 0).
  + Cần sửa thành: `cd.freight_value >= 0`.

- [LỖI 4 - KIẾN TRÚC PHÂN TẦNG]: Lẫn lộn trách nhiệm giữa Clean và Standardize
  + Mệnh đề WHERE lọc dữ liệu vô lý (price > 0, payment_value > 0, shipping_limit_date > purchase_date)
    thuộc về trách nhiệm của tầng CLEAN_DATA (làm sạch dữ liệu bẩn).
  + Tầng STANDARDIZE_DATA chỉ nên làm nhiệm vụ ép kiểu (CAST), chuẩn hóa chữ (UPPER, TRIM) và bóc tách ngày.
  + Lỗi chính tả tên CTE: 'standerlize_data' nên sửa thành 'standardize_data'.

- [LỖI 5 - TẦNG DERIVE]: Chưa tách riêng CTE cho tầng Derive
  + Đề bài yêu cầu quy trình chuẩn 4 bước: Raw -> Clean -> Standardize -> Derive.
  + Bạn đang viết các trường tính toán (Derive) gộp chung ở câu SELECT cuối. Cần tách hẳn thành CTE
    `derive_data as (...)` để chuẩn hóa kiến trúc tái sử dụng.
==========================================================================================
*/
;with raw_data as (
    select 
        orders.order_id,
        orders.customer_id,
        orders.order_status,
        orders.order_purchase_timestamp,
        orders.order_approved_at,
        orders.order_delivered_carrier_date,
        orders.order_delivered_customer_date,
        orders.order_estimated_delivery_date,
        payments.payment_type,
        payments.payment_installments,
        payments.payment_value,
        items.product_id,
        items.seller_id,
        items.price,
        items.freight_value,
        items.shipping_limit_date
    from dbo.olist_orders_dataset orders
    inner join dbo.olist_order_payments_dataset payments on orders.order_id = payments.order_id
    inner join dbo.olist_order_items_dataset items on orders.order_id = items.order_id
),
-- TẦNG 1: LÀM SẠCH (Lọc khóa chính NULL, gán default hợp lệ, loại trừ dữ liệu sai logic)
clean_data as (
    select 
        rd.order_id,
        rd.customer_id,
        rd.product_id,
        rd.seller_id,
        coalesce(rd.order_status, 'unknown') as order_status,
        rd.order_purchase_timestamp,
        rd.order_approved_at,
        
        -- Đơn hủy thì không phát sinh giao hàng thực tế
        case 
            when rd.order_status = 'canceled' then null 
            else rd.order_delivered_carrier_date 
        end as order_delivered_carrier_date,
        case 
            when rd.order_status = 'canceled' then null 
            else rd.order_delivered_customer_date 
        end as order_delivered_customer_date,
        -- Giữ nguyên mốc dự kiến ban đầu để phân tích
        rd.order_estimated_delivery_date,
        coalesce(rd.payment_type, 'not_defined') as payment_type,
        coalesce(rd.payment_installments, 1) as payment_installments,
        coalesce(rd.payment_value, 0.0) as payment_value,
        coalesce(rd.price, 0.0) as price,
        coalesce(rd.freight_value, 0.0) as freight_value,
        rd.shipping_limit_date
from raw_data rd 
where 
        rd.order_id is not null
        and rd.customer_id is not null
        and rd.product_id is not null
        and rd.seller_id is not null
        and rd.order_purchase_timestamp is not null
        -- Chuyển toàn bộ điều kiện lọc tính hợp lệ về đúng tầng Clean:
        and rd.payment_value > 0
        and rd.price > 0
        and rd.freight_value >= 0  -- Đã sửa: >= 0 để bảo toàn các đơn Free Ship
        and (rd.shipping_limit_date is null or rd.shipping_limit_date >= rd.order_purchase_timestamp)
),
-- TẦNG 2: STANDARDIZE (CHUẨN HÓA ĐỊNH DẠNG)
-- Nhiệm vụ: Ép kiểu dữ liệu (CAST), chuẩn hóa chuỗi (TRIM, UPPER), phân rã thuộc tính ngày
-- ------------------------------------------------------------------------------------------
standardize_data as (
    select 
        cd.order_id,
        cd.customer_id,
        cd.product_id,
        cd.seller_id,
        
        -- Chuẩn hóa văn bản
        upper(trim(cd.order_status)) as order_status,
        lower(trim(cd.payment_type)) as payment_type,
        cd.payment_installments,
        -- Chuẩn hóa số thập phân tài chính
        cast(cd.payment_value as decimal(18, 2)) as payment_value,
        cast(cd.price as decimal(18, 2)) as price,
        cast(cd.freight_value as decimal(18, 2)) as freight_value,
        -- Chuẩn hóa mốc thời gian
        cast(cd.order_purchase_timestamp as datetime) as order_purchase_timestamp,
        cast(cd.order_approved_at as datetime) as order_approved_at,
        cast(cd.order_delivered_carrier_date as datetime) as order_delivered_carrier_date,
        cast(cd.order_delivered_customer_date as datetime) as order_delivered_customer_date,
        cast(cd.order_estimated_delivery_date as datetime) as order_estimated_delivery_date,
        cast(cd.shipping_limit_date as datetime) as shipping_limit_date,
        -- Phân cấp thời gian
        year(cd.order_purchase_timestamp) as order_year,
        datepart(quarter, cd.order_purchase_timestamp) as order_quarter,
        month(cd.order_purchase_timestamp) as order_month,
        day(cd.order_purchase_timestamp) as order_day,
        datename(weekday, cd.order_purchase_timestamp) as order_weekday,
        format(cd.order_purchase_timestamp, 'MMMM') as order_month_name
    from clean_data cd
),
-- TẦNG 3: TÍNH TOÁN NGHIỆP VỤ (Derive Metrics & Business Rules)
derive_data as (
    select 
        sd.*,
        -- 1. Tổng tiền mặt hàng (Giá + Cước)
        round(sd.price + sd.freight_value, 2) as total_item_cost,
        -- 2. Phân loại hình thức trả góp
        case 
            when sd.payment_installments = 1 then 'One-time Payment'
            else 'Installment Payment'
        end as payment_installment_type,
        -- 3. Số ngày vận chuyển thực tế từ lúc đặt đến khi khách nhận
        datediff(day, sd.order_purchase_timestamp, sd.order_delivered_customer_date) as delivery_duration_days,
        -- 4. Số ngày chặng đầu xử lý kho (từ lúc đặt đến khi giao cho shipper)
        datediff(day, sd.order_purchase_timestamp, sd.order_delivered_carrier_date) as fulfillment_duration_days,
        -- 5. Đánh giá cam kết dịch vụ giao hàng (SLA)
        case 
            when sd.order_delivered_customer_date is null then 'In Progress / Not Delivered'
            when sd.order_delivered_customer_date <= sd.order_estimated_delivery_date then 'On Time / Early'
            else 'Late Delivery'
        end as delivery_sla_status
    from standardize_data sd
)
select * 
from derive_data;


-- ------------------------------------------------------------------------------------------
-- Câu 2.7.2:
-- Kết hợp và biến đổi dữ liệu từ chi tiết đơn hàng và danh mục sản phẩm để tạo tập dữ liệu Fact sạch:
-- Chuẩn hóa đơn giá và tiền cước, quy đổi khối lượng sang kg, xử lý tên ngành hàng chưa xác định,
-- và loại trừ tất cả các bản ghi có giá trị bất hợp lý.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.2 TẠI ĐÂY:

;with clean_data as (
    select 
        items.order_item_id,
        items.order_id,
        products.product_id,
        products.product_category_name,
        items.freight_value,
        items.price,
        products.product_weight_g
    from dbo.olist_order_items_dataset items
    inner join dbo.olist_products_dataset products on items.product_id = products.product_id
    where products.product_id is not null
    and items.freight_value >= 0
    and items.price > 0
    and products.product_weight_g > 0
),
standerlize_data as (
    select 
        cd.order_item_id,
        cd.order_id,
        cd.product_id,
        coalesce(nullif(upper(trim(cd.product_category_name)), ''), 'UNKNOWN') as product_category_name,
        cast(cd.freight_value as decimal(18, 2)) as freight_value,
        cast(cd.price as decimal(18, 2)) as price,
        cast(cd.product_weight_g / 1000 as decimal(18, 3)) as product_weight_kg
    from clean_data cd
),
derive_data as (
    select 
        sd.order_item_id,
        sd.order_id,
        sd.product_id,
        sd.product_category_name,
        sd.freight_value,
        sd.price,
        sd.product_weight_kg,
        round(sd.price + sd.freight_value, 2) as total_item_cost
    from standerlize_data sd
)
select *
from derive_data;



-- ------------------------------------------------------------------------------------------
-- Câu 2.7.3:
-- Đóng gói toàn bộ logic làm sạch và biến đổi dữ liệu đơn hàng thành một View tầng Silver
-- chuẩn hóa để toàn bộ các đội ngũ phân tích có thể tái sử dụng dữ liệu sạch.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 2.7.3 TẠI ĐÂY:

create or alter view dbo.vw_silver_layer as  
with raw_data as (
    select 
        orders.order_id,
        orders.customer_id,
        orders.order_purchase_timestamp,
        orders.order_approved_at,
        orders.order_delivered_carrier_date,
        orders.order_delivered_customer_date,
        orders.order_estimated_delivery_date,
        orders.order_status
    from dbo.olist_orders_dataset orders
    where orders.order_id is not null
        and orders.customer_id is not null
        and orders.order_purchase_timestamp is not null
),
standerdize_data as (
    select 
        trim(rd.order_id) as order_id,
        trim(rd.customer_id) as customer_id,
        cast(rd.order_purchase_timestamp as datetime) as order_purchase_timestamp,
        cast(rd.order_approved_at as datetime) as order_approved_at,
        cast(rd.order_delivered_carrier_date as datetime) as order_delivered_carrier_date,
        cast(rd.order_delivered_customer_date as datetime) as order_delivered_customer_date,
        cast(rd.order_estimated_delivery_date as datetime) as order_estimated_delivery_date,
        upper(trim(rd.order_status)) as order_status
    from raw_data rd
),
derive_data as (
    select 
        sd.order_id,
        sd.customer_id,
        sd.order_purchase_timestamp,
        sd.order_approved_at,
        sd.order_delivered_carrier_date,
        sd.order_delivered_customer_date,
        sd.order_estimated_delivery_date,
        sd.order_status,
        -- Phân cấp thời gian
        year(sd.order_purchase_timestamp) as order_year,
        month(sd.order_purchase_timestamp) as order_month,
        datepart(quarter, sd.order_purchase_timestamp) as order_quarter,
        -- Chỉ số vận hành
        datediff(day, sd.order_purchase_timestamp, sd.order_delivered_customer_date) as delivery_duration_days,
        datediff(day, sd.order_purchase_timestamp, sd.order_delivered_carrier_date) as fulfillment_duration_days,
        -- Đánh giá SLA
        case 
            when sd.order_status in ('CANCELED', 'UNAVAILABLE') then 'Canceled / Unavailable'
            when sd.order_delivered_customer_date is null then 'In Progress'
            when sd.order_delivered_customer_date <= sd.order_estimated_delivery_date then 'On Time / Early'
            else 'Late Delivery'
        end as delivery_sla_status
    from standerdize_data sd
)
select * 
from derive_data;

select 
* 
from dbo.vw_order_details
