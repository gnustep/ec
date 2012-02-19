
#include <Foundation/Foundation.h>

#include "EcProcess.h"
#include "NSFileHandle+Printf.h"

#include <sys/signal.h>

#if WITH_READLINE
#  include <stdlib.h>
#  include <readline/readline.h>
#  include <readline/history.h>
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

@interface Console : EcProcess <RunLoopEvents, Console>
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
  id			server;
  int			pos;
}
- (void) connectionBecameInvalid: (NSNotification*)notification;
#if !WITH_READLINE
- (void) didRead: (NSNotification*)notification;
#endif
- (void) didWrite: (NSNotification*)notification;
- (void) doCommand: (NSMutableArray*)words;
- (void) timedOut;
@end




@implementation Console

- (BOOL) cmdIsClient
{
  return NO;	// Not a client of the Command server
}

- (void) cmdQuit: (int)sig
{
  [ochan puts: @"\nExiting\n"];

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
  exit(0);
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
	  [server release];
	  server = nil;
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
#if WITH_READLINE
  rl_callback_read_char();
#else
  NSLog(@"ERROR: this should not get called w/o readline: %s",
	__PRETTY_FUNCTION__);
#endif
}

- (void)processReadLine:(NSString *)_line
{
  NSAutoreleasePool *arp;
  NSMutableArray *words;
  NSEnumerator   *wordsEnum;
  NSString       *word;
  
  if (_line == nil)
    {
      [self cmdQuit: 0];
    }
  
  if ([_line length] == 0)
    {
      return;
    }

  arp = [[NSAutoreleasePool alloc] init];

  /* setup word array */
  
  words     = [NSMutableArray arrayWithCapacity:16];
  wordsEnum = [[_line componentsSeparatedByString:@" "] objectEnumerator];
  while ((word = [wordsEnum nextObject]) != nil)
    [words addObject:[word stringByTrimmingSpaces]];

  /* invoke server */
  
  [self doCommand:words];

  [arp release];
}

#if WITH_READLINE

- (char **)complete:(const char *)_text range:(NSRange)_range
{
  return NULL; /* no completion yet */
}

#endif

#if !WITH_READLINE
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

      [ichan readInBackgroundAndNotify];	/* Need more data.	*/
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
      cmd = @"";
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

#if !WITH_READLINE
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
#endif /* WITH_READLINE */
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

#define	add(C) { if (op - out >= len - 1) { int i = op - out; len += 128; [d setLength: len]; out = [d mutableBytes]; op = &out[i];} *op++ = C; }

- (oneway void) information: (NSString*)s
{
  int		ilen = [s cStringLength] + 1;
  int		len = (ilen + 4) * 2;
  char		buf[ilen];
  const char	*ip = buf;
  NSMutableData	*d = [NSMutableData dataWithCapacity: len];
  char		*out = [d mutableBytes];
  char		*op = out;
  char		c;

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
}

#define	NUMARGS	3
- (id) init
{
  NSDictionary	*appDefaults;
  id		objects[NUMARGS];
  id		keys[NUMARGS];

  keys[0] = @"BSEffectiveUser";
  objects[0] = @"";
  keys[1] = @"BSDaemon";
  objects[1] = @"NO";		/* Never run as daemon */
  keys[2] = @"BSNoDaemon";
  objects[2] = @"YES";		/* Never run as daemon */

  appDefaults = [NSDictionary dictionaryWithObjects: objects
					    forKeys: keys
					      count: NUMARGS];
  self = [super initWithDefaults: appDefaults];
  if (self)
    {
      NSUserDefaults	*defs = [self cmdDefaults];

      local = [[[NSHost currentHost] name] retain];
      name = [defs stringForKey: @"ControlName"];
      if (name == nil)
	{
	  name = @"Control";
	}
      host = [defs stringForKey: @"ControlHost"];
      if (host == nil)
	{
	  host = @"*";
	}
      if ([host length] == 0)
	{
	  host = local;
	}
      [host retain];
      rnam = [[NSString stringWithFormat: @"%@:%@", user, local] retain];

      data = [[NSMutableData alloc] init];
      ichan = [[NSFileHandle fileHandleWithStandardInput] retain];
      ochan = [[NSFileHandle fileHandleWithStandardOutput] retain];

#if !WITH_READLINE
      [[NSNotificationCenter defaultCenter] addObserver: self
		     selector: @selector(didRead:)
			 name: NSFileHandleReadCompletionNotification
		       object: (id)ichan];
      [ochan puts: @"Enter your username: "];
      [ichan readInBackgroundAndNotify];
#endif
    }
  return self;
}

- (void) timedOut
{
  return;
}

/* readline handling */

#if WITH_READLINE

/* readline callbacks have no context, so we need this one ... */
static Console *rlConsole = nil;

static void readlineReadALine(char *_line)
{
  NSString *s = _line ? [[NSString alloc] initWithCString:_line] : nil;
  
  [rlConsole processReadLine:s];
  
  if (_line != NULL && strlen(_line) > 0)
    {
      add_history(_line);
    }
  
  DESTROY(s);
}

static char **consoleCompleter(const char *text, int start, int end)
{
  return [rlConsole complete:text range:NSMakeRange(start, end - start)];
}

- (void)activateReadline {
  rlConsole = self;
  
  /* setup readline */

  rl_readline_name = "Console";
  rl_attempted_completion_function = consoleCompleter;
  
  rl_callback_handler_install("" /* prompt */, readlineReadALine);
  atexit(rl_callback_handler_remove);
  
  /* register in runloop */
  
  [[NSRunLoop currentRunLoop] addEvent:(void*)(uintptr_t)0 type:ET_RDESC 
			      watcher:self forMode:NSDefaultRunLoopMode];
}

- (void)deactivateReadline
{
  [[NSRunLoop currentRunLoop] removeEvent:(void*)(uintptr_t)0 type:ET_RDESC 
			      forMode:NSDefaultRunLoopMode all:YES];

  rl_callback_handler_remove();
  rlConsole = nil;
}

- (void) setupConnectionr
{
  while (self->server == nil)
    {
      NSString *reject;
      char lUser[128], *llUser;

      /* read username */
      
      printf("Login: ");
      fflush(stdout);
      
      llUser = fgets(lUser, sizeof(lUser), stdin);
      if (llUser == NULL || strlen(llUser) == 0)
	{
	  /* user pressed ctrl-D, just exit */
	  exit(0);
	}
      
      llUser[strlen(llUser) - 1] = '\0';
      if (strlen(llUser) < 1)
	{
	  /* user just pressed enter, retry */
	  continue;
	}
      
      /* read password (glibc documentation says not to use getpass?) */
      
      const char *lPassword = getpass("Password: ");
      if (lPassword == NULL) {
	NSLog(@"Could not read password: %s", strerror(errno));
	exit(1);
      }
      
      
      /* setup connection to server */
      
      self->server =
	[[NSConnection rootProxyForConnectionWithRegisteredName: name
		       host: host
		       usingNameServer:
			 [NSSocketPortNameServer sharedInstance]] retain];
      if (self->server == nil)
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
      
      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(connectionBecameInvalid:)
	name: NSConnectionDidDieNotification
	object: (id)[self->server connectionForProxy]];
      [server setProtocolForProxy: @protocol(Control)];
      [[server connectionForProxy] setDelegate: self];
      
      /* attempt login */
      
      self->user = [[NSString alloc] initWithCString:lUser];
      self->pass = [[NSString alloc] initWithCString:lPassword];
      self->rnam = 
	[[NSString alloc] initWithFormat:@"%@:%@", self->user, self->local];
      
      reject = [self->server registerConsole:self 
		    name:self->rnam pass:self->pass];
      
      /* connection failed */
      
      if (reject != nil) {
	[ochan puts:
		 [NSString stringWithFormat: 
			     @"Connection attempt rejected - %@\n", reject]];
	
	[[NSNotificationCenter defaultCenter] 
	  removeObserver:self
	  name: NSConnectionDidDieNotification
	  object: (id)[self->server connectionForProxy]];
	
	DESTROY(self->pass);
	DESTROY(self->user);
	DESTROY(self->rnam);
	DESTROY(self->server);
      }
    }
}

#endif /* WITH_READLINE */

@end


void
inner_main()
{
  extern NSString	*cmdVersion(NSString*);
  Console		*console;
  NSAutoreleasePool	*arp;

  arp = [[NSAutoreleasePool alloc] init];
  cmdVersion(@"$Date: 2012-02-13 08:11:49 +0000 (Mon, 13 Feb 2012) $ $Revision: 65934 $");

  console = [Console new];
  [arp release];

  arp = [[NSAutoreleasePool alloc] init];

#if WITH_READLINE
  [console setupConnection];
  [console activateReadline];
#endif

  /* Let standard signals simply kill the Console
   */
  signal(SIGHUP, SIG_DFL);
  signal(SIGINT, SIG_DFL);
  signal(SIGTERM, SIG_DFL);

  [[NSRunLoop currentRunLoop] run];

#if WITH_READLINE
  [console deactivateReadline];
#endif

  [console release];
  [arp release];
  exit(0);
}

int
main(int argc, char *argv[])
{
  inner_main();
  return 0;
}
