# 🎮 Digital Game Store & In-Game Items Data Warehouse (GameStoreDW)

[![SQL Server](https://img.shields.io/badge/RDBMS-SQL%20Server-red.svg)](https://www.microsoft.com/sql-server)
[![SSIS](https://img.shields.io/badge/ETL-SSIS%20%7C%20Kettle-orange.svg)]()
[![SSAS](https://img.shields.io/badge/OLAP-SSAS%20%7C%20Mondrian-blue.svg)]()
[![Methodology](https://img.shields.io/badge/Methodology-Vaisman%20%26%20Zimányi-green.svg)]()
[![Institution](https://img.shields.io/badge/University-VKU-blueviolet.svg)]()

> **Đồ án môn học Kho dữ liệu (Data Warehouse)**  
> **Đề tài:** Kho dữ liệu Phân tích Doanh thu Cửa hàng Game & Vật phẩm Ảo (*Digital Game Store & In-Game Items Data Warehouse*)  
> **Phương pháp luận:** Tuân thủ chuẩn 6 giai đoạn giáo trình *"Data Warehouse Systems: Design and Implementation"* (Alejandro Vaisman & Esteban Zimányi) — Khoa Khoa học Máy tính, Trường Đại học Công nghệ Thông tin và Truyền thông Việt - Hàn (VKU).

---

## 📌 Tổng quan Dự án

Hệ thống **GameStoreDW** giải quyết bài toán phân tích doanh thu đa chiều cho hai luồng kinh doanh cốt lõi trong ngành công nghiệp game hiện đại:
1. **Fact 1: `FactGameSales`** — Doanh thu bán Game bản quyền và các gói mở rộng DLC (*Diablo IV, Elden Ring, Cyberpunk 2077, Forza Horizon 5...*).
2. **Fact 2: `FactItemTransactions`** — Doanh thu nền kinh tế vật phẩm ảo Live-Ops (*CS2 Armory Pass, Case Keys, Dao Karambit Doppler, Dota 2 Arcana...*).

### 🌟 Điểm nổi bật về mặt Học thuật & Kỹ thuật
* **Lược đồ Constellation (Fact Constellation / Starflake Schema):** 2 Fact dùng chung các Conformed Dimensions.
* **Đầy đủ 6 loại Hierarchy:**
  - *Balanced:* Chiều Thời gian (`Date -> Month -> Quarter -> Semester -> Year`) và Danh mục sản phẩm (`Item -> SubCategory -> Category -> Department`).
  - *Alternative:* Chiều Thời gian song song hai nhánh **Calendar Year** và **Fiscal Year** (bắt đầu từ tháng 2).
  - *Parallel:* Chiều Game có 2 phân cấp độc lập (`Categories` và `GameEngine -> EngineVendor`).
  - *Parent-Child / Unbalanced:* Cây phân cấp đệ quy Studio mẹ – Studio con (`Publisher`), hỗ trợ bảng bao đóng bắc cầu **`DimPublisherClosure`** và hàm MDX **`.DATAMEMBER`**.
  - *Ragged / Generalized Hierarchy:* Cây địa lý khuyết cấp Bang (`City -> State (0,1) -> Country -> Continent`), kiểm soát bằng **XOR CHECK Constraint** và thuộc tính SSAS **`HideMemberIf = OnlyChildWithNoName`**.
  - *Nonstrict Many-to-Many:* Một tựa Game thuộc nhiều Thể loại (`Genre`), phân bổ bằng thuộc tính trọng số **`WeightFactor ÷`** (tổng trọng số $= 1.0$) để loại bỏ lỗi cộng trùng (*Double-Counting*).
* **Quản lý lịch sử SCD (Type 1 đến Type 7):** Triển khai đồng thời **SCD Type 2 & Type 6** trên `DimPlayer` kết hợp **Mini-dimension SCD Type 4/5** (`DimPlayerProfile`).
* **Quy trình ETL chuẩn BPMN 2.0:** Triển khai trên **Microsoft SSIS** (Cascading Lookups, Sequence Container, Data Conversion, XML Source, Window Framing) và đối sánh với **Pentaho Kettle** (Closure Generator, XPath, Dummy parallel step, Sort + Unique).
* **Truy vấn Đa chiều chuyên sâu:** Bộ 14 câu truy vấn **MDX** (Time Series YTD, ParallelPeriod, Moving Average, Set Top 3 vs Other) và 14 câu truy vấn **SQL/OLAP** (`ROLLUP`, `CUBE`, `GROUPING SETS`, Window Partitioning/Ordering/Framing).
* **Thiết kế Vật lý & Tối ưu hóa:**
  - SQL Server: **Indexed Views (`WITH SCHEMABINDING`, `NOEXPAND`)**, **Partition Function (`PartByYear`)**, **Partition-Aligned Indexed View**, và **Nonclustered Columnstore Index**.
  - SSAS: Phân vùng theo năm với 3 chế độ lưu trữ **MOLAP (2024)**, **HOLAP (2025)**, **ROLAP (2026)** (tuân thủ 5 quy tắc ROLAP) và cấu hình **`AggregationUsage`**.
  - Mondrian: File XML Schema 4.0 và cấu hình **Aggregate Tables**.

---

## 📂 Cấu trúc Thư mục Repository

```bash
├── 01_Create_GameStoreOLTP.sql         # Kịch bản DDL/DML tạo CSDL tác nghiệp chuẩn 3NF GameStoreOLTP
├── 02_Create_GameStoreDW.sql           # Kịch bản DDL tạo Kho dữ liệu GameStoreDW (Constellation Schema)
├── 03_MockData_ETL_Load.sql            # Sinh 10.000+ giao dịch & chạy toàn bộ pipeline ETL nạp vào DW
├── 04_SQL_OLAP_and_MDX_Queries.sql     # Bộ 14 câu MDX (SSAS/Mondrian) & 14 câu SQL/OLAP (SQL Server)
├── 05_Physical_Design_Tuning.sql       # Indexed Views, Range Partitioning theo năm & Columnstore Index
├── 06_Mondrian_GameStoreDW_Schema.xml  # File XML Schema định nghĩa Cube trong Pentaho Mondrian
├── GameStoreDW_Full_Report.md          # Tài liệu thuyết minh toàn diện 6 giai đoạn đồ án (Markdown)
├── GameStoreDW_Project_Tables.xlsx     # File Excel 8 bảng chuẩn định dạng sẵn để copy-paste vào Slide
├── KHO_GKI_GameStoreDW_RutGon.pptx     # File PowerPoint 18 slides tinh gọn phục vụ bảo vệ (10-15 phút)
├── KHO_GKI_GameStoreDW.pptx            # File PowerPoint 47 slides chi tiết theo mẫu chuẩn
├── data/                               # Dữ liệu ngoại vi phục vụ quy trình ETL
│   ├── Cities.txt                      # Tab-delimited text chứa danh sách thành phố có/khuyết bang
│   ├── Territories.xml                 # XML Schema cây địa lý Continent -> Country -> State
│   └── Time.csv                        # CSV dữ liệu thời gian Calendar & Fiscal
└── README.md                           # Hướng dẫn chi tiết & kịch bản demo chấm đồ án
```

---

## 🚀 Hướng dẫn Cài đặt & Chạy Thực thi (Fast Track)

### Bước 1: Khởi tạo CSDL Nguồn & Kho dữ liệu
Mở **SQL Server Management Studio (SSMS)** và thực thi lần lượt:
1. Mở file `01_Create_GameStoreOLTP.sql` $\rightarrow$ Nhấn **Execute** (Tạo CSDL nguồn 3NF).
2. Mở file `02_Create_GameStoreDW.sql` $\rightarrow$ Nhấn **Execute** (Tạo Kho dữ liệu `GameStoreDW` với các ràng buộc khóa và XOR Check).

### Bước 2: Nạp Dữ liệu & Chạy ETL Tự động
1. Mở file `03_MockData_ETL_Load.sql` $\rightarrow$ Nhấn **Execute**.
   - Script tự động sinh hơn 10.000 dòng giao dịch thực tế vào `GameStoreOLTP`.
   - Tự động thực thi toàn bộ logic ETL (Time Generator, Geography Lookup, SCD 2/6 Versioning, Fact Window Function).
   - Kiểm tra kết quả đếm dòng ở cuối script (bảng tổng hợp dòng của Fact và các Dim).

### Bước 3: Chạy Truy vấn Phân tích & Tối ưu hóa Vật lý
1. Mở file `04_SQL_OLAP_and_MDX_Queries.sql` $\rightarrow$ Chạy các câu truy vấn SQL/OLAP để kiểm tra kết quả phân tích đa chiều.
2. Mở file `05_Physical_Design_Tuning.sql` $\rightarrow$ Nhấn **Execute** để tạo Indexed Views, Phân vùng Fact theo năm và tạo Columnstore Index.

---

## 👨‍🏫 Kịch bản Demo Sản phẩm khi Chấm Đồ án (5 - 7 Phút)

Khi giảng viên yêu cầu mở máy demo sản phẩm, hãy thực hiện theo đúng 4 bước trình diễn sau:

1. **Demo Kiến trúc CSDL & Ràng buộc toàn vẹn (SSMS - 1.5 phút):**
   - Mở Object Explorer trong SSMS $\rightarrow$ Mở `GameStoreDW` $\rightarrow$ Mở `Tables`.
   - Cho thầy xem hai bảng Fact: `FactGameSales` và `FactItemTransactions` (minh chứng **Constellation Schema**).
   - Mở bảng `DimCity` $\rightarrow$ `Constraints`: Chỉ cho thầy xem 2 ràng buộc `CK_DimCity_WithStateFK` và `CK_DimCity_DirectCountryFK` (minh chứng xử lý học thuật chuẩn cho **Ragged Geography XOR**).
   - Mở bảng `DimPlayer`: Select 10 dòng của người chơi `PL-001` để thầy thấy 2 phiên bản `HistoricalVIPLevel` (Gold $\rightarrow$ Diamond), `StartDate`, `EndDate`, `IsCurrent` (minh chứng **SCD Type 2 & Type 6**).

2. **Demo Dữ liệu & Pipeline ETL (SSMS / SSIS - 1.5 phút):**
   - Chạy truy vấn đếm dòng ở cuối script `03_MockData_ETL_Load.sql` để thầy thấy số lượng hơn 10.000 dòng dữ liệu thực tế.
   - Trình bày sơ đồ BPMN 2.0 trong file báo cáo hoặc mở gói SSIS Package: Chỉ rõ luồng xử lý `Cascading Lookups` và hàm cửa sổ `ROW_NUMBER() OVER (PARTITION BY OrderID)`.

3. **Demo Truy vấn Phân tích Đa chiều (SSMS / SSAS - 2 phút):**
   - Mở file `04_SQL_OLAP_and_MDX_Queries.sql`:
     - Chạy **Query [SQL 08]**: Demo tính trung bình trượt 3 tháng (`ROWS 2 PRECEDING`) và lũy kế đầu năm `CumulativeYTD`.
     - Chạy **Query [SQL 11]**: Giải thích cho thầy thấy cột `UnweightedGenreSales` (bị cộng trùng do game đa thể loại) so sánh với cột `WeightedGenreSales_NoDoubleCount` (sau khi nhân `WeightFactor ÷` đã loại bỏ hoàn toàn sai số).
     - Chạy **Query [SQL 12]**: Demo đệ quy Parent-Child qua bảng bao đóng `DimPublisherClosure` (tách doanh thu riêng `Distance = 0` so với tổng toàn bộ cây con).

4. **Demo Tối ưu hóa Vật lý & Phân vùng (SSMS - 1 phút):**
   - Mở file `05_Physical_Design_Tuning.sql`:
     - Chạy câu lệnh kiểm tra phân vùng `sys.partitions`: Cho thầy thấy Fact được chia đều vào 3 phân vùng năm `Sales_2024`, `Sales_2025`, `Sales_2026`.
     - Chạy truy vấn với gợi ý `WITH (NOEXPAND)` trên `vw_GameSalesSummary`: Bật **Include Actual Execution Plan** (`Ctrl + M`) để chứng minh Query Optimizer đọc thẳng từ Clustered Index của View mà không cần đụng đến bảng Fact.

---
**Tác giả:** Group 07 — VKU (Vietnam - Korea University of Information and Communication Technology).  
**Giấy phép:** MIT License.
