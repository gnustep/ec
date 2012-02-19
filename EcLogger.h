
#ifndef	_ECLOGGER_H
#define	_ECLOGGER_H

@interface	EcLogger : NSObject <CmdPing>
{
  NSRecursiveLock       *lock;
  NSDate		*last;
  NSTimer		*timer;
  unsigned		interval;
  unsigned		size;
  NSMutableString	*message;
  EcLogType		type;
  NSString		*key;
  NSString		*flushKey;
  NSString		*serverKey;
  NSString		*serverName;
  BOOL			inFlush;
  BOOL                  externalFlush;
  BOOL			registered;
  BOOL			pendingFlush;
}
+ (EcLogger*) loggerForType: (EcLogType)t;
- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) cmdMadeConnectionToServer: (NSString*)name;
- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data;
- (void) flush;
- (void) log: (NSString*)fmt arguments: (va_list)args;
- (void) update;
@end

#endif

