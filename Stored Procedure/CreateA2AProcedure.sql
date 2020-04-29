CREATE PROCEDURE
	InsertLetterRecord
		/** Parameters **/
		@StudentId INT
		, @SchoolId INT
		, @Grade INT
		, @LetterDate VARCHAR(11)
		, @LetterType VARCHAR(6)
		, @LetterCode VARCHAR(2) = 'TR'
		, @Comment VARCHAR(80)
AS
	BEGIN
		/** Prevent conditions for data race **/
		SET TRANSACTION ISOLATION LEVEL SERIALIZABLE
		/** Check that record doesn't already exist **/
		IF NOT EXISTS (
			SELECT
				INV.PID
				, INV.SCL
				, INV.GR
				, INV.DT
				, INV.DS
			FROM
				INV
			WHERE
				INV.PID = @StudentId
				AND INV.SCL = @SchoolId
				AND INV.GR = @Grade
				AND (
					INV.DT = @LetterDate
					OR INV.DT = DATEADD(DAY, 1, @LetterDate)
					OR INV.DT = DATEADD(DAY, 2, @LetterDate)
				)
				AND INV.DS = @LetterType
				AND INV.CD = @LetterCode
				AND (
					INV.DEL = 0
					OR INV.DEL = 1	-- Do not re-add records that have been deleted
				)
		)
		BEGIN
			/** Create record **/
			INSERT INTO
				INV (
					PID		--StudentID
					, SQ	--Sequence
					, GR	--Grade
					, SCL	--School
					, CD	--Code (Truant)
					, DS	--Disposition (Letter Type)
					, DY	--Day (unused; default=0)
					, HR	--Hour (unused; default=0)
					, CO	--Comment
					, DP	--Display (Visible to Parent)
					, IDT	--Insert date
					, IUI	--UserID
					, IUN	--Username
					, UUI	--UserID
					, UUN	--Username
					, DT	--Letter Date
				)
			VALUES (
				(
					SELECT
						ID
					FROM
						STU
					WHERE
						STU.ID = @StudentId
						AND STU.SC = @SchoolId
						AND STU.DEL = 0
				)
				, (
					SELECT
						CASE
							WHEN MAX(SQ) <> ''
								THEN (MAX(SQ))
							ELSE 1
						END
					FROM
						INV
					WHERE
						INV.PID = @StudentId
				) + 1
				, @Grade
				, @SchoolId
				, @LetterCode
				, @LetterType
				, 0
				, 0
				, @Comment
				, 0
				, GETDATE()
				, 0
				, 'A2A-Integration'
				, 0
				, 'A2A-Integration'
				, Convert(DATE, @LetterDate)
			)
		END
	END