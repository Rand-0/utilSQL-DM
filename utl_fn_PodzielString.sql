-- Funkcja do dzielenia ciągu tekstu na podstawie separatora i przedstawienie w postaci tabeli
-- Alternatywa dla STRING_SPLIT (dostepny dopiero od wersji SQL 2017)
CREATE FUNCTION dbo.utl_fn_PodzielString(@String varchar(max), @Separator varchar(10))
RETURNS @t TABLE
(
  Line varchar(1000) NULL 
)
AS
BEGIN
  
  DECLARE @name nvarchar(255);
  DECLARE @pos int;

  WHILE CHARINDEX(@Separator, @String) > 0
  BEGIN
    SELECT @pos  = CHARINDEX(@Separator, @String);  
    SELECT @name = SUBSTRING(@String, 1, @pos-1);
    
    INSERT INTO @t(Line)  
    SELECT @name;
    
    SELECT @String = SUBSTRING(@String, @pos+1, LEN(@String)-@pos);
  END;

  INSERT INTO @t(Line)  
  SELECT @String;

  RETURN;
END;
GO