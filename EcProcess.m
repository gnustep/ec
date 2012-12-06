
/** Enterprise Control Configuration and Logging

   Copyright (C) 2012 Free Software Foundation, Inc.

   Written by: Richard Frith-Macdonald <rfm@gnu.org>
   Date: Febrary 2010
   Originally developed from 1996 to 2012 by Brainstorm, and donated to
   the FSF.

   This file is part of the GNUstep project.

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 3 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
   Boston, MA 02111 USA.

   */

#import <Foundation/NSArray.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSData.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSDebug.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSDistantObject.h>
#import <Foundation/NSException.h>
#import <Foundation/NSFileManager.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSObjCRuntime.h>
#import <Foundation/NSPort.h>
#import <Foundation/NSProcessInfo.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSScanner.h>
#import <Foundation/NSSerialization.h>
#import <Foundation/NSString.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSUserDefaults.h>
#import <Foundation/NSValue.h>

#import <GNUstepBase/GSObjCRuntime.h>


#import "EcProcess.h"
#import "EcLogger.h"
#import "EcAlarm.h"
#import "EcAlarmDestination.h"
#import "EcHost.h"
#import "EcUserDefaults.h"
#import "EcBroadcastProxy.h"

#include "malloc.h"

#include "config.h"

#ifdef	HAVE_SYS_SIGNAL_H
#include <sys/signal.h>
#endif
#ifdef	HAVE_SYS_FILE_H
#include <sys/file.h>
#endif
#ifdef	HAVE_SYS_FCNTL_H
#include <sys/fcntl.h>
#endif
#ifdef	HAVE_UNISTD_H
#include <unistd.h>
#endif
#ifdef	HAVE_PWD_H
#include <pwd.h>
#endif
#ifdef	HAVE_SYS_TIME_H
#include <sys/time.h>
#endif
#ifdef	HAVE_SYS_RESOURCE_H
#include <sys/resource.h>
#endif



#if	!defined(EC_DEFAULTS_PREFIX)
#define	EC_DEFAULTS_PREFIX nil
#endif
#if	!defined(EC_DEFAULTS_STRICT)
#define	EC_DEFAULTS_STRICT NO
#endif
#if	!defined(EC_EFFECTIVE_USER)
#define	EC_EFFECTIVE_USER nil
#endif

/* Lock for controlling access to per-process singleton instance.
 */
static NSRecursiveLock	*ecLock = nil;

static BOOL		cmdFlagDaemon = NO;
static BOOL		cmdFlagTesting = NO;
static BOOL		cmdIsQuitting = NO;
static NSString		*cmdInst = nil;
static NSString		*cmdName = nil;
static NSString		*cmdUser = nil;
static NSUserDefaults	*cmdDefs = nil;
static NSString		*cmdDebugName = nil;
static NSMutableDictionary	*cmdLogMap = nil;

static NSDate	*started = nil;	/* Time object was created.		*/
static NSDate	*lastIP = nil;	/* Time of last input to object.	*/
static NSDate	*lastOP = nil;	/* Time of last output by object.	*/

static Class	cDateClass = 0;
static Class	dateClass = 0;
static Class	stringClass = 0;
static int	cmdSignalled = 0;

static RETSIGTYPE
ihandler(int sig)
{
  static	BOOL	beenHere = NO;

  signal(sig, ihandler);
  if (NO == beenHere)
    {
      beenHere = YES;
      signal(SIGABRT, SIG_DFL);
      abort();
    }
  exit(sig);
#if	RETSIGTYPE != void
  return 0;
#endif
}

static RETSIGTYPE
qhandler(int sig)
{
  signal(sig, ihandler);
  /* We store the signal value in a global variable and return to normal
   * processing ... that way later code can check on the sttate of the
   * variable and take action outside the handler.
   * We can't act immediately here inside the handler as the signal may
   * have interrupted some vital library (eg malloc()) and left it in a
   * state such that our code can't continue.  For instance if we try to
   * cleanup after a signal and call free(), the process may hang waiting
   * for a lock that the interupted malloc() functioin still holds.
   */
  if (0 == cmdSignalled)
    {
      cmdSignalled = sig;
    }
  else
    {
      static BOOL	beenHere = NO;

      if (NO == beenHere)
	{
	  beenHere = YES;
	  signal(SIGABRT, SIG_DFL);
	  abort();
	}
      exit(sig);
    }
#if	RETSIGTYPE != void
  return 0;
#endif
}

NSString*
cmdVersion(NSString *ver)
{
  static NSString	*version = @"1997-1999";

  if (ver != nil)
    {
      ASSIGNCOPY(version, ver);
    }
  return version;
}

static NSString	*homeDir = nil;

NSString*
cmdHomeDir()
{
  return homeDir;
}

void
cmdSetHome(NSString *home)
{
  ASSIGNCOPY(homeDir, home);
}

static NSString	*userDir = nil;

static NSString*
cmdUserDir()
{
  if (userDir == nil)
    return NSHomeDirectoryForUser(cmdUser);
  else
    return userDir;
}

static NSString*
cmdSetUserDirectory(NSString *dir)
{
  if (dir == nil)
    {
      dir = NSHomeDirectoryForUser(cmdUser);
    }
  else if ([dir isAbsolutePath] == NO)
    {
      dir = [NSHomeDirectoryForUser(cmdUser)
	stringByAppendingPathComponent: dir];
    }
  ASSIGNCOPY(userDir, dir);
  return userDir;
}

static NSString	*dataDir = nil;

/*
 * Return the current logging directory - if 'today' is not nil, treat it as
 * the name of a subdirectory in which todays logs should be archived.
 * Create the directory path if necessary.
 */
NSString*
cmdLogsDir(NSString *date)
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  NSString	*str = cmdUserDir();
  BOOL		flag;

  if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
    {
      if ([mgr createDirectoryAtPath: str
         withIntermediateDirectories: YES
                          attributes: nil
                               error: NULL] == NO)
	{
	  if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	    {
	      NSLog(@"Unable to create directory - %@", str);
	      return nil;
	    }
	}
      else
	{
	  flag = YES;
	}
    }
  if (flag == NO)
    {
      NSLog(@"The path '%@' is not a directory", str);
      return nil;
    }

  str = [str stringByAppendingPathComponent: @"Logs"];
  if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
    {
      if ([mgr createDirectoryAtPath: str
         withIntermediateDirectories: YES
                          attributes: nil
                               error: NULL] == NO)
	{
	  if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	    {
	      NSLog(@"Unable to create directory - %@", str);
	      return nil;
	    }
	}
      else
	{
	  flag = YES;
	}
    }
  if (flag == NO)
    {
      NSLog(@"The path '%@' is not a directory", str);
      return nil;
    }

  if (date != nil)
    {
      str = [str stringByAppendingPathComponent: date];
      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	{
	  if ([mgr createDirectoryAtPath: str
             withIntermediateDirectories: YES
                              attributes: nil
                                   error: NULL] == NO)
	    {
	      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		{
		  NSLog(@"Unable to create directory - %@", str);
		  return nil;
		}
	    }
	  else
	    {
	      flag = YES;
	    }
	}
      if (flag == NO)
	{
	  NSLog(@"The path '%@' is not a directory", str);
	  return nil;
	}
    }

  if (homeDir != nil)
    {
      str = [str stringByAppendingPathComponent: homeDir];
      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	{
	  if ([mgr createDirectoryAtPath: str
             withIntermediateDirectories: YES
                              attributes: nil
                                   error: NULL] == NO)
	    {
	      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		{
		  NSLog(@"Unable to create directory - %@", str);
		  return nil;
		}
	    }
	  else
	    {
	      flag = YES;
	    }
	}
      if (flag == NO)
	{
	  NSLog(@"The path '%@' is not a directory", str);
	  return nil;
	}
    }

  return str;
}

NSString*
cmdLogKey(EcLogType t)
{
  switch (t)
    {
      case LT_DEBUG:	return @"Debug";
      case LT_WARNING:	return @"Warn";
      case LT_ERROR:	return @"Error";
      case LT_AUDIT:	return @"Audit";
      case LT_ALERT:	return @"Alert";
      default:		return @"UnknownLogType";
    }
}

NSString*
cmdLogName()
{
  static NSString	*cmdLogName = nil;

  if (nil == cmdLogName)
    {
      [ecLock lock];
      if (nil == cmdLogName)
	{
	  NSString	*n = [EcProc cmdName];

	  if (nil == n)
	    {
	      n = [[NSProcessInfo processInfo] processName];
	    }
	  cmdLogName = [n copy];
	}
      [ecLock unlock];
    }
  return cmdLogName;
}

NSString*
cmdLogFormat(EcLogType t, NSString *fmt)
{
  static NSString	*h = nil;
  static NSDictionary	*l = nil;
  NSCalendarDate	*c = [[cDateClass alloc] init];
  NSString	*f = cmdLogKey(t);
  NSString	*n = cmdLogName();
  NSString	*d;
  NSString	*result;
  
  if (h == nil)
    {
      h = [[[NSHost currentHost] wellKnownName] copy];
    }
  if (l == nil)
    {
      l = [[cmdDefs dictionaryRepresentation] copy];
    }
  d = [c descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M:%S %z" locale: l];
  result = [stringClass stringWithFormat: @"%@(%@): %@ %@ - %@\n",
    n, h, d, f, fmt];
  RELEASE(c);
  return result;
}









EcProcess		*EcProc = nil;
static NSConnection     *EcProcConnection = nil;

static EcAlarmDestination	*alarmDestination = nil;

static EcLogger	*alertLogger = nil;
static EcLogger	*auditLogger = nil;
static EcLogger	*debugLogger = nil;
static EcLogger	*errorLogger = nil;
static EcLogger	*warningLogger = nil;

static NSMutableSet	*cmdActions = nil;
static id		cmdServer = nil;
static id		cmdPTimer = nil;
static NSDictionary	*cmdConf = nil;
static NSDictionary	*cmdOperators = nil;
static NSDate		*cmdFirst = nil;
static NSDate		*cmdLast = nil;
static BOOL		cmdIsTransient = NO;
static NSMutableSet	*cmdDebugModes = nil;
static NSMutableDictionary	*cmdDebugKnown = nil;
static NSMutableString	*replyBuffer = nil;
static SEL		cmdTimSelector = 0;
static NSTimeInterval	cmdTimInterval = 60.0;

static NSMutableArray	*noNetConfig = nil;

static NSMutableDictionary *servers = nil;

static NSString		*hostName = nil;
static NSString	*
ecHostName()
{
  NSString	*name;

  [ecLock lock];
  if (nil == hostName)
    {
      hostName = [[[NSHost currentHost] wellKnownName] retain];
    }
  name = [hostName retain];
  [ecLock unlock];
  return [name autorelease];
}

#define	DEFMEMALLOWED	50
static int	memAllowed = DEFMEMALLOWED;
static int	memLast = 0;
static int	memPeak = 0;
static int	memSlot = 0;
static int	memRoll[10];
#define	memSize (sizeof(memRoll)/sizeof(*memRoll))


static NSString*
findAction(NSString *cmd)
{
  NSString	*found = nil;

  cmd = [cmd lowercaseString];
  [ecLock lock];
  if (nil == (found = [cmdActions member: cmd]))
    {
      NSEnumerator	*enumerator;
      NSString		*name;

      enumerator = [cmdActions objectEnumerator];
      while (nil != (name = [enumerator nextObject]))
	{
	  if (YES == [name hasPrefix: cmd])
	    {
	      if (nil == found)
		{
		  found = name;
		}
	      else
		{
		  found = nil;	// Ambiguous
                  break;
		}
	    }
	}
    }
  cmd = [found retain];
  [ecLock unlock];
  return [cmd autorelease];
}
 
static NSString*
ecCommandHost()
{
  NSString	*host;

  host = [cmdDefs stringForKey: @"CommandHost"];
  if (nil == host)
    {
      host = @"";	/* Local host 	*/
    }
  return host;
}

static NSString*
ecCommandName()
{
  NSString	*name;

  name = [cmdDefs stringForKey: @"CommandName"];
  if (nil == name)
    {
      name = @"Command";
    }
  return name;
}


NSString	*cmdDefaultDbg = @"defaultMode";
NSString	*cmdConnectDbg = @"connectMode";
NSString	*cmdDetailDbg = @"detailMode";


static int	comp_len = 0;

static int
comp(const char* s0, const char* s1)
{
  comp_len = 0;
  if (s0 == 0) {
      s0 = "";
  }
  if (s1 == 0) {
      s1 = "";
  }
  while (*s0) {
      if (*s0 != *s1) {
	  char	c0 = islower(*s0) ? toupper(*s0) : *s0;
	  char	c1 = islower(*s1) ? toupper(*s1) : *s1;

	  if (c0 != c1) {
	      if (c0 != '\0') {
		  comp_len = -1; /* s0 is not a substring of s1.	*/
	      }
	      return(-1);
	  }
      }
      comp_len++;
      s0++;
      s1++;
  }
  if (*s0 != *s1) {
      return(-1);
  }
  return(0);
}

static NSString*
findMode(NSDictionary* d, NSString* s)
{
  NSArray	*a = [d allKeys];
  NSString	*o;
  unsigned int	i;
  const char	*s0 = [s UTF8String];
  const char	*s1;
  int		best_pos = -1;
  int		best_len = 0;

  for (i = 0; i < [a count]; i++)
    {
      o = (NSString*)[a objectAtIndex: i];
      s1 =  [o UTF8String];
      if (comp(s0, s1) == 0)
	{
	  return o;
	}
      if (comp_len > best_len)
	{
	  best_len = comp_len;
	  best_pos = i;
	}
    }
  if (best_pos >= 0)
    {
      return (NSString*)[a objectAtIndex: best_pos];
    }
  return nil;
}

/*
 * Auxiliary object representing a remote server a subclass might need
 * to connect to.  This class is for EcProcess.m internal use. 
 */
@interface RemoteServer : NSObject
{
  /* This is the string which identifies this server */
  NSString *defaultName;
  /* These are the actual name and host for this server, as obtained
     by configuration for the `defaultName' server */
  NSString *name;
  NSString *host;

  /* The same for multiple servers */
  NSArray *multiple;

  /* The real object representing the remote server. */
  id proxy;
  /* An object responding to cmdMadeConnectionToServer: and/or 
     cmdLostConnectionToServer: */
  id delegate;
  
}
/* Initialize the object - string is the default server name */
- (id) initWithDefaultName: (NSString *)string
		  delegate: (id)object;
- (NSString *) defaultName;
- (void) setName: (NSString *)string;
- (NSString *) name;
- (void) setHost: (NSString *)string;
- (void) setMultiple: (NSArray*)config;
- (NSArray*) multiple;
/* 
 * Return a proxy to the remote server; create one if needed by making
 * a connection, using name and host.  
 * If the server is multiple, create a EcBroadcastProxy object, and returns 
 * that object. 
 */
- (id) proxy;
/*
 * Internal connection management methods
 */
- (id) connectionBecameInvalid: (NSNotification*)notification;
- (BOOL) connection: (NSConnection*)ancestor
  shouldMakeNewConnection: (NSConnection*)newConn;
- (void) BCP: (EcBroadcastProxy *)proxy
  lostConnectionToServer: (NSString *)name
  host: (NSString *)host;
- (void) BCP: (EcBroadcastProxy *)proxy
  madeConnectionToServer: (NSString *)name
  host: (NSString *)host;
/*
 * Returns YES if the connection is ALIVE, NO if the connection is DEAD
 */
- (BOOL) isConnected;
- (NSString *)description;
- (void) update;
@end
 
@implementation RemoteServer

- (id) initWithDefaultName: (NSString *)string
		  delegate: (id)object
{
  self = [super init];
  if (self != nil)
    {
      ASSIGNCOPY(defaultName, string);
      ASSIGN(name, defaultName);
      host = @"*";
      multiple = nil;
      proxy = nil;
      delegate = object;
      /*
       * Grab configuration information.
       */
      [self update];
    }
  return self;
}

- (void) dealloc
{
  DESTROY(defaultName);
  DESTROY(name);
  DESTROY(host);
  DESTROY(multiple);
  DESTROY(proxy);
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [super dealloc];
}

- (NSString *) defaultName
{
  return defaultName;
}

- (void) setName: (NSString *)string
{
  if ([name isEqual: string] == NO)
    {
      ASSIGNCOPY(name, string);
      DESTROY(proxy);
    }
}

- (NSString *) name
{
  return name;
}

- (void) setHost: (NSString *)string
{
  if ([host isEqual: string] == NO)
    {
      ASSIGNCOPY(host, string);
      DESTROY(proxy);
    }
}

- (NSString *) host
{
  return host;
}

- (void) setMultiple: (NSArray *)config
{
  if ([multiple isEqual: config] == NO)
    {
      ASSIGNCOPY(multiple, config);
      DESTROY(proxy);
    }
}

- (NSArray*) multiple
{
  return multiple;
}

- (id) proxy
{
  if (nil == proxy)
    {
      if (nil == multiple)
	{
	  [EcProc cmdDbg: cmdConnectDbg
		     msg: @"Looking for service %@ on host %@", name, host];
	  proxy = [NSConnection rootProxyForConnectionWithRegisteredName: name 
				host: host
	    usingNameServer: [NSSocketPortNameServer sharedInstance]];
	  if (proxy != nil)
	    {
	      id connection = [proxy connectionForProxy];
	  
	      RETAIN (proxy);
	      [connection setDelegate: self];
	      [[NSNotificationCenter defaultCenter]
		addObserver: self
		selector: @selector(connectionBecameInvalid:)
		name: NSConnectionDidDieNotification
		object: connection];
	      if ([delegate respondsToSelector:
		@selector(cmdMadeConnectionToServer:)] == YES)
		{
		  [delegate cmdMadeConnectionToServer: defaultName];
		}
	      [EcProc cmdDbg: cmdConnectDbg
		msg: @"Connected to %@ server on host %@",
		name, host]; 
	    }
	  else
	    {
	      [EcProc cmdDbg: cmdConnectDbg
		msg: @"Failed to contact %@ server on host %@",
		name, host];
	    }
	}
      else /* a multiple server */
	{
	  proxy = [[EcBroadcastProxy alloc] initWithReceivers: multiple]; 
	  [proxy BCPsetDelegate: self];
	}    
    }
  return proxy;
}

- (id) connectionBecameInvalid: (NSNotification*)notification
{
  id connection = [notification object];
  
  [[NSNotificationCenter defaultCenter] 
    removeObserver: self
    name: NSConnectionDidDieNotification
    object: connection];
  
  if ([connection isKindOfClass: [NSConnection class]])
    {
      if (connection == [proxy connectionForProxy])
	{
	  [EcProc cmdDbg: cmdConnectDbg
	    msg: @"lost connection - clearing %@.", 
	    name];
	  if ([delegate respondsToSelector:
	    @selector(cmdLostConnectionToServer:)] == YES)
	    {
	      [delegate cmdLostConnectionToServer: defaultName];
	    }
	  RELEASE (proxy);
	  proxy = nil;
	}
    }
  else    
    {
      [self error: "non-Connection sent invalidation"];
    }
  return self;
}

/* Debugging purposes only */
- (BOOL) connection: (NSConnection*)ancestor
  shouldMakeNewConnection: (NSConnection*)newConn
{
  [EcProc cmdDbg: cmdConnectDbg
	     msg: @"New connection 0x%p created", newConn];
  return YES;
}

- (BOOL) isConnected
{
  if (proxy != nil)
    {
      return YES;
    }
  else 
    {
      return NO;
    }  
}

- (NSString*) description
{
  if (multiple == nil)
    {
      NSString *status;
      
      if (proxy != nil)
	{
	  status = @"LIVE";
	}
      else
	{
	  status = @"DEAD";
	}
      
      return [NSString stringWithFormat:
	@"Connection to server `%@' on host `%@' is %@", 
	name, host, status];
    }
  else /* multiple server */
    {
      if (proxy == nil)
	{
	  return [NSString stringWithFormat:
	    @"Multiple connection to servers %@\n" 
	    @" has not yet been initialized", 
	    multiple];
	}
      else
	{
	  return [proxy BCPstatus];
	}
    }
}

- (void) BCP: (EcBroadcastProxy*)proxy
  lostConnectionToServer: (NSString*)name
  host: (NSString*)host
{
  if ([delegate respondsToSelector:
    @selector(cmdLostConnectionToServer:)] == YES)
    {
      /* FIXME: How do we inform delegate of this ?  Is it of any use ? */
      //      [delegate cmdLostConnectionToServer: defaultName];
    }
}

- (void) BCP: (EcBroadcastProxy*)proxy
  madeConnectionToServer: (NSString*)name
  host: (NSString*)host
{
  if ([delegate respondsToSelector:
    @selector(cmdLostConnectionToServer:)] == YES)
    {
      /* FIXME: How do we inform delegate of this ?  Is it of any use ? */
      //[delegate cmdMadConnectionToServer: defaultName];
    }
}

- (void) update
{
  NSString		*configKey;
  id			configValue;

  configKey = [defaultName stringByAppendingString: @"Name"];
  configValue = [cmdDefs stringForKey: configKey];
  if (nil != configValue)
    {
      [self setName: configValue];
    }

  configKey = [defaultName stringByAppendingString: @"Host"];
  configValue = [cmdDefs stringForKey: configKey];
  if (nil != configValue)
    {
      [self setHost: configValue];
    }
  
  configKey = [defaultName stringByAppendingString: @"BroadCast"];
  configValue = [cmdDefs arrayForKey: configKey];
  if (nil != configValue)
    {
      [self setMultiple: configValue];
    }
}

@end

@interface	EcProcess (Private)
- (void) cmdMesgrelease: (NSArray*)msg;
- (void) cmdMesgtesting: (NSArray*)msg;
- (NSString*) _moveLog: (NSString*)name to: (NSString*)sub;
- (void) _timedOut: (NSTimer*)timer;
- (void) _update: (NSMutableDictionary*)info;
@end

@implementation EcProcess

static NSString	*noFiles = @"No log files to archive";

- (id) cmdConfig: (NSString*)key
{
  return [cmdDefs objectForKey: key];
}

- (NSString*) cmdDataDirectory
{
  if (dataDir == nil)
    {
      NSFileManager	*mgr = [NSFileManager defaultManager];
      NSString		*str = cmdUserDir();
      BOOL		flag;

      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	{
	  if ([mgr createDirectoryAtPath: str
             withIntermediateDirectories: YES
                              attributes: nil
                                   error: NULL] == NO)
	    {
	      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		{
		  NSLog(@"Unable to create directory - %@", str);
		  return nil;
		}
	    }
	  else
	    {
	      flag = YES;
	    }
	}
      if (flag == NO)
	{
	  NSLog(@"The path '%@' is not a directory", str);
	  return nil;
	}

      str = [str stringByAppendingPathComponent: @"Data"];
      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	{
	  if ([mgr createDirectoryAtPath: str
             withIntermediateDirectories: YES
                              attributes: nil
                                   error: NULL] == NO)
	    {
	      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		{
		  NSLog(@"Unable to create directory - %@", str);
		  return nil;
		}
	    }
	  else
	    {
	      flag = YES;
	    }
	}
      if (flag == NO)
	{
	  NSLog(@"The path '%@' is not a directory", str);
	  return nil;
	}

      if (homeDir != nil)
	{
	  str = [str stringByAppendingPathComponent: homeDir];
	  if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	    {
	      if ([mgr createDirectoryAtPath: str
                 withIntermediateDirectories: YES
                                  attributes: nil
                                       error: NULL] == NO)
		{
		  if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		    {
		      NSLog(@"Unable to create directory - %@", str);
		      return nil;
		    }
		}
	      else
		{
		  flag = YES;
		}
	    }
	  if (flag == NO)
	    {
	      NSLog(@"The path '%@' is not a directory", str);
	      return nil;
	    }
	}

      ASSIGNCOPY(dataDir, str);
    }
  return dataDir;
}

- (NSUserDefaults*) cmdDefaults
{
  return cmdDefs;
}

- (void) cmdDefaultsChanged: (NSNotification*)n
{
  NSEnumerator	*enumerator;
  NSDictionary	*dict;
  NSString	*mode;
  NSString	*str;

  enumerator = [cmdDebugKnown keyEnumerator];
  while (nil != (mode = [enumerator nextObject]))
    {
      NSString	*key = [@"Debug-" stringByAppendingString: mode];

      if (YES == [cmdDefs boolForKey: key])
	{
	  [cmdDebugModes addObject: mode];
	}
      else
	{
	  [cmdDebugModes removeObject: mode];
	}
    }

  dict = [cmdDefs dictionaryForKey: @"WellKnownHostNames"];
  if (nil != dict)
    {
      [NSHost setWellKnownNames: dict];
      [ecLock lock];
      ASSIGN(hostName, [[NSHost currentHost] wellKnownName]);
      [ecLock unlock];
    }

  GSDebugAllocationActive([cmdDefs boolForKey: @"Memory"]);
  [NSObject enableDoubleReleaseCheck: [cmdDefs boolForKey: @"Release"]];
  cmdFlagTesting = [cmdDefs boolForKey: @"Testing"];

  if ((str = [cmdDefs stringForKey: @"CmdInterval"]) != nil)
    {
      [self setCmdInterval: [str floatValue]];
    }

  str = [cmdDefs stringForKey: @"MemAllowed"];
  if (nil != str)
    {
      memAllowed = [str intValue];
      if (memAllowed <= 0)
        {
          memAllowed = DEFMEMALLOWED;	// Fifty megabytes default
        }
    }

  if (servers != nil)
    {
      NSEnumerator *e;
      RemoteServer *server;

      e = [servers objectEnumerator];

      while ((server = [e nextObject])) 
	{
	  [server update];
	}
    }
}

- (NSString*) cmdDebugPath
{
  if (cmdDebugName == nil)
    return nil;
  return [cmdLogsDir(nil) stringByAppendingPathComponent: cmdDebugName]; 
}

- (NSString*) cmdInstance
{
  return cmdInst;
}

- (BOOL) cmdIsDaemon
{
  return cmdFlagDaemon;
}

- (BOOL) cmdIsTesting
{
  return cmdFlagTesting;
}

- (NSDate*) cmdLastIP
{
  return lastIP;
}

- (NSDate*) cmdLastOP
{
  return lastOP;
}

- (void) cmdLogEnd: (NSString*)name
{
  NSFileHandle	*hdl;

  if ([name length] == 0)
    {
      NSLog(@"Attempt to end log with empty filename");
      return;
    }
  name = [name lastPathComponent];
  hdl = [cmdLogMap objectForKey: name];
  if (hdl != nil)
    {
      NSString		*path;
      NSDictionary	*attr;
      NSFileManager	*mgr;

      /*
       * Ensure that all data is written to file.
       */
      fflush(stderr);
      [hdl closeFile];

      /*
       * If the file is empty, remove it, otherwise move to archive directory.
       */
      path = [cmdLogsDir(nil) stringByAppendingPathComponent: name]; 
      mgr = [NSFileManager defaultManager];
      attr = [mgr fileAttributesAtPath: path traverseLink: NO];
      if ([[attr objectForKey: NSFileSize] intValue] == 0)
	{
	  [mgr removeFileAtPath: path handler: nil];
	}
      else
	{
	  NSDate	*when;
	  NSString	*where;

	  when = [NSDate date];
	  where = [when descriptionWithCalendarFormat: @"%Y-%m-%d"
			timeZone: nil locale: nil];
	  if (where != nil)
	    {
	      [self _moveLog: name to: where];
	    }
	}

      /*
       * Unregister filename.
       */
      [cmdLogMap removeObjectForKey: name];
    }
}

- (NSFileHandle*) cmdLogFile: (NSString*)name
{
  NSFileHandle	*hdl;
  NSString	*status = nil;

  if ([name length] == 0)
    {
      NSLog(@"Attempt to log with empty filename");
      return nil;
    }
  name = [name lastPathComponent];
  hdl = [cmdLogMap objectForKey: name];
  if (hdl == nil)
    {
      NSFileManager	*mgr = [NSFileManager defaultManager];
      NSString		*path;

      path = [cmdLogsDir(nil) stringByAppendingPathComponent: name];

      if ([mgr fileExistsAtPath: path] == YES)
	{
	  NSDictionary	*attr;
	  NSDate	*when;
	  NSString	*where;

	  attr = [mgr fileAttributesAtPath: path traverseLink: NO];
	  when = [attr objectForKey: NSFileModificationDate];
	  where = [when descriptionWithCalendarFormat: @"%Y-%m-%d"
			timeZone: nil locale: nil];
	  if (where != nil)
	    {
	      status = [self _moveLog: name to: where];
	    }
	}

      /*
       * Create the file if necessary, and open it for updating.
       */
      if ([mgr isWritableFileAtPath: path] == NO
	&& [mgr createFileAtPath: path contents: nil attributes: nil] == NO)
	{
	  NSLog(@"File '%@' is not writable and can't be created", path);
	}
      else
	{
	  hdl = [NSFileHandle fileHandleForUpdatingAtPath: path];
	  if (hdl == nil)
	    {
	      if (status != nil)
		{
		  NSLog(@"%@", status);
		}
	      NSLog(@"Unable to log to %@", path);
	    }
	  else
	    {
	      [hdl seekToEndOfFile];
	    }
	}
      if (hdl == nil)
	{
	  return nil;
	}
      /*
       * As a special case, if this is the default debug file
       * we must set it up to write to stderr.
       */
      if ([name isEqual: cmdDebugName] == YES)
	{
	  int	desc;

	  desc = [hdl fileDescriptor];
	  if (desc != 2)
	    {
	      dup2(desc, 2);
	      [hdl closeFile];
	      hdl = [NSFileHandle fileHandleWithStandardError];
	    }
	}
      /*
       * Store the file handle in the dictionary for later use.
       */
      [cmdLogMap setObject: hdl forKey: name];
      if (status != nil)
	{
	  NSLog(@"%@", status);
	}
    }
  return hdl;
}

- (void) cmdLostConnectionToServer: (NSString*)name
{
  return;
}

- (void) cmdMadeConnectionToServer: (NSString*)name
{
  return;
}

- (NSString*) cmdName
{
  return cmdName;
}

- (int) cmdSignalled
{
  return cmdSignalled;
}

- (NSDate*) cmdStarted
{
  return started;
}

- (NSArray*) alarms
{
  return [alarmDestination alarms];
}

- (oneway void) alarm: (in bycopy EcAlarm*)event
{
  [alarmDestination alarm: event];
}

- (oneway void) domanage: (in bycopy NSString*)managedObject
{
  [alarmDestination domanage: managedObject];
}

- (oneway void) unmanage: (in bycopy NSString*)managedObject
{
  [alarmDestination unmanage: managedObject];
}

- (void) setCmdInterval: (NSTimeInterval)interval
{
  if (interval > 60.0)
    {
NSLog(@"Ignored attempt to set timer interval to %g ... using 60.0", interval);
      interval = 60.0;
    }
  if (interval < 0.001)
    {
NSLog(@"Ignored attempt to set timer interval to %g ... using 10.0", interval);
      interval = 10.0;
    }
  if (interval != cmdTimInterval)
    {
      cmdTimInterval = interval;
      [self triggerCmdTimeout];
    }
}

- (NSString*) ecCopyright
{
  return @"";
}

- (void) ecDoLock
{
  [ecLock lock];
}

- (void) ecUnLock
{
  [ecLock unlock];
}

+ (void) initialize
{
  if (nil == ecLock)
    {
      ecLock = [NSRecursiveLock new];
      dateClass = [NSDate class];
      cDateClass = [NSCalendarDate class];
      stringClass = [NSString class];
      cmdLogMap = [[NSMutableDictionary alloc] initWithCapacity: 4];

      cmdDebugModes = [[NSMutableSet alloc] initWithCapacity: 4];
      cmdDebugKnown = [[NSMutableDictionary alloc] initWithCapacity: 4];

      [cmdDebugKnown setObject: @"Mode for distributed object connections"
			forKey: cmdConnectDbg];
      [cmdDebugKnown setObject: @"Standard mode for basic debug information"
			forKey: cmdDefaultDbg];
      [cmdDebugKnown setObject: @"Detailed but general purpose debugging"
			forKey: cmdDetailDbg];

      [cmdDebugModes addObject: cmdDefaultDbg];

      /*
       * Set the timeouts for the default connection so that
       * they will be inherited by other connections.
       * A two minute timeout is long enough for almost all
       * circumstances.
       */
      [[NSConnection defaultConnection] setRequestTimeout: 120.0];
      [[NSConnection defaultConnection] setReplyTimeout: 120.0];
    }
}

- (void) addServerToList: (NSString *)serverName
{
  [self addServerToList: serverName for: nil];
}

- (void) addServerToList: (NSString *)serverName for: (id)anObject
{
  RemoteServer	*remote;

  if ((serverName == nil)
    || ([serverName isKindOfClass: [NSString class]] == NO))
    {
      NSLog (@"Warning: invalid string passed to addServerToList:for:");
      return;
    }
  
  if (anObject == nil)
    {
      anObject = self;
    }

  if (servers == nil)
    {
      servers = [[NSMutableDictionary alloc] initWithCapacity: 2];
    }
  
  remote = [[RemoteServer alloc] initWithDefaultName: serverName
					    delegate: anObject];
  [servers setObject: remote forKey: serverName];
  [remote release];
}

- (void) removeServerFromList: (NSString *)serverName
{
  if ((serverName == nil)
    || ([serverName isKindOfClass: [NSString class]] == NO))
    {
      NSLog (@"Warning: invalid array passed to removeServerFromList:");
      return;
    }
  [servers removeObjectForKey: serverName];
}

- (id) cmdConnectionBecameInvalid: (NSNotification*)notification
{
  id connection;

  connection = [notification object];
  [[NSNotificationCenter defaultCenter]
    removeObserver: self
	      name: NSConnectionDidDieNotification
	    object: connection];
  if (cmdServer != nil && connection == [cmdServer connectionForProxy])
    {
      [alarmDestination setDestination: nil];
      DESTROY(cmdServer);
      NSLog(@"lost connection 0x%p to command server\n", connection);
      /*
       *	Cause timeout to go off really soon so we will try to
       *	re-establish the link to the server.
       */
      if (cmdPTimer != nil)
	{
	  [cmdPTimer invalidate];
	  cmdPTimer = nil;
	}
      cmdPTimer = [NSTimer scheduledTimerWithTimeInterval: 0.1
					      target: self
					    selector: @selector(_timedOut:)
					    userInfo: nil
					     repeats: NO];
    }
  else
    {
      NSLog(@"unknown-Connection sent invalidation\n");
    }
  return self;
}

- (void) cmdAlert: (NSString*)fmt arguments: (va_list)args
{
  if (nil == alertLogger)
    {
      alertLogger = [[EcLogger loggerForType: LT_ALERT] retain];
    }
  [alertLogger log: fmt arguments: args];
}

- (void) cmdAlert: (NSString*)fmt, ...
{
  va_list ap;

  va_start (ap, fmt);
  [self cmdAlert: fmt arguments: ap];
  va_end (ap);
}

- (NSString*) cmdArchive: (NSString*)subdir
{
  NSString	*status = @"";

  if ([cmdLogMap count] == 0)
    {
      status = noFiles;
    }
  else
    {
      NSEnumerator	*enumerator = [[cmdLogMap allKeys] objectEnumerator];
      NSString		*name;

      if (subdir == nil)
	{
	  NSCalendarDate	*when = [NSCalendarDate date];
	  int			y, m, d;

	  y = [when yearOfCommonEra];
	  m = [when monthOfYear];
	  d = [when dayOfMonth];
	  
	  subdir = [stringClass stringWithFormat: @"%04d-%02d-%02d", y, m, d];
	}

      while ((name = [enumerator nextObject]) != nil)
	{
	  NSString	*s;

	  s = [self _moveLog: name to: subdir];
	  if ([status length] > 0)
	    status = [status stringByAppendingString: @"\n"];
	  status = [status stringByAppendingString: s];
	  [self cmdLogEnd: name];
	  if (cmdIsQuitting == NO)
	    {
	      [self cmdLogFile: name];
	    }
	}
    }
  return status;
}

- (void) cmdAudit: (NSString*)fmt arguments: (va_list)args
{
  if (nil == auditLogger)
    {
      auditLogger = [[EcLogger loggerForType: LT_AUDIT] retain];
    }
  [auditLogger log: fmt arguments: args];
}

- (void) cmdAudit: (NSString*)fmt, ...
{
  va_list ap;

  va_start (ap, fmt);
  [self cmdAudit: fmt arguments: ap];
  va_end (ap);
}

- (void) cmdDbg: (NSString*)type msg: (NSString*)fmt arguments: (va_list)args
{
  if (nil != [cmdDebugModes member: type])
    {
      if (nil == debugLogger)
	{
	  debugLogger = [[EcLogger loggerForType: LT_DEBUG] retain];
	}
      [debugLogger log: fmt arguments: args];
    }
}

- (void) cmdDbg: (NSString*)type msg: (NSString*)fmt, ...
{
  va_list ap;

  va_start (ap, fmt);
  [self cmdDbg: type msg: fmt arguments: ap];
  va_end (ap);
}

- (void) cmdDebug: (NSString*)fmt arguments: (va_list)args
{
  if (nil != [cmdDebugModes member: cmdDefaultDbg])
    {
      if (nil == debugLogger)
	{
	  debugLogger = [[EcLogger loggerForType: LT_DEBUG] retain];
	}
      [debugLogger log: fmt arguments: args];
    }
}

- (void) cmdDebug: (NSString*)fmt, ...
{
  va_list ap;

  va_start (ap, fmt);
  [self cmdDebug: fmt arguments: ap];
  va_end (ap);
}

- (void) cmdError: (NSString*)fmt arguments: (va_list)args
{
  if (nil == errorLogger)
    {
      errorLogger = [[EcLogger loggerForType: LT_ERROR] retain];
    }
  [errorLogger log: fmt arguments: args];
}

- (void) cmdError: (NSString*)fmt, ...
{
  va_list ap;

  va_start (ap, fmt);
  [self cmdError: fmt arguments: ap];
  va_end (ap);
}

- (void) cmdFlushLogs
{
  [alertLogger flush];
  [auditLogger flush];
  [debugLogger flush];
  [errorLogger flush];
  [warningLogger flush];
}

- (NSTimeInterval) cmdInterval
{
  return cmdTimInterval;
}

- (BOOL) cmdIsClient
{
  return YES;
}

- (void) log: (NSString*)message type: (EcLogType)t
{
  switch (t)
    {
      case LT_DEBUG:
	[self cmdDebug: @"%@", message];
	break;
      case LT_WARNING:
	[self cmdWarn: @"%@", message];
	break;
      case LT_ERROR:
	[self cmdError: @"%@", message];
	break;
      case LT_ALERT:
	[self cmdAlert: @"%@", message];
	break;
      case LT_AUDIT:
	[self cmdAudit: @"%@", message];
	break;
      default:
	[self cmdError: @"%@", message];
	break;
    }
}

- (NSMutableDictionary*) cmdOperator: (NSString*)name password: (NSString*)pass
{
  NSMutableDictionary	*d = (NSMutableDictionary*)cmdOperators;

  if (d == nil || [d isKindOfClass: [NSDictionary class]] == NO)
    {
      return nil;
    }
  d = [d objectForKey: name];
  if (d == nil || [d isKindOfClass: [NSDictionary class]] == NO)
    {
      return nil;
    }
  d = [d mutableCopy];
  if (pass != nil && [[d objectForKey: @"Password"] isEqual: pass] == YES)
    {
      [d setObject: @"yes" forKey: @"Password"];
    }
  else
    {
      [d setObject: @"no" forKey: @"Password"];
    }
  return AUTORELEASE(d);
}

- (id) cmdNewServer
{
  static BOOL connecting = NO;

  if (NO == connecting)
    {
      /*
       * Use the 'cmdLast' variable to ensure that we don't try to
       * check memory usage or connect to the command server more
       * than once every 10 sec.
       */
      if (cmdLast == nil || [cmdLast timeIntervalSinceNow] < -10.0)
	{
	  connecting = YES;

	  ASSIGN(cmdLast, [dateClass date]);
	  if (cmdFirst == nil)
	    {
	      ASSIGN(cmdFirst, cmdLast);
	    }

	  if (cmdServer == nil && YES == [self cmdIsClient])
	    {
	      NSString	*name = nil;
	      NSString	*host = nil;
	      id	proxy;

	      NS_DURING
		{
		  host = ecCommandHost();
		  name = ecCommandName();

		  proxy = [NSConnection
		    rootProxyForConnectionWithRegisteredName: name
							host: host
		    usingNameServer: [NSSocketPortNameServer sharedInstance]];
		}
	      NS_HANDLER
		{
		  proxy = nil;
		  NSLog(@"Exception connecting to Command server %@ on %@): %@",
		    name, host, localException);
		}
	      NS_ENDHANDLER

	      if (proxy != nil)
		{
		  NSMutableDictionary	*r = nil;
		  
		  [proxy setProtocolForProxy: @protocol(Command)];

		  NS_DURING
		    {
		      NSData	*d;

		      d = [proxy registerClient: self
					   name: cmdLogName()
				      transient: cmdIsTransient];
		      r = [NSPropertyListSerialization
			propertyListWithData: d
			options: NSPropertyListMutableContainers
			format: 0
			error: 0];
		    }
		  NS_HANDLER
		    {
		      r = [NSMutableDictionary dictionaryWithCapacity: 1];
		      [r setObject: [localException reason]
			    forKey: @"rejected"];
		      NSLog(@"Caught exception registering with Command: %@",
			localException);
		    }
		  NS_ENDHANDLER

		  /* We could be rejected or told to back off,
		   * otherwise we continue as normal.
		   */
		  if (r != nil && [r objectForKey: @"rejected"] != nil)
		    {
		      NSLog(@"Rejected by Command - %@",
			[r objectForKey: @"rejected"]);
		      [self cmdQuit: 0];	/* Rejected by server.	*/
		    }
		  else if (nil == r || nil == [r objectForKey: @"back-off"])
		    {
		      NSConnection	*connection;

		      cmdServer = [proxy retain];
		      connection = [cmdServer connectionForProxy];
		      [connection enableMultipleThreads];
		      if (nil == alarmDestination)
			{
			  alarmDestination = [EcAlarmDestination new];
			}
		      [alarmDestination setDestination: cmdServer];
		      [[NSNotificationCenter defaultCenter]
			addObserver: self
			   selector: @selector(cmdConnectionBecameInvalid:)
			       name: NSConnectionDidDieNotification
			     object: connection];
		      [self _update: r];
		    }
		}
	    }
	  connecting = NO;
	}
      else if (cmdServer == nil && YES == [self cmdIsClient])
	{
	  NSLog(@"Unable to connect to Command server ... not retry time yet");
	}
    }

  return cmdServer;
}

- (void) cmdUnregister
{
  if (nil != cmdServer)
    {
      NS_DURING
	{
	  [cmdServer unregisterByObject: self];
	}
      NS_HANDLER
	{
	  DESTROY(cmdServer);
	  NSLog(@"Caught exception unregistering from Command: %@",
	    localException);
	}
      NS_ENDHANDLER
      DESTROY(cmdServer);
    }
}

- (void) cmdWarn: (NSString*)fmt arguments: (va_list)args
{
  if (nil == warningLogger)
    {
      warningLogger = [[EcLogger loggerForType: LT_WARNING] retain];
    }
  [warningLogger log: fmt arguments: args];
}

- (void) cmdWarn: (NSString*)fmt, ...
{
  va_list ap;

  va_start (ap, fmt);
  [self cmdWarn: fmt arguments: ap];
  va_end (ap);
}

- (void) ecNewDay: (NSCalendarDate*)when
{
  NSString		*sub;

  /* New day ... archive debug/log files into a subdirectory based on
   * the current date.  This is yesterday's debug, so we use yesterday.
   */
  sub = [[when dateByAddingYears: 0 months: 0 days: -1 hours: 0 minutes: 0
    seconds: 0] descriptionWithCalendarFormat: @"%Y-%m-%d"];
  NSLog(@"%@", [self cmdArchive: sub]);
}

- (void) ecNewHour: (NSCalendarDate*)when
{
  return;
}

- (void) ecNewMinute: (NSCalendarDate*)when
{
  struct mallinfo	info;

  info = mallinfo();
  if (memSlot >= memSize)
    {
      NSUInteger	average;
      NSUInteger	notLeaked;
      int		i;

      notLeaked = [self ecNotLeaked];

      /* Next slot to record in will be zero.
       */
      memSlot = 0;

      /* Find the average usage over the last set of samples.
       * Round up to a block size.
       */
      for (average = i = 0; i < memSize; i++)
	{
	  average += memRoll[i];
	}
      average /= memSize;

      /* The cache size should probably be less than the heap usage 
       * though some objects in the cache could actually be using
       * memory which didn't come from the heap, so subtracting one
       * from the other is not completely reliable.
       */
      average = (notLeaked < average) ? average - notLeaked : 0;

      /* Convert to 1KB blocks.
       */
      average = ((average / 1024) + 1) * 1024;
      if (average > memPeak)
	{
	  /* Alert if the we have peaked above the allowed size.
	   */
	  if (average > (memAllowed * 1024 * 1024))
	    {
	      [self cmdError: @"Average memory usage grown to %"PRIuPTR"KB",
		average / 1024];
	    }

	  /* Set the peak memory from the last set of readings.
	   */
	  memLast = memPeak;
	  for (i = 0; i < memSize; i++)
	    {
	      unsigned	size = memRoll[i];

	      size = (notLeaked < size) ? size - notLeaked : 0;
	      if (size > memPeak)
		{
		  memPeak = size;
		}
	    }
	  if (YES == [cmdDefs boolForKey: @"Memory"])
	    {
	      /* We want detailed memory information, so we set the next
	       * alerting threshold from 20 to 40 KB above the current
	       * peak usage.
	       */
	      memPeak = ((memPeak / (20 * 1024)) + 2) * (20 * 1024);
	    }
	  else
	    {
	      /* We do not want detailed memory information,
	       * so we set the next alerting threshold from
	       * 500 to 1000 KB above the current peak usage,
	       * ensuring that only serious increases
	       * in usage will generate an alert.
	       */
	      memPeak = ((memPeak / (500 * 1024)) + 2) * (500 * 1024);
	    }
	}
    }
  /* Record the latest memory usage.
   */
  memRoll[memSlot] = info.uordblks;
  if (YES == [cmdDefs boolForKey: @"Memory"])
    {
      [self cmdDbg: cmdDetailDbg
	       msg: @"Memory usage %u", memRoll[memSlot]];
    }
  memSlot++;

  return;
}

- (void) ecHadIP: (NSDate*)when
{
  if (when == nil)
    {
      when = [dateClass date];
    }
  ASSIGN(lastIP, when);
}

- (void) ecHadOP: (NSDate*)when
{
  if (when == nil)
    {
      when = [dateClass date];
    }
  ASSIGN(lastOP, when);
}

- (NSUInteger) ecNotLeaked
{
  return 0;
}

- (int) ecRun
{
  NSAutoreleasePool     *arp;
  NSConnection          *c;
  NSRunLoop             *loop;

  arp = [NSAutoreleasePool new];
  if (YES == cmdIsTransient)
    {
      [self cmdWarn: @"Attempted to run transient  process."];
      [self cmdFlushLogs];
      [arp release];
      return 1;
    }

  NSAssert(nil == EcProcConnection, NSGenericException);
  c = [[NSConnection alloc] initWithReceivePort: (NSPort*)[NSSocketPort port]
                                       sendPort: nil];
  [c setRootObject: self];
  
  if ([c registerName: [self cmdName]
       withNameServer: [NSSocketPortNameServer sharedInstance]] == NO)
    {
      DESTROY(c);
      [self cmdError: @"Unable to register with name server."];
      [self cmdFlushLogs];
      [arp release];
      return 2;
    }

  [c setDelegate: self];
  [[NSNotificationCenter defaultCenter] 
    addObserver: self
    selector: @selector(connectionBecameInvalid:)
    name: NSConnectionDidDieNotification
    object: c];
  EcProcConnection = c;
  
  [self cmdAudit: @"Started `%@'", [self cmdName]];
  
  loop = [NSRunLoop currentRunLoop];
  while (YES == [EcProcConnection isValid])
    {
      NS_DURING
	{
          NSDate        *d = [loop limitDateForMode: NSDefaultRunLoopMode];

	  if (0 == cmdSignalled)
            {
              [loop acceptInputForMode: NSDefaultRunLoopMode beforeDate: d];
            }
	  if (0 != cmdSignalled)
	    {
              int       sig = cmdSignalled;

              cmdSignalled = 0;
	      [self cmdQuit: sig];
	    }
	}
      NS_HANDLER
	{
	  [self cmdAlert: @"Problem running server: %@", localException];
	}
      NS_ENDHANDLER;
      [arp emptyPool];
    }

  [arp release];

  /* finish server */

  [self cmdQuit: 0];
  DESTROY(EcProcConnection);
  return 0;
}

- (void) setCmdDebug: (NSString*)mode withDescription: (NSString*)desc
{
  [cmdDebugKnown setObject: desc forKey: mode];
}

- (void) setCmdTimeout: (SEL)sel
{
  cmdTimSelector = sel;
  [self triggerCmdTimeout];
}

- (void) triggerCmdTimeout
{
  if (cmdPTimer != nil)
    {
      /*
       * If the timer is due to go off soon - don't reset it -
       * continually resetting could lead to it never firing.
       */
      if ([[cmdPTimer fireDate] timeIntervalSinceNow] <= 0.01)
	{
	  return;
	}
      [cmdPTimer invalidate];
      cmdPTimer = nil;
    }
  cmdPTimer = [NSTimer scheduledTimerWithTimeInterval: 0.001
					       target: self
					     selector: @selector(_timedOut:)
					     userInfo: nil
					      repeats: NO];
}

- (BOOL) cmdDebugMode: (NSString*)mode
{
  if ([cmdDebugModes member: mode] == nil)
    return NO;
  return YES;
}

- (void) cmdDebugMode: (NSString*)mode active: (BOOL)flag
{
  if ((mode = findMode(cmdDebugKnown, mode)) != nil)
    {
      if (flag == YES && [cmdDebugModes member: mode] == nil)
	{
	  [cmdDebugModes addObject: mode];
	}
      if (flag == NO && [cmdDebugModes member: mode] != nil)
	{
	  [cmdDebugModes removeObject: mode];
	}
    }
}

- (void) cmdGnip: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  [self cmdDbg: cmdConnectDbg msg: @"cmdGnip: %lx sequence: %u extra: %lx",
    (unsigned long)from, num, (unsigned long)data];
}

- (BOOL) cmdIsConnected
{
  return cmdServer != nil;
}

- (BOOL) cmdMatch: (NSString*)val toKey: (NSString*)key
{
  unsigned int	len = [val length];

  if (len == 0)
    {
      return NO;
    }
  if (len > [key length])
    {
      return NO;
    }
  if ([key compare: val
	   options: NSCaseInsensitiveSearch|NSLiteralSearch
	     range: NSMakeRange(0, len)] != NSOrderedSame)
    {
      return NO;
    }
  return YES;
}

- (void) cmdMesgCache
{
  NSEnumerator  *enumerator;
  NSString      *name;

  /* The cmdActions set contains the names of all the commands this
   * instance will accept from the Command server.  These are methods
   * taking an array of strings as an argument and returning a string
   * as their result.  All have names of the form cmdMesgXXX: where
   * XXX is the (lowercase) command.
   */
  [ecLock lock];
  if (nil == cmdActions)
    {
      cmdActions = [NSMutableSet new];
    }
  [cmdActions removeAllObjects];
  enumerator = [GSObjCMethodNames(self, YES) objectEnumerator];
  while (nil != (name = [enumerator nextObject]))
    {
      NSRange	r = [name rangeOfString: @":"];

      if ([name hasPrefix: @"cmdMesg"] && 1 == r.length && r.location > 7)
        {
          name = [name substringWithRange: NSMakeRange(7, r.location - 7)];
          if (YES == [name isEqual: [name lowercaseString]])
            {
              [cmdActions addObject: name];
            }
        }
    }
  [ecLock unlock];
}

- (NSString*) cmdMesg: (NSArray*)msg
{
  NSMutableString	*saved;
  NSString		*result;
  NSString		*cmd;
  SEL			sel;

  if (msg == nil || [msg count] < 1)
    {
      return @"no command specified\n";
    }

  cmd = findAction([msg objectAtIndex: 0]);
  if (nil == cmd)
    {
      return @"unrecognised command\n";
    }

  sel = NSSelectorFromString([NSString stringWithFormat: @"cmdMesg%@:", cmd]);

  saved = replyBuffer;
  replyBuffer = [NSMutableString stringWithCapacity: 50000];

  NS_DURING
    {
      [self performSelector: sel withObject: msg];
    }
  NS_HANDLER
    {
      [self cmdPrintf: @"\n%@ during command\n", localException];
    }
  NS_ENDHANDLER

  result = replyBuffer;
  replyBuffer = saved;
  return result;
}

/*
 *	Name -		cmdMesgData: from: 
 *	Purpose -	Invoke other methods to handle commands.
 */
- (void) cmdMesgData: (NSData*)dat from: (NSString*)name
{
  NSArray		*msg;
  NSString		*val;

  msg = [NSPropertyListSerialization
    propertyListWithData: dat
    options: NSPropertyListMutableContainers
    format: 0
    error: 0];
  val = [self cmdMesg: msg];
  if (cmdServer)
    {
      NS_DURING
	{
	  [cmdServer reply: val to: name from: cmdLogName()];
	}
      NS_HANDLER
	{
	  cmdServer = nil;
	  NSLog(@"Caught exception sending client reply to Command: %@ %@",
	    name, localException);
	}
      NS_ENDHANDLER
    }
}

- (void) cmdMesgalarms: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"reports current alarms"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] isEqualToString: @"help"])
	{
	  [self cmdPrintf: @"\nThe alarms command is used to report the"];
	  [self cmdPrintf: @" alarms currently active for this process.\n"];
	  [self cmdPrintf: @"NB. Each individual process identifies current"];
	  [self cmdPrintf: @" alarms by address within the process.\n"];
	  [self cmdPrintf: @"This differs from the Control server which"];
	  [self cmdPrintf: @" uses a unique notification ID intended\n"];
	  [self cmdPrintf: @"for working with external SNMP systems.\n"];
	}
      else
	{
	  NSArray	*a = [alarmDestination alarms];
          

	  if (0 == [a count])
	    {
              [self cmdPrintf: @"No alarms currently active.\n"];
	    }
	  else
	    {
	      int	i;

	      a = [a sortedArrayUsingSelector: @selector(compare:)];
	      [self cmdPrintf: @"Current alarms -\n"];
	      for (i = 0; i < [a count]; i++)
		{
		  EcAlarm	*alarm = [a objectAtIndex: i];

		  [self cmdPrintf: @"%@\n", [alarm description]];
		}
	    }
	}
    }
}

- (void) cmdMesgarchive: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"archives log files"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame)
	{
	  [self cmdPrintf: @"\nThe archive command is used to archive the"];
	  [self cmdPrintf: @" debug file to a subdirectory.\n"];
	  [self cmdPrintf: @"You should not need it - as archiving should"];
	  [self cmdPrintf: @"be done automatically at midnight.\n"];
	}
      else
	{
	  [self cmdPrintf: @"\n%@\n", [self cmdArchive: nil]];
	}
    }
}

- (void) cmdMesgclear: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"clears current alarms"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] isEqualToString: @"help"])
	{
	  [self cmdPrintf: @"\nThe clear command is used to clear the"];
	  [self cmdPrintf: @" alarms currently active for this process.\n"];
	  [self cmdPrintf: @"You may use the word 'all' or a space separated"];
	  [self cmdPrintf: @" list of alarm addresses.\n"];
	  [self cmdPrintf: @"NB. Each individual process identifies current"];
	  [self cmdPrintf: @" alarms by address within the process.\n"];
	  [self cmdPrintf: @"This differs from the Control server which"];
	  [self cmdPrintf: @" uses a unique notification ID intended\n"];
	  [self cmdPrintf: @"for working with external SNMP systems.\n"];
	}
      else
	{
	  NSArray	*a = [alarmDestination alarms];
          NSUInteger    count = [msg count];

          if (count < 2)
            {
	      [self cmdPrintf: @"The 'clear' command requires an alarm"
                @" notificationID or the word all\n"];
            }
          else
            {
              NSUInteger        alarmCount = [a count];
              EcAlarm	        *alarm;
              NSUInteger        index;

              for (index = 1; index < count; index++)
                {
                  uint64_t      addr;
                  NSString      *arg = [msg objectAtIndex: index];

                  if ([arg caseInsensitiveCompare: _(@"all")]
                    == NSOrderedSame)
                    {
                      NSUInteger        i;

                      for (i = 0; i < alarmCount; i++)
                        {
                          alarm = [a objectAtIndex: i];
                          [self cmdPrintf: @"Clearing %@\n", alarm];
                          alarm = [alarm clear];
                          [alarmDestination alarm: alarm];
                        }
                    }
                  else if (1 == sscanf([arg UTF8String], "%" PRIx64, &addr))
                    {
                      NSUInteger	i;

                      alarm = nil;
                      for (i = 0; i < alarmCount; i++)
                        {
                          alarm = [a objectAtIndex: i];
                          if ((uint64_t)(uintptr_t)alarm == addr)
                            {
                              break;
                            }
                          alarm = nil;
                        }
                      if (nil == alarm)
                        {
                          [self cmdPrintf:
                            @"No alarm found with the address '%@'\n",
                            arg];
                        }
                      else
                        {
                          [self cmdPrintf: @"Clearing %@\n", alarm];
                          alarm = [alarm clear];
                          [alarmDestination alarm: alarm];
                        }
                    }
                  else
                    {
                      [self cmdPrintf: @"Not a hexadecimal address: '%@'\n",
                        arg];
                    }
                }
            }
	}
    }
}

- (void) cmdMesgdebug: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"turns on debug logging"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame)
	{
	  [self cmdPrintf: @"\nWithout parameters, the debug command is "];
	  [self cmdPrintf: @"used to list the currently active "];
	  [self cmdPrintf: @"debug modes.\n"];
	  [self cmdPrintf: @"With the single parameter 'default', the debug "];
	  [self cmdPrintf: @"command is used to revert to default "];
	  [self cmdPrintf: @"debug settings.\n"];
	  [self cmdPrintf: @"With the single parameter 'all', the debug "];
	  [self cmdPrintf: @"command is used to activate all "];
	  [self cmdPrintf: @"debugging.\n"];
	  [self cmdPrintf: @"With any other parameter, the debug command "];
	  [self cmdPrintf: @"is used to activate one of the "];
	  [self cmdPrintf: @"debug modes listed below.\n\n"];

	  [self cmdPrintf: @"%@\n", cmdDebugKnown];
	}
      else if ([msg count] > 1)
	{
	  NSString	*mode = (NSString*)[msg objectAtIndex: 1];
	  NSString	*key;

          if ([mode caseInsensitiveCompare: @"default"] == NSOrderedSame)
            {
	      NSEnumerator	*enumerator = [cmdDebugKnown keyEnumerator];

	      while (nil != (mode = [enumerator nextObject]))
		{
		  key = [@"Debug-" stringByAppendingString: mode];
		  [cmdDefs setCommand: nil forKey: key];
		}
	      [self cmdPrintf: @"Now using debug settings from config.\n"];
            }
          else if ([mode caseInsensitiveCompare: @"all"] == NSOrderedSame)
	    {
	      NSEnumerator	*enumerator = [cmdDebugKnown keyEnumerator];

	      while (nil != (mode = [enumerator nextObject]))
		{
		  key = [@"Debug-" stringByAppendingString: mode];
		  [cmdDefs setCommand: @"YES" forKey: key];
		}
	      [self cmdPrintf: @"All debugging is now active.\n"];
	    }
          else
            {
	      [self cmdPrintf: @"debug mode '"];
	      if ((mode = findMode(cmdDebugKnown, mode)) == nil)
		{
		  [self cmdPrintf: @"%@' is not known.\n", mode];
		}
	      else
		{
		  [self cmdPrintf: @"%@", mode];
		  if ([cmdDebugModes member: mode] == nil)
		    {
		      [self cmdPrintf: @"' is now active."];
		    }
		  else
		    {
		      [self cmdPrintf: @"' is already active."];
		    }
		  key = [@"Debug-" stringByAppendingString: mode];
		  [cmdDefs setCommand: @"YES" forKey: key];
		}
	    }
	}
      else
	{
	  [self cmdPrintf: @"%@\n", [EcLogger loggerForType: LT_DEBUG]];
	  [self cmdPrintf: @"Current active debug modes -\n"];
	  if ([cmdDebugModes count] == 0)
	    {
	      [self cmdPrintf: @"\nNone.\n"];
	    }
	  else
	    {
	      [self cmdPrintf: @"%@\n", cmdDebugModes];
	    }
	}
    }
}

- (void) cmdMesghelp: (NSArray*)msg
{
  NSEnumerator	*e;
  NSString	*cmd;
  SEL		sel;

  [ecLock lock];
  e = [cmdActions objectEnumerator];
  [ecLock unlock];
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"provides helpful information :-)"];
      return;
    }
  else if ([msg count] > 1)
    {
      NSString	*found;

      cmd = [msg objectAtIndex: 1];
      found = findAction(cmd);

      if ([cmd caseInsensitiveCompare: @"control"] == NSOrderedSame)
	{
	  [self cmdPrintf: @"Detailed help on the 'control' command -\n"];
	  [self cmdPrintf: @"This command enables you to send an"];
	  [self cmdPrintf: @"instruction to the 'Control' server rather\n"];
	  [self cmdPrintf: @"than to the currently connected server.\n"];
	  [self cmdPrintf: @"Everything typed on the line after the word"];
	  [self cmdPrintf: @" 'control' is treated as a command to\n"];
	  [self cmdPrintf: @"the 'Control' server process.\n"];
	  [self cmdPrintf: @"\nTo disconnect from the server type -\n"];
	  [self cmdPrintf: @"  control connect\n"];
	  [self cmdPrintf: @"\nTo disconnect from the host type -\n"];
	  [self cmdPrintf: @"  control host\n"];
	  return;
	}
      else if (nil == found)
	{
	  [self cmdPrintf: @"Unable to find the '%@' command -\n", cmd];
	}
      else if ([found caseInsensitiveCompare: @"help"] != NSOrderedSame)
	{
	  NSMutableArray	*m;

	  [self cmdPrintf: @"Detailed help on the '%@' command -\n", found];
	  sel = NSSelectorFromString(
	    [NSString stringWithFormat: @"cmdMesg%@:", found]);
      
	  /* To get the help on a command, we invoke that command
	   * by passing the command and arguments (ie, the msg array).
	   * The command implementation should check the argument 0 -
	   * if it is "help", it should print out help on itself.
	   * Save expanded (unabbreviated) commands so the methods
	   * getting the help request don't need to recheck the values.
	   */
	  m = [[msg mutableCopy] autorelease];
	  [m replaceObjectAtIndex: 0 withObject: @"help"];
	  [m replaceObjectAtIndex: 1 withObject: found];

	  [self performSelector: sel  withObject: m];
	  return;
	}
    }
 
  [self cmdPrintf: @"\n"];
  [self cmdPrintf: @"For help on a particular command, type 'help <cmd>'\n"];
  [self cmdPrintf: @"\n"];
  [self cmdPrintf: @"These are the commands available to you -\n"];
  [self cmdPrintf: @"\n"];
  while ((cmd = [e nextObject]) != nil)
    {
      unsigned l;

      sel = NSSelectorFromString(
	[NSString stringWithFormat: @"cmdMesg%@:", cmd]);
      [self cmdPrintf: @"%@ - ", cmd];
      l = [cmd length];
      while (l++ < 9)
	{
	  [self cmdPrintf: @" "];
	}
      [self performSelector: sel withObject: nil];
      [self cmdPrintf: @"\n"];
    }
}

- (void) cmdMesgnodebug: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"turns off debug logging"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame)
	{
	  [self cmdPrintf: @"\n"];
	  [self cmdPrintf: @"Without parameters, the nodebug command is "];
	  [self cmdPrintf: @"used to list the currently inactive\n"];
	  [self cmdPrintf: @"debug modes.\n"];
	  [self cmdPrintf: @"With the single parameter 'all', the nodebug "];
	  [self cmdPrintf: @"command is used to deactivate all\n"];
	  [self cmdPrintf: @"debugging.\n"];
	  [self cmdPrintf: @"With the single parameter 'default', the "];
	  [self cmdPrintf: @"nodebug command is used to revert to default "];
	  [self cmdPrintf: @"debug settings.\n"];
	  [self cmdPrintf: @"With any other parameter, the nodebug command is"];
	  [self cmdPrintf: @" used to deactivate one of the\n"];
	  [self cmdPrintf: @"debug modes listed below.\n"];
	  [self cmdPrintf: @"\n"];
	  [self cmdPrintf: @"%@\n", cmdDebugKnown];
	}
      else if ([msg count] > 1)
	{
	  NSString	*mode = (NSString*)[msg objectAtIndex: 1];
	  NSString	*key;

          if ([mode caseInsensitiveCompare: @"default"] == NSOrderedSame)
            {
	      NSEnumerator	*enumerator = [cmdDebugKnown keyEnumerator];

	      while (nil != (mode = [enumerator nextObject]))
		{
		  key = [@"Debug-" stringByAppendingString: mode];
		  [cmdDefs setCommand: nil forKey: key];
		}
	      [self cmdPrintf: @"Now using debug settings from config.\n"];
            }
          else if ([mode caseInsensitiveCompare: @"all"] == NSOrderedSame)
	    {
	      NSEnumerator	*enumerator = [cmdDebugKnown keyEnumerator];

	      while (nil != (mode = [enumerator nextObject]))
		{
		  key = [@"Debug-" stringByAppendingString: mode];
		  [cmdDefs setCommand: @"NO" forKey: key];
		}
	      [self cmdPrintf: @"All debugging is now inactive.\n"];
	    }
	  else
	    {
	      [self cmdPrintf: @"debug mode '"];
	      if ((mode = findMode(cmdDebugKnown, mode)) == nil)
		{
		  [self cmdPrintf: @"%@' is not known.\n", mode];
		}
	      else
		{
		  [self cmdPrintf: @"%@' is ", mode];
		  if ([cmdDebugModes member: mode] == nil)
		    {
		      [self cmdPrintf: @"already inactive.\n"];
		    }
		  else
		    {
		      [self cmdPrintf: @"now deactivated.\n"];
		    }
		  key = [@"Debug-" stringByAppendingString: mode];
		  [cmdDefs setCommand: @"NO" forKey: key];
		}
	    }
	}
      else
	{
	  NSArray	*a = [cmdDebugKnown allKeys];
	  NSMutableSet	*s = [NSMutableSet setWithArray: a];

	  /*
	   * Find items known but not active.
	   */
	  [s minusSet: cmdDebugModes];
	  [self cmdPrintf: @"Current inactive debug modes -\n"];
	  if (a == 0)
	    {
	      [self cmdPrintf: @"none.\n"];
	    }
	  else
	    {
	      [self cmdPrintf: @"%@\n", s];
	    }
	}
    }
}

- (void) cmdMesgmemory: (NSArray*)msg
{
  if ([msg count] == 0
    || [[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
    == NSOrderedSame)
    {
      [self cmdPrintf: @"controls recording of memory management statistics"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame)
	{
	  [self cmdPrintf: @"\n"];
	  [self cmdPrintf: @"Without parameters, the memory command is "];
	  [self cmdPrintf: @"used to list the changes in the numbers of "];
	  [self cmdPrintf: @"objects allocated since the command was "];
	  [self cmdPrintf: @"last issued.\n"];
	  [self cmdPrintf: @"With the single parameter 'all', the memory "];
	  [self cmdPrintf: @"command is used to list the cumulative totals "];
	  [self cmdPrintf: @"of objects allocated since the first time a "];
	  [self cmdPrintf: @"memory command was issued.\n"];
	  [self cmdPrintf: @"With the single parameter 'yes', the memory "];
	  [self cmdPrintf: @"command is used to turn on gathering of "];
	  [self cmdPrintf: @"memory usage statistics.\n"];
	  [self cmdPrintf: @"With the single parameter 'no', the memory "];
	  [self cmdPrintf: @"command is used to turn off gathering of "];
	  [self cmdPrintf: @"memory usage statistics.\n"];
	  [self cmdPrintf: @"With the single parameter 'default', the "];
	  [self cmdPrintf: @"gathering of memory usage statistics reverts "];
	  [self cmdPrintf: @"to the default setting."];
	  [self cmdPrintf: @"\n"];
	}
      else if ([msg count] > 1)
	{
	  NSString	*word = [msg objectAtIndex: 1];

	  if ([word caseInsensitiveCompare: @"default"] == NSOrderedSame)
	    {
	      [cmdDefs setCommand: nil forKey: @"Memory"];
	      [self cmdPrintf: @"Memory checking: %s\n",
		[cmdDefs boolForKey: @"Memory"] ? "YES" : "NO"];
	    }
	  else if ([word caseInsensitiveCompare: @"all"] == NSOrderedSame)
	    {
	      if (NO == [cmdDefs boolForKey: @"Memory"])
		{
		  [self cmdPrintf:
		    @"Memory statistics were not being gathered.\n"];
		  [self cmdPrintf: @"Memory statistics Will start from NOW.\n"];
		}
	      else
		{
		  const char*	list;

		  list = (const char*)GSDebugAllocationList(NO);
		  [self cmdPrintf: @"%s", list];
		}
	      [cmdDefs setCommand: @"YES" forKey: @"Memory"];
	    }
	  else if ([word boolValue] == YES)
	    {
	      if (NO == [cmdDefs boolForKey: @"Memory"])
		{
		  [self cmdPrintf:
		    @"Memory statistics were not being gathered.\n"];
		  [self cmdPrintf: @"Statistics Will start from NOW.\n"];
		}
	      else
		{
		  [self cmdPrintf:
		    @"Memory statistics are already being gathered.\n"];
		}
	      [cmdDefs setCommand: @"YES" forKey: @"Memory"];
	    }
	  else
	    {
	      if (NO == [cmdDefs boolForKey: @"Memory"])
		{
		  [self cmdPrintf:
		    @"Memory statistics were not being gathered.\n"];
		}
	      [self cmdPrintf: @"Memory statistics are turned off NOW.\n"];
	      [cmdDefs setCommand: @"NO" forKey: @"Memory"];
	    }
	}
      else
	{
	  [self cmdPrintf: @"\n%@ on %@ running since %@\n\n",
	    cmdLogName(), ecHostName(), [self cmdStarted]];

	  if (NO == [cmdDefs boolForKey: @"Memory"])
	    {
	      [self cmdPrintf: @"Memory stats are not being gathered.\n"];
	    }
	  else
	    {
	      const char*	list;

	      list = (const char*)GSDebugAllocationList(YES);
	      [self cmdPrintf: @"%s", list];
	    }
	}
    }
}

- (void) cmdMesgstatus: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"provides server status information"];
    }
  else
    {
      [self cmdPrintf: @"\n%@ on %@ running since %@\n",
	cmdLogName(), ecHostName(), [self cmdStarted]];
      if ([self cmdLastIP] != nil)
	{
	  [self cmdPrintf: @"Last IP at %@\n", [self cmdLastIP]];
	}
      if ([self cmdLastOP] != nil)
	{
	  [self cmdPrintf: @"Last OP at %@\n", [self cmdLastOP]];
	}
      if (servers != nil)
	{
	  NSEnumerator *e;
	  RemoteServer *server;
	  
	  e = [servers objectEnumerator];
	  while ((server = (RemoteServer *)[e nextObject]) != 0) 
	    {
	      [self cmdPrintf: @"%@\n", server];
	    }
	}

      if (YES == [cmdDefs boolForKey: @"Memory"])
	{
	  [self cmdPrintf: @"Memory usage: %u (peak), %u (current)\n",
	    memPeak, memLast];
	}
    }
}


- (void) cmdPing: (id <CmdPing>)from
	sequence: (unsigned)num
	   extra: (NSData*)data
{
  [self cmdDbg: cmdConnectDbg msg: @"cmdPing: %lx sequence: %u extra: %lx",
    (unsigned long)from, num, (unsigned long)data];
  [from cmdGnip: self sequence: num extra: nil];
}

- (void) cmdPrintf: (NSString*)fmt arguments: (va_list)args
{
  NSString	*tmp;

  tmp = [[stringClass alloc] initWithFormat: fmt arguments: args];
  [replyBuffer appendString: tmp];
  [tmp release];
}

- (void) cmdPrintf: (NSString*)fmt, ...
{
  va_list	ap;

  va_start(ap, fmt);
  [self cmdPrintf: fmt arguments: ap];
  va_end(ap);
}

- (void) cmdQuit: (NSInteger)status
{
  cmdIsQuitting = YES;

  if (cmdPTimer != nil)
    {
      [cmdPTimer invalidate];
      cmdPTimer = nil;
    }

  [alarmDestination shutdown];

  [self cmdFlushLogs];

  [self cmdUnregister];

  [alarmDestination shutdown];
  [alarmDestination release];

  [EcProcConnection invalidate];

    {
      NSArray	*keys;
      unsigned	index;

      /*
       * Close down all log files.
       */
      keys = [cmdLogMap allKeys];
      for (index = 0; index < [keys count]; index++)
	{
	  [self cmdLogEnd: [keys objectAtIndex: index]];
	}
    }

  exit(status);
}

- (void) cmdUpdate: (NSMutableDictionary*)info
{
  BOOL  defaultsChanged;

  if (nil == info)
    {
      defaultsChanged = NO;
    }
  else
    {
      ASSIGNCOPY(cmdConf, info);
      defaultsChanged = [cmdDefs setConfiguration: cmdConf];
    }
  /* If the defaults did not actually change,
   * trigger an update anyway.
   */
  if (NO == defaultsChanged)
    {
      [self cmdDefaultsChanged: nil];
    }
}

- (void) cmdUpdated
{
  return;
}


- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [ecLock lock];
  if (self == EcProc)
    {
      EcProc = nil;
    }
  [ecLock unlock];
  [super dealloc];
}

- (NSString*) description
{
  return [stringClass stringWithFormat: @"%@ (%@) on %@",
    [super description], cmdLogName(), ecHostName()];
}

- (id) init
{
  id		objects[2];
  id		keys[2];
  NSString	*prefix;

  objects[0] = [[NSProcessInfo processInfo] processName];
  objects[1] = @".";
  prefix = EC_DEFAULTS_PREFIX;
  if (nil == prefix)
    {
      prefix = @"";
    }
  keys[0] = [prefix stringByAppendingString: @"ProgramName"];
  keys[1] = [prefix stringByAppendingString: @"HomeDirectory"];

  return [self initWithDefaults: [NSDictionary dictionaryWithObjects: objects
							     forKeys: keys
							       count: 2]];
}

- (id) initWithDefaults: (NSDictionary*) defs
{
  [ecLock lock];
  if (nil != EcProc)
    {
      [self release];
      [ecLock unlock];
      [NSException raise: NSGenericException
		  format: @"EcProcess initialiser called more than once"];
    }
  if (nil == (self = [super init]))
    {
      [ecLock unlock];
      return nil;
    }
  else
    {
      struct rlimit	rlim;
      NSProcessInfo	*pinfo;
      NSFileManager	*mgr;
      NSEnumerator	*enumerator;
      NSString		*str;
      NSString		*dbg;
      NSString		*prf;
      BOOL		flag;
      NSInteger		i;

      EcProc = self;

      pinfo = [NSProcessInfo processInfo];
      mgr = [NSFileManager defaultManager];
      prf = EC_DEFAULTS_PREFIX;
      if (nil == prf)
	{
	  prf = @"";
	}

      ASSIGN(cmdDefs, [NSUserDefaults
	userDefaultsWithPrefix: prf
	strict: EC_DEFAULTS_STRICT]);
      if (defs != nil)
	{
	  [cmdDefs registerDefaults: defs];
	}

      if ([[pinfo arguments] containsObject: @"--help"])
	{
	  NSLog(@"Standard command-line arguments ...\n\n"
	    @"-%@CommandHost [aHost]    Host of command server to use.\n"
	    @"-%@CommandName [aName]    Name of command server to use.\n"
	    @"-%@Daemon [YES/NO]        Fork process to run in background?\n"
	    @"-%@EffectiveUser [aName]  User to run as\n"
	    @"-%@HomeDirectory [relDir] Relative home within user directory\n"
	    @"-%@UserDirectory [dir]    Override home directory for user\n"
	    @"-%@Instance [aNumber]     Instance number for multiple copies\n"
	    @"-%@Memory [YES/NO]        Enable memory allocation checks?\n"
	    @"-%@ProgramName [aName]    Name to use for this program\n"
	    @"-%@Testing [YES/NO]       Run in test mode (if supported)\n"
	    @"\n--version to get version information and quit\n\n",
	    prf, prf, prf, prf, prf, prf, prf, prf, prf, prf
	    );
	  RELEASE(self);
	  [ecLock unlock];
	  return nil;
	}

      if ([[pinfo arguments] containsObject: @"--version"])
	{
	  NSLog(@"%@ %@", [self ecCopyright], cmdVersion(nil));
	  RELEASE(self);
	  [ecLock unlock];
	  return nil;
	}

      cmdUser = EC_EFFECTIVE_USER;
      if (nil == cmdUser)
	{
	  cmdUser = [[cmdDefs stringForKey: @"EffectiveUser"] retain];
	}
      if (YES == [cmdUser isEqual: @"*"]
        || YES == [cmdUser isEqualToString: NSUserName()])
	{
	  ASSIGN(cmdUser, NSUserName());
	}
      else if ([cmdUser length] == 0)
        {
          NSLog(@"This software is not configured to run as any user.\n"
            @"You may use the EffectiveUser user default setting"
            @" to specify the user (setting this to an asterisk ('*')"
            @" allows the software to run as any user).  Alternatively"
            @" an EC_EFFECTIVE_USER can be  defined when the ec library"
            @" is built.");
          exit(1);
        }
      else
	{
	  const char	*user = [cmdUser UTF8String];
	  struct passwd	*pwd = getpwnam(user);
	  int		uid;

	  if (pwd != 0)
	    {
	      uid = pwd->pw_uid;
	    }
	  else
	    {
              NSLog(@"This software is configured to run as the user '%@',"
                @" but there does not appear to be any such user.", cmdUser);
              if ([cmdUser isEqual: EC_EFFECTIVE_USER])
                {
                  NSLog(@"You may use the EffectiveUser user default setting"
                    @" to override the user (setting this to an asterisk ('*')"
                    @" allows the software to run as any user).  Alternatively"
                    @" a different EC_EFFECTIVE_USER can be  defined when the"
                    @" ec library is built.");
                }
	      exit(1);
	    }

	  if (uid != (int)geteuid())
	    {
	      if (geteuid() == 0 || (int)getuid() == uid)
		{
		  if (0 != setuid(uid))
		    {
		      [ecLock unlock];
		      NSLog(@"You must be '%@' to run this.", cmdUser);
		      exit(1);
		    }
		}
	      else
		{
		  [ecLock unlock];
		  NSLog(@"You must be '%@' to run this.", cmdUser);
		  exit(1);
		}
	    }
	  GSSetUserName(cmdUser);
	  if (NO == [cmdUser isEqualToString: NSUserName()])
	    {
	      [ecLock unlock];
	      NSLog(@"You must be '%@' to run this.", cmdUser);
	      exit(1);
	    }
	  ASSIGN(cmdDefs, [NSUserDefaults
	    userDefaultsWithPrefix: prf
	    strict: EC_DEFAULTS_STRICT]);
	  if (defs != nil)
	    {
	      [cmdDefs registerDefaults: defs];
	    }
	}


      i = [cmdDefs integerForKey: @"CoreSize"];
      if (i <= 0)
	{
	  i = 250000000;
	}
      if (getrlimit(RLIMIT_CORE, &rlim) < 0)
	{
	  NSLog(@"Unable to get core file size limit: %d", errno);
	}
      else
	{
	  if (rlim.rlim_max < i)
	    {
	      NSLog(@"Hard limit for core file size (%lu) less than desired",
		rlim.rlim_max);
	    }
	  else
	    {
	      rlim.rlim_cur = i;
	      if (setrlimit(RLIMIT_CORE, &rlim) < 0)
		{
		  NSLog(@"Unable to set core file size limit: %d", errno);
		}
	    }
	}

      if (nil == noNetConfig)
	{
	  noNetConfig = [[NSMutableArray alloc] initWithCapacity: 4];
	  [noNetConfig
	    addObject: [prf stringByAppendingString: @"Daemon"]];
	  [noNetConfig
	    addObject: [prf stringByAppendingString: @"EffectiveUser"]];
	  [noNetConfig
	    addObject: [prf stringByAppendingString: @"Instance"]];
	  [noNetConfig
	    addObject: [prf stringByAppendingString: @"Transient"]];
	}

      defs = [cmdDefs dictionaryRepresentation];
      enumerator = [defs keyEnumerator];
      dbg = [prf stringByAppendingString: @"Debug-"];
      while ((str = [enumerator nextObject]) != nil)
	{
	  if ([str hasPrefix: dbg])
	    {
	      id	obj = [defs objectForKey: str];
	      NSString	*key = [str substringFromIndex: [dbg length]];

	      if ([cmdDebugKnown objectForKey: key] == nil)
		{
		  [cmdDebugKnown setObject: key forKey: key];
		}
	      if ([obj isKindOfClass: stringClass])
		{
		  if ([obj intValue] != 0
		    || [obj isEqual: @"YES"] || [obj isEqual: @"yes"])
		    {
		      if ([cmdDebugModes member: key] == nil)
			{
			  [cmdDebugModes addObject: key];
			}
		    }
		  else
		    {
		      if ([cmdDebugModes member: key] != nil)
			{
			  [cmdDebugModes removeObject: key];
			}
		    }
		}
	    }
	}

      started = RETAIN([dateClass date]);

      /* See if we have a name specified for this process.
       */
      ASSIGN(cmdName, [cmdDefs stringForKey: @"ProgramName"]);

      /* If there's no ProgramName specified, but this is a Control server,
       * try looking for the ControlName instead.
       */
      if (nil == cmdName
	&& Nil != NSClassFromString(@"EcControl")
        && YES == [self isKindOfClass: NSClassFromString(@"EcControl")])
	{
	  ASSIGN(cmdName, [cmdDefs stringForKey: @"ControlName"]);
	}

      /* If there's no ProgramName specified, but this is a Command server,
       * try looking for the CommandName instead.
       */
      if (nil == cmdName
	&& Nil != NSClassFromString(@"EcCommand")
        && YES == [self isKindOfClass: NSClassFromString(@"EcCommand")])
	{
	  ASSIGN(cmdName, [cmdDefs stringForKey: @"CommandName"]);
	}

      /* Finally, if no name is given at all, use the standard process name.
       */
      if (nil == cmdName)
	{
	  ASSIGN(cmdName, [pinfo processName]);
	}

      /*
       * Make sure our users home directory exists.
       */
      str = [cmdDefs objectForKey: @"UserDirectory"];
      str = cmdSetUserDirectory(str);
      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	{
	  if ([mgr createDirectoryAtPath: str
             withIntermediateDirectories: YES
                              attributes: nil
                                   error: NULL] == NO)
	    {
	      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		{
		  [ecLock unlock];
		  NSLog(@"Unable to create directory - %@", str);
		  exit(1);
		}
	    }
	  else
	    {
	      flag = YES;
	    }
	}
      if (flag == NO)
	{
	  [ecLock unlock];
	  NSLog(@"The path '%@' is not a directory", str);
	  exit(1);
	}

      str = [cmdDefs objectForKey: @"HomeDirectory"];
      if (str != nil)
	{
	  if ([str length] == 0)
	    {
	      str = nil;
	    }
	  else if ([str isAbsolutePath] == YES)
	    {
	      NSLog(@"Absolute HomeDirectory ignored.");
	      str = nil;
	    }
	  cmdSetHome(str);
	}

      for (i = 0; i < 32; i++)
	{
	  switch (i)
	    {
	      case SIGPROF: 
	      case SIGABRT: 
		break;

	      case SIGPIPE: 
	      case SIGTTOU: 
	      case SIGTTIN: 
	      case SIGHUP: 
	      case SIGCHLD: 

		/* SIGWINCH is generated when the terminal size
		   changes (for example when you resize the xterm).
		   Ignore it.  */
#ifdef SIGWINCH
	    case SIGWINCH:
#endif

		signal(i, SIG_IGN);
		break;

	      case SIGINT: 
	      case SIGTERM: 
		signal(i, qhandler);
		break;

	      case SIGSTOP:
	      case SIGCONT:
	      case SIGTSTP:
		signal(i, SIG_DFL);
		break;

	      default: 
		signal(i, ihandler);
		break;
	    }
	}

      ASSIGN(cmdInst, [cmdDefs stringForKey: @"Instance"]);
      if (nil != cmdInst)
	{
	  str = [[NSString alloc] initWithFormat: @"%@-%@", cmdName, cmdInst];
	  ASSIGN(cmdName, str);
	  [str release];
	}

      str = userDir;
      if (cmdHomeDir() != nil)
	{
	  str = [str stringByAppendingPathComponent: cmdHomeDir()];
	}
      str = [str stringByStandardizingPath];
      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
	{
	  if ([mgr createDirectoryAtPath: str
             withIntermediateDirectories: YES
                              attributes: nil
                                   error: NULL] == NO)
	    {
	      if ([mgr fileExistsAtPath: str isDirectory: &flag] == NO)
		{
		  [ecLock unlock];
		  NSLog(@"Unable to create directory - %@", str);
		  exit(1);
		}
	    }
	  else
	    {
	      flag = YES;
	    }
	}
      if (flag == NO)
	{
	  [ecLock unlock];
	  NSLog(@"The path '%@' is not a directory", str);
	  exit(1);
	}

      if ([mgr changeCurrentDirectoryPath: str] == NO)
	{
	  [ecLock unlock];
	  NSLog(@"Unable to move to directory - %@", str);
	  exit(1);
	}

      /*
       * Make sure the data directory exists.
       */
      if ([self cmdDataDirectory] == nil)
	{
	  [ecLock unlock];
	  NSLog(@"Unable to create/access data directory");
	  exit(1);
	}

      /*
       * Make sure the logs directory exists.
       */
      if (cmdLogsDir(nil) == nil)
	{
	  [ecLock unlock];
	  NSLog(@"Unable to create/access logs directory");
	  exit(1);
	}

      [[NSProcessInfo processInfo] setProcessName: cmdName];

      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(cmdDefaultsChanged:)
	name: NSUserDefaultsDidChangeNotification
	object: [NSUserDefaults standardUserDefaults]];

      [self cmdDefaultsChanged: nil];

      /* Archive any existing debug log left over by a crash.
       */
      str = [cmdName stringByAppendingPathExtension: @"debug"];
      if (cmdDebugName == nil || [cmdDebugName isEqual: str] == NO)
	{
	  NSFileHandle	*hdl;

	  /*
	   * Force archiving of old logfile.
	   */
	  [self cmdArchive: nil];

	  ASSIGNCOPY(cmdDebugName, str);
	  hdl = [self cmdLogFile: cmdDebugName];
	  if (hdl == nil)
	    {
	      [ecLock unlock];
	      exit(1);
	    }
	}

      [self cmdMesgCache];

      cmdIsTransient = [cmdDefs boolForKey: @"Transient"];

      if ([cmdDefs objectForKey: @"CmdInterval"] != nil)
	{
          [self setCmdInterval: [cmdDefs floatForKey: @"CmdInterval"]];
	}

      if (YES == [self cmdIsClient] && nil == [self cmdNewServer])
	{
	  NSLog(@"Giving up - unable to contact '%@' server on '%@'",
	    ecCommandName(), ecCommandHost());
	  [self release];
	  self = nil;
	}
    }
  [ecLock unlock];

  /* Put self in background.
   */
  if ([cmdDefs boolForKey: @"Daemon"] == YES)
    {
      int	pid = fork();

      if (pid == 0)
	{
	  cmdFlagDaemon = YES;
	  setpgid(0, getpid());
	}
      else
	{
	  if (pid < 0)
	    {
	      printf("Failed fork to run as daemon.\r\n");
	    }
	  else
	    {
	      printf("Process backgrounded (running as daemon)\r\n");
	    }
	  exit(0);
	}
    }

  /* And make sure that regular timers run.
   */
  [self triggerCmdTimeout];

  return self;
}

/*
 *	Implement the CmdConfig protocol.
 */

- (void) replaceFile: (NSData*)data
		name: (NSString*)name
	    isConfig: (BOOL)f
{
  [NSException raise: NSGenericException
	      format: @"Illegal method call"];
}

- (void) requestConfigFor: (id<CmdConfig>)c
{
  [NSException raise: NSGenericException
	      format: @"Illegal method call"];
}

- (void) requestFile: (BOOL)flag
		name: (NSString*)name
		 for: (id<CmdConfig>)c
{
  [NSException raise: NSGenericException
	      format: @"Illegal method call"];
}

- (void) updateConfig: (NSData*)info
{
  id	plist = [NSPropertyListSerialization
    propertyListWithData: info
    options: NSPropertyListMutableContainers
    format: 0
    error: 0];

  if (nil != plist)
    {
      [self _update: plist];
    }
}

- (id) server: (NSString *)serverName
{
  RemoteServer *server;

  server = (RemoteServer *)[servers objectForKey: serverName];
  
  if (server == nil)
    {
      NSLog (@"Trying to ask for not-existent server %@", serverName);
      return nil;
    }
  
  return [server proxy];
}

- (id) server: (NSString *)serverName forNumber: (NSString*)num
{
  RemoteServer	*server;
  NSArray	*config;

  server = (RemoteServer *)[servers objectForKey: serverName];
  
  if (server == nil)
    {
      NSLog (@"Trying to ask for not-existent server %@", serverName);
      return nil;
    }
  config = [server multiple];
  if (config != nil && [config count] > 1)
    {
      int	val = -1;
      unsigned	count = [config count];

      /*
       * Get trailing two digits of number ... in range 00 to 99
       */
      if ([num length] >= 2)
	{
	  val = [[num substringFromIndex: [num length] - 2] intValue];
	}
      if (val < 0)
	{
	  val = 0;
	}
      /*
       * Try to find a broadcast server with a numeric range matching
       * the number we were given.
       */
      while (count-- > 0)
	{
	  NSDictionary	*d = [config objectAtIndex: count];

	  if (val >= [[d objectForKey: @"Low"] intValue]
	    && val <= [[d objectForKey: @"High"] intValue])
	    {
	      return [[server proxy] BCPproxy: count];
	    }
	}
      [self cmdError: @"Attempt to get %@ server for number %@ with bad config",
	serverName, num];
      return nil;
    }
  return [server proxy];
}

- (BOOL) isServerMultiple: (NSString *)serverName
{
  RemoteServer *server;
  
  server = (RemoteServer *)[servers objectForKey: serverName];
  
  if (server == nil)
    {
      NSLog (@"Trying to ask for not-existent server %@", serverName);
      return NO;
    }
  
  return ([server multiple] == nil) ? NO : YES;
}
@end

@implementation	EcProcess (Private)

// For logging from the Control server.
- (void) log: (NSString*)message type: (EcLogType)t
{
  NSLog(@"%@", message);
}

- (void) cmdMesgrelease: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"controls double release memory error detection"];
      return;
    }

  if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"] == NSOrderedSame)
    {
      [self cmdPrintf: @"controls double release memory error detection\n"];
      [self cmdPrintf: @"This has a big impact on program performance.\n"];
      [self cmdPrintf: @"'release yes' turns on checking\n"];
      [self cmdPrintf: @"'release no' turns off checking\n"];
      [self cmdPrintf: @"'release default' reverts to default setting\n"];
      [self cmdPrintf: @"'release' reports current status\n"];
      return;
    }

  if ([msg count] == 1)
    {
      [self cmdPrintf: @"Double release checking: %s\n",
	[cmdDefs boolForKey: @"Release"] ? "YES" : "NO"];
    }

  if ([msg count] > 1)
    {
      if ([[msg objectAtIndex: 1] caseInsensitiveCompare: @"default"]
        == NSOrderedSame)
	{
	  [cmdDefs setCommand: nil forKey: @"Release"];
	}
      else
        {
	  [cmdDefs setCommand: [msg objectAtIndex: 1] forKey: @"Release"];
	}
      [self cmdPrintf: @"Double release checking: %s\n",
	[cmdDefs boolForKey: @"Release"] ? "YES" : "NO"];
    }
}

- (void) cmdMesgtesting: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"controls whether server is running in testing mode"];
      return;
    }

  if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"] == NSOrderedSame)
    {
      [self cmdPrintf: @"controls whether server is running in testing mode\n"];
      [self cmdPrintf: @"Behavior in testing mode is server dependent.\n"];
      [self cmdPrintf: @"'testing yes' turns on testing mode\n"];
      [self cmdPrintf: @"'testing no' turns off testing mode\n"];
      [self cmdPrintf: @"'testing default' reverts to default setting\n"];
      [self cmdPrintf: @"'testing' reports current status\n"];
      return;
    }

  if ([msg count] == 1)
    {
      [self cmdPrintf: @"Server running in testing mode: %s\n",
        cmdFlagTesting ? "YES" : "NO"];
    }

  if ([msg count] > 1)
    {
      if ([[msg objectAtIndex: 1] caseInsensitiveCompare: @"default"]
        == NSOrderedSame)
	{
	  [cmdDefs setObject: nil forKey: @"Testing"];
	}
      else
        {
	  [cmdDefs setObject: [msg objectAtIndex: 1] forKey: @"Testing"];
	}
      [self cmdPrintf: @"Server running in testing mode: %s\n",
	cmdFlagTesting ? "YES" : "NO"];
    }
}

- (NSString*) _moveLog: (NSString*)name to: (NSString*)sub
{
  NSString	*status;
  NSString	*where;

  NS_DURING
    {
      where = cmdLogsDir(sub);
      if (where != nil)
	{
	  NSFileManager	*mgr = [NSFileManager defaultManager];
	  NSString	*from;
	  NSString	*path;
	  NSString	*base;
	  NSString	*gzpath;
	  unsigned	count = 0;

	  path = [where stringByAppendingPathComponent: name];
	  from = [cmdLogsDir(nil) stringByAppendingPathComponent: name];

	  /*
	   * Check for pre-existing file - if found, try another.
	   */
	  base = path;
	  path = [base stringByAppendingPathExtension: @"0"];
	  gzpath = [path stringByAppendingPathExtension: @"gz"];
	  while ([mgr fileExistsAtPath: path] == YES
	    || [mgr fileExistsAtPath: gzpath] == YES)
	    {
	      NSString	*ext;

	      ext = [stringClass stringWithFormat: @"%u", ++count];
	      path = [base stringByAppendingPathExtension: ext];
	      gzpath = [path stringByAppendingPathExtension: @"gz"];
	    }

	  if ([mgr movePath: from
		     toPath: path
		    handler: nil] == NO)
	    {
	      status = [NSString stringWithFormat:
		@"Unable to move %@ to %@", from, path];
	    }
	  else
	    {
	      status = [NSString stringWithFormat:
		@"Moved %@ to %@", from, path];
	    }
	}
      else
	{
	  status = [NSString stringWithFormat:
	    @"Unable to archive log %@ into %@", name, sub];
	}
    }
  NS_HANDLER
    {
      status = [NSString stringWithFormat: @"Problem in %@ with %@ to %@ - %@",
	NSStringFromSelector(_cmd), name, sub, localException];
    }
  NS_ENDHANDLER
  return status;
}

- (void) _timedOut: (NSTimer*)timer
{
  static BOOL	inProgress = NO;
  int	sig = [self cmdSignalled];

  cmdPTimer = nil;
  if (sig > 0)
    {
      [self cmdQuit: sig];
    }
  if (YES == inProgress)
    {
      NSLog(@"_timedOut: ignored because timeout already in progress");
    }
  else
    {
      BOOL	delay = NO;

      inProgress = YES;
      NS_DURING
	{
	  NSCalendarDate	*now = [NSCalendarDate date];
	  static int		lastDay = 0;
	  static int		lastHour = 0;
	  static int		lastMinute = 0;
	  static int		lastTenSecond = 0;
	  BOOL			newDay = NO;
	  BOOL			newHour = NO;
	  BOOL			newMinute = NO;
	  BOOL			newTenSecond = NO;
	  int			i;

	  i = [now dayOfWeek];
	  if (i != lastDay)
	    {
	      lastDay = i;
	      newDay = YES;
	      newHour = YES;
	      newMinute = YES;
	      newTenSecond = YES;
	    }
	  i = [now hourOfDay];
	  if (i != lastHour)
	    {
	      lastHour = i;
	      newHour = YES;
	      newMinute = YES;
	      newTenSecond = YES;
	    }
	  i = [now minuteOfHour];
	  if (i != lastMinute)
	    {
	      lastMinute = i;
	      newMinute = YES;
	      newTenSecond = YES;
	    }
	  i = [now secondOfMinute] / 10;
	  if (i != lastTenSecond)
	    {
	      lastTenSecond = i;
	      newTenSecond = YES;
	    }
	  if (YES == newTenSecond)
	    {
	      [self cmdNewServer];
	    }
	  if (YES == newMinute)
	    {
	      [self ecNewMinute: now];
	    }
	  if (YES == newHour)
	    {
	      [self ecNewHour: now];
	    }
	  if (YES == newDay)
	    {
	      [self ecNewDay: now];
	    }
	  if (cmdTimSelector != 0)
	    {
	      [self performSelector: cmdTimSelector];
	    }
	}
      NS_HANDLER
	{
	  NSLog(@"Exception performing regular timeout: %@", localException);
	  delay = YES;	// Avoid runaway logging.
	}
      NS_ENDHANDLER

      if (cmdPTimer == nil)
	{
	  NSTimeInterval	when = cmdTimInterval;

	  if (delay == YES && when < 1.0)
	    {
	      when = 10.0;
	    }
	  cmdPTimer =
	    [NSTimer scheduledTimerWithTimeInterval: when
					     target: self
					   selector: @selector(_timedOut:)
					   userInfo: nil
					    repeats: NO];
	}
      inProgress = NO;
    }
}

- (void) _update: (NSMutableDictionary*)info
{
  NSMutableDictionary	*newConfig;
  NSDictionary		*dict;
  NSEnumerator		*enumerator;
  NSString		*key;

  newConfig = [NSMutableDictionary dictionaryWithCapacity: 32];
  /*
   *	Put all values for this application in the cmdConf dictionary.
   */
  dict = [info objectForKey: cmdLogName()];
  if (dict != nil)
    {
      enumerator = [dict keyEnumerator];
      while ((key = [enumerator nextObject]) != nil)
        {
          id	obj;

          if ([noNetConfig containsObject: key])
            {
              [self cmdWarn: @"Bad key '%@' in net config.", key];
              continue;
            }
          obj = [dict objectForKey: key];
          [newConfig setObject: obj forKey: key];
        }
    }
  /*
   *	Add any default values to the cmdConf
   *	dictionary where we don't have application
   *	specific values.
   */
  dict = [info objectForKey: @"*"];
  if (dict)
    {
      enumerator = [dict keyEnumerator];
      while ((key = [enumerator nextObject]) != nil)
        {
          if ([newConfig objectForKey: key] == nil)
            {
              id	obj;

              if ([noNetConfig containsObject: key])
                {
                  [self cmdWarn: @"Bad key '%@' in net config.", key];
                  continue;
                }
              obj = [dict objectForKey: key];
              [newConfig setObject: obj forKey: key];
            }
        }
    }

  dict = [info objectForKey: @"Operators"];
  if (dict != nil && dict != cmdOperators)
    {
      ASSIGNCOPY(cmdOperators, dict);
    }

  if (nil == cmdConf || [cmdConf isEqual: newConfig] == NO)
    {
      NS_DURING
        [self cmdUpdate: newConfig];
      NS_HANDLER
        [self cmdError: @"Problem before updating config: %@", localException];
      NS_ENDHANDLER
      NS_DURING
        [self cmdUpdated];
      NS_HANDLER
        [self cmdError: @"Problem after updating config: %@", localException];
      NS_ENDHANDLER
    }
}

@end

