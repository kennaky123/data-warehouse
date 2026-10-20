-- =============================================================================
-- FILE: 04_SQL_OLAP_and_MDX_Queries.sql
-- PROJECT: Digital Game Store & In-Game Items Data Warehouse
-- METHODOLOGY: Vaisman & Zimanyi (Chapter 3.8 SQL/OLAP & Chapter 4 Querying DWs)
-- DESCRIPTION:
--   Contains 14 comprehensive Analytical Queries in both MDX (for SSAS/Mondrian)
--   and SQL/OLAP (runnable directly on GameStoreDW in SQL Server).
-- =============================================================================

USE GameStoreDW;
GO

/* =============================================================================
   SECTION A: 14 MDX QUERIES FOR SSAS / MONDRIAN OLAP CUBE (Chapter 4 Slides 3-34)
   =============================================================================

-- [MDX 01] Slicing & Basic Navigation (Chapter 4 Slide 5-6)
-- Business Meaning: Analyze all measures across Purchase Years sliced by Germany.
SELECT
    Measures.MEMBERS ON COLUMNS,
    [Purchase Date].[Calendar].[Year].MEMBERS ON ROWS
FROM [GameStoreCube]
WHERE ([Player].[Geography].[Country].&[Germany]);

-- [MDX 02] CrossJoin, NON EMPTY & .CHILDREN Navigation (Chapter 4 Slide 6-7, 24)
-- Business Meaning: Cross-analyze Game Categories on columns against Player Countries
-- and Calendar Quarters on rows, removing empty tuples.
SELECT
    [Game].[Categories].[Category].MEMBERS ON COLUMNS,
    NON EMPTY CROSSJOIN(
        [Player].[Geography].[Country].MEMBERS,
        [Purchase Date].[Calendar].[Quarter].MEMBERS
    ) ON ROWS
FROM [GameStoreCube]
WHERE ([Measures].[Net Sales Amount]);

-- [MDX 03] MDX Subquery Filtering in FROM Clause (Chapter 4 Slide 8)
-- Business Meaning: Restrict the sub-cube to AAA Action & RPG Titles and Major Story Expansions.
SELECT
    { [Measures].[Gross Sales Amount], [Measures].[Net Sales Amount] } ON COLUMNS,
    [Purchase Date].[Calendar].[Quarter].MEMBERS *
    [Game].[Categories].[SubCategory].MEMBERS ON ROWS
FROM (
    SELECT {
        [Game].[Categories].[SubCategory].&[101],
        [Game].[Categories].[SubCategory].&[201]
    } ON COLUMNS
    FROM [GameStoreCube]
);

-- [MDX 04] Calculated Members: Profit Margin % & Custom Rollup Member (Chapter 4 Slide 9)
-- Business Meaning: Compute Net Profit Margin % after taxes and combine Full Games + DLCs.
WITH
MEMBER [Measures].[Net Margin %] AS
    ([Measures].[Gross Sales Amount] - [Measures].[Tax Amount]) / [Measures].[Gross Sales Amount],
    FORMAT_STRING = '#0.00%'
MEMBER [Game].[Categories].[All].[Core Game Ecosystem] AS
    [Game].[Categories].[Category].&[1] + [Game].[Categories].[Category].&[2]
SELECT
    { [Measures].[Gross Sales Amount], [Measures].[Tax Amount], [Measures].[Net Sales Amount], [Measures].[Net Margin %] } ON COLUMNS,
    [Game].[Categories].[Category].ALLMEMBERS ON ROWS
FROM [GameStoreCube];

-- [MDX 05] Relative Navigation: CURRENTMEMBER, PARENT & DESCENDANTS (SELF_AND_BEFORE) (Chapter 4 Slide 10)
-- Business Meaning: Compute each Country's and State's percentage contribution to its parent Continent/Country.
WITH
MEMBER [Measures].[Geo Contribution %] AS
    ([Measures].[Net Sales Amount], [Player].[Geography].CURRENTMEMBER) /
    ([Measures].[Net Sales Amount], [Player].[Geography].CURRENTMEMBER.PARENT),
    FORMAT_STRING = '#0.00%'
SELECT
    { [Measures].[Net Sales Amount], [Measures].[Geo Contribution %] } ON COLUMNS,
    DESCENDANTS(
        [Player].[Geography].[Continent].&[North America],
        [Player].[Geography].[Country],
        SELF_AND_BEFORE
    ) ON ROWS
FROM [GameStoreCube];

-- [MDX 06] GENERATE & ORDER with BASC / BDESC (Chapter 4 Slide 11, 16)
-- Business Meaning: For each Continent ordered alphabetically, list all Game Categories ordered by name.
SELECT
    { [Measures].[Net Sales Amount], [Measures].[Quantity] } ON COLUMNS,
    NON EMPTY GENERATE(
        ORDER([Player].[Geography].[Continent].ALLMEMBERS, [Player].[Geography].CURRENTMEMBER.NAME, BASC),
        ORDER(
            { [Player].[Geography].CURRENTMEMBER } * [Game].[Categories].[Category].ALLMEMBERS,
            [Game].[Categories].CURRENTMEMBER.NAME,
            BASC
        )
    ) ON ROWS
FROM [GameStoreCube];

-- [MDX 07] Time Series: Year-Over-Year Growth with PARALLELPERIOD & Month-Over-Month with PREVMEMBER (Chapter 4 Slide 12, 25-26)
-- Business Meaning: Compare quarterly Net Sales against the same quarter of the previous year (lag 4),
-- and monthly sales against the immediately preceding month.
WITH
MEMBER [Measures].[Prev Year Sales] AS
    ([Measures].[Net Sales Amount], PARALLELPERIOD([Purchase Date].[Calendar].[Quarter], 4)),
    FORMAT_STRING = '$###,##0.00'
MEMBER [Measures].[YoY Sales Growth] AS
    [Measures].[Net Sales Amount] - [Measures].[Prev Year Sales],
    FORMAT_STRING = '$###,##0.00;$-###,##0.00'
SELECT
    { [Measures].[Net Sales Amount], [Measures].[Prev Year Sales], [Measures].[YoY Sales Growth] } ON COLUMNS,
    NON EMPTY [Purchase Date].[Calendar].[Quarter].MEMBERS ON ROWS
FROM [GameStoreCube];

-- [MDX 08] Time Series: OPENINGPERIOD, YTD (PERIODSTODATE) & 3-Month Moving Average (LAG) (Chapter 4 Slide 13, 30-31)
-- Business Meaning: Compute Year-to-Date cumulative sales, 3-month rolling average, and difference from January of the same year.
WITH
MEMBER [Measures].[YTD Net Sales] AS
    SUM(
        PERIODSTODATE([Purchase Date].[Calendar].[Year], [Purchase Date].[Calendar].CURRENTMEMBER),
        [Measures].[Net Sales Amount]
    ),
    FORMAT_STRING = '$###,##0.00'
MEMBER [Measures].[MovAvg 3 Months] AS
    AVG(
        [Purchase Date].[Calendar].CURRENTMEMBER.LAG(2) : [Purchase Date].[Calendar].CURRENTMEMBER,
        [Measures].[Net Sales Amount]
    ),
    FORMAT_STRING = '$###,##0.00'
MEMBER [Measures].[Diff From First Month] AS
    [Measures].[Net Sales Amount] -
    ([Measures].[Net Sales Amount], OPENINGPERIOD([Purchase Date].[Calendar].[Month], [Purchase Date].[Calendar].CURRENTMEMBER.PARENT)),
    FORMAT_STRING = '$###,##0.00;$-###,##0.00'
SELECT
    { [Measures].[Net Sales Amount], [Measures].[YTD Net Sales], [Measures].[MovAvg 3 Months], [Measures].[Diff From First Month] } ON COLUMNS,
    DESCENDANTS([Purchase Date].[Calendar].[Year].&[2025], [Purchase Date].[Calendar].[Month]) ON ROWS
FROM [GameStoreCube];

-- [MDX 09] Filtering with FILTER() Comparing Member vs Parent Margin (Chapter 4 Slide 14-15)
-- Business Meaning: Identify individual Players whose Net Margin % is lower than their City's average Net Margin %.
WITH
MEMBER [Measures].[Net Margin %] AS
    ([Measures].[Gross Sales Amount] - [Measures].[Tax Amount]) / [Measures].[Gross Sales Amount],
    FORMAT_STRING = '#0.00%'
MEMBER [Measures].[City Margin %] AS
    ([Measures].[Net Margin %], [Player].[Geography].CURRENTMEMBER.PARENT),
    FORMAT_STRING = '#0.00%'
SELECT
    { [Measures].[Gross Sales Amount], [Measures].[Net Margin %], [Measures].[City Margin %] } ON COLUMNS,
    FILTER(
        NONEMPTY([Player].[Geography].[Player].MEMBERS),
        [Measures].[Net Margin %] < [Measures].[City Margin %]
    ) ON ROWS
FROM [GameStoreCube]
WHERE ([Purchase Date].[Calendar].[Year].&[2025]);

-- [MDX 10] Top/Bottom Analysis: TOPCOUNT, TOPPERCENT & Named Sets (Top 3 Countries vs Other Countries) (Chapter 4 Slide 17-18, 27)
-- Business Meaning: Compare the Top 3 Virtual Item purchasing countries against the aggregated "Other Countries" group.
WITH
SET [SetTop3Countries] AS
    TOPCOUNT([Player].[Geography].[Country].MEMBERS, 3, [Measures].[Gross Item Amount])
MEMBER [Player].[Geography].[Top 3 Countries] AS
    AGGREGATE([SetTop3Countries])
MEMBER [Player].[Geography].[Other Countries] AS
    ([Player].[Geography].[All]) - ([Player].[Geography].[Top 3 Countries])
SELECT
    { [Measures].[Gross Item Amount], [Measures].[Net Item Revenue], [Measures].[Item Quantity] } ON COLUMNS,
    { [SetTop3Countries], [Player].[Geography].[Top 3 Countries], [Player].[Geography].[Other Countries], [Player].[Geography].[All] } ON ROWS
FROM [GameStoreCube];

-- [MDX 11] Peak Month Detection using MAX, MIN, AVG & TOPCOUNT(...).ITEM(0).NAME (Chapter 4 Slide 19-21)
-- Business Meaning: For each Game Category and Country, find the maximum monthly sales and the exact Month Name where that peak occurred.
WITH
MEMBER [Measures].[Max Monthly Sales] AS
    MAX(DESCENDANTS([Purchase Date].[Calendar].[Year].&[2025], [Purchase Date].[Calendar].[Month]), [Measures].[Net Sales Amount]),
    FORMAT_STRING = '$###,##0.00'
MEMBER [Measures].[Peak Month Name] AS
    TOPCOUNT(
        DESCENDANTS([Purchase Date].[Calendar].[Year].&[2025], [Purchase Date].[Calendar].[Month]),
        1,
        [Measures].[Net Sales Amount]
    ).ITEM(0).NAME
SELECT
    { [Measures].[Max Monthly Sales], [Measures].[Peak Month Name] } ON COLUMNS,
    NON EMPTY [Game].[Categories].[Category].MEMBERS * [Player].[Geography].[Country].MEMBERS ON ROWS
FROM [GameStoreCube];

-- [MDX 12] Parent-Child Hierarchy Navigation with .DATAMEMBER (Chapter 4 Slide 32)
-- Business Meaning: Compare a Parent Publisher Studio's own direct game sales (Personal Sales via .DATAMEMBER)
-- against the rollup total that includes all its subsidiary studios (e.g., Xbox Game Studios -> Activision Blizzard -> Blizzard).
WITH
MEMBER [Measures].[Direct Studio Sales] AS
    ([Publisher].[Studio Hierarchy].CURRENTMEMBER.DATAMEMBER, [Measures].[Net Sales Amount]),
    FORMAT_STRING = '$###,##0.00'
SELECT
    { [Measures].[Direct Studio Sales], [Measures].[Net Sales Amount] } ON COLUMNS,
    ORDER(
        [Publisher].[Studio Hierarchy].MEMBERS - { [Publisher].[Studio Hierarchy].[All] },
        [Publisher].[Studio Hierarchy].CURRENTMEMBER.NAME,
        BASC
    ) ON ROWS
FROM [GameStoreCube]
WHERE ([Purchase Date].[Calendar].[Year].&[2025]);

-- [MDX 13] Degenerate Order Dimension: Line Item Count per Order & Monthly Average Order Value (Chapter 4 Slide 33-34)
-- Business Meaning: Count how many distinct game titles were bought in each Order using [Order].[Order No] * [Order].[Order Line].
WITH
MEMBER [Measures].[NbOrderLines] AS
    COUNT(NONEMPTY([Order].[Order No].CURRENTMEMBER * [Order].[Order Line].MEMBERS))
SELECT
    { [Measures].[Net Sales Amount], [Measures].[NbOrderLines], [Measures].[Quantity] } ON COLUMNS,
    HEAD([Order].[Order No].CHILDREN, 20) ON ROWS
FROM [GameStoreCube];

-- [MDX 14] Many-to-Many Dimension & DISTINCTCOUNT / EXCLUDEEMPTY (Chapter 4 Slide 22, 34)
-- Business Meaning: Count distinct Active Buyers and distinct Genres associated with each Publisher.
WITH
MEMBER [Measures].[Active Buyers Count] AS
    COUNT(
        { [Measures].[Net Sales Amount] } * [Player].[Player].[Player].MEMBERS,
        EXCLUDEEMPTY
    )
MEMBER [Measures].[Distinct Genres Count] AS
    DISTINCTCOUNT(
        NONEMPTY([Publisher].[Publisher].CURRENTMEMBER * [Genre].[Genre].[Genre].MEMBERS, [Measures].[Bridge Game Genre Count])
    )
SELECT
    { [Measures].[Net Sales Amount], [Measures].[Active Buyers Count], [Measures].[Distinct Genres Count] } ON COLUMNS,
    [Publisher].[Publisher].CHILDREN ON ROWS
FROM [GameStoreCube];
*/

-- =============================================================================
-- SECTION B: 14 EQUIVALENT SQL/OLAP QUERIES (RUNNABLE ON SQL SERVER)
--            (Chapter 3.8 Slides 56-76 & Chapter 4.3 Slides 35-42)
-- =============================================================================

-- [SQL 01] Starflake Join: Total Sales Amount per Player, Year, and Game Category (Chapter 4 Slide 36)
SELECT
    p.GamerTag,
    t.[Year],
    c.CategoryName,
    FORMAT(SUM(f.GrossSalesAmount), '$###,##0.00') AS GrossSales,
    FORMAT(SUM(f.NetSalesAmount), '$###,##0.00')   AS NetSales
FROM dbo.FactGameSales f
INNER JOIN dbo.DimPlayer p      ON f.PlayerKey       = p.PlayerKey
INNER JOIN dbo.DimTime t        ON f.PurchaseDateKey = t.TimeKey
INNER JOIN dbo.DimGame g        ON f.GameKey         = g.GameKey
INNER JOIN dbo.DimSubCategory s ON g.SubCategoryKey  = s.SubCategoryKey
INNER JOIN dbo.DimCategory c    ON s.CategoryKey     = c.CategoryKey
GROUP BY p.GamerTag, t.[Year], c.CategoryName
ORDER BY t.[Year], p.GamerTag;
GO

-- [SQL 02] Ragged Geography Traversal: Yearly Sales for Pairs of Player Country and Publisher Country (Chapter 4 Slide 38)
-- Uses COALESCE(st.CountryKey, ci.CountryKey) to handle Ragged Hierarchy (cities with or without states)!
SELECT
    co_player.CountryName AS PlayerCountry,
    co_pub.CountryName    AS PublisherCountry,
    t.[Year],
    FORMAT(SUM(f.NetSalesAmount), '$###,##0.00') AS NetSalesAmount
FROM dbo.FactGameSales f
INNER JOIN dbo.DimPlayer pl      ON f.PlayerKey    = pl.PlayerKey
INNER JOIN dbo.DimCity ci_pl     ON pl.CityKey     = ci_pl.CityKey
LEFT  JOIN dbo.DimState st_pl    ON ci_pl.StateKey = st_pl.StateKey
INNER JOIN dbo.DimCountry co_player ON COALESCE(st_pl.CountryKey, ci_pl.CountryKey) = co_player.CountryKey
INNER JOIN dbo.DimPublisher pub  ON f.PublisherKey = pub.PublisherKey
INNER JOIN dbo.DimCity ci_pub    ON pub.CityKey    = ci_pub.CityKey
LEFT  JOIN dbo.DimState st_pub   ON ci_pub.StateKey = st_pub.StateKey
INNER JOIN dbo.DimCountry co_pub ON COALESCE(st_pub.CountryKey, ci_pub.CountryKey) = co_pub.CountryKey
INNER JOIN dbo.DimTime t         ON f.PurchaseDateKey = t.TimeKey
GROUP BY co_player.CountryName, co_pub.CountryName, t.[Year]
ORDER BY co_player.CountryName, co_pub.CountryName, t.[Year];
GO

-- [SQL 03] GROUP BY ROLLUP on Continent -> Country -> City Hierarchy (Chapter 3 Slide 64-65)
SELECT
    cont.ContinentName,
    co.CountryName,
    ci.CityName,
    SUM(f.Quantity)       AS TotalUnits,
    SUM(f.NetSalesAmount) AS TotalNetSales,
    GROUPING_ID(cont.ContinentName, co.CountryName, ci.CityName) AS GroupingLevel
FROM dbo.FactGameSales f
INNER JOIN dbo.DimPlayer pl      ON f.PlayerKey    = pl.PlayerKey
INNER JOIN dbo.DimCity ci        ON pl.CityKey     = ci.CityKey
LEFT  JOIN dbo.DimState st       ON ci.StateKey    = st.StateKey
INNER JOIN dbo.DimCountry co     ON COALESCE(st.CountryKey, ci.CountryKey) = co.CountryKey
INNER JOIN dbo.DimContinent cont ON co.ContinentKey = cont.ContinentKey
GROUP BY ROLLUP(cont.ContinentName, co.CountryName, ci.CityName)
ORDER BY GroupingLevel, cont.ContinentName, co.CountryName, ci.CityName;
GO

-- [SQL 04] GROUP BY CUBE on Category, CalendarYear, and AccountType (Chapter 3 Slide 64-65)
SELECT
    ISNULL(c.CategoryName, N'[ALL CATEGORIES]') AS CategoryName,
    ISNULL(CAST(t.[Year] AS VARCHAR(10)), '[ALL YEARS]') AS CalendarYear,
    ISNULL(p.AccountType, '[ALL ACCOUNT TYPES]') AS AccountType,
    SUM(f.NetSalesAmount) AS TotalNetSales
FROM dbo.FactGameSales f
INNER JOIN dbo.DimPlayer p      ON f.PlayerKey       = p.PlayerKey
INNER JOIN dbo.DimTime t        ON f.PurchaseDateKey = t.TimeKey
INNER JOIN dbo.DimGame g        ON f.GameKey         = g.GameKey
INNER JOIN dbo.DimSubCategory s ON g.SubCategoryKey  = s.SubCategoryKey
INNER JOIN dbo.DimCategory c    ON s.CategoryKey     = c.CategoryKey
GROUP BY CUBE(c.CategoryName, t.[Year], p.AccountType);
GO

-- [SQL 05] GROUP BY GROUPING SETS Comparing Calendar vs Fiscal Hierarchy (Chapter 3 Slide 66)
SELECT
    t.[Year]         AS CalendarYear,
    t.Quarter        AS CalendarQuarter,
    t.FiscalYear     AS FiscalYear,
    t.FiscalQuarter  AS FiscalQuarter,
    g.EngineVendor   AS EngineVendor,
    SUM(f.NetSalesAmount) AS TotalNetSales
FROM dbo.FactGameSales f
INNER JOIN dbo.DimTime t ON f.PurchaseDateKey = t.TimeKey
INNER JOIN dbo.DimGame g ON f.GameKey         = g.GameKey
GROUP BY GROUPING SETS (
    (t.[Year], t.Quarter),
    (t.FiscalYear, t.FiscalQuarter),
    (g.EngineVendor),
    ()
);
GO

-- [SQL 06] Window Partitioning: Compare Detailed Game Sales with Category Maximum & Share % (Chapter 3 Slide 68-69)
WITH GameCatSales AS (
    SELECT
        c.CategoryName,
        g.GameTitle,
        SUM(f.NetSalesAmount) AS GameNetSales
    FROM dbo.FactGameSales f
    INNER JOIN dbo.DimGame g        ON f.GameKey        = g.GameKey
    INNER JOIN dbo.DimSubCategory s ON g.SubCategoryKey = s.SubCategoryKey
    INNER JOIN dbo.DimCategory c    ON s.CategoryKey    = c.CategoryKey
    GROUP BY c.CategoryName, g.GameTitle
)
SELECT
    CategoryName,
    GameTitle,
    GameNetSales,
    MAX(GameNetSales) OVER (PARTITION BY CategoryName) AS MaxInCategory,
    SUM(GameNetSales) OVER (PARTITION BY CategoryName) AS CategoryTotal,
    FORMAT(GameNetSales / SUM(GameNetSales) OVER (PARTITION BY CategoryName), '#0.00%') AS CategorySharePct
FROM GameCatSales
ORDER BY CategoryName, GameNetSales DESC;
GO

-- [SQL 07] Window Ordering: ROW_NUMBER(), RANK(), DENSE_RANK() of Games per Country (Chapter 3 Slide 70-72)
WITH CountryGameSales AS (
    SELECT
        co.CountryName,
        g.GameTitle,
        SUM(f.NetSalesAmount) AS NetSales
    FROM dbo.FactGameSales f
    INNER JOIN dbo.DimPlayer pl  ON f.PlayerKey = pl.PlayerKey
    INNER JOIN dbo.DimCity ci    ON pl.CityKey  = ci.CityKey
    LEFT  JOIN dbo.DimState st   ON ci.StateKey = st.StateKey
    INNER JOIN dbo.DimCountry co ON COALESCE(st.CountryKey, ci.CountryKey) = co.CountryKey
    INNER JOIN dbo.DimGame g     ON f.GameKey   = g.GameKey
    GROUP BY co.CountryName, g.GameTitle
)
SELECT
    CountryName,
    GameTitle,
    NetSales,
    ROW_NUMBER() OVER (PARTITION BY CountryName ORDER BY NetSales DESC) AS RowNo,
    RANK()       OVER (PARTITION BY CountryName ORDER BY NetSales DESC) AS SalesRank,
    DENSE_RANK() OVER (PARTITION BY CountryName ORDER BY NetSales DESC) AS DenseSalesRank
FROM CountryGameSales
ORDER BY CountryName, SalesRank;
GO

-- [SQL 08] Window Framing: 3-Month Moving Average (ROWS 2 PRECEDING) & Cumulative YTD (ROWS UNBOUNDED PRECEDING) (Chapter 3 Slide 73-75)
WITH MonthlyGameSales AS (
    SELECT
        g.GameTitle,
        t.[Year],
        t.MonthNumber,
        t.MonthName,
        SUM(f.NetSalesAmount) AS MonthlyNetSales
    FROM dbo.FactGameSales f
    INNER JOIN dbo.DimGame g ON f.GameKey         = g.GameKey
    INNER JOIN dbo.DimTime t ON f.PurchaseDateKey = t.TimeKey
    GROUP BY g.GameTitle, t.[Year], t.MonthNumber, t.MonthName
)
SELECT
    GameTitle,
    [Year],
    MonthNumber,
    MonthName,
    MonthlyNetSales,
    CONVERT(DECIMAL(12,2), AVG(MonthlyNetSales) OVER (
        PARTITION BY GameTitle
        ORDER BY [Year], MonthNumber
        ROWS 2 PRECEDING
    )) AS MovAvg3Months,
    CONVERT(DECIMAL(12,2), SUM(MonthlyNetSales) OVER (
        PARTITION BY GameTitle, [Year]
        ORDER BY MonthNumber
        ROWS UNBOUNDED PRECEDING
    )) AS CumulativeYTD
FROM MonthlyGameSales
ORDER BY GameTitle, [Year], MonthNumber;
GO

-- [SQL 09] Best-Selling Publisher per Game Category and Year using CTE (Chapter 4 Slide 40)
WITH SalesCatYearPub AS (
    SELECT
        c.CategoryName,
        t.[Year],
        pub.PublisherName,
        SUM(f.NetSalesAmount) AS TotalSales
    FROM dbo.FactGameSales f
    INNER JOIN dbo.DimGame g        ON f.GameKey         = g.GameKey
    INNER JOIN dbo.DimSubCategory s ON g.SubCategoryKey  = s.SubCategoryKey
    INNER JOIN dbo.DimCategory c    ON s.CategoryKey     = c.CategoryKey
    INNER JOIN dbo.DimPublisher pub ON f.PublisherKey    = pub.PublisherKey
    INNER JOIN dbo.DimTime t        ON f.PurchaseDateKey = t.TimeKey
    GROUP BY c.CategoryName, t.[Year], pub.PublisherName
)
SELECT
    s1.CategoryName,
    s1.[Year],
    s1.PublisherName AS TopPublisher,
    FORMAT(s1.TotalSales, '$###,##0.00') AS TopSales
FROM SalesCatYearPub s1
WHERE s1.TotalSales = (
    SELECT MAX(s2.TotalSales)
    FROM SalesCatYearPub s2
    WHERE s1.CategoryName = s2.CategoryName AND s1.[Year] = s2.[Year]
)
ORDER BY s1.[Year], s1.CategoryName;
GO

-- [SQL 10] Degenerate Order Dimension: Monthly Order Count, Total Sales & Average Order Value (Chapter 4 Slide 41)
WITH OrderAgg AS (
    SELECT
        OrderNo,
        PurchaseDateKey,
        SUM(NetSalesAmount) AS OrderNetSales
    FROM dbo.FactGameSales
    GROUP BY OrderNo, PurchaseDateKey
)
SELECT
    t.[Year],
    t.MonthNumber,
    t.MonthName + ' ' + CAST(t.[Year] AS CHAR(4)) AS FullMonth,
    COUNT(o.OrderNo) AS NoOrders,
    FORMAT(SUM(o.OrderNetSales), '$###,##0.00') AS TotalSalesAmount,
    FORMAT(AVG(o.OrderNetSales), '$###,##0.00') AS AvgOrderAmount
FROM OrderAgg o
INNER JOIN dbo.DimTime t ON o.PurchaseDateKey = t.TimeKey
GROUP BY t.[Year], t.MonthNumber, t.MonthName
ORDER BY t.[Year], t.MonthNumber;
GO

-- [SQL 11] Many-to-Many Dimension with WeightFactor vs Unweighted Double-Counting (Chapter 2 Slide 5g, 16; Chapter 3 Slide 40, 49)
SELECT
    gen.SuperGenre,
    gen.GenreName,
    COUNT(DISTINCT f.PlayerKey) AS ActiveBuyersDistinctCount,
    FORMAT(SUM(f.NetSalesAmount), '$###,##0.00') AS UnweightedGenreSales,
    FORMAT(SUM(f.NetSalesAmount * b.WeightFactor), '$###,##0.00') AS WeightedGenreSales_NoDoubleCount
FROM dbo.FactGameSales f
INNER JOIN dbo.BridgeGameGenre b ON f.GameKey  = b.GameKey
INNER JOIN dbo.DimGenre gen      ON b.GenreKey = gen.GenreKey
GROUP BY gen.SuperGenre, gen.GenreName
ORDER BY SUM(f.NetSalesAmount * b.WeightFactor) DESC;
GO

-- [SQL 12] Parent-Child Recursive Rollup using Closure Table vs Direct Studio Sales (Chapter 3 Slide 25 & Chapter 4 Slide 32)
SELECT
    sup.PublisherName AS ParentOrSelfStudio,
    FORMAT(SUM(CASE WHEN cl.Distance = 0 THEN f.NetSalesAmount ELSE 0 END), '$###,##0.00') AS PersonalStudioSales_DataMember,
    FORMAT(SUM(f.NetSalesAmount), '$###,##0.00') AS TotalHierarchySales_WithSubordinates,
    COUNT(DISTINCT cl.SubordinatePublisherKey) AS StudiosInSubtree
FROM dbo.DimPublisher sup
INNER JOIN dbo.DimPublisherClosure cl ON sup.PublisherKey = cl.SupervisorPublisherKey
INNER JOIN dbo.FactGameSales f        ON cl.SubordinatePublisherKey = f.PublisherKey
GROUP BY sup.PublisherKey, sup.PublisherName
ORDER BY SUM(f.NetSalesAmount) DESC;
GO

-- [SQL 13] Top 3 Countries vs "Other Countries" for In-Game Virtual Items (Chapter 4 Slide 18)
WITH CountryItemSales AS (
    SELECT
        co.CountryName,
        SUM(fi.GrossItemAmount) AS GrossItemSales,
        SUM(fi.NetItemRevenue)  AS NetItemSales,
        RANK() OVER (ORDER BY SUM(fi.GrossItemAmount) DESC) AS rnk
    FROM dbo.FactItemTransactions fi
    INNER JOIN dbo.DimPlayer pl  ON fi.PlayerKey = pl.PlayerKey
    INNER JOIN dbo.DimCity ci    ON pl.CityKey   = ci.CityKey
    LEFT  JOIN dbo.DimState st   ON ci.StateKey  = st.StateKey
    INNER JOIN dbo.DimCountry co ON COALESCE(st.CountryKey, ci.CountryKey) = co.CountryKey
    GROUP BY co.CountryName
)
SELECT
    CASE WHEN rnk <= 3 THEN CountryName ELSE N'Other Countries' END AS CountryGroup,
    CASE WHEN rnk <= 3 THEN rnk ELSE 99 END AS SortOrder,
    FORMAT(SUM(GrossItemSales), '$###,##0.00') AS GrossItemSales,
    FORMAT(SUM(NetItemSales), '$###,##0.00')   AS NetItemSales
FROM CountryItemSales
GROUP BY
    CASE WHEN rnk <= 3 THEN CountryName ELSE N'Other Countries' END,
    CASE WHEN rnk <= 3 THEN rnk ELSE 99 END
ORDER BY SortOrder;
GO

-- [SQL 14] Drill-Across Constellation Schema: Combining FactGameSales & FactItemTransactions + SCD Type 2 vs Type 6 Analysis (Chapter 1 Slide 31 & Chapter 3 Slide 54-55)
WITH GameRev AS (
    SELECT pl.PlayerAltKey, pl.GamerTag, pl.HistoricalVIPLevel, pl.CurrentVIPLevel, SUM(f.NetSalesAmount) AS GameNetRevenue
    FROM dbo.FactGameSales f
    INNER JOIN dbo.DimPlayer pl ON f.PlayerKey = pl.PlayerKey
    GROUP BY pl.PlayerAltKey, pl.GamerTag, pl.HistoricalVIPLevel, pl.CurrentVIPLevel
),
ItemRev AS (
    SELECT pl.PlayerAltKey, pl.HistoricalVIPLevel, SUM(fi.NetItemRevenue) AS ItemNetRevenue
    FROM dbo.FactItemTransactions fi
    INNER JOIN dbo.DimPlayer pl ON fi.PlayerKey = pl.PlayerKey
    GROUP BY pl.PlayerAltKey, pl.HistoricalVIPLevel
)
SELECT
    g.PlayerAltKey,
    g.GamerTag,
    g.HistoricalVIPLevel AS SCD2_HistoricalVIP_AtPurchase,
    g.CurrentVIPLevel    AS SCD6_CurrentVIP_Now,
    FORMAT(g.GameNetRevenue, '$###,##0.00') AS GameStoreNetRevenue,
    FORMAT(ISNULL(i.ItemNetRevenue, 0), '$###,##0.00') AS InGameItemsNetRevenue,
    FORMAT(g.GameNetRevenue + ISNULL(i.ItemNetRevenue, 0), '$###,##0.00') AS TotalCombinedEcosystemRevenue
FROM GameRev g
LEFT JOIN ItemRev i ON g.PlayerAltKey = i.PlayerAltKey AND g.HistoricalVIPLevel = i.HistoricalVIPLevel
ORDER BY g.PlayerAltKey, g.HistoricalVIPLevel;
GO

