
#include <Foundation/NSFileHandle.h>

/** File handle printing utilities.
 */
@interface	NSFileHandle (Printf)

- (void) printWithFormat: (NSString*)format arguments: (va_list)args;
- (void) printf: (NSString*)format,...;
- (void) puts: (NSString*)text;

@end

