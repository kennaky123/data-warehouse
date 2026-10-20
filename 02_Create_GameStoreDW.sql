-- =============================================================================
-- FILE: 02_Create_GameStoreDW.sql
-- PROJECT: Digital Game Store & In-Game Items Data Warehouse
-- METHODOLOGY: Vaisman & Zimanyi (VKU Data Warehouse Course - Chapters 1 to 6)
-- DESCRIPTION: Creates the Relational Data Warehouse (GameStoreDW)
--              Includes Starflake / Constellation Schema, Surrogate Keys,
--              Alternate Keys (AK), Ragged/Generalized XOR CHECK Constraints,
--              Parent-Child Hierarchy + Closure Table, SCD Type 2 & Type 6,
--              and Many-to-Many Bridge Table with WeightFactor.
-- =============================================================================

USE master;
GO

IF DB_ID('GameStoreDW') IS NOT NULL
BEGIN
    ALTER DATABASE GameStoreDW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GameStoreDW;
END
GO

CREATE DATABASE GameStoreDW;
GO

USE GameStoreDW;
GO

-- =============================================================================
-- 1. STAGING TABLE FOR ETL (Chapter 6 - Slide 22, 44)
-- =============================================================================
CREATE TABLE dbo.TempCities (
    City    NVARCHAR(60) NOT NULL,
    State   NVARCHAR(60) NULL,
    Country NVARCHAR(60) NOT NULL
);
GO

-- =============================================================================
-- 2. GEOGRAPHY SNOWFLAKE / RAGGED HIERARCHY: Continent -> Country -> State -> City
--    (Chapter 2 Slide 3, Chapter 3 Slide 14, 28-31)
-- =============================================================================
CREATE TABLE dbo.DimContinent (
    ContinentKey  INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ContinentName NVARCHAR(30)      NOT NULL UNIQUE
);
GO

CREATE TABLE dbo.DimCountry (
    CountryKey     INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CountryName    NVARCHAR(60)      NOT NULL UNIQUE,
    CountryCode    CHAR(2)           NOT NULL UNIQUE,
    CountryCapital NVARCHAR(60)      NOT NULL,
    Population     BIGINT            NOT NULL,
    Subdivision    NVARCHAR(120)     NULL,
    ContinentKey   INT               NOT NULL,
    CONSTRAINT FK_DimCountry_DimContinent FOREIGN KEY (ContinentKey) REFERENCES dbo.DimContinent(ContinentKey)
);
GO

CREATE TABLE dbo.DimState (
    StateKey         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    StateName        NVARCHAR(60)      NOT NULL,
    EnglishStateName NVARCHAR(60)      NOT NULL,
    StateType        NVARCHAR(30)      NOT NULL,
    StateCode        VARCHAR(10)       NOT NULL,
    StateCapital     NVARCHAR(60)      NOT NULL,
    RegionName       NVARCHAR(60)      NULL,
    RegionCode       VARCHAR(10)       NULL,
    CountryKey       INT               NOT NULL,
    CONSTRAINT FK_DimState_DimCountry FOREIGN KEY (CountryKey) REFERENCES dbo.DimCountry(CountryKey)
);
GO

-- DimCity implements the Ragged / Generalized Hierarchy (Chapter 3 Slide 14 & Slide 30):
-- A city either belongs to a State (StateKey IS NOT NULL, CountryKey IS NULL)
-- OR directly belongs to a Country without states (StateKey IS NULL, CountryKey IS NOT NULL).
CREATE TABLE dbo.DimCity (
    CityKey          INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    CityName         NVARCHAR(60)      NOT NULL,
    CityHierarchyType VARCHAR(20)      NOT NULL DEFAULT 'WithState',
    StateKey         INT               NULL,
    CountryKey       INT               NULL,
    CONSTRAINT FK_DimCity_DimState   FOREIGN KEY (StateKey)   REFERENCES dbo.DimState(StateKey),
    CONSTRAINT FK_DimCity_DimCountry FOREIGN KEY (CountryKey) REFERENCES dbo.DimCountry(CountryKey)
);
GO

-- Exclusive (XOR) Check Constraints as taught in Chapter 3 Slide 30:
ALTER TABLE dbo.DimCity ADD CONSTRAINT CK_DimCity_HierarchyType
CHECK (CityHierarchyType IN ('WithState', 'DirectCountry'));
GO

ALTER TABLE dbo.DimCity ADD CONSTRAINT CK_DimCity_WithStateFK
CHECK ((CityHierarchyType != 'WithState') OR (StateKey IS NOT NULL AND CountryKey IS NULL));
GO

ALTER TABLE dbo.DimCity ADD CONSTRAINT CK_DimCity_DirectCountryFK
CHECK ((CityHierarchyType != 'DirectCountry') OR (StateKey IS NULL AND CountryKey IS NOT NULL));
GO

-- =============================================================================
-- 3. TIME DIMENSION WITH ALTERNATIVE HIERARCHIES (Calendar vs Fiscal)
--    (Chapter 2 Slide 13, Chapter 3 Slide 14, 16-18, 34)
-- =============================================================================
CREATE TABLE dbo.DimTime (
    TimeKey          INT          NOT NULL PRIMARY KEY, -- YYYYMMDD Surrogate Key
    [Date]           DATE         NOT NULL UNIQUE,      -- Alternate Key (AK: Date)
    DayNbWeek        TINYINT      NOT NULL,
    DayNameWeek      NVARCHAR(15) NOT NULL,
    DayNbMonth       TINYINT      NOT NULL,
    DayNbYear        SMALLINT     NOT NULL,
    WeekNbYear       TINYINT      NOT NULL,
    MonthNumber      TINYINT      NOT NULL,
    MonthName        NVARCHAR(15) NOT NULL,
    -- Calendar Hierarchy Levels
    Quarter          TINYINT      NOT NULL,
    Semester         TINYINT      NOT NULL,
    [Year]           SMALLINT     NOT NULL,
    -- Alternative Fiscal Hierarchy Levels (Fiscal Year starts in February - Chapter 2 Slide 13)
    FiscalQuarter    TINYINT      NOT NULL,
    FiscalSemester   TINYINT      NOT NULL,
    FiscalYear       SMALLINT     NOT NULL,
    WeekendFlag      BIT          NOT NULL
);
GO

-- =============================================================================
-- 4. PRODUCT & ITEM HIERARCHIES (Balanced & Parallel Hierarchies)
--    (Chapter 2 Slide 7, 14-15; Chapter 3 Slide 21)
-- =============================================================================
CREATE TABLE dbo.DimCategory (
    CategoryKey    INT           NOT NULL PRIMARY KEY,
    CategoryName   NVARCHAR(60)  NOT NULL,
    DepartmentName NVARCHAR(60)  NOT NULL,
    Description    NVARCHAR(255) NULL
);
GO

CREATE TABLE dbo.DimSubCategory (
    SubCategoryKey  INT          NOT NULL PRIMARY KEY,
    SubCategoryName NVARCHAR(60) NOT NULL,
    CategoryKey     INT          NOT NULL,
    CONSTRAINT FK_DimSubCategory_DimCategory FOREIGN KEY (CategoryKey) REFERENCES dbo.DimCategory(CategoryKey)
);
GO

-- DimPublisher: Unbalanced / Parent-Child Recursive Hierarchy (Chapter 2 Slide 8, 10; Chapter 3 Slide 25, 96)
CREATE TABLE dbo.DimPublisher (
    PublisherKey      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    PublisherAltKey   VARCHAR(20)       NOT NULL UNIQUE, -- AK: PublisherID
    PublisherName     NVARCHAR(100)     NOT NULL,
    FoundedYear       INT               NOT NULL,
    CityKey           INT               NOT NULL,
    ParentPublisherKey INT              NULL,
    CONSTRAINT FK_DimPublisher_DimCity   FOREIGN KEY (CityKey)            REFERENCES dbo.DimCity(CityKey),
    CONSTRAINT FK_DimPublisher_ParentKey FOREIGN KEY (ParentPublisherKey) REFERENCES dbo.DimPublisher(PublisherKey)
);
GO

-- Closure Table for Parent-Child Hierarchy (Chapter 6 Slide 54: Kettle Closure Generator / SQL Recursive Traversal)
CREATE TABLE dbo.DimPublisherClosure (
    SupervisorPublisherKey  INT NOT NULL,
    SubordinatePublisherKey INT NOT NULL,
    Distance                INT NOT NULL,
    CONSTRAINT PK_DimPublisherClosure PRIMARY KEY (SupervisorPublisherKey, SubordinatePublisherKey),
    CONSTRAINT FK_Closure_Supervisor  FOREIGN KEY (SupervisorPublisherKey)  REFERENCES dbo.DimPublisher(PublisherKey),
    CONSTRAINT FK_Closure_Subordinate FOREIGN KEY (SubordinatePublisherKey) REFERENCES dbo.DimPublisher(PublisherKey)
);
GO

-- DimGame: Includes Parallel Hierarchy attributes (SubCategoryKey->CategoryKey AND EngineName->EngineVendor)
CREATE TABLE dbo.DimGame (
    GameKey         INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    GameAltKey      VARCHAR(20)       NOT NULL UNIQUE, -- AK: GameID
    GameTitle       NVARCHAR(120)     NOT NULL,
    ProductType     VARCHAR(20)       NOT NULL,
    SubCategoryKey  INT               NOT NULL,
    EngineName      NVARCHAR(60)      NOT NULL,
    EngineVendor    NVARCHAR(60)      NOT NULL,
    LicenseType     NVARCHAR(40)      NOT NULL,
    PublisherKey    INT               NOT NULL,
    ReleaseDate     DATE              NOT NULL,
    ListPrice       DECIMAL(10,2)     NOT NULL,
    AgeRating       VARCHAR(10)       NOT NULL,
    IsDiscontinued  BIT               NOT NULL,
    CONSTRAINT FK_DimGame_DimSubCategory FOREIGN KEY (SubCategoryKey) REFERENCES dbo.DimSubCategory(SubCategoryKey),
    CONSTRAINT FK_DimGame_DimPublisher   FOREIGN KEY (PublisherKey)   REFERENCES dbo.DimPublisher(PublisherKey)
);
GO

-- DimGenre & BridgeGameGenre: Many-to-Many / Nonstrict Hierarchy (Chapter 2 Slide 16, 18; Chapter 3 Slide 39, 49)
CREATE TABLE dbo.DimGenre (
    GenreKey    INT           NOT NULL PRIMARY KEY,
    GenreName   NVARCHAR(50)  NOT NULL,
    SuperGenre  NVARCHAR(50)  NOT NULL,
    Description NVARCHAR(200) NULL
);
GO

CREATE TABLE dbo.BridgeGameGenre (
    GameKey        INT          NOT NULL,
    GenreKey       INT          NOT NULL,
    WeightFactor   DECIMAL(5,4) NOT NULL DEFAULT 1.0000, -- Distributing attribute (percentage ÷)
    IsPrimaryGenre BIT          NOT NULL DEFAULT 0,
    CONSTRAINT PK_BridgeGameGenre PRIMARY KEY (GameKey, GenreKey),
    CONSTRAINT FK_BridgeGameGenre_DimGame  FOREIGN KEY (GameKey)  REFERENCES dbo.DimGame(GameKey),
    CONSTRAINT FK_BridgeGameGenre_DimGenre FOREIGN KEY (GenreKey) REFERENCES dbo.DimGenre(GenreKey)
);
GO

-- DimItem: Balanced Hierarchy (Item -> SubCategory -> Category)
CREATE TABLE dbo.DimItem (
    ItemKey        INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    ItemAltKey     VARCHAR(20)       NOT NULL UNIQUE, -- AK: ItemID
    ItemName       NVARCHAR(120)     NOT NULL,
    GameKey        INT               NOT NULL,
    SubCategoryKey INT               NOT NULL,
    Rarity         VARCHAR(30)       NOT NULL,
    IsTradable     BIT               NOT NULL,
    BasePrice      DECIMAL(10,2)     NOT NULL,
    CONSTRAINT FK_DimItem_DimGame        FOREIGN KEY (GameKey)        REFERENCES dbo.DimGame(GameKey),
    CONSTRAINT FK_DimItem_DimSubCategory FOREIGN KEY (SubCategoryKey) REFERENCES dbo.DimSubCategory(SubCategoryKey)
);
GO

-- =============================================================================
-- 5. PLAYER DIMENSION WITH SCD TYPE 2, TYPE 3, TYPE 4 & TYPE 6 SUPPORT
--    (Chapter 3 Slide 50-55)
-- =============================================================================
-- Mini-dimension DimPlayerProfile (SCD Type 4 & Type 5 Outrigger - Chapter 3 Slide 55)
CREATE TABLE dbo.DimPlayerProfile (
    ProfileKey      INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    VIPLevelBand    VARCHAR(20)       NOT NULL,
    SpendingTier    VARCHAR(20)       NOT NULL,
    ActivitySegment VARCHAR(20)       NOT NULL
);
GO

-- Primary Dimension DimPlayer implementing SCD Type 2 (StartDate, EndDate, IsCurrent)
-- + SCD Type 6 (CurrentVIPLevel alongside HistoricalVIPLevel)
-- + SCD Type 5 (CurrentProfileKey outrigger link)
CREATE TABLE dbo.DimPlayer (
    PlayerKey         INT IDENTITY(1,1) NOT NULL PRIMARY KEY, -- Surrogate Key (Versioned for Type 2)
    PlayerAltKey      VARCHAR(20)       NOT NULL,             -- Durable / Alternate Key (AK: PlayerID for Type 7)
    GamerTag          NVARCHAR(50)      NOT NULL,
    FirstName         NVARCHAR(50)      NOT NULL,
    LastName          NVARCHAR(50)      NOT NULL,
    Email             NVARCHAR(100)     NOT NULL,
    AccountType       VARCHAR(20)       NOT NULL,
    HistoricalVIPLevel VARCHAR(20)      NOT NULL,             -- SCD Type 2 attribute (versioned)
    CurrentVIPLevel   VARCHAR(20)       NOT NULL,             -- SCD Type 6 attribute (overwritten across all versions)
    CityKey           INT               NOT NULL,
    CurrentProfileKey INT               NULL,                 -- SCD Type 5 Outrigger FK
    StartDate         DATE              NOT NULL,
    EndDate           DATE              NULL,
    IsCurrent         BIT               NOT NULL DEFAULT 1,
    CONSTRAINT FK_DimPlayer_DimCity          FOREIGN KEY (CityKey)           REFERENCES dbo.DimCity(CityKey),
    CONSTRAINT FK_DimPlayer_DimPlayerProfile FOREIGN KEY (CurrentProfileKey) REFERENCES dbo.DimPlayerProfile(ProfileKey)
);
GO

CREATE TABLE dbo.DimPaymentMethod (
    PaymentMethodKey  INT          NOT NULL PRIMARY KEY,
    PaymentMethodName NVARCHAR(50) NOT NULL,
    ProviderName      NVARCHAR(50) NOT NULL,
    FeePercentage     DECIMAL(5,4) NOT NULL
);
GO

-- =============================================================================
-- 6. CONSTELLATION SCHEMA FACT TABLES (Fact 1: FactGameSales, Fact 2: FactItemTransactions)
--    (Chapter 2 Slide 3, Chapter 3 Slide 10-11, 14)
-- =============================================================================

-- Fact 1: FactGameSales (Grain: Individual Order Line for Game / DLC purchase)
CREATE TABLE dbo.FactGameSales (
    PlayerKey        INT           NOT NULL,
    GameKey          INT           NOT NULL,
    PublisherKey     INT           NOT NULL,
    PurchaseDateKey  INT           NOT NULL, -- Role-playing Time 1
    ReleaseDateKey   INT           NOT NULL, -- Role-playing Time 2
    RefundDateKey    INT           NULL,     -- Role-playing Time 3 (Nullable)
    PaymentMethodKey INT           NOT NULL,
    OrderNo          INT           NOT NULL, -- Degenerate (Fact) Dimension part 1
    OrderLineNo      INT           NOT NULL, -- Degenerate (Fact) Dimension part 2
    -- Measures
    Quantity         INT           NOT NULL,
    UnitPrice        DECIMAL(10,2) NOT NULL, -- Non-additive (Avg)
    Discount         DECIMAL(5,4)  NOT NULL, -- Non-additive (Avg)
    GrossSalesAmount DECIMAL(12,2) NOT NULL, -- Additive: Quantity * UnitPrice * (1 - Discount)
    TaxAmount        DECIMAL(10,2) NOT NULL, -- Additive: Allocated per order line
    NetSalesAmount   AS (CONVERT(DECIMAL(12,2), GrossSalesAmount - TaxAmount)) PERSISTED, -- Derived Measure (/NetSalesAmount)
    CONSTRAINT PK_FactGameSales PRIMARY KEY (OrderNo, OrderLineNo), -- AK / Fact Key as in Chapter 3 Slide 14
    CONSTRAINT FK_FactGameSales_DimPlayer        FOREIGN KEY (PlayerKey)        REFERENCES dbo.DimPlayer(PlayerKey),
    CONSTRAINT FK_FactGameSales_DimGame          FOREIGN KEY (GameKey)          REFERENCES dbo.DimGame(GameKey),
    CONSTRAINT FK_FactGameSales_DimPublisher     FOREIGN KEY (PublisherKey)     REFERENCES dbo.DimPublisher(PublisherKey),
    CONSTRAINT FK_FactGameSales_PurchaseDate     FOREIGN KEY (PurchaseDateKey)  REFERENCES dbo.DimTime(TimeKey),
    CONSTRAINT FK_FactGameSales_ReleaseDate      FOREIGN KEY (ReleaseDateKey)   REFERENCES dbo.DimTime(TimeKey),
    CONSTRAINT FK_FactGameSales_RefundDate       FOREIGN KEY (RefundDateKey)    REFERENCES dbo.DimTime(TimeKey),
    CONSTRAINT FK_FactGameSales_DimPaymentMethod FOREIGN KEY (PaymentMethodKey) REFERENCES dbo.DimPaymentMethod(PaymentMethodKey)
);
GO

-- Fact 2: FactItemTransactions (Grain: Individual Order Line for In-Game Virtual Item / Pass / Key)
CREATE TABLE dbo.FactItemTransactions (
    PlayerKey         INT           NOT NULL,
    ProfileKey        INT           NOT NULL, -- SCD Type 4 Mini-dimension link
    ItemKey           INT           NOT NULL,
    GameKey           INT           NOT NULL,
    PublisherKey      INT           NOT NULL,
    PurchaseDateKey   INT           NOT NULL, -- Role-playing Time 1
    SettlementDateKey INT           NOT NULL, -- Role-playing Time 2
    RefundDateKey     INT           NULL,     -- Role-playing Time 3
    PaymentMethodKey  INT           NOT NULL,
    TxOrderNo         INT           NOT NULL, -- Degenerate Dimension part 1
    TxOrderLineNo     INT           NOT NULL, -- Degenerate Dimension part 2
    -- Measures
    Quantity          INT           NOT NULL,
    UnitPrice         DECIMAL(10,2) NOT NULL,
    Discount          DECIMAL(5,4)  NOT NULL,
    GrossItemAmount   DECIMAL(12,2) NOT NULL,
    TaxAmount         DECIMAL(10,2) NOT NULL,
    PlatformFeeAmount DECIMAL(10,2) NOT NULL,
    NetItemRevenue    AS (CONVERT(DECIMAL(12,2), GrossItemAmount - TaxAmount - PlatformFeeAmount)) PERSISTED,
    WalletBalanceAfter DECIMAL(12,2) NOT NULL, -- Semi-additive Measure (+! across Time: LastNonEmpty / Avg)
    CONSTRAINT PK_FactItemTransactions PRIMARY KEY (TxOrderNo, TxOrderLineNo),
    CONSTRAINT FK_FactItemTx_DimPlayer        FOREIGN KEY (PlayerKey)         REFERENCES dbo.DimPlayer(PlayerKey),
    CONSTRAINT FK_FactItemTx_DimPlayerProfile FOREIGN KEY (ProfileKey)        REFERENCES dbo.DimPlayerProfile(ProfileKey),
    CONSTRAINT FK_FactItemTx_DimItem          FOREIGN KEY (ItemKey)           REFERENCES dbo.DimItem(ItemKey),
    CONSTRAINT FK_FactItemTx_DimGame          FOREIGN KEY (GameKey)           REFERENCES dbo.DimGame(GameKey),
    CONSTRAINT FK_FactItemTx_DimPublisher     FOREIGN KEY (PublisherKey)      REFERENCES dbo.DimPublisher(PublisherKey),
    CONSTRAINT FK_FactItemTx_PurchaseDate     FOREIGN KEY (PurchaseDateKey)   REFERENCES dbo.DimTime(TimeKey),
    CONSTRAINT FK_FactItemTx_SettlementDate   FOREIGN KEY (SettlementDateKey) REFERENCES dbo.DimTime(TimeKey),
    CONSTRAINT FK_FactItemTx_RefundDate       FOREIGN KEY (RefundDateKey)     REFERENCES dbo.DimTime(TimeKey),
    CONSTRAINT FK_FactItemTx_DimPaymentMethod FOREIGN KEY (PaymentMethodKey)  REFERENCES dbo.DimPaymentMethod(PaymentMethodKey)
);
GO

