#include "hbhrb.ch"

THREAD STATIC s_hExLastError

/* Additive namespace API. Older compiler name remains compatible.
 * Returns a normalized hash: on compile failure h["err"] contains the
 * canonical error view and h["phase"] == "compile". See HIX_Compile_Normalize.
 */
FUNCTION HIX_CompileCode( ... )
   LOCAL h := hb_ExecFromArray( @HIX_CompileFromBuf(), hb_AParams() )
   _HixCompileAttachErr( h )
   RETURN h

/* Unified contract: never propagates Break. Always returns a hash with the same
 * shape. On compile failure h["phase"] = "compile" + h["err"] from diagnostics.
 * On runtime failure h["phase"] = "runtime" + h["err"] from captured snapshot.
 */
FUNCTION HIX_CompileRunPrg( cPath, ... )
   LOCAL aArgs := hb_AParams(), h, aRun := {}, n, nFirstArg := 2
   LOCAL hOpts := { "preamble" => .T. }
   LOCAL aAutoInc, aCompile, nOffset, hRun
   s_hExLastError := NIL
   IF ! HB_ISSTRING( cPath ) .OR. ! hb_FileExists( cPath )
      RETURN _HixCompileInvalidRun( "HIX_CompileRunPrg: source file does not exist", cPath )
   ENDIF
   /* Detect optional opts hash at position 2 (must have key "opts" to avoid
    * confusion with a hash passed as runtime arg to Main). */
   IF Len( aArgs ) >= 2 .AND. HB_ISHASH( aArgs[ 2 ] ) .AND. hb_HHasKey( aArgs[ 2 ], "opts" )
      hOpts := aArgs[ 2 ][ "opts" ]
      IF ! HB_ISHASH( hOpts ) ; hOpts := {=>} ; ENDIF
      IF ! hb_HHasKey( hOpts, "preamble" )
         hOpts[ "preamble" ] := .T.
      ENDIF
      nFirstArg := 3
   ENDIF
   aAutoInc := _HixCompileAutoIncludes()
   aCompile := { MemoRead( cPath ), { "opts" => hOpts }, aAutoInc, "-n", "-w3", "-es0", cPath }
   h := hb_ExecFromArray( @HIX_CompileCode(), aCompile )
   h[ "where" ] := _HixCompileWhere( h )
   IF ! h[ "ok" ]
      /* Compile/validate failed: err + phase already attached by HIX_CompileCode. */
      RETURN h
   ENDIF
   IF h[ "kind" ] == "hrb"
      AAdd( aRun, h[ "hrb" ] )
      AAdd( aRun, cPath )
      FOR n := nFirstArg TO Len( aArgs )
         AAdd( aRun, aArgs[ n ] )
      NEXT
      hRun := hb_ExecFromArray( @HIX_CompileRunHrb(), aRun )
      /* Do not keep binary ownership in a returned compiler result. */
      h[ "hrbBytes" ] := Len( h[ "hrb" ] )
      h[ "hrb" ] := NIL
      /* Compensate runtime stack/where if preamble was prepended. */
      nOffset := iif( hb_HHasKey( h, "preambleLines" ), h[ "preambleLines" ], 0 )
      IF nOffset > 0 .AND. HB_ISHASH( s_hExLastError )
         _HixCompileAdjustHashLines( s_hExLastError, cPath, nOffset )
      ENDIF
      IF hRun[ "ok" ]
         h[ "value" ] := hRun[ "value" ]
         h[ "phase" ] := NIL
      ELSE
         h[ "ok" ]    := .F.
         h[ "phase" ] := "runtime"
         h[ "err" ]   := _HixCompileNormalizeErr( s_hExLastError, .T. )
         /* Keep legacy "where" top-level populated from the runtime snapshot. */
         IF HB_ISHASH( s_hExLastError ) .AND. HB_ISHASH( s_hExLastError[ "where" ] )
            h[ "where" ] := s_hExLastError[ "where" ]
         ENDIF
      ENDIF
   ENDIF
   RETURN h

/* Compile-only convenience wrapper around HIX_CompileCode: reads cPath, injects
 * auto-includes and compiles with the HIX preamble prepended. Returns the
 * unified hash — the caller inspects h["ok"] / h["hrb"] / h["err"]. No run
 * phase; perfect for boot loaders that persist the .hrb to disk, and for the
 * dispatcher which runs the resulting HRB under its own timeout wrapper.
 */
FUNCTION HIX_CompileCodeFromFile( cPath )
   LOCAL cCode, aAutoInc, hCmp
   IF ! HB_ISSTRING( cPath ) .OR. ! hb_FileExists( cPath )
      RETURN _HixCompileInvalidRun( "File does not exist", cPath )
   ENDIF
   cCode := hb_MemoRead( cPath )
   IF Empty( cCode )
      RETURN _HixCompileInvalidRun( "File empty", cPath )
   ENDIF
   aAutoInc := _HixCompileAutoIncludes()
   hCmp := hb_ExecFromArray( @HIX_CompileCode(), ;
      { cCode, { "opts" => { "preamble" => .T. } }, aAutoInc, "-n", "-q2", cPath } )
   RETURN hCmp

/* Auto-includes array (-I flags + user flags). Reads HB_INCLUDE and
 * HB_USER_PRGFLAGS on every invocation; no caching so env changes propagate
 * immediately. Four sources: HIX_GetRootAbsolute (project), HB_INCLUDE,
 * platform-specific Harbour include dir, and HB_USER_PRGFLAGS trailing.
 */
STATIC FUNCTION _HixCompileAutoIncludes()
   LOCAL aOut := {}
   LOCAL cOs := OS()
   LOCAL cHBHeader := "", cHBInclude, cUserFlags
   DO CASE
      CASE "Windows" $ cOs ; cHBHeader := "c:\harbour\include"
      CASE "Linux"   $ cOs ; cHBHeader := hb_GetEnv( "HOME" ) + "/harbour/include"
   ENDCASE
   cHBInclude := hb_GetEnv( "HB_INCLUDE" )
   cUserFlags := hb_GetEnv( "HB_USER_PRGFLAGS" )
   AAdd( aOut, "-I" + HIX_GetRootAbsolute() )
   IF ! Empty( cHBInclude ) ; AAdd( aOut, "-I" + cHBInclude ) ; ENDIF
   IF ! Empty( cHBHeader )  ; AAdd( aOut, "-I" + cHBHeader ) ; ENDIF
   IF ! Empty( cUserFlags ) ; AAdd( aOut, cUserFlags ) ; ENDIF
   RETURN aOut

/* Resta nOffset a los frames stack/where cuyo file matchea cUserFile.
 * Si line <= nOffset → clamp a 1 + source="preamble".
 */
STATIC FUNCTION _HixCompileAdjustHashLines( h, cUserFile, nOffset )
   LOCAL cLow := Lower( cUserFile ), f, nRaw
   IF HB_ISARRAY( h[ "stack" ] )
      FOR EACH f IN h[ "stack" ]
         IF HB_ISHASH( f ) .AND. HB_ISSTRING( f[ "file" ] ) .AND. ;
               Lower( f[ "file" ] ) == cLow .AND. HB_ISNUMERIC( f[ "line" ] ) .AND. f[ "line" ] > 0
            nRaw := f[ "line" ]
            IF nRaw <= nOffset
               f[ "line" ] := 1
               f[ "source" ] := "preamble"
            ELSE
               f[ "line" ] := nRaw - nOffset
            ENDIF
         ENDIF
      NEXT
   ENDIF
   IF HB_ISHASH( h[ "where" ] ) .AND. HB_ISSTRING( h[ "where" ][ "file" ] ) .AND. ;
         Lower( h[ "where" ][ "file" ] ) == cLow .AND. HB_ISNUMERIC( h[ "where" ][ "line" ] ) .AND. h[ "where" ][ "line" ] > 0
      nRaw := h[ "where" ][ "line" ]
      IF nRaw <= nOffset
         h[ "where" ][ "line" ] := 1
         h[ "where" ][ "source" ] := "preamble"
      ELSE
         h[ "where" ][ "line" ] := nRaw - nOffset
      ENDIF
   ENDIF
   RETURN NIL

/* Unified contract: never propagates Break. Returns:
 *   { ok, phase ("runtime"/NIL), value, err, cleanupError }
 * The old shape returned xValue; this is a breaking change. All production
 * call sites — dispatcher, loaders, mw loader, view engine — go through this
 * unified contract now (migration completed in Fase 5, v2.3.12).
 */
FUNCTION HIX_CompileRunHrb( cHrb, cPrgName, ... )
   LOCAL aInput := hb_AParams(), aLoad := {}, aDo := {}, n, pHrb := NIL, xValue := NIL
   LOCAL bOld := ErrorBlock(), ePrimary, eCleanup, lPrimary := .F., lCleanup := .F.
   LOCAL hPrimary, hCleanup
   s_hExLastError := NIL
   BEGIN SEQUENCE WITH {|e| _HixCompileCaptureBreak( e ) }
      AAdd( aLoad, HB_HRB_BIND_FORCELOCAL + iif( HB_ISSTRING( cPrgName ), HB_HRB_ARG_PRGNAME, 0 ) )
      AAdd( aLoad, cHrb )
      IF HB_ISSTRING( cPrgName )
         AAdd( aLoad, cPrgName )
      ENDIF
      FOR n := 3 TO Len( aInput )
         AAdd( aLoad, aInput[ n ] )
      NEXT
      pHrb := hb_ExecFromArray( @hb_hrbLoad(), aLoad )
      AAdd( aDo, pHrb )
      FOR n := 3 TO Len( aInput )
         AAdd( aDo, aInput[ n ] )
      NEXT
      xValue := hb_ExecFromArray( @hb_hrbDo(), aDo )
   RECOVER USING ePrimary
      lPrimary := .T.
      /* Break( <non-Error> ) unwinds here but does NOT fire the WITH block
       * (which the Harbour error subsystem only invokes for real errors).
       * Capture ePrimary manually so err["description"] carries the raw value. */
      IF ! HB_ISHASH( s_hExLastError )
         _HixCompileCaptureBreakNoReraise( ePrimary )
      ENDIF
      hPrimary := s_hExLastError
   ALWAYS
      /* ALWAYS runs on normal return, Break and Harbour VM QUIT. */
      IF pHrb != NIL
         BEGIN SEQUENCE WITH {|e| _HixCompileCaptureBreak( e ) }
            hb_hrbUnload( pHrb )
         RECOVER USING eCleanup
            lCleanup := .T.
            hCleanup := s_hExLastError
         END SEQUENCE
         pHrb := NIL
      ENDIF
      ErrorBlock( bOld )
      IF lPrimary
         s_hExLastError := hPrimary
         IF lCleanup .AND. HB_ISHASH( s_hExLastError )
            s_hExLastError[ "cleanupError" ] := hCleanup
         ENDIF
      ELSEIF lCleanup
         s_hExLastError := hCleanup
      ENDIF
   END SEQUENCE
   /* Never re-raise. Build normalized hash. HB_SYMBOL_UNUSED avoids compile warn. */
   HB_SYMBOL_UNUSED( ePrimary )
   HB_SYMBOL_UNUSED( eCleanup )
   RETURN _HixCompileBuildRunResult( xValue, lPrimary, lCleanup )

STATIC FUNCTION _HixCompileBuildRunResult( xValue, lPrimary, lCleanup )
   LOCAL h := { "ok" => .T., "phase" => NIL, "value" => xValue, "err" => NIL, ;
                "cleanupError" => NIL }
   IF lPrimary
      h[ "ok" ]    := .F.
      h[ "phase" ] := "runtime"
      h[ "value" ] := NIL
      h[ "err" ]   := _HixCompileNormalizeErr( s_hExLastError, .T. )
   ENDIF
   IF lCleanup
      /* If primary ok, cleanup error becomes the primary. Otherwise, attach. */
      IF ! lPrimary
         h[ "ok" ]    := .F.
         h[ "phase" ] := "runtime"
         h[ "value" ] := NIL
         h[ "err" ]   := _HixCompileNormalizeErr( s_hExLastError, .T. )
      ELSE
         h[ "cleanupError" ] := iif( HB_ISHASH( s_hExLastError ) .AND. ;
            hb_HHasKey( s_hExLastError, "cleanupError" ), s_hExLastError[ "cleanupError" ], NIL )
      ENDIF
   ENDIF
   RETURN h

FUNCTION HIX_CompileLastError()
   RETURN s_hExLastError

/* Non-reraising variant: fills s_hExLastError from a Break argument caught
 * at RECOVER (Break of a non-Error value does not fire the WITH block). */
STATIC FUNCTION _HixCompileCaptureBreakNoReraise( e )
   LOCAL h := { "origin" => "runtime", "stack" => {}, "aStack" => {}, "where" => NIL }, n := 1, cFile
   LOCAL cSelf := ProcFile( 0 ), f
   IF HB_ISOBJECT( e )
      h[ "subsystem" ] := e:subsystem
      h[ "genCode" ] := e:genCode
      h[ "subCode" ] := e:subCode
      h[ "severity" ] := e:severity
      h[ "type" ] := iif( e:severity == 1, "warning", "error" )
      h[ "description" ] := e:description
      h[ "operation" ] := e:operation
      h[ "filename" ] := e:filename
      h[ "osCode" ] := e:osCode
      h[ "args" ] := e:args
   ELSE
      h[ "description" ] := hb_ValToStr( e )
   ENDIF
   DO WHILE ! Empty( ProcName( n ) ) .AND. n <= 100
      cFile := ProcFile( n )
      AAdd( h[ "stack" ], { "proc" => ProcName( n ), "line" => ProcLine( n ), "file" => cFile } )
      IF Empty( cFile ) .AND. ProcLine( n ) == 0
         AAdd( h[ "aStack" ], ProcName( n ) )
      ELSE
         AAdd( h[ "aStack" ], iif( Empty( cFile ), "?", cFile ) + ":" + hb_ntos( ProcLine( n ) ) + " " + ProcName( n ) )
      ENDIF
      ++n
   ENDDO
   FOR EACH f IN h[ "stack" ]
      IF ! Empty( f[ "file" ] ) .AND. f[ "file" ] != cSelf
         h[ "where" ] := { "kind" => "runtime", "file" => f[ "file" ], "func" => f[ "proc" ], "line" => f[ "line" ] }
         EXIT
      ENDIF
   NEXT
   s_hExLastError := h
   RETURN NIL

STATIC FUNCTION _HixCompileCaptureBreak( e )
   LOCAL h := { "origin" => "runtime", "stack" => {}, "aStack" => {}, "where" => NIL }, n := 1, cFile
   LOCAL cSelf := ProcFile( 0 ), f
   IF HB_ISOBJECT( e )
      h[ "subsystem" ] := e:subsystem
      h[ "genCode" ] := e:genCode
      h[ "subCode" ] := e:subCode
      h[ "severity" ] := e:severity
      h[ "type" ] := iif( e:severity == 1, "warning", "error" )
      h[ "description" ] := e:description
      h[ "operation" ] := e:operation
      h[ "filename" ] := e:filename
      h[ "osCode" ] := e:osCode
      h[ "args" ] := e:args
      h[ "tries" ] := e:tries
      h[ "canDefault" ] := e:canDefault
      h[ "canRetry" ] := e:canRetry
      h[ "canSubstitute" ] := e:canSubstitute
   ELSE
      h[ "description" ] := hb_ValToStr( e )
   ENDIF
   DO WHILE ! Empty( ProcName( n ) ) .AND. n <= 100
      cFile := ProcFile( n )
      AAdd( h[ "stack" ], { "proc" => ProcName( n ), "line" => ProcLine( n ), "file" => cFile } )
      /* One string per frame: "file:line function"; a frame with no file and line 0 (VM/loader) is just "function". */
      IF Empty( cFile ) .AND. ProcLine( n ) == 0
         AAdd( h[ "aStack" ], ProcName( n ) )
      ELSE
         AAdd( h[ "aStack" ], iif( Empty( cFile ), "?", cFile ) + ":" + hb_ntos( ProcLine( n ) ) + " " + ProcName( n ) )
      ENDIF
      ++n
   ENDDO
   /* where: first frame with a file that is not this library: the code that failed. */
   FOR EACH f IN h[ "stack" ]
      IF ! Empty( f[ "file" ] ) .AND. f[ "file" ] != cSelf
         h[ "where" ] := { "kind" => "runtime", "file" => f[ "file" ], "func" => f[ "proc" ], "line" => f[ "line" ] }
         EXIT
      ENDIF
   NEXT
   s_hExLastError := h
   RETURN Break( e )

/* Where a compilation failed: first error/fatal diagnostic. Compiler diagnostics carry no function. */
STATIC FUNCTION _HixCompileWhere( h )
   LOCAL d
   IF HB_ISHASH( h ) .AND. ! h[ "ok" ]
      FOR EACH d IN h[ "diagnostics" ]
         IF d[ "severity" ] == "error" .OR. d[ "severity" ] == "fatal"
            RETURN { "kind" => "compile", "file" => d[ "file" ], "func" => "", "line" => d[ "line" ] }
         ENDIF
      NEXT
   ENDIF
   RETURN NIL

/* Public: normalize a raw error hash (runtime snapshot or compile diagnostic)
 * into the unified err shape. lRuntime = .T. for s_hExLastError, .F. for a
 * compile diagnostic. Called internally and exposed for callers that already
 * have a snapshot in hand (eg. HIX_CompileLastError consumers).
 */
FUNCTION HIX_CompileNormalizeErr( hRaw, lRuntime )
   RETURN _HixCompileNormalizeErr( hRaw, lRuntime )

STATIC FUNCTION _HixCompileNormalizeErr( hRaw, lRuntime )
   LOCAL hErr, cFile, nLine, cSub, nGen
   IF ! HB_ISHASH( hRaw ) ; RETURN NIL ; ENDIF
   IF lRuntime
      cFile := ""
      nLine := 0
      IF HB_ISHASH( hRaw[ "where" ] )
         cFile := iif( HB_ISSTRING( hRaw[ "where" ][ "file" ] ), hRaw[ "where" ][ "file" ], "" )
         nLine := iif( HB_ISNUMERIC( hRaw[ "where" ][ "line" ] ), hRaw[ "where" ][ "line" ], 0 )
      ENDIF
      cSub := iif( hb_HHasKey( hRaw, "subsystem" ) .AND. HB_ISSTRING( hRaw[ "subsystem" ] ), hRaw[ "subsystem" ], "" )
      nGen := iif( hb_HHasKey( hRaw, "genCode" )   .AND. HB_ISNUMERIC( hRaw[ "genCode" ] ), hRaw[ "genCode" ], 0 )
      hErr := { ;
         "kind"        => "runtime", ;
         "severity"    => iif( hb_HHasKey( hRaw, "type" ) .AND. HB_ISSTRING( hRaw[ "type" ] ), hRaw[ "type" ], "runtime" ), ;
         "code"        => iif( Empty( cSub ), "", cSub + "/" + hb_NToS( nGen ) ), ;
         "description" => iif( hb_HHasKey( hRaw, "description" ) .AND. HB_ISSTRING( hRaw[ "description" ] ), hRaw[ "description" ], "" ), ;
         "file"        => cFile, ;
         "line"        => nLine, ;
         "lineCode"    => _HixCompileReadSourceLine( cFile, nLine ), ;
         "operation"   => iif( hb_HHasKey( hRaw, "operation" ), hRaw[ "operation" ], NIL ), ;
         "args"        => iif( hb_HHasKey( hRaw, "args" ), hRaw[ "args" ], NIL ), ;
         "subsystem"   => iif( Empty( cSub ), NIL, cSub ), ;
         "genCode"     => iif( hb_HHasKey( hRaw, "genCode" ), hRaw[ "genCode" ], NIL ), ;
         "subCode"     => iif( hb_HHasKey( hRaw, "subCode" ), hRaw[ "subCode" ], NIL ), ;
         "osCode"      => iif( hb_HHasKey( hRaw, "osCode" ), hRaw[ "osCode" ], NIL ), ;
         "filename"    => iif( hb_HHasKey( hRaw, "filename" ), hRaw[ "filename" ], NIL ), ;
         "stack"       => iif( hb_HHasKey( hRaw, "stack" ), hRaw[ "stack" ], NIL ), ;
         "aStack"      => iif( hb_HHasKey( hRaw, "aStack" ), hRaw[ "aStack" ], NIL ) ;
      }
      RETURN hErr
   ENDIF
   /* Compile diagnostic. */
   cFile := iif( hb_HHasKey( hRaw, "file" ) .AND. HB_ISSTRING( hRaw[ "file" ] ), hRaw[ "file" ], "" )
   nLine := iif( hb_HHasKey( hRaw, "line" ) .AND. HB_ISNUMERIC( hRaw[ "line" ] ), hRaw[ "line" ], 0 )
   hErr := { ;
      "kind"        => "compile", ;
      "severity"    => iif( hb_HHasKey( hRaw, "severity" ) .AND. HB_ISSTRING( hRaw[ "severity" ] ), hRaw[ "severity" ], "error" ), ;
      "code"        => iif( hb_HHasKey( hRaw, "id" ) .AND. HB_ISSTRING( hRaw[ "id" ] ) .AND. ! Empty( hRaw[ "id" ] ), hRaw[ "id" ], "" ), ;
      "description" => iif( hb_HHasKey( hRaw, "message" ) .AND. HB_ISSTRING( hRaw[ "message" ] ), hRaw[ "message" ], "" ), ;
      "file"        => cFile, ;
      "line"        => nLine, ;
      "lineCode"    => _HixCompileReadSourceLine( cFile, nLine ) ;
   }
   RETURN hErr

/* Attach h["err"] from the first error/fatal diagnostic. Warnings do not populate
 * err and do not flip ok. */
STATIC FUNCTION _HixCompileAttachErr( h )
   LOCAL d
   IF ! HB_ISHASH( h ) ; RETURN NIL ; ENDIF
   IF h[ "ok" ] ; RETURN NIL ; ENDIF
   /* Preserve phase if already set (eg. "validate" from input validation). */
   IF ! hb_HHasKey( h, "phase" ) .OR. ! HB_ISSTRING( h[ "phase" ] ) .OR. Empty( h[ "phase" ] )
      h[ "phase" ] := "compile"
   ENDIF
   FOR EACH d IN h[ "diagnostics" ]
      IF HB_ISHASH( d ) .AND. ( d[ "severity" ] == "error" .OR. d[ "severity" ] == "fatal" )
         h[ "err" ] := _HixCompileNormalizeErr( d, .F. )
         EXIT
      ENDIF
   NEXT
   RETURN NIL

/* Minimal result hash returned when RunPrg validation fails (file missing, etc).
 * Looks like a compile phase failure for caller symmetry. */
STATIC FUNCTION _HixCompileInvalidRun( cMessage, cPath )
   LOCAL hErr := { ;
      "kind" => "compile", "severity" => "error", "code" => "E0000", ;
      "description" => cMessage, ;
      "file" => iif( HB_ISSTRING( cPath ), cPath, "" ), "line" => 0, "lineCode" => "" }
   RETURN { "ok" => .F., "phase" => "compile", "value" => NIL, ;
      "diagnostics" => {}, "errors" => 1, "warnings" => 0, "preambleLines" => 0, ;
      "where" => NIL, "err" => hErr, "kind" => NIL, "hrb" => NIL }

STATIC FUNCTION _HixCompileReadSourceLine( cFile, nLine )
   LOCAL cText, aLines
   IF ! HB_ISSTRING( cFile ) .OR. Empty( cFile ) .OR. ! HB_ISNUMERIC( nLine ) .OR. nLine < 1
      RETURN ""
   ENDIF
   IF ! hb_FileExists( cFile ) ; RETURN "" ; ENDIF
   cText := StrTran( MemoRead( cFile ), Chr( 13 ), "" )
   aLines := hb_ATokens( cText, Chr( 10 ) )
   IF nLine > Len( aLines ) ; RETURN "" ; ENDIF
   RETURN AllTrim( aLines[ nLine ] )
