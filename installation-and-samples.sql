IF OBJECT_ID(N'dbo.Logs', N'U') IS NULL
BEGIN
	CREATE TABLE dbo.Logs
	(LogId UNIQUEIDENTIFIER NOT NULL,
	 SchemaName SYSNAME NOT NULL,
	 TableName SYSNAME NOT NULL,
	 ChangeDate DATETIME2 NOT NULL,
	 ChangeStatus CHAR(1) NOT NULL CONSTRAINT CK_Logs__ChangeStatus CHECK(ChangeStatus IN('I', 'D', 'U')),
	 PKColumnName1 SYSNAME NULL,
	 PKColumnValue1 SQL_VARIANT NULL,
	 PKColumnName2 SYSNAME NULL,
	 PKColumnValue2 SQL_VARIANT NULL,
	 PKColumnName3 SYSNAME NULL,
	 PKColumnValue3 SQL_VARIANT NULL,
	 ColumnName SYSNAME NOT NULL,
	 OldValue SQL_VARIANT NULL,
	 NewValue SQL_VARIANT NULL)
	ON [PRIMARY];
END
GO

IF OBJECT_ID(N'dbo.CreateLog', N'P') IS NOT NULL
BEGIN
	DROP PROCEDURE dbo.CreateLog;
END
GO

CREATE PROCEDURE dbo.CreateLog
(@SchemaName AS SYSNAME,
 @TableName AS SYSNAME,
 @ChangeStatus AS CHAR(1),
 @ColumnsUpdated AS VARBINARY(8))
AS
BEGIN
	SET NOCOUNT ON;
    SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

	BEGIN TRY
		DECLARE @NewLine AS NCHAR(2) = NCHAR(13) + NCHAR(10);
		
		-- Can only handle up to 3 columns for composite primary key.
		DECLARE @PKColumnName1 AS SYSNAME = NULL;
		DECLARE @PKColumnName2 AS SYSNAME = NULL;
		DECLARE @PKColumnName3 AS SYSNAME = NULL;
		DECLARE @PKCount AS INT = 0;
		
		SELECT @PKColumnName1 = CASE [index_columns].index_column_id
									WHEN 1 THEN [columns].name
									ELSE @PKColumnName1
	                            END,
	                            
	           @PKColumnName2 = CASE [index_columns].index_column_id
									WHEN 2 THEN [columns].name
									ELSE @PKColumnName2
	                            END,
	                            
	           @PKColumnName3 = CASE [index_columns].index_column_id
									WHEN 3 THEN [columns].name
									ELSE @PKColumnName3
	                            END,
			   
			   @PKCount += 1
		
		FROM sys.schemas AS [schemas] 
		INNER JOIN sys.tables AS [tables]
		ON [schemas].schema_id = [tables].schema_id AND
		   [schemas].name = @SchemaName AND
		   [tables].name = @TableName
		   
		INNER JOIN sys.indexes AS [indexes]
		ON [tables].object_id = [indexes].object_id AND
		   [indexes].is_primary_key = 1
		   
		INNER JOIN sys.index_columns AS [index_columns]
		ON [indexes].object_id = [index_columns].object_id AND
		   [indexes].index_id = [index_columns].index_id
		   
		INNER JOIN sys.columns AS [columns]
		ON [tables].object_id = [columns].object_id
		
		WHERE [index_columns].column_id = [columns].column_id; 
		
		IF (@PKCount > 3)
		BEGIN
			THROW 51000, N'Only max of 3 PKs are supported.', 1;
		END

		CREATE TABLE #LogParams
		(LogParamId INT NOT NULL,
		 PKColumnValue1 SQL_VARIANT NULL,
		 PKColumnValue2 SQL_VARIANT NULL,
		 PKColumnValue3 SQL_VARIANT NULL,
		 ColumnName SYSNAME NOT NULL,
		 OldValue SQL_VARIANT NULL,
		 NewValue SQL_VARIANT NULL);

		CREATE UNIQUE CLUSTERED INDEX UCI_LogParams__LogParamId_ColumnName
		ON #LogParams(LogParamId ASC, ColumnName ASC);
		
		DECLARE @Query AS NVARCHAR(4000) = N'';
		
		SET @Query = N'INSERT INTO #LogParams(LogParamId,' + @NewLine +
		             N'                       PKColumnValue1,' + @NewLine +
		             N'                       PKColumnValue2,' + @NewLine +
		             N'                       PKColumnValue3,' + @NewLine +
					 N'                       ColumnName)' + @NewLine +
	                 
					 N'SELECT CASE @ColumnsUpdated' + @NewLine +
					 N'          WHEN 0x THEN #deleted.LogParamId' + @NewLine +
					 N'          ELSE #inserted.LogParamId' + @NewLine +
					 N'       END,' + @NewLine +
					 N'       ' + CASE
					                 WHEN @PKColumnName1 IS NULL THEN N'NULL,'
									 ELSE N'CASE @ColumnsUpdated' + @NewLine +
					                      N'   WHEN 0x THEN #deleted.[' + @PKColumnName1 + N']' + @NewLine +
					                      N'   ELSE #inserted.[' + @PKColumnName1 + N']' + @NewLine +
					                      N'END,' 
								  END + @NewLine +
					 N'       ' + CASE 
								      WHEN @PKColumnName2 IS NULL THEN N'NULL,'
								      ELSE N'CASE @ColumnsUpdated' + @NewLine + 
					 N'       ' +          N'   WHEN 0x THEN #deleted.[' + @PKColumnName2 + N']' + @NewLine +
					 N'       ' +          N'   ELSE #inserted.[' + @PKColumnName2 + N']' + @NewLine +
					 N'       ' +          N'END,'
					              END + @NewLine +
					 N'       ' + CASE 
								      WHEN @PKColumnName3 IS NULL THEN N'NULL,'
								      ELSE N'CASE @ColumnsUpdated' + @NewLine + 
					 N'       ' +          N'   WHEN 0x THEN #deleted.[' + @PKColumnName3 + N']' + @NewLine +
					 N'       ' +          N'   ELSE #inserted.[' + @PKColumnName3 + N']' + @NewLine +
					 N'       ' +          N'END,'
					              END + @NewLine +
					 N'       [columns].name' + @NewLine +

					 N'FROM #inserted' + @NewLine +
					 N'FULL OUTER JOIN #deleted' + @NewLine +
					 N'ON #inserted.LogParamId = #deleted.LogParamId' + @NewLine +
		             
					 N'CROSS JOIN sys.schemas AS [schemas]' + @NewLine +
		             
					 N'INNER JOIN sys.tables AS [tables]' + @NewLine +
					 N'ON [schemas].schema_id = [tables].schema_id AND' + @NewLine +
					 N'   [schemas].name = N''' + @SchemaName + ''' AND' + @NewLine +
					 N'   [tables].name = N''' + @TableName + N'''' + @NewLine +
		             
					 N'INNER JOIN sys.columns AS [columns]' + @NewLine +
					 N'ON [tables].object_id = [columns].object_id' + @NewLine +
		             
		             -- http://msdn.microsoft.com/en-us/library/ms173829.aspx
					 N'INNER JOIN sys.types AS [types]' + @NewLine +
					 N'ON [columns].user_type_id = [types].user_type_id AND' + @NewLine +        
					 N'   [types].name IN(N''SQL_VARIANT'',' + @NewLine +
					 N'                   N''DATETIME2'',' + @NewLine +
					 N'                   N''DATETIMEOFFSET'',' + @NewLine +
					 N'                   N''DATETIME'',' + @NewLine +
					 N'                   N''SMALLDATETIME'',' + @NewLine +
					 N'                   N''DATE'',' + @NewLine +
					 N'                   N''TIME'',' + @NewLine +
					 N'                   N''FLOAT'',' + @NewLine +
					 N'                   N''REAL'',' + @NewLine +
					 N'                   N''DECIMAL'',' + @NewLine +
					 N'                   N''MONEY'',' + @NewLine +
					 N'                   N''SMALLMONEY'',' + @NewLine +
					 N'                   N''BIGINT'',' + @NewLine +
					 N'                   N''INT'',' + @NewLine +
					 N'                   N''SMALLINT'',' + @NewLine +
					 N'                   N''TINYINT'',' + @NewLine +
					 N'                   N''BIT'',' + @NewLine +
					 N'                   N''SYSNAME'',' + @NewLine +
					 N'                   N''NVARCHAR'',' + @NewLine +
					 N'                   N''NCHAR'',' + @NewLine +
					 N'                   N''VARCHAR'',' + @NewLine +
					 N'                   N''CHAR'',' + @NewLine +
					 N'                   N''VARBINARY'',' + @NewLine +
					 N'                   N''BINARY'',' + @NewLine +
					 N'                   N''UNIQUEIDENTIFIER'') AND' + @NewLine +
					 N'   [columns].max_length <> -1' + @NewLine +
		                          
					 -- Get the target byte from left to right.
					 -- From the target byte, check the if the bit is turned on/off -> the column is updated/not.
					 -- https://sqlblogcasts.com/blogs/piotr_rodak/archive/2010/04/28/columns-updated.aspx   
					 N'WHERE (SUBSTRING(@ColumnsUpdated,' + @NewLine +
					 N'                 ([columns].column_id - 1) / 8 + 1,' + @NewLine +
					 N'                 1) & POWER(2,' + @NewLine +
					 N'                            ([columns].column_id - 1) % 8) > 0) OR' + @NewLine +
					 N'      @ColumnsUpdated = 0x;';
		
		--PRINT @Query;

		EXECUTE sp_executesql @Query,
							  N'@ColumnsUpdated AS VARBINARY(8)',
							  @ColumnsUpdated = @ColumnsUpdated;

		--PRINT @Query;
		
		-- Insert old and new column value.
		DECLARE @LogParamId AS INT;
		DECLARE @ColumnName AS SYSNAME;

		DECLARE C Cursor FAST_FORWARD
		FOR SELECT LogParamId, ColumnName
		FROM #LogParams
		WITH(INDEX(UCI_LogParams__LogParamId_ColumnName));

		OPEN C;
		FETCH NEXT FROM C INTO @LogParamId, @ColumnName;

		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @Query = N'UPDATE #LogParams' + @NewLine +
						 N'SET #LogParams.OldValue = #deleted.[' + @ColumnName + N'],' + @NewLine +
						 N'    #LogParams.NewValue = #inserted.[' + @ColumnName + N']' + @NewLine +
						 N'FROM #inserted' + @NewLine +
						 N'FULL OUTER JOIN #deleted' + @NewLine +
						 N'ON #inserted.LogParamId = #deleted.LogParamId' + @NewLine +
						 N'INNER JOIN #LogParams' + @NewLine +
						 N'ON #LogParams.LogParamId = #inserted.LogParamId OR' + @NewLine +
						 N'   #LogParams.LogParamId = #deleted.LogParamId' + @NewLine +			 
						 N'WHERE #LogParams.LogParamId = ' + CAST(@LogParamId AS NVARCHAR(10)) + N' AND' + @NewLine +
						 N'      #LogParams.ColumnName = N''' + @ColumnName + N''';';
			
			-- PRINT @Query;

			EXECUTE sp_executesql @Query;
			
			-- PRINT @Query;          
			             
			FETCH NEXT FROM C INTO @LogParamId, @ColumnName;          
		END

		CLOSE C;
		DEALLOCATE C;
		
		DECLARE @NewId AS TABLE
		(Id UNIQUEIDENTIFIER DEFAULT NEWSEQUENTIALID());

		INSERT INTO @NewId(Id)
		VALUES(DEFAULT);

		DECLARE @Now AS DATETIME2 = SYSUTCDATETIME();

		INSERT INTO dbo.[Logs](LogId,
		                       SchemaName,
							   TableName,
							   ChangeDate,
							   ChangeStatus,
							   PKColumnName1,
							   PKColumnValue1,
							   PKColumnName2,
							   PKColumnValue2,
							   PKColumnName3,
							   PKColumnValue3,
							   ColumnName,
							   OldValue,
							   NewValue)
		SELECT (SELECT Id FROM @NewId),
		        @SchemaName,
		        @TableName,
			    @Now,
			    @ChangeStatus,
		        @PKColumnName1,
		        PKColumnValue1,
		        @PKColumnName2,
		        PKColumnValue2,
		        @PKColumnName3,
		        PKColumnValue3,
		        ColumnName,
		        OldValue,
		        NewValue
		FROM #LogParams;
	END TRY
	BEGIN CATCH
		THROW;
	END CATCH
END
GO

IF OBJECT_ID(N'dbo.CreateLogTriggerForInsert', N'P') IS NOT NULL
BEGIN
	DROP PROCEDURE dbo.CreateLogTriggerForInsert;
END
GO

CREATE PROCEDURE dbo.CreateLogTriggerForInsert
(@SchemaName AS SYSNAME,
 @TableName AS SYSNAME)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @NewLine AS NCHAR(2) = NCHAR(13) + NCHAR(10);
	DECLARE @TriggerName AS SYSNAME = QUOTENAME(@SchemaName) + N'.TRI_Logs__' + @TableName;
	
	DECLARE @Query AS NVARCHAR(4000) = 
		N'IF (OBJECT_ID(N''' + @TriggerName + N''', N''TR'')) IS NOT NULL' + @NewLine +
		N'   DROP TRIGGER ' + @TriggerName + N';';
    
	EXECUTE sp_executesql @Query;

	SET @Query = 
		N'CREATE TRIGGER ' + @TriggerName + @NewLine +
		N'ON ' + @SchemaName + N'.' + @TableName + N' FOR INSERT' + @NewLine +
		N'AS' + @NewLine +
		N'BEGIN' + @NewLine +
		N'   IF (@@ROWCOUNT = 0)' + @NewLine +
		N'      RETURN;' + @NewLine + @NewLine +
		N'   SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS LogParamId, * INTO #inserted FROM inserted;' + @NewLine +
		N'   CREATE UNIQUE CLUSTERED INDEX UCI_inserted__LogParamId ON #inserted(LogParamId ASC);' + @NewLine + @NewLine +
		N'   SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS LogParamId, * INTO #deleted FROM deleted;' + @NewLine +
		N'   CREATE UNIQUE CLUSTERED INDEX UCI_deleted__LogParamId ON #deleted(LogParamId ASC);' + @NewLine + @NewLine + 
		N'   DECLARE @ColumnsUpdated AS VARBINARY(8) = COLUMNS_UPDATED();' + @NewLine +
		N'   EXECUTE dbo.CreateLog @SchemaName = N''' + @SchemaName + N''',' + @NewLine +
		N'                         @TableName =  N''' + @TableName + N''',' + @NewLine +
		N'                         @ChangeStatus = N''I'',' + @NewLine +
		N'                         @ColumnsUpdated = @ColumnsUpdated;' + @NewLine +
		N'END' + @NewLine +
		N'EXECUTE sp_settriggerorder @triggername = ''' + @TriggerName + ''', @order = ''FIRST'', @stmttype = ''INSERT'';';

	EXECUTE sp_executesql @Query;
END
GO

IF OBJECT_ID(N'dbo.CreateLogTriggerForUpdate', N'P') IS NOT NULL
BEGIN
	DROP PROCEDURE dbo.CreateLogTriggerForUpdate;
END
GO

CREATE PROCEDURE dbo.CreateLogTriggerForUpdate
(@SchemaName AS SYSNAME,
 @TableName AS SYSNAME)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @NewLine AS NCHAR(2) = NCHAR(13) + NCHAR(10);
	DECLARE @TriggerName AS SYSNAME = QUOTENAME(@SchemaName) + N'.TRU_Logs__' + @TableName;
	
	DECLARE @Query AS NVARCHAR(4000) = 
		N'IF (OBJECT_ID(N''' + @TriggerName + N''', N''TR'')) IS NOT NULL' + @NewLine +
		N'   DROP TRIGGER ' + @TriggerName + N';';
    
	EXECUTE sp_executesql @Query;

	SET @Query = 
		N'CREATE TRIGGER ' + @TriggerName + @NewLine +
		N'ON ' + @SchemaName + N'.' + @TableName + N' FOR UPDATE' + @NewLine +
		N'AS' + @NewLine +
		N'BEGIN' + @NewLine +
		N'   IF (@@ROWCOUNT = 0)' + @NewLine +
		N'      RETURN;' + @NewLine + @NewLine +
		N'   SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS LogParamId, * INTO #inserted FROM inserted;' + @NewLine +
		N'   CREATE UNIQUE CLUSTERED INDEX UCI_inserted__LogParamId ON #inserted(LogParamId ASC);' + @NewLine + @NewLine +
		N'   SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS LogParamId, * INTO #deleted FROM deleted;' + @NewLine +
		N'   CREATE UNIQUE CLUSTERED INDEX UCI_deleted__LogParamId ON #deleted(LogParamId ASC);' + @NewLine + @NewLine + 
		N'   DECLARE @ColumnsUpdated AS VARBINARY(8) = COLUMNS_UPDATED();' + @NewLine +
		N'   EXECUTE dbo.CreateLog @SchemaName = N'''+ @SchemaName + N''',' + @NewLine +
		N'                         @TableName =  N'''+ @TableName + N''',' + @NewLine +
		N'                         @ChangeStatus = N''U'',' + @NewLine +
		N'                         @ColumnsUpdated = @ColumnsUpdated;' + @NewLine +
		N'END' + @NewLine +
		N'EXECUTE sp_settriggerorder @triggername = ''' + @TriggerName + ''', @order = ''FIRST'', @stmttype = ''UPDATE'';';

	EXECUTE sp_executesql @Query;
END
GO

IF OBJECT_ID(N'dbo.CreateLogTriggerForDelete', N'P') IS NOT NULL
BEGIN
	DROP PROCEDURE dbo.CreateLogTriggerForDelete;
END
GO

CREATE PROCEDURE dbo.CreateLogTriggerForDelete
(@SchemaName AS SYSNAME,
 @TableName AS SYSNAME)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @NewLine AS NCHAR(2) = NCHAR(13) + NCHAR(10);
	DECLARE @TriggerName AS SYSNAME = QUOTENAME(@SchemaName) + N'.TRD_Logs__' + @TableName;
	
	DECLARE @Query AS NVARCHAR(4000) = 
		N'IF (OBJECT_ID(N''' + @TriggerName + N''', N''TR'')) IS NOT NULL' + @NewLine +
		N'   DROP TRIGGER ' + @TriggerName + N';';
    
	EXECUTE sp_executesql @Query;

	SET @Query = 
		N'CREATE TRIGGER ' + @TriggerName + @NewLine +
		N'ON ' + @SchemaName + N'.' + @TableName + N' FOR DELETE' + @NewLine +
		N'AS' + @NewLine +
		N'BEGIN' + @NewLine +
		N'   IF (@@ROWCOUNT = 0)' + @NewLine +
		N'      RETURN;' + @NewLine + @NewLine +
		N'   SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS LogParamId, * INTO #inserted FROM inserted;' + @NewLine +
		N'   CREATE UNIQUE CLUSTERED INDEX UCI_inserted__LogParamId ON #inserted(LogParamId ASC);' + @NewLine + @NewLine +
		N'   SELECT ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) AS LogParamId, * INTO #deleted FROM deleted;' + @NewLine +
		N'   CREATE UNIQUE CLUSTERED INDEX UCI_deleted__LogParamId ON #deleted(LogParamId ASC);' + @NewLine + @NewLine + 
		N'   DECLARE @ColumnsUpdated AS VARBINARY(8) = COLUMNS_UPDATED();' + @NewLine +
		N'   EXECUTE dbo.CreateLog @SchemaName = N'''+ @SchemaName + N''',' + @NewLine +
		N'                         @TableName =  N'''+ @TableName + N''',' + @NewLine +
		N'                         @ChangeStatus = N''D'',' + @NewLine +
		N'                         @ColumnsUpdated = @ColumnsUpdated;' + @NewLine +
		N'END' + @NewLine +
		N'EXECUTE sp_settriggerorder @triggername = ''' + @TriggerName + ''', @order = ''FIRST'', @stmttype = ''DELETE'';';

	EXECUTE sp_executesql @Query;
END
GO

-- Example #1:
-- http://www.encodedna.com/2012/12/create-dummy-database-tables.htm
CREATE TABLE [dbo].[Birds](
[ID] [int] NOT NULL,
[BirdName] [varchar](50) NULL,
[TypeOfBird] [varchar](50) NULL,
[ScientificName] [varchar](50) NULL,
 CONSTRAINT [PK_Birds] PRIMARY KEY CLUSTERED ([ID] ASC)
) ON [PRIMARY]; 

EXECUTE dbo.CreateLogTriggerForInsert @SchemaName = N'dbo', @TableName = N'Birds';
EXECUTE dbo.CreateLogTriggerForUpdate @SchemaName = N'dbo', @TableName = N'Birds';
EXECUTE dbo.CreateLogTriggerForDelete @SchemaName = N'dbo', @TableName = N'Birds';
GO

INSERT INTO dbo.Birds (ID, BirdName, TypeOfBird, ScientificName)
VALUES (1, 'Eurasian Collared-Dove', 'Dove', 'Streptopelia'),
       (2, 'Bald Eagle	Hawk', 'Haliaeetus', 'Leucocephalus'),
       (3, 'Coopers Hawk',	'Hawk',	'Accipiter Cooperii'),
       (4, 'Bells Sparrow', 'Sparrow', 'Artemisiospiza Belli'),
       (5, 'Mourning Dove', 'Dove', 'Zenaida Macroura'),
       (6, 'Rock Pigeon', 'Dove', 'Columba Livia'),
       (7, 'Aberts Towhee', 'Sparrow', 'Melozone Aberti'),
       (8, 'Brewers Sparrow', 'Sparrow', 'Spizella Breweri'),
       (9, 'Canyon Towhee', 'Sparrow', 'Melozone Fusca'),
       (10, 'Black Vulture', 'Hawk', 'Coragyps Atratus'),
       (11, 'Gila Woodpecker', 'Woodpecker', 'Melanerpes Uropygialis'),
       (12, 'Gilded Flicker', 'Woodpecker', 'Colaptes Chrysoides'),
       (13, 'Cassins Sparrow', 'Sparrow', 'Peucaea Cassinii'),
       (14, 'American Kestrel', 'Hawk', 'Falco Sparverius'),
       (15, 'Hairy Woodpecker', 'Woodpecker', 'Picoides villosus'),
       (16, 'Lewis Woodpecker', 'Woodpecker', 'Melanerpes Lewis'),
       (17, 'Snail Kite', 'Rostrhamus', 'Sociabilis'),
       (18, 'White-tailed Hawk', 'Hawk', 'Geranoaetus Albicaudatus');

UPDATE dbo.Birds
SET TypeOfBird = 'Hawk'
WHERE ID = 17;

DELETE dbo.Birds
WHERE TypeOfBird = 'Sparrow';

UPDATE dbo.Birds
SET TypeOfBird = NULL
WHERE TypeOfBird = 'Dove';

--DROP TABLE dbo.Birds;
GO

-- Example #2:
-- https://dzone.com/articles/sql-server-how-insert-million
CREATE TABLE Numbers
(Id INT PRIMARY KEY IDENTITY(1, 1),
 Value INT)
ON [PRIMARY];

EXECUTE dbo.CreateLogTriggerForInsert @SchemaName = N'dbo', @TableName = N'Numbers';
GO

declare @t table (number int)
insert into @t 
select 0
union all
select 1
union all
select 2
union all
select 3
union all
select 4
union all
select 5
union all
select 6
union all
select 7
union all
select 8
union all
select 9;

insert into numbers(Value)
select t1.number + t2.number*10 + t3.number*100-- + t4.number*1000 + t5.number*10000 + t6.number*100000
from @t as t1, 
     @t as t2,
     @t as t3;/*,
     @t as t4,
     @t as t5,
     @t as t6;*/

--DROP TABLE dbo.Numbers;
GO
