
@interface	ClientInfo : NSObject
{
  id<CmdClient>	theServer;
  id		obj;
  NSString	*name;
  NSDate	*lastUnanswered;	/* Last unanswered ping.	*/
  unsigned	fwdSequence;		/* Last ping sent TO client.	*/
  unsigned	revSequence;		/* Last gnip sent BY client.	*/
  NSMutableSet	*files;			/* Want update info for these.	*/
  NSData	*config;		/* Config info for client.	*/
  BOOL		pingOk;
  BOOL		transient;
  BOOL		unregistered;
}
- (NSComparisonResult) compare: (ClientInfo*)other;
- (NSData*) config;
- (NSMutableSet*) files;
- (BOOL) gnip: (unsigned)seq;
- (id) initFor: (id)obj
          name: (NSString*)n
	  with: (id<CmdClient>)svr;
- (NSDate*) lastUnanswered;
- (NSString*) name;
- (id) obj;
- (void) ping;
- (void) setConfig: (NSData*)c;
- (void) setName: (NSString*)n;
- (void) setObj: (id)o;
- (void) setTransient: (BOOL)flag;
- (void) setUnregistered: (BOOL)flag;
- (BOOL) transient;
@end

