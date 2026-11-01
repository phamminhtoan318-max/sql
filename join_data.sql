-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 1: CÁC NỀN TẢNG XỬ LÝ VÀ PHÂN TÍCH DỮ LIỆU CỐT LÕI (CORE DATA PIPELINE FOUNDATIONS)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 3: BÀI TOÁN JOIN TRONG DATA PIPELINE
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 1]: NỐI DIMENSION & FACT (STAR SCHEMA & BẢO TOÀN DOANH THU)
-- ------------------------------------------------------------------------------------------

-- Câu 3.1.1:
-- Tạo một tập dữ liệu phân tích bán hàng tổng hợp theo mô hình Star Schema:
-- Nối dữ liệu chi tiết mặt hàng bán ra với các thông tin ngữ cảnh: ngày đặt hàng, trạng thái đơn,
-- địa bàn của khách mua, thông tin người bán và ngành hàng sản phẩm.
-- Chỉ lấy các giao dịch của đơn hàng đã được giao thành công.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.1 TẠI ĐÂY:

select 
    orders.order_id,
    orders.order_purchase_timestamp,
    orders.order_status,
    customers.customer_state,
    sellers.seller_id,
    products.product_category_name
from dbo.olist_orders_dataset orders 
inner join dbo.olist_customers_dataset customers on orders.customer_id = customers.customer_id
inner join dbo.olist_order_items_dataset order_items on orders.order_id = order_items.order_id
inner join dbo.olist_sellers_dataset sellers on order_items.seller_id = sellers.seller_id
inner join dbo.olist_products_dataset products on order_items.product_id = products.product_id
where orders.order_status = 'delivered'



-- ------------------------------------------------------------------------------------------
-- Câu 3.1.2:
-- Trong Data Warehouse, việc chọn sai kiểu JOIN có thể làm "bốc hơi" doanh thu của công ty
-- nếu bảng danh mục sản phẩm chưa kịp đồng bộ các mã hàng mới.
-- Hãy viết truy vấn so sánh tổng doanh thu và tổng số mặt hàng bán ra giữa hai phép nối:
-- Phép nối loại bỏ dòng không khớp và Phép nối bảo toàn toàn bộ dữ liệu bán hàng.
-- Đo lường chính xác lượng doanh thu bị thất thoát nếu chọn sai kiểu JOIN.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.2 TẠI ĐÂY:

select 
    N'INNER JOIN (Bảo toàn dữ liệu)' AS join_type,
    count(*) as total_items,
    sum(oi.price) as total_price
from dbo.olist_products_dataset products
inner join dbo.olist_order_items_dataset oi on oi.product_id = products.product_id

union all

select 
    N'LEFT JOIN (Bảo toàn dữ liệu)' AS join_type,
    count(*) as total_items,
    sum(oi.price) as total_price
from dbo.olist_products_dataset products
left join dbo.olist_order_items_dataset oi on products.product_id = oi.product_id

union all 

SELECT 
    N'DOANH THU THẤT THOÁT' AS join_type,
    COUNT(*) AS total_items,
    SUM(oi.price) AS total_revenue
FROM dbo.olist_order_items_dataset oi
LEFT JOIN dbo.olist_products_dataset products 
    ON oi.product_id = products.product_id
WHERE products.product_id IS NULL;



-- ------------------------------------------------------------------------------------------
-- Câu 3.1.3:
-- Áp dụng kỹ thuật xử lý Dimension bị thiếu (Missing Member):
-- Khi kết hợp dữ liệu bán hàng với danh mục sản phẩm, nếu gặp sản phẩm chưa có trong danh mục,
-- hãy gán các thuộc tính mô tả về giá trị mặc định 'Unknown' và đánh dấu cờ cảnh báo
-- để đội ngũ vận hành dữ liệu kịp thời bổ sung.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.3 TẠI ĐÂY:

select 
   items.order_item_id,
   items.product_id,
   products.product_id,
   cast(items.price as decimal(10,2)) as price,
   case 
    when products.product_category_name is null then 'Unknown'
    else products.product_category_name
   end as product_category_name,
   case 
    when products.product_id is null then 'Unknown'
    else 'OK'
   end as [status]
from dbo.olist_order_items_dataset items
left join dbo.olist_products_dataset products on items.product_id = products.product_id



-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 2]: ANTI-JOIN & TÌM BẢN GHI MỒ CÔI (ORPHAN RECORDS)
-- ------------------------------------------------------------------------------------------

-- Câu 3.2.1:
-- Kiểm tra tính toàn vẹn dữ liệu giữa bảng chi tiết mặt hàng và bảng đơn hàng tổng quát:
-- Tìm xem có bản ghi chi tiết nào mang mã đơn hàng không hề tồn tại trong bảng đơn hàng gốc hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.1 TẠI ĐÂY:

select 
    items.order_id,
    items.order_item_id,
    items.product_id,
    items.seller_id
from dbo.olist_order_items_dataset items 
where not exists (
    select 1
    from dbo.olist_orders_dataset orders 
    where items.order_id = orders.order_id
)


select 
    items.order_id,
    items.order_item_id,
    items.product_id,
    items.seller_id
from dbo.olist_order_items_dataset items 
left join dbo.olist_orders_dataset orders on items.order_id = orders.order_id
where orders.order_id is null


-- ------------------------------------------------------------------------------------------
-- Câu 3.2.2:
-- Tìm tất cả các khách hàng đã đăng ký tài khoản trong hệ thống nhưng chưa từng phát sinh
-- bất kỳ đơn đặt hàng nào.
-- Hãy thử giải quyết bài toán này bằng ít nhất 2 cách viết truy vấn khác nhau
-- và kiểm chứng xem số lượng khách hàng tìm được có trùng khớp hay không.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.2 TẠI ĐÂY:

select 
    count(customers.customer_id) as total_customers
from dbo.olist_customers_dataset customers 
where not exists (
    select 1
    from dbo.olist_orders_dataset orders 
    where customers.customer_id = orders.customer_id
)

select 
    count(customers.customer_id) as total_customers
from 
    dbo.olist_customers_dataset customers 
left join 
    dbo.olist_orders_dataset orders 
on 
    customers.customer_id = orders.customer_id
where 
    orders.order_id is null


-- ------------------------------------------------------------------------------------------
-- Câu 3.2.3:
-- Tìm danh sách các sản phẩm đang tồn tại trong danh mục sản phẩm nhưng chưa từng được
-- bất kỳ khách hàng nào đặt mua.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.3 TẠI ĐÂY:


select 
    products.product_id,
    products.product_category_name
from dbo.olist_products_dataset products
where not exists (
    select 1
    from dbo.olist_order_items_dataset items
    where items.product_id = products.product_id
);

select 
    products.product_id,
    products.product_category_name
from dbo.olist_products_dataset products
left join dbo.olist_order_items_dataset items 
    on products.product_id = items.product_id
where items.product_id is null;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 3]: PHÁT HIỆN & XỬ LÝ NHÂN BẢN DÒNG (ONE-TO-MANY FAN-OUT)
-- ------------------------------------------------------------------------------------------

-- Câu 3.3.1:
-- Khảo sát hiện tượng nhân bản số dòng khi nối bảng đơn hàng (cấp độ 1 đơn) với bảng chi tiết
-- mặt hàng (cấp độ nhiều món):
-- Chọn một đơn hàng có từ 2 mặt hàng trở lên, kết hợp với thông tin thanh toán của đơn đó.
-- Quan sát và chỉ ra số dòng bị tăng lên và số tiền thanh toán bị nhân sai lệch như thế nào nếu tính tổng trực tiếp.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.1 TẠI ĐÂY:

select 
    payments.order_id,
    items.order_item_id,
    items.price,
    payments.payment_value
from dbo.olist_order_payments_dataset payments 
inner join dbo.olist_order_items_dataset items on payments.order_id = items.order_id
where payments.order_id = (
    select top 1
        items.order_id
    from dbo.olist_order_items_dataset items
    group by items.order_id
    having count(items.order_item_id) >= 2
);

-- ==========================================================================================
-- CẨM NANG TOÀN DIỆN VỀ HIỆN TƯỢNG FAN-OUT (NHÂN BẢN DÒNG TRONG SQL)
-- ==========================================================================================
-- 1. BẢN CHẤT & ĐỊNH NGHĨA FAN-OUT:
--    - Fan-out (xòe quạt): Là hiện tượng khi JOIN 1 bảng Cha (cấp độ 1 dòng, ví dụ: payments)
--      với 1 bảng Con (cấp độ Nhiều dòng, ví dụ: items), kết quả bị xòe bung ra thành N dòng.
--    - Khi đó, các thuộc tính của bảng Cha (payment_value, shipping_fee, budget...) 
--      bị sao chép/nhân bản lặp lại trên tất cả N dòng đó.
--    - HẬU QUẢ: Nếu tính SUM() trực tiếp trên cột của bảng Cha sau khi JOIN, 
--      con số sẽ bị thổi phồng gấp nhiều lần (gây sai lệch báo cáo tài chính, thất thoát tiền thưởng).
--
-- 2. VÍ DỤ THỰC TẾ TRÊN ĐƠN HÀNG: '3a73fa58ac16869d242abd0320be97cf'
--    - Đơn này có 2 món hàng (order_item_id = 1 và 2), mỗi món giá price = 53.90.
--      -> Tổng tiền hàng thực tế: 53.90 + 53.90 = 107.80.
--    - Tiền khách thanh toán thực tế cho cả đơn: payment_value = 134.60 (tiền hàng 107.80 + ship 26.80).
--    - Khi JOIN trực tiếp: Giá trị 134.60 bị lặp lại ở cả 2 dòng.
--    - Nếu tính SUM(payment_value): 134.60 * 2 = 269.20 (bị thổi phồng gấp đôi so với tiền khách trả)!
--
-- 3. DẤU HIỆU NHẬN BIẾT FAN-OUT (4 DẤU HIỆU CẢNH BÁO):
--    [Dấu hiệu 1] Số dòng sau khi JOIN vọt lên bất thường: COUNT(*) > COUNT(DISTINCT parent_id).
--    [Dấu hiệu 2] Dữ liệu của bảng Cha bị lặp lại y chang nhau trên cùng một mã đơn/mã cha.
--    [Dấu hiệu 3] Doanh thu sau khi JOIN lệch lớn so với doanh thu gốc:
--                 SUM(p.payment_value) sau khi JOIN >> SUM(payment_value) từ bảng gốc.
--    [Dấu hiệu 4] Bản chất quan hệ 1 - Nhiều (1 Order -> N Items; 1 Dept -> N Employees).
-- ==========================================================================================
-- ------------------------------------------------------------------------------------------
-- [PHẦN A] CÁC QUERY NHẬN BIẾT VÀ ĐO LƯỜNG FAN-OUT
-- ------------------------------------------------------------------------------------------

-- A.1. Query nhận biết trên 1 đơn hàng cụ thể (So sánh tiền thực tế vs tiền bị tính sai):
select 
    p.order_id,
    count(*)                                                     as so_dong_sau_join,
    max(p.payment_value)                                         as tien_thanh_toan_THUC_TE,
    sum(p.payment_value)                                         as tien_thanh_toan_BI_TINH_SAI,
    sum(p.payment_value) - max(p.payment_value)                 as so_tien_bi_thoi_phong_ao
from dbo.olist_order_payments_dataset p
inner join dbo.olist_order_items_dataset i on p.order_id = i.order_id
where p.order_id = '3a73fa58ac16869d242abd0320be97cf'
group by p.order_id;

-- A.2. Query kiểm toán Fan-out trên TOÀN BỘ HỆ THỐNG (Thấy quy mô sai lệch hàng triệu đồng):
select 
    count(distinct p.order_id)                                   as tong_don_hang_thuc_te,
    count(*)                                                     as tong_so_dong_bi_no_ra,
    (select sum(payment_value) from dbo.olist_order_payments_dataset) 
                                                                 as doanh_thu_CHUAN_THUC_TE,
    sum(p.payment_value)                                         as doanh_thu_BI_FAN_OUT_SAI,
    round(sum(p.payment_value) / (select sum(payment_value) from dbo.olist_order_payments_dataset), 2) 
                                                                 as he_so_bi_doi_khong_len
from dbo.olist_order_payments_dataset p
inner join dbo.olist_order_items_dataset i on p.order_id = i.order_id;


-- ------------------------------------------------------------------------------------------
-- [PHẦN B] CÁC PHƯƠNG PHÁP KHẮC PHỤC TRIỆT ĐỂ & TỐI ƯU
-- ------------------------------------------------------------------------------------------

-- CÁCH 1 (CHUẨN TỐI ƯU NHẤT): Gom nhóm trước khi JOIN (Pre-aggregation)
-- Nguyên tắc: Gom các bảng con về cấp độ 1 dòng/1 đơn hàng (quan hệ 1-1) trước khi JOIN.
-- Ưu điểm: Tốc độ xử lý cực nhanh, không tốn bộ nhớ TempDB, không sợ tính sai số.
with items_agg as (
    select 
        items.order_id,
        count(items.order_item_id) as total_items,
        sum(items.price)           as total_item_price
    from dbo.olist_order_items_dataset items
    group by items.order_id
),
payments_agg as (
    select
        payments.order_id,
        sum(payments.payment_value) as total_payment_value
    from dbo.olist_order_payments_dataset payments
    group by payments.order_id
)
select 
    i.order_id,
    i.total_items,
    i.total_item_price,
    p.total_payment_value
from items_agg i
inner join payments_agg p on i.order_id = p.order_id
where i.order_id = '3a73fa58ac16869d242abd0320be97cf';


-- CÁCH 2: Dùng ROW_NUMBER() + CASE WHEN (Khi cần giữ lại chi tiết từng món)
-- Nguyên tắc: Đánh số thứ tự các món. Chỉ cộng tiền thanh toán ở món đầu tiên (rn = 1).
with ranked_payments as (
    select 
        payments.order_id,
        payments.payment_value,
        items.order_item_id,
        items.price,
        row_number() over (
            partition by payments.order_id 
            order by items.order_item_id
        ) as rn
    from dbo.olist_order_payments_dataset payments
    inner join dbo.olist_order_items_dataset items on payments.order_id = items.order_id
    where payments.order_id = '3a73fa58ac16869d242abd0320be97cf'
)
select 
    order_id,
    sum(case when rn = 1 then payment_value else 0 end) as real_payment_value,
    sum(price)                                          as total_item_price
from ranked_payments
group by order_id;


-- CÁCH 3: Tách truy vấn độc lập (Không JOIN nếu không bắt buộc)
-- Nếu mục đích chỉ là lấy tổng doanh thu và tổng tiền hàng toàn sàn:
-- -> Query độc lập từng bảng, tuyệt đối không JOIN chéo 2 bảng con với nhau.


-- ------------------------------------------------------------------------------------------
-- [MỞ RỘNG KIẾN THỨC]: HIỆN TƯỢNG FAN-OUT TRONG OLTP SO VỚI OLAP (DATA WAREHOUSE)
-- ------------------------------------------------------------------------------------------
-- CÂU HỎI: Fan-out chỉ xảy ra ở mô hình OLTP hay cả trong OLAP (Data Warehouse)?
-- TRẢ LỜI: CẢ HAI ĐỀU BỊ, và trong OLAP nó còn tinh vi và nguy hiểm hơn rất nhiều!
--
-- 1. Trong mô hình OLTP (Cơ sở dữ liệu vận hành giao dịch hàng ngày):
--    - Hệ thống bắt buộc phải thiết kế chuẩn hóa (3NF) để tránh trùng lặp khi thêm/sửa/xóa.
--    - Fan-out phát sinh tự nhiên khi viết query nối giữa Bảng Cha (1 dòng) và Bảng Con (N dòng)
--      (Ví dụ: orders -> order_items, payments -> items).
--
-- 2. Trong mô hình OLAP (Data Warehouse / BI / Báo cáo phân tích):
--    - Thiết kế hình sao (Star Schema) chuẩn có quan hệ Fact -> Dimension là N - 1.
--      Khi Fact nối Dimension thì KHÔNG bị Fan-out.
--    - TUY NHIÊN, OLAP vẫn bị Fan-out nghiêm trọng ở 2 "bẫy tử thần":
--      * Bẫy 1: Nối 2 bảng Fact khác cấp độ hạt (Mismatched Fact Grains / Fact-to-Fact Join):
--        Ví dụ: Nối Fact_Doanh_Thu (cấp độ Ngày) với Fact_Chi_Tieu_KPI (cấp độ Tháng).
--        Mục tiêu KPI 500 triệu của tháng sẽ bị lặp lại 30 lần (theo 30 ngày) -> SUM bị nhân 30 lần!
--      * Bẫy 2: Chiều quan hệ Nhiều - Nhiều (Many-to-Many Dimension qua Bridge Table):
--        Ví dụ: 1 ca khám bệnh mắc 3 bệnh cùng lúc, 1 tài khoản có 2 đồng sở hữu, 1 đơn dùng 2 voucher...
--        Khi nối Fact qua Bridge Table, số tiền viện phí / số dư tài khoản lập tức bị nhân bản!
--
-- -> QUY TẮC BẤT BIẾN: Dù là OLTP hay OLAP, bất kỳ khi nào có phép nối 1 -> Nhiều (1-to-Many),
--    luôn phải xác định rõ Granularity (cấp độ hạt) và gom nhóm trước khi tính SUM/AVG!


-- ------------------------------------------------------------------------------------------
-- Câu 3.3.2:
-- Viết truy vấn kiểm toán độ nở dòng (Row Count & Fan-out Audit) khi nối bảng đơn hàng
-- với bảng chi tiết mặt hàng:
-- Tính số lượng đơn hàng độc nhất trước khi nối, tổng số dòng sau khi nối,
-- và tỷ lệ nở dòng trung bình của toàn hệ thống.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.2 TẠI ĐÂY:

with before_table as (
    select 
        count(distinct o.order_id) as tong_don_hang
    from dbo.olist_orders_dataset o
),
after_table as (
    select
        count(*) as tong_so_dong_sau_join
    from dbo.olist_orders_dataset o
    inner join dbo.olist_order_items_dataset i on o.order_id = i.order_id
)
select 
    b.tong_don_hang,
    a.tong_so_dong_sau_join,
    round(1.0 * a.tong_so_dong_sau_join / b.tong_don_hang, 2) as he_so_no_ra_trung_binh
from before_table b
cross join after_table a;

-- ------------------------------------------------------------------------------------------
-- Câu 3.3.3:
-- Cần lấy thông tin của từng đơn hàng kèm theo: Tổng tiền hàng, Tổng cước phí, và Tổng số món hàng.
-- Viết câu truy vấn đảm bảo số dòng kết quả trả về đúng bằng số dòng của bảng đơn hàng gốc,
-- tuyệt đối không để xảy ra hiện tượng nhân bản dòng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.3 TẠI ĐÂY:

with table_item as (
    select 
        i.order_id,
        sum(i.price) as total_price,
        sum(i.freight_value) as total_freight,
        count(*) as total_item
    from dbo.olist_order_items_dataset i
    group by i.order_id
),
table_payment as (
    select 
        p.order_id,
        sum(p.payment_value) as total_payment
    from dbo.olist_order_payments_dataset p
    group by p.order_id
)
select 
    i.total_price,
    i.total_freight,
    i.total_item,
    p.total_payment
from table_item i
inner join table_payment p on i.order_id = p.order_id;

-- ------------------------------------------------------------------------------------------
-- NHẬN XÉT & CÁC ĐIỂM CẦN LƯU Ý Ở QUERY TRÊN:
-- 1. Thừa bảng thanh toán (table_payment): Đề bài chỉ yêu cầu tiền hàng, cước phí và số món,
--    tất cả đều nằm trong bảng order_items, không cần đưa bảng payment vào.
-- 2. Thiếu thông tin đơn hàng gốc: Mệnh đề SELECT chưa có mã đơn (order_id), ngày đặt, trạng thái...
-- 3. Mất đơn hàng (Data Loss do INNER JOIN):
--    - Bảng đơn hàng gốc (olist_orders_dataset) có 99,441 đơn.
--    - Trong đó có 775 đơn hàng bị hủy hoặc không có sản phẩm trong bảng items.
--    - Dùng INNER JOIN sẽ làm rơi rụng 775 đơn này (chỉ còn 98,666 dòng), vi phạm yêu cầu
--      "đảm bảo số dòng kết quả đúng bằng số dòng bảng đơn hàng gốc".
--    -> GIẢI PHÁP: Phải dùng LEFT JOIN từ bảng olist_orders_dataset sang bảng gom nhóm items.
-- ------------------------------------------------------------------------------------------

-- QUERY HOÀN CHỈNH CHUẨN 100% THEO ĐỀ BÀI:
with table_item as (
    select 
        i.order_id,
        sum(i.price)         as total_price,
        sum(i.freight_value) as total_freight,
        count(*)             as total_item
    from dbo.olist_order_items_dataset i
    group by i.order_id
)
select 
    o.order_id,
    o.order_status,
    o.order_purchase_timestamp,
    isnull(i.total_price, 0)   as total_price,
    isnull(i.total_freight, 0) as total_freight,
    isnull(i.total_item, 0)    as total_item
from dbo.olist_orders_dataset o
left join table_item i 
    on o.order_id = i.order_id;

-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 4]: THẢM HỌA CARTESIAN EXPLOSION (CHẬP NHIỀU BẢNG CON CÙNG LÚC)
-- ------------------------------------------------------------------------------------------

-- Câu 3.4.1:
-- Một đơn hàng có thể có nhiều mặt hàng và cũng có thể được thanh toán làm nhiều đợt.
-- Hãy tìm các đơn hàng có cả 2 điều kiện trên (nhiều món hàng VÀ nhiều lần thanh toán),
-- sau đó minh họa hiện tượng "nổ tích Descartes" khi nối đồng thời 3 bảng này lại với nhau.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.1 TẠI ĐÂY:


with target_order as (
    select top 1
        i.order_id,
        count(distinct i.order_item_id)   as so_mon_hang,      -- Giả sử = M (ví dụ: 3 món)
        count(distinct p.payment_sequential) as so_lan_thanh_toan -- Giả sử = N (ví dụ: 2 lần)
    from dbo.olist_order_items_dataset i
    inner join dbo.olist_order_payments_dataset p 
        on i.order_id = p.order_id
    group by i.order_id
    having count(distinct i.order_item_id) > 1 
       and count(distinct p.payment_sequential) > 1
)

select 
    t.order_id,
    t.so_mon_hang,
    t.so_lan_thanh_toan,
    i.order_item_id,
    i.price,
    p.payment_sequential,
    p.payment_type,
    p.payment_value
from target_order t
inner join dbo.olist_orders_dataset o 
    on t.order_id = o.order_id
inner join dbo.olist_order_items_dataset i 
    on o.order_id = i.order_id
inner join dbo.olist_order_payments_dataset p 
    on o.order_id = p.order_id
order by i.order_item_id, p.payment_sequential;

-- ------------------------------------------------------------------------------------------
-- Câu 3.4.2:
-- Viết truy vấn tổng hợp báo cáo tài chính cho từng đơn hàng:
-- Hiển thị mã đơn hàng, ngày đặt, trạng thái, tổng giá trị hàng bán và tổng số tiền thanh toán thực nhận.
-- Xử lý triệt để bẫy nhân chéo dòng giữa bảng chi tiết món hàng và bảng thanh toán.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.2 TẠI ĐÂY:


with table_item as (
    select 
        i.order_id,
        sum(i.price) as total_revenue
    from dbo.olist_order_items_dataset i
    group by i.order_id
),
table_payment as (
    select 
        p.order_id,
        sum(p.payment_value) as total_payments
    from dbo.olist_order_payments_dataset p  
    group by p.order_id
)
select 
    o.order_id,
    cast(o.order_purchase_timestamp as date) as order_purchase_date,
    o.order_status,
    isnull(i.total_revenue, 0) as total_revenue,
    isnull(p.total_payments, 0) as total_payments
from dbo.olist_orders_dataset o
left join table_item i on o.order_id = i.order_id
left join table_payment p on o.order_id = p.order_id
order by order_purchase_date desc;

-- ------------------------------------------------------------------------------------------
-- Câu 3.4.3:
-- Thực hiện đối soát số liệu trên quy mô toàn sàn:
-- Tính tổng tiền hàng bán ra toàn hệ thống và đối chiếu với tổng tiền thanh toán thu về.
-- Thống kê số lượng các đơn hàng có sự chênh lệch giữa tiền hàng và tiền thanh toán thực nhận.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.3 TẠI ĐÂY:

with table_item as (
    select 
        i.order_id,
        sum(i.price + i.freight_value) as total_revenue
    from dbo.olist_order_items_dataset i
    group by i.order_id
),
table_payment as (
    select 
        p.order_id,
        sum(p.payment_value) as total_payments
    from dbo.olist_order_payments_dataset p  
    group by p.order_id
)
select 
    count(*) as total_orders,
    sum(t1.total_revenue) as total_revenue,
    sum(t2.total_payments) as total_payments,
    sum(t1.total_revenue - t2.total_payments) as diff,
    sum(case when isnull(t1.total_revenue, 0) <> isnull(t2.total_payments, 0) then 1 else 0 end) as total_diff
from dbo.olist_orders_dataset o
left join table_item t1 on o.order_id = t1.order_id
left join table_payment t2 on o.order_id = t2.order_id;

truncate table dbo.Pipeline_Control;

drop table dbo.Pipeline_Control;

-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 5]: GEOLOCATION JOIN & KHỬ TRÙNG TRƯỚC KHI NỐI
-- ------------------------------------------------------------------------------------------

-- Câu 3.5.1:
-- Bảng Geolocation chứa rất nhiều tọa độ đo lường khác nhau cho cùng một mã bưu chính.
-- Hãy viết truy vấn chứng minh rằng nếu đem nối trực tiếp bảng khách hàng với bảng Geolocation
-- theo mã bưu chính thì số lượng dòng kết quả sẽ bùng nổ gấp nhiều lần so với số khách hàng thực tế.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.1 TẠI ĐÂY:

select 
    count(*) as total_geolocation
from dbo.olist_geolocation_dataset g 

select 
    count(*) as total_customers
from dbo.olist_customers_dataset c

select 
    count(distinct c.customer_id) as total_customers,
    count(*) as total_rows_after_join,
    cast(count(*) * 1.0 / count(distinct c.customer_id) as decimal(10, 2)) as explosion_multiplier
from dbo.olist_geolocation_dataset g  
inner join dbo.olist_customers_dataset c on g.geolocation_zip_code_prefix = c.customer_zip_code_prefix;

-- ==========================================================================================
-- GIẢI THÍCH CHI TIẾT HIỆN TƯỢNG BÙNG NỔ DÒNG KHI JOIN GEOLOCATION (FAN-OUT EXPLOSION)
-- ==========================================================================================
-- 1. BẢN CHẤT VẤN ĐỀ:
--    - Bảng khách hàng (olist_customers_dataset) có 99,441 khách hàng.
--    - Khóa liên kết giữa 2 bảng là mã bưu chính: customer_zip_code_prefix = geolocation_zip_code_prefix.
--    - Bảng Geolocation không phải bảng danh mục chuẩn (1 zip = 1 dòng), mà chứa dữ liệu thô (raw data)
--      được thu thập từ nhiều lần đo đạc GPS thực tế:
--      -> Mỗi mã bưu chính (zip_code) có thể chứa từ hàng chục đến hàng nghìn bản ghi tọa độ khác nhau.
--
-- 2. CƠ CHẾ NỞ DÒNG (FAN-OUT TRÊN TỪNG MÃ BƯU CHÍNH):
--    - Khi thực hiện INNER JOIN trực tiếp theo mã bưu chính:
--      Mỗi khách hàng mang mã zip X sẽ bị ghép cặp với TẤT CẢ các dòng tọa độ của mã zip X đó.
--    - Ví dụ: Với mã zip 24220 có 1,146 bản ghi tọa độ trong bảng Geolocation:
--      Mỗi khách hàng thuộc mã zip này sẽ bị nhân bản thành 1,146 dòng sau khi JOIN!
--
-- 3. KẾT QUẢ ĐỐI SOÁT & CHỨNG MINH TỪ TRUY VẤN:
--    - Số khách hàng thực tế khớp dữ liệu: 99,163 khách.
--    - Tổng số dòng sinh ra sau khi JOIN: 15,083,455 dòng!
--    - Hệ số bùng nổ (explosion_multiplier): ~152.11 lần!
--      -> Dữ liệu bị thổi phồng gấp hơn 152 lần so với số lượng khách hàng thực tế.
--
-- 4. HẬU QUẢ NẾU KHÔNG XỬ LÝ TRƯỚC KHI NỐI:
--    - Gây sai lệch nghiêm trọng khi tính tổng, đếm hoặc thống kê doanh thu theo vùng miền.
--    - Gây nghẽn băng thông, tràn bộ nhớ TempDB và sập truy vấn (Memory Spill / Out of Memory).
--
-- 5. BÀI HỌC VÀ ĐỊNH HƯỚNG CHO CÂU 3.5.2:
--    - BẮT BUỘC phải làm sạch (Data Cleaning) và khử trùng bảng Geolocation trước khi JOIN:
--      Gom nhóm (GROUP BY) bảng Geolocation theo zip_code_prefix để mỗi mã bưu chính chỉ còn
--      đúng 1 dòng đại diện (ví dụ: lấy tọa độ trung bình AVG(lat), AVG(lng) hoặc dùng ROW_NUMBER() = 1).
-- ==========================================================================================


-- ------------------------------------------------------------------------------------------
-- Câu 3.5.2:
-- Xây dựng giải pháp làm sạch dữ liệu tọa độ địa lý sao cho mỗi mã bưu chính chỉ còn đúng một dòng đại diện.
-- Sau đó nối dữ liệu này vào bảng khách hàng, đảm bảo số dòng kết quả bảo toàn 100% số lượng khách ban đầu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.2 TẠI ĐÂY:

with table_geolocation as (
    select 
        g.geolocation_zip_code_prefix,
        AVG(g.geolocation_lat) as avg_lat,
        AVG(g.geolocation_lng) as avg_lng
    from dbo.olist_geolocation_dataset g
    group by g.geolocation_zip_code_prefix
)

select 
    count(distinct c.customer_id) as total_customers,
    count(g.geolocation_zip_code_prefix) as total_geolocation,
    count(*) as total_rows_after_join,
    cast(count(*) * 1.0 / count(distinct c.customer_id) as decimal(10, 2)) as explosion_multiplier
from table_geolocation g  
inner join dbo.olist_customers_dataset c on g.geolocation_zip_code_prefix = c.customer_zip_code_prefix


-- ------------------------------------------------------------------------------------------
-- Câu 3.5.3:
-- Phân tích chi phí vận chuyển theo khoảng cách địa lý:
-- Xác định các đơn hàng mà Người bán và Khách mua nằm cùng một bang (giao hàng nội vùng).
-- So sánh mức cước vận chuyển trung bình giữa đơn hàng nội vùng so với đơn hàng liên vùng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.3 TẠI ĐÂY:

with orders_seller as (
    select 
        c.customer_state,
        s.seller_state,
        i.freight_value
    from dbo.olist_orders_dataset o
    join dbo.olist_order_items_dataset i on i.order_id = o.order_id
    join dbo.olist_sellers_dataset s on s.seller_id = i.seller_id
    join dbo.olist_customers_dataset c on c.customer_id = o.customer_id
    group by c.customer_state, s.seller_state, i.freight_value
),
category as (
    select 
        case 
            when os.customer_state = os.seller_state then N'Nội vùng'
            else    N'Liên vùng'
        end as freight_category,
        os.freight_value
    from orders_seller os
)
select 
    freight_category,
    count(*) as total_customers,
    round(AVG(freight_value), 2) as avg_freight_value
from category
group by freight_category



-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 6]: KỸ THUẬT LẤY TOP 1 MỖI NHÓM TRONG PHÉP NỐI (TOP 1 PER GROUP)
-- ------------------------------------------------------------------------------------------

-- Câu 3.6.1:
-- Trích xuất danh sách đơn hàng kèm theo thông tin của đúng một sản phẩm có giá trị đắt nhất
-- trong đơn hàng đó, đảm bảo kết quả mỗi đơn hàng chỉ xuất hiện duy nhất một dòng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.1 TẠI ĐÂY:

;with order_max as (
    select 
        o.order_id,
        o.order_purchase_timestamp,
        o.order_approved_at,
        i.price,
        i.freight_value,
        ROW_NUMBER() over(partition by o.order_id order by i.price desc) as rn
    from dbo.olist_orders_dataset o  
    inner join dbo.olist_order_items_dataset i on o.order_id = i.order_id
    where o.order_status <> 'cancel'
)
select 
    om.order_id,
    om.order_purchase_timestamp,
    om.order_approved_at,
    om.price,
    om.freight_value
from order_max om 
where om.rn = 1
order by om.price desc


-- ------------------------------------------------------------------------------------------
-- Câu 3.6.2:
-- Trích xuất thông tin đơn hàng kết hợp với nội dung đánh giá mới nhất của đơn hàng đó.
-- Với các đơn hàng chưa có đánh giá, vẫn phải bảo toàn đơn hàng trong kết quả.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.2 TẠI ĐÂY:

with new_review as (
    select 
        r.order_id,
        r.review_id,
        r.review_score,
        r.review_answer_timestamp,
        r.review_comment_message,
        r.review_comment_title,
        r.review_creation_date,
        ROW_NUMBER() over(partition by r.order_id order by r.review_creation_date desc, r.review_answer_timestamp desc) as rn
    from dbo.olist_order_reviews_dataset r
)

select 
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    nr.review_id,
    nr.review_score,
    nr.review_comment_title,
    nr.review_comment_message,
    nr.review_creation_date,
    nr.review_answer_timestamp
from dbo.olist_orders_dataset o
left join new_review nr on nr.order_id = o.order_id
and nr.rn = 1
order by o.order_purchase_timestamp



-- ------------------------------------------------------------------------------------------
-- Câu 3.6.3:
-- Đối với các đơn hàng có nhiều hình thức thanh toán, hãy lấy thông tin đơn hàng kèm theo
-- phương thức thanh toán chiếm tỷ trọng tiền lớn nhất của đơn hàng đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.3 TẠI ĐÂY:

with payment_order as (
    select 
        p.order_id,
        p.payment_type,
        sum(p.payment_value) as total_payment_value,
        row_number() over(partition by p.order_id order by sum(p.payment_value) desc) as rn,
        count(*) over(partition by p.order_id) as payment_count
    from dbo.olist_order_payments_dataset p
    group by p.order_id, p.payment_type
)
select 
    o.order_id,
    o.customer_id,
    o.order_status,
    o.order_purchase_timestamp,
    po.payment_type,
    po.total_payment_value,
    po.payment_count
from dbo.olist_orders_dataset o
inner join payment_order po on po.order_id = o.order_id
and po.rn = 1
and po.payment_count > 1




-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 7]: TỔNG HỢP KIỂM TRA CHẤT LƯỢNG PHÉP NỐI TRÊN PRODUCTION
-- ------------------------------------------------------------------------------------------

-- Câu 3.7.1:
-- Xây dựng một View tổng hợp dữ liệu Fact bán hàng chuẩn Star Schema kết hợp đầy đủ
-- thông tin về Khách hàng, Người bán và Sản phẩm.
-- Cấp độ dữ liệu của View phải chuẩn xác ở mức: 1 dòng tương ứng với 1 mặt hàng bán ra trong đơn.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.1 TẠI ĐÂY:

CREATE OR ALTER VIEW vw_fact_sales AS
SELECT 
    -- Fact Grain: 1 dòng tương ứng 1 mặt hàng bán ra trong đơn
    oi.order_id,
    oi.order_item_id,
    
    -- Fact Measures (Số liệu bán hàng)
    oi.price,
    oi.freight_value,
    (oi.price + oi.freight_value) AS total_item_value,
    
    -- Order Attributes (Thông tin đơn hàng)
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    oi.shipping_limit_date,

    -- Customer Dimension (Thông tin khách hàng)
    o.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,

    -- Seller Dimension (Thông tin người bán)
    oi.seller_id,
    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state,

    -- Product Dimension (Thông tin sản phẩm)
    oi.product_id,
    p.product_category_name,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm
FROM dbo.olist_order_items_dataset oi
INNER JOIN dbo.olist_orders_dataset o 
    ON oi.order_id = o.order_id
LEFT JOIN dbo.olist_customers_dataset c 
    ON o.customer_id = c.customer_id
LEFT JOIN dbo.olist_sellers_dataset s 
    ON oi.seller_id = s.seller_id
LEFT JOIN dbo.olist_products_dataset p 
    ON oi.product_id = p.product_id
GO
-- ------------------------------------------------------------------------------------------
-- Câu 3.7.2:
-- Viết một kịch bản SQL tự động kiểm tra đối soát (Assertion Test):
-- So sánh tổng doanh thu ở bảng dữ liệu nguồn gốc và tổng doanh thu tính từ View vừa tạo ở Câu 3.7.1.
-- Tự động đưa ra thông báo thành công hoặc báo động đỏ nếu phát hiện có sự sai lệch số tiền.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.2 TẠI ĐÂY:

DECLARE @source_revenue DECIMAL(18, 2);
DECLARE @view_revenue   DECIMAL(18, 2);
DECLARE @diff           DECIMAL(18, 2);

-- 1. Tính tổng doanh thu tiền hàng từ bảng nguồn (olist_order_items_dataset)
SELECT @source_revenue = ROUND(SUM(price), 2)
FROM dbo.olist_order_items_dataset;

-- 2. Tính tổng doanh thu tiền hàng từ View đã tạo ở Câu 3.7.1 (vw_fact_sales)
SELECT @view_revenue = ROUND(SUM(price), 2)
FROM vw_fact_sales;

-- 3. Tính mức chênh lệch tuyệt đối
SET @diff = ABS(ISNULL(@source_revenue, 0) - ISNULL(@view_revenue, 0));

-- 4. Bảng chi tiết kết quả đối soát dữ liệu
SELECT 
    @source_revenue AS source_revenue,
    @view_revenue   AS view_revenue,
    @diff           AS diff_amount,
    CASE 
        WHEN @diff = 0 THEN N'PASS (Dữ liệu khớp)' 
        ELSE N'FAIL (Lệch doanh thu)' 
    END AS audit_status;

-- 5. Kịch bản thông báo tự động (Assertion Check)
IF @diff = 0
BEGIN
    PRINT N' [THÀNH CÔNG] KIỂM TRA ĐỐI SOÁT HOÀN TOÀN KHỚP!';
    PRINT N'- Doanh thu bảng nguồn: ' + FORMAT(@source_revenue, 'N2');
    PRINT N'- Doanh thu từ View:    ' + FORMAT(@view_revenue, 'N2');
    PRINT N'- Chênh lệch:           0.00';
END
ELSE
BEGIN
    PRINT N' [BÁO ĐỘNG ĐỎ] PHÁT HIỆN SAI LỆCH DỮ LIỆU DOANH THU!';
    PRINT N'- Doanh thu bảng nguồn: ' + FORMAT(@source_revenue, 'N2');
    PRINT N'- Doanh thu từ View:    ' + FORMAT(@view_revenue, 'N2');
    PRINT N'- Số tiền chênh lệch:   ' + FORMAT(@diff, 'N2');
    
    RAISERROR(N'BÁO ĐỘNG ĐỎ: Doanh thu giữa View và bảng nguồn không khớp!', 16, 1);
END;
GO


-- ------------------------------------------------------------------------------------------
-- Câu 3.7.3:
-- Viết một Stored Procedure kiểm toán chất lượng phép nối giữa bảng cha và bảng con:
-- Tự động tính toán mức độ gia tăng số dòng sau khi nối và liệt kê danh sách các khóa chính
-- bị nhân bản nhiều nhất kèm theo số lần nhân bản.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.3 TẠI ĐÂY:

CREATE OR ALTER PROCEDURE sp_audit_join_quality
    @parent_table NVARCHAR(128) = 'dbo.olist_orders_dataset',
    @child_table  NVARCHAR(128) = 'dbo.olist_order_items_dataset',
    @join_key     NVARCHAR(128) = 'order_id',
    @top_n        INT = 10
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @parent_row_count BIGINT;
    DECLARE @joined_row_count BIGINT;
    DECLARE @sql NVARCHAR(MAX);

    -- 1. Đếm tổng số dòng của bảng cha
    SET @sql = N'SELECT @cnt = COUNT_BIG(*) FROM ' + @parent_table;
    EXEC sp_executesql @sql, N'@cnt BIGINT OUTPUT', @cnt = @parent_row_count OUTPUT;

    -- 2. Đếm tổng số dòng sau khi nối (INNER JOIN) giữa bảng cha và bảng con
    SET @sql = N'
        SELECT @cnt = COUNT_BIG(*) 
        FROM ' + @parent_table + N' p
        INNER JOIN ' + @child_table + N' c 
            ON p.' + @join_key + N' = c.' + @join_key;
    EXEC sp_executesql @sql, N'@cnt BIGINT OUTPUT', @cnt = @joined_row_count OUTPUT;

    -- 3. Bảng 1: Báo cáo mức độ gia tăng số dòng sau phép nối
    SELECT 
        @parent_table AS parent_table,
        @child_table AS child_table,
        @join_key AS join_key,
        @parent_row_count AS parent_rows,
        @joined_row_count AS joined_rows,
        (@joined_row_count - @parent_row_count) AS rows_added,
        CAST(ROUND((@joined_row_count - @parent_row_count) * 100.0 / NULLIF(@parent_row_count, 0), 2) AS DECIMAL(10, 2)) AS growth_rate_pct,
        CAST(ROUND(@joined_row_count * 1.0 / NULLIF(@parent_row_count, 0), 2) AS DECIMAL(10, 2)) AS duplication_factor;

    -- 4. Bảng 2: Danh sách top các khóa chính bị nhân bản nhiều nhất kèm số lần nhân bản
    SET @sql = N'
        SELECT TOP (' + CAST(@top_n AS NVARCHAR(10)) + N')
            p.' + @join_key + N' AS primary_key_value,
            COUNT(*) AS duplicate_count
        FROM ' + @parent_table + N' p
        INNER JOIN ' + @child_table + N' c 
            ON p.' + @join_key + N' = c.' + @join_key + N'
        GROUP BY p.' + @join_key + N'
        HAVING COUNT(*) > 1
        ORDER BY COUNT(*) DESC;';

    EXEC sp_executesql @sql;
END;
GO

-- Lời gọi thực thi Stored Procedure mẫu:
-- EXEC sp_audit_join_quality;
