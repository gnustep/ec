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
#import <GNUstepBase/NSObject+GNUstepBase.h>


#import "EcProcess.h"
#import "EcLogger.h"
#import "EcAlarm.h"
#import "EcAlarmDestination.h"
#import "EcHost.h"
#import "EcUserDefaults.h"
#import "EcBroadcastProxy.h"
#import "EcMemoryLogger.h"

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

#if defined(HAVE_TERMIOS_H)
#include <termios.h>
#endif

#if defined(HAVE_GETTID)
#  include <sys/syscall.h>
#  include <sys/types.h>
#endif

#include <stdio.h>


#ifndef __MINGW__
static int              reservedPipe[2] = { 0, 0 };
static NSInteger        descriptorsMaximum = 0;
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

NSUInteger
ecNativeThreadID()
{
#if defined(__MINGW__)
  return (NSUInteger)GetCurrentThreadId();
#elif defined(HAVE_GETTID)
  return (NSUInteger)syscall(SYS_gettid);
#else
  return NSNotFound;
#endif
}

static NSString * const ecControlKey = @"EcControlKey";

/* Return the number of bytes represented by a hexadecimal string (length/2)
 * or the number of 8bit characters  if the string is not hexadecimal digits.
 * If the string is hexadecimal, standardise o uppercase.
 */
static size_t
checkHex(char *str)
{
  const char    *src = str;
  uint8_t       *dst = (uint8_t*)str;
  size_t        l;

  while (*src)
    {
      if (isxdigit(*src))
        {
          if (islower(*src))
            {
              *dst = toupper(*src);
            }
          else
            {
              *dst = *src;
            }
          dst++;
        }
      else if (!isspace(*src))
        {
          *dst = '\0';
          return 0;     // Bad character
        }
      src++;
    }
  *dst = '\0';
  l = ((char*)dst) - str;  
  if (l%2 == 1)
    {
      return 0;         // Not an even number of digits
    }
  return l/2;           // Return number of bytes represented
}

#if 0
static size_t
trim(char *str)
{
  size_t        len = 0;
  char          *frontp = str - 1;
  char          *endp = NULL;

  if (NULL == str || '\0' == str[0])
    {
      return 0;
    }

  len = strlen(str);
  endp = str + len;

  while (isspace(*(++frontp)))
    ;

  while (isspace(*(--endp)) && endp != frontp)
    ;

  if (str + len - 1 != endp)
    {
      *++endp = '\0';
    }
  else if (frontp != str && endp == frontp)
    {
      *str = '\0';
    }

  if (frontp != str)
    {
      endp = str;
      while (*frontp)
        {
          *endp++ = *frontp++;
        }
      *endp = '\0';
    }

  return endp - str;
}
#endif

@interface      EcDefaultRegistration : NSObject
{
  NSString      *name;          // The name/key of the default (without prefix)
  NSString      *type;          // The type text for the default
  NSString      *help;          // The help text for the default
  SEL           cmd;            // method to update when default values change
  id            obj;            // The latest value of the default
  id            val;            // The fallback value of the default
}
+ (void) defaultsChanged: (NSUserDefaults*)defs;
+ (NSMutableString*) listHelp: (NSString*)key;
+ (NSDictionary*) merge: (NSDictionary*)d;
+ (void) registerDefault: (NSString*)name
            withTypeText: (NSString*)type
             andHelpText: (NSString*)help
                  action: (SEL)cmd
                   value: (id)value;
+ (void) showHelp;
@end

/* Lock for controlling access to per-process singleton instance.
 */
static NSRecursiveLock	*ecLock = nil;

static NSString         *configError = nil;
static BOOL             configInProgress = NO;
static BOOL		cmdFlagDaemon = NO;
static BOOL		cmdFlagTesting = NO;
static BOOL		cmdIsRunning = NO;
static BOOL		cmdKeepStderr = NO;
static NSString		*cmdBase = nil;
static NSString		*cmdInst = nil;
static NSString		*cmdName = nil;
static NSString		*cmdUser = nil;
static NSUserDefaults	*cmdDefs = nil;
static NSString		*cmdDebugName = nil;
static NSMutableDictionary	*cmdLogMap = nil;
static id<EcMemoryLogger>       cmdMemoryLogger = nil;

static NSDate	*started = nil;	        /* Time object was created. */
static NSDate	*memStats = nil;        /* Time stats were started. */
static NSTimeInterval	lastIP = 0.0;	/* Time of last input to object. */
static NSTimeInterval	lastOP = 0.0;	/* Time of last output by object. */

static Class	cDateClass = 0;
static Class	dateClass = 0;
static Class	stringClass = 0;
static int	cmdSignalled = 0;

static NSTimeInterval   initAt = 0.0;

/* Internal value for use only by ecIsQuitting() and ecWillQuit()
 */
static NSTimeInterval   beganQuitting = 0.0;    // Start of orderly shutdown
static BOOL             ecWillAbort = NO;       // Abort on next quit

/* Test to see if the process is tryiung to quit gracefully.
 * If quitting has taken over three minutes, abort immediately.
 */
static BOOL
ecIsQuitting()
{
  if (0.0 == beganQuitting)
    {
      return NO;
    }
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (now - beganQuitting >= 180.0)
    {
      NSLog(@"abort: quitting took too long (after %g sec)\n",
        (now - beganQuitting));
      signal(SIGABRT, SIG_DFL);
      abort();
    }
  return YES;
} 

/* Function to start quitting (graceful shutdown).
 */
static void
ecWillQuit(NSString *reason)
{
  NSTimeInterval    now = [NSDate timeIntervalSinceReferenceDate];

  if (0.0 == beganQuitting)
    {
      beganQuitting = now;
#ifndef __MINGW__
      if (reservedPipe[1] > 0)
        {
          close(reservedPipe[0]); reservedPipe[0] = 0;
          close(reservedPipe[1]); reservedPipe[1] = 0;
        }
#endif
      if ([reason length] > 0)
        {
          NSLog(@"will quit: %@", reason);
        }
    }
  else if (YES == ecWillAbort)
    {
      if ([reason length] > 0)
        {
          NSLog(@"abort: quit requested (%@) while quitting after %g sec.\n",
            reason, (now - beganQuitting));
        }
      else
        {
          NSLog(@"abort: quit requested while quitting after %g sec.\n",
            (now - beganQuitting));
        }
      signal(SIGABRT, SIG_DFL);
      abort();
    }
  ecWillAbort = YES;
}

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
  if (SIGHUP == sig)
    {
      static int        hupCount = 0;

      /* We allow multiple HUP signals since, while shutting down we may
       * attempt to write out messages to our terminal, generating more
       * signals, and we want to ignore those and shut down cleanly.
       */
      if (hupCount++ < 1000)
        {
	  cmdSignalled = 0;	// Allow signal to be set.
        }
    }

  /* We store the signal value in a global variable and return to normal
   * processing ... that way later code can check on the state of the
   * variable and take action outside the handler.
   * We can't act immediately here inside the handler as the signal may
   * have interrupted some vital library (eg malloc()) and left it in a
   * state such that our code can't continue.  For instance if we try to
   * cleanup after a signal and call free(), the process may hang waiting
   * for a lock that the interupted function still holds.
   */
  if (0 == cmdSignalled)
    {
      cmdSignalled = sig;       // Record signal for event loop.
    }
  else
    {
      static BOOL	beenHere = NO;

      /* We have been signalled more than once ... so let's try to
       * crash rather than continuing.
       */
      if (NO == beenHere)
	{
	  beenHere = YES;
	  signal(SIGABRT, SIG_DFL);
	  abort();
	}
      exit(cmdSignalled);	// Exit with *first* signal number
    }
#if	RETSIGTYPE != void
  return 0;
#endif
}

NSString*
cmdVersion(NSString *ver)
{
  static NSString	*version = @"1997-2013";

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

static NSString *logsDir = nil;

NSString*
ecLogsSubdirectory()
{
  return logsDir;
}

void
ecSetLogsSubdirectory(NSString *pathComponent)
{
  ASSIGNCOPY(logsDir, pathComponent);
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

/* Return the current data directory.
 * Create the directory path if necessary.
 */
NSString*
cmdDataDir()
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

/* Return the current logging directory - if 'today' is not nil, treat it as
 * the name of a subdirectory in which todays logs should be archived.
 * Create the directory path if necessary.
 */
NSString*
cmdLogsDir(NSString *date)
{
  NSFileManager	*mgr = [NSFileManager defaultManager];
  NSString	*str = cmdUserDir();
  NSString      *component;
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

  component = ecLogsSubdirectory();
  if (nil == component)
    {
      component = @"DebugLogs";
    }
  str = [str stringByAppendingPathComponent: component];
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
	  NSString	*n = cmdName;

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
  NSCalendarDate	*c = [[cDateClass alloc] init];
  NSString	*f = cmdLogKey(t);
  NSString	*n = cmdLogName();
  NSString	*d;
  NSString	*result;
  
  if (h == nil)
    {
      h = [[[NSHost currentHost] wellKnownName] copy];
    }
  d = [c descriptionWithCalendarFormat: @"%Y-%m-%d %H:%M:%S.%F %z" locale: nil];
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

static int              coreSize = -2;  // Not yet set

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

static uint64_t memMaximum = 0;
static uint64_t	memAllowed = 0;
static uint64_t	excAvge = 0;    // current period average
static uint64_t	memAvge = 0;    // current period average
static uint64_t	excStrt = 0;    // excluded usage at first check
static uint64_t	memStrt = 0;    // total usage at first check
static uint64_t	excLast = 0;    // excluded usage at last check
static uint64_t	memLast = 0;    // total usage at last check
static uint64_t	excPrev = 0;    // excluded usage at previous warning
static uint64_t	memPrev = 0;    // total usage at previous warning
static uint64_t	excPeak = 0;    // excluded peak usage
static uint64_t	memPeak = 0;    // total peak usage
static uint64_t	memWarn = 0;    // next warning interval
static uint64_t	memSlot = 0;    // minute counter
static uint64_t	excRoll[10];    // last N values
static uint64_t	memRoll[10];    // last N values
#define	MEMCOUNT (sizeof(memRoll)/sizeof(*memRoll))
static NSDate   *memTime = nil; // Time of last alert


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


NSString	*cmdBasicDbg = @"basicMode";
NSString	*cmdDefaultDbg = @"basicMode";  // Allow older code to link
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

@interface      EcProcess (Defaults)
- (void) _defMemory: (id)val;
- (void) _defRelease: (id)val;
- (void) _defTesting: (id)val;
@end

@interface	EcProcess (Private)
- (void) cmdMesgrelease: (NSArray*)msg;
- (void) cmdMesgrestart: (NSArray*)msg;
- (void) cmdMesgtesting: (NSArray*)msg;
- (void) _memCheck;
- (NSString*) _moveLog: (NSString*)name to: (NSDate*)when;
- (void) _timedOut: (NSTimer*)timer;
- (void) _update: (NSMutableDictionary*)info;
@end

@implementation EcProcess

+ (void) atExit
{
  if ([NSObject shouldCleanUp])
    {
      DESTROY(EcProc);
      DESTROY(EcProcConnection);
      DESTROY(alarmDestination);
      DESTROY(alertLogger);
      DESTROY(auditLogger);
      DESTROY(cmdActions);
      DESTROY(cmdConf);
      DESTROY(cmdDebugKnown);
      DESTROY(cmdDebugModes);
      DESTROY(cmdDebugName);
      DESTROY(cmdDefs);
      DESTROY(cmdFirst);
      DESTROY(cmdInst);
      DESTROY(cmdLast);
      DESTROY(cmdLogMap);
      DESTROY(cmdName);
      DESTROY(cmdOperators);
      DESTROY(cmdPTimer);
      DESTROY(cmdServer);
      DESTROY(cmdUser);
      DESTROY(dataDir);
      DESTROY(debugLogger);
      DESTROY(ecLock);
      DESTROY(errorLogger);
      DESTROY(homeDir);
      DESTROY(hostName);
      DESTROY(noNetConfig);
      DESTROY(replyBuffer);
      DESTROY(servers);
      DESTROY(started);
      DESTROY(userDir);
      DESTROY(warningLogger);
      DESTROY(cmdMemoryLogger);
    }
}


- (Class) _memoryLoggerClassFromBundle: (NSString*)bundleName
{
  NSString *path = nil;
  Class c = Nil;
  NSBundle *bundle = nil;
  NSArray *paths =
   NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,
                                       NSAllDomainsMask,
                                       YES);
  NSEnumerator *e = [paths objectEnumerator];
  while (nil != (path = [e nextObject]))
    {
      path = [path stringByAppendingPathComponent: @"Bundles"];
      path = [path stringByAppendingPathComponent: bundleName];
      path = [path stringByAppendingPathExtension: @"bundle"];
      bundle = [NSBundle bundleWithPath: path];
      if (bundle != nil)
        {
          break;
        }
    }
  if (nil == bundle)
    {
      [self cmdWarn: @"Could not load bundle '%@'", bundleName];
    }
  else if (Nil == (c = [bundle principalClass]))
    {
      [self cmdWarn: @"Could not load principal class from %@ at %@.",
        bundleName, path];
    }
  else if (NO == [c conformsToProtocol: @protocol(EcMemoryLogger)])
    {
      [self cmdWarn:
       @"%@ does not implement the EcMemoryLogger protocol", 
        NSStringFromClass(c)];
      c = Nil;
    }
  return c;
}

+ (NSString*) ecGetKey: (const char*)name
                  size: (unsigned)size
                   md5: (NSData*)digest
{
  struct termios old;
  struct termios new;
  char          *one = NULL;
  char          *two = NULL;
  FILE          *stream;
  NSString      *key;

  if (size < 16) size = 16;
  if (size > 128) size = 128;

  /* Open the terminal
   */
  if ((stream = fopen("/dev/tty", "r+")) == NULL)
    {
      return nil;
    }
  /* Turn echoing off 
   */
  if (tcgetattr(fileno(stream), &old) != 0)
    {
      fclose(stream);
      return nil;
    }
  new = old;
  new.c_lflag &= ~ECHO;
  if (tcsetattr (fileno(stream), TCSAFLUSH, &new) != 0)
    {
      fclose(stream);
      return nil;
    }

  while (NULL == one || NULL == two)
    {
      int       olen = 0;
      int       tlen = 0;

      while (olen != size)
        {
          size_t    len = 0;

          fprintf(stream, "\nPlease enter %s: ", name);
          if (one != NULL) { free(one); one = NULL; }
          olen = getline(&one, &len, stream);
          if (olen < 0)
            {
              if (one != NULL) { free(one); one = NULL; }
              fclose(stream);
              return nil;
            }
          olen = checkHex(one);
          if (olen != size)
            {
              fprintf(stream, "\n%s must be %u hexadecimal digits.\n", name,
                size);
              olen = 0;
            }
          else if (nil != digest)
            {
              CREATE_AUTORELEASE_POOL(pool);
              NSString  *s = [NSString stringWithUTF8String: one];
              NSData    *d;
              NSData    *md5;

              s = [NSString stringWithUTF8String: one];
              d = [[NSData alloc] initWithHexadecimalRepresentation: s];
              md5 = [d md5Digest];
              RELEASE(d);
              if ([digest isEqual: md5])
                {
                  /* If the digest of the key matches the expected value,
                   * we assume entry was correct and set two to be the
                   * same as one so we will not prompt for a confirmation.
                   */
                  two = malloc(len + 1);
                  strcpy(two, one);
                  tlen = olen;
                }
              DESTROY(pool);
            }
        }
  
      while (0 == tlen)
        {
          size_t    len = 0;

          fprintf(stream, "\nPlease re-enter %s to confirm: ", name);
          if (two != NULL) { free(two); two = NULL; }
          tlen = getline(&two, &len, stream);
          if (tlen < 0)
            {
              if (one != NULL) { free(one); one = NULL; }
              if (two != NULL) { free(two); two = NULL; }
              fclose(stream);
              return nil;
            }
          tlen = checkHex(two);
          if (tlen != size)
            {
              fprintf(stream, "\n%s must be %u hexadecimal digits.\n", name,
                size);
              tlen = 0;
            }
        }

      if (strcmp(one, two) != 0)
        {
          free(one); one = NULL;
          free(two); two = NULL;
          fprintf(stream,
            "\nThe strings you entered do not match, please try again.");
        }
    }
  
  /* Restore terminal. */
  (void) tcsetattr(fileno(stream), TCSAFLUSH, &old);

  key = [NSString stringWithUTF8String: one];
  free(one);
  free(two);
  fprintf(stream, "\n%s accepted.\n", name);
  fclose(stream);
  return key;
}

+ (NSMutableDictionary*) ecInitialDefaults
{
  NSProcessInfo *pi;
  id		objects[2];
  id		keys[2];
  NSString	*prefix;

  pi = [NSProcessInfo processInfo];
  objects[0] = [pi processName];
  objects[1] = @".";
  prefix = EC_DEFAULTS_PREFIX;
  if (nil == prefix)
    {
      prefix = @"";
    }
  keys[0] = [prefix stringByAppendingString: @"ProgramName"];
  keys[1] = [prefix stringByAppendingString: @"HomeDirectory"];

  return [NSMutableDictionary dictionaryWithObjects: objects
                                            forKeys: keys
                                              count: 2];
}

+ (NSDictionary*) ecPrepareWithDefaults: (NSDictionary*)defs
{
  static BOOL   prepared = NO;

  [ecLock lock];
  if (NO == prepared)
    {
      NSProcessInfo	*pinfo;
      NSArray           *args;
      NSFileManager	*mgr;
      NSEnumerator	*enumerator;
      NSString		*str;
      NSString		*dbg;
      NSString		*prf;
      BOOL		flag;

      started = RETAIN([dateClass date]);

      pinfo = [NSProcessInfo processInfo];
      args = [pinfo arguments];
      mgr = [NSFileManager defaultManager];
      prf = EC_DEFAULTS_PREFIX;
      if (nil == prf)
	{
	  prf = @"";
	}

      ASSIGN(cmdDefs, [NSUserDefaults
	userDefaultsWithPrefix: prf
	strict: EC_DEFAULTS_STRICT]);
      defs = [EcDefaultRegistration merge: defs];
      if (defs != nil)
	{
	  [cmdDefs registerDefaults: defs];
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

      /* See if we should keep stderr separate, or merge it with
       * our debug output (the default).
       */
      cmdKeepStderr = [cmdDefs boolForKey: @"KeepStandardError"];

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

      /* See if we have a name specified for this process.
       */
      ASSIGN(cmdName, [cmdDefs stringForKey: @"ProgramName"]);

      /* If there's no ProgramName specified, but this is a Control server,
       * try looking for the ControlName instead.
       */
      if (nil == cmdName
	&& Nil != NSClassFromString(@"EcControl")
        && YES == [self isSubclassOfClass: NSClassFromString(@"EcControl")])
	{
	  ASSIGN(cmdName, [cmdDefs stringForKey: @"ControlName"]);
	}

      /* If there's no ProgramName specified, but this is a Command server,
       * try looking for the CommandName instead.
       */
      if (nil == cmdName
	&& Nil != NSClassFromString(@"EcCommand")
        && YES == [self isSubclassOfClass: NSClassFromString(@"EcCommand")])
	{
	  ASSIGN(cmdName, [cmdDefs stringForKey: @"CommandName"]);
	}

      /* Finally, if no name is given at all, use the standard process name.
       */
      if (nil == cmdName)
	{
	  ASSIGN(cmdName, [pinfo processName]);
	}

      /* This is the base name of the process (without instance)
       */
      if (nil == cmdBase)
	{
	  ASSIGN(cmdBase, cmdName);
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

      str = [[cmdDefs stringForKey: @"Instance"] stringByTrimmingSpaces];
      if (nil != str)
        {
          if ([str length] > 0 && isdigit([str characterAtIndex: 0]))
            {
              str = [NSString stringWithFormat: @"%d", [str intValue]];
            }
          else
            {
              str = nil;
            }
        }
      ASSIGN(cmdInst, str);
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
      if (cmdDataDir() == nil)
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

      prepared = YES;
    }
  [ecLock unlock];
  return defs;
}




+ (void) ecRegisterDefault: (NSString*)name
              withTypeText: (NSString*)type
               andHelpText: (NSString*)help
                    action: (SEL)cmd
{
  [EcDefaultRegistration registerDefault: name
                            withTypeText: type
                             andHelpText: help
                                  action: cmd
                                   value: nil];
}

+ (void) ecRegisterDefault: (NSString*)name
              withTypeText: (NSString*)type
               andHelpText: (NSString*)help
                    action: (SEL)cmd
                     value: (id)value
{
  [EcDefaultRegistration registerDefault: name
                            withTypeText: type
                             andHelpText: help
                                  action: cmd
                                   value: value];
}

+ (void) ecSetup
{
  if (nil != EcProc)
    {
      [NSException raise: NSGenericException
                  format: @"+ecSetup called when EcProcess is already set up"];
    }
  [[self alloc] init];
}

- (void) _commandRemove
{
  id connection = [cmdServer connectionForProxy];

  if (nil != connection)
    {
      [connection setDelegate: nil];
      [[NSNotificationCenter defaultCenter]
        removeObserver: self
                  name: NSConnectionDidDieNotification
                object: connection];
      [connection invalidate];
    }
  DESTROY(cmdServer);
}

- (void) _connectionRegistered
{
  [alarmDestination domanage: nil];
}

static NSString	*noFiles = @"No log files to archive";

- (NSString*) cmdBase
{
  return cmdBase;
}

- (id) cmdConfig: (NSString*)key
{
  return [cmdDefs objectForKey: key];
}

- (NSString*) cmdDataDirectory
{
  return cmdDataDir();
}

- (NSUserDefaults*) cmdDefaults
{
  return cmdDefs;
}

/* This method handles the final stage of a configuration update either
 * from the Control server or via the local NSUserDefaults system.
 * If no error has occurred so far, we call the method to chewck/apply
 * the updated config.
 * If an error occurs at any stage, we reset the error string and call
 * the method to report it.
 */
- (void) _checkUpdate
{
  NSString      *err;

  if (nil == configError)
    {
      NS_DURING
        ASSIGN(configError, [self cmdUpdated]);
      NS_HANDLER
        NSLog(@"Problem after updating config (in cmdUpdated) %@",
          localException);
        ASSIGN(configError, @"the -cmdUpdated method raised an exception");
      NS_ENDHANDLER
    }
  
  err = AUTORELEASE(configError);
  configError = nil;
  /* NB. if err is nil this will clear any currently raised alarm
   */
  [self ecConfigurationError: err];
}

/* This method is called when the defaults database is updated for any
 * reason and also if the configuration from the Control server changes.
 * In the latter case, the notification argument is nil.
 * If no error has occurred, we call -cmdDefaultsChanged:
 * After this is done, we check that the update is OK (on the next runloop
 * iteration in the main thread).  The async processing ensures that all
 * handling of defaults database notifications has been done before we
 * check the effects of the update.
 */
- (void) _defaultsChanged: (NSNotification*)n
{
  if (YES == configInProgress)
    {
      return;   // Ignore defaults updates during configuration update.
    }
  if (YES == ecIsQuitting())
    {
      NSLog(@"NSUserDefaults change during process shutdown ... ignored.");
      return;   // Ignore defaults changes during shutdown.
    }
  if (nil == configError)
    {
      NS_DURING
        [self cmdDefaultsChanged: n];
      NS_HANDLER
        NSLog(@"Problem in cmdDefaultsChanged:) %@", localException);
        ASSIGN(configError,
          @"the -cmdDefaultsChanged: method raised an exception");
      NS_ENDHANDLER
    }
  [self performSelectorOnMainThread: @selector(_checkUpdate)
                         withObject: nil
                      waitUntilDone: NO];
}

- (void) cmdDefaultsChanged: (NSNotification*)n
{
  NSEnumerator	*enumerator;
  NSDictionary	*dict;
  NSString	*mode;
  NSString	*str;
  int           i;

  [EcDefaultRegistration defaultsChanged: cmdDefs];

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

  if ((str = [cmdDefs stringForKey: @"CmdInterval"]) != nil)
    {
      [self setCmdInterval: [str floatValue]];
    }

#ifndef __MINGW__
  descriptorsMaximum = [cmdDefs integerForKey: @"DescriptorsMaximum"];
#endif

  memAllowed = (uint64_t)[cmdDefs integerForKey: @"MemoryAllowed"];
#if     SIZEOF_VOIDP == 4
  if (memAllowed >= 4*1024)
    {
      [self cmdError: @"MemoryAllowed (%"PRIu64" too large for 32bit machine..."
        @" using 0", memAllowed];
      memAllowed = 0;
    }
#endif

  memMaximum = (uint64_t)[cmdDefs integerForKey: @"MemoryMaximum"];
#if     SIZEOF_VOIDP == 4
  if (memMaximum >= 4*1024)
    {
      [self cmdError: @"MemoryMaximum (%"PRIu64" too large for 32bit machine..."
        @" using 0", memAllowed];
      memMaximum = 0;	                // Disabled
    }
#endif

  str = [cmdDefs stringForKey: @"CoreSize"];
  if (nil == str)
    {
      i = 2*1024;       // 2 GB default
    }
  else
    {
      i = [str intValue];
      if (i < 0)
        {
          i = -1;       // unlimited
        }
    }
  if (i != coreSize)
    {
      struct rlimit	rlim;
      rlim_t            want;

      coreSize = i;
      if (coreSize < 0)
        {
          want = RLIM_INFINITY;
        }
      else
        {
          want = i * 1024 * 1024;
        }
      if (getrlimit(RLIMIT_CORE, &rlim) < 0)
        {
          NSLog(@"Unable to get core file size limit: %d", errno);
        }
      else
        {
          if (RLIM_INFINITY != rlim.rlim_max && rlim.rlim_max < want)
            {
              int       maxMB = (int)(rlim.rlim_max/(1024*1024));

              if (RLIM_INFINITY == want)
                {
                  NSLog(@"Hard limit for core file size (%dMB)"
                    @" less than requested (unlimited); using %dMB.",
                    maxMB, maxMB);
                }
              else
                {
                  NSLog(@"Hard limit for core file size (%dMB)"
                    @" less than requested (%dMB); using %dMB.",
                    maxMB, coreSize, maxMB);
                }
              want = rlim.rlim_max;
            }
          rlim.rlim_cur = want;
          if (setrlimit(RLIMIT_CORE, &rlim) < 0)
            {
              if (coreSize > 0)
                {
                  NSLog(@"Unable to set core file size limit to %uMB"
                    @", errno: %d", coreSize, errno);
                }
              else if (coreSize < 0)
                {
                  NSLog(@"Unable to set core file size unlimited"
                    @", errno: %d", errno);
                }
              else
                {
                  NSLog(@"Unable to set core dumps disabled"
                    @", errno: %d", errno);
                }
            }
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
  if (0.0 == lastIP)
    {
      return nil;
    }
  return [dateClass dateWithTimeIntervalSinceReferenceDate: lastIP];
}

- (NSDate*) cmdLastOP
{
  if (0.0 == lastOP)
    {
      return nil;
    }
  return [dateClass dateWithTimeIntervalSinceReferenceDate: lastOP];
}

- (NSString*) ecLogEnd: (NSString*)name to: (NSDate*)when
{
  NSString      *status = nil;

  if ([name length] == 0)
    {
      NSLog(@"Attempt to end log with empty filename");
    }
  else
    {
      NSFileHandle	*hdl;

      name = [name lastPathComponent];

      [self ecDoLock];
      hdl = [cmdLogMap objectForKey: name];
      if (hdl != nil)
        {
          /* If the file is empty, remove it, otherwise archive it.
           */
          status = [self _moveLog: name to: when];

          /* Ensure that all data is written to file, then close it unless it's
           * stderr (which we must keep open for logging at all times).
           */
          fflush(stderr);
          if ([hdl fileDescriptor] != 2)
            {
              NS_DURING
                [hdl closeFile];
              NS_HANDLER
              NS_ENDHANDLER
            }

          /*
           * Unregister filename.
           */
          [cmdLogMap removeObjectForKey: name];
        }
      [self ecUnLock];
    }
  return status;
}

- (NSString*) cmdLogEnd: (NSString*)name
{
  return [self ecLogEnd: name to: nil];
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
  [self ecDoLock];
  hdl = [cmdLogMap objectForKey: name];
  if (nil == hdl)
    {
      NSFileManager	*mgr = [NSFileManager defaultManager];
      NSString		*path;

      path = [cmdLogsDir(nil) stringByAppendingPathComponent: name];

      /* Archive any old left-over file.
       */
      [self _moveLog: name to: nil];

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
          [self ecUnLock];
	  return nil;
	}
      /*
       * As a special case, if this is the default debug file
       * we must set it up to write to stderr.
       */
      if (NO == cmdKeepStderr && [name isEqual: cmdDebugName] == YES)
	{
	  int	desc;

	  desc = [hdl fileDescriptor];
	  if (desc != 2)
	    {
	      dup2(desc, 2);
              NS_DURING
                [hdl closeFile];
              NS_HANDLER
              NS_ENDHANDLER
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
  [hdl retain];
  [self ecUnLock];
  return [hdl autorelease];
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

static BOOL     ecDidAwaken = NO;

- (void) ecAwaken
{
  ecDidAwaken = YES;
}

- (void) ecConfigurationError: (NSString*)err
{
  if ([err length] > 0)
    {
      EcAlarm       *a;

      /* Truncate additional text to fit if necessary.
       */
      err = [err stringByTrimmingSpaces];
      if ([err length] > 255)
        {
          err = [err substringToIndex: 255];
          while (255 < strlen([err UTF8String]))
            {
              err = [err substringToIndex: [err length] - 1];
            }
        }
      a = [EcAlarm alarmForManagedObject: nil
        at: nil
        withEventType: EcAlarmEventTypeProcessingError
        probableCause: EcAlarmConfigurationOrCustomizationError
        specificProblem: @"Fatal configuration error"
        perceivedSeverity: EcAlarmSeverityMajor
        proposedRepairAction:
        _(@"Correct config (check additional text and/or log for details).")
        additionalText: err];
      [self alarm: a];
      [alarmDestination shutdown];
      [self ecQuitFor: @"configuration error" with: 1];
    }
  else
    {
      [self clearConfigurationFor: nil
                  specificProblem: @"Fatal configuration error"
                   additionalText: @"Configuration updated"];
    }
}

- (BOOL) ecDidAwaken
{
  return ecDidAwaken;
}

- (oneway void) ecDidQuit: (NSInteger)status
{
  NSArray	*keys;
  NSUInteger	index;
  NSDate        *now = [NSDate date];

  if (NO == ecIsQuitting())
    {
      ecWillQuit(nil);
    }

  if (cmdPTimer != nil)
    {
      [cmdPTimer invalidate];
      cmdPTimer = nil;
    }

  if (0 == status)
    {  
      /* Normal shutdown ... unmanage this process first.
       */
      [alarmDestination unmanage: nil];
    }
  [alarmDestination shutdown];

  /* Almost done ... flush any logs then write the final audit log and
   * flush again (so that audit log should be the last in the file).
   */
  [self cmdFlushLogs];
  if (0 == status)
    {
      [self cmdAudit: @"Shutdown '%@' (normal)", [self cmdName]];
    }
  else
    {
      [self cmdAudit: @"Shutdown '%@' (status %"PRIdPTR")",
        [self cmdName], status];
    }
  [auditLogger flush];

  /* Now that the audit log has been flushed to the Command/Control
   * servers, we can unregister from Command.
   */
  [self cmdUnregister];

  /* Re-do the alarm destination shut down, just in case an alarm
   * occurred while we were flushing logs and/or unregistering.
   */
  [alarmDestination shutdown];
  DESTROY(alarmDestination);

  /* Ensure our DO connection is invalidated so there will be no more
   * remote communications or connection related events.
   */
  [EcProcConnection setDelegate: nil];
  [[NSNotificationCenter defaultCenter]
    removeObserver: self
              name: nil
            object: EcProcConnection];
  [EcProcConnection invalidate];

  /* The very last thing we do is to close down the log filed so they
   * are archived to the correct directory for the current date.
   */
  keys = [cmdLogMap allKeys];
  for (index = 0; index < [keys count]; index++)
    {
      [self ecLogEnd: [keys objectAtIndex: index] to: now];
    }

  exit(status);
}

- (void) ecHandleQuit
{
  return;
}

- (BOOL) ecIsQuitting
{
  return ecIsQuitting();
}

- (oneway void) ecQuitFor: (NSString*)reason with: (NSInteger)status
{
  [self ecWillQuit: reason];
  if (class_getMethodImplementation([EcProcess class], @selector(cmdQuit:))
    != class_getMethodImplementation([self class], @selector(cmdQuit:)))
    {
      /* The -cmdQuit: method was overridden by a subclass, so we must call
       * it but first set the flag so that will not cause an abort when it
       * causes -ecWillQuit: to be called again.
       */
      ecWillAbort = NO;
      [self cmdQuit: status];
    }
  else
    {
      [self ecHandleQuit];
      [self ecDidQuit: status];
    }
}

- (oneway void) ecRestart: (NSString*)reason
{
  if (NO == [NSThread isMainThread])
    {
      [self performSelectorOnMainThread: _cmd
                             withObject: reason
                          waitUntilDone: NO];
      return;
    }
  [self ecQuitFor: reason with: -1];
}

- (void) ecLoggersChanged: (NSNotification*)n
{
  DESTROY(alertLogger);
  DESTROY(auditLogger);
  DESTROY(debugLogger);
  DESTROY(errorLogger);
  DESTROY(warningLogger);
}

- (NSDate*) ecStarted
{
  return started;
}

- (void) ecWillQuit: (NSString*)reason
{
  ecWillQuit(reason);
}

- (oneway void) alarm: (in bycopy EcAlarm*)event
{
  [alarmDestination alarm: event];
}

- (EcAlarm*) alarmConfigurationFor: (NSString*)managedObject
                   specificProblem: (NSString*)specificProblem
                    additionalText: (NSString*)additionalText
                          critical: (BOOL)isCritical
{
  EcAlarmSeverity       severity;
  NSString              *action;
  EcAlarm               *a;

  if (YES == isCritical)
    {
      severity = EcAlarmSeverityCritical;
    }
  else
    {
      severity = EcAlarmSeverityMajor;
    }
  action = @"Check/correct configuration";      // FIXME ... localize
  a = [EcAlarm alarmForManagedObject: managedObject
                                  at: nil
                       withEventType: EcAlarmEventTypeProcessingError
                       probableCause: EcAlarmConfigurationOrCustomizationError 
                     specificProblem: specificProblem
                   perceivedSeverity: severity
                proposedRepairAction: action
                      additionalText: additionalText];
  [self alarm: a];
  return a;
}

- (NSArray*) alarms
{
  return [alarmDestination alarms];
}

- (void) clearConfigurationFor: (NSString*)managedObject
               specificProblem: (NSString*)specificProblem
                additionalText: (NSString*)additionalText
{
  EcAlarm       *a;

  a = [EcAlarm alarmForManagedObject: managedObject
                                  at: nil
                       withEventType: EcAlarmEventTypeProcessingError
                       probableCause: EcAlarmConfigurationOrCustomizationError 
                     specificProblem: specificProblem
                   perceivedSeverity: EcAlarmSeverityCleared
                proposedRepairAction: nil
                      additionalText: additionalText];
  [self alarm: a];
}

- (oneway void) domanage: (in bycopy NSString*)managedObject
{
  [alarmDestination domanage: managedObject];
}

- (oneway void) unmanage: (in bycopy NSString*)managedObject
{
  [alarmDestination unmanage: managedObject];
}

- (int) processIdentifier
{
  static int    pi = 0;

  if (0 == pi)
    {
      pi = [[NSProcessInfo processInfo] processIdentifier];
    }
  return pi;
}

- (void) setCmdInterval: (NSTimeInterval)interval
{
  if (interval > 300.0)
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

+ (NSRecursiveLock*) ecLock
{
  return ecLock;
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
			forKey: cmdBasicDbg];
      [cmdDebugKnown setObject: @"Detailed but general purpose debugging"
			forKey: cmdDetailDbg];

      [cmdDebugModes addObject: cmdBasicDbg];

      [self ecRegisterDefault: @"Memory"
                 withTypeText: @"YES/NO"
                  andHelpText: @"Enable memory allocation checks"
                       action: @selector(_defMemory:)
                        value: @"YES"];
      [self ecRegisterDefault: @"Release"
                 withTypeText: @"YES/NO"
                  andHelpText: @"Turn on double release checks (debug)"
                       action: @selector(_defRelease:)
                        value: @"NO"];
      [self ecRegisterDefault: @"Testing"
                 withTypeText: @"YES/NO"
                  andHelpText: @"Run in test mode (if supported)"
                       action: @selector(_defTesting:)
                        value: @"NO"];
      /*
       * Set the timeouts for the default connection so that
       * they will be inherited by other connections.
       * A two minute timeout is long enough for almost all
       * circumstances.
       */
      [[NSConnection defaultConnection] setRequestTimeout: 120.0];
      [[NSConnection defaultConnection] setReplyTimeout: 120.0];
      [self registerAtExit];
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
  [connection setDelegate: nil];
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
      [self triggerCmdTimeout];
    }
  else
    {
      NSLog(@"unknown connection sent invalidation\n");
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

- (NSString*) ecArchive: (NSDate*)when
{
  NSString	*status = @"";

  if ([cmdLogMap count] == 0)
    {
      status = noFiles;
    }
  else
    {
      NSEnumerator	*enumerator;
      NSString		*name;

      [self ecDoLock];
      enumerator = [[cmdLogMap allKeys] objectEnumerator];
      [self ecUnLock];

      while ((name = [enumerator nextObject]) != nil)
	{
	  NSString	*s;

	  s = [self ecLogEnd: name to: when];
          if (nil != s)
            {
              if ([status length] > 0)
                status = [status stringByAppendingString: @"\n"];
              status = [status stringByAppendingString: s];
            }
	  if (NO == ecIsQuitting())
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
  if (nil != [cmdDebugModes member: cmdBasicDbg])
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
          int   mayRetry;

	  connecting = YES;

          /* The first time we try to connect to the Command server
           * (on startup) we should retry for several seconds in case
           * the whole system is coming up and the Command server has
           * not yet been started.
           */
          mayRetry = (nil == cmdLast ? 10 : 0);

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
                  NSSocketPortNameServer        *ns;

		  host = ecCommandHost();
		  name = ecCommandName();

                  ns = [NSSocketPortNameServer sharedInstance];
		  proxy = [NSConnection
		    rootProxyForConnectionWithRegisteredName: name
							host: host
                                             usingNameServer: ns];
                  while (nil == proxy && mayRetry-- > 0)
                    {
                      [NSThread sleepForTimeInterval: 1.0];
                      proxy = [NSConnection
                        rootProxyForConnectionWithRegisteredName: name
                                                            host: host
                                                 usingNameServer: ns];
                    }
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
		      NSString  *shutdown;

                      shutdown = [NSString stringWithFormat:
                        @" rejected by Command - %@",
			[r objectForKey: @"rejected"]];
		      /* Rejected by server.	*/
                      [self ecQuitFor: shutdown with: 0];
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

                      /* If we just connected to the command server,
                       * and we have a registered connection, then we
                       * can tell it that any alarm for failure to
                       * register must be cleared.
                       */
                      if (nil != cmdServer && [EcProcConnection isValid])
                        {
                          [self _connectionRegistered];
                        }
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
          [self _commandRemove];
	  NSLog(@"Caught exception unregistering from Command: %@",
	    localException);
	}
      NS_ENDHANDLER
      [self _commandRemove];
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
  static BOOL           beenHere = NO;
  static NSDictionary   *defs = nil;
  NSDictionary          *d = [cmdDefs volatileDomainForName: @"EcCommand"];

  if (YES == beenHere)
    {
      /* Archive previous day's logs.  Force logs to be archived for
       * yesterday even if they have been modified today (on the basis
       * that only the very latest info in them should be from today).
       */
      when = [when dateByAddingTimeInterval: -3600.0];
      NSLog(@"Daily: %@", [self ecArchive: when]);

      if (nil != defs)
        {
          NSEnumerator      *e;
          NSString          *k;

          /* Check information left in the EcCommand domain.
           */
          e = [[d allKeys] objectEnumerator];
          while (nil != (k = [e nextObject]))
            {
              id        v = [d objectForKey: k];

              if ([v isEqual: [defs objectForKey: k]])
                {
                  [self cmdError: @"The Console defaults override for '%@'"
                    @" has been left at '%@' for more than a day."
                    @" Please reset it ('tell %@ defaults delete %@') after"
                    @" updating Control.plist as required.",
                    k, v, [self cmdName], k];
                }
            }
        }
    }
  else
    {
      /* First time round we must not archive since that will have
       * been done on startup anyway.
       */
      beenHere = YES;
    }
  ASSIGNCOPY(defs, d);
}

- (void) ecNewHour: (NSCalendarDate*)when
{
  return;
}

- (void) ecNewMinute: (NSCalendarDate*)when
{
#ifndef __MINGW__
  if (NO == ecIsQuitting())
    {
      NSString          *shutdown = nil;
      int	        p[2];

      if (pipe(p) == 0)
        {
          if (0 == reservedPipe[1])
            {
              reservedPipe[0] = p[0];
              reservedPipe[1] = p[1];
            }
          else
            {
              close(p[0]);
              close(p[1]);
            }
          if (descriptorsMaximum > 0)
            {
              if (p[0] > descriptorsMaximum || p[1] > descriptorsMaximum)
                {
                  shutdown = [NSString stringWithFormat:
                    @"Open file descriptor limit (%lu) exceeded",
                    (unsigned long) descriptorsMaximum];
                }
            }
        }
      else
        {
          shutdown = @"Process ran out of file descriptors";
        }
      if (nil != shutdown)
        {
          /* We hope that closing two reserved file descriptors will allow
           * us to shut down gracefully and restart.
           */
          if (reservedPipe[1] > 0)
            {
              close(reservedPipe[0]); reservedPipe[0] = 0;
              close(reservedPipe[1]); reservedPipe[1] = 0;
            }
          [self ecQuitFor: shutdown with: -1];
          return;
        }
    }
#endif

  /* We want to be sure we work with reasonably up to date information.
   */
  [NSHost flushHostCache];

  [self _memCheck];
}

- (void) ecHadIP: (NSDate*)when
{
  if (nil == when)
    {
      lastIP = [dateClass timeIntervalSinceReferenceDate];
    }
  else
    {
      lastIP = [when timeIntervalSinceReferenceDate];
    }
}

- (void) ecHadOP: (NSDate*)when
{
  if (nil == when)
    {
      lastOP = [dateClass timeIntervalSinceReferenceDate];
    }
  else
    {
      lastOP = [when timeIntervalSinceReferenceDate];
    }
}

- (NSUInteger) ecNotLeaked
{
  return 0;
}

- (int) ecRun
{
  CREATE_AUTORELEASE_POOL(arp);
  NSConnection          *c;
  NSRunLoop             *loop;
  NSDate                *future;

  /* Called to permit subclasses to initialise before entering run loop.
   */
  [self ecAwaken];
  RELEASE(arp);
  arp = [NSAutoreleasePool new];
  if (YES == cmdIsTransient)
    {
      [self cmdWarn: @"Attempted to run transient process."];
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
      EcAlarm   *a;

      DESTROY(c);
      NSLog(@"Unable to register with name server. Perhaps a copy of this process is already running (or is hung or blocked waiting for a database query etc), or perhaps an old version was killed and is still registered.  Check the state of any running process and and check the process registration with gdomap.");

      a = [EcAlarm alarmForManagedObject: nil
        at: nil
        withEventType: EcAlarmEventTypeProcessingError
        probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
        specificProblem: @"Unable to register"
        perceivedSeverity: EcAlarmSeverityMajor
        proposedRepairAction:
        _(@"Check for running copy of process and/or registration in gdomap.")
        additionalText: _(@"Process probably already running (possibly hung/delayed) or problem in name registration with distributed objects system (gdomap)")];
      [self alarm: a];
      [alarmDestination shutdown];
      [self ecQuitFor: @"unable to register with name server" with: 2];
      [self cmdFlushLogs];
      [arp release];
      return 2;
    }
  else
    {
      EcAlarm   *a;

      a = [EcAlarm alarmForManagedObject: nil
        at: nil
        withEventType: EcAlarmEventTypeProcessingError
        probableCause: EcAlarmSoftwareProgramAbnormallyTerminated
        specificProblem: @"Unable to register"
        perceivedSeverity: EcAlarmSeverityCleared
        proposedRepairAction: nil
        additionalText: nil];
      [self alarm: a];
    }

  [c setDelegate: self];
  [[NSNotificationCenter defaultCenter] 
    addObserver: self
    selector: @selector(cmdConnectionBecameInvalid:)
    name: NSConnectionDidDieNotification
    object: c];
  EcProcConnection = c;
  
  [self _connectionRegistered];

  [self cmdAudit: @"Started '%@' in %g seconds",
    [self cmdName], [NSDate timeIntervalSinceReferenceDate] - initAt];
  [self cmdFlushLogs];
  cmdIsRunning = YES;
  
  [self triggerCmdTimeout];     /* make sure that regular timers run.  */

  loop = [NSRunLoop currentRunLoop];
  future = [NSDate distantFuture];
  while (YES == [EcProcConnection isValid])
    {
      NS_DURING
	{
          NSDate        *d = [loop limitDateForMode: NSDefaultRunLoopMode];

	  if (0 == cmdSignalled)
            {
              if (nil == d)
                {
                  d = future;
                }
              [loop acceptInputForMode: NSDefaultRunLoopMode beforeDate: d];
            }
	  if (0 != cmdSignalled)
	    {
              int       sig = cmdSignalled;
              NSString  *shutdown;

              shutdown
                = [NSString stringWithFormat: @"signal %d received", sig];
              cmdSignalled = 0;
              [self ecQuitFor: shutdown with: sig];
	    }
	}
      NS_HANDLER
	{
	  [self cmdAlert: @"Problem running server: %@", localException];
          [NSThread sleepForTimeInterval: 1.0];
	}
      NS_ENDHANDLER;
      [arp emptyPool];
    }

  [arp release];

  /* finish server */
  [self ecQuitFor: nil with: 0];
  cmdIsRunning = NO;
  DESTROY(EcProcConnection);
  return 0;
}

- (void) ecTestLog: (NSString*)fmt arguments: (va_list)args
{
  if (YES == cmdFlagTesting)
    {
      NSLogv(fmt, args);
    }
}

- (void) ecTestLog: (NSString*)fmt, ...
{
  if (YES == cmdFlagTesting)
    {
      va_list ap;

      va_start (ap, fmt);
      [self ecTestLog: fmt arguments: ap];
      va_end (ap);
    }
}

- (NSString*) ecUserDirectory
{
  return cmdUserDir();
}

- (void) setCmdDebug: (NSString*)mode withDescription: (NSString*)desc
{
  [cmdDebugKnown setObject: desc forKey: mode];
  if (YES == [cmdDefs boolForKey: [@"Debug-" stringByAppendingString: mode]])
    {
      [cmdDebugModes addObject: mode];
    }
  else
    {
      [cmdDebugModes removeObject: mode];
    }
}

- (void) setCmdTimeout: (SEL)sel
{
  cmdTimSelector = sel;
  [self triggerCmdTimeout];
}

- (void) triggerCmdTimeout
{
  if (NO == [NSThread isMainThread])
    {
      [self performSelectorOnMainThread: _cmd
                             withObject: nil
                          waitUntilDone: NO];
      return;
    }
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

- (oneway void) cmdGnip: (id <CmdPing>)from
	       sequence: (unsigned)num
		  extra: (in bycopy NSData*)data
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
          [self _commandRemove];
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
	  [self cmdPrintf: @"\n%@\n", [self ecArchive: nil]];
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
                  NSUInteger    addr;
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
                  else if (1 == sscanf([arg UTF8String], "%" PRIxPTR, &addr))
                    {
                      NSUInteger	i;

                      alarm = nil;
                      for (i = 0; i < alarmCount; i++)
                        {
                          alarm = [a objectAtIndex: i];
                          if ((NSUInteger)alarm == addr)
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

- (void) cmdMesgdefaults: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf:
        @"temporarily overrides defaults/Control.plist settings"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame)
	{
	  [self cmdPrintf: @"\nWithout parameters,\n  the defaults command is"];
	  [self cmdPrintf: @" used to list the current defaults overrides.\n"];
	  [self cmdPrintf: @"With the 'delete' parameter followed by a name,"];
	  [self cmdPrintf: @"\n  removes an override.\n"];
	  [self cmdPrintf: @"With the 'write' parameter followed by a name "];
	  [self cmdPrintf: @"and value,\n  sets an override of the default.\n"];
	  [self cmdPrintf: @"With the 'read' parameter followed by a name,\n"];
	  [self cmdPrintf: @" shows the effective default after overrides.\n"];
	  [self cmdPrintf: @"With the 'revert' parameter,\n  the command"];
	  [self cmdPrintf: @" is used to revert all overides.\n"];
	  [self cmdPrintf: @"With the 'list' parameter,\n  this lists"];
	  [self cmdPrintf: @" registered (not all) defaults names.\n"];
	  [self cmdPrintf: @"With the 'list' parameter followed by a name,\n"];
	  [self cmdPrintf: @" shows the help for the specified default.\n"];
	}
      else if ([msg count] > 1 && [[msg objectAtIndex: 1] isEqual: @"list"])
	{
          NSString      *key = nil;

          if ([msg count] > 2)
            {
              key = [msg objectAtIndex: 2];
            }
          [self cmdPrintf: @"%@", [EcDefaultRegistration listHelp: key]];
        }
      else if ([msg count] > 1 && [[msg objectAtIndex: 1] isEqual: @"revert"])
	{
          [cmdDefs revertSettings];
          [self cmdPrintf: @"All override settings are removed.\n"];
        }
      else if ([msg count] > 2)
	{
	  NSString	*mode = (NSString*)[msg objectAtIndex: 1];
	  NSString	*key = (NSString*)[msg objectAtIndex: 2];
          id            old;
          id            val;

          old = [cmdDefs objectForKey: key];
          if ([mode caseInsensitiveCompare: @"delete"] == NSOrderedSame)
            {
              if ([key isEqualToString: ecControlKey])
                {
                  [self cmdPrintf: @"%@ can only be set on startup.\n", key];
                  val = nil;
                }
              else
                {
                  [cmdDefs setCommand: nil forKey: key];
                  val = [cmdDefs objectForKey: key];
                }
            }
          else if ([mode caseInsensitiveCompare: @"write"] == NSOrderedSame
            || [mode caseInsensitiveCompare: @"set"] == NSOrderedSame)
	    {
              if ([key isEqualToString: ecControlKey])
                {
                  [self cmdPrintf: @"%@ can only be set on startup.\n", key];
                  val = nil;
                }
              else if ([msg count] == 4)
                {
                  val = [msg objectAtIndex: 3];
                  [cmdDefs setCommand: val forKey: key];
                  val = [cmdDefs objectForKey: key];
                }
              else if ([msg count] == 3)
                {
                  [self cmdPrintf: @"Missing value for '%@ %@' (no effect).\n",
                    mode, key];
                  val = old;
                }
              else
                {
                  [self cmdPrintf: @"Too many values for '%@ %@' (ignored).\n",
                    mode, key];
                  val = old;
                }
	    }
          else if ([mode caseInsensitiveCompare: @"read"] == NSOrderedSame
            || [mode caseInsensitiveCompare: @"get"] == NSOrderedSame)
            {
              if ([key isEqualToString: ecControlKey])
                {
                  [self cmdPrintf: @"%@ can not be displayed.\n", key];
                  val = nil;
                }
              else
                {
                  val = [cmdDefs objectForKey: key];
                }
            }
          else
            {
              /* To be tolerant of typing errors and maintain backward
               * compatibility, anything else is treated as a 'read'
               */
              [self cmdPrintf: @"Unrecognised command '%@' (assume 'read').\n",
                key];
              val = [cmdDefs objectForKey: key];
            }

          if ([key isEqualToString: ecControlKey])
            {
              if ([old length] == 0)
                {
                  [self cmdPrintf: @"%@ is not set.\n", key];
                }
              else
                {
                  [self cmdPrintf: @"%@ was set on startup.\n", key];
                }
            }
          else if (val == old || [val isEqual: old])
            {
              if (nil == val)
                {
                  [self cmdPrintf:
                    @"The override setting for the default '%@' is"
                    @" unchanged (and not set).\n", key];
                }
              else
                {
                  [self cmdPrintf:
                    @"The override setting for the default '%@' is"
                    @" unchanged (%@).\n", key, val];
                }
            }
          else if (nil == val)
            {
              [self cmdPrintf: @"The override setting for the default '%@' is"
                @" deleted (was %@).\n", key, old];
            }
          else if (nil == old)
            {
              [self cmdPrintf: @"The override setting for the default '%@' is"
                @" set to: %@ (was not set).\n", key, val];
            }
          else
            {
              [self cmdPrintf: @"The override setting for the default '%@' is"
                @" set to: %@ (was %@).\n", key, val, old];
            }
	}
      else
	{
          NSDictionary  *d = [cmdDefs volatileDomainForName: @"EcCommand"];
          NSArray       *a;
          NSEnumerator  *e;
          NSString      *k;

	  [self cmdPrintf: @"Console temporary overrides of defaults:\n"];
          a = [[d allKeys] sortedArrayUsingSelector: @selector(compare:)];
          e = [a objectEnumerator];
          k = [e nextObject];
          if (nil == k)
            {
	      [self cmdPrintf: @"  None.\n"];
            }
          else
            {
              while (nil != k)
                {
                  id    v = [d objectForKey: k];

	          [self cmdPrintf: @"  %@ = %@\n", k, v];
                  k = [e nextObject];
                }
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
  e = [[[cmdActions allObjects] sortedArrayUsingSelector: @selector(compare:)]
    objectEnumerator];
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
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"controls recording of memory management statistics"];
    }
  else
    {
      [self cmdPrintf: @"\n%@ on %@ running since %@\n\n",
        cmdLogName(), ecHostName(), [self ecStarted]];

      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame || ([msg count] > 1
          && [[msg objectAtIndex: 1] caseInsensitiveCompare: @"help"]
            == NSOrderedSame))
	{
	  [self cmdPrintf: @"\n\
Without parameters,\n\
  the memory command is used to list the changes in the numbers of objects\n\
  allocated since the command was last issued.\n\
With the single parameter 'all',\n\
  the memory command is used to list the cumulative totals of objects\n\
  allocated since the gathering of memory usage statistics was turned on.\n\
With the single parameter 'current',\n\
  the memory command is used to list the current totals of objects\n\
  allocated (and not deallocated) since the gathering of memory usage\n\
  statistics was turned on.\n\
With the single parameter 'yes',\n\
  the memory command is used to turn on gathering of memory usage statistics.\n\
With the single parameter 'no',\n\
  the memory command is used to turn off gathering of memory usage statistics.\n\
With the single parameter 'default',\n\
  the gathering of memory usage statistics reverts to the default setting.\n\
With two parameters ('class' and a class name),\n\
  new instances of the class are recorded.\n\
With two parameters ('list' and a class),\n\
  recorded instances of the class are reported.\n\
With two parameters ('allowed' and a number),\n\
  the threshold for warnings about process size is set (in MB).\n\
  Set to 'default' to revert to the default.\n\
With two parameters ('increment' and a number),\n\
  the size increment between warnings about process size is set (in KB\n\
  from 10 to 1048576).  Set to 'default' to revert to the default.\n\
With two parameters ('percentage' and a number),\n\
  the percentage increment between warnings about process memory size is\n\
  set (from 1 to 1000).  Set to 'default' to revert to the default.\n\
With two parameters ('maximum' and a number),\n\
  the maximum process size (in MB) is set.  On reaching the limit, the\n\
  process restarts unless the limit is zero (meaning no maximum).\n\
  Set to 'default' to revert to the default."];
	  [self cmdPrintf: @"\n"];
	}
      else if ([msg count] == 2)
	{
	  NSString	*word = [msg objectAtIndex: 1];

	  if ([word caseInsensitiveCompare: @"current"] == NSOrderedSame)
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
                  [self cmdPrintf: @"Memory current stats at %@:\n%s",
                    [NSDate date], list];
		}
	      [cmdDefs setCommand: @"YES" forKey: @"Memory"];
            }
	  else if ([word caseInsensitiveCompare: @"default"] == NSOrderedSame)
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
                  [self cmdPrintf: @"Memory total allocation stats at %@:\n%s",
                    [NSDate date], list];
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
      else if ([msg count] == 3)
        {
	  NSString	*op = [msg objectAtIndex: 1];
          NSString      *arg = [msg objectAtIndex: 2];
          NSInteger     val = [arg integerValue];
       
          if ([op caseInsensitiveCompare: @"allowed"] == NSOrderedSame)
            {
              if (val <= 0)
                {
                  [cmdDefs setCommand: nil forKey: @"MemoryAllowed"];
                  if (0 == memAllowed)
                    {
                      /* The threshold was set back to zero ... to be
                       * calculated from a ten minute baseline.
                       */
                      memSlot = 0;
                    }
		  [self cmdPrintf: @"MemoryAllowed using default value.\n"];
                }
              else
                {
                  arg = [NSString stringWithFormat: @"%"PRIu64, (uint64_t)val];
                  [cmdDefs setCommand: arg forKey: @"MemoryAllowed"];
		  [self cmdPrintf: @"MemoryAllowed set to %@MB.\n", arg];
                }
              memWarn = memAllowed * 1024 * 1024;
              DESTROY(memTime);
              [self _memCheck];
            }
          else if ([op caseInsensitiveCompare: @"increment"] == NSOrderedSame)
            {
              if (val <= 100 || val > 1048576)
                {
                  [cmdDefs setCommand: nil forKey: @"MemoryIncrement"];
                  [self cmdPrintf: @"MemoryIncrement using default value.\n"];
                }
              else
                {
                  arg = [NSString stringWithFormat: @"%"PRIu64, (uint64_t)val];
                  [cmdDefs setCommand: arg forKey: @"MemoryIncrement"];
		  [self cmdPrintf: @"MemoryIncrement set to %@KB.\n", arg];
                }
            }
          else if ([op caseInsensitiveCompare: @"percentage"] == NSOrderedSame)
            {
              if (val <= 0 || val > 1000)
                {
                  [cmdDefs setCommand: nil forKey: @"MemoryPercentage"];
                  [self cmdPrintf: @"MemoryPercentage using default value.\n"];
                }
              else
                {
                  arg = [NSString stringWithFormat: @"%"PRIu64, (uint64_t)val];
                  [cmdDefs setCommand: arg forKey: @"MemoryPercentage"];
		  [self cmdPrintf: @"MemoryPercentage set to %@.\n", arg];
                }
            }
          else if ([op caseInsensitiveCompare: @"maximum"] == NSOrderedSame)
            {
              if (val <= 0)
                {
                  if ([arg caseInsensitiveCompare: @"default"] == NSOrderedSame)
                    {
                      [cmdDefs setCommand: nil forKey: @"MemoryMaximum"];
                      [self cmdPrintf: @"MemoryMaximum using default value.\n"];
                    }
                  else
                    {
                      [cmdDefs setCommand: @"0" forKey: @"MemoryMaximum"];
                      [self cmdPrintf: @"MemoryMaximum restart turned off.\n"];
                    }
                }
              else
                {
                  arg = [NSString stringWithFormat: @"%"PRIu64, (uint64_t)val];
                  [cmdDefs setCommand: arg forKey: @"MemoryMaximum"];
		  [self cmdPrintf: @"MemoryMaximum set to %@MB.\n", arg];
                }
            }
          else
            {
              Class         c = NSClassFromString(arg);

              if (Nil == c)
                {
                  [self cmdPrintf: @"Unable to find class '%@'.\n", arg];
                }
              else
                {
                  if ([op caseInsensitiveCompare: @"class"] == NSOrderedSame)
                    {
                      GSDebugAllocationActiveRecordingObjects(c);
                      [self cmdPrintf: @"Recording instances of '%@'.\n", arg];
                    }
                  else if ([op caseInsensitiveCompare: @"list"] == NSOrderedSame)
                    {
                      NSArray       *array;
                      NSUInteger    count;
                      NSUInteger    index;

                      array = GSDebugAllocationListRecordedObjects(c);
                      [self cmdPrintf: @"Current instances of '%@':\n", arg];
                      count = [array count];
                      for (index = 0; index < count; index++)
                        {
                          [self cmdPrintf: @"%6lu %@\n",
                            (unsigned long)index, [array objectAtIndex: index]];
                        }
                    }
                  else
                    {
                      [self cmdPrintf: @"Unknown memory command '%@'.\n", op];
                    }
                }
            }
        }
      else
	{
	  if (NO == [cmdDefs boolForKey: @"Memory"])
	    {
	      [self cmdPrintf: @"Memory stats are not being gathered.\n"];
	    }
	  else
	    {
	      const char        *list;
              NSDate            *now;

              now = [NSDate date];
	      list = (const char*)GSDebugAllocationList(YES);
              if (nil == memStats)
                {
                  [self cmdPrintf: @"Memory change stats at %@:\n%s",
                    now, list];
                }
              else
                {
                  [self cmdPrintf: @"Memory change stats at %@\n"
                    @"  (since %@):\n%s", now, memStats, list];
                }
              ASSIGN(memStats, now);
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
	cmdLogName(), ecHostName(), [self ecStarted]];
      if (lastIP > 0.0)
	{
	  [self cmdPrintf: @"Last IP at %@\n", [self cmdLastIP]];
	}
      if (lastOP > 0.0)
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

      [self cmdPrintf: @"Memory usage: %"PRIu64"KB (current),"
        @" %"PRIu64"KB (peak)\n",
        memLast/1024, memPeak/1024];
      [self cmdPrintf: @"              %"PRIu64"KB (average),"
        @" %"PRIu64"KB (start)\n",
        memAvge/1024, memStrt/1024];
      [self cmdPrintf: @"              %"PRIu64"KB (reserved)\n",
        excLast/1024];
      if (memSlot < MEMCOUNT)
        {
          [self cmdPrintf: @"Memory error reporting disabled (for %d min"
            @" of baseline stats collection).\n", (int)(MEMCOUNT - memSlot)];
        }
      else
        {
          [self cmdPrintf:
            @"Memory error reporting after average usage: %"PRIu64"KB\n",
            memWarn/1024];
        }
      if (memMaximum > 0)
        {
          [self cmdPrintf:
            @"Memory exceeded shutdown after peak usage: %"PRIu64"KB\n",
            memMaximum * 1024];
        }
    }
}

- (oneway void) cmdPing: (id <CmdPing>)from
	       sequence: (unsigned)num
		  extra: (in bycopy NSData*)data
{
  /* When responding to a ping from a remote process, we also check
   * and abort if we have spent too long trying to quit.
   */
  ecIsQuitting();
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

- (oneway void) cmdQuit: (NSInteger)status
{
  [self ecWillQuit: nil];
  [self ecHandleQuit];
  [self ecDidQuit: status];
}

- (void) cmdUpdate: (NSMutableDictionary*)info
{
  ASSIGNCOPY(cmdConf, info);
  [cmdDefs setConfiguration: cmdConf];
}

- (NSString*) cmdUpdated
{
  return nil;
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
  CREATE_AUTORELEASE_POOL(pool);

  self = [self initWithDefaults: [[self class] ecInitialDefaults]];
  RELEASE(pool);
  return self;
}

- (id) initWithDefaults: (NSDictionary*) defs
{
  [ecLock lock];
  initAt = [NSDate timeIntervalSinceReferenceDate];
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
      NSArray           *args = [[NSProcessInfo processInfo] arguments];
      NSString		*str;
      NSString		*prf;
      NSInteger		i;

      EcProc = self;

      prf = EC_DEFAULTS_PREFIX;
      if (nil == prf)
	{
	  prf = @"";
	}

      started = RETAIN([dateClass date]);
      defs = [[self class] ecPrepareWithDefaults: defs];

      if ([args containsObject: @"--help"] || [args containsObject: @"-H"])
	{
	  GSPrintf(stderr, @"Standard command-line arguments ...\n\n");

          if ([self isKindOfClass: NSClassFromString(@"EcControl")])
            {
              GSPrintf(stderr,
@"-%@Daemon NO              Run process in the foreground.\n",
                prf);
            }
          else if ([self isKindOfClass: NSClassFromString(@"EcConsole")])
            {
              GSPrintf(stderr,
@"-%@ControlHost [aHost]    Host of the Control server to use.\n"
@"-%@ControlName [aName]    Name of the Control server to use.\n"
@"-%@Daemon [YES/NO]        Fork process to run in background?\n",
                prf, prf, prf);
            }
          else if ([self isKindOfClass: NSClassFromString(@"EcCommand")])
            {
              GSPrintf(stderr,
@"-%@ControlHost [aHost]    Host of the Control server to use.\n"
@"-%@ControlName [aName]    Name of the Control server to use.\n"
@"-%@Daemon NO              Run process in in the foreground.\n",
                prf, prf, prf);
            }
          else
            {
              GSPrintf(stderr,
@"-%@CommandHost [aHost]    Host of the Command server to use.\n"
@"-%@CommandName [aName]    Name of the Command server to use.\n"
@"-%@Daemon [YES/NO]        Fork process to run in background?\n",
@"-%@Transient [YES/NO]     Expect this process be short-lived?\n",
                prf, prf, prf, prf);
            }

	  GSPrintf(stderr, @"\n");
          GSPrintf(stderr,
	    @"-%@CoreSize [MB]          Maximum core dump size\n"
            @"                          0 = no dumps, -1 = unlimited\n"
	    @"-%@DescriptorsMaximum [N]\n"
            @"                          Set maximum file descriptors to use\n"
            @"-%@Debug-name [YES/NO]    Turn on/off the named type of debug\n"
	    @"-%@EffectiveUser [aName]  User to run this process as\n"
	    @"-%@HomeDirectory [relDir] Relative home within user directory\n"
	    @"-%@UserDirectory [dir]    Override home directory for user\n"
	    @"-%@Instance [aNumber]     Instance number for multiple copies\n"
	    @"-%@MemoryAllowed [MB]     Expected memory usage (before alerts)\n"
	    @"-%@MemoryIncrement [KB]   Absolute increase in alert threshold\n"
	    @"-%@MemoryMaximum [MB]     Maximum memory usage (before restart)\n"
	    @"-%@MemoryPercentage [N]   Percent increase in alert threshold\n"
	    @"-%@ProgramName [aName]    Name to use for this program\n"
	    @"\n--version to get version information and quit\n\n",
	    prf, prf, prf, prf, prf, prf, prf, prf, prf, prf, prf, prf);

          [EcDefaultRegistration showHelp];

	  RELEASE(self);
	  [ecLock unlock];
	  return nil;
	}

      if ([args containsObject: @"--version"])
	{
	  NSLog(@"%@ %@", [self ecCopyright], cmdVersion(nil));
	  RELEASE(self);
	  [ecLock unlock];
	  return nil;
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
	      case SIGCHLD: 

		/* SIGWINCH is generated when the terminal size
		   changes (for example when you resize the xterm).
		   Ignore it.  */
#ifdef SIGWINCH
	    case SIGWINCH:
#endif

		signal(i, SIG_IGN);
		break;

	      case SIGHUP: 
                if ([cmdDefs boolForKey: @"Daemon"] == YES)
                  {
                    signal(i, SIG_IGN);
                  }
                else
                  {
                    signal(i, qhandler);
                  }
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

      /* Archive any existing debug log left over by a crash.
       */
      str = [cmdName stringByAppendingPathExtension: @"debug"];
      if (cmdDebugName == nil || [cmdDebugName isEqual: str] == NO)
	{
	  NSFileHandle	*hdl;
          NSString      *result;

	  /* Force archiving of old logfile.
	   */
          result = [self ecArchive: nil];
          if (result != noFiles)
            {
              NSLog(@"Startup: %@", result);
            }

	  ASSIGNCOPY(cmdDebugName, str);
	  hdl = [self cmdLogFile: cmdDebugName];
	  if (hdl == nil)
	    {
	      [ecLock unlock];
	      exit(1);
	    }
	}

      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(_defaultsChanged:)
	name: NSUserDefaultsDidChangeNotification
	object: [NSUserDefaults standardUserDefaults]];

      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(ecLoggersChanged:)
	name: EcLoggersDidChangeNotification
	object: nil];

      [self cmdMesgCache];

      [self cmdDefaultsChanged: nil];

      cmdIsTransient = [cmdDefs boolForKey: @"Transient"];

      if ([cmdDefs objectForKey: @"CmdInterval"] != nil)
	{
          [self setCmdInterval: [cmdDefs floatForKey: @"CmdInterval"]];
	}

      /* Log that we are starting up, after the config required for logging
       * is in place, but before we have updated config from the Command
       * server (since updating config may generater log files).
       */
      [self cmdAudit: @"Starting '%@'", [self cmdName]];

      if (YES == [self cmdIsClient] && nil == [self cmdNewServer])
	{
	  NSLog(@"Giving up - unable to contact '%@' server on '%@'",
	    ecCommandName(), ecCommandHost());
	  [self release];
	  self = nil;
	}
    }
  [ecLock unlock];

  if (self != nil)
    {
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
    }

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

- (oneway void) requestConfigFor: (id<CmdConfig>)c
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

- (oneway void) updateConfig: (in bycopy NSData*)info
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
      [self cmdPrintf: @"to report if an object is released too many times.\n"];
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

- (void) cmdMesgrestart: (NSArray*)msg
{
  if ([msg count] == 0)
    {
      [self cmdPrintf: @"requests a restart"];
    }
  else
    {
      if ([[msg objectAtIndex: 0] caseInsensitiveCompare: @"help"]
        == NSOrderedSame)
	{
	  [self cmdPrintf: @"\nThe restart command is used to request a"];
	  [self cmdPrintf: @" restart of the process.\n"];
	  [self cmdPrintf: @"This is like quitting the process but with"];
	  [self cmdPrintf: @" a new process started by the Command\n"];
	  [self cmdPrintf: @" server and potentially different shutdown"];
	  [self cmdPrintf: @" behavior.\n"];
	}
      else
	{
          [self performSelectorOnMainThread: @selector(ecRestart:)
                                 withObject: @"Console restart command"
                              waitUntilDone: NO];
	  [self cmdPrintf: @"A restart is being requested for %@.\n", cmdName];
	}
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
	  [cmdDefs setCommand: nil forKey: @"Testing"];
	}
      else
        {
	  [cmdDefs setCommand: [msg objectAtIndex: 1] forKey: @"Testing"];
	}
      [self cmdPrintf: @"Server running in testing mode: %s\n",
	cmdFlagTesting ? "YES" : "NO"];
    }
}

- (void) _ensureMemLogger
{
  NSString *bundle = [cmdDefs stringForKey: @"MemoryLoggerBundle"];
  Class cls = Nil;
  if (nil == bundle)
    {
      DESTROY(cmdMemoryLogger);
      return;
    }
  // This is a reasonable fast path if we have already loaded the bundle
  cls = NSClassFromString(bundle);
  if ((Nil == cls)
      || (NO == [cls conformsToProtocol: @protocol(EcMemoryLogger)]))
    {
      cls = [self _memoryLoggerClassFromBundle: bundle];
    }
  if (Nil == cls)
    {
      // No usable logger class, destroy any we might have
      DESTROY(cmdMemoryLogger);
      return;
    }
  if (NO == [cmdMemoryLogger isKindOfClass: cls])
    {
      // If it's no longer the right class, destroy it
      DESTROY(cmdMemoryLogger);
    }
  if (nil == cmdMemoryLogger)
    {
      NS_DURING
        {
          cmdMemoryLogger = [cls new];
        }
      NS_HANDLER
        {
          [self cmdWarn: @"Exception creating memory logger: %@",
             localException];
        }
      NS_ENDHANDLER
    }
}

- (void) _memCheck
{
  BOOL          memDebug = [cmdDefs boolForKey: @"Memory"];
  FILE          *fptr;
  int	        i;

  /* /proc/pid/statm reports the process memory size in 4KB pages
   */
  fptr = fopen([[NSString stringWithFormat: @"/proc/%d/statm",
    [[NSProcessInfo processInfo] processIdentifier]] UTF8String], "r");
  memLast = 1;
  if (NULL != fptr)
    {
      if (fscanf(fptr, "%"PRIu64, &memLast) != 1)
        {
          memLast = 1;
        }
      else
        {
          memLast *= (4 * 1024);
          if (memLast <= 0) memLast = 1;
        }
      fclose(fptr);
    }
  excLast = (uint64_t)[self ecNotLeaked];

  [self _ensureMemLogger];
  if (nil != cmdMemoryLogger)
    {
      NS_DURING
        {
          [cmdMemoryLogger process: self
                      didUseMemory: memLast
                         notLeaked: excLast];
        }
      NS_HANDLER
        {
          [self cmdWarn:
            @"Exception logging memory usage to bundle: %@",
           localException];
        }
      NS_ENDHANDLER
    }

  /* Do initial population so we can work immediately.
   */
  if (0 == memSlot)
    {
      for (i = 1; i < MEMCOUNT; i++)
        {
          excRoll[i] = excLast;
          memRoll[i] = memLast;
        }
      memPrev = memStrt = memLast;
      excPrev = excStrt = excLast;
    }
  excRoll[memSlot % MEMCOUNT] = excLast;
  memRoll[memSlot % MEMCOUNT] = memLast;
  memSlot++;

  /* Find the average usage over the last set of samples.
   * Round up to a block size.
   */
  excAvge = 0;
  memAvge = 0;
  for (i = 0; i < MEMCOUNT; i++)
    {
      excAvge += excRoll[i];
      memAvge += memRoll[i];
    }
  excAvge /= MEMCOUNT;
  memAvge /= MEMCOUNT;

  /* Convert to 1KB blocks.
   */
  if (memAvge % 1024)
    {
      memAvge = ((memAvge / 1024) + 1) * 1024;
    }
  if (excAvge % 1024)
    {
      excAvge = ((excAvge / 1024) + 1) * 1024;
    }

  /* Update peak memory usage if necessary.
   */
  if (memLast > memPeak)
    {
      memPeak = memLast;
    }
  if (excLast > excPeak)
    {
      excPeak = excLast;
    }

  /* If we have a defined maximum memory usage for the process,
   * we should perform a restart once that limit is passed.
   */
  if (memMaximum > 0 && memPeak > (memMaximum * 1024 * 1024))
    {
      static BOOL       memRestart = NO;

      if (NO == memRestart)
        {
          memRestart = YES;
          [self cmdAlert: @"MemoryMaximum exceeded ... initiating restart"];
          [self ecRestart: @"memory usage limit reached"];
        }
      return;
    }

  /* If the average memory usage is above the threshold (adjusted by any
   * change in known unleaked memory), we alert and reset the threshold.
   * During the first ten minutes though, we always adjust the threshold and
   * we suppress any warnings. This gives us a more stable starting point.
   */
  if (memAvge + excPrev - excAvge > memWarn || memSlot < MEMCOUNT)
    {
      NSInteger     inc;
      NSInteger     pct;
      uint64_t      iMax = 0;
      uint64_t      pMax = 0;

      /* We increase the threshold for the next alert by a percentage
       * of the existing usage or by a fixed increment, whichever is
       * the larger.
       */
      pct = [cmdDefs integerForKey: @"MemoryPercentage"];
      if (pct < 1 || pct > 100)
        {
          /* Set the next alerting threshold 5%
           * the current peak usage,
           * ensuring that only serious increases
           * in usage will generate an alert.
           */
          pct = 5;
        }
      pMax = (memPeak * (100 + pct)) / 100;

      inc = [cmdDefs integerForKey: @"MemoryIncrement"];
      if (inc < 100 || inc > 1048576)
        {
          /* Set the next alerting threshold from
           * 50MB above the current peak usage,
           * ensuring that only serious increases
           * in usage will generate an alert.
           */
          inc = 50 * 1024;
        }
      iMax = memPeak + (inc * 1024);

      memWarn = (iMax > pMax) ? iMax : pMax;
      if (memWarn % 1024)
        {
          memWarn = (memWarn/1024 + 1) * 1024;
        }
      if (memWarn < memAllowed * 1024 * 1024)
        {
          /* Never warn at less than the allowed memory.
           */
          memWarn = memAllowed * 1024 * 1024;
        }

      /* If not in the initial period, we need to generate an alert
       * because the average has risen above the allowed size.
       */
      if (memSlot >= MEMCOUNT)
        {
          uint64_t      ePrev;
          uint64_t      mPrev;
          NSDate        *when;

          ePrev = excPrev;
          mPrev = memPrev;
          when = AUTORELEASE(memTime);
          excPrev = excAvge;
          memPrev = memAvge;
          memTime = [NSDate new];
          if (nil == when)
            {
              [self cmdError: @"Average memory usage %luKB (grown by %ldKB)"
                @" with %luKB (grown by %ldKB) accounted for;"
                @" possible leak of %ldKB (%u%%)",
                (unsigned long)memAvge/1024,
                (long)(memAvge - mPrev)/1024,
                (unsigned long)excAvge/1024,
                (long)(excAvge - ePrev)/1024,
                (long)(memAvge - mPrev + ePrev - excAvge)/1024,
                (unsigned)(((memAvge - mPrev + ePrev - excAvge)*100)/mPrev)];
            }
          else
            {
              [self cmdError: @"Average memory usage %luKB (grown by %ldKB)"
                @" with %luKB (grown by %ldKB) accounted for;"
                @" possible leak of %ldKB (%u%%) since %@",
                (unsigned long)memAvge/1024,
                (long)(memAvge - mPrev)/1024,
                (unsigned long)excAvge/1024,
                (long)(excAvge - ePrev)/1024,
                (long)(memAvge - mPrev + ePrev - excAvge)/1024,
                (unsigned)(((memAvge - mPrev + ePrev - excAvge)*100)/mPrev),
                when];
            }
        }
    }

  if (YES == memDebug)
    {
      [self cmdDbg: cmdDetailDbg
	       msg: @"Memory usage %"PRIu64"KB (reserved: %"PRIu64"KB)",
        memLast/1024, excLast/1024];
    }
}

- (NSString*) _moveLog: (NSString*)name to: (NSDate*)when
{
  NSString	*status = nil;

  NS_DURING
    {
      NSFileManager	*mgr = [NSFileManager defaultManager];
      NSString          *from;
      NSDictionary      *attr;

      from = [cmdLogsDir(nil) stringByAppendingPathComponent: name];
      attr = [mgr fileAttributesAtPath: from traverseLink: NO];
      if (nil != attr)
        {
          if ([[attr objectForKey: NSFileSize] intValue] == 0)
            {
              [mgr removeFileAtPath: from handler: nil];
              status = [NSString stringWithFormat:
                @"Removed empty log %@", from];
            }
          else
            {
              NSString      *where;
              NSString      *sub;

              if (nil == when)
                {
                  when = [attr fileModificationDate];
                }
              sub = [when descriptionWithCalendarFormat: @"%Y-%m-%d"
                                               timeZone: nil
                                                 locale: nil];
              where = cmdLogsDir(sub);
              if (where != nil)
                {
                  NSString	*path;
                  NSString	*base;
                  NSString	*gzpath;
                  unsigned	count = 0;

                  path = [where stringByAppendingPathComponent: name];

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
        }
    }
  NS_HANDLER
    {
      status = [NSString stringWithFormat: @"Problem in %@ with %@ to %@ - %@",
	NSStringFromSelector(_cmd), name, when, localException];
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
      NSString  *shutdown;

      shutdown = [NSString stringWithFormat: @"signal %d received", sig];
      [self ecQuitFor: shutdown with: sig];
    }
  if (YES == ecIsQuitting())
    {
      NSLog(@"_timedOut: ignored because process is quitting");
    }
  else if (YES == inProgress)
    {
      NSLog(@"_timedOut: ignored because timeout already in progress");
    }
  else
    {
      BOOL	delay = NO;

      inProgress = YES;

      /* We only perform timeouts if the process is actually
       * running (don't want them during startup before the
       * thing is fully initialised.
       * So if not running, skip to scheduling next timeout.
       */
      if (YES == cmdIsRunning)
        {
          NS_DURING
            {
              NSCalendarDate	*now = [NSCalendarDate date];
              static int	lastDay = -1;
              static int	lastHour = -1;
              static int	lastMinute = -1;
              static int	lastTenSecond = -1;
              BOOL		newDay = NO;
              BOOL		newHour = NO;
              BOOL		newMinute = NO;
              BOOL		newTenSecond = NO;
              int		i;

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
              NSLog(@"Exception performing regular timeout: %@",
                localException);
              delay = YES;	// Avoid runaway logging.
            }
          NS_ENDHANDLER
        }

      if (cmdPTimer == nil)
	{
	  NSTimeInterval	when = cmdTimInterval;

	  if (when < 0.001 || (when < 10.0 && YES == delay))
	    {
	      when = 10.0;
	    }
          if (when > 300.0)
            {
              when = 60.0;
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

  if (YES == ecIsQuitting())
    {
      NSLog(@"Configuration change during process shutdown ... ignored.");
      return;   // Ignore config updates while quitting
    }
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
      DESTROY(configError);
      configInProgress = YES;
      NS_DURING
        [self cmdUpdate: newConfig];
      NS_HANDLER
        NSLog(@"Problem before updating config (in cmdUpdate:) %@",
          localException);
        ASSIGN(configError, @"the -cmdUpdate: method raised an exception");
      NS_ENDHANDLER
      configInProgress = NO;
      [self _defaultsChanged: nil];
    }
}

@end

@implementation EcProcess (Test)

- (bycopy NSString*) ecTestCommand: (in bycopy NSString*)command
{
  NSEnumerator          *enumerator;
  NSMutableArray        *words;
  NSString              *word;

  command = [command stringByTrimmingSpaces];
  words = [NSMutableArray arrayWithCapacity: 16];
  enumerator = [[command componentsSeparatedByString: @" "] objectEnumerator];
  while ((word = [enumerator nextObject]) != nil)
    {
      [words addObject: [word stringByTrimmingSpaces]];
    }
  if ([words count] == 0)
    {
      return nil;
    }
  return [self cmdMesg: words];
}

- (bycopy NSData*) ecTestConfigForKey: (in bycopy NSString*)key
{
  id    result = [cmdDefs objectForKey: key];

  if (nil != result)
    {
      result = [NSPropertyListSerialization
        dataFromPropertyList: result
        format: NSPropertyListBinaryFormat_v1_0
        errorDescription: 0];
    }
  return result;
}

- (void) ecTestSetConfig: (in bycopy NSData*)data
                  forKey: (in bycopy NSString*)key
{
  id    val;

  if (nil == data)
    {
      val = data;
    }
  else
    {
      val = [NSPropertyListSerialization
        propertyListWithData: data
        options: NSPropertyListMutableContainers
        format: 0
        error: 0];
    }
  [cmdDefs setCommand: val forKey: key];
}

@end

@implementation EcProcess (Defaults)
- (void) _defMemory: (id)val
{
  BOOL  stats = [val boolValue];

  GSDebugAllocationActive(stats);
  if (YES == stats && nil == memStats)
    {
      ASSIGN(memStats, [NSDate date]);
    }
  if (NO == stats && nil != memStats)
    {
      DESTROY(memStats);
    }
}
- (void) _defRelease: (id)val
{
  [NSObject enableDoubleReleaseCheck: [val boolValue]];
}
- (void) _defTesting: (id)val
{
  cmdFlagTesting = [val boolValue];
}
@end

@implementation EcDefaultRegistration

static NSMutableDictionary      *regDefs = nil;
static BOOL                     merged = NO;

+ (void) defaultsChanged: (NSUserDefaults*)defs
{
  NSEnumerator  *e;
  NSString      *n;

  [ecLock lock];
  e = [[regDefs allKeys] objectEnumerator];  
  [ecLock unlock];
  while (nil != (n = [e nextObject]))
    {
      EcDefaultRegistration     *d;
      id                        o = nil;
      SEL                       c = NULL;

      [ecLock lock];
      d = [regDefs objectForKey: n];
      if (nil != d)
        {
          o = [defs objectForKey: n];
          if (o != d->obj && NO == [o isEqual: d->obj])
            {
              ASSIGNCOPY(d->obj, o);
              o = d->obj;
              c = d->cmd;
            }
        }
      [ecLock unlock];
      if (NULL != c && [EcProc respondsToSelector: c])
        {
          [EcProc performSelector: c withObject: o]; 
        }
    }
}

+ (void) initialize
{
  regDefs = [NSMutableDictionary new];
}

/* Key may be one of:
 *   nil        list all registered defaults keys
 *   empty      list all registered defaults help
 *   other      list the registered defaults help for the specified key
 */
+ (NSMutableString*) listHelp: (NSString*)key
{
  NSMutableString       *out = [NSMutableString stringWithCapacity: 1000];
  NSArray       *keys;
  NSString      *prf;
  NSEnumerator  *e;
  NSString      *k;
  NSUInteger    max = 0;

  prf = EC_DEFAULTS_PREFIX;
  if (nil == prf)
    {
      prf = @"";
    }

  [ecLock lock];
  keys = [regDefs allKeys];
  [ecLock unlock];
  e = [keys objectEnumerator];
  while (nil != (k = [e nextObject]))
    {
      EcDefaultRegistration     *d;

      [ecLock lock];
      d = [regDefs objectForKey: k];
      if (nil != d->type && nil != d->help)
        {
          NSUInteger    length = [prf length] + 5;

          length += [k length] + [d->type length];
          if (length > max)
            {
              max = length;
            }
        }
      [ecLock unlock];
    }

  keys = [keys sortedArrayUsingSelector: @selector(compare:)];
  e = [keys objectEnumerator];
  if (nil == key)
    {
      unsigned  col = 0;

      /* We just want to list all the keys ...
       */
      while (nil != (k = [e nextObject]))
        {
          if (col + [k length] > 70)
            {
              [out appendString: @"\n"];
              col = 0;
            }
          if (col > 0)
            {
              [out appendString: @" "];
              col++;
            }
          [out appendString: k];
          col = [k length];
        }
      if (col > 0)
        {
          [out appendString: @"\n"];
        }
    }
  else
    {
      while (nil != (k = [e nextObject]))
        {
          EcDefaultRegistration     *d;

          if ([key length] > 0)
            {
              /* We want help for a specific key.
               */
              if ([key caseInsensitiveCompare: k] != NSOrderedSame)
                {
                  NSString  *pk = [prf stringByAppendingString: k];

                  if ([key caseInsensitiveCompare: pk] != NSOrderedSame)
                    {
                      continue; /* This is not the key we are looking for */
                    }
                }
            }

          [ecLock lock];
          d = [regDefs objectForKey: k];
          if (nil != d->type && nil != d->help)
            {
              /* If the help text is short enough, put it all on one line.
               */
              if ([d->help length] + max < 80)
                {
                  NSMutableString   *m;

                  m = [NSMutableString stringWithFormat: @"-%@%@ [%@] ",
                    prf, k, d->type];
                  while ([m length] < max)
                    {
                      [m appendString: @" "];
                    }
                  [out appendFormat: @"%@%@\n", m, d->help];
                }
              else
                {
                  [out appendFormat: @"-%@%@ [%@]\n  %@\n",
                    prf, k, d->type, d->help];
                }
            }
          [ecLock unlock];
        }
    }
  return out;
}

+ (NSDictionary*) merge: (NSDictionary*)d
{
  NSMutableDictionary   *m = AUTORELEASE([d mutableCopy]);
  NSEnumerator          *e;
  NSString              *k;

  if (nil == m)
    {
      m = [NSMutableDictionary dictionaryWithCapacity: [regDefs count]];
    }
  [ecLock lock];
  merged = YES;
  e = [regDefs keyEnumerator];
  while (nil != (k = [e nextObject]))
    {
      EcDefaultRegistration     *r = [regDefs objectForKey: k];

      if (nil != r->val && nil == [d objectForKey: k])
        {
          [m setObject: r->val forKey: k];
        }
    }
  [ecLock unlock];
  return m;
}

+ (void) registerDefault: (NSString*)name
            withTypeText: (NSString*)type
             andHelpText: (NSString*)help
                  action: (SEL)cmd
                   value: (id)value
{
  static NSCharacterSet *w = nil;
  EcDefaultRegistration *d;
  BOOL                  alreadyMerged;

  if (nil == w)
    {
      w = RETAIN([NSCharacterSet whitespaceAndNewlineCharacterSet]);
    }
  if ([type length] > 0)
    {
      type = [type stringByTrimmingSpaces];
      if ([type length] == 0)
        {
          type = nil;
        }
      else
        {
          NSUInteger            length = [type length];
          NSMutableString       *m = nil;

          while (length-- > 0)
            {
              unichar   u = [type characterAtIndex: length];

              if (u != ' ' && [w characterIsMember: u])
                {
                  if (nil == m)
                    {
                      m = AUTORELEASE([type mutableCopy]);
                      type = m;
                    }
                  [m replaceCharactersInRange: NSMakeRange(length, 1)
                                   withString: @" "];
                }
            }
        }
    }
  if ([help length] > 0)
    {
      help = [help stringByTrimmingSpaces];
      if ([help length] == 0)
        {
          help = nil;
        }
    }

  [ecLock lock];
  alreadyMerged = merged;
  d = [regDefs objectForKey: name];
  if (nil == d)
    {
      d = [EcDefaultRegistration new];
      ASSIGNCOPY(d->name, name);
      [regDefs setObject: d forKey: d->name];
      RELEASE(d);
    }
  ASSIGNCOPY(d->type, type);
  ASSIGNCOPY(d->help, help);
  if (0 != cmd)
    {
      d->cmd = cmd;
    }
  ASSIGNCOPY(d->val, value);
  [ecLock unlock];
  if (YES == alreadyMerged && nil != d->val)
    {
      [NSException raise: NSInternalInconsistencyException
                  format: @"default '%@' value '%@' registered too late",
        d->name, d->val];
    }
}

+ (void) showHelp
{
  GSPrintf(stderr, @"%@", [self listHelp: @""]);
}

- (void) dealloc
{
  RELEASE(name);
  RELEASE(type);
  RELEASE(help);
  RELEASE(obj);
  [super dealloc];
}

@end

