/*
  Corrección y enriquecimiento didáctico para Northwind.MySQL5.sql
  Versión 2: ajustada a la versión corregida del script Northwind sin espacios en nombres.
  Ejecutar DESPUÉS de cargar Northwind.MySQL5.sql.
  Compatible con MySQL 5.x / MySQL 8.x.

  Nota:
  - El script usa los nombres reales del archivo revisado:
    Customers, Suppliers, Orders, OrderDetails, Products, Employees.
  - No usa nombres con espacios como `Order Details`.
  - Las columnas agregadas son condicionales para evitar error si el script se ejecuta más de una vez.
*/

USE northwind;
SET SQL_SAFE_UPDATES = 0;
SET FOREIGN_KEY_CHECKS = 0;

DELIMITER $$

DROP PROCEDURE IF EXISTS AddColumnIfMissing $$
CREATE PROCEDURE AddColumnIfMissing(
  IN p_table_name VARCHAR(64),
  IN p_column_name VARCHAR(64),
  IN p_column_definition TEXT
)
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = p_table_name
      AND COLUMN_NAME = p_column_name
  ) THEN
    SET @ddl = CONCAT(
      'ALTER TABLE `', p_table_name, '` ADD COLUMN `', p_column_name, '` ',
      p_column_definition
    );
    PREPARE stmt FROM @ddl;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END $$

DROP PROCEDURE IF EXISTS AddIndexIfMissing $$
CREATE PROCEDURE AddIndexIfMissing(
  IN p_table_name VARCHAR(64),
  IN p_index_name VARCHAR(64),
  IN p_index_ddl TEXT
)
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME = p_table_name
      AND INDEX_NAME = p_index_name
  ) THEN
    SET @ddl = p_index_ddl;
    PREPARE stmt FROM @ddl;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;
  END IF;
END $$

DELIMITER ;

/* =========================================================
   1) CLIENTES Y PROVEEDORES: nombre y apellidos separados
      CP8 #1 y CP10 #1, #3.
   ========================================================= */

CALL AddColumnIfMissing('Customers', 'FirstName', 'VARCHAR(30) NULL AFTER `ContactName`');
CALL AddColumnIfMissing('Customers', 'LastName',  'VARCHAR(60) NULL AFTER `FirstName`');

UPDATE `Customers`
SET
  `FirstName` = CASE
                  WHEN `ContactName` IS NULL OR TRIM(`ContactName`) = '' THEN NULL
                  ELSE SUBSTRING_INDEX(TRIM(`ContactName`), ' ', 1)
                END,
  `LastName` = CASE
                 WHEN `ContactName` IS NULL OR TRIM(`ContactName`) = '' THEN NULL
                 WHEN LOCATE(' ', TRIM(`ContactName`)) = 0 THEN ''
                 ELSE TRIM(SUBSTRING(TRIM(`ContactName`), LOCATE(' ', TRIM(`ContactName`)) + 1))
               END;

/* Traducción mínima para que el cargo “Propietario” exista literalmente. */
UPDATE `Customers`
SET `ContactTitle` = 'Propietario'
WHERE `ContactTitle` = 'Owner';

CALL AddColumnIfMissing('Suppliers', 'FirstName', 'VARCHAR(30) NULL AFTER `ContactName`');
CALL AddColumnIfMissing('Suppliers', 'LastName',  'VARCHAR(60) NULL AFTER `FirstName`');

UPDATE `Suppliers`
SET
  `FirstName` = CASE
                  WHEN `ContactName` IS NULL OR TRIM(`ContactName`) = '' THEN NULL
                  ELSE SUBSTRING_INDEX(TRIM(`ContactName`), ' ', 1)
                END,
  `LastName` = CASE
                 WHEN `ContactName` IS NULL OR TRIM(`ContactName`) = '' THEN NULL
                 WHEN LOCATE(' ', TRIM(`ContactName`)) = 0 THEN ''
                 ELSE TRIM(SUBSTRING(TRIM(`ContactName`), LOCATE(' ', TRIM(`ContactName`)) + 1))
               END;

/* =========================================================
   2) PEDIDOS: tipo de pago y fecha de pago
      CP8 #4, #8, #9, #15.
   ========================================================= */

CALL AddColumnIfMissing('Orders', 'PaymentType', 'VARCHAR(20) NULL AFTER `Freight`');
CALL AddColumnIfMissing('Orders', 'PaymentDate', 'DATETIME NULL AFTER `PaymentType`');

UPDATE `Orders`
SET
  `PaymentType` = CASE
                    WHEN MOD(`OrderID`, 5) = 0 THEN 'Cheque'
                    WHEN MOD(`OrderID`, 5) = 1 THEN 'Efectivo'
                    WHEN MOD(`OrderID`, 5) = 2 THEN 'Tarjeta'
                    WHEN MOD(`OrderID`, 5) = 3 THEN 'Transferencia'
                    ELSE 'Efectivo'
                  END,
  `PaymentDate` = CASE
                    WHEN `OrderDate` IS NULL THEN NULL
                    ELSE DATE_ADD(`OrderDate`, INTERVAL MOD(`OrderID`, 7) DAY)
                  END;

/* Casos controlados para consultas de fechas. */
UPDATE `Orders`
SET `ShippedDate` = DATE_SUB(`OrderDate`, INTERVAL 1 DAY)
WHERE `OrderID` IN (10248, 10249, 10250)
  AND `OrderDate` IS NOT NULL;

UPDATE `Orders`
SET `ShippedDate` = NULL
WHERE `OrderID` IN (11075, 11076, 11077);

CALL AddIndexIfMissing('Orders', 'IX_Orders_PaymentType',
  'CREATE INDEX `IX_Orders_PaymentType` ON `Orders` (`PaymentType`)');

CALL AddIndexIfMissing('Orders', 'IX_Orders_PaymentDate',
  'CREATE INDEX `IX_Orders_PaymentDate` ON `Orders` (`PaymentDate`)');

/* =========================================================
   3) PRODUCTOS: precio de listado y costo estándar
      CP8 #10, #14 y CP10 #9-#12.
   ========================================================= */

CALL AddColumnIfMissing('Products', 'ListPrice',    'DECIMAL(10,4) NULL AFTER `UnitPrice`');
CALL AddColumnIfMissing('Products', 'StandardCost', 'DECIMAL(10,4) NULL AFTER `ListPrice`');

UPDATE `Products`
SET
  `ListPrice` = IFNULL(`UnitPrice`, 0),
  `StandardCost` = ROUND(IFNULL(`UnitPrice`, 0) * 0.65, 4);

CALL AddIndexIfMissing('Products', 'IX_Products_ListPrice',
  'CREATE INDEX `IX_Products_ListPrice` ON `Products` (`ListPrice`)');

CALL AddIndexIfMissing('Products', 'IX_Products_StandardCost',
  'CREATE INDEX `IX_Products_StandardCost` ON `Products` (`StandardCost`)');

/* =========================================================
   4) TRANSACCIONES
      CP8 #6.
   ========================================================= */

DROP TABLE IF EXISTS `Transactions`;

CREATE TABLE `Transactions` (
  `TransactionID` INTEGER NOT NULL AUTO_INCREMENT,
  `OrderID` INTEGER NOT NULL,
  `CustomerID` VARCHAR(5) NULL,
  `TransactionDate` DATETIME NULL,
  `TransactionType` VARCHAR(20) NOT NULL DEFAULT 'Venta',
  `PaymentType` VARCHAR(20) NULL,
  `Quantity` SMALLINT NOT NULL,
  `Amount` DECIMAL(10,4) NOT NULL DEFAULT 0,
  CONSTRAINT `PK_Transactions` PRIMARY KEY (`TransactionID`),
  CONSTRAINT `FK_Transactions_Orders` FOREIGN KEY (`OrderID`) REFERENCES `Orders` (`OrderID`),
  CONSTRAINT `FK_Transactions_Customers` FOREIGN KEY (`CustomerID`) REFERENCES `Customers` (`CustomerID`)
);

INSERT INTO `Transactions`
  (`OrderID`, `CustomerID`, `TransactionDate`, `TransactionType`, `PaymentType`, `Quantity`, `Amount`)
SELECT
  o.`OrderID`,
  o.`CustomerID`,
  IFNULL(o.`PaymentDate`, o.`OrderDate`) AS `TransactionDate`,
  'Venta' AS `TransactionType`,
  o.`PaymentType`,
  od.`Quantity`,
  ROUND((od.`UnitPrice` * od.`Quantity`) * (1 - od.`Discount`), 4) AS `Amount`
FROM `Orders` o
INNER JOIN `OrderDetails` od ON od.`OrderID` = o.`OrderID`;

INSERT INTO `Transactions`
  (`OrderID`, `CustomerID`, `TransactionDate`, `TransactionType`, `PaymentType`, `Quantity`, `Amount`)
SELECT
  `OrderID`,
  `CustomerID`,
  IFNULL(`PaymentDate`, `OrderDate`),
  'Venta',
  `PaymentType`,
  60,
  600.0000
FROM `Orders`
WHERE `OrderID` IN (10248, 10249, 10250);

CREATE INDEX `IX_Transactions_Quantity` ON `Transactions` (`Quantity`);
CREATE INDEX `IX_Transactions_OrderID` ON `Transactions` (`OrderID`);

/* =========================================================
   5) FACTURAS
      CP10 #4.
   ========================================================= */

DROP VIEW IF EXISTS `Invoices`;

CREATE TABLE `Invoices` (
  `InvoiceID` INTEGER NOT NULL AUTO_INCREMENT,
  `OrderID` INTEGER NOT NULL,
  `InvoiceDate` DATETIME NULL,
  `SubTotal` DECIMAL(12,4) NOT NULL DEFAULT 0,
  `TaxRate` DECIMAL(5,4) NOT NULL DEFAULT 0.1900,
  `TaxAmount` DECIMAL(12,4) NOT NULL DEFAULT 0,
  `TotalAmount` DECIMAL(12,4) NOT NULL DEFAULT 0,
  CONSTRAINT `PK_Invoices` PRIMARY KEY (`InvoiceID`),
  CONSTRAINT `FK_Invoices_Orders` FOREIGN KEY (`OrderID`) REFERENCES `Orders` (`OrderID`)
);

INSERT INTO `Invoices`
  (`OrderID`, `InvoiceDate`, `SubTotal`, `TaxRate`, `TaxAmount`, `TotalAmount`)
SELECT
  o.`OrderID`,
  IFNULL(o.`PaymentDate`, o.`OrderDate`) AS `InvoiceDate`,
  ROUND(SUM(od.`UnitPrice` * od.`Quantity` * (1 - od.`Discount`)), 4) AS `SubTotal`,
  0.1900 AS `TaxRate`,
  ROUND(SUM(od.`UnitPrice` * od.`Quantity` * (1 - od.`Discount`)) * 0.19, 4) AS `TaxAmount`,
  ROUND(SUM(od.`UnitPrice` * od.`Quantity` * (1 - od.`Discount`)) * 1.19, 4) AS `TotalAmount`
FROM `Orders` o
INNER JOIN `OrderDetails` od ON od.`OrderID` = o.`OrderID`
GROUP BY o.`OrderID`, o.`PaymentDate`, o.`OrderDate`;

CREATE INDEX `IX_Invoices_OrderID` ON `Invoices` (`OrderID`);

/* =========================================================
   6) PEDIDOS DE COMPRA A PROVEEDORES
      CP10 #3.
   ========================================================= */

DROP TABLE IF EXISTS `PurchaseOrderDetails`;
DROP TABLE IF EXISTS `PurchaseOrders`;

CREATE TABLE `PurchaseOrders` (
  `PurchaseOrderID` INTEGER NOT NULL AUTO_INCREMENT,
  `SupplierID` INTEGER NOT NULL,
  `EmployeeID` INTEGER NULL,
  `OrderDate` DATETIME NOT NULL,
  `ExpectedDate` DATETIME NULL,
  `Freight` DECIMAL(10,4) DEFAULT 0,
  `Status` VARCHAR(20) NOT NULL DEFAULT 'Emitido',
  CONSTRAINT `PK_PurchaseOrders` PRIMARY KEY (`PurchaseOrderID`),
  CONSTRAINT `FK_PurchaseOrders_Suppliers` FOREIGN KEY (`SupplierID`) REFERENCES `Suppliers` (`SupplierID`),
  CONSTRAINT `FK_PurchaseOrders_Employees` FOREIGN KEY (`EmployeeID`) REFERENCES `Employees` (`EmployeeID`)
);

CREATE TABLE `PurchaseOrderDetails` (
  `PurchaseOrderID` INTEGER NOT NULL,
  `ProductID` INTEGER NOT NULL,
  `UnitCost` DECIMAL(10,4) NOT NULL DEFAULT 0,
  `Quantity` SMALLINT NOT NULL DEFAULT 1,
  CONSTRAINT `PK_PurchaseOrderDetails` PRIMARY KEY (`PurchaseOrderID`, `ProductID`),
  CONSTRAINT `FK_PurchaseOrderDetails_PurchaseOrders` FOREIGN KEY (`PurchaseOrderID`) REFERENCES `PurchaseOrders` (`PurchaseOrderID`),
  CONSTRAINT `FK_PurchaseOrderDetails_Products` FOREIGN KEY (`ProductID`) REFERENCES `Products` (`ProductID`)
);

INSERT INTO `PurchaseOrders`
  (`SupplierID`, `EmployeeID`, `OrderDate`, `ExpectedDate`, `Freight`, `Status`)
SELECT
  s.`SupplierID`,
  1 + MOD(s.`SupplierID`, 9) AS `EmployeeID`,
  DATE_ADD('1998-05-01', INTERVAL s.`SupplierID` DAY) AS `OrderDate`,
  DATE_ADD('1998-05-08', INTERVAL s.`SupplierID` DAY) AS `ExpectedDate`,
  ROUND(5 + (s.`SupplierID` * 1.25), 4) AS `Freight`,
  'Emitido' AS `Status`
FROM `Suppliers` s
WHERE EXISTS (
  SELECT 1
  FROM `Products` p
  WHERE p.`SupplierID` = s.`SupplierID`
);

INSERT INTO `PurchaseOrderDetails`
  (`PurchaseOrderID`, `ProductID`, `UnitCost`, `Quantity`)
SELECT
  po.`PurchaseOrderID`,
  p.`ProductID`,
  IFNULL(p.`StandardCost`, ROUND(IFNULL(p.`UnitPrice`, 0) * 0.65, 4)) AS `UnitCost`,
  CASE
    WHEN p.`UnitsInStock` < p.`ReorderLevel` THEN 50
    ELSE 20 + MOD(p.`ProductID`, 30)
  END AS `Quantity`
FROM `PurchaseOrders` po
INNER JOIN `Products` p ON p.`SupplierID` = po.`SupplierID`;

CREATE INDEX `IX_PurchaseOrders_SupplierID` ON `PurchaseOrders` (`SupplierID`);
CREATE INDEX `IX_PurchaseOrderDetails_ProductID` ON `PurchaseOrderDetails` (`ProductID`);

SET FOREIGN_KEY_CHECKS = 1;

DROP PROCEDURE IF EXISTS AddColumnIfMissing;
DROP PROCEDURE IF EXISTS AddIndexIfMissing;

/* =========================================================
   7) Consultas rápidas de verificación para el docente
   ========================================================= */

SELECT 'CP8/CP10 - corrección aplicada' AS Estado;

SELECT 'Clientes con nombre/apellido' AS Verificacion, COUNT(*) AS Registros
FROM `Customers`
WHERE `FirstName` IS NOT NULL;

SELECT 'Pedidos con tipo y fecha de pago' AS Verificacion, COUNT(*) AS Registros
FROM `Orders`
WHERE `PaymentType` IS NOT NULL AND `PaymentDate` IS NOT NULL;

SELECT 'Transacciones 51-69' AS Verificacion, COUNT(*) AS Registros
FROM `Transactions`
WHERE `Quantity` > 50 AND `Quantity` < 70;

SELECT 'Facturas creadas' AS Verificacion, COUNT(*) AS Registros
FROM `Invoices`;

SELECT 'Pedidos de compra creados' AS Verificacion, COUNT(*) AS Registros
FROM `PurchaseOrders`;
