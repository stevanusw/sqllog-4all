# sqllog-4all
SQL Server audit infrastructure for INSERT, UPDATE and DELETE.

## Features
1. A centralised audit table,
2. Supports up to three columns for composite primary key,
3. No need to modify triggers if new columns are added or existing ones are deleted,
4. Work against >= SQL 2008 and SQL Azure.

## Limitations
1. Only support column types that are compatible with sql_variant (https://docs.microsoft.com/en-us/sql/t-sql/data-types/sql-variant-transact-sql),
2. May not be suitable for high traffic CUD database.

## Installations
1. Tables: 
   * dbo.Logs,
2. Stored procedures: 
   * dbo.CreateLog
   * dbo.CreateLogTriggerForInsert
   * dbo.CreateLogTriggerForUpdate 
   * dbo.CreateLogTriggerForDelete
   
## Notes
1. Audit table name is dbo.Logs,
2. Trigger name starts with TRI_Logs__TableName for INSERT, TRU_Logs__TableName for UPDATE and TRD_Logs__TableName for DELETE,
3. All the triggers are set to run as first trigger (https://docs.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-settriggerorder-transact-sql),
4. As with other DML triggers, it is wise to disable them when performing import such as BULK INSERT for example.

## Examples
```
EXECUTE dbo.CreateLogTriggerForInsert @SchemaName = N'dbo', @TableName = N'Birds';
EXECUTE dbo.CreateLogTriggerForUpdate @SchemaName = N'dbo', @TableName = N'Birds';
EXECUTE dbo.CreateLogTriggerForDelete @SchemaName = N'dbo', @TableName = N'Birds';
```
![dbo.Logs](https://github.com/stevanuz/sqllog-4all/blob/master/090418.png)

## Resources
1. https://sqlblogcasts.com/blogs/piotr_rodak/archive/2010/04/28/columns-updated.aspx
2. https://docs.microsoft.com/en-us/sql/t-sql/functions/columns-updated-transact-sql
