
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
#import <GNUstepBase/GSMime.h>

#import "EcProcess.h"
#import "EcAlerter.h"
#import "NSFileHandle+Printf.h"

#include <regex.h>

@interface Regex: NSObject
{
  regex_t	regex;
  BOOL		built;
}
- (id) initWithString: (NSString*)pattern;
- (NSString*) match: (NSString*)string;
@end

@implementation	Regex
- (void) dealloc
{
  if (built == YES)
    {
      built = NO;
      regfree(&regex);
    }
  [super dealloc];
}

- (id) initWithString: (NSString*)pattern
{
  if (regcomp(&regex, [pattern UTF8String], REG_EXTENDED) != 0)
    {
      NSLog(@"Failed to compile regex - '%@'", pattern);
      DESTROY(self);
    }
  else
    {
      built = YES;
    }
  return self;
}

- (NSString*) match: (NSString*)string
{
  regmatch_t	matches[2];
  const char	*str = [string UTF8String];

  if (regexec(&regex, str, 1, matches, 0) != 0)
    {
      return nil;
    }
  else
    {
      int	l = matches[0].rm_eo - matches[0].rm_so;
      char	b[l+1];

      memcpy(b, &str[matches[0].rm_so], l);
      b[l] = '\0';
      return [NSString stringWithUTF8String: b];
    }
}
@end

static NSMutableString *
replaceFields(NSDictionary *fields)
{
  NSMutableString	*m;

  m = [[[fields objectForKey: @"Replacement"] mutableCopy] autorelease];
  if (nil != m)
    {
      NSEnumerator	*e;
      NSString		*k;

      e = [fields keyEnumerator];
      while (nil != (k = [e nextObject]))
	{
	  if (NO == [k isEqualToString: @"Replacement"])
	    {
	      NSString	*v;

	      v = [[fields objectForKey: k] description];
	      k = [NSString stringWithFormat: @"{%@}", k];
	      [m replaceOccurrencesOfString: k
				 withString: v
				    options: NSLiteralSearch
				      range: NSMakeRange(0, [m length])];
	    }
	}
    }
  return m;
}

/**
 * <p>This class handles delivery and logging of error and alert messages
 * to the people who should be monitoring the system.  It is used by the
 * Control server (to which all these messages are delivered) and
 * implements a simple rule based mechanism for managing final
 * delivery of the messages.
 * </p>
 * <p>The configured rules are compared against each message and any
 * actions associated with a matching rule are performed.<br />
 * The matching fields in each rule are -
 * </p>
 * <deflist>
 *   <term>Host</term>
 *   <desc>An extended regular expression to match the name of the host
 *   machine on which the message originated (possibly just the host name).
 *   If this is not specified, messages from any host may match.
 *   </desc>
 *   <term>Server</term>
 *   <desc>An extended regular expression to match the name of the server
 *   process from which the message originated (possibly just the server
 *   name).
 *   If this is not specified, messages from any server may match.
 *   </desc>
 *   <term>Type</term>
 *   <desc>The type of message ... <em>Error</em> or <em>Alert</em>.
 *   If this is not specified, messages of any type may match.
 *   </desc>
 *   <term>Pattern</term>
 *   <desc>An extended regular expression used to match the main text
 *   of the message.  See the posix regcomp documentation for details
 *   of enhanced posix regular expressions.  If this is not present,
 *   any message text will match.
 *   </desc>
 *   <term>Stop</term>
 *   <desc>A boolean (YES or NO) saying whether rule matching should
 *   stop if this rule is matched.  If this is NO (the default) then
 *   after any action associated with this rule is performed, matching
 *   continues at the next rule.<br />
 *   <em>Don't use this option injudiciusly.  Try to write your pattern
 *   matching rules so that most messages match a single rule to map
 *   them to a nice readable version, and also match a default rule to
 *   log full details to the technical team.</em>
 *   </desc>
 *   <term>Flush</term>
 *   <desc>A boolean (YES or NO) saying whether stored messages due to
 *   be sent out later should be sent out immediately after processing
 *   this rule.  This is useful in the event that some time critical
 *   message must be sent, but should not normally be used.<br />
 *   As a special case, instead of the boolean value, this may take
 *   the value <em>Email</em> or <em>Sms</em> indicating that a flush
 *   should be performed, but only on the specified type of messages.<br />
 *   <strong>beware</strong> The batching mechanism exists to prevent
 *   a single problem triggering floods of messages.  You should only
 *   override it using <em>Flush</em> where you are <strong>sure</strong>
 *   that messages triggering the flush will be infrequent.
 *   </desc>
 * </deflist>
 * <p>There are two additional fields <em>Extra1</em> and <em>Extra2</em>
 * which are matched against the message.  These patterns do not effect
 * whether the action of the rule is executed or not, but the text matched
 * is made available for substitution into replacement messages.
 * </p>
 * <p>When a match is found the full message is normally sent to all the
 * destinations listed in the <em>Email</em> and <em>Sms</em> arrays in
 * the rule, and logged to all the destinations in the <em>Log</em> array.<br />
 * However, the <em>Replacement</em> field may be used to specify
 * a message to be sent in the place of the one received.  Within the
 * <em>Replacement</em> string values enclosed in curly brackets will
 * be substituted as follows -
 * </p>
 * <deflist>
 *   <term>Extra1</term>
 *   <desc>The text in the message matched by the Extra1 pattern (if any)</desc>
 *   <term>Extra2</term>
 *   <desc>The text in the message matched by the Extra2 pattern (if any)</desc>
 *   <term>Host</term>
 *   <desc>The host name of the original message</desc>
 *   <term>Server</term>
 *   <desc>The server name of the original message</desc>
 *   <term>Type</term>
 *   <desc>The type of the original message</desc>
 *   <term>Timestamp</term>
 *   <desc>The timestamp of the original message</desc>
 *   <term>Message</term>
 *   <desc>The text of the original message</desc>
 *   <term>Match</term>
 *   <desc>The text matched by the <em>Pattern</em> if any</desc>
 * </deflist>
 * <p>The <em>Log</em> array specifies a list of log destinations which are
 * normally treated as filenames (stored in the standard log directory).
 * However, a value beginning 'database:' * is logged to a
 * database (the default database configured for SQLClient).<br />
 * After the colon you may place a table name, but if you don't then
 * the message will be logged to the 'Alert' table.<br />
 * The values logged in separate fields are the Timestamp, Type, Server, Host,
 * Extra1, Extra2, and full log text (as produced by the Replacement config)
 * is written into the Message field of the table after having been truncated
 * to 200 chars.  Because of the truncation limit, it is recommended that
 * if you are trying to include the original alert {Message} (rather
 * than rewriting it) the Replacement does not include Timestamp,
 * Type, Server, Host, Extra1, Extra2 which are already saved in
 * separate fields, and would take up a lot of the 200 chars, which would
 * be better used to log the actual message.
 *
 * </p>
 * <p>The <em>Sms</em> array lists phone numbers to which Sms alerts are
 * to be sent.
 * </p>
 * <p>The <em>Email</em> array lists email addresses to which email alerts are
 * to be sent.<br />
 * An optional 'Subject' field may be present in the rule ... this is used
 * to specify that the is to be tagged with the given subject line.  This
 * <em>defeats</em> batching of messages in that only messages with the
 * same subject may be batched in the same email.
 * </p>
 */
@implementation	EcAlerter : NSObject

/**
 * Called to set up or modify the configuration of the alerter.<br />
 * The dictionary c must contain (keyed on <code>Rules</code> an
 * array of dictionaries, each of which provides a rule for
 * delivering some form of alert.<br />
 * Other values in the configuration are used for standard configuration
 * of message delivery to the queueing system etc.
 */
- (BOOL) configure: (NSNotification*)n
{
  NSUserDefaults	*d;
  NSDictionary		*c;
  NSMutableArray	*r;
  unsigned int		i;

  d = [EcProc cmdDefaults];
  c = [d dictionaryForKey: @"Alerter"];

  ASSIGNCOPY(eHost, [c objectForKey: @"EmailHost"]);
  ASSIGNCOPY(eFrom, [c objectForKey: @"EmailFrom"]);
  ASSIGNCOPY(ePort, [c objectForKey: @"EmailPort"]);

  /*
   * Cache a copy of the Rules with modifications to store information
   * so we don't need to regenerate it every time we check a message.
   */
  r = [[[c objectForKey: @"Rules"] mutableCopy] autorelease];
  for (i = 0; i < [r count]; i++)
    {
      NSMutableDictionary	*md;
      NSString			*str;
      Regex			*val;

      md = [[r objectAtIndex: i] mutableCopy];
      [r replaceObjectAtIndex: i withObject: md];
      [md release];

      str = [md objectForKey: @"Host"];
      [md removeObjectForKey: @"HostRegex"];
      if (str != nil)
        {
	  val = [[Regex alloc] initWithString: str];
	  if (nil == val)
	    {
	      return NO;
	    }
	  [md setObject: val forKey: @"HostRegex"];
	  [val release];
	}

      str = [md objectForKey: @"Pattern"];
      [md removeObjectForKey: @"PatternRegex"];
      if (str != nil)
        {
	  val = [[Regex alloc] initWithString: str];
	  if (val == nil)
	    {
	      return NO;
	    }
	  [md setObject: val forKey: @"PatternRegex"];
	  RELEASE(val);
	}

      str = [md objectForKey: @"Server"];
      [md removeObjectForKey: @"ServerRegex"];
      if (str != nil)
        {
	  val = [[Regex alloc] initWithString: str];
	  if (val == nil)
	    {
	      return NO;
	    }
	  [md setObject: val forKey: @"ServerRegex"];
	  RELEASE(val);
	}

      str = [md objectForKey: @"Extra1"];
      [md removeObjectForKey: @"Extra1Regex"];
      if (str != nil)
        {
	  val = [[Regex alloc] initWithString: str];
	  if (val == nil)
	    {
	      return NO;
	    }
	  [md setObject: val forKey: @"Extra1Regex"];
	  RELEASE(val);
	}

      str = [md objectForKey: @"Extra2"];
      [md removeObjectForKey: @"Extra2Regex"];
      if (str != nil)
        {
	  val = [[Regex alloc] initWithString: str];
	  if (val == nil)
	    {
	      return NO;
	    }
	  [md setObject: val forKey: @"Extra2Regex"];
	  RELEASE(val);
	}
    }
  ASSIGN(rules, r);
  return YES;
}

- (void) dealloc
{
  [[NSNotificationCenter defaultCenter] removeObserver: self];
  [timer invalidate];
  [self flushSms];
  [self flushEmail];
  [smtp flush: [NSDate dateWithTimeIntervalSinceNow: 30.0]];
  RELEASE(smtp);
  RELEASE(email);
  RELEASE(sms);
  RELEASE(rules);
  [super dealloc];
}

- (NSString*) description
{
  return [NSString stringWithFormat: @"%@ -\nConfigured with %u rules\n"
    @"With SMTP %@:%@ as %@\nPending Email:%@\nPending SMS:%@",
    [super description], [rules count], eHost, ePort, eFrom, email, sms];
}

- (void) flushEmailForAddress: (NSString*)address
		      subject: (NSString*)subject
		      	 text: (NSString*)text
{
  GSMimeHeader		*hdr;
  GSMimeDocument	*doc;

  NS_DURING
    {
      if (smtp == nil)
	{
	  smtp = [GSMimeSMTPClient new];
	}

      if (nil != eHost)
	{
	  [smtp setHostname: eHost];
	}

      if (nil != ePort)
	{
	  [smtp setPort: ePort];
	}

      if (nil == eFrom)
	{
	  eFrom = [NSString stringWithFormat: @"alerter@%@",
	    [[NSHost currentHost] name]];
	  RETAIN(eFrom);
	}

      doc = AUTORELEASE([GSMimeDocument new]);
      hdr = [[GSMimeHeader alloc] initWithName: @"subject"
					 value: subject
				    parameters: nil];
      [doc setHeader: hdr];
      RELEASE(hdr);
      hdr = [[GSMimeHeader alloc] initWithName: @"to"
					 value: address
				    parameters: nil];
      [doc setHeader: hdr];
      RELEASE(hdr);
      hdr = [[GSMimeHeader alloc] initWithName: @"from"
					 value: eFrom
				    parameters: nil];
      [doc setHeader: hdr];
      RELEASE(hdr);

      [doc setContent: text type: @"text/plain" name: nil];
      [smtp send: doc];
    }
  NS_HANDLER
    {
      NSLog(@"Problem flushing email for address: %@, subject: %@, %@",
	address, subject, localException);
    }
  NS_ENDHANDLER
}

/**
 * This method is called to flush any batched email messages.
 */
- (void) flushEmail
{
  NSDictionary		*destinations;

  NS_DURING
    {
      if ((destinations = email) != nil)
	{
	  NSEnumerator	*addressEnumerator = [destinations keyEnumerator];
	  NSString	*address;

	  DESTROY(email);
	  while ((address = [addressEnumerator nextObject]) != nil)
	    {
	      NSDictionary	*items = [destinations objectForKey: address];
	      NSEnumerator	*itemEnumerator = [items keyEnumerator];
	      NSString		*subject;

	      while ((subject = [itemEnumerator nextObject]) != nil)
		{
		  NSString	*text = [items objectForKey: subject];

		  [self flushEmailForAddress: address
				     subject: subject
					text: text];
		}
	    }
	}
    }
  NS_HANDLER
    {
      NSLog(@"Problem flushing email: %@", localException);
    }
  NS_ENDHANDLER
}

/**
 * This method is called periodically to flush any batched sms messages.
 */
- (void) flushSms
{
  NS_DURING
    {
      NSLog(@"Problem flushing sms: ...not currently supported");
    }
  NS_HANDLER
    {
      NSLog(@"Problem flushing sms: %@", localException);
    }
  NS_ENDHANDLER
}

/**
 * <p>This method handles error/alert messages.  It is able to handle
 * multiple (newline separated messages.
 * </p>
 * <p>Each message must be a line of the format -<br />
 * serverName(hostName): YYYY-MM-DD hh:mm:ss.mmm szzzz type - text
 * </p>
 * <p>Each message is matched against each rule in the <em>Rules</em>
 * configuration in turn, and the first match found is used.  The
 * message is sent to the people listed in the <code>Email</code> and
 * <code>Sms</code> entries in the rule (which may be either single
 * names or arryas of names).
 * </p>
 */
- (void) handleInfo: (NSString*)str
{
  NSArray		*a;
  unsigned int		i;
  NSMutableDictionary	*m;

  NS_DURING
    {
      a = [str componentsSeparatedByString: @"\n"];
      for (i = 0; i < [a count]; i++)
	{
	  NSString		*inf = [a objectAtIndex: i];
	  NSRange		r;
	  NSString		*timestamp;
	  NSString		*serverName;
	  NSString		*hostName;
	  NSString		*type = @"Error";
	  unsigned		pos;
	  unsigned		j;

	  str = inf;
	  if ([str length] == 0)
	    {
	      continue;	// Nothing to do
	    }

	 /* Record format is -
	  * serverName(hostName): timestamp Alert - message
	  * or
	  * serverName(hostName): timestamp Error - message
	  */
	  r = [str rangeOfString: @":"];
	  if (r.length == 0)
	    {
	      continue;		// Not an alert or error
	    }
	  serverName = [str substringToIndex: r.location];
	  str = [str substringFromIndex: NSMaxRange(r) + 1];
	  r = [serverName rangeOfString: @"("];
	  if (r.length == 0)
	    {
	      continue;		// Not an alert or error
	    }
	  pos = NSMaxRange(r);
	  hostName = [serverName substringWithRange:
	    NSMakeRange(pos, [serverName length] - pos - 1)];
	  serverName = [serverName substringToIndex: r.location];

	  r = [str rangeOfString: @" Alert - "];
	  if (r.length == 0)
	    {
	      r = [str rangeOfString: @" Error - "];
	      if (r.length == 0)
		{
		  continue;		// Not an alert or error
		}
	      type = @"Error";
	    }
	  else
	    {
	      type = @"Alert";
	    }
	  timestamp = [str substringToIndex: r.location];

	  str = [str substringFromIndex: NSMaxRange(r)];

	  for (j = 0; j < [rules count]; j++)
	    {
	      NSDictionary	*d = [rules objectAtIndex: j];
	      NSString		*match = nil;
	      Regex		*e;
	      NSString		*s;
	      id		o;

	      s = [d objectForKey: @"Type"];
	      if (s != nil && [s isEqualToString: type] == NO)
		{
		  continue;		// Not a match.
		}
	      e = [d objectForKey: @"ServerRegex"];
	      if (e != nil && [e match: serverName] == nil)
		{
		  continue;		// Not a match.
		}
	      e = [d objectForKey: @"HostRegex"];
	      if (e != nil && [e match: hostName] == nil)
		{
		  continue;		// Not a match.
		}
	      e = [d objectForKey: @"PatternRegex"];
	      if (e != nil && (match = [e match: str]) == nil)
		{
		  continue;		// Not a match.
		}

	      m = [NSMutableDictionary new];

	      /*
	       * If the Extra1 or Extra2 patterns are matched,
	       * The matching strings are made available for
	       * substitution inot the replacement message.
	       */
	      [m removeObjectForKey: @"Extra1"];
	      e = [d objectForKey: @"Extra1Regex"];
	      if (e != nil && (match = [e match: str]) != nil)
		{
		  [m setObject: match forKey: @"Extra1"];
		}

	      [m removeObjectForKey: @"Extra2"];
	      e = [d objectForKey: @"Extra2Regex"];
	      if (e != nil && (match = [e match: str]) != nil)
		{
		  [m setObject: match forKey: @"Extra2"];
		}

	      /* We set the Replacement later, because if it is not
	       * set, we want to set a different default for Sms/Email
	       * and database: for Sms/Email logs we want to include
	       * Server, Host, Timestamp, Type and Message (possibly
	       * trying to use as little spaces as possible for Sms,
	       * while trying to display comfortably for Email), while
	       * for database logs we only want to include the
	       * Message.
	       */

	      [m setObject: serverName forKey: @"Server"];
	      [m setObject: hostName forKey: @"Host"];
	      [m setObject: type forKey: @"Type"];
	      [m setObject: timestamp forKey: @"Timestamp"];
	      [m setObject: str forKey: @"Message"];
	      if (match != nil)
		{
		  [m setObject: match forKey: @"Match"];
		}

	      // NSLog(@"Match produced %@", s);

	      NS_DURING
		{
		  o = [d objectForKey: @"Log"];
		  if ([o isKindOfClass: [NSString class]] == YES)
		    {
		      if ([o hasPrefix: @"("])
			{
			  o = [(NSString*)o propertyList];
			}
		      else
			{
			  o = [NSArray arrayWithObject: o];
			}
		    }
		  if (o != nil)
		    {
		      NSString *s = [d objectForKey: @"Replacement"];
		      if (s == nil)
			{
			  s = @"{Message}";
			}
		      [m setObject: s forKey: @"Replacement"];
		      
		      [self log: m to: o];
		    }
		}
	      NS_HANDLER
		{
		  NSLog(@"Exception handling database log for rule: %@",
		    localException);
		}
	      NS_ENDHANDLER

	      NS_DURING
		{
		  o = [d objectForKey: @"Email"];
		  if ([o isKindOfClass: [NSString class]] == YES)
		    {
		      if ([o hasPrefix: @"("])
			{
			  o = [(NSString*)o propertyList];
			}
		      else
			{
			  o = [NSArray arrayWithObject: o];
			}
		    }
		  if (o != nil)
		    {
		      NSString	*s = [d objectForKey: @"Subject"];

		      if (s != nil)
			{
			  [m setObject: s forKey: @"Subject"];
			}

		      s = [d objectForKey: @"Replacement"];
		      if (s == nil)
			{
			  /* Full details.  */
			  s = @"{Server}({Host}): {Timestamp} {Type} - {Message}";
			}
		      [m setObject: s forKey: @"Replacement"];

		      [self mail: m to: o];
		    }
		}
	      NS_HANDLER
		{
		  NSLog(@"Exception handling Email send for rule: %@",
		    localException);
		}
	      NS_ENDHANDLER

	      NS_DURING
		{
		  o = [d objectForKey: @"Sms"];
		  if ([o isKindOfClass: [NSString class]] == YES)
		    {
		      if ([o hasPrefix: @"("])
			{
			  o = [(NSString*)o propertyList];
			}
		      else
			{
			  o = [NSArray arrayWithObject: o];
			}
		    }
		  if (o != nil)
		    {
		      NSString *s = [d objectForKey: @"Replacement"];
		      if (s == nil)
			{
			  /* Use few spaces so that more of the
			   * message fits into an Sms.  */
			  s = @"{Server}({Host}):{Timestamp} {Type}-{Message}";
			}
		      [m setObject: s forKey: @"Replacement"];

		      [self sms: m to: o];
		    }
		}
	      NS_HANDLER
		{
		  NSLog(@"Exception handling Sms send for rule: %@",
		    localException);
		}
	      NS_ENDHANDLER

	      RELEASE(m);

	      s = [d objectForKey: @"Flush"];
	      if (s != nil)
		{
		  if ([s caseInsensitiveCompare: @"Email"] == NSOrderedSame)
		    {
		      [self flushEmail];
		    }
		  else if ([s caseInsensitiveCompare: @"Sms"] == NSOrderedSame)
		    {
		      [self flushSms];
		    }
		  else if ([s boolValue] == YES)
		    {
		      [self flushSms];
		      [self flushEmail];
		    }
		}

	      if ([[d objectForKey: @"Stop"] boolValue] == YES)
		{
		  break;	// Don't want to perform any more matches.
		}
	    }
	}
    }
  NS_HANDLER
    {
      NSLog(@"Problem in handleInfo:'%@' ... %@", str, localException);
    }
  NS_ENDHANDLER
}

- (id) init
{
  if (nil != (self = [super init]))
    {
      timer = [NSTimer scheduledTimerWithTimeInterval: 240.0
					       target: self
					     selector: @selector(timeout:)
					     userInfo: nil
					      repeats: YES];
      [[NSNotificationCenter defaultCenter]
	addObserver: self
	selector: @selector(configure:)
	name: NSUserDefaultsDidChangeNotification
	object: [NSUserDefaults standardUserDefaults]];
      [self configure: nil];
    }
  return self;
}

/**
 * Called by -handleInfo: to log a message to an array of destinations.
 */
- (void) log: (NSMutableDictionary*)m to: (NSArray*)destinations
{
  NSEnumerator	*e = [destinations objectEnumerator];
  NSString	*d;
  NSString	*s;

  /*
   * Perform {field-name} substitutions ...
   */
  s = replaceFields(m);
  while ((d = [e nextObject]) != nil)
    {
      [[EcProc cmdLogFile: d] printf: @"%@\n", s];
    }
}

/**
 * Called by -handleInfo: to pass a message to an array of destinations.
 * The message is actually appended to any cached messages for those
 * destinations ... and the cache is periodically flushed.
 */
- (void) mail: (NSMutableDictionary*)m to: (NSArray*)destinations
{
  NSEnumerator	*e = [destinations objectEnumerator];
  NSString	*d;
  NSString	*s;
  NSString	*subject = [m objectForKey: @"Subject"];

  if (subject == nil)
    {
      subject = @"system alert";
    }
  else
    {
      AUTORELEASE(RETAIN(subject));
      [m removeObjectForKey: @"Subject"];
    }

  /*
   * Perform {field-name} substitutions ...
   */
  s = replaceFields(m);
  if (email == nil)
    {
      email = [NSMutableDictionary new];
    }
  while ((d = [e nextObject]) != nil)
    {
      NSMutableDictionary	*md = [email objectForKey: d];
      NSString			*msg;

      if (md == nil)
	{
	  md = [NSMutableDictionary new];
	  [email setObject: md forKey: d];
	  RELEASE(md);
	}

      msg = [md objectForKey: subject];

      /*
       * If adding the new text would take an existing message over the
       * size limit, send the existing stuff first.
       */
      if ([msg length] > 0 && [msg length] + [s length] + 2 > 20*1024)
	{
	  AUTORELEASE(RETAIN(msg));
	  [md removeObjectForKey: subject];
	  [self flushEmailForAddress: d 
			     subject: subject
				text: msg];
	  msg = nil;
	}
      if (msg == nil)
        {
	  msg = s;
	}
      else
        {
	  msg = [msg stringByAppendingFormat: @"\n\n%@", s];
	}
      [md setObject: msg forKey: subject];
    }
}

/**
 * Called by -handleInfo: to pass a message to an array of destinations.
 * The message replaces any cached messages for those
 * destinations (and has a count of the lost messages noted) ... and
 * the cache is periodically flushed.
 */
- (void) sms: (NSMutableDictionary*)m to: (NSArray*)destinations
{
  NSEnumerator	*e = [destinations objectEnumerator];
  NSString	*d;
  NSString	*s;
  NSString	*t;

  /*
   * Perform {field-name} substitutions, but to shorten the message
   * remove any Timestamp value from the dictionary.
   */
  t = RETAIN([m objectForKey: @"Timestamp"]);
  [m removeObjectForKey: @"Timestamp"];
  s = replaceFields(m);
  if (t != nil)
    {
      [m setObject: t forKey: @"Timestamp"];
      RELEASE(t);
    }

  if (sms == nil)
    {
      sms = [NSMutableDictionary new];
    }
  while ((d = [e nextObject]) != nil)
    {
      NSString	*msg = [sms objectForKey: d];

      if (msg == nil)
        {
	  msg = s;
	}
      else
        {
	  int	missed = 0;

	  if ([msg hasPrefix: @"Missed("] == YES)
	    {
	      NSRange	r = [msg rangeOfString: @")"];

	      r = NSMakeRange(7, r.location - 7);
	      msg = [msg substringWithRange: r];
	      missed = [msg intValue];
	    }
	  missed++;
	  msg = [NSString stringWithFormat: @"Missed(%d)\n%@", missed, s];
	}
      [sms setObject: msg forKey: d];
    }
}

/**
 * Responsible for the periodic calling of -flushEmail and -flushSms
 */
- (void) timeout: (NSTimer*)t
{
  [self flushSms];
  [self flushEmail];
}
@end

