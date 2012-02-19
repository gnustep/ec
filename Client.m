

#import <Foundation/Foundation.h>

#import "EcProcess.h"
#import "Client.h"


@implementation ClientInfo

- (NSComparisonResult) compare: (ClientInfo*)other
{
  return [name compare: [other name]];
}

- (NSData*) config
{
  return config;
}

- (void) dealloc
{
  NSConnection	*c = [obj connectionForProxy];

  if (c != nil)
    {
      RETAIN(c);
      [[NSNotificationCenter defaultCenter]
	removeObserver: theServer
		  name: NSConnectionDidDieNotification
		object: (id)c];
      if (unregistered == NO && [c isValid] == YES)
	{
	  NS_DURING
	    {
	      [obj cmdQuit: 0];
	    }
	  NS_HANDLER
	    {
	      NSLog(@"cmdQuit: to %@ - %@", name, localException);
	    }
	  NS_ENDHANDLER
	}
      RELEASE(c);
    }
  DESTROY(lastUnanswered);
  DESTROY(config);
  DESTROY(files);
  DESTROY(name);
  DESTROY(obj);
  [super dealloc];
}

- (NSMutableSet*) files
{
  return files;
}

- (BOOL) gnip: (unsigned)s
{
  if (s != revSequence + 1 && revSequence != 0)
    {
      NSLog(@"Gnip from %@ seq: %u when expecting %u", name, s, revSequence);
      if (s == 0)
        {
	  fwdSequence = 0;	// Reset
	}
    }
  revSequence = s;
  if (revSequence == fwdSequence)
    {
      DESTROY(lastUnanswered);
      return YES;				/* up to date	*/
    }
  else
    {
      return NO;
    }
}

- (id) initFor: (id)o
	  name: (NSString*)n
	  with: (id<CmdClient>)s
{
  self = [super init];
  if (self != nil)
    {
      theServer = s;
      files = [NSMutableSet new];
      [self setObj: o];
      [self setName: n];
      pingOk = [o respondsToSelector: @selector(cmdPing:sequence:extra:)];
      if (pingOk == NO)
	NSLog(@"Warning - %@ is an old server ... it can't be pinged", n);
    }
  return self;
}

- (NSDate*) lastUnanswered
{
  return lastUnanswered;
}

- (NSString*) name
{
  return name;
}

- (id) obj
{
  return obj;
}

- (void) ping
{
  if (pingOk == NO)
    {
      return;
    }
  if (fwdSequence == revSequence)
    {
      lastUnanswered = [[NSDate date] retain];
      NS_DURING
	{
	  [obj cmdPing: theServer sequence: ++fwdSequence extra: nil];
	}
      NS_HANDLER
	{
	  NSLog(@"Ping to %@ - %@", name, localException);
	}
      NS_ENDHANDLER
    }
  else
    {
      NSLog(@"Ping to %@ when one is already in progress.", name);
    }
}

- (void) setConfig: (NSData*)c
{
  ASSIGN(config, c);
}

- (void) setName: (NSString*)n
{
  ASSIGN(name, n);
}

- (void) setObj: (id)o
{
  ASSIGN(obj, o);
}

- (void) setTransient: (BOOL)flag
{
  transient = flag;
}

- (void) setUnregistered: (BOOL)flag
{
  unregistered = flag;
}

- (BOOL) transient
{
  return transient;
}
@end


