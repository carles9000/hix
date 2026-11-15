/* Public wrapper. No user code executes inside the compiler's C callbacks. */
FUNCTION HIX_CompileFromBuf( cSource, ... )
   LOCAL aInput := hb_AParams(), aArgs := {}, hIncludes := NIL
   LOCAL hOpts := {=>}, hResult, bCallback := NIL, x, y, d, k
   LOCAL nFirst := 2, nWarn := 1, nEs := 0, nMax := 500
   LOCAL lPreamble := .F., nOffset := 0, cSourceFile := "", nRaw, cLow

   IF ! HB_ISSTRING( cSource )
      RETURN _HixCompileInvalid( "cSource must be a string" )
   ENDIF
   IF Chr( 0 ) $ cSource
      RETURN _HixCompileInvalid( "Embedded NUL in cSource would silently truncate compilation" )
   ENDIF
   IF Len( aInput ) >= nFirst .AND. HB_ISHASH( aInput[ nFirst ] )
      IF hb_HHasKey( aInput[ nFirst ], "opts" )
         hOpts := aInput[ nFirst ][ "opts" ]
         ++nFirst
         IF ! HB_ISHASH( hOpts )
            RETURN _HixCompileInvalid( "opts must be a hash" )
         ENDIF
      ENDIF
   ENDIF
   IF Len( aInput ) >= nFirst .AND. HB_ISHASH( aInput[ nFirst ] )
      hIncludes := aInput[ nFirst ]
      ++nFirst
      FOR EACH k IN hb_HKeys( hIncludes )
         IF ! HB_ISSTRING( k ) .OR. ! HB_ISSTRING( hIncludes[ k ] )
            RETURN _HixCompileInvalid( "Include names and contents must be strings" )
         ENDIF
         IF Chr( 0 ) $ k
            RETURN _HixCompileInvalid( "Embedded NUL in include name" )
         ENDIF
      NEXT
   ENDIF
   FOR EACH k IN hb_HKeys( hOpts )
      IF ! HB_ISSTRING( k )
         RETURN _HixCompileInvalid( "Option names must be strings" )
      ENDIF
      IF AScan( { "warn", "es", "maxdiag", "callback", "stopOnErr", "raw", "preamble" }, k ) == 0
         RETURN _HixCompileInvalid( "Unsupported option: " + k )
      ENDIF
   NEXT
   IF hb_HHasKey( hOpts, "preamble" )
      IF ! HB_ISLOGICAL( hOpts[ "preamble" ] )
         RETURN _HixCompileInvalid( "preamble must be logical" )
      ENDIF
      lPreamble := hOpts[ "preamble" ]
   ENDIF
   IF hb_HHasKey( hOpts, "warn" )
      nWarn := hOpts[ "warn" ]
   ENDIF
   IF hb_HHasKey( hOpts, "es" )
      nEs := hOpts[ "es" ]
   ENDIF
   IF hb_HHasKey( hOpts, "maxdiag" )
      nMax := hOpts[ "maxdiag" ]
   ENDIF
   IF ! HB_ISNUMERIC( nWarn ) .OR. ! HB_ISNUMERIC( nEs ) .OR. ! HB_ISNUMERIC( nMax )
      RETURN _HixCompileInvalid( "warn, es and maxdiag must be integers" )
   ENDIF
   IF nWarn != Int( nWarn ) .OR. nWarn < 0 .OR. nWarn > 4 .OR. ;
      nEs != Int( nEs ) .OR. nEs < 0 .OR. nEs > 2 .OR. ;
      nMax != Int( nMax ) .OR. nMax < 0 .OR. nMax > 1000000
      RETURN _HixCompileInvalid( "Ranges: warn 0..4, es 0..2, maxdiag 0..1000000" )
   ENDIF
   FOR EACH k IN { "stopOnErr", "raw" }
      IF hb_HHasKey( hOpts, k )
         IF ! HB_ISLOGICAL( hOpts[ k ] )
            RETURN _HixCompileInvalid( k + " must be logical" )
         ENDIF
         IF hOpts[ k ]
            RETURN _HixCompileInvalid( k + "=.T. is not implemented in this phase" )
         ENDIF
      ENDIF
   NEXT
   IF hb_HHasKey( hOpts, "callback" )
      bCallback := hOpts[ "callback" ]
      IF bCallback != NIL .AND. ! HB_ISBLOCK( bCallback )
         RETURN _HixCompileInvalid( "callback must be a codeblock or NIL" )
      ENDIF
   ENDIF
   FOR nFirst := nFirst TO Len( aInput )
      x := aInput[ nFirst ]
      IF HB_ISARRAY( x )
         FOR EACH y IN x
            IF ! HB_ISSTRING( y )
               RETURN _HixCompileInvalid( "Compiler argument arrays must contain strings" )
            ENDIF
            IF Chr( 0 ) $ y
               RETURN _HixCompileInvalid( "Embedded NUL in compiler argument" )
            ENDIF
            IF Len( y ) > 0
               AAdd( aArgs, y )
            ENDIF
         NEXT
      ELSEIF HB_ISSTRING( x )
         IF Chr( 0 ) $ x
            RETURN _HixCompileInvalid( "Embedded NUL in compiler argument" )
         ENDIF
         IF Len( x ) > 0
            AAdd( aArgs, x )
         ENDIF
      ELSE
         RETURN _HixCompileInvalid( "Expected compiler strings/arrays; logical error mode is not supported" )
      ENDIF
   NEXT
   /* Preamble: prepend HIX directives + remember offset for line compensation. */
   IF lPreamble
      cSource := HIX_CompilePreamble() + cSource
      nOffset := HIX_CompilePreambleLines()
   ENDIF
   /* Locate source filename (last non-flag arg) to filter diagnostics by file. */
   FOR EACH x IN aArgs
      IF Len( x ) > 0 .AND. Left( x, 1 ) != "-"
         cSourceFile := x
      ENDIF
   NEXT
   /* No filename provided: inject a synthetic one so diagnostics don't surface
    * Harbour's "{SOURCE}.prg" placeholder. Derived from the first caller frame
    * outside this module when available; "inline.prg" otherwise. */
   IF Empty( cSourceFile )
      cSourceFile := _HixCompileSyntheticName()
      AAdd( aArgs, cSourceFile )
   ENDIF
   cLow := Lower( cSourceFile )
   hResult := HIX_Compile_FromBuf( cSource, hIncludes, aArgs, nMax, nWarn, nEs )
   /* Compensate lines in diagnostics attributed to the user source. Covers all
    * severities (warnings, errors, fatals). Clamp to 1 with source="preamble"
    * flag if the diagnostic falls inside the synthetic preamble. */
   IF nOffset > 0
      FOR EACH d IN hResult[ "diagnostics" ]
         IF HB_ISNUMERIC( d[ "line" ] ) .AND. d[ "line" ] > 0 .AND. ;
               ( Empty( d[ "file" ] ) .OR. Lower( d[ "file" ] ) == cLow )
            nRaw := d[ "line" ]
            IF nRaw <= nOffset
               d[ "line" ]   := 1
               d[ "source" ] := "preamble"
            ELSE
               d[ "line" ] := nRaw - nOffset
            ENDIF
         ENDIF
      NEXT
   ENDIF
   hResult[ "preambleLines" ] := nOffset
   IF HB_ISBLOCK( bCallback )
      /* A callback error propagates normally; compilation resources are freed.
       * Clone avoids callback mutations corrupting the stored diagnostics.
       */
      FOR EACH d IN hResult[ "diagnostics" ]
         Eval( bCallback, hb_HClone( d ) )
      NEXT
   ENDIF
   RETURN hResult

/* Build a readable virtual filename for buffer compilations where the caller
 * didn't pass one. Walks the call stack to find the first .prg outside the
 * HIX compile subsystem and uses its basename; falls back to "inline.prg". */
STATIC FUNCTION _HixCompileSyntheticName()
   LOCAL cFile, cProc, cBase, n := 1
   DO WHILE ! Empty( ProcName( n ) ) .AND. n <= 100
      cFile := ProcFile( n )
      cProc := Upper( ProcName( n ) )
      /* Skip frames inside the compile subsystem (any HIX_COMPILE* / _HIXCOMPILE*
       * function, or an HRB-loader frame like HB_HRBDO / HB_EXECFROMARRAY). */
      IF ! Empty( cFile ) .AND. Lower( hb_FNameExt( cFile ) ) == ".prg" .AND. ;
            ! ( "HIX_COMPILE" $ cProc ) .AND. ! ( "_HIXCOMPILE" $ cProc ) .AND. ;
            ! ( "HB_HRB" $ cProc ) .AND. ! ( "HB_EXECFROMARRAY" $ cProc )
         cBase := Lower( hb_FNameName( cFile ) )
         /* Reject lib modules by filename too (defensive). */
         IF cBase != "exrun" .AND. cBase != "frombufex"
            RETURN cBase + "-inline.prg"
         ENDIF
      ENDIF
      ++n
   ENDDO
   RETURN "inline.prg"

STATIC FUNCTION _HixCompileInvalid( cMessage )
   LOCAL hDiag := { "seq" => 1, "phase" => "validate", "tool" => "hbcompex", ;
      "severity" => "error", "prefix" => "E", "code" => 0, "id" => "E0000", ;
      "file" => "", "line" => 0, "column" => NIL, "message" => cMessage, "raw" => cMessage }
   RETURN { "ok" => .F., "status" => 1, "phase" => "validate", "hrb" => NIL, ;
      "kind" => NIL, "errors" => 1, "warnings" => 0, "diagnostics" => { hDiag }, ;
      "emitted" => 1, "dropped" => 0, "truncated" => .F., "aborted" => .F., ;
      "raw" => NIL, "value" => NIL, "runtime" => NIL, "elapsed" => 0, ;
      "preambleLines" => 0 }
