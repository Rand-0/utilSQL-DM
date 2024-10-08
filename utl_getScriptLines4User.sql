-- Procedura służy do przygotowania skryptu do ramkowania, uwzględniając obiekty, wpisy z logu zmian rozwojowych, a także ustawia odpowiednią kolejność
--
-- Działa domyślnie dla użytkownika który wykonuje skrypt, parametr @DateFrom określa od którego dnia ma uwzględniać zmiany, domyślnie bierze datę najstarszego obiektu (lub jeżeli nie ma - to datę dzisiejszą)
-- Parametr @IgnoreDollars - czy brać pod uwagę obiekty które opis mają $$$ - domyślnie 1, czyli nie bierzemy
-- Parametr @RollbackOld - rollbackuje zmiany z dnia niedzisiejszego, można wtedy bez problemu dodać do konwetera - domyślnie 1, czyli rollbackuje
-- Flaga -- AUTO_SCR_IGNORE -  dodanie jej w treści obiektu (jako komentarz) powoduje zignorowanie przy skryptowaniu
-- Flaga -- AUTO_SCR_WARN - dodanie jej w treści obiektu (jako komentarz) powoduje wyświetlenie ostrzeżenia przy użyciu utilsa (dzięki temu możemy zostawić przypomnienie żeby nie zapomnieć)

CREATE PROCEDURE dbo.[utl_getScriptLines4User] @DateFrom date = NULL, @IgnoreDollars TSLBoolean = 1, @RollbackOld TSLBoolean = 1
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @Res int, @__ProcName sysname, @__TranName varchar(40), @__TranId bigint, @TranCnt int;
  SELECT  @Res = 0, @__ProcName = OBJECT_NAME(@@PROCID), @__TranName = CONVERT(varchar(40),REPLACE(NEWID(),'-','')), @TranCnt  = @@TRANCOUNT;
  IF @TranCnt  = 0 BEGIN TRAN;
  IF @@TRANCOUNT > 0 AND XACT_STATE() != -1 SAVE TRAN @__TranName;
  IF @@TRANCOUNT > 0 SELECT TOP 1 @__TranId = t.ID FROM dbo.sl_vv_curtran t;

  -- AUTO_SCR_IGNORE

  DECLARE @CurUser sysname = SUSER_NAME();
  DECLARE @Objects TABLE (ObjName varchar(255) NULL , VersionId int NULL , IsNew TSLBoolean NULL , VersionDate datetime NULL , ObjNameForLike varchar(257) NULL );
  DECLARE @ChangeLogs TABLE (LogId int NULL , LogDate datetime NULL );

  INSERT INTO @Objects (ObjName, VersionId, IsNew, VersionDate, ObjNameForLike)
  SELECT o.ObjectName, o.VersionId, CASE WHEN o.Ver_S IS NULL THEN 1 ELSE 0 END, o.VersionDate, ('%' + o.ObjectName + '%')
  FROM dbo.sl_ObjectVersions o WITH(NOLOCK)
  WHERE o.Author = @CurUser AND o.VersionStatus = 'adhoc' AND CASE WHEN @IgnoreDollars = 1 THEN '$$$' ELSE '' END <> o.Description;
  EXEC @Res = dbo.CheckError #0020AE3F60E3A6, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/

  SELECT @DateFrom = COALESCE(@DateFrom, (SELECT MIN(o.VersionDate) FROM @Objects o), GETDATE());

  INSERT INTO @ChangeLogs (LogId, LogDate)
  SELECT c.LogId, c.Date
  FROM dbo.sl_vv_ChangesLogViewAll c
  WHERE c.Login = @CurUser AND c.Date >= @DateFrom AND c.IsApplied = 0 AND c.Active = 1;
  EXEC @Res = dbo.CheckError #002535029E6390, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/

  DECLARE @ObjectsLines TABLE (VersionId int NULL , LineNumber int NULL , Line varchar(max) NULL );
  DECLARE @ChangeLogsLines TABLE (LogId int NULL , LineNumber int NULL , Line varchar(max) NULL );
  DECLARE @CurObjName varchar(255), @CurId int, @MaxLineNumber int;
  DECLARE @CurLines TABLE (LineNumber int NULL , Line varchar(max) NULL );
  DECLARE @Dependencies TABLE (SrcObjId int NULL , DepObjId int NULL );
  DECLARE @Warnings TABLE (ObjName varchar(255) NULL, Line varchar(max) NULL, Warning varchar(1000) NULL);
  DECLARE @LineChecks TABLE (Line varchar(1000) NULL, Warning varchar(100) NULL);

  INSERT INTO @LineChecks(Line, Warning)
  SELECT '%/*RESULTSET-ALLOWED*/%', 'SELECT w powietrze - upewnij się, że jest on celowy!';
  EXEC @Res = dbo.CheckError #0040772F9282CA, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;

  INSERT INTO @LineChecks(Line, Warning)
  SELECT '%AUTO_SCR_WARN', 'Ostrzeżenie użytkownika - zweryfikuj jego zasadność!';
  EXEC @Res = dbo.CheckError #00436556ADAC8B, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;

  -- Objects
  DECLARE @cur CURSOR; SET @cur = CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
  SELECT o.VersionId
  FROM @Objects o;

  OPEN @cur;
  FETCH @cur INTO @CurId;
  WHILE @@FETCH_STATUS=0
  BEGIN;

    DELETE FROM @CurLines;
    EXEC @Res = dbo.CheckError #00463553957937, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

    SELECT TOP 1 @CurObjName = o.ObjName
    FROM @Objects o
    WHERE @CurId = o.VersionId;

    INSERT INTO @CurLines(LineNumber, Line)
    SELECT o.id, o.line
    FROM dbo.utl_fn_scrobject(@CurObjName, 0, 'tmp', 0, 1, 1, 0, 3) o;
    EXEC @Res = dbo.CheckError #0052A2C936D321, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

    SELECT TOP 1 @MaxLineNumber = MAX(c.LineNumber)
    FROM @CurLines c;

    INSERT INTO @CurLines(LineNumber, Line)
    SELECT (@MaxLineNumber + 1), '';
    EXEC @Res = dbo.CheckError #00634FE4F0DA84, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

    INSERT INTO @CurLines(LineNumber, Line)
    SELECT (@MaxLineNumber + 2), '-- New object';
    EXEC @Res = dbo.CheckError #0066B4DB112F9A, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

    INSERT INTO @CurLines(LineNumber, Line)
    SELECT (@MaxLineNumber + 3), '';
    EXEC @Res = dbo.CheckError #00697816CB157C, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

    IF NOT EXISTS (SELECT 1 FROM @CurLines cl WHERE cl.Line LIKE '%AUTO_SCR_IGNORE')
    BEGIN;

        INSERT INTO @Warnings(ObjName, Line, Warning)
        SELECT @CurObjName, cl.Line, lch.Warning
        FROM @CurLines cl 
         INNER JOIN @LineChecks lch ON cl.Line LIKE lch.Line;
        EXEC @Res = dbo.CheckError #00862EE7CE954A, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

        IF @RollbackOld = 1 AND (SELECT TOP 1 CAST(ISNULL(o.VersionDate, GETDATE()) AS date)
                                 FROM @Objects o
                                 WHERE @CurId = o.VersionId AND o.IsNew = 0) <> CAST(GETDATE() AS date)
        BEGIN;

            INSERT INTO @Warnings(ObjName, Line, Warning)
            SELECT @CurObjName, -1, 'Najnowsza wersja obiektu została wycofana żeby można było dodać go do ramki!';
            EXEC @Res = dbo.CheckError #0096A71F290423, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;
        
            EXEC @Res = dbo.utl_RollbackObjVersion @ObjectName = @CurObjName, @MyChangeOnly = 0, @WithCheck = 0, @TodayOnly = 0;
            EXEC @Res = dbo.CheckError #008363C1A266D6, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/
        
        END;

        INSERT INTO @ObjectsLines(VersionId, LineNumber, Line)
        SELECT @CurId, o.LineNumber, o.Line
        FROM @CurLines o
        ORDER BY o.LineNumber;
        EXEC @Res = dbo.CheckError #0059EA9710F35F, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

        INSERT INTO @Dependencies(SrcObjId, DepObjId)
        SELECT DISTINCT @CurId, o.VersionId
        FROM @CurLines cl
         INNER JOIN @Objects o ON cl.Line LIKE o.ObjNameForLike
        WHERE o.VersionId <> @CurId;
        EXEC @Res = dbo.CheckError #0064A5DD73802F, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;
                  
    END;
    ELSE
    BEGIN;

        INSERT INTO @Warnings(ObjName, Line, Warning)
        SELECT TOP 1 @CurObjName, cl.Line, 'Obiekt pominięty - AUTO_SCR_IGNORE'
        FROM @CurLines cl 
        WHERE cl.Line LIKE '%AUTO_SCR_IGNORE';
        EXEC @Res = dbo.CheckError #0121BB4B346FBD, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

        DELETE FROM @Objects
        WHERE VersionId = @CurId;
        EXEC @Res = dbo.CheckError #00800F6DF543EE, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur; GOTO END_ERROR; END;

    END;

    FETCH @cur INTO @CurId;

  END;

  CLOSE @cur;
  DEALLOCATE @cur;

  -- Changes from log
  INSERT INTO @ChangeLogsLines(LogId, LineNumber, Line)
  SELECT cl.LogId, t.id, t.line
  FROM @ChangeLogs cl
   OUTER APPLY (SELECT s.id, s.line
                FROM dbo.sl_fn_ScriptChange(cl.LogId) s
                UNION 
                SELECT 99999, '') t;
  EXEC @Res = dbo.CheckError #0080011947D5FB, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/

  DECLARE @Order TABLE(OrderVal int NULL , Id int NULL , IsObject TSLBoolean NULL );

  IF NOT EXISTS (SELECT 1 FROM @Dependencies d)
  BEGIN;

    INSERT INTO @Order(OrderVal, Id, IsObject)
    SELECT ROW_NUMBER() OVER (ORDER BY t.OrderDate ASC), t.Id, t.IsObject
    FROM (SELECT o.VersionId AS Id, 1 AS IsObject, o.VersionDate AS OrderDate
          FROM @Objects o
          UNION ALL
          SELECT cl.LogId AS Id, 0 AS IsObject, cl.LogDate AS OrderDate
          FROM @ChangeLogs cl) t
    ORDER BY t.OrderDate ASC;
    EXEC @Res = dbo.CheckError #00902AD14E0C4B, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/ 

  END;
  ELSE
  BEGIN;

    DECLARE @cur2 CURSOR; SET @cur2 = CURSOR LOCAL STATIC READ_ONLY FORWARD_ONLY FOR
    SELECT d.SrcObjId
    FROM @Dependencies d;
    
    OPEN @cur2;
    FETCH @cur2 INTO @CurId;
    WHILE @@FETCH_STATUS=0
    BEGIN; 

       SELECT TOP 1 @MaxLineNumber = ISNULL(MAX(o.OrderVal), 0)
       FROM @Order o; 

       INSERT INTO @Order(OrderVal, Id, IsObject)
       SELECT ROW_NUMBER() OVER (ORDER BY o.VersionDate ASC) + @MaxLineNumber, o.VersionId, 1
       FROM @Dependencies d
        INNER JOIN @Objects o ON o.VersionId = d.DepObjId
       WHERE d.DepObjId NOT IN (SELECT d2.SrcObjId FROM @Dependencies d2)
       GROUP BY o.VersionId, o.VersionDate
       ORDER BY o.VersionDate ASC;
       EXEC @Res = dbo.CheckError #015733C524B204, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur2; GOTO END_ERROR; END;
       
       DELETE d
       FROM @Dependencies d
       WHERE d.DepObjId IN (SELECT o.Id FROM @Order o);
       EXEC @Res = dbo.CheckError #016469FF011E4C, @Res, @__ProcName; IF @Res < 0 BEGIN; CLOSE @cur; DEALLOCATE @cur2; GOTO END_ERROR; END;

       FETCH @cur2 INTO @CurId;
    
    END;
    
    CLOSE @cur2;
    DEALLOCATE @cur2;

    SELECT TOP 1 @MaxLineNumber = ISNULL(MAX(o.OrderVal), 0)
    FROM @Order o; 

    INSERT INTO @Order(OrderVal, Id, IsObject)
    SELECT ROW_NUMBER() OVER (ORDER BY t.OrderDate ASC) + @MaxLineNumber, t.Id, t.IsObject
    FROM (SELECT o.VersionId AS Id, 1 AS IsObject, o.VersionDate AS OrderDate
          FROM @Objects o
          WHERE o.VersionId NOT IN (SELECT ord.Id FROM @Order ord)
          UNION 
          SELECT cl.LogId AS Id, 0 AS IsObject, cl.LogDate AS OrderDate
          FROM @ChangeLogs cl) t
    ORDER BY t.OrderDate ASC;
    EXEC @Res = dbo.CheckError #014340F8BA579D, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/ 

  END;

  DECLARE @ScriptLines TABLE (LineNumber int NULL , Line varchar(max) NULL);

  INSERT INTO @ScriptLines(LineNumber, Line)
  SELECT ROW_NUMBER() OVER (ORDER BY o.OrderVal ASC, ISNULL(ol.LineNumber, cl.LineNumber) ASC),
         CASE WHEN o.IsObject = 1 THEN ol.Line
              WHEN o.IsObject = 0 THEN cl.Line END
  FROM @Order o
   LEFT JOIN @ObjectsLines ol ON o.Id = ol.VersionId AND o.IsObject = 1
   LEFT JOIN @ChangeLogsLines cl ON o.Id = cl.LogId AND o.IsObject = 0;
  EXEC @Res = dbo.CheckError #0103134E2E0622, @Res, @__ProcName; IF @Res < 0 GOTO END_ERROR;/*AUTO_CE*/

  SELECT/*RESULTSET-ALLOWED*/ * FROM @Warnings w;

  SELECT/*RESULTSET-ALLOWED*/ * FROM @ScriptLines sl;

  END_OK:
  IF @TranCnt = 0 AND @@TRANCOUNT = 1 COMMIT TRAN;
  RETURN 0;
  END_ERROR:
  IF @@TRANCOUNT > 0 AND @TranCnt = 0 ROLLBACK TRAN;
  IF @@TRANCOUNT > 0 AND XACT_STATE() != -1 AND (SELECT TOP 1 t.ID FROM dbo.sl_vv_curtran t) = @__TranId ROLLBACK TRAN @__TranName;
  RETURN @Res;
END;
GO