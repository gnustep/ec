
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

#import <Foundation/Foundation.h>

#import "EcProcess.h"
#import "EcHost.h"
#import "NSFileHandle+Printf.h"

#import "config.h"

#if defined(HAVE_LIBREADLINE)
#  include <stdlib.h>
#  include <unistd.h>
#  include <readline/readline.h>
#  include <readline/history.h>
#endif

#if defined(HAVE_READPASSPHRASE_H)
#  include <readpassphrase.h>
#elif defined(HAVE_BSD_READPASSPHRASE_H)
#  include <bsd/readpassphrase.h>
#endif
static BOOL commandIsRepeat (NSString *string)
{
  switch ([string length])
    {
      case 1: return [string isEqualToString: @"r"];
      case 2: return [string isEqualToString: @"re"];
      case 3: return [string isEqualToString: @"rep"];
      case 4: return [string isEqualToString: @"repe"];
      case 5: return [string isEqualToString: @"repea"];
      case 6: return [string isEqualToString: @"repeat"];
      default: return NO;
    }
}

@interface EcConsole : EcProcess <RunLoopEvents, Console>
{
  NSFileHandle		*ichan;
  NSFileHandle		*ochan;
  NSMutableData		*data;
  NSTimer		*timer;
  NSString		*local;
  NSString		*host;
  NSString		*name;
  NSString		*user;
  NSString		*pass;
  NSString		*rnam;
  NSRegularExpression   *want;
  NSRegularExpression   *fail;
  id			server;
  int			pos;
  BOOL                  interactive;
}
- (void) connectionBecameInvalid: (NSNotification*)notification;
#if defined(HAVE_LIBREADLINE)
- (void) activateReadline;
- (void) deactivateReadline;
- (void) setupConnection;
#else
- (void) didRead: (NSNotification*)notification;
#endif
- (void) didWrite: (NSNotification*)notification;
- (void) doCommand: (NSMutableArray*)words;
- (void) timedOut;
- (void) waitEnded: (NSTimer*)t;
@end




@implementation EcConsole

- (BOOL) cmdIsClient
{
  return NO;	// Not a client of the Command server
}

- (oneway void) cmdQuit: (NSInteger)sig
{
  [timer invalidate];
  timer = nil;

  /* Attempt to output an exit message, but our tereminal may have gone away
   * so we ignore exceptions during that.
   */
  NS_DURING
    [ochan puts: @"\nExiting\n"];
  NS_HANDLER
  NS_ENDHANDLER

#if defined(HAVE_LIBREADLINE)
  [self deactivateReadline];
#endif

  if (server)
    {
      id	con = [(NSDistantObject*)server connectionForProxy];

      [[NSNotificationCenter defaultCenter] removeObserver: self
				      name: NSConnectionDidDieNotification
				    object: con];
      NS_DURING
	{
	  [server unregister: self];
	}
      NS_HANDLER
	{
	  NSLog(@"Exception unregistering from Control: %@", localException);
	}
      NS_ENDHANDLER
      [con invalidate];
      DESTROY(server);
    }

  if (ichan)
    {
      [[NSNotificationCenter defaultCenter] removeObserver: self
			 name: NSFileHandleReadCompletionNotification
		       object: (id)ichan];
      if ([ichan fileDescriptor] >= 0)
	{
	  [ichan closeFile];
	}
      [ichan release];
      ichan = nil;
    }
  if (ochan)
    {
      if ([ochan fileDescriptor] >= 0)
	{
	  [ochan closeFile];
	}
      [ochan release];
      ochan = nil;
    }
  [super cmdQuit: sig];
}

- (void) connectionBecameInvalid: (NSNotification*)notification
{
  id conn = [notification object];

  [[NSNotificationCenter defaultCenter] removeObserver: self
				  name: NSConnectionDidDieNotification
				object: conn];
  if ([conn isKindOfClass: [NSConnection class]])
    {
      if (server && [(NSDistantObject*)server connectionForProxy] == conn)
	{
          DESTROY(server);
	  NSLog(@"Lost connection to Control server.");
	  [self cmdQuit: 0];
	}
    }
}

- (void) dealloc
{
  [rnam release];
  [user release];
  [pass release];
  [host release];
  [name release];
  [local release];
  [want release];
  [fail release];
  [data release];
  if (timer)
    {
      [timer invalidate];
      timer = nil;
    }
  [self cmdQuit: 0];
  [super dealloc];
}

- (void) receivedEvent: (void *)descriptorData
  type: (RunLoopEventType)type
  extra: (void*)extra
  forMode: (NSString*)mode
{
#if defined(HAVE_LIBREADLINE)
  rl_callback_read_char();
#else
  NSLog(@"ERROR: this should not get called w/o readline: %s",
    __PRETTY_FUNCTION__);
#endif
}

#if defined(HAVE_LIBREADLINE)

- (char **)complete:(const char *)_text range:(NSRange)_range
{
  return NULL; /* no completion yet */
}

#endif

#if !defined(HAVE_LIBREADLINE)
- (void) didRead: (NSNotification*)notification
{
  NSDictionary	*userInfo = [notification userInfo];
  NSData	*d;

  d = [[userInfo objectForKey: NSFileHandleNotificationDataItem] retain];

  if (d == nil || [d length] == 0)
    {
      if (d != nil)
	{
	  [d release];
	}
      [self cmdQuit: 0];
    }
  else
    {
      char	*bytes;
      int	len;
      int	eol;
      int	done = 0;

      [data appendData: d];
      [d release];
      bytes = (char*)[data mutableBytes];
      len = [data length];

      for (eol = 0; eol < len; eol++)
	{
	  if (bytes[eol] == '\r' || bytes[eol] == '\n')
	    {
	      char		*word = bytes;
	      char		*end = word;
	      NSMutableArray	*a;

	      a = [NSMutableArray arrayWithCapacity: 1];

	      bytes[eol++] = '\0';
	      while (eol < len && isspace(bytes[eol]))
		{
		  eol++;
		}
	      done = eol;

	      while (end && *end)
		{
		  word = end;
		  while (*word && isspace(*word))
		    {
		      word++;
		    }
		  end = word;

		  if (*word == '"' || *word == '\'')
		    {
		      char	term = *word;
		      char	*ptr;

		      end = ++word;
		      ptr = end;

		      while (*end)
			{
			  if (*end == term)
			    {
			      end++;
			      break;
			    }
			  if (*end == '\\')
			    {
			      end++;
			      switch (*end)
				{
				  case '\\': 	*ptr++ = '\\';	break;
				  case 'b': 	*ptr++ = '\b';	break;
				  case 'f': 	*ptr++ = '\f';	break;
				  case 'n': 	*ptr++ = '\n';	break;
				  case 'r': 	*ptr++ = '\r';	break;
				  case 't': 	*ptr++ = '\t';	break;
				  case 'x': 
				    {
				      int	val = 0;

				      if (isxdigit(end[1]))
					{
					  end++;
					  val <<= 4;
					  if (islower(*end))
					    {
					      val += *end - 'a' + 10;
					    }
					  else if (isupper(*end))
					    {
					      val += *end - 'A' + 10;
					    }
					  else
					    {
					      val += *end - '0';
					    }
					}
				      if (isxdigit(end[1]))
					{
					  end++;
					  val <<= 4;
					  if (islower(*end))
					    {
					      val += *end - 'a' + 10;
					    }
					  else if (isupper(*end))
					    {
					      val += *end - 'A' + 10;
					    }
					  else
					    {
					      val += *end - '0';
					    }
					}
				      *ptr++ = val;
				    }
				    break;

				  case '0': 
				    {
				      int	val = 0;

				      if (isdigit(end[1]))
					{
					  end++;
					  val <<= 3;
					  val += *end - '0';
					}
				      if (isdigit(end[1]))
					{
					  end++;
					  val <<= 3;
					  val += *end - '0';
					}
				      if (isdigit(end[1]))
					{
					  end++;
					  val <<= 3;
					  val += *end - '0';
					}
				      *ptr++ = val;
				    }
				    break;

				  default: 	*ptr++ = *end;	break;
				}
			      if (*end)
				{
				  end++;
				}
			    }
			  else
			    {
			      *ptr++ = *end++;
			    }
			}
		      *ptr = '\0';
		    }
		  else
		    {
		      while (*end && !isspace(*end))
			{
			  if (isupper(*end))
			    {
			      *end = tolower(*end);
			    }
			  end++;
			}
		    }

		  if (*end)
		    {
		      *end++ = '\0';
		    }
		  else
		    {
		      end = 0;
		    }

		  if (word && *word)
		    {
		      [a addObject: [NSString stringWithCString: word]];
		    }
		}

	      [self doCommand: a];
	      if (ichan == nil)
		{
		  return;		/* Quit while doing command.	*/
		}
	    }
	}

      if (done > 0)
	{
	  memcpy(bytes, &bytes[done], len - done);
	  [data setLength: len - done];
	}

      if (YES == interactive)
        {
          [ichan readInBackgroundAndNotify];	/* Need more data.	*/
        }
    }
}
#endif

- (void) didWrite: (NSNotification*)notification
{
  NSDictionary	*userInfo = [notification userInfo];
  NSString	*e;

  e = [userInfo objectForKey: GSFileHandleNotificationError];
  if (e)
    {
      [self cmdQuit: 0];
    }
}

- (void) doCommand: (NSMutableArray*)words
{
  NSString	*cmd;
  static NSArray	*pastWords = nil;

  if (words == nil || [words count] == 0)
    {
      return;
    }
  else
    {
      cmd = [words objectAtIndex: 0];
    }
  if ([cmd isEqual: @"quit"] && [words count] == 1)
    {
      [self cmdQuit: 0];
      return;
    }

#if !defined(HAVE_LIBREADLINE)
  if (user == nil)
    {
      if ([cmd length] > 0)
	{
	  user = [cmd retain];
	  [ochan puts: @"Enter your password: "];
	}
      else
	{
	  [ochan puts: @"Enter your username: "];
	}
    }
  else if (pass == nil)
    {
      if ([cmd length] > 0)
	{
	  pass = [cmd retain];
	  server = [NSConnection rootProxyForConnectionWithRegisteredName: name
	    host: host
	    usingNameServer: [NSSocketPortNameServer sharedInstance]];
	  if (server == nil)
	    {
	      if ([host isEqual: @"*"])
		{
		  [ochan printf: @"Unable to connect to %@ on any host.\n",
		    name];
		}
	      else
		{
		  [ochan printf: @"Unable to connect to %@ on %@.\n",
		    name, host];
		}
	      [self cmdQuit: 0];
	      return;
	    }
	  else
	    {
	      NSString	*reject;

	      [rnam release];
	      rnam = [NSString stringWithFormat: @"%@:%@", user, local];
	      [rnam retain];

	      [server retain];
	      [server setProtocolForProxy: @protocol(Control)];
	      [[NSNotificationCenter defaultCenter]
		  addObserver: self
		  selector: @selector(connectionBecameInvalid:)
		  name: NSConnectionDidDieNotification
		  object: (id)[server connectionForProxy]];
	      [[server connectionForProxy] setDelegate: self];

	      reject = [server registerConsole: self
					  name: rnam
					  pass: pass];

	      if (reject == nil)
		{
		  [words removeAllObjects];
		  [words addObject: @"list"];
		  [words addObject: @"consoles"];
		  [server command: [NSPropertyListSerialization
		    dataFromPropertyList: words
		    format: NSPropertyListBinaryFormat_v1_0
		    errorDescription: 0] from: rnam];
		}
	      else
		{
		  [pass release];
		  pass = nil;
		  [user release];
		  user = nil;
		  [ochan puts: [NSString stringWithFormat: 
		    @"Connection attempt rejected - %@\n", reject]];
		  [ochan puts: @"Enter your username: "];
		}
	    }
	}
      else
	{
	  [ochan puts: @"Enter your password: "];
	}
    }
  else
#endif /* defined(HAVE_LIBREADLINE) */
  if (commandIsRepeat(cmd))
    {
      if (pastWords == nil)
	{
	  [ochan puts: @"No command to repeat.\n"];
	}
      else
	{
	  [ochan printf: @"Repeating command `%@' -\n", 
		 [pastWords componentsJoinedByString: @" "]];
	  [server command: [NSPropertyListSerialization
	    dataFromPropertyList: pastWords
	    format: NSPropertyListBinaryFormat_v1_0
	    errorDescription: 0] from: rnam];
	}
    }
  else
    {
      ASSIGN(pastWords, words);
      [server command: [NSPropertyListSerialization
	dataFromPropertyList: words
	format: NSPropertyListBinaryFormat_v1_0
	errorDescription: 0] from: rnam];
    }
}

- (void) doLine:(NSString *)_line
{
  NSAutoreleasePool *arp;
  NSMutableArray *words;
  NSEnumerator   *wordsEnum;
  NSString       *word;
  
  if (_line == nil)
    {
      [self cmdQuit: 0];
    }
  
  _line = [_line stringByTrimmingSpaces];       // Remove trailing newline
  if ([_line length] == 0)
    {
      return;
    }

  arp = [[NSAutoreleasePool alloc] init];

  /* setup word array */
  
  words = [NSMutableArray arrayWithCapacity: 16];
  wordsEnum = [[_line componentsSeparatedByString: @" "] objectEnumerator];
  while ((word = [wordsEnum nextObject]) != nil)
    {
      word = [word stringByTrimmingSpaces];
      if ([word length] > 0)
        {
          [words addObject: word];
        }
    }

  /* invoke server */
  
  [self doCommand: words];

  [arp release];
}

#define	add(C) { if (op - out >= len - 1) { int i = op - out; len += 128; [d setLength: len]; out = [d mutableBytes]; op = &out[i];} *op++ = C; }

- (oneway void) information: (NSString*)s
{
  int		ilen = [s cStringLength] + 1;
  int		len = (ilen + 4) * 2;
  char		buf[ilen];
  const char	*ip = buf;
  NSMutableData	*d;
  char		*out;
  char		*op;
  char		c;

  d = [NSMutableData dataWithCapacity: len];
  out = [d mutableBytes];
  op = out;

  [s getCString: buf];
  buf[ilen-1] = '\0';
  [d setLength: len];
  if (pos)
    {
      add('\n');
      pos = 0;
    }
  while (*ip)
    {
      switch (*ip)
	{
	  case '\r': 
	  case '\n': 
	    pos = 0;
	    add(*ip);
	    break;
	      
	  case '\t': 
	    if (pos >= 72)
	      {
		pos = 0;
		add('\n');
	      }
	    else
	      {
		do
		  {
		    add(' ');
		    pos++;
		  }
		while (pos % 8);
	      }
	    break;

	  default: 
	    c = *ip;
	    if (c < ' ')
	      {
		c = ' ';
	      }
	    if (c > 126)
	      {
		c = ' ';
	      }
	    if (c == ' ')
	      {
		int	l = 0;

		while (ip[l] && isspace(ip[l])) l++;
		while (ip[l] && !isspace(ip[l])) l++;
		l--;
		if ((pos + l) >= 80 && l < 80)
		  {
		    add('\n');
		    pos = 0;
		  }
		else
		  {
		    add(' ');
		    pos++;
		  }
	      }
	    else
	      {
		add(c);
		pos++;
	      }
	    break;
	}
      ip++;
    }
  [d setLength: op - out];
  [ochan writeData: d];

  /* If we are waiting for a regular expression ... check to see if it is
   * found and then end with a success status.
   */
  if (nil != want)
    {
      NSRange   r;

      r = [want rangeOfFirstMatchInString: s
                                  options: 0
                                    range: NSMakeRange(0, [s length])];
      if (r.length > 0)
        {
          [self cmdQuit: 0];
          return;
        }
    }
  if (nil != fail)
    {
      NSRange   r;

      r = [fail rangeOfFirstMatchInString: s
                                  options: 0
                                    range: NSMakeRange(0, [s length])];
      if (r.length > 0)
        {
          [self cmdQuit: 3];    // Matched failure message ... status 3
          return;
        }
    }
}

#define	NUMARGS	1
- (id) init
{
  NSDictionary	*appDefaults;
  id		objects[NUMARGS];
  id		keys[NUMARGS];

  keys[0] = @"Daemon";
  objects[0] = @"NO";		/* Never run as daemon */

  appDefaults = [NSDictionary dictionaryWithObjects: objects
					    forKeys: keys
					      count: NUMARGS];
  return [self initWithDefaults: appDefaults];
}

- (id) initWithDefaults: (NSDictionary*)defs
{
  self = [super initWithDefaults: defs];
  if (self)
    {
      NSUserDefaults	*defs = [self cmdDefaults];
      NSDictionary      *env = [[NSProcessInfo processInfo] environment];
      NSString          *s;

      interactive = YES;
      local = [[[NSHost currentHost] wellKnownName] retain];
      name = [defs stringForKey: @"ControlName"];
      if (name == nil)
	{
	  name = @"Control";
	}
      if (nil != (host = [NSHost controlWellKnownName]))
        {
          host = [[NSHost hostWithWellKnownName: host] name];
        }
      if (nil == host)
	{
	  host = @"*";
	}
      if ([host length] == 0)
	{
	  host = local;
	}
      [host retain];

      /* If the User and Pass arguments are supplied, login directly.
       */
      user = [[defs stringForKey: @"User"] retain];
      if (nil == user)
        {
          user = [[env objectForKey: @"ConsoleUser"] retain];
        }
      pass = [[defs stringForKey: @"Pass"] retain];
      if (nil == pass)
        {
          pass = [[env objectForKey: @"ConsolePass"] retain];
        }

      rnam = [[NSString stringWithFormat: @"%@:%@", user, local] retain];

      if (user && pass)
        {
          interactive = NO;
	  server = [NSConnection rootProxyForConnectionWithRegisteredName: name
	    host: host
	    usingNameServer: [NSSocketPortNameServer sharedInstance]];
	  if (nil == server)
	    {
	      if ([host isEqual: @"*"])
		{
		  GSPrintf(stderr, @"Unable to connect to %@ on any host.\n",
		    name);
		}
	      else
		{
		  GSPrintf(stderr, @"Unable to connect to %@ on %@.\n",
		    name, host);
		}
	      [self cmdQuit: 1];
	      DESTROY(self);
	    }
	  else
	    {
	      NSString	*reject;

	      [server retain];
	      [server setProtocolForProxy: @protocol(Control)];
	      [[NSNotificationCenter defaultCenter]
		  addObserver: self
		  selector: @selector(connectionBecameInvalid:)
		  name: NSConnectionDidDieNotification
		  object: (id)[server connectionForProxy]];
	      [[server connectionForProxy] setDelegate: self];

	      reject = [server registerConsole: self
					  name: rnam
					  pass: pass];

	      if (reject != nil)
		{
		  GSPrintf(stderr, @"Login rejected for %@ on %@.\n",
		    name, host);
                  [self cmdQuit: 1];
		  DESTROY(self);
		}
	    }

          s = [defs stringForKey: @"Line"];
          if (0 == [s length])
            {
              s = [env objectForKey: @"ConsoleLine"];
            }
          if (nil != self && nil != s)
            {
              [self doLine: s];

              /* Now, we may delay for 'Wait' seconds looking for a response
               * containing the 'Want' pattern or the 'Fail' pattern.
               */
              s = [defs stringForKey: @"Want"];
              if (0 == [s length])
                {
                  s = [env objectForKey: @"ConsoleWant"];
                }
              if ([s length] > 0)
                {
                  want = [[NSRegularExpression alloc] initWithPattern: s
                                                              options: 0
                                                                error: 0];
                }
              s = [defs stringForKey: @"Fail"];
              if (0 == [s length])
                {
                  s = [env objectForKey: @"ConsoleFail"];
                }
              if ([s length] > 0)
                {
                  fail = [[NSRegularExpression alloc] initWithPattern: s
                                                              options: 0
                                                                error: 0];
                }
              if (nil != want || nil != fail)
                {
                  NSTimeInterval    ti;

                  s = [defs stringForKey: @"Wait"];
                  if (0 == [s length])
                    {
                      s = [env objectForKey: @"ConsoleWait"];
                      if (0 == [s length])
                        {
                          s = @"5";
                        }
                    }
                  ti = [s floatValue];
                  timer = [NSTimer scheduledTimerWithTimeInterval: ti
                    target: self selector: @selector(waitEnded:)
                    userInfo: nil repeats: NO];

                  if (YES == [defs boolForKey: @"Quiet"]
                    || YES == [[env objectForKey: @"ConsoleQuiet"] boolValue])
                    {
                      /* If we don't want any output, return without
                       * setting the output channel up.
                       */
                      return self;
                    }
                }
              else
                {
                  /* No waiting ... quit immediately.
                   */
                  [self cmdQuit: 0];
                  DESTROY(self);
                }
            }
        }

      if (nil != self)
        {
          data = [[NSMutableData alloc] init];
          ichan = [[NSFileHandle fileHandleWithStandardInput] retain];
          ochan = [[NSFileHandle fileHandleWithStandardOutput] retain];
#if !defined(HAVE_LIBREADLINE)
          if (YES == interactive)
            {
              [[NSNotificationCenter defaultCenter] addObserver: self
                             selector: @selector(didRead:)
                                 name: NSFileHandleReadCompletionNotification
                               object: (id)ichan];
              [ochan puts: @"Enter your username: "];
              [ichan readInBackgroundAndNotify];
            }
#endif
        }
    }
  return self;
}

- (int) ecRun
{
  NSRunLoop	*loop;

#if defined(HAVE_LIBREADLINE)
  if (YES == interactive)
    {
      [self setupConnection];
      [self activateReadline];
    }
#endif

  loop = [NSRunLoop currentRunLoop];
  while (YES == [loop runMode: NSDefaultRunLoopMode beforeDate: nil])
    {
      if (0 != [self cmdSignalled])
	{
	  [self cmdQuit: [self cmdSignalled]];
	}
    }

#if defined(HAVE_LIBREADLINE)
  if (YES == interactive)
    {
      [self deactivateReadline];
    }
#endif
  return 0;
}

- (void) timedOut
{
  return;               // Ignore EcProcess timeouts
}

- (void) waitEnded: (NSTimer*)t
{
  [self cmdQuit: 2];    // Timeout waiting for regex has status 2
}

/* readline handling */

#if defined(HAVE_LIBREADLINE)

/* readline callbacks have no context, so we need this one ... */
static EcConsole *rlConsole = nil;

static void
readlineReadALine(char *_line)
{
  NSString *s = _line ? [[NSString alloc] initWithCString: _line] : nil;
  
  [rlConsole doLine: s];
  
  if (_line != NULL && strlen(_line) > 0)
    {
      add_history(_line);
    }
  
  DESTROY(s);
}

static char **
consoleCompleter(const char *text, int start, int end)
{
  return [rlConsole complete: text range: NSMakeRange(start, end - start)];
}

- (void) activateReadline
{
  rlConsole = self;
  
  /* setup readline */

  rl_readline_name = "Console";
  rl_attempted_completion_function = consoleCompleter;
  
  rl_callback_handler_install("" /* prompt */, readlineReadALine);
  atexit(rl_callback_handler_remove);
  
  /* register in runloop */
  
  [[NSRunLoop currentRunLoop] addEvent: (void*)(uintptr_t)0
				  type: ET_RDESC 
			       watcher: self
			       forMode: NSDefaultRunLoopMode];
}

- (void) deactivateReadline
{
  [[NSRunLoop currentRunLoop] removeEvent: (void*)(uintptr_t)0
				     type: ET_RDESC 
				  forMode: NSDefaultRunLoopMode
				      all: YES];

  rl_callback_handler_remove();
  rlConsole = nil;
}

- (void) setupConnection
{
  while (self->server == nil)
    {
      NSString	*u;
      NSString	*p;
      NSString	*reject;
      char 	buf[128], *line;

      /* read username */
      
      printf("Login: ");
      fflush(stdout);
      
      line = fgets(buf, sizeof(buf), stdin);
      if (0 == line)
	{
	  /* user pressed ctrl-D, just exit */
	  exit(0);
	}
      line[strlen(line) - 1] = '\0';

      u = [[NSString stringWithCString: line] stringByTrimmingSpaces];
      if ([u length] == 0)
	{
	  /* user just pressed enter, retry */
	  continue;
	}
      if ([u caseInsensitiveCompare: @"quit"] == NSOrderedSame)
	{
	  [self cmdQuit: 0];
	}
#ifndef HAVE_READPASSPHRASE
      /* read password (glibc documentation says not to use getpass?) */
      
      line = getpass("Password: ");
      if (0 == line)
	{
	  NSLog(@"Could not read password: %s", strerror(errno));
	  exit(1);
	}
#else
      line = readpassphrase("Password: ", &buf[0], 128, RPP_ECHO_OFF);
      if (NULL == line)
        {
          NSLog(@"Could not read password");
          exit(1);
        }
#endif
      p = [[NSString stringWithCString: line] stringByTrimmingSpaces];
      if ([p caseInsensitiveCompare: @"quit"] == NSOrderedSame)
	{
	  [self cmdQuit: 0];
	}

      /* setup connection to server */
      
      self->server = [[NSConnection
	rootProxyForConnectionWithRegisteredName: name
	host: host
	usingNameServer: [NSSocketPortNameServer sharedInstance]] retain];
      if (self->server == nil)
	{
	  if ([host isEqual: @"*"])
	    {
	      [ochan printf: @"Unable to connect to %@ on any host.\n", name];
	    }
	  else
	    {
	      [ochan printf: @"Unable to connect to %@ on %@.\n", name, host];
	    }
	  
	  [self cmdQuit: 0];
	  return;
	}
      
      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(connectionBecameInvalid:)
	name: NSConnectionDidDieNotification
	object: (id)[self->server connectionForProxy]];
      [server setProtocolForProxy: @protocol(Control)];
      [[server connectionForProxy] setDelegate: self];
      
      /* attempt login */
      
      self->user = [u retain];
      self->pass = [p retain];
      self->rnam = 
	[[NSString alloc] initWithFormat: @"%@:%@", self->user, self->local];
      
      reject = [self->server registerConsole: self 
				        name: self->rnam
					pass: self->pass];
      
      /* connection failed */
      
      if (reject != nil)
	{
	  [ochan puts: [NSString stringWithFormat: 
	     @"Connection attempt rejected - %@\n", reject]];
	  
	  [[NSNotificationCenter defaultCenter] 
	    removeObserver: self
	    name: NSConnectionDidDieNotification
	    object: (id)[self->server connectionForProxy]];
	  
	  DESTROY(self->pass);
	  DESTROY(self->user);
	  DESTROY(self->rnam);
	  DESTROY(self->server);
	}
    }
}

#endif /* defined(HAVE_LIBREADLINE) */

@end
