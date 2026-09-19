/*-----------------------------------------------------------
  File ......: hix_safe_fs.prg
  Author.....: Carles Aubia Floresvi (Charly 9000)
  Created....: 2026-09-18
  Description: Safe-Delete Root Guard. Every destructive filesystem
               primitive (erase file, remove directory) that any
               HIX module calls MUST go through HIX_SafeErase /
               HIX_SafeDirDelete. These wrappers refuse to touch a
               path that resolves outside HIX_AppRoot() or that
               matches a hardcoded system-path blacklist.
  Usage      : IF HIX_SafeErase( cSessionFile ) ; ENDIF
               IF HIX_SafeDirDelete( cTmpDir ) ; ENDIF
  Notes      : Fail-closed. If canonicalization is ambiguous or
               the path escapes the root, the wrapper returns .F.
               and logs a warning — the file/directory is left
               intact.
  License....: This Source Code Form is subject to the terms of the
               Mozilla Public License, v. 2.0. (https://mozilla.org/MPL/2.0/).
               Copyright (c) 2026 Carles Aubia Floresví - HIX Server Project
 -----------------------------------------------------------*/

#DEFINE HIX_LOG_MODULE HIX_MOD_APP

#INCLUDE "hix_logger.ch"

STATIC s_cAppRoot   := NIL
STATIC s_mtxRoot    := NIL
STATIC s_aBlackWin  := NIL
STATIC s_aBlackNix  := NIL
STATIC s_lWindows   := NIL
STATIC s_aAllowExtra := {}

INIT PROCEDURE _HixSafeFsInit()
   s_mtxRoot := hb_mutexCreate()
RETURN

// ============================================================
// HIX_SafeRegisterDir — extend the whitelist. Callers that place
// filesystem state OUTSIDE HIX_AppRoot() (e.g. session store on
// hb_DirTemp(), rotated logs on a mounted volume) must register
// their base dir here BEFORE any HIX_SafeErase / HIX_SafeDirDelete
// touches it. Blacklist entries still override — you cannot
// register c:\windows.
// ============================================================
FUNCTION HIX_SafeRegisterDir( cPath )

   LOCAL cCanon

   IF ValType( cPath ) != "C" .OR. Empty( cPath )
      RETURN .F.
   ENDIF

   cCanon := _HixSafeCanonical( cPath )
   IF cCanon == NIL
      RETURN .F.
   ENDIF

   // Reject if the dir itself is blacklisted — never register a system path.
   IF _HixSafeInBlacklist( cCanon )
      RETURN .F.
   ENDIF

   // Normalize with trailing "/" for prefix comparison later.
   IF Right( cCanon, 1 ) != "/"
      cCanon += "/"
   ENDIF
   IF _HixIsWindows()
      cCanon := Lower( cCanon )
   ENDIF

   hb_mutexLock( s_mtxRoot )
   IF AScan( s_aAllowExtra, cCanon ) == 0
      AAdd( s_aAllowExtra, cCanon )
   ENDIF
   hb_mutexUnlock( s_mtxRoot )

RETURN .T.

// ============================================================
// _HixSafeInExtraAllowed — .T. if cCanon (already canonicalized
// and lowered on Windows) sits under any registered extra dir.
// ============================================================
STATIC FUNCTION _HixSafeInExtraAllowed( cCanon )

   LOCAL cEntry, cLower

   IF Len( s_aAllowExtra ) == 0
      RETURN .F.
   ENDIF

   cLower := iif( _HixIsWindows(), Lower( cCanon ), cCanon )

   FOR EACH cEntry IN s_aAllowExtra
      // Reject the entry itself (would allow deleting the extra root).
      IF cLower + "/" == cEntry .OR. cLower == Left( cEntry, Len( cEntry ) - 1 )
         LOOP
      ENDIF
      IF Left( cLower + "/", Len( cEntry ) ) == cEntry
         RETURN .T.
      ENDIF
   NEXT

RETURN .F.

// ============================================================
// HIX_AppRoot — canonical app root (absolute, trailing "/"),
// cached. Derived from hb_DirBase() the first time it is asked.
// ============================================================
FUNCTION HIX_AppRoot()

   IF s_cAppRoot != NIL
      RETURN s_cAppRoot
   ENDIF

   hb_mutexLock( s_mtxRoot )
   IF s_cAppRoot == NIL
      s_cAppRoot := _HixSafeNormalize( hb_DirBase() )
      IF Right( s_cAppRoot, 1 ) != "/"
         s_cAppRoot += "/"
      ENDIF
   ENDIF
   hb_mutexUnlock( s_mtxRoot )

RETURN s_cAppRoot

// ============================================================
// HIX_PathIsUnderRoot — .T. if cPath (after canonicalization)
// resolves strictly under HIX_AppRoot(). The root itself does
// NOT count as "under" — never allow deleting the root.
// ============================================================
FUNCTION HIX_PathIsUnderRoot( cPath )

   LOCAL cCanon, cRoot

   cCanon := _HixSafeCanonical( cPath )

   IF cCanon == NIL
      RETURN .F.
   ENDIF

   cRoot := HIX_AppRoot()

   // Case-insensitive on Windows (drive letters + FAT/NTFS)
   IF _HixIsWindows()
      cCanon := Lower( cCanon )
      cRoot  := Lower( cRoot  )
   ENDIF

   // Reject the root itself.
   IF cCanon + "/" == cRoot .OR. cCanon == cRoot
      RETURN .F.
   ENDIF

   // Must start with root + trailing "/"
   IF Left( cCanon + "/", Len( cRoot ) ) != cRoot
      RETURN .F.
   ENDIF

RETURN .T.

// ============================================================
// HIX_SafePathAllowed — full guard chain. Public predicate.
// ============================================================
FUNCTION HIX_SafePathAllowed( cPath )

   LOCAL cCanon

   IF ValType( cPath ) != "C" .OR. Empty( cPath ) .OR. Len( AllTrim( cPath ) ) < 2
      RETURN .F.
   ENDIF

   // Null byte (truncation attack)
   IF Chr( 0 ) $ cPath
      RETURN .F.
   ENDIF

   cCanon := _HixSafeCanonical( cPath )
   IF cCanon == NIL
      RETURN .F.
   ENDIF

   // Blacklist check — defense in depth, in case HIX_AppRoot() is misconfigured
   IF _HixSafeInBlacklist( cCanon )
      RETURN .F.
   ENDIF

   IF ! HIX_PathIsUnderRoot( cPath ) .AND. ! _HixSafeInExtraAllowed( cCanon )
      RETURN .F.
   ENDIF

RETURN .T.

// ============================================================
// HIX_SafeErase — safe replacement for FErase / hb_vfErase.
// Returns .T. only if a real file was under root AND was erased.
// ============================================================
FUNCTION HIX_SafeErase( cPath )

   LOCAL lOk

   IF ! HIX_SafePathAllowed( cPath )
      lw( "SafeErase RECHAZADO: " + hb_ValToStr( cPath ) )
      RETURN .F.
   ENDIF

   IF hb_DirExists( cPath )
      lw( "SafeErase RECHAZADO (es directorio): " + cPath )
      RETURN .F.
   ENDIF

   lOk := hb_vfErase( cPath ) == 0

   IF ! lOk
      // silent if file simply did not exist — hb_vfErase returns non-zero
      // in both "no such file" and "permission denied" cases; caller decides
   ENDIF

RETURN lOk

// ============================================================
// HIX_SafeDirDelete — safe replacement for hb_DirDelete / DirRemove.
// Deletes ONE empty directory. Returns .T. on success.
// ============================================================
FUNCTION HIX_SafeDirDelete( cPath )

   IF ! HIX_SafePathAllowed( cPath )
      lw( "SafeDirDelete RECHAZADO: " + hb_ValToStr( cPath ) )
      RETURN .F.
   ENDIF

   IF ! hb_DirExists( cPath )
      RETURN .F.
   ENDIF

RETURN hb_vfDirRemove( cPath ) == 0

// ---- private helpers ----

STATIC FUNCTION _HixIsWindows()
   IF s_lWindows == NIL
      s_lWindows := ( hb_ps() == "\" )
   ENDIF
RETURN s_lWindows

// Normalize separators (\ -> /), collapse double slashes, drop trailing "/"
STATIC FUNCTION _HixSafeNormalize( cPath )

   LOCAL cResult

   IF ValType( cPath ) != "C"
      RETURN NIL
   ENDIF

   cResult := StrTran( cPath, "\", "/" )

   DO WHILE "//" $ cResult
      cResult := StrTran( cResult, "//", "/" )
   ENDDO

   // Strip trailing "/" except for drive roots ("c:/") and unix root ("/")
   IF Len( cResult ) > 1 .AND. Right( cResult, 1 ) == "/"
      IF ! ( Len( cResult ) == 3 .AND. SubStr( cResult, 2, 1 ) == ":" ) ;
            .AND. cResult != "/"
         cResult := Left( cResult, Len( cResult ) - 1 )
      ENDIF
   ENDIF

RETURN cResult

// Full canonicalization: absolute + resolve . / .. + normalized separators.
// Returns NIL on unresolvable path.
STATIC FUNCTION _HixSafeCanonical( cPath )

   LOCAL cNorm, aParts, aStack, cPart, cResult, i

   IF ValType( cPath ) != "C" .OR. Empty( cPath )
      RETURN NIL
   ENDIF

   cNorm := _HixSafeNormalize( cPath )

   // Prepend app root if not absolute. Absolute = starts with "/" (unix)
   // or has drive letter "X:" on Windows.
   IF ! _HixIsAbsolute( cNorm )
      cNorm := _HixSafeNormalize( HIX_AppRoot() + cNorm )
   ENDIF

   aParts := hb_ATokens( cNorm, "/" )
   aStack := {}

   FOR i := 1 TO Len( aParts )
      cPart := aParts[ i ]
      DO CASE
      CASE cPart == "" .AND. i > 1
         // skip empty segments (from double slash) except leading
         LOOP
      CASE cPart == "."
         LOOP
      CASE cPart == ".."
         IF Len( aStack ) > 0 .AND. ;
               ! ( Len( aStack ) == 1 .AND. ( aStack[ 1 ] == "" .OR. ;
                   ( Len( aStack[ 1 ] ) == 2 .AND. Right( aStack[ 1 ], 1 ) == ":" ) ) )
            ASize( aStack, Len( aStack ) - 1 )
         ELSE
            // .. attempting to escape root — reject
            RETURN NIL
         ENDIF
      OTHERWISE
         AAdd( aStack, cPart )
      ENDCASE
   NEXT

   cResult := ""
   FOR i := 1 TO Len( aStack )
      cResult += aStack[ i ]
      IF i < Len( aStack )
         cResult += "/"
      ENDIF
   NEXT

   // Restore leading "/" on unix absolute paths that started with "/"
   IF ! _HixIsWindows() .AND. Left( cNorm, 1 ) == "/" .AND. Left( cResult, 1 ) != "/"
      cResult := "/" + cResult
   ENDIF

RETURN cResult

STATIC FUNCTION _HixIsAbsolute( cPath )
   IF Empty( cPath ) ; RETURN .F. ; ENDIF
   IF Left( cPath, 1 ) == "/" ; RETURN .T. ; ENDIF   // unix or normalized windows
   // Windows drive letter: "X:..." (already normalized to forward slash)
   IF Len( cPath ) >= 2 .AND. SubStr( cPath, 2, 1 ) == ":"
      RETURN .T.
   ENDIF
RETURN .F.

// Drive/root paths — reject EXACTLY these, but allow subdirs.
// (An HIX app deployed at d:\myapp must be able to delete files
// under d:\myapp\...)
STATIC FUNCTION _HixBlacklistExact()
   LOCAL aList
   IF _HixIsWindows()
      aList := { "c:", "c:/", "d:", "d:/", "e:", "e:/", ;
                 "f:", "f:/", "g:", "g:/" }
   ELSE
      aList := { "/" }
   ENDIF
RETURN aList

// System paths — reject the path itself AND anything under it.
// (Never touch c:/windows/system32/kernel32.dll no matter what.)
STATIC FUNCTION _HixBlacklistRecursive()
   LOCAL aList
   IF _HixIsWindows()
      aList := { ;
         "c:/windows", "c:/program files", "c:/program files (x86)", ;
         "c:/programdata", "c:/harbour", "c:/harbour.core" }
   ELSE
      aList := { "/bin", "/boot", "/dev", "/etc", "/lib", "/lib64", ;
                 "/opt", "/proc", "/root", "/sbin", "/sys", "/usr", "/var" }
   ENDIF
RETURN aList

STATIC FUNCTION _HixSafeInBlacklist( cCanon )

   LOCAL cEntry, cLower

   cLower := iif( _HixIsWindows(), Lower( cCanon ), cCanon )

   FOR EACH cEntry IN _HixBlacklistExact()
      IF cLower == cEntry
         RETURN .T.
      ENDIF
   NEXT

   FOR EACH cEntry IN _HixBlacklistRecursive()
      IF cLower == cEntry
         RETURN .T.
      ENDIF
      IF Left( cLower, Len( cEntry ) + 1 ) == cEntry + "/"
         RETURN .T.
      ENDIF
   NEXT

RETURN .F.
