-- =============================================================================
-- FILE: 05_Physical_Design_Tuning.sql
-- PROJECT: Digital Game Store & In-Game Items Data Warehouse
-- METHODOLOGY: Vaisman & Zimanyi (Chapter 5 Physical Data Warehouse Design)
-- DESCRIPTION:
--   1. Materialized / Indexed Views (WITH SCHEMABINDING + UNIQUE CLUSTERED INDEX)
--      and querying with WITH (NOEXPAND) (Chapter 5 Slide 25-26).
--   2. Range Partitioning by Year (PARTITION FUNCTION PartByYear & PARTITION SCHEME
--      SalesPartScheme) (Chapter 5 Slide 27-28).
--   3. Partitioned Fact Table & Partition-Aligned Indexed View (Chapter 5 Slide 28).
--   4. Nonclustered Columnstore Index for vertical partitioning / vector compression
--      (Chapter 5 Slide 29).
-- =============================================================================

USE GameStoreDW;
GO

SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
SET NUMERIC_ROUNDABORT OFF;
GO

-- =============================================================================
-- 1. INDEXED VIEW (SUMMARY TABLE) OVER FACTGAMESALES (Chapter 5 Slide 25-26)
--    Precomputes and materializes daily game sales per Date, Game, and Player
-- =============================================================================
IF OBJECT_ID('dbo.vw_GameSalesSummary', 'V') IS NOT NULL
    DROP VIEW dbo.vw_GameSalesSummary;
GO

CREATE VIEW dbo.vw_GameSalesSummary
WITH SCHEMABINDING
AS
SELECT
    f.PurchaseDateKey,
    f.GameKey,
    f.PublisherKey,
    SUM(f.Quantity)         AS TotalQuantity,
    SUM(f.GrossSalesAmount) AS TotalGrossSales,
    SUM(f.TaxAmount)        AS TotalTaxAmount,
    SUM(f.NetSalesAmount)   AS TotalNetSales,
    COUNT_BIG(*)            AS SalesRowCount -- Required by SQL Server for Indexed Views with GROUP BY
FROM dbo.FactGameSales f
GROUP BY
    f.PurchaseDateKey,
    f.GameKey,
    f.PublisherKey;
GO

CREATE UNIQUE CLUSTERED INDEX UCI_vw_GameSalesSummary
ON dbo.vw_GameSalesSummary (PurchaseDateKey, GameKey, PublisherKey);
GO

-- Querying the Indexed View explicitly with WITH (NOEXPAND) hint (Chapter 5 Slide 26):
SELECT
    t.[Year],
    g.GameTitle,
    pub.PublisherName,
    SUM(v.TotalQuantity)   AS UnitsSold,
    SUM(v.TotalNetSales)   AS NetRevenue,
    SUM(v.SalesRowCount)   AS FactLinesAggregated
FROM dbo.vw_GameSalesSummary v WITH (NOEXPAND)
INNER JOIN dbo.DimTime t        ON v.PurchaseDateKey = t.TimeKey
INNER JOIN dbo.DimGame g        ON v.GameKey         = g.GameKey
INNER JOIN dbo.DimPublisher pub ON v.PublisherKey    = pub.PublisherKey
GROUP BY t.[Year], g.GameTitle, pub.PublisherName
ORDER BY t.[Year], NetRevenue DESC;
GO

-- =============================================================================
-- 2. HORIZONTAL RANGE PARTITIONING BY YEAR & PARTITION-ALIGNED INDEXED VIEW
--    (Chapter 5 Slide 27-28)
-- =============================================================================
IF OBJECT_ID('dbo.vw_PartSalesByDateGamePub', 'V') IS NOT NULL
    DROP VIEW dbo.vw_PartSalesByDateGamePub;
IF OBJECT_ID('dbo.FactGameSales_Partitioned', 'U') IS NOT NULL
    DROP TABLE dbo.FactGameSales_Partitioned;
IF EXISTS (SELECT * FROM sys.partition_schemes WHERE name = 'SalesPartScheme')
    DROP PARTITION SCHEME SalesPartScheme;
IF EXISTS (SELECT * FROM sys.partition_functions WHERE name = 'PartByYear')
    DROP PARTITION FUNCTION PartByYear;
GO

-- Create Partition Function using YYYYMMDD integer TimeKey boundaries for 2024, 2025, 2026
CREATE PARTITION FUNCTION [PartByYear] (INT)
AS RANGE LEFT FOR VALUES (20241231, 20251231, 20261231);
GO

-- Create Partition Scheme mapping all partitions to [PRIMARY] filegroup (Chapter 5 Slide 27)
CREATE PARTITION SCHEME [SalesPartScheme]
AS PARTITION [PartByYear] ALL TO ([PRIMARY]);
GO

-- Create the Partitioned Fact Table aligned on PurchaseDateKey (Chapter 5 Slide 28)
CREATE TABLE dbo.FactGameSales_Partitioned (
    PlayerKey        INT           NOT NULL,
    GameKey          INT           NOT NULL,
    PublisherKey     INT           NOT NULL,
    PurchaseDateKey  INT           NOT NULL,
    ReleaseDateKey   INT           NOT NULL,
    RefundDateKey    INT           NULL,
    PaymentMethodKey INT           NOT NULL,
    OrderNo          INT           NOT NULL,
    OrderLineNo      INT           NOT NULL,
    Quantity         INT           NOT NULL,
    UnitPrice        DECIMAL(10,2) NOT NULL,
    Discount         DECIMAL(5,4)  NOT NULL,
    GrossSalesAmount DECIMAL(12,2) NOT NULL,
    TaxAmount        DECIMAL(10,2) NOT NULL,
    NetSalesAmount   DECIMAL(12,2) NOT NULL,
    CONSTRAINT PK_FactGameSales_Partitioned PRIMARY KEY CLUSTERED (PurchaseDateKey, OrderNo, OrderLineNo)
        ON [SalesPartScheme](PurchaseDateKey)
) ON [SalesPartScheme](PurchaseDateKey);
GO

-- Populate Partitioned Fact Table from FactGameSales
INSERT INTO dbo.FactGameSales_Partitioned
SELECT
    PlayerKey, GameKey, PublisherKey, PurchaseDateKey, ReleaseDateKey, RefundDateKey,
    PaymentMethodKey, OrderNo, OrderLineNo, Quantity, UnitPrice, Discount,
    GrossSalesAmount, TaxAmount, NetSalesAmount
FROM dbo.FactGameSales;
GO

-- Create Partition-Aligned Indexed View on the Partitioned Fact Table (Chapter 5 Slide 28)
CREATE VIEW dbo.vw_PartSalesByDateGamePub
WITH SCHEMABINDING
AS
SELECT
    PurchaseDateKey,
    GameKey,
    PublisherKey,
    COUNT_BIG(*)          AS Cnt,
    SUM(Quantity)         AS TotalQty,
    SUM(GrossSalesAmount) AS GrossSalesAmount,
    SUM(NetSalesAmount)   AS NetSalesAmount
FROM dbo.FactGameSales_Partitioned
GROUP BY PurchaseDateKey, GameKey, PublisherKey;
GO

CREATE UNIQUE CLUSTERED INDEX UCI_vw_PartSalesByDateGamePub
ON dbo.vw_PartSalesByDateGamePub (PurchaseDateKey, GameKey, PublisherKey)
ON [SalesPartScheme](PurchaseDateKey);
GO

-- Verify Partition Distribution across 2024 (Partition 1), 2025 (Partition 2), 2026 (Partition 3)
SELECT
    p.partition_number AS PartitionNumber,
    CASE p.partition_number
        WHEN 1 THEN 'Sales_2024 (<= 20241231)'
        WHEN 2 THEN 'Sales_2025 (20250101 - 20251231)'
        WHEN 3 THEN 'Sales_2026 (20260101 - 20261231)'
        ELSE 'Sales_Future (> 20261231)'
    END AS PartitionSliceDescription,
    p.rows AS FactRowCount
FROM sys.partitions p
WHERE p.object_id = OBJECT_ID('dbo.FactGameSales_Partitioned')
  AND p.index_id = 1
ORDER BY p.partition_number;
GO

-- =============================================================================
-- 3. NONCLUSTERED COLUMNSTORE INDEX (Chapter 5 Slide 29)
-- =============================================================================
CREATE NONCLUSTERED COLUMNSTORE INDEX CSI_FactGameSales
ON dbo.FactGameSales (
    PurchaseDateKey,
    ReleaseDateKey,
    PlayerKey,
    GameKey,
    PublisherKey,
    PaymentMethodKey,
    Quantity,
    UnitPrice,
    Discount,
    GrossSalesAmount,
    TaxAmount,
    NetSalesAmount
);
GO

CREATE NONCLUSTERED COLUMNSTORE INDEX CSI_FactItemTransactions
ON dbo.FactItemTransactions (
    PurchaseDateKey,
    SettlementDateKey,
    PlayerKey,
    ProfileKey,
    ItemKey,
    GameKey,
    PublisherKey,
    Quantity,
    GrossItemAmount,
    TaxAmount,
    PlatformFeeAmount,
    NetItemRevenue,
    WalletBalanceAfter
);
GO

