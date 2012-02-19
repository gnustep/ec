
#import <Foundation/NSObject.h>

@class	GSMimeSMTPClient;
@class	NSArray;
@class	NSMutableArray;
@class	NSMutableDictionary;
@class	NSString;
@class	NSTimer;


@interface	EcAlerter : NSObject
{
  NSArray		*rules;
  NSMutableDictionary	*email;
  NSMutableDictionary	*sms;
  NSTimer		*timer;
  NSString		*eFrom;
  NSString		*eHost;
  NSString		*ePort;
  GSMimeSMTPClient	*smtp;
}
- (BOOL) configure: (NSNotification*)n;
- (void) handleInfo: (NSString*)str;
- (void) flushEmail;
- (void) flushSms;
- (void) log: (NSMutableDictionary*)m to: (NSArray*)destinations;
- (void) mail: (NSMutableDictionary*)m to: (NSArray*)destinations;
- (void) sms: (NSMutableDictionary*)m to: (NSArray*)destinations;
- (void) timeout: (NSTimer*)t;
@end

