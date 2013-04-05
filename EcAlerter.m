
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

#import "EcHost.h"
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

@implementation	EcAlerter : NSObject

- (BOOL) configure: (NSNotification*)n
{
  NSUserDefaults	*d;
  NSDictionary		*c;

  d = [EcProc cmdDefaults];
  c = [d dictionaryForKey: @"Alerter"];
  return [self configureWithDefaults: c];
}

- (BOOL) configureWithDefaults: (NSDictionary*)c
{
  ASSIGNCOPY(eHost, [c objectForKey: @"EmailHost"]);
  ASSIGNCOPY(eFrom, [c objectForKey: @"EmailFrom"]);
  ASSIGNCOPY(ePort, [c objectForKey: @"EmailPort"]);
  return [self setRules: [c objectForKey: @"Rules"]];
}

- (BOOL) setRules: (NSArray*)ra
{
  NSUInteger    i = 0;
  NSMutableArray        *r = AUTORELEASE([ra mutableCopy]); 

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
	    [[NSHost currentHost] wellKnownName]];
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

- (void) handleEvent: (NSString*)text
            withHost: (NSString*)hostName
           andServer: (NSString*)serverName
           timestamp: (NSString*)timestamp
          identifier: (NSString*)identifier
             isClear: (BOOL)isClear
{
  if (nil == identifier)
    {
      isClear = NO;
    }
  NS_DURING
    {
      NSUInteger                i;
      NSString                  *type;
      NSMutableDictionary	*m;


      if (nil != identifier)
        {
          type = @"Alert";
        }
      else
        {
          type = @"Error";
        }
      for (i = 0; i < [rules count]; i++)
        {
          NSDictionary	*d = [rules objectAtIndex: i];
          NSString	*match = nil;
          Regex		*e;
          NSString	*s;
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
          if (e != nil && (match = [e match: text]) == nil)
            {
              continue;		// Not a match.
            }

          m = [NSMutableDictionary new];

          /*
           * If the Extra1 or Extra2 patterns are matched,
           * The matching strings are made available for
           * substitution into the replacement message.
           */
          [m removeObjectForKey: @"Extra1"];
          e = [d objectForKey: @"Extra1Regex"];
          if (e != nil && (match = [e match: text]) != nil)
            {
              [m setObject: match forKey: @"Extra1"];
            }

          [m removeObjectForKey: @"Extra2"];
          e = [d objectForKey: @"Extra2Regex"];
          if (e != nil && (match = [e match: text]) != nil)
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
          [m setObject: text forKey: @"Message"];
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
                  [self log: m identifier: identifier isClear: isClear to: o];
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
                  [self mail: m identifier: identifier isClear: isClear to: o];
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
                  [self sms: m identifier: identifier isClear: isClear to: o];
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
  NS_HANDLER
    {
      NSLog(@"Problem in handleInfo:'%@' ... %@", text, localException);
    }
  NS_ENDHANDLER
}

- (void) handleInfo: (NSString*)str
{
  NS_DURING
    {
      NSArray		*a;
      NSUInteger	i;

      a = [str componentsSeparatedByString: @"\n"];
      for (i = 0; i < [a count]; i++)
	{
	  NSString		*inf = [a objectAtIndex: i];
	  NSRange		r;
	  NSString		*timestamp;
	  NSString		*serverName;
	  NSString		*hostName;
	  BOOL  		immediate;
	  unsigned		pos;

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
	      immediate = NO;
	    }
	  else
	    {
	      immediate = YES;
	    }
	  timestamp = [str substringToIndex: r.location];

	  str = [str substringFromIndex: NSMaxRange(r)];

          [self handleEvent: str
                   withHost: hostName
                  andServer: serverName
                  timestamp: timestamp
                 identifier: (YES == immediate) ? (id)@"" : (id)nil
                    isClear: NO];
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

- (void) log: (NSMutableDictionary*)m
  identifier: (NSString*)identifier
     isClear: (BOOL)isClear
          to: (NSArray*)destinations
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

- (void) log: (NSMutableDictionary*)m to: (NSArray*)destinations
{
  [self log: m identifier: nil isClear: NO to: destinations];
}

- (void) mail: (NSMutableDictionary*)m
   identifier: (NSString*)identifier
      isClear: (BOOL)isClear
           to: (NSArray*)destinations
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

- (void) mail: (NSMutableDictionary*)m to: (NSArray*)destinations
{
  [self mail: m identifier: nil isClear: NO to: destinations];
}


- (void) sms: (NSMutableDictionary*)m
  identifier: (NSString*)identifier
     isClear: (BOOL)isClear
          to: (NSArray*)destinations
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

- (void) sms: (NSMutableDictionary*)m to: (NSArray*)destinations
{
  [self sms: m identifier: nil isClear: NO to: destinations];
}

- (void) timeout: (NSTimer*)t
{
  [self flushSms];
  [self flushEmail];
}
@end

