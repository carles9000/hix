/*-----------------------------------------------------------
  File ......: message.prg
  Author.....: Charly 9000
  Created....: 2026-08-20
  Modified...: 2026-08-20
  Version....: 1.1.0
  Description: Renders the /message screen: the post form that
               feeds data/messages.dbf through POST /api/message.
  Usage      : GET /message
  Notes      : No table read here -- the screen only posts.
 -----------------------------------------------------------*/

FUNCTION Main()

RETURN UView( 'message.html' )
