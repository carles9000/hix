#define HB_HRB_BIND_DEFAULT    	0x0  /* do not overwrite any functions, ignore
											public HRB functions if functions with the same
											names already exist */
#define HB_HRB_BIND_LOCAL      	0x1  /* do not overwrite any functions, but keep local
											references, so if module has public function FOO
											and this function exists already, then the
											function in HRB is converted to STATIC one */
#define HB_HRB_BIND_OVERLOAD   	0x2  /* overload all existing public functions */
#define HB_HRB_BIND_FORCELOCAL 	0x3  /* convert all public functions to STATIC ones */
#define HB_HRB_BIND_LAZY       	0x4  /* Doesn't check references, allows load HRB with */

#define HB_HRB_FUNC_PUBLIC     	0x1  /* locally defined public functions */
#define HB_HRB_FUNC_STATIC     	0x2  /* locally defined static functions */
#define HB_HRB_FUNC_EXTERN     	0x4  /* external functions used in HRB module */
