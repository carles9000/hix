/* Independent EX interface. Core reference: 6deac9cf3ad977ae829e5bca543d553b92dd4b6d.
 * No original HB_COMPILE* symbols are redefined.
 */
#include "hbcomp.h"
#include "hbapiitm.h"
#include "hbapierr.h"
#include "hbdate.h"
#include <stdarg.h>
#include <limits.h>

typedef struct
{
   PHB_ITEM includes;
   PHB_ITEM diagnostics;
   HB_SIZE errors, warnings, emitted, maxdiag;
} HBCE_CONTEXT;

static void put( PHB_ITEM hash, const char * key, PHB_ITEM value )
{
   PHB_ITEM name = hb_itemPutC( NULL, key );
   hb_hashAdd( hash, name, value );
   hb_itemRelease( name );
}

static void hbce_putc( PHB_ITEM hash, const char * key, const char * value )
{
   PHB_ITEM item = hb_itemPutC( NULL, value );
   put( hash, key, item );
   hb_itemRelease( item );
}

static void putn( PHB_ITEM hash, const char * key, HB_SIZE value )
{
   PHB_ITEM item = hb_itemPutNInt( NULL, ( HB_MAXINT ) value );
   put( hash, key, item );
   hb_itemRelease( item );
}

static void putl( PHB_ITEM hash, const char * key, HB_BOOL value )
{
   PHB_ITEM item = hb_itemPutL( NULL, value );
   put( hash, key, item );
   hb_itemRelease( item );
}

/* Retry rather than silently cut messages at 512 bytes. MSVC's snprintf
 * may return -1 on truncation; Harbour's own version returns required size.
 */
static char * format( const char * pattern, ... )
{
   HB_SIZE capacity = 256;
   char * text = NULL;
   int length;
   for( ;; )
   {
      va_list args;
      text = ( char * ) hb_xrealloc( text, capacity );
      va_start( args, pattern );
      length = hb_vsnprintf( text, capacity, pattern, args );
      va_end( args );
      if( length >= 0 && ( HB_SIZE ) length < capacity )
         return text;
      capacity = length >= 0 ? ( HB_SIZE ) length + 1 : capacity * 2;
   }
}

/* On the pinned core, hb_compDispMessage has exactly two callers:
 * hb_compGenError/Warning. Compiler call sites use the exported compiler
 * tables; ppcomp passes the preprocessor's private tables. Compare template
 * POINTER identity, never message text or overlapping numeric codes.
 * Valid only for the documented pinned call graph; re-audit on upgrades.
 */
static const char * hbce_origin( char prefix, int code, const char * pattern )
{
   if( prefix == 'W' )
   {
      if( code >= 1 && code <= HB_COMP_WARN_STATIC_FUNC_UNUSED &&
          pattern == hb_comp_szWarnings[ code - 1 ] + 1 )
         return "compiler";
   }
   else if( code >= 1 && code <= HB_COMP_ERR_HISTORICAL_4 &&
            pattern == hb_comp_szErrors[ code - 1 ] )
      return "compiler";
   return "preprocessor";
}

static void collect( void * cargo, int errorfmt, int line,
                     const char * module, char prefix, int code,
                     const char * pattern, const char * par1, const char * par2 )
{
   HBCE_CONTEXT * ctx = ( HBCE_CONTEXT * ) ( ( PHB_COMP ) cargo )->cargo;
   PHB_ITEM diag, nil;
   char id[ 32 ], pref[ 2 ];
   char * message, * raw;
   HB_SYMBOL_UNUSED( errorfmt );
   if( hb_vmRequestQuery() != 0 )
      return;
   ++ctx->emitted;
   if( prefix == 'W' )
      ++ctx->warnings;
   else
      ++ctx->errors;
   if( hb_arrayLen( ctx->diagnostics ) >= ctx->maxdiag )
      return;

   message = format( pattern ? pattern : "", par1 ? par1 : "", par2 ? par2 : "" );
   hb_snprintf( id, sizeof( id ), "%c%04d", prefix, code );
   pref[ 0 ] = prefix;
   pref[ 1 ] = '\0';
   /* Canonical Clipper rendering, even if caller selected IDE format. */
   raw = module ? format( "\r%s(%d) %s %s  %s\n", module, line,
                         prefix == 'W' ? "Warning" : "Error", id, message ) :
                  format( "%s %s  %s\n", prefix == 'W' ? "Warning" : "Error", id, message );
   diag = hb_hashNew( NULL );
   nil = hb_itemNew( NULL );
   putn( diag, "seq", ctx->emitted );
   hbce_putc( diag, "origin", hbce_origin( prefix, code, pattern ) );
   hbce_putc( diag, "phase", strcmp( hbce_origin( prefix, code, pattern ), "preprocessor" ) == 0 ? "preprocess" : "compile" );
   hbce_putc( diag, "tool", "harbour" );
   hbce_putc( diag, "severity", prefix == 'W' ? "warning" : prefix == 'F' ? "fatal" : "error" );
   hbce_putc( diag, "prefix", pref );
   putn( diag, "code", ( HB_SIZE ) code );
   hbce_putc( diag, "id", id );
   hbce_putc( diag, "file", module ? module : "" );
   putn( diag, "line", line > 0 ? ( HB_SIZE ) line : 0 );
   put( diag, "column", nil );
   hbce_putc( diag, "message", message );
   hbce_putc( diag, "raw", raw );
   hb_arrayAdd( ctx->diagnostics, diag );
   hb_itemRelease( nil );
   hb_itemRelease( diag );
   hb_xfree( raw );
   hb_xfree( message );
}

static int open_include( void * cargo, char * filename,
                        HB_BOOL before, HB_BOOL sysfile, HB_BOOL binary,
                        HB_PATHNAMES * paths, HB_BOOL * nested, FILE ** file,
                        const char ** buffer, HB_SIZE * length, HB_BOOL * freebuf )
{
   HBCE_CONTEXT * ctx = ( HBCE_CONTEXT * ) ( ( PHB_COMP ) cargo )->cargo;
   HB_SYMBOL_UNUSED( sysfile );
   HB_SYMBOL_UNUSED( binary );
   HB_SYMBOL_UNUSED( paths );
   HB_SYMBOL_UNUSED( nested );
   HB_SYMBOL_UNUSED( file );
   /* Match core order: filesystem first, hash as fallback. Empty includes
    * are valid here, unlike hb_compileFromBuf's nLen > 0 check.
    */
   if( ! before && ctx->includes )
   {
      PHB_ITEM item = hb_hashGetCItemPtr( ctx->includes, filename );
      if( item && HB_IS_STRING( item ) )
      {
         *buffer = hb_itemGetCPtr( item );
         *length = hb_itemGetCLen( item );
         *freebuf = HB_FALSE;
         return HB_PP_OPEN_OK;
      }
   }
   return HB_PP_OPEN_FILE;
}

/* Private bridge. Public PRG wrapper validates and normalizes arguments.
 * source, includes/NIL, flattened string array, maxdiag, warn, es.
 */
HB_FUNC( HIX_COMPILE_FROMBUF )
{
   PHB_ITEM args = hb_param( 3, HB_IT_ARRAY );
   const char * source = hb_parc( 1 );
   HBCE_CONTEXT ctx;
   PHB_ITEM result, nil, elapsed;
   HB_BYTE * buffer = NULL;
   HB_SIZE length = 0, i, count;
   const char ** argv;
   char warn[ 8 ], es[ 8 ];
   int status;
   HB_MAXUINT start;

   /* Defensive gate for calls that bypass the public wrapper. */
   if( ! source || ! args || hb_parnint( 4 ) < 0 ||
       hb_parni( 5 ) < 0 || hb_parni( 5 ) > 4 ||
       hb_parni( 6 ) < 0 || hb_parni( 6 ) > 2 ||
       memchr( source, '\0', hb_parclen( 1 ) ) != NULL )
   {
      hb_errRT_BASE( EG_ARG, 3012, NULL, HB_ERR_FUNCNAME, HB_ERR_ARGS_BASEPARAMS );
      return;
   }
   count = hb_arrayLen( args );
   if( count > ( HB_SIZE ) INT_MAX - 4 )
   {
      hb_errRT_BASE( EG_ARG, 3012, NULL, HB_ERR_FUNCNAME, HB_ERR_ARGS_BASEPARAMS );
      return;
   }
   for( i = 1; i <= count; ++i )
   {
      PHB_ITEM arg = hb_arrayGetItemPtr( args, i );
      if( ! HB_IS_STRING( arg ) || hb_itemGetCLen( arg ) == 0 ||
          memchr( hb_itemGetCPtr( arg ), '\0', hb_itemGetCLen( arg ) ) != NULL )
      {
         hb_errRT_BASE( EG_ARG, 3012, NULL, HB_ERR_FUNCNAME, HB_ERR_ARGS_BASEPARAMS );
         return;
      }
   }

   ctx.includes = hb_param( 2, HB_IT_HASH );
   ctx.diagnostics = hb_itemArrayNew( 0 );
   ctx.errors = ctx.warnings = ctx.emitted = 0;
   ctx.maxdiag = ( HB_SIZE ) hb_parnint( 4 );
   hb_snprintf( warn, sizeof( warn ), "-w%d", hb_parni( 5 ) );
   hb_snprintf( es, sizeof( es ), "-es%d", hb_parni( 6 ) );
   argv = ( const char ** ) hb_xgrab( ( count + 5 ) * sizeof( char * ) );
   argv[ 0 ] = "hbcompex"; /* core skips argv[0]; never skip a user's flag */
   argv[ 1 ] = warn;
   argv[ 2 ] = es;
   for( i = 1; i <= count; ++i )
      argv[ i + 2 ] = hb_arrayGetCPtr( args, i );
   argv[ count + 3 ] = "-q2"; /* last: quiet cannot hide collect() */
   argv[ count + 4 ] = NULL;
   start = hb_timerGet();
   status = hb_compMainExt( ( int ) count + 4, argv, &buffer, &length,
                           source, 0, &ctx, open_include, collect );
   hb_xfree( ( void * ) argv );

   result = hb_hashNew( NULL );
   nil = hb_itemNew( NULL );
   putl( result, "ok", status == EXIT_SUCCESS && ctx.errors == 0 &&
                         buffer != NULL && length > 0 && hb_vmRequestQuery() == 0 );
   putn( result, "status", ( HB_SIZE ) status );
   hbce_putc( result, "phase", "compile" );
   putn( result, "errors", ctx.errors );
   putn( result, "warnings", ctx.warnings );
   put( result, "diagnostics", ctx.diagnostics );
   putn( result, "emitted", ctx.emitted );
   putn( result, "dropped", ctx.emitted - hb_arrayLen( ctx.diagnostics ) );
   putl( result, "truncated", ctx.emitted > hb_arrayLen( ctx.diagnostics ) );
   putl( result, "aborted", hb_vmRequestQuery() != 0 );
   put( result, "hrb", nil );
   put( result, "kind", nil );
   put( result, "raw", nil );
   put( result, "value", nil );
   put( result, "runtime", nil );
   elapsed = hb_itemPutND( NULL, ( double ) ( hb_timerGet() - start ) / 1000.0 );
   put( result, "elapsed", elapsed );
   hb_itemRelease( elapsed );
   if( buffer )
   {
      if( status == EXIT_SUCCESS && ctx.errors == 0 && hb_vmRequestQuery() == 0 )
      {
         PHB_ITEM output = hb_itemPutCL( NULL, ( const char * ) buffer, length );
         put( result, "hrb", output );
         hbce_putc( result, "kind", length >= 4 && memcmp( buffer, "\xC0" "HRB", 4 ) == 0 ? "hrb" : "other" );
         hb_itemRelease( output );
      }
      hb_xfree( buffer );
   }
   hb_itemRelease( nil );
   hb_itemRelease( ctx.diagnostics );
   hb_itemReturnRelease( result );
}
