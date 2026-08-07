/*-----------------------------------------------------------
  File ......: init_mw_{{MIDDLEWARE_NAME_LOWER}}.prg
  Description: Loader stub for HixMw{{MIDDLEWARE_NAME}}. Its only job
               is to pull the middleware into the compile unit so
               its public function gets registered globally when
               HIX_Loaders() runs at boot.
 -----------------------------------------------------------*/

#include '/middlewares/{{MIDDLEWARE_NAME_LOWER}}.prg'
