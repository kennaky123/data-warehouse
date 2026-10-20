-- =============================================================================
-- FILE: 03_MockData_ETL_Load.sql
-- PROJECT: Digital Game Store & In-Game Items Data Warehouse
-- DESCRIPTION:
--   1. Populates GameStoreOLTP with realistic publishers, games (Diablo IV,
--      Forza Horizon 5, CS2, Elden Ring, Cyberpunk 2077, Baldur's Gate 3, etc.),
--      virtual items (CS2 Armory Pass, Mann Co. Supply Crate Key, Arcana Skins),
--      players across countries with and without states, and 6,000+ transactions.
--   2. Executes the complete T-SQL ETL pipeline into GameStoreDW including:
--      - DimTime generation (2023-01-01 to 2026-12-31) with Calendar & Fiscal hierarchies
--      - DimContinent -> DimCountry -> DimState -> DimCity (Ragged Hierarchy)
--      - DimPublisher Parent-Child & DimPublisherClosure (Recursive CTE Closure Table)
--      - SCD Type 2 & Type 6 versioning on DimPlayer
--      - FactGameSales & FactItemTransactions loading with ROW_NUMBER() OVER (PARTITION BY ...)
-- =============================================================================

USE GameStoreOLTP;
GO

SET NOCOUNT ON;

-- 1. Seed Publishers (Parent-Child Recursive Hierarchy)
INSERT INTO dbo.Publishers (PublisherID, PublisherName, HeadquartersCity, Region, Country, FoundedYear, ParentStudioID) VALUES
('PUB-MS',   N'Xbox Game Studios (Microsoft Gaming)', N'Redmond',       N'Washington',             N'United States', 2000, NULL),
('PUB-ATVI', N'Activision Blizzard',                  N'Santa Monica',  N'California',             N'United States', 2008, 'PUB-MS'),
('PUB-BLIZ', N'Blizzard Entertainment',               N'Irvine',        N'California',             N'United States', 1991, 'PUB-ATVI'),
('PUB-PG',   N'Playground Games',                     N'Austin',        N'Texas',                  N'United States', 2010, 'PUB-MS'),
('PUB-VALV', N'Valve Corporation',                    N'Bellevue',      N'Washington',             N'United States', 1996, NULL),
('PUB-CDPR', N'CD Projekt',                           N'Warsaw',        NULL,                      N'Poland',        1994, NULL),
('PUB-CDPR-RED', N'CD Projekt RED Studio',            N'Warsaw',        NULL,                      N'Poland',        2002, 'PUB-CDPR'),
('PUB-BAND', N'Bandai Namco Entertainment',           N'Tokyo',         NULL,                      N'Japan',         1955, NULL),
('PUB-FROM', N'FromSoftware',                         N'Tokyo',         NULL,                      N'Japan',         1986, 'PUB-BAND'),
('PUB-UBI',  N'Ubisoft Entertainment',                N'Paris',         N'Ile-de-France',          N'France',        1986, NULL),
('PUB-UBI-MTL', N'Ubisoft Montreal',                  N'Montreal',      N'Quebec',                 N'Canada',        1997, 'PUB-UBI');

-- 2. Seed Categories & SubCategories (Balanced Hierarchy)
INSERT INTO dbo.Categories (CategoryID, CategoryName, DepartmentName, Description) VALUES
(1, N'Full Games',           N'Digital Game Store', N'Standalone base games across PC and Console platforms'),
(2, N'DLC & Expansions',     N'Digital Game Store', N'Downloadable content, story expansions, and season packs'),
(3, N'In-Game Passes & Keys',N'Virtual Item Economy', N'Battle passes, armory passes, loot crate keys, and event tickets'),
(4, N'Cosmetic Skins',       N'Virtual Item Economy', N'Weapon finishes, character skins, heirlooms, and mounts');

INSERT INTO dbo.SubCategories (SubCategoryID, SubCategoryName, CategoryID) VALUES
(101, N'AAA Action & RPG Titles', 1),
(102, N'Competitive & Racing Titles', 1),
(201, N'Major Story Expansions', 2),
(202, N'Car & Content Packs', 2),
(301, N'Season & Armory Passes', 3),
(302, N'Crate & Case Keys', 3),
(401, N'Weapon Skins & Knives', 4),
(402, N'Hero Arcana & Mounts', 4);

-- 3. Seed Game Engines (Parallel Hierarchy on Game)
INSERT INTO dbo.GameEngines (EngineID, EngineName, EngineVendor, LicenseType) VALUES
(1, N'Source 2 Engine',      N'Valve Corporation',          N'Proprietary'),
(2, N'Blizzard Proprietary', N'Blizzard Entertainment',     N'Proprietary'),
(3, N'ForzaTech Engine',     N'Turn 10 / Playground Games', N'Proprietary'),
(4, N'REDengine 4',          N'CD Projekt RED',             N'Proprietary'),
(5, N'Unreal Engine 5',      N'Epic Games',                 N'Commercial Royalty'),
(6, N'Snowdrop / Anvil',     N'Ubisoft',                    N'Proprietary');

-- 4. Seed Games
INSERT INTO dbo.Games (GameID, GameTitle, ProductType, SubCategoryID, EngineID, PublisherID, ReleaseDate, ListPrice, AgeRating, IsDiscontinued) VALUES
('GM-D4',     N'Diablo IV',                              'BaseGame',  101, 2, 'PUB-BLIZ',    '2023-06-05', 69.99, 'M',     0),
('GM-D4-VOH', N'Diablo IV: Vessel of Hatred',            'Expansion', 201, 2, 'PUB-BLIZ',    '2024-10-08', 39.99, 'M',     0),
('GM-FH5',    N'Forza Horizon 5',                        'BaseGame',  102, 3, 'PUB-PG',      '2021-11-09', 59.99, 'E',     0),
('GM-FH5-HW', N'Forza Horizon 5: Hot Wheels DLC',        'DLC',       202, 3, 'PUB-PG',      '2022-07-19', 19.99, 'E',     0),
('GM-CS2',    N'Counter-Strike 2 Prime Status',          'BaseGame',  102, 1, 'PUB-VALV',    '2023-09-27', 14.99, 'M',     0),
('GM-DOTA2',  N'Dota 2 Collector Bundle',                'BaseGame',  102, 1, 'PUB-VALV',    '2013-07-09', 29.99, 'T',     0),
('GM-CP77',   N'Cyberpunk 2077',                         'BaseGame',  101, 4, 'PUB-CDPR-RED','2020-12-10', 59.99, 'M',     0),
('GM-CP77-PL',N'Cyberpunk 2077: Phantom Liberty',        'Expansion', 201, 4, 'PUB-CDPR-RED','2023-09-26', 29.99, 'M',     0),
('GM-ER',     N'Elden Ring',                             'BaseGame',  101, 5, 'PUB-FROM',    '2022-02-25', 59.99, 'M',     0),
('GM-ER-SOTE',N'Elden Ring: Shadow of the Erdtree',      'Expansion', 201, 5, 'PUB-FROM',    '2024-06-21', 39.99, 'M',     0),
('GM-AC-SHD', N'Assassins Creed Shadows',                'BaseGame',  101, 6, 'PUB-UBI-MTL', '2025-02-14', 69.99, 'M',     0);

-- 5. Seed Genres & GameGenres (Many-to-Many with Distributing WeightFactor sum = 1.0 per Game)
INSERT INTO dbo.Genres (GenreID, GenreName, SuperGenre, Description) VALUES
(1, N'Action RPG',        N'Role-Playing', N'Hack and slash or real-time combat role-playing games'),
(2, N'Open World',        N'Adventure',    N'Nonlinear open world exploration games'),
(3, N'Tactical Shooter',  N'Shooter',      N'Competitive first-person tactical shooters'),
(4, N'Racing Simulation', N'Sports & Racing', N'Arcade and simulation motor racing'),
(5, N'MOBA & Strategy',   N'Strategy',     N'Multiplayer online battle arena and real-time strategy'),
(6, N'Stealth Action',    N'Action',       N'Stealth-focused action adventure titles');

INSERT INTO dbo.GameGenres (GameID, GenreID, WeightFactor, IsPrimaryGenre) VALUES
('GM-D4',      1, 0.7000, 1), ('GM-D4',      2, 0.3000, 0),
('GM-D4-VOH',  1, 0.8000, 1), ('GM-D4-VOH',  2, 0.2000, 0),
('GM-FH5',     4, 0.6000, 1), ('GM-FH5',     2, 0.4000, 0),
('GM-FH5-HW',  4, 1.0000, 1),
('GM-CS2',     3, 1.0000, 1),
('GM-DOTA2',   5, 0.7500, 1), ('GM-DOTA2',   1, 0.2500, 0),
('GM-CP77',    1, 0.5000, 1), ('GM-CP77',    2, 0.3000, 0), ('GM-CP77', 3, 0.2000, 0),
('GM-CP77-PL', 1, 0.5000, 1), ('GM-CP77-PL', 6, 0.5000, 0),
('GM-ER',      1, 0.6000, 1), ('GM-ER',      2, 0.4000, 0),
('GM-ER-SOTE', 1, 0.7000, 1), ('GM-ER-SOTE', 2, 0.3000, 0),
('GM-AC-SHD',  6, 0.6000, 1), ('GM-AC-SHD',  2, 0.4000, 0);

-- 6. Seed In-Game Items
INSERT INTO dbo.InGameItems (ItemID, ItemName, GameID, SubCategoryID, Rarity, IsTradable, BasePrice) VALUES
('ITM-CS2-PASS', N'CS2 The Armory Pass',                    'GM-CS2',   301, 'Rare',      0, 15.99),
('ITM-CS2-KEY',  N'CS2 Gallery Case Key',                   'GM-CS2',   302, 'Common',    0,  2.49),
('ITM-CS2-AK47', N'AK-47 | Gold Arabesque (Factory New)',   'GM-CS2',   401, 'Immortal',  1, 249.99),
('ITM-CS2-KAR',  N'Karambit | Doppler Sapphire',            'GM-CS2',   401, 'Immortal',  1, 499.99),
('ITM-D4-BP',    N'Diablo IV Accelerated Battle Pass',      'GM-D4',    301, 'Legendary', 0, 24.99),
('ITM-D4-MNT',   N'Diablo IV Hellborn Carapace Mount Pack', 'GM-D4',    402, 'Mythical',  0, 19.99),
('ITM-DOTA-ARC', N'Bladeform Legacy Juggernaut Arcana',     'GM-DOTA2', 402, 'Arcana',    1, 34.99),
('ITM-FH5-VIP',  N'Forza Horizon 5 VIP Membership Pass',    'GM-FH5',   301, 'Legendary', 0, 19.99);

-- 7. Seed Payment Methods
INSERT INTO dbo.PaymentMethods (PaymentMethodID, PaymentMethodName, ProviderName, FeePercentage) VALUES
(1, N'Steam Wallet',       N'Valve Payments', 0.0100),
(2, N'Visa / MasterCard',  N'Stripe Global',  0.0250),
(3, N'PayPal Express',     N'PayPal Inc.',    0.0290),
(4, N'MoMo / VNPay QR',    N'VNPay Gateway',  0.0150);

-- 8. Seed Players (Across US, Canada, Germany, France, Poland, Vietnam, Singapore, Japan, South Korea)
INSERT INTO dbo.Players (PlayerID, GamerTag, FirstName, LastName, Email, AccountType, VIPLevel, City, Region, Country, CreatedDate, WalletBalance) VALUES
('PL-001', N'ShadowSlayer99', N'Alex',    N'Mercer',    N'alex.m@gamer.us',     'Individual', 'Platinum', N'Los Angeles',      N'California',             N'United States', '2022-01-15', 145.50),
('PL-002', N'ValkyrieQueen',  N'Sarah',   N'Connor',    N's.connor@sky.us',     'Individual', 'Gold',     N'Seattle',          N'Washington',             N'United States', '2022-03-10',  82.00),
('PL-003', N'TexanSniper',    N'Colt',    N'McCoy',     N'colt@austin.us',      'Individual', 'Silver',   N'Austin',           N'Texas',                  N'United States', '2022-06-20',  34.20),
('PL-004', N'GothamKnight',   N'Bruce',   N'Wayne',     N'bruce@wayne.us',      'EsportsOrg', 'Diamond',  N'New York City',    N'New York',               N'United States', '2021-11-01', 950.00),
('PL-005', N'MapleLeafPro',   N'Liam',    N'Tremblay',  N'liam@toronto.ca',     'Individual', 'Gold',     N'Toronto',          N'Ontario',                N'Canada',        '2023-01-05',  65.00),
('PL-006', N'MontrealAce',    N'Chloe',   N'Dubois',    N'chloe@mtl.ca',        'Individual', 'Silver',   N'Montreal',         N'Quebec',                 N'Canada',        '2023-02-18',  40.00),
('PL-007', N'RheinMeister',   N'Lukas',   N'Schmidt',   N'lukas@koeln.de',      'EsportsOrg', 'Diamond',  N'Cologne',          N'North Rhine-Westphalia', N'Germany',       '2022-04-12', 620.00),
('PL-008', N'BayernHunter',   N'Hannah',  N'Weber',     N'hannah@munich.de',    'Individual', 'Gold',     N'Munich',           N'Bayern',                 N'Germany',       '2022-08-22', 110.00),
('PL-009', N'ParisianPhantom',N'Lucas',   N'Martin',    N'lucas@paris.fr',      'Individual', 'Platinum', N'Paris',            N'Ile-de-France',          N'France',        '2022-09-10', 210.00),
('PL-010', N'LyonTemplar',    N'Emma',    N'Bernard',   N'emma@lyon.fr',        'Individual', 'Bronze',   N'Lyon',             N'Auvergne-Rhone-Alpes',   N'France',        '2023-05-01',  15.00),
('PL-011', N'WitcherGeralt',  N'Jakub',   N'Kowalski',  N'jakub@warsaw.pl',     'Individual', 'Gold',     N'Warsaw',           NULL,                      N'Poland',        '2022-02-14',  95.00),
('PL-012', N'DragonDanang',   N'Minh',    N'Nguyen',    N'minh.nguyen@vku.vn',  'Individual', 'Diamond',  N'Da Nang',          NULL,                      N'Vietnam',       '2022-01-10', 380.00),
('PL-013', N'SaigonStriker',  N'Tuan',    N'Le',        N'tuan.le@hcm.vn',      'Individual', 'Gold',     N'Ho Chi Minh City', NULL,                      N'Vietnam',       '2022-07-07', 125.00),
('PL-014', N'HanoiLegend',    N'Linh',    N'Pham',      N'linh.pham@hn.vn',     'Individual', 'Platinum', N'Hanoi',            NULL,                      N'Vietnam',       '2023-03-15', 190.00),
('PL-015', N'MerlionApex',    N'Wei',     N'Tan',       N'wei.tan@sg.com',      'EsportsOrg', 'Diamond',  N'Singapore',        NULL,                      N'Singapore',     '2021-12-20', 840.00),
('PL-016', N'TokyoSamurai',   N'Kenji',   N'Sato',      N'kenji@tokyo.jp',      'Individual', 'Platinum', N'Tokyo',            NULL,                      N'Japan',         '2022-05-19', 310.00),
('PL-017', N'SeoulT1Fan',     N'Minho',   N'Kim',       N'minho@seoul.kr',      'EsportsOrg', 'Diamond',  N'Seoul',            NULL,                      N'South Korea',   '2022-01-25', 790.00),
('PL-018', N'BayAreaWizard',  N'kevin',   N'Chen',      N'k.chen@sf.us',        'Individual', 'Silver',   N'San Francisco',    N'California',             N'United States', '2023-04-11',  55.00);

-- 9. Generate 3,000 Game Orders (~5,000 Order Lines) and 3,000 Item Orders (~5,000 Item Lines)
--    Total: ~10,000 transaction rows across 2024, 2025, and 2026
DECLARE @i INT = 1;
WHILE @i <= 3000
BEGIN
    DECLARE @PlayerID VARCHAR(20) = 'PL-' + RIGHT('000' + CAST(((@i % 18) + 1) AS VARCHAR(3)), 3);
    DECLARE @DaysOffset INT = (@i * 7) % 1050; -- Spans 2024-01-01 to 2026-11-15
    DECLARE @PurchaseDate DATE = DATEADD(DAY, @DaysOffset, '2024-01-01');
    DECLARE @ReleaseDateRef DATE = DATEADD(DAY, -((@i % 180) + 1), @PurchaseDate);
    DECLARE @RefundDate DATE = CASE WHEN @i % 25 = 0 THEN DATEADD(DAY, 3, @PurchaseDate) ELSE NULL END;
    DECLARE @PaymentMethodID INT = (@i % 4) + 1;
    DECLARE @Tax DECIMAL(10,2) = ROUND(2.50 + (@i % 7) * 1.25, 2);

    INSERT INTO dbo.Orders (PlayerID, PurchaseDate, ReleaseDateRef, RefundDate, PaymentMethodID, OrderTaxAmount)
    VALUES (@PlayerID, @PurchaseDate, @ReleaseDateRef, @RefundDate, @PaymentMethodID, @Tax);

    DECLARE @NewOrderID INT = SCOPE_IDENTITY();

    -- Primary Game Line
    DECLARE @GameIdx INT = (@i % 11) + 1;
    DECLARE @GameID VARCHAR(20) = CHOOSE(@GameIdx, 'GM-D4','GM-D4-VOH','GM-FH5','GM-FH5-HW','GM-CS2','GM-DOTA2','GM-CP77','GM-CP77-PL','GM-ER','GM-ER-SOTE','GM-AC-SHD');
    DECLARE @Price DECIMAL(10,2) = (SELECT ListPrice FROM dbo.Games WHERE GameID = @GameID);
    DECLARE @Disc DECIMAL(5,4) = CASE WHEN @i % 5 = 0 THEN 0.2000 WHEN @i % 3 = 0 THEN 0.1000 ELSE 0.0000 END;
    DECLARE @Qty INT = CASE WHEN @i % 10 = 0 THEN 2 ELSE 1 END;

    INSERT INTO dbo.OrderDetails (OrderID, GameID, Quantity, UnitPrice, Discount)
    VALUES (@NewOrderID, @GameID, @Qty, @Price, @Disc);

    -- Second Game Line on 65% of orders to demonstrate multi-line OrderLineNo & tax allocation
    IF @i % 3 <> 0
    BEGIN
        DECLARE @GameIdx2 INT = ((@i + 4) % 11) + 1;
        DECLARE @GameID2 VARCHAR(20) = CHOOSE(@GameIdx2, 'GM-D4','GM-D4-VOH','GM-FH5','GM-FH5-HW','GM-CS2','GM-DOTA2','GM-CP77','GM-CP77-PL','GM-ER','GM-ER-SOTE','GM-AC-SHD');
        IF @GameID2 <> @GameID
        BEGIN
            DECLARE @Price2 DECIMAL(10,2) = (SELECT ListPrice FROM dbo.Games WHERE GameID = @GameID2);
            INSERT INTO dbo.OrderDetails (OrderID, GameID, Quantity, UnitPrice, Discount)
            VALUES (@NewOrderID, @GameID2, 1, @Price2, @Disc);
        END
    END

    -- Item Order
    INSERT INTO dbo.ItemOrders (PlayerID, PurchaseDate, SettlementDate, RefundDate, PaymentMethodID, TxTaxAmount, PlatformFee)
    VALUES (@PlayerID, @PurchaseDate, DATEADD(DAY, 1, @PurchaseDate), NULL, @PaymentMethodID, ROUND(@Tax * 0.6, 2), ROUND(1.50 + (@i % 5) * 0.75, 2));

    DECLARE @NewTxOrderID INT = SCOPE_IDENTITY();
    DECLARE @ItemIdx INT = (@i % 8) + 1;
    DECLARE @ItemID VARCHAR(20) = CHOOSE(@ItemIdx, 'ITM-CS2-PASS','ITM-CS2-KEY','ITM-CS2-AK47','ITM-CS2-KAR','ITM-D4-BP','ITM-D4-MNT','ITM-DOTA-ARC','ITM-FH5-VIP');
    DECLARE @ItemPrice DECIMAL(10,2) = (SELECT BasePrice FROM dbo.InGameItems WHERE ItemID = @ItemID);
    DECLARE @ItemQty INT = (@i % 4) + 1;

    INSERT INTO dbo.ItemOrderDetails (TxOrderID, ItemID, Quantity, UnitPrice, Discount)
    VALUES (@NewTxOrderID, @ItemID, @ItemQty, @ItemPrice, @Disc);

    IF @i % 2 = 0
    BEGIN
        DECLARE @ItemIdx2 INT = ((@i + 3) % 8) + 1;
        DECLARE @ItemID2 VARCHAR(20) = CHOOSE(@ItemIdx2, 'ITM-CS2-PASS','ITM-CS2-KEY','ITM-CS2-AK47','ITM-CS2-KAR','ITM-D4-BP','ITM-D4-MNT','ITM-DOTA-ARC','ITM-FH5-VIP');
        IF @ItemID2 <> @ItemID
        BEGIN
            DECLARE @ItemPrice2 DECIMAL(10,2) = (SELECT BasePrice FROM dbo.InGameItems WHERE ItemID = @ItemID2);
            INSERT INTO dbo.ItemOrderDetails (TxOrderID, ItemID, Quantity, UnitPrice, Discount)
            VALUES (@NewTxOrderID, @ItemID2, 1, @ItemPrice2, 0.0000);
        END
    END

    SET @i = @i + 1;
END
GO

-- =============================================================================
-- PART 2: ETL LOAD INTO GameStoreDW
-- =============================================================================
USE GameStoreDW;
GO

-- 1. Load TempCities (Simulating Cities.txt Flat File Source)
INSERT INTO dbo.TempCities (City, State, Country) VALUES
(N'Los Angeles',      N'California',             N'United States'),
(N'San Francisco',    N'California',             N'United States'),
(N'Seattle',          N'Washington',             N'United States'),
(N'Bellevue',         N'Washington',             N'United States'),
(N'Redmond',          N'Washington',             N'United States'),
(N'Santa Monica',     N'California',             N'United States'),
(N'Irvine',           N'California',             N'United States'),
(N'Austin',           N'Texas',                  N'United States'),
(N'New York City',    N'New York',               N'United States'),
(N'Toronto',          N'Ontario',                N'Canada'),
(N'Montreal',         N'Quebec',                 N'Canada'),
(N'Cologne',          N'North Rhine-Westphalia', N'Germany'),
(N'Munich',           N'Bayern',                 N'Germany'),
(N'Paris',            N'Ile-de-France',          N'France'),
(N'Lyon',             N'Auvergne-Rhone-Alpes',   N'France'),
(N'Warsaw',           NULL,                      N'Poland'),
(N'Hanoi',            NULL,                      N'Vietnam'),
(N'Da Nang',          NULL,                      N'Vietnam'),
(N'Ho Chi Minh City', NULL,                      N'Vietnam'),
(N'Singapore',        NULL,                      N'Singapore'),
(N'Tokyo',            NULL,                      N'Japan'),
(N'Seoul',            NULL,                      N'South Korea');

-- 2. Load DimContinent, DimCountry, DimState (Simulating Territories.xml Sequence Container)
INSERT INTO dbo.DimContinent (ContinentName) VALUES
(N'North America'), (N'Europe'), (N'Asia');

INSERT INTO dbo.DimCountry (CountryName, CountryCode, CountryCapital, Population, Subdivision, ContinentKey) VALUES
(N'United States', 'US', N'Washington, D.C.', 331002651, N'50 states and 1 federal district', 1),
(N'Canada',        'CA', N'Ottawa',            38005238, N'10 provinces and 3 territories',   1),
(N'Germany',       'DE', N'Berlin',            83783942, N'16 Bundeslander (states)',         2),
(N'France',        'FR', N'Paris',             65273511, N'18 administrative regions',        2),
(N'Poland',        'PL', N'Warsaw',            37846611, N'16 voivodeships',                  2),
(N'Vietnam',       'VN', N'Hanoi',             97338579, N'58 provinces and 5 municipalities',3),
(N'Singapore',     'SG', N'Singapore',          5850342, N'Unitary city-state without states',3),
(N'Japan',         'JP', N'Tokyo',            126476461, N'47 prefectures',                   3),
(N'South Korea',   'KR', N'Seoul',             51269185, N'9 provinces and 8 special cities', 3);

INSERT INTO dbo.DimState (StateName, EnglishStateName, StateType, StateCode, StateCapital, RegionName, RegionCode, CountryKey) VALUES
(N'California',             N'California',             N'state',    'CA',  N'Sacramento',   N'West',             'W',  1),
(N'Washington',             N'Washington',             N'state',    'WA',  N'Olympia',      N'West',             'W',  1),
(N'Texas',                  N'Texas',                  N'state',    'TX',  N'Austin',       N'South',            'S',  1),
(N'New York',               N'New York',               N'state',    'NY',  N'Albany',       N'Northeast',        'NE', 1),
(N'Ontario',                N'Ontario',                N'province', 'ON',  N'Toronto',      N'Central Canada',   'CC', 2),
(N'Quebec',                 N'Quebec',                 N'province', 'QC',  N'Quebec City',  N'Central Canada',   'CC', 2),
(N'Nordrhein-Westfalen',    N'North Rhine-Westphalia', N'state',    'NW',  N'Dusseldorf',   N'Western Germany',  'WG', 3),
(N'Bayern',                 N'Bavaria',                N'state',    'BY',  N'Munich',       N'Southern Germany', 'SG', 3),
(N'Ile-de-France',          N'Ile-de-France',          N'region',   'IDF', N'Paris',        N'North-Central',    'NC', 4),
(N'Auvergne-Rhone-Alpes',   N'Auvergne-Rhone-Alpes',   N'region',   'ARA', N'Lyon',         N'South-East',       'SE', 4);

-- 3. Load DimCity using Conditional Split & Cascading Lookups logic (Chapter 6 Slide 26, 45)
-- Branch 1: State IS NULL -> Direct link to CountryKey (CityHierarchyType = 'DirectCountry')
INSERT INTO dbo.DimCity (CityName, CityHierarchyType, StateKey, CountryKey)
SELECT tc.City, 'DirectCountry', NULL, c.CountryKey
FROM dbo.TempCities tc
INNER JOIN dbo.DimCountry c ON tc.Country = c.CountryName
WHERE tc.State IS NULL;

-- Branch 2: State IS NOT NULL -> Cascading match on StateName, EnglishStateName, StateCode
INSERT INTO dbo.DimCity (CityName, CityHierarchyType, StateKey, CountryKey)
SELECT tc.City, 'WithState', s.StateKey, NULL
FROM dbo.TempCities tc
INNER JOIN dbo.DimCountry c ON (tc.Country = c.CountryName OR tc.Country = c.CountryCode)
INNER JOIN dbo.DimState s   ON s.CountryKey = c.CountryKey
   AND (tc.State = s.StateName OR tc.State = s.EnglishStateName OR tc.State = s.StateCode)
WHERE tc.State IS NOT NULL;
GO

-- 4. Populate DimTime (2020-01-01 to 2026-12-31) with Calendar & Fiscal Hierarchies (Fiscal starts in Feb)
DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate   DATE = '2026-12-31';
WITH DateSeq AS (
    SELECT @StartDate AS Dt
    UNION ALL
    SELECT DATEADD(DAY, 1, Dt) FROM DateSeq WHERE Dt < @EndDate
)
INSERT INTO dbo.DimTime (
    TimeKey, [Date], DayNbWeek, DayNameWeek, DayNbMonth, DayNbYear, WeekNbYear,
    MonthNumber, MonthName, Quarter, Semester, [Year],
    FiscalQuarter, FiscalSemester, FiscalYear, WeekendFlag
)
SELECT
    CONVERT(INT, FORMAT(Dt, 'yyyyMMdd')) AS TimeKey,
    Dt AS [Date],
    DATEPART(WEEKDAY, Dt) AS DayNbWeek,
    DATENAME(WEEKDAY, Dt) AS DayNameWeek,
    DAY(Dt) AS DayNbMonth,
    DATEPART(DAYOFYEAR, Dt) AS DayNbYear,
    DATEPART(WEEK, Dt) AS WeekNbYear,
    MONTH(Dt) AS MonthNumber,
    DATENAME(MONTH, Dt) AS MonthName,
    DATEPART(QUARTER, Dt) AS Quarter,
    CASE WHEN MONTH(Dt) <= 6 THEN 1 ELSE 2 END AS Semester,
    YEAR(Dt) AS [Year],
    -- Alternative Fiscal Hierarchy (Fiscal Year begins in February - Chapter 2 Slide 13)
    CASE
        WHEN MONTH(Dt) IN (2,3,4)   THEN 1
        WHEN MONTH(Dt) IN (5,6,7)   THEN 2
        WHEN MONTH(Dt) IN (8,9,10)  THEN 3
        ELSE 4
    END AS FiscalQuarter,
    CASE WHEN MONTH(Dt) BETWEEN 2 AND 7 THEN 1 ELSE 2 END AS FiscalSemester,
    CASE WHEN MONTH(Dt) = 1 THEN YEAR(Dt) - 1 ELSE YEAR(Dt) END AS FiscalYear,
    CASE WHEN DATENAME(WEEKDAY, Dt) IN (N'Saturday', N'Sunday') THEN 1 ELSE 0 END AS WeekendFlag
FROM DateSeq
OPTION (MAXRECURSION 0);
GO

-- 5. Load DimCategory, DimSubCategory, DimGenre, DimPaymentMethod
INSERT INTO dbo.DimCategory (CategoryKey, CategoryName, DepartmentName, Description)
SELECT CategoryID, CategoryName, DepartmentName, Description FROM GameStoreOLTP.dbo.Categories;

INSERT INTO dbo.DimSubCategory (SubCategoryKey, SubCategoryName, CategoryKey)
SELECT SubCategoryID, SubCategoryName, CategoryID FROM GameStoreOLTP.dbo.SubCategories;

INSERT INTO dbo.DimGenre (GenreKey, GenreName, SuperGenre, Description)
SELECT GenreID, GenreName, SuperGenre, Description FROM GameStoreOLTP.dbo.Genres;

INSERT INTO dbo.DimPaymentMethod (PaymentMethodKey, PaymentMethodName, ProviderName, FeePercentage)
SELECT PaymentMethodID, PaymentMethodName, ProviderName, FeePercentage FROM GameStoreOLTP.dbo.PaymentMethods;

-- 6. Load DimPublisher (Parent-Child) & DimPublisherClosure (Transitive Closure Table)
INSERT INTO dbo.DimPublisher (PublisherAltKey, PublisherName, FoundedYear, CityKey, ParentPublisherKey)
SELECT p.PublisherID, p.PublisherName, p.FoundedYear, c.CityKey, NULL
FROM GameStoreOLTP.dbo.Publishers p
INNER JOIN dbo.DimCity c ON p.HeadquartersCity = c.CityName;

UPDATE dp
SET dp.ParentPublisherKey = parent_dp.PublisherKey
FROM dbo.DimPublisher dp
INNER JOIN GameStoreOLTP.dbo.Publishers src ON dp.PublisherAltKey = src.PublisherID
INNER JOIN dbo.DimPublisher parent_dp       ON src.ParentStudioID = parent_dp.PublisherAltKey;

-- Populate DimPublisherClosure using Recursive CTE (Chapter 6 Slide 54)
WITH PubClosureCTE AS (
    SELECT PublisherKey AS SupervisorPublisherKey, PublisherKey AS SubordinatePublisherKey, 0 AS Distance
    FROM dbo.DimPublisher
    UNION ALL
    SELECT c.SupervisorPublisherKey, p.PublisherKey AS SubordinatePublisherKey, c.Distance + 1
    FROM PubClosureCTE c
    INNER JOIN dbo.DimPublisher p ON p.ParentPublisherKey = c.SubordinatePublisherKey
)
INSERT INTO dbo.DimPublisherClosure (SupervisorPublisherKey, SubordinatePublisherKey, Distance)
SELECT SupervisorPublisherKey, SubordinatePublisherKey, Distance FROM PubClosureCTE;
GO

-- 7. Load DimGame, BridgeGameGenre, DimItem
INSERT INTO dbo.DimGame (
    GameAltKey, GameTitle, ProductType, SubCategoryKey,
    EngineName, EngineVendor, LicenseType, PublisherKey,
    ReleaseDate, ListPrice, AgeRating, IsDiscontinued
)
SELECT
    g.GameID, g.GameTitle, g.ProductType, g.SubCategoryID,
    e.EngineName, e.EngineVendor, e.LicenseType, p.PublisherKey,
    g.ReleaseDate, g.ListPrice, g.AgeRating, g.IsDiscontinued
FROM GameStoreOLTP.dbo.Games g
INNER JOIN GameStoreOLTP.dbo.GameEngines e ON g.EngineID = e.EngineID
INNER JOIN dbo.DimPublisher p              ON g.PublisherID = p.PublisherAltKey;

INSERT INTO dbo.BridgeGameGenre (GameKey, GenreKey, WeightFactor, IsPrimaryGenre)
SELECT dg.GameKey, gg.GenreID, gg.WeightFactor, gg.IsPrimaryGenre
FROM GameStoreOLTP.dbo.GameGenres gg
INNER JOIN dbo.DimGame dg ON LTRIM(RTRIM(gg.GameID)) = dg.GameAltKey;

INSERT INTO dbo.DimItem (ItemAltKey, ItemName, GameKey, SubCategoryKey, Rarity, IsTradable, BasePrice)
SELECT i.ItemID, i.ItemName, dg.GameKey, i.SubCategoryID, i.Rarity, i.IsTradable, i.BasePrice
FROM GameStoreOLTP.dbo.InGameItems i
INNER JOIN dbo.DimGame dg ON i.GameID = dg.GameAltKey;
GO

-- 8. Load DimPlayerProfile (SCD Type 4 Mini-dimension) & DimPlayer (SCD Type 2 & Type 6)
INSERT INTO dbo.DimPlayerProfile (VIPLevelBand, SpendingTier, ActivitySegment) VALUES
('Bronze',   'Low Spender',    'Casual'),
('Silver',   'Medium Spender', 'Regular'),
('Gold',     'High Spender',   'Core Gamer'),
('Platinum', 'Whale',          'Hardcore'),
('Diamond',  'Mega Whale',     'Esports / Collector');

-- Insert initial historical version for PL-001 and PL-012 to demonstrate SCD Type 2 & Type 6 versioning
INSERT INTO dbo.DimPlayer (
    PlayerAltKey, GamerTag, FirstName, LastName, Email, AccountType,
    HistoricalVIPLevel, CurrentVIPLevel, CityKey, CurrentProfileKey,
    StartDate, EndDate, IsCurrent
)
SELECT
    p.PlayerID, p.GamerTag, p.FirstName, p.LastName, p.Email, p.AccountType,
    CASE WHEN p.PlayerID IN ('PL-001', 'PL-012') THEN 'Gold' ELSE p.VIPLevel END AS HistoricalVIPLevel,
    p.VIPLevel AS CurrentVIPLevel,
    c.CityKey,
    prof.ProfileKey,
    p.CreatedDate AS StartDate,
    CASE WHEN p.PlayerID IN ('PL-001', 'PL-012') THEN '2025-01-01' ELSE NULL END AS EndDate,
    CASE WHEN p.PlayerID IN ('PL-001', 'PL-012') THEN 0 ELSE 1 END AS IsCurrent
FROM GameStoreOLTP.dbo.Players p
INNER JOIN dbo.DimCity c          ON p.City = c.CityName
INNER JOIN dbo.DimPlayerProfile prof ON p.VIPLevel = prof.VIPLevelBand;

-- Insert upgraded SCD Type 2 current version for PL-001 and PL-012 (from 2025-01-01 onwards)
INSERT INTO dbo.DimPlayer (
    PlayerAltKey, GamerTag, FirstName, LastName, Email, AccountType,
    HistoricalVIPLevel, CurrentVIPLevel, CityKey, CurrentProfileKey,
    StartDate, EndDate, IsCurrent
)
SELECT
    p.PlayerID, p.GamerTag, p.FirstName, p.LastName, p.Email, p.AccountType,
    p.VIPLevel AS HistoricalVIPLevel,
    p.VIPLevel AS CurrentVIPLevel,
    c.CityKey,
    prof.ProfileKey,
    '2025-01-01' AS StartDate,
    NULL AS EndDate,
    1 AS IsCurrent
FROM GameStoreOLTP.dbo.Players p
INNER JOIN dbo.DimCity c             ON p.City = c.CityName
INNER JOIN dbo.DimPlayerProfile prof ON p.VIPLevel = prof.VIPLevelBand
WHERE p.PlayerID IN ('PL-001', 'PL-012');
GO

-- 9. Load FactGameSales using exact SSIS OLE DB Source Query pattern (Chapter 6 Slide 32 & 50)
INSERT INTO dbo.FactGameSales (
    PlayerKey, GameKey, PublisherKey,
    PurchaseDateKey, ReleaseDateKey, RefundDateKey, PaymentMethodKey,
    OrderNo, OrderLineNo,
    Quantity, UnitPrice, Discount, GrossSalesAmount, TaxAmount
)
SELECT
    (SELECT TOP 1 dp.PlayerKey
     FROM dbo.DimPlayer dp
     WHERE dp.PlayerAltKey = o.PlayerID
       AND o.PurchaseDate >= dp.StartDate
       AND (dp.EndDate IS NULL OR o.PurchaseDate < dp.EndDate)
     ORDER BY dp.StartDate DESC) AS PlayerKey,
    dg.GameKey,
    dg.PublisherKey,
    (SELECT t.TimeKey FROM dbo.DimTime t WHERE t.[Date] = o.PurchaseDate)   AS PurchaseDateKey,
    (SELECT t.TimeKey FROM dbo.DimTime t WHERE t.[Date] = o.ReleaseDateRef) AS ReleaseDateKey,
    (SELECT t.TimeKey FROM dbo.DimTime t WHERE t.[Date] = o.RefundDate)     AS RefundDateKey,
    o.PaymentMethodID AS PaymentMethodKey,
    o.OrderID AS OrderNo,
    CONVERT(INT, ROW_NUMBER() OVER (PARTITION BY od.OrderID ORDER BY od.GameID)) AS OrderLineNo,
    od.Quantity,
    od.UnitPrice,
    od.Discount,
    CONVERT(DECIMAL(12,2), od.UnitPrice * (1.0 - od.Discount) * od.Quantity) AS GrossSalesAmount,
    CONVERT(DECIMAL(10,2), o.OrderTaxAmount / COUNT(*) OVER (PARTITION BY od.OrderID)) AS TaxAmount
FROM GameStoreOLTP.dbo.Orders o
INNER JOIN GameStoreOLTP.dbo.OrderDetails od ON o.OrderID = od.OrderID
INNER JOIN dbo.DimGame dg                    ON od.GameID = dg.GameAltKey;
GO

-- 10. Load FactItemTransactions (Fact 2 in Constellation Schema)
INSERT INTO dbo.FactItemTransactions (
    PlayerKey, ProfileKey, ItemKey, GameKey, PublisherKey,
    PurchaseDateKey, SettlementDateKey, RefundDateKey, PaymentMethodKey,
    TxOrderNo, TxOrderLineNo,
    Quantity, UnitPrice, Discount, GrossItemAmount, TaxAmount, PlatformFeeAmount, WalletBalanceAfter
)
SELECT
    dp.PlayerKey,
    dp.CurrentProfileKey AS ProfileKey,
    di.ItemKey,
    di.GameKey,
    dg.PublisherKey,
    (SELECT t.TimeKey FROM dbo.DimTime t WHERE t.[Date] = io.PurchaseDate)   AS PurchaseDateKey,
    (SELECT t.TimeKey FROM dbo.DimTime t WHERE t.[Date] = io.SettlementDate) AS SettlementDateKey,
    (SELECT t.TimeKey FROM dbo.DimTime t WHERE t.[Date] = io.RefundDate)     AS RefundDateKey,
    io.PaymentMethodID AS PaymentMethodKey,
    io.TxOrderID AS TxOrderNo,
    CONVERT(INT, ROW_NUMBER() OVER (PARTITION BY iod.TxOrderID ORDER BY iod.ItemID)) AS TxOrderLineNo,
    iod.Quantity,
    iod.UnitPrice,
    iod.Discount,
    CONVERT(DECIMAL(12,2), iod.UnitPrice * (1.0 - iod.Discount) * iod.Quantity) AS GrossItemAmount,
    CONVERT(DECIMAL(10,2), io.TxTaxAmount / COUNT(*) OVER (PARTITION BY iod.TxOrderID)) AS TaxAmount,
    CONVERT(DECIMAL(10,2), io.PlatformFee / COUNT(*) OVER (PARTITION BY iod.TxOrderID)) AS PlatformFeeAmount,
    p_oltp.WalletBalance AS WalletBalanceAfter
FROM GameStoreOLTP.dbo.ItemOrders io
INNER JOIN GameStoreOLTP.dbo.ItemOrderDetails iod ON io.TxOrderID = iod.TxOrderID
INNER JOIN GameStoreOLTP.dbo.Players p_oltp       ON io.PlayerID  = p_oltp.PlayerID
INNER JOIN dbo.DimItem di                         ON iod.ItemID   = di.ItemAltKey
INNER JOIN dbo.DimGame dg                         ON di.GameKey   = dg.GameKey
CROSS APPLY (
    SELECT TOP 1 PlayerKey, CurrentProfileKey
    FROM dbo.DimPlayer dp_sub
    WHERE dp_sub.PlayerAltKey = io.PlayerID
      AND io.PurchaseDate >= dp_sub.StartDate
      AND (dp_sub.EndDate IS NULL OR io.PurchaseDate < dp_sub.EndDate)
    ORDER BY dp_sub.StartDate DESC
) dp;
GO

-- Summary verification counts
SELECT 'DimContinent' AS TableName, COUNT(*) AS RowCnt FROM dbo.DimContinent
UNION ALL SELECT 'DimCountry', COUNT(*) FROM dbo.DimCountry
UNION ALL SELECT 'DimState', COUNT(*) FROM dbo.DimState
UNION ALL SELECT 'DimCity', COUNT(*) FROM dbo.DimCity
UNION ALL SELECT 'DimTime', COUNT(*) FROM dbo.DimTime
UNION ALL SELECT 'DimPublisher', COUNT(*) FROM dbo.DimPublisher
UNION ALL SELECT 'DimPublisherClosure', COUNT(*) FROM dbo.DimPublisherClosure
UNION ALL SELECT 'DimGame', COUNT(*) FROM dbo.DimGame
UNION ALL SELECT 'BridgeGameGenre', COUNT(*) FROM dbo.BridgeGameGenre
UNION ALL SELECT 'DimItem', COUNT(*) FROM dbo.DimItem
UNION ALL SELECT 'DimPlayer (SCD2/6)', COUNT(*) FROM dbo.DimPlayer
UNION ALL SELECT 'FactGameSales', COUNT(*) FROM dbo.FactGameSales
UNION ALL SELECT 'FactItemTransactions', COUNT(*) FROM dbo.FactItemTransactions;
GO

