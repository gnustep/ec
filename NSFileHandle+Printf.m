#import <Foundation/NSData.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileHandle.h>
#import <Foundation/NSString.h>

#include "NSFileHandle+Printf.h"

@implementation	NSFileHandle (Printf)

- (void) printWithFormat: (NSString*)format arguments: (va_list)args
{
  NSString	*text;

  text = [NSString stringWithFormat: format arguments: args];
  [self puts: text];
}

- (void) printf: (NSString*)format,...
{
  va_list ap;
  va_start(ap, format);
  [self printWithFormat: format arguments: ap];
  va_end(ap);
}

- (void) puts: (NSString*)text
{
  NS_DURING
    {
      NSData	*data;

      data = [text dataUsingEncoding: [NSString defaultCStringEncoding]];
      if (data == nil)
	{
	  data = [text dataUsingEncoding: NSUTF8StringEncoding];
	}
      [self writeData: data];
    }
  NS_HANDLER
    {
      NSLog(@"Exception writing to log file: %@", localException);
      [localException raise];
    }
  NS_ENDHANDLER
}

@end

