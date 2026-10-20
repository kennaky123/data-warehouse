-- =============================================================================
-- FILE: 01_Create_GameStoreOLTP.sql
-- PROJECT: Digital Game Store & In-Game Items Data Warehouse
-- METHODOLOGY: Vaisman & Zimanyi (VKU Data Warehouse Course - Chapters 1 to 6)
-- DESCRIPTION: Creates the 3NF Operational Database (GameStoreOLTP)
-- =============================================================================

USE master;
GO

IF DB_ID('GameStoreOLTP') IS NOT NULL
BEGIN
    ALTER DATABASE GameStoreOLTP SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE GameStoreOLTP;
END
GO

CREATE DATABASE GameStoreOLTP;
GO

USE GameStoreOLTP;
GO

-- 1. Table: Publishers (Recursive Parent-Child Hierarchy in Source)
CREATE TABLE dbo.Publishers (
    PublisherID     VARCHAR(20)   NOT NULL PRIMARY KEY,
    PublisherName   NVARCHAR(100) NOT NULL,
    HeadquartersCity NVARCHAR(60) NOT NULL,
    Region          NVARCHAR(60)  NULL,
    Country         NVARCHAR(60)  NOT NULL,
    FoundedYear     INT           NOT NULL,
    ParentStudioID  VARCHAR(20)   NULL,
    CONSTRAINT FK_Publishers_Parent FOREIGN KEY (ParentStudioID) REFERENCES dbo.Publishers(PublisherID)
);
GO

-- 2. Table: Categories & SubCategories (Balanced Hierarchy in Source)
CREATE TABLE dbo.Categories (
    CategoryID      INT           NOT NULL PRIMARY KEY,
    CategoryName    NVARCHAR(60)  NOT NULL,
    DepartmentName  NVARCHAR(60)  NOT NULL,
    Description     NVARCHAR(255) NULL
);
GO

CREATE TABLE dbo.SubCategories (
    SubCategoryID   INT           NOT NULL PRIMARY KEY,
    SubCategoryName NVARCHAR(60)  NOT NULL,
    CategoryID      INT           NOT NULL,
    CONSTRAINT FK_SubCategories_Categories FOREIGN KEY (CategoryID) REFERENCES dbo.Categories(CategoryID)
);
GO

-- 3. Table: GameEngines (For Parallel Independent Hierarchy on Games)
CREATE TABLE dbo.GameEngines (
    EngineID        INT           NOT NULL PRIMARY KEY,
    EngineName      NVARCHAR(60)  NOT NULL,
    EngineVendor    NVARCHAR(60)  NOT NULL,
    LicenseType     NVARCHAR(40)  NOT NULL
);
GO

-- 4. Table: Games (Base Games & DLCs)
CREATE TABLE dbo.Games (
    GameID          VARCHAR(20)   NOT NULL PRIMARY KEY,
    GameTitle       NVARCHAR(120) NOT NULL,
    ProductType     VARCHAR(20)   NOT NULL CHECK (ProductType IN ('BaseGame', 'DLC', 'Expansion')),
    SubCategoryID   INT           NOT NULL,
    EngineID        INT           NOT NULL,
    PublisherID     VARCHAR(20)   NOT NULL,
    ReleaseDate     DATE          NOT NULL,
    ListPrice       DECIMAL(10,2) NOT NULL,
    AgeRating       VARCHAR(10)   NOT NULL,
    IsDiscontinued  BIT           NOT NULL DEFAULT 0,
    CONSTRAINT FK_Games_SubCategories FOREIGN KEY (SubCategoryID) REFERENCES dbo.SubCategories(SubCategoryID),
    CONSTRAINT FK_Games_Engines       FOREIGN KEY (EngineID)      REFERENCES dbo.GameEngines(EngineID),
    CONSTRAINT FK_Games_Publishers    FOREIGN KEY (PublisherID)   REFERENCES dbo.Publishers(PublisherID)
);
GO

-- 5. Table: Genres & GameGenres (Many-to-Many / Nonstrict Relationship with Distributing Weight)
CREATE TABLE dbo.Genres (
    GenreID         INT           NOT NULL PRIMARY KEY,
    GenreName       NVARCHAR(50)  NOT NULL,
    SuperGenre      NVARCHAR(50)  NOT NULL,
    Description     NVARCHAR(200) NULL
);
GO

CREATE TABLE dbo.GameGenres (
    GameID          VARCHAR(20)   NOT NULL,
    GenreID         INT           NOT NULL,
    WeightFactor    DECIMAL(5,4)  NOT NULL DEFAULT 1.0000,
    IsPrimaryGenre  BIT           NOT NULL DEFAULT 0,
    CONSTRAINT PK_GameGenres PRIMARY KEY (GameID, GenreID),
    CONSTRAINT FK_GameGenres_Games  FOREIGN KEY (GameID)  REFERENCES dbo.Games(GameID),
    CONSTRAINT FK_GameGenres_Genres FOREIGN KEY (GenreID) REFERENCES dbo.Genres(GenreID)
);
GO

-- 6. Table: InGameItems (Virtual Items, Battle Passes, Keys, Skins)
CREATE TABLE dbo.InGameItems (
    ItemID          VARCHAR(20)   NOT NULL PRIMARY KEY,
    ItemName        NVARCHAR(120) NOT NULL,
    GameID          VARCHAR(20)   NOT NULL,
    SubCategoryID   INT           NOT NULL,
    Rarity          VARCHAR(30)   NOT NULL CHECK (Rarity IN ('Common', 'Rare', 'Mythical', 'Legendary', 'Immortal', 'Arcana')),
    IsTradable      BIT           NOT NULL DEFAULT 1,
    BasePrice       DECIMAL(10,2) NOT NULL,
    CONSTRAINT FK_InGameItems_Games         FOREIGN KEY (GameID)        REFERENCES dbo.Games(GameID),
    CONSTRAINT FK_InGameItems_SubCategories FOREIGN KEY (SubCategoryID) REFERENCES dbo.SubCategories(SubCategoryID)
);
GO

-- 7. Table: Players (Customers in Operational System)
CREATE TABLE dbo.Players (
    PlayerID        VARCHAR(20)   NOT NULL PRIMARY KEY,
    GamerTag        NVARCHAR(50)  NOT NULL,
    FirstName       NVARCHAR(50)  NOT NULL,
    LastName        NVARCHAR(50)  NOT NULL,
    Email           NVARCHAR(100) NOT NULL,
    AccountType     VARCHAR(20)   NOT NULL CHECK (AccountType IN ('Individual', 'EsportsOrg')),
    VIPLevel        VARCHAR(20)   NOT NULL CHECK (VIPLevel IN ('Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond')),
    City            NVARCHAR(60)  NOT NULL,
    Region          NVARCHAR(60)  NULL, -- Nullable for countries without states (Singapore, Vietnam, Japan, etc.)
    Country         NVARCHAR(60)  NOT NULL,
    CreatedDate     DATE          NOT NULL,
    WalletBalance   DECIMAL(12,2) NOT NULL DEFAULT 0.00
);
GO

-- 8. Table: PaymentMethods
CREATE TABLE dbo.PaymentMethods (
    PaymentMethodID   INT          NOT NULL PRIMARY KEY,
    PaymentMethodName NVARCHAR(50) NOT NULL,
    ProviderName      NVARCHAR(50) NOT NULL,
    FeePercentage     DECIMAL(5,4) NOT NULL
);
GO

-- 9. Table: Orders & OrderDetails (Game & DLC Purchases)
CREATE TABLE dbo.Orders (
    OrderID         INT IDENTITY(10001,1) NOT NULL PRIMARY KEY,
    PlayerID        VARCHAR(20)   NOT NULL,
    PurchaseDate    DATE          NOT NULL,
    ReleaseDateRef  DATE          NOT NULL,
    RefundDate      DATE          NULL,
    PaymentMethodID INT           NOT NULL,
    OrderTaxAmount  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_Orders_Players        FOREIGN KEY (PlayerID)        REFERENCES dbo.Players(PlayerID),
    CONSTRAINT FK_Orders_PaymentMethods FOREIGN KEY (PaymentMethodID) REFERENCES dbo.PaymentMethods(PaymentMethodID)
);
GO

CREATE TABLE dbo.OrderDetails (
    OrderID         INT           NOT NULL,
    GameID          VARCHAR(20)   NOT NULL,
    Quantity        INT           NOT NULL CHECK (Quantity > 0),
    UnitPrice       DECIMAL(10,2) NOT NULL,
    Discount        DECIMAL(5,4)  NOT NULL DEFAULT 0.0000 CHECK (Discount >= 0 AND Discount <= 1),
    CONSTRAINT PK_OrderDetails PRIMARY KEY (OrderID, GameID),
    CONSTRAINT FK_OrderDetails_Orders FOREIGN KEY (OrderID) REFERENCES dbo.Orders(OrderID),
    CONSTRAINT FK_OrderDetails_Games  FOREIGN KEY (GameID)  REFERENCES dbo.Games(GameID)
);
GO

-- 10. Table: ItemOrders & ItemOrderDetails (Virtual Item / Skin / Key Transactions)
CREATE TABLE dbo.ItemOrders (
    TxOrderID       INT IDENTITY(50001,1) NOT NULL PRIMARY KEY,
    PlayerID        VARCHAR(20)   NOT NULL,
    PurchaseDate    DATE          NOT NULL,
    SettlementDate  DATE          NOT NULL,
    RefundDate      DATE          NULL,
    PaymentMethodID INT           NOT NULL,
    TxTaxAmount     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    PlatformFee     DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    CONSTRAINT FK_ItemOrders_Players        FOREIGN KEY (PlayerID)        REFERENCES dbo.Players(PlayerID),
    CONSTRAINT FK_ItemOrders_PaymentMethods FOREIGN KEY (PaymentMethodID) REFERENCES dbo.PaymentMethods(PaymentMethodID)
);
GO

CREATE TABLE dbo.ItemOrderDetails (
    TxOrderID       INT           NOT NULL,
    ItemID          VARCHAR(20)   NOT NULL,
    Quantity        INT           NOT NULL CHECK (Quantity > 0),
    UnitPrice       DECIMAL(10,2) NOT NULL,
    Discount        DECIMAL(5,4)  NOT NULL DEFAULT 0.0000 CHECK (Discount >= 0 AND Discount <= 1),
    CONSTRAINT PK_ItemOrderDetails PRIMARY KEY (TxOrderID, ItemID),
    CONSTRAINT FK_ItemOrderDetails_ItemOrders  FOREIGN KEY (TxOrderID) REFERENCES dbo.ItemOrders(TxOrderID),
    CONSTRAINT FK_ItemOrderDetails_InGameItems FOREIGN KEY (ItemID)    REFERENCES dbo.InGameItems(ItemID)
);
GO

