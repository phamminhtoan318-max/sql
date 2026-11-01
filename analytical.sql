-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- TẦNG 2: XỬ LÝ DỮ LIỆU NÂNG CAO & ANALYTICAL SQL (ADVANCED DATA PIPELINE & ANALYTICAL SQL)
-- Database thực hành: E_commerse (Olist Brazilian E-Commerce)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ==========================================================================================
-- ████████████████████████████████████████████████████████████████████████████████████████
-- PHẦN 3: ANALYTICAL SQL (WINDOW FUNCTIONS PHỤC VỤ DATA ENGINEERING)
-- ████████████████████████████████████████████████████████████████████████████████████████
-- ==========================================================================================

-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 1]: RANKING FUNCTIONS & LỌC TOP-N MỖI NHÓM
-- ------------------------------------------------------------------------------------------

-- Câu 3.1.1:
-- Phân tích và so sánh thực tế 3 hàm xếp hạng (ROW_NUMBER, RANK, DENSE_RANK):
-- Xếp hạng doanh số bán hàng của các Người bán theo từng Bang cư trú.
-- Chỉ ra sự khác biệt rõ rệt về mặt số thứ tự khi có 2 người bán đạt doanh số bằng nhau.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.1 TẠI ĐÂY:

with table_seller_rank as (
    select 
        sellers.seller_id,
        sellers.seller_state,
        temp.sum_price
    from dbo.olist_sellers_dataset sellers 
    inner join (
        select 
            items.seller_id,
            SUM(items.price) as sum_price
        from dbo.olist_order_items_dataset items 
        group by items.seller_id 
    ) temp
    on sellers.seller_id = temp.seller_id
)
select 
    s.seller_id,
    s.seller_state,
    s.sum_price,
    ROW_NUMBER() OVER (PARTITION BY s.seller_state ORDER BY s.sum_price DESC) as rn,
    RANK() OVER (PARTITION BY s.seller_state ORDER BY s.sum_price DESC) as rk,
    DENSE_RANK() OVER (PARTITION BY s.seller_state ORDER BY s.sum_price DESC) as dr
from table_seller_rank s

-- ------------------------------------------------------------------------------------------
-- Câu 3.1.2:
-- Tìm Top 3 sản phẩm có tổng doanh thu bán ra cao nhất trong TỪNG ngành hàng sản phẩm.
-- Đảm bảo kết quả phân cấp chính xác theo từng danh mục mà không làm lẫn lộn giữa các ngành hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.2 TẠI ĐÂY:

;with cte_product_revenue_by_cat as (
    select 
        p.product_category_name,
        p.product_id,
        temp.sum_price
    from dbo.olist_products_dataset p 
    inner join (
        select 
            items.product_id,
            sum(items.price) as sum_price
        from dbo.olist_order_items_dataset items 
        group by items.product_id 
    ) temp
    on p.product_id = temp.product_id
    where p.product_category_name is not null 
),
ranked_product_cat as (
    select 
        cte.product_category_name,
        cte.product_id,
        cte.sum_price,
        DENSE_RANK() OVER (PARTITION BY cte.product_category_name ORDER BY cte.sum_price DESC) as drnk
    from cte_product_revenue_by_cat cte
)
select 
    product_category_name,
    product_id,
    sum_price
from ranked_product_cat
where drnk <= 3
order by 
    product_category_name,
    sum_price desc



-- ------------------------------------------------------------------------------------------
-- Câu 3.1.3:
-- Đánh số thứ tự lịch sử mua hàng của từng khách hàng thực tế theo trình tự thời gian đặt đơn:
-- Đơn hàng nào là đơn thứ 1 (First Order), đơn nào là đơn thứ 2, đơn thứ 3...
-- Trích xuất danh sách tất cả các đơn hàng thứ 2 của những khách hàng đã quay lại mua sắm.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.1.3 TẠI ĐÂY:


with cte_order_by_cust as (
    select 
        c.customer_unique_id,
        o.customer_id,
        o.order_id,
        o.order_purchase_timestamp,
        row_number() over (
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp asc
        ) as order_seq
    from dbo.olist_orders_dataset o
    inner join dbo.olist_customers_dataset c
        on o.customer_id = c.customer_id
)
select 
    customer_unique_id,
    order_id,
    order_purchase_timestamp,
    order_seq,
    'Second Order' as order_type
from cte_order_by_cust
where order_seq = 2
order by 
    customer_unique_id,
    order_purchase_timestamp;


-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 2]: PREVIOUS / NEXT (LEAD & LAG - THEO DÕI BIẾN ĐỘNG & TĂNG TRƯỞNG)
-- ------------------------------------------------------------------------------------------

-- Câu 3.2.1:
-- Tính khoảng cách thời gian giữa các lần mua sắm (Inter-Purchase Cycle Time):
-- Đối với mỗi đơn hàng của khách, hãy tính số ngày chênh lệch so với đơn hàng liền trước đó của chính khách hàng đó.
-- Tìm thời gian trung bình giữa 2 lần mua sắm liên tiếp của các khách hàng thân thiết.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.1 TẠI ĐÂY:

with cte_order_by_cust as (
    select 
        customers.customer_unique_id,
        orders.order_id,
        orders.order_purchase_timestamp,
        lag(orders.order_purchase_timestamp) over(partition by customers.customer_unique_id order by orders.order_purchase_timestamp ASC) as prev_order_date
    from dbo.olist_customers_dataset customers 
    inner join dbo.olist_orders_dataset orders 
    on customers.customer_id = orders.customer_id
), 
cte_cycle as (
    select 
        c.customer_unique_id,
        datediff(
            day, 
            c.prev_order_date, 
            c.order_purchase_timestamp
        ) as cycle_time
    from cte_order_by_cust c
    where c.prev_order_date is not null 
)
select 
    c.customer_unique_id,
    count(c.customer_unique_id) as purchase_count,
    round(avg(c.cycle_time), 2) as avg_cycle_time
from cte_cycle c
group by c.customer_unique_id
order by avg_cycle_time ASC

-- ------------------------------------------------------------------------------------------
-- Câu 3.2.2:
-- Phân tích tốc độ tăng trưởng doanh thu so với tháng trước (Month-over-Month Growth):
-- Tính tổng doanh thu theo từng tháng trong lịch sử, lấy doanh thu của tháng liền trước
-- và tính toán tỷ lệ tăng trưởng phần trăm (% MoM) qua từng tháng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.2 TẠI ĐÂY:

with cte_month_revenue as (
    select 
        format(orders.order_purchase_timestamp, 'yyyy-MM') as year_month,
        sum(items.price) as monthly_revenue
    from dbo.olist_orders_dataset orders 
    inner join dbo.olist_order_items_dataset items on orders.order_id = items.order_id
    group by format(orders.order_purchase_timestamp, 'yyyy-MM')
),cte_mon as (
    select 
        c.year_month,
        c.monthly_revenue,
        lag(c.monthly_revenue) over(order by c.year_month) as prev_monthly_revenue
    from cte_month_revenue c
)
select 
    c.year_month,
    c.monthly_revenue,
    c.prev_monthly_revenue,
    round((c.monthly_revenue - c.prev_monthly_revenue) / c.prev_monthly_revenue * 100, 2) as mom_growth
from cte_mon c
where c.prev_monthly_revenue is not null
order by c.year_month;

-- ------------------------------------------------------------------------------------------
-- Câu 3.2.3:
-- Theo dõi sự biến động đơn giá của sản phẩm (Price Volatility / Price Drift):
-- So sánh đơn giá của sản phẩm trong từng giao dịch với đơn giá ở lần bán liền trước đó 
-- của chính sản phẩm đó
-- để phát hiện các sản phẩm thường xuyên bị giảm giá hoặc tăng giá đột ngột.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.2.3 TẠI ĐÂY:


with cte_order_product as ( 
    select 
        orders.order_id,
        orders.order_purchase_timestamp,
        products.product_id,
        sum(items.price) as order_price -- ⚠️ SAI LOGIC: SUM(items.price) là TỔNG TIỀN, không phải ĐƠN GIÁ (Unit Price). Nếu mua số lượng > 1 sẽ bị tính sai % biến động giá.
    from dbo.olist_orders_dataset orders 
    inner join dbo.olist_order_items_dataset items 
        on items.order_id = orders.order_id
    inner join dbo.olist_products_dataset products on products.product_id = items.product_id -- 💡 DƯ THỪA: order_items đã có sẵn product_id, join thêm products làm chậm query.
    group by orders.order_id, orders.order_purchase_timestamp, products.product_id
),
cte_drift as (
    select 
        c.product_id,
        c.order_price,
        c.order_purchase_timestamp,
        lag(c.order_price) over (partition by c.product_id order by c.order_purchase_timestamp asc) as prev_order_price
    from cte_order_product c
)
select 
    c.product_id,
    c.order_purchase_timestamp,
    c.order_price,
    c.prev_order_price,
    round((c.order_price - c.prev_order_price) / nullif(c.prev_order_price,0) * 100, 2) as price_drift 
from cte_drift c
where c.prev_order_price is not null
order by c.product_id; -- 💡 NÊN BỔ SUNG: Thêm `c.order_purchase_timestamp asc` để xem đúng trình tự thời gian.


-- [BẢN CHUẨN HOÀN THIỆN]:
with cte_order_product as ( 
    select 
        orders.order_id,
        orders.order_purchase_timestamp,
        items.product_id,
        max(items.price) as unit_price  -- Lấy đúng ĐƠN GIÁ (Unit Price) của sản phẩm trong đơn
    from dbo.olist_orders_dataset orders 
    inner join dbo.olist_order_items_dataset items 
        on items.order_id = orders.order_id
    group by orders.order_id, orders.order_purchase_timestamp, items.product_id
),
cte_drift as (
    select 
        c.product_id,
        c.unit_price,
        c.order_purchase_timestamp,
        lag(c.unit_price) over (
            partition by c.product_id 
            order by c.order_purchase_timestamp asc
        ) as prev_unit_price
    from cte_order_product c
)
select 
    c.product_id,
    c.order_purchase_timestamp,
    c.unit_price,
    c.prev_unit_price,
    round((c.unit_price - c.prev_unit_price) / nullif(c.prev_unit_price, 0) * 100.0, 2) as price_drift_pct 
from cte_drift c
where c.prev_unit_price is not null
order by c.product_id, c.order_purchase_timestamp asc;



-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 3]: WINDOW AGGREGATION & TỶ TRỌNG ĐÓNG GÓP (SHARE OF TOTAL)
-- ------------------------------------------------------------------------------------------

-- Câu 3.3.1:
-- Tính tỷ trọng phần trăm đóng góp của từng sản phẩm trên tổng doanh thu của toàn bộ ngành hàng tương ứng:
-- Hiển thị thông tin từng sản phẩm, doanh thu sản phẩm, tổng doanh thu của ngành hàng đó,
-- và tỷ lệ % đóng góp của sản phẩm so với toàn ngành.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.1 TẠI ĐÂY:

with cte_pro_price as (
    select 
        products.product_category_name,
        products.product_id,
        sum(items.price) as product_revenue
    from dbo.olist_products_dataset products 
    inner join dbo.olist_order_items_dataset items on products.product_id = items.product_id
    where products.product_category_name is not null
    group by products.product_category_name, products.product_id

),
cte_total_rev as (
    select 
        c.product_category_name,
        c.product_id,
        c.product_revenue,
        sum(c.product_revenue) over(partition by c.product_category_name) as total_revenue
    from cte_pro_price c
)
select 
    c.product_category_name,
    c.product_id,
    c.product_revenue,
    c.total_revenue,
    round((c.product_revenue * 100.0 / c.total_revenue), 2) as share_of_total
from cte_total_rev c

-- ------------------------------------------------------------------------------------------
-- Câu 3.3.2:
-- So sánh giá trị của từng đơn hàng với mức chi tiêu trung bình của chính khách hàng đó:
-- Đánh dấu cờ phát hiện các đơn hàng có giá trị cao vượt trội (lớn hơn 1.5 lần mức chi tiêu trung bình của khách).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.2 TẠI ĐÂY:

;with cte_order_total as (
    select 
        customers.customer_unique_id,
        orders.order_id,
        sum(items.price) as order_price
    from dbo.olist_customers_dataset customers 
    inner join dbo.olist_orders_dataset orders on orders.customer_id = customers.customer_id
    inner join dbo.olist_order_items_dataset items on items.order_id = orders.order_id
    group by orders.order_id, customers.customer_unique_id
),
cte_avg_order as (
    select 
        c.customer_unique_id,
        c.order_id,
        c.order_price,
        avg(c.order_price) over(partition by c.customer_unique_id) as avg_order_price
    from cte_order_total c
)
select 
    customer_unique_id,
    order_id,
    order_price,
    round(avg_order_price, 2) as avg_order_price,
    case 
        when order_price > avg_order_price * 1.5 then 'High Value Order'
        else 'Normal Order'
    end as order_type
from cte_avg_order; 


-- ------------------------------------------------------------------------------------------
-- Câu 3.3.3:
-- Hiển thị chi tiết từng đơn hàng song song với các chỉ số tổng hợp cấp độ khu vực:
-- Với mỗi đơn hàng, hiển thị mã đơn, ngày mua, giá tiền kèm theo:
-- Tổng số đơn hàng của khách đó, và tổng số đơn hàng phát sinh trong toàn bộ thành phố của khách đó
-- mà không làm thu gọn số dòng (không dùng mệnh đề GROUP BY).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.3.3 TẠI ĐÂY:

with cte_order_details as (
    select 
        o.order_id,
        o.order_purchase_timestamp,
        c.customer_unique_id,
        c.customer_city,
        sum(i.price) as order_price
    from dbo.olist_orders_dataset o
    inner join dbo.olist_customers_dataset c 
        on o.customer_id = c.customer_id
    inner join dbo.olist_order_items_dataset i 
        on o.order_id = i.order_id
    group by o.order_id, o.order_purchase_timestamp, c.customer_unique_id, c.customer_city
)
select 
    order_id,
    order_purchase_timestamp,
    customer_unique_id,
    customer_city,
    order_price,
    -- Tổng số đơn hàng của chính khách hàng này (không làm mất chi tiết từng đơn):
    count(order_id) over (partition by customer_unique_id) as total_customer_orders,
    -- Tổng số đơn hàng của toàn bộ thành phố nơi khách hàng sinh sống:
    count(order_id) over (partition by customer_city) as total_city_orders
from cte_order_details
order by customer_city, customer_unique_id, order_purchase_timestamp;
-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 4]: CUMULATIVE AGGREGATION & RUNNING TOTALS (TÍNH TỔNG TÍCH LŨY DỒN)
-- ------------------------------------------------------------------------------------------

-- Câu 3.4.1:
-- Tính tổng doanh thu tích lũy lũy kế theo từng ngày trong năm 2017 (Year-to-Date Running Total):
-- Hiển thị từng ngày trong năm, doanh thu phát sinh trong ngày, và tổng doanh thu cộng dồn
-- từ ngày đầu năm 01/01/2017 tính đến ngày đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.1 TẠI ĐÂY:

with daily_rev as (
    select 
        cast(o.order_purchase_timestamp as date) as order_date,
        sum(i.price) as daily_revenue
    from dbo.olist_orders_dataset o
    inner join dbo.olist_order_items_dataset i 
        on o.order_id = i.order_id
    where o.order_purchase_timestamp >= '2017-01-01' 
      and o.order_purchase_timestamp < '2018-01-01'
    group by cast(o.order_purchase_timestamp as date)
)
select 
    order_date,
    daily_revenue,
    sum(daily_revenue) over (
        order by order_date asc
        rows between unbounded preceding and current row
    ) as running_total_ytd
from daily_rev
order by order_date;

-- ------------------------------------------------------------------------------------------
-- Câu 3.4.2:
-- Theo dõi ngưỡng chi tiêu tích lũy của từng khách hàng:
-- Tại mỗi đơn hàng mà khách thực hiện, tính tổng số tiền mà khách hàng đó đã tích lũy chi tiêu
-- kể từ đơn hàng đầu tiên cho đến thời điểm hiện tại.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.2 TẠI ĐÂY:

with cte_cust_orders as (
    select 
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        sum(i.price) as order_value
    from dbo.olist_customers_dataset c
    inner join dbo.olist_orders_dataset o 
        on c.customer_id = o.customer_id
    inner join dbo.olist_order_items_dataset i 
        on o.order_id = i.order_id
    group by c.customer_unique_id, o.order_id, o.order_purchase_timestamp
)
select 
    customer_unique_id,
    order_id,
    order_purchase_timestamp,
    order_value,
    sum(order_value) over (
        partition by customer_unique_id 
        order by order_purchase_timestamp asc, order_id asc
        rows between unbounded preceding and current row
    ) as cumulative_spending
from cte_cust_orders
order by customer_unique_id, order_purchase_timestamp;

-- ------------------------------------------------------------------------------------------
-- Câu 3.4.3:
-- Đếm số lượng đơn hàng tích lũy lũy kế qua từng ngày trong tháng 08/2017 để theo dõi tiến độ
-- hoàn thành chỉ tiêu kinh doanh của tháng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.4.3 TẠI ĐÂY:

with daily_orders as (
    select 
        cast(o.order_purchase_timestamp as date) as order_date,
        count(distinct o.order_id) as daily_order_count
    from dbo.olist_orders_dataset o
    where o.order_purchase_timestamp >= '2017-08-01' 
      and o.order_purchase_timestamp < '2017-09-01'
    group by cast(o.order_purchase_timestamp as date)
)
select 
    order_date,
    daily_order_count,
    sum(daily_order_count) over (
        order by order_date asc
        rows between unbounded preceding and current row
    ) as running_total_orders
from daily_orders
order by order_date;
-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 5]: WINDOW FRAMES & ĐƯỜNG TRUNG BÌNH TRƯỢT (MOVING AVERAGES)
-- ------------------------------------------------------------------------------------------

-- Câu 3.5.1:
-- Xây dựng đường trung bình trượt 7 ngày (7-Day Moving Average) cho doanh thu hàng ngày:
-- Doanh thu mỗi ngày thường biến động mạnh giữa các ngày trong tuần và cuối tuần.
-- Hãy tính đường trung bình trượt 7 ngày (bao gồm ngày hiện tại và 6 ngày trước đó) để làm mịn xu hướng doanh thu.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.1 TẠI ĐÂY:

with daily_revenue as (
    select 
        cast(o.order_purchase_timestamp as date) as order_date,
        sum(i.price) as revenue
    from dbo.olist_orders_dataset o
    inner join dbo.olist_order_items_dataset i 
        on o.order_id = i.order_id
    group by cast(o.order_purchase_timestamp as date)
)
select 
    order_date,
    revenue,
    round(avg(revenue * 1.0) over (
        order by order_date asc
        rows between 6 preceding and current row
    ), 2) as moving_avg_7d
from daily_revenue
order by order_date;

-- ------------------------------------------------------------------------------------------
-- Câu 3.5.2:
-- Áp dụng khung cửa sổ đối xứng (Centered Moving Frame):
-- Tính giá trị trung bình trượt doanh thu của khung gồm 3 ngày: 1 ngày trước đó, ngày hiện tại và 1 ngày tiếp theo.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.2 TẠI ĐÂY:

with daily_revenue as (
    select 
        cast(o.order_purchase_timestamp as date) as order_date,
        sum(i.price) as revenue
    from dbo.olist_orders_dataset o
    inner join dbo.olist_order_items_dataset i 
        on o.order_id = i.order_id
    group by cast(o.order_purchase_timestamp as date)
)
select 
    order_date,
    revenue,
    round(avg(revenue * 1.0) over (
        order by order_date asc
        rows between 1 preceding and 1 following
    ), 2) as centered_moving_avg_3d
from daily_revenue
order by order_date;

-- ------------------------------------------------------------------------------------------
-- Câu 3.5.3:
-- Theo dõi phong độ bán hàng gần nhất của Người bán:
-- Với mỗi đơn hàng của người bán, tính tổng doanh thu và cước phí trung bình của 3 đơn hàng gần đây nhất
-- mà người bán đó đã phục vụ.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.5.3 TẠI ĐÂY:

with seller_orders as (
    select 
        i.seller_id,
        o.order_id,
        o.order_purchase_timestamp,
        sum(i.price) as order_revenue,
        sum(i.freight_value) as order_freight
    from dbo.olist_order_items_dataset i
    inner join dbo.olist_orders_dataset o 
        on i.order_id = o.order_id
    group by i.seller_id, o.order_id, o.order_purchase_timestamp
)
select 
    seller_id,
    order_id,
    order_purchase_timestamp,
    order_revenue,
    order_freight,
    -- Tổng doanh thu của 3 đơn gần nhất (2 đơn trước + đơn này):
    sum(order_revenue) over (
        partition by seller_id 
        order by order_purchase_timestamp asc, order_id asc
        rows between 2 preceding and current row
    ) as rolling_3_orders_revenue,
    -- Cước phí trung bình của 3 đơn gần nhất:
    round(avg(order_freight * 1.0) over (
        partition by seller_id 
        order by order_purchase_timestamp asc, order_id asc
        rows between 2 preceding and current row
    ), 2) as rolling_3_orders_avg_freight
from seller_orders
order by seller_id, order_purchase_timestamp;
-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 6]: PHÂN TÁCH PHIÊN & PHÁT HIỆN KHOẢNG TRỐNG (SESSIONIZATION & GAPS)
-- ------------------------------------------------------------------------------------------

-- Câu 3.6.1:
-- Bài toán Sessionization:
-- Nếu một khách hàng đặt nhiều đơn hàng mà mỗi đơn cách nhau không quá 24 giờ, ta coi chúng thuộc cùng 1 "phiên mua sắm".
-- Nếu khoảng cách vượt quá 24 giờ, phiên mới sẽ được mở ra.
-- Hãy gán số Session ID phân biệt cho từng phiên mua sắm của khách hàng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.1 TẠI ĐÂY:

with lagged_orders as (
    select 
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        lag(o.order_purchase_timestamp) over (
            partition by c.customer_unique_id 
            order by o.order_purchase_timestamp asc
        ) as prev_order_time
    from dbo.olist_customers_dataset c
    inner join dbo.olist_orders_dataset o 
        on c.customer_id = o.customer_id
),
session_flags as (
    select 
        customer_unique_id,
        order_id,
        order_purchase_timestamp,
        prev_order_time,
        case 
            when prev_order_time is null or datediff(hour, prev_order_time, order_purchase_timestamp) > 24 
            then 1 
            else 0 
        end as is_new_session
    from lagged_orders
)
select 
    customer_unique_id,
    order_id,
    order_purchase_timestamp,
    prev_order_time,
    sum(is_new_session) over (
        partition by customer_unique_id 
        order by order_purchase_timestamp asc
        rows between unbounded preceding and current row
    ) as session_id
from session_flags
order by customer_unique_id, order_purchase_timestamp;

-- ------------------------------------------------------------------------------------------
-- Câu 3.6.2:
-- Bắt lỗi đứt gãy dữ liệu (Data Pipeline Gaps Detection):
-- Kiểm tra xem trong toàn bộ lịch sử đơn hàng có khoảng thời gian nào kéo dài trên 3 ngày liên tiếp
-- mà hệ thống không ghi nhận bất kỳ đơn hàng nào phát sinh hay không (nghi vấn lỗi sập pipeline ghi nhận).
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.2 TẠI ĐÂY:

with distinct_order_dates as (
    select distinct 
        cast(order_purchase_timestamp as date) as order_date
    from dbo.olist_orders_dataset
    where order_purchase_timestamp is not null
),
date_gaps as (
    select 
        order_date,
        lag(order_date) over (order by order_date asc) as prev_order_date
    from distinct_order_dates
)
select 
    prev_order_date as gap_start_date,
    order_date as gap_end_date,
    datediff(day, prev_order_date, order_date) as days_gap
from date_gaps
where datediff(day, prev_order_date, order_date) > 3
order by gap_start_date;

-- ------------------------------------------------------------------------------------------
-- Câu 3.6.3:
-- Chuỗi hoạt động liên tiếp (Customer Retention Streak):
-- Tìm các khách hàng có lịch sử đặt hàng đều đặn qua các tháng liên tiếp nhau mà không bị ngắt quãng.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.6.3 TẠI ĐÂY:

with cust_active_months as (
    select distinct 
        c.customer_unique_id,
        year(o.order_purchase_timestamp) as yr,
        month(o.order_purchase_timestamp) as mn,
        (year(o.order_purchase_timestamp) * 12 + month(o.order_purchase_timestamp)) as month_idx
    from dbo.olist_customers_dataset c
    inner join dbo.olist_orders_dataset o 
        on c.customer_id = o.customer_id
    where o.order_purchase_timestamp is not null
),
numbered_months as (
    select 
        customer_unique_id,
        yr,
        mn,
        month_idx,
        row_number() over (
            partition by customer_unique_id 
            order by month_idx asc
        ) as rn
    from cust_active_months
),
streak_groups as (
    select 
        customer_unique_id,
        (month_idx - rn) as streak_group,
        count(*) as consecutive_months_count,
        min(cast(cast(yr as varchar) + '-' + right('0' + cast(mn as varchar), 2) + '-01' as date)) as streak_start,
        max(cast(cast(yr as varchar) + '-' + right('0' + cast(mn as varchar), 2) + '-01' as date)) as streak_end
    from numbered_months
    group by customer_unique_id, (month_idx - rn)
)
select 
    customer_unique_id,
    consecutive_months_count,
    streak_start,
    streak_end
from streak_groups
where consecutive_months_count >= 2
order by consecutive_months_count desc, customer_unique_id;
-- ------------------------------------------------------------------------------------------
-- [P3 - NGÀY 7]: TỔNG HỢP ANALYTICAL FEATURE STORE CHO BI & MACHINE LEARNING
-- ------------------------------------------------------------------------------------------

-- Câu 3.7.1:
-- Xây dựng bảng đặc trưng khách hàng phục vụ mô hình phân nhóm RFM (Recency, Frequency, Monetary):
-- Tính toán song song cho từng khách hàng:
-- - Số ngày kể từ lần mua gần nhất đến mốc chốt dữ liệu (Recency)
-- - Tổng số đơn hàng (Frequency)
-- - Tổng số tiền chi tiêu (Monetary)
-- - Giá trị đơn hàng trung bình
-- - Xếp hạng chi tiêu của khách hàng so với toàn bộ khách hàng khác trên hệ thống.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.1 TẠI ĐÂY:

with max_system_date as (
    select max(order_purchase_timestamp) as snapshot_date
    from dbo.olist_orders_dataset
),
customer_orders as (
    select 
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        sum(i.price) as order_value
    from dbo.olist_customers_dataset c
    inner join dbo.olist_orders_dataset o 
        on c.customer_id = o.customer_id
    inner join dbo.olist_order_items_dataset i 
        on o.order_id = i.order_id
    group by c.customer_unique_id, o.order_id, o.order_purchase_timestamp
),
rfm_agg as (
    select 
        co.customer_unique_id,
        datediff(day, max(co.order_purchase_timestamp), (select snapshot_date from max_system_date)) as recency_days,
        count(distinct co.order_id) as frequency_orders,
        sum(co.order_value) as monetary_total_spend,
        round(avg(co.order_value * 1.0), 2) as avg_order_value
    from customer_orders co
    group by co.customer_unique_id
)
select 
    customer_unique_id,
    recency_days,
    frequency_orders,
    monetary_total_spend,
    avg_order_value,
    rank() over (order by monetary_total_spend desc) as monetary_rank,
    percent_rank() over (order by monetary_total_spend desc) as monetary_percentile
from rfm_agg
order by monetary_rank asc;

-- ------------------------------------------------------------------------------------------
-- Câu 3.7.2:
-- Phát hiện giao dịch bất thường (Anomaly Detection):
-- Gắn cờ cảnh báo đối với các đơn hàng có giá trị đột biến cao gấp 3 lần mức trung bình của toàn ngành hàng
-- hoặc cước phí cao gấp 3 lần cước phí trung bình của cùng tuyến đường.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.2 TẠI ĐÂY:

with item_details as (
    select 
        o.order_id,
        i.order_item_id,
        i.product_id,
        p.product_category_name,
        c.customer_state,
        s.seller_state,
        concat(s.seller_state, ' - ', c.customer_state) as shipping_route,
        i.price,
        i.freight_value,
        avg(i.price) over (partition by p.product_category_name) as avg_category_price,
        avg(i.freight_value) over (partition by s.seller_state, c.customer_state) as avg_route_freight
    from dbo.olist_order_items_dataset i
    inner join dbo.olist_orders_dataset o on i.order_id = o.order_id
    inner join dbo.olist_customers_dataset c on o.customer_id = c.customer_id
    inner join dbo.olist_sellers_dataset s on i.seller_id = s.seller_id
    left join dbo.olist_products_dataset p on i.product_id = p.product_id
)
select 
    order_id,
    order_item_id,
    product_category_name,
    shipping_route,
    price,
    round(avg_category_price, 2) as avg_category_price,
    freight_value,
    round(avg_route_freight, 2) as avg_route_freight,
    case 
        when price > 3 * avg_category_price and freight_value > 3 * avg_route_freight 
            then 'Both High Price & High Freight'
        when price > 3 * avg_category_price 
            then 'High Price Anomaly'
        when freight_value > 3 * avg_route_freight 
            then 'High Freight Anomaly'
        else 'Normal'
    end as anomaly_flag
from item_details
where price > 3 * avg_category_price or freight_value > 3 * avg_route_freight
order by price desc;

-- ------------------------------------------------------------------------------------------
-- Câu 3.7.3:
-- Đóng gói thành View phân tích hoạt động Người bán _seller_performance_analytics:
-- Tổng hợp cho từng người bán: Doanh thu lũy kế, Xếp hạng trong bang, Tỷ trọng đóng góp doanh thu cho bang,
-- và độ lệch thời gian bàn giao hàng so với mức trung bình của bang đó.
-- ------------------------------------------------------------------------------------------
-- VIẾT QUERY CÂU 3.7.3 TẠI ĐÂY:

-- create or alter view dbo.v_seller_performance_analytics as
with seller_orders as (
    select 
        s.seller_id,
        s.seller_state,
        sum(i.price) as seller_revenue,
        avg(datediff(day, o.order_purchase_timestamp, o.order_delivered_carrier_date) * 1.0) as avg_handover_days
    from dbo.olist_sellers_dataset s
    inner join dbo.olist_order_items_dataset i on s.seller_id = i.seller_id
    inner join dbo.olist_orders_dataset o on i.order_id = o.order_id
    where o.order_delivered_carrier_date is not null
    group by s.seller_id, s.seller_state
),
state_metrics as (
    select 
        so.seller_id,
        so.seller_state,
        so.seller_revenue,
        so.avg_handover_days,
        sum(so.seller_revenue) over (partition by so.seller_state) as state_total_revenue,
        avg(so.avg_handover_days) over (partition by so.seller_state) as state_avg_handover_days,
        rank() over (partition by so.seller_state order by so.seller_revenue desc) as rank_in_state
    from seller_orders so
)
select 
    seller_id,
    seller_state,
    seller_revenue,
    rank_in_state,
    round(seller_revenue * 100.0 / nullif(state_total_revenue, 0), 2) as revenue_share_in_state_pct,
    round(avg_handover_days, 2) as seller_avg_handover_days,
    round(state_avg_handover_days, 2) as state_avg_handover_days,
    round(avg_handover_days - state_avg_handover_days, 2) as handover_variance_vs_state
from state_metrics;
go
