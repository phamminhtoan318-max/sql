-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 1: CÁC NỀN TẢNG XỬ LÝ VÀ PHÂN TÍCH DỮ LIỆU CỐT LÕI (CORE DATA PIPELINE FOUNDATIONS)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 4: AGGREGATION (TỔNG HỢP DỮ LIỆU)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 1]: THỐNG KÊ ĐƠN VỊ & PHỄU TRẠNG THÁI GIAO DỊCH (COUNT & GROUP BY)
-- ------------------------------------------------------------------------------------------

-- Câu 4.1.1:
-- Phân tích phễu giao dịch bán hàng (Order Status Funnel):
-- Thống kê tổng số lượng đơn hàng theo từng trạng thái giao dịch và tính tỷ lệ phần trăm
-- đóng góp của từng trạng thái so với tổng số lượng đơn hàng trên toàn sàn.
-- Sắp xếp theo số lượng đơn hàng giảm dần.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1.1 TẠI ĐÂY:

select 
    o.order_status,
    count(o.order_id) as total_orders,
    round((count(o.order_id)*100.0)/ nullif((select count(*) from dbo.olist_orders_dataset),0),2) as percentage
from dbo.olist_orders_dataset o
group by o.order_status
order by total_orders desc

-- ------------------------------------------------------------------------------------------
-- Câu 4.1.2:
-- Phân bổ mạng lưới khách hàng theo vùng địa lý:
-- Thống kê số lượng khách hàng duy nhất cư trú tại từng bang.
-- Liệt kê danh sách các bang theo thứ tự quy mô khách hàng từ lớn đến nhỏ.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1.2 TẠI ĐÂY:

select distinct 
    c.customer_state,
    count(c.customer_id) as total_customers
from dbo.olist_customers_dataset c
group by c.customer_state
order by total_customers desc


-- ------------------------------------------------------------------------------------------
-- Câu 4.1.3:
-- Phân tích cơ cấu thanh toán của người tiêu dùng:
-- Thống kê theo từng hình thức thanh toán: Tổng số lượt giao dịch, tổng giá trị tiền thanh toán thu về,
-- và tỷ trọng phần trăm về doanh số của từng hình thức thanh toán trên tổng dòng tiền toàn sàn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.1.3 TẠI ĐÂY:

select 
    p.payment_type,
    count(p.order_id) as total_transactions,
    sum(p.payment_value) as total_value,
    round((sum(p.payment_value)*100.0)/nullif((select sum(payment_value) from dbo.olist_order_payments_dataset),0),2) as percentage
from dbo.olist_order_payments_dataset p
group by p.payment_type
order by total_value desc


-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 2]: TÍNH TOÁN GIÁ TRỊ ĐƠN HÀNG TRUNG BÌNH (AOV - AVERAGE ORDER VALUE)
-- ------------------------------------------------------------------------------------------

-- Câu 4.2.1:
-- Chỉ số AOV (Average Order Value = Tổng doanh thu / Tổng số đơn) là thước đo sức khỏe quan trọng của sàn TMĐT.
-- Hãy tính toán chỉ số AOV cho toàn bộ hệ thống đối với các đơn hàng đã được giao thành công.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2.1 TẠI ĐÂY:

select 
    round(sum(p.payment_value)*1.0/nullif(count(distinct o.order_id),0),2) as AOV
from dbo.olist_orders_dataset o
inner join dbo.olist_order_payments_dataset p
on o.order_id = p.order_id
where o.order_status = 'delivered' 

-- ------------------------------------------------------------------------------------------
-- Câu 4.2.2:
-- So sánh sức mua và giá trị đơn hàng trung bình giữa các khu vực địa lý:
-- Tính chỉ số AOV của từng bang của khách hàng đối với các đơn hoàn tất giao dịch.
-- Tìm ra 5 bang có mức chi tiêu trung bình trên mỗi đơn hàng cao nhất cả nước.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2.2 TẠI ĐÂY:

SELECT TOP 5
    c.customer_state,
    COUNT(DISTINCT o.order_id) AS total_delivered_orders,
    ROUND(SUM(p.payment_value), 2) AS total_revenue,
    ROUND(SUM(p.payment_value) * 1.0 / NULLIF(COUNT(DISTINCT o.order_id), 0), 2) AS aov
FROM dbo.olist_orders_dataset o
INNER JOIN dbo.olist_customers_dataset c ON o.customer_id = c.customer_id
INNER JOIN dbo.olist_order_payments_dataset p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY aov DESC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.2.3:
-- Khảo sát tác động của chính sách trả góp đến quy mô đơn hàng:
-- Tính giá trị đơn hàng trung bình theo từng số lượng kỳ trả góp (từ 1 kỳ, 2 kỳ đến trên 10 kỳ).
-- Đưa ra kết luận liệu khách hàng chọn trả góp nhiều kỳ có chi tiêu cho đơn hàng cao hơn khách trả thẳng (1 kỳ) hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.2.3 TẠI ĐÂY:

WITH installment_bins AS (
    SELECT 
        order_id,
        payment_installments,
        payment_value,
        CASE 
            WHEN payment_installments = 1 THEN '01. Trả thẳng (1 kỳ)'
            WHEN payment_installments BETWEEN 2 AND 5 THEN '02. Ngắn hạn (2 - 5 kỳ)'
            WHEN payment_installments BETWEEN 6 AND 10 THEN '03. Trung hạn (6 - 10 kỳ)'
            ELSE '04. Dài hạn (> 10 kỳ)'
        END AS installment_segment
    FROM dbo.olist_order_payments_dataset
    WHERE payment_installments >= 1
)
SELECT 
    installment_segment,
    COUNT(DISTINCT order_id) AS total_orders,
    ROUND(SUM(payment_value), 2) AS total_payment_value,
    ROUND(SUM(payment_value) * 1.0 / NULLIF(COUNT(DISTINCT order_id), 0), 2) AS avg_order_value
FROM installment_bins
GROUP BY installment_segment
ORDER BY installment_segment ASC;

-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 3]: PHÂN TÍCH DOANH THU THEO CHUỖI THỜI GIAN (TIME-SERIES AGGREGATION)
-- ------------------------------------------------------------------------------------------

-- Câu 4.3.1:
-- Phân tích xu hướng doanh thu theo ngày (Daily Revenue Trend):
-- Tính tổng doanh thu tiền hàng, tổng phí vận chuyển thu được và số lượng đơn hàng phát sinh
-- theo từng ngày trong tháng 11/2017 (tháng diễn ra sự kiện mua sắm Black Friday).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3.1 TẠI ĐÂY:

SELECT 
    CAST(o.order_purchase_timestamp AS DATE) AS order_date,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_item_revenue,
    ROUND(SUM(oi.freight_value), 2) AS total_freight_value,
    ROUND(SUM(oi.price + oi.freight_value), 2) AS total_gross_value
FROM dbo.olist_orders_dataset o
INNER JOIN dbo.olist_order_items_dataset oi ON o.order_id = oi.order_id
WHERE o.order_purchase_timestamp >= '2017-11-01'
  AND o.order_purchase_timestamp < '2017-12-01'
  AND o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY CAST(o.order_purchase_timestamp AS DATE)
ORDER BY order_date ASC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.3.2:
-- Phân tích doanh thu tổng thể theo tháng (Monthly Revenue):
-- Thống kê tổng doanh thu bán hàng, tổng số lượng đơn hàng và số lượng khách hàng mua sắm
-- theo từng tháng trong toàn bộ lịch sử hoạt động của hệ thống, sắp xếp theo thứ tự thời gian.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3.2 TẠI ĐÂY:

SELECT 
    YEAR(o.order_purchase_timestamp) AS order_year,
    MONTH(o.order_purchase_timestamp) AS order_month,
    FORMAT(o.order_purchase_timestamp, 'yyyy-MM') AS year_month,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT c.customer_unique_id) AS total_customers,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM dbo.olist_orders_dataset o
INNER JOIN dbo.olist_order_items_dataset oi ON o.order_id = oi.order_id
INNER JOIN dbo.olist_customers_dataset c ON o.customer_id = c.customer_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY 
    YEAR(o.order_purchase_timestamp),
    MONTH(o.order_purchase_timestamp),
    FORMAT(o.order_purchase_timestamp, 'yyyy-MM')
ORDER BY order_year ASC, order_month ASC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.3.3:
-- Phân tích hành vi mua sắm theo các ngày trong tuần (Day-of-Week Pattern):
-- Tính tổng doanh thu và số lượng đơn hàng trung bình được đặt vào từng ngày trong tuần
-- (từ Thứ Hai đến Chủ Nhật) để xác định xem ngày nào trong tuần có lượng truy cập mua sắm đạt đỉnh.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.3.3 TẠI ĐÂY:

WITH daily_order_summary AS (
    SELECT 
        CAST(o.order_purchase_timestamp AS DATE) AS order_date,
        DATEPART(WEEKDAY, o.order_purchase_timestamp) AS weekday_number,
        DATENAME(WEEKDAY, o.order_purchase_timestamp) AS weekday_name,
        COUNT(DISTINCT o.order_id) AS orders_count,
        SUM(oi.price) AS daily_revenue
    FROM dbo.olist_orders_dataset o
    INNER JOIN dbo.olist_order_items_dataset oi ON o.order_id = oi.order_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY 
        CAST(o.order_purchase_timestamp AS DATE),
        DATEPART(WEEKDAY, o.order_purchase_timestamp),
        DATENAME(WEEKDAY, o.order_purchase_timestamp)
)
SELECT 
    weekday_name,
    COUNT(order_date) AS total_calendar_days,
    SUM(orders_count) AS total_orders,
    ROUND(AVG(orders_count * 1.0), 2) AS avg_orders_per_day,
    ROUND(SUM(daily_revenue), 2) AS total_revenue,
    ROUND(AVG(daily_revenue * 1.0), 2) AS avg_revenue_per_day
FROM daily_order_summary
GROUP BY weekday_number, weekday_name
ORDER BY weekday_number;

-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 4]: TỔNG HỢP THEO KHÁCH HÀNG & TẦN SUẤT MUA LẠI (CUSTOMER AGGREGATION)
-- ------------------------------------------------------------------------------------------

-- Câu 4.4.1:
-- Xếp hạng khách hàng VIP (Top Spenders):
-- Tính tổng số tiền đã chi tiêu và tổng số đơn hàng đã hoàn tất của từng khách hàng thực tế.
-- Trích xuất danh sách Top 10 khách hàng mang lại doanh thu lớn nhất cho sàn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.4.1 TẠI ĐÂY:

SELECT TOP 10
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS total_delivered_orders,
    ROUND(SUM(p.payment_value), 2) AS total_spending
FROM dbo.olist_customers_dataset c
INNER JOIN dbo.olist_orders_dataset o ON c.customer_id = o.customer_id
INNER JOIN dbo.olist_order_payments_dataset p ON o.order_id = p.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_unique_id
ORDER BY total_spending DESC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.4.2:
-- Phân tích tỷ lệ mua lại (Repeat Purchase Customer Behavior):
-- Gom nhóm theo từng khách hàng duy nhất để đếm tổng số lần đặt hàng của họ.
-- Sau đó, thống kê tổng số lượng khách hàng chỉ mua đúng 1 lần (One-time buyers)
-- so với tổng số lượng khách hàng quay lại mua từ 2 lần trở lên (Repeat buyers).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.4.2 TẠI ĐÂY:

WITH customer_orders AS (
    SELECT 
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM dbo.olist_customers_dataset c
    INNER JOIN dbo.olist_orders_dataset o ON c.customer_id = o.customer_id
    WHERE o.order_status NOT IN ('canceled', 'unavailable')
    GROUP BY c.customer_unique_id
)
SELECT 
    CASE 
        WHEN order_count = 1 THEN 'One-time buyers (1 đơn)'
        ELSE 'Repeat buyers (>= 2 đơn)'
    END AS customer_segment,
    COUNT(customer_unique_id) AS total_customers,
    ROUND(COUNT(customer_unique_id) * 100.0 / (SELECT COUNT(*) FROM customer_orders), 2) AS percentage
FROM customer_orders
GROUP BY 
    CASE 
        WHEN order_count = 1 THEN 'One-time buyers (1 đơn)'
        ELSE 'Repeat buyers (>= 2 đơn)'
    END
ORDER BY total_customers DESC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.4.3:
-- Đánh giá mức độ hài lòng của khách hàng trung thành:
-- Tính điểm đánh giá trung bình của các khách hàng đã từng thực hiện từ 2 đơn hàng trở lên.
-- Lọc ra danh sách những khách hàng mua nhiều đơn nhưng có điểm đánh giá trung bình dưới 3 sao
-- để chuyển giao cho bộ phận chăm sóc khách hàng khẩn cấp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.4.3 TẠI ĐÂY:

SELECT 
    c.customer_unique_id,
    COUNT(DISTINCT o.order_id) AS total_orders,
    ROUND(AVG(r.review_score * 1.0), 2) AS avg_review_score,
    COUNT(r.review_id) AS total_reviews
FROM dbo.olist_customers_dataset c
INNER JOIN dbo.olist_orders_dataset o ON c.customer_id = o.customer_id
INNER JOIN dbo.olist_order_reviews_dataset r ON o.order_id = r.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY c.customer_unique_id
HAVING COUNT(DISTINCT o.order_id) >= 2
   AND AVG(r.review_score * 1.0) < 3.0
ORDER BY avg_review_score ASC, total_orders DESC;

-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 5]: DOANH THU THEO NGÀNH HÀNG & HIỆU SUẤT NGƯỜI BÁN (PRODUCT & SELLER)
-- ------------------------------------------------------------------------------------------

-- Câu 4.5.1:
-- Báo cáo doanh thu theo ngành hàng (Category Performance):
-- Tính tổng doanh thu tiền hàng, tổng số lượng sản phẩm bán ra, và đơn giá trung bình của từng danh mục sản phẩm.
-- Sắp xếp theo danh mục có doanh thu cao nhất.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.5.1 TẠI ĐÂY:

SELECT 
    COALESCE(p.product_category_name, 'Unknown') AS product_category_name,
    COUNT(oi.order_item_id) AS total_items_sold,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(oi.price), 2) AS avg_item_price
FROM dbo.olist_order_items_dataset oi
INNER JOIN dbo.olist_products_dataset p ON oi.product_id = p.product_id
INNER JOIN dbo.olist_orders_dataset o ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY p.product_category_name
ORDER BY total_revenue DESC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.5.2:
-- Top Sản phẩm mang lại doanh thu chủ lực (Best-Selling Products):
-- Tìm 10 sản phẩm cụ thể có tổng giá trị bán ra cao nhất toàn sàn, kèm theo số lượng mặt hàng
-- đã bán và số đơn hàng có chứa sản phẩm đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.5.2 TẠI ĐÂY:

SELECT TOP 10
    oi.product_id,
    COALESCE(p.product_category_name, 'Unknown') AS product_category_name,
    COUNT(oi.order_item_id) AS total_quantity_sold,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.price), 2) AS total_revenue
FROM dbo.olist_order_items_dataset oi
INNER JOIN dbo.olist_products_dataset p ON oi.product_id = p.product_id
INNER JOIN dbo.olist_orders_dataset o ON oi.order_id = o.order_id
WHERE o.order_status NOT IN ('canceled', 'unavailable')
GROUP BY oi.product_id, p.product_category_name
ORDER BY total_revenue DESC;

-- ------------------------------------------------------------------------------------------
-- Câu 4.5.3:
-- Đánh giá năng lực của các đối tác bán hàng (Seller Performance):
-- Đối với từng người bán, hãy tính: Tổng doanh thu tạo ra, tổng số đơn hàng đã phục vụ,
-- và thời gian trung bình (tính bằng ngày) từ lúc đơn được duyệt cho đến khi bàn giao cho hãng vận chuyển.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.5.3 TẠI ĐÂY:

SELECT 
    s.seller_id,
    s.seller_city,
    s.seller_state,
    COUNT(DISTINCT o.order_id) AS total_orders_served,
    ROUND(SUM(oi.price), 2) AS total_revenue,
    ROUND(AVG(DATEDIFF(day, o.order_approved_at, o.order_delivered_carrier_date) * 1.0), 2) AS avg_handover_days
FROM dbo.olist_sellers_dataset s
INNER JOIN dbo.olist_order_items_dataset oi ON s.seller_id = oi.seller_id
INNER JOIN dbo.olist_orders_dataset o ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
  AND o.order_approved_at IS NOT NULL
  AND o.order_delivered_carrier_date IS NOT NULL
GROUP BY s.seller_id, s.seller_city, s.seller_state
ORDER BY total_revenue DESC;






-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 6]: LỌC NHÓM NÂNG CAO VỚI MỆNH ĐỀ HAVING (OUTLIERS & HIGH-VALUE FILTERING)
-- ------------------------------------------------------------------------------------------

-- Câu 4.6.1:
-- Lọc danh sách Người bán hàng xuất sắc:
-- Tìm tất cả các Người bán đạt tổng doanh thu bán hàng trên 20,000 và đã hoàn tất tối thiểu từ 50 đơn hàng trở lên.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.6.1 TẠI ĐÂY:

select 
    s.seller_id,
    sum(oi.price) as doanh_thu,
    count(oi.order_id) as so_don_hang
from dbo.olist_sellers_dataset s
left join dbo.olist_order_items_dataset oi
on s.seller_id = oi.seller_id
where oi.seller_id is not null
group by s.seller_id
having sum(oi.price) > 20000 and count(oi.order_id) > 50;



-- ------------------------------------------------------------------------------------------
-- Câu 4.6.2:
-- Kiểm soát chất lượng ngành hàng - Phát hiện ngành hàng có rủi ro hủy đơn cao:
-- Tìm các ngành hàng sản phẩm có quy mô bán ra từ 100 đơn trở lên, nhưng tỷ lệ các đơn hàng
-- bị rơi vào trạng thái hủy bỏ hoặc không khả dụng chiếm trên 3% tổng số đơn của ngành đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.6.2 TẠI ĐÂY:

SELECT 
    p.product_category_name,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(DISTINCT CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN o.order_id END) AS canceled_or_unavailable_orders,
    ROUND(
        COUNT(DISTINCT CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN o.order_id END) * 100.0 
        / NULLIF(COUNT(DISTINCT o.order_id), 0), 
        2
    ) AS cancel_rate_pct
FROM dbo.olist_products_dataset p
INNER JOIN dbo.olist_order_items_dataset oi 
    ON p.product_id = oi.product_id
INNER JOIN dbo.olist_orders_dataset o 
    ON oi.order_id = o.order_id
WHERE p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
HAVING 
    COUNT(DISTINCT o.order_id) >= 100
    AND COUNT(DISTINCT CASE WHEN o.order_status IN ('canceled', 'unavailable') THEN o.order_id END) * 1.0 
        / NULLIF(COUNT(DISTINCT o.order_id), 0) > 0.03
ORDER BY cancel_rate_pct DESC; 



-- ------------------------------------------------------------------------------------------
-- Câu 4.6.3:
-- Phát hiện các khu vực có chi phí vận chuyển bất thường:
-- Tìm các thành phố của người mua có từ 30 đơn hàng trở lên nhưng có mức cước phí vận chuyển
-- trung bình cho mỗi món hàng cao vượt ngưỡng 40.00.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.6.3 TẠI ĐÂY:


select 
    c.customer_city,
    c.customer_state,
    count(distinct o.order_id) as total_orders,
    round(avg(oi.freight_value), 2) as avg_freight_value
from dbo.olist_customers_dataset c
inner join dbo.olist_orders_dataset o on c.customer_id = o.customer_id
inner join dbo.olist_order_items_dataset oi on o.order_id = oi.order_id
where c.customer_city is not null
    and oi.freight_value >= 0
    and o.order_id <> 'canceled'
group by c.customer_city, c.customer_state
having count(distinct o.order_id) >= 30
    and avg(oi.freight_value) > 40.00
order by total_orders DESC, avg_freight_value DESC;



-- ------------------------------------------------------------------------------------------
-- [P4 - NGÀY 7]: TỔNG HỢP CHỈ SỐ ĐA CHIỀU & BÁO CÁO QUẢN TRỊ (EXECUTIVE KPI DASHBOARD)
-- ------------------------------------------------------------------------------------------

-- Câu 4.7.1:
-- Xây dựng ma trận báo cáo tài chính Năm - Quý (Year-Quarter Business Matrix):
-- Thống kê tổng doanh thu hàng bán, tổng tiền cước vận chuyển, tổng số đơn hàng và giá trị 
-- đơn trung bình (AOV)
-- theo từng cặp Năm và Quý trong toàn bộ lịch sử dữ liệu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.7.1 TẠI ĐÂY:

select 
    year(od.order_purchase_timestamp) as year,
    datepart(quarter,od.order_purchase_timestamp) as quarter,
    sum(oi.price) as total_revenue,
    sum(oi.freight_value) as total_freight_value,
    count(distinct od.order_id) as total_orders,
    ROUND(SUM(oi.price) * 1.0 / NULLIF(COUNT(DISTINCT od.order_id), 0), 2) as avg_price
from dbo.olist_orders_dataset od
inner join dbo.olist_order_items_dataset oi 
    on od.order_id = oi.order_id
where od.order_status NOT IN ('unavailable', 'canceled')
    and oi.freight_value >= 0
    and od.order_purchase_timestamp is not null
    and oi.price > 0
group by
    year(od.order_purchase_timestamp),
    datepart(quarter,od.order_purchase_timestamp)
order by 
    year(od.order_purchase_timestamp),
    datepart(quarter,od.order_purchase_timestamp)



-- ------------------------------------------------------------------------------------------
-- Câu 4.7.2:
-- Phân tích hiệu suất logistics trên các tuyến hành lang vận tải liên bang:
-- Gom nhóm theo từng cặp (Bang của Người bán - Bang của Khách mua) có phát sinh từ 50 đơn hàng trở lên:
-- Tính thời gian giao hàng thực tế trung bình và cước phí vận chuyển trung bình của tuyến đường đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.7.2 TẠI ĐÂY:

SELECT 
    s.seller_state,
    c.customer_state,
    COUNT(DISTINCT od.order_id) AS total_orders,
    ROUND(AVG(DATEDIFF(day, od.order_purchase_timestamp, od.order_delivered_customer_date) * 1.0), 2) AS avg_delivery_days,
    ROUND(AVG(oi.freight_value), 2) AS avg_freight_value
FROM dbo.olist_orders_dataset od
INNER JOIN dbo.olist_customers_dataset c 
    ON od.customer_id = c.customer_id
INNER JOIN dbo.olist_order_items_dataset oi 
    ON od.order_id = oi.order_id
INNER JOIN dbo.olist_sellers_dataset s 
    ON oi.seller_id = s.seller_id
WHERE od.order_status = 'delivered'
  AND od.order_delivered_customer_date IS NOT NULL
  AND s.seller_state IS NOT NULL
  AND c.customer_state IS NOT NULL
GROUP BY 
    s.seller_state,
    c.customer_state
HAVING COUNT(DISTINCT od.order_id) >= 50
ORDER BY total_orders DESC, avg_delivery_days DESC;
-- ------------------------------------------------------------------------------------------
-- Câu 4.7.3:
-- Đóng gói thành một View báo cáo quản trị tổng hợp KPI kinh doanh theo tháng:
-- Tạo View tổng hợp dữ liệu theo từng Tháng-Năm gồm:
-- Tổng doanh thu, Tổng số đơn hàng thành công, Số khách hàng duy nhất mua sắm,
-- Giá trị đơn hàng trung bình (AOV), và Tỷ lệ phần trăm đơn hàng giao đúng hạn cam kết SLA.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 4.7.3 TẠI ĐÂY:
CREATE OR ALTER VIEW vw_monthly_business_kpi AS
select 
    year(od.order_purchase_timestamp) as [year],
    month(od.order_purchase_timestamp) as [month],
    round(sum(oi.price), 2) as total_revenue,
    count(distinct od.order_id) as total_orders,
    count(distinct c.customer_unique_id) as total_customers,
    ROUND(SUM(oi.price) * 1.0 / NULLIF(COUNT(DISTINCT od.order_id), 0), 2) as avg_order_value,
    ROUND(
        COUNT(DISTINCT CASE WHEN CAST(od.order_delivered_customer_date AS DATE) <= CAST(od.order_estimated_delivery_date AS DATE) THEN od.order_id END) * 100.0 
        / NULLIF(COUNT(DISTINCT od.order_id), 0),
        2
    ) AS sla_on_time_rate_pct
from dbo.olist_orders_dataset od
inner join dbo.olist_order_items_dataset oi 
    on od.order_id = oi.order_id
inner join dbo.olist_customers_dataset c 
    on od.customer_id = c.customer_id
where od.order_status = 'delivered'
    and od.order_delivered_customer_date IS NOT NULL
    and oi.freight_value >= 0
    and od.order_purchase_timestamp is not null
    and oi.price > 0
group by 
    year(od.order_purchase_timestamp),
    month(od.order_purchase_timestamp)


SELECT * FROM vw_monthly_business_kpi ORDER BY [year], [month];
