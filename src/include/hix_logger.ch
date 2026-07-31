// ============================================================
// hix_logger.ch — Macros de conveniencia para el logger
// ============================================================

#ifndef HIX_LOGGER_CH
#define HIX_LOGGER_CH

#include "hix_const.ch"
#include "fileio.ch"

#define HIX_LOG_DEBUG    1
#define HIX_LOG_INFO     2
#define HIX_LOG_WARN     3
#define HIX_LOG_ERROR    4
#define HIX_LOG_FATAL    5

#define HIX_LOG_ROTATE   ( 10 * 1024 * 1024 )

// Módulo por defecto si el .prg no define HIX_LOG_MODULE
#ifndef HIX_LOG_MODULE
#define HIX_LOG_MODULE "unknown"
#endif

#xtranslate l( <msg> )   => _l( <msg>, HIX_LOG_INFO,  HIX_LOG_MODULE )
#xtranslate ld( <msg> )  => _l( <msg>, HIX_LOG_DEBUG, HIX_LOG_MODULE )
#xtranslate lw( <msg> )  => _l( <msg>, HIX_LOG_WARN,  HIX_LOG_MODULE )
#xtranslate le( <msg> )  => _l( <msg>, HIX_LOG_ERROR, HIX_LOG_MODULE )
#xtranslate lf( <msg> )  => _l( <msg>, HIX_LOG_FATAL, HIX_LOG_MODULE )

#endif
