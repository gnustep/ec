
#include <Foundation/Foundation.h>
#include <Foundation/NSDebug.h>

#include "EcProcess.h"
#include "EcLogger.h"

@implementation	EcLogger

static NSLock           *loggersLock;
static NSMutableArray	*loggers;
static NSArray          *modes;

+ (void) initialize
{
  if (self == [EcLogger class])
    {
      id	objects[1];

      loggersLock = [NSLock new];
      loggers = [[NSMutableArray alloc] initWithCapacity: 6];
      objects[0] = NSDefaultRunLoopMode;
      modes = [[NSArray alloc] initWithObjects: objects count: 1];
    }
}

+ (EcLogger*) loggerForType: (EcLogType)t
{
  unsigned	count;
  EcLogger	*logger;

  [loggersLock lock];
  count = [loggers count];
  while (count-- > 0)
    {
      logger = [loggers objectAtIndex: count];

      if (logger->type == t)
	{
          [loggersLock unlock];
	  return logger;
	}
    }
  logger = [[EcLogger alloc] init];
  if (logger != nil)
    {
      logger->lock = [NSRecursiveLock new];
      logger->type = t;
      logger->key = [cmdLogKey(t) copy];
      logger->flushKey
	= [[NSString alloc] initWithFormat: @"BS%@Flush", logger->key];
      logger->serverKey
	= [[NSString alloc] initWithFormat: @"BS%@Server", logger->key];
      logger->interval = 10;
      logger->size = 8 * 1024;
      logger->message = [[NSMutableString alloc] initWithCapacity: 2048];
      [EcProc setCmdUpdate: logger withMethod: @selector(update)];
      [logger update];
      [loggers addObject: logger];
      RELEASE(logger);
    }
  [loggersLock unlock];
  return logger;
}

/* Should only be called on main thread, but doesn't matter.
 */
- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  return;
}

/*
 * When connecting to a logging server, we need to register so it
 * knows who we are.
 * Should only be called on main thread.
 */
- (void) cmdMadeConnectionToServer: (NSString*)name
{
  id<CmdLogger>	server;

  server = (id<CmdLogger>)[EcProc server: name];
  [server registerClient: self name: cmdLogName()];
}

/* Should only be called on main thread, but doesn't matter.
 */
- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  [from cmdGnip: self sequence: num extra: nil];
}

/* Should only be called on main thread.
 */
- (oneway void) cmdQuit: (int)status
{
  [EcProc cmdQuit: status];
}

- (void) dealloc
{
  [self flush];
  [timer invalidate];
  RELEASE(key);
  RELEASE(flushKey);
  RELEASE(serverKey);
  RELEASE(serverName);
  RELEASE(message);
  RELEASE(lock);
  [super dealloc];
}

- (NSString*) description
{
  NSMutableString	*s = [NSMutableString stringWithCapacity: 256];

  [lock lock];
  if (size == 0)
    {
      [s appendFormat: @"%@ output is immediate.\n", key];
    }
  else if (interval > 0)
    {
      [s appendFormat: @"%@ flushed every %u seconds", key, interval];
      [s appendFormat: @" or with a %u byte buffer.\n", size];
      if (timer != nil)
	{
	  [s appendFormat: @"Next flush - %@\n", [timer fireDate]];
	}
    }
  else
    {
      [s appendFormat: @"%@ flushed with a %u byte buffer.\n", key, size];
    }
  [lock unlock];
  return s;
}

/**
 * Internal flush operation ... writes data out from us, but
 * doesn't try any further.
 */
- (void) _flush
{
  unsigned      len;

  if (inFlush == YES)
    {
      return;
    }
  [lock lock];
  if (inFlush == NO && (len = [message length]) > 0)
    {
      BOOL	ok = YES;
      NSData	*buf;
      NSString	*str;

      inFlush = YES;
      str = [message copy];
      [message setString: @""];
      [lock unlock];

      buf = [str dataUsingEncoding: [NSString defaultCStringEncoding]];
      if (buf == nil)
        {
          buf = [str dataUsingEncoding: NSUTF8StringEncoding];
        }
      fwrite([buf bytes], 1, [buf length], stderr);
      if (LT_DEBUG != type)
        {
          if (nil == serverName)
            {
              id<CmdLogger>	server;

              NS_DURING
                {
                  server = (id<CmdLogger>)[EcProc cmdNewServer];
                }
              NS_HANDLER
                {
                  server = nil;
                  NSLog(@"Exception contacting Command server: %@\n",
                    localException);
                }
              NS_ENDHANDLER
              if (server != nil)
                {
                  NS_DURING
                    {
                      [server logMessage: str
                                    type: type
                                     for: EcProc];
                    }
                  NS_HANDLER
                    {
                      NSLog(@"Exception sending info to logger: %@",
                        localException);
                      ok = NO;
                    }
                  NS_ENDHANDLER
                }
              else
                {
                  ok = NO;
                }
            }
          else
            {
              id<CmdLogger>	server;

              NS_DURING
                {
                  server = (id<CmdLogger>)
                    [EcProc server: serverName];
                }
              NS_HANDLER
                {
                  server = nil;
                  NSLog(@"Exception contacting logging server: %@\n",
                    localException);
                }
              NS_ENDHANDLER
              if (server != nil)
                {
                  NS_DURING
                    {
                      [server logMessage: str
                                    type: type
                                     for: self];
                    }
                  NS_HANDLER
                    {
                      NSLog(@"Exception sending info to %@: %@",
                        serverName, localException);
                      ok = NO;
                    }
                  NS_ENDHANDLER
                }
              else
                {
                  ok = NO;
                }
            }
        }
      if (NO == ok)
        {
          if (serverName == nil)
            {
              NSLog(@"Unable to log to Command server - %@", str);
            }
          else
            {
              NSLog(@"Unable to log to %@ - %@", serverName, str);
            }
          /*
           * Flush any messages that might have been generated by
           * (or during) our failed attempt to contact server.
           */
          [lock lock];
          if ([message length] > 0)
            {
              NSString	*tmp = [message copy];

              [message setString: @""];
              NSLog(@"%@", tmp);
	      [tmp release];
            }
          [lock unlock];
        }
      RELEASE(str);
      inFlush = NO;
    }
  else
    {
      [lock unlock];
    }
}

- (void) _externalFlush: (id)dummy
{
  if (externalFlush == NO)
    {
      externalFlush = YES;

      [self _flush];
      if (LT_DEBUG != type)
	{
	  id<CmdLogger>	server;

	  if (serverName == nil)
	    {
	      NS_DURING
		{
		  server = (id<CmdLogger>)[EcProc cmdNewServer];
		}
	      NS_HANDLER
		{
		  server = nil;
		  NSLog(@"Exception contacting Command server: %@\n",
		    localException);
		}
	      NS_ENDHANDLER
	    }
	  else
	    {
	      NS_DURING
		{
		  server = (id<CmdLogger>)
		    [EcProc server: serverName];
		}
	      NS_HANDLER
		{
		  server = nil;
		  NSLog(@"Exception contacting logging server: %@\n",
		    localException);
		}
	      NS_ENDHANDLER
	    }
	  if (server != nil)
	    {
	      NS_DURING
		{
		  [server flush];	// Force round trip.
		}
	      NS_HANDLER
		{
		  NSLog(@"Exception flushing info to %@: %@",
		    serverName, localException);
		}
	      NS_ENDHANDLER
	    }
	}
      externalFlush = NO;
    }
}

/**
 * External flush operation ... writes out data and asks any server
 * we write to to flush its data out too.
 */
- (void) flush
{
  [self performSelectorOnMainThread: @selector(_externalFlush:)
                         withObject: nil
                      waitUntilDone: YES
                              modes: modes];
}

- (void) _scheduleFlush: (id)reset
{
  /* A non-nil value of reset means that we should reset to do
   * a flush real soon.
   */
  [lock lock];
  if (reset != nil)
    {
      if (timer != nil && [[timer fireDate] timeIntervalSinceNow] > 0.001)
	{
	  [timer invalidate];
	  timer = nil;
	}
      if (timer == nil)
	{
	  timer = [NSTimer scheduledTimerWithTimeInterval: 0.0001
	    target: self selector: @selector(_timeout:)
	    userInfo: nil repeats: NO];
	}
    }
  else if ([message length] >= size)
    {
      /*
       * Buffer too large - schedule immediate flush.
       */
      if (timer != nil && [[timer fireDate] timeIntervalSinceNow] > 0.001)
	{
	  [timer invalidate];
	  timer = nil;
	}
      if (timer == nil)
	{
	  timer = [NSTimer scheduledTimerWithTimeInterval: 0.0001
	    target: self selector: @selector(_timeout:)
	    userInfo: nil repeats: NO];
	}
    }
  else if (interval > 0 && timer == nil)
    {
      /*
       * No timer running - so schedule one to output the debug info.
       */
      timer = [NSTimer scheduledTimerWithTimeInterval: interval
	target: self selector: @selector(_timeout:)
	userInfo: nil repeats: NO];
    }
  [lock unlock];
}

- (void) log: (NSString*)fmt arguments: (va_list)args
{
  CREATE_AUTORELEASE_POOL(arp);
  NSString	*format;
  NSString	*text;

  format = cmdLogFormat(type, fmt);
  text = [NSString stringWithFormat: format arguments: args];

  [lock lock];
  if (message == nil)
    {
      message = [[NSMutableString alloc] initWithCapacity: 1024];
    }
  [message appendString: text];
  if ([message length] >= size || (interval > 0 && timer == nil))
    {
      [self performSelectorOnMainThread: @selector(_scheduleFlush:)
                             withObject: nil
                          waitUntilDone: NO
                                  modes: modes];
    }
  [lock unlock];
  RELEASE(arp);
}

/* Should only be called on main thread.
 */
- (void) _timeout: (NSTimer*)t
{
  if (t == nil)
    {
      [timer invalidate];
    }
  timer = nil;
  [self _flush];
}

/* Should only be called on main thread.
 */
- (void) update
{
  NSUserDefaults	*defs = [NSUserDefaults standardUserDefaults];
  NSString		*str;

  /*
   * If there is a server specified for this debug logger, we want it
   * registered so we can use it - otherwise we will default to using
   * the Command server for logging.
   */
  str = [defs stringForKey: serverKey];
  if ([str isEqual: @""] == YES)
    {
      str = nil;	// An empty string means no server is used.
    }
  if ([serverName isEqual: str] == NO)
    {
      if (serverName != nil)
	{
	  [EcProc removeServerFromList: serverName];
	}
      ASSIGN(serverName, str);
      if (serverName != nil)
	{
	  [EcProc addServerToList: serverName for: self];
	}
    }
      
  /*
   *	Is the program to flush at intervals or at
   *	a particular buffer size (or both)?
   */
  str = [defs stringForKey: flushKey];
  if (str == nil)
    {
      str = [defs stringForKey: @"BSDefaultFlush"];	// Default settings.
      if (str == nil)
	{
	  str = [defs stringForKey: @"BSDebugFlush"];	// Backward compat.
	}
    }
  if (str != nil)
    {
      NSScanner	*scanner = [NSScanner scannerWithString: str];
      int	i;

      if ([scanner scanInt: &i] == YES)
	{
	  if (i < 0)
	    interval = 0;
	  else
	    interval = i;
	}
      if (([scanner scanString: @":" intoString: 0] == YES)
	&& ([scanner scanInt: &i] == YES))
	{
	  if (i < 0)
	    size = 0;
	  else
	    size = i*1024;
	}

      /*
       * Ensure new values take effect real soon.
       */
      [self performSelectorOnMainThread: @selector(_scheduleFlush:)
                             withObject: self
                          waitUntilDone: NO
                                  modes: modes];
    }
}
@end

