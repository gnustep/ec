
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
#import "EcAlarm.h"
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

  if (0 == str)
    {
      return nil;
    }
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
replaceFields(NSDictionary *fields, NSString *template)
{
  NSMutableString	*m;

  m = [[template mutableCopy] autorelease];
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

- (void) _setEFrom: (NSString*)s
{
  if (nil == s)
    {
      /* Can't have a nil sender ... use (generate if needed) default.
       */
      if (nil == eDflt)
        {
          eDflt = [[NSString alloc] initWithFormat: @"alerter@%@",
            [[NSHost currentHost] wellKnownName]];
        }
      s = eDflt;
    }
  if (s != eFrom && NO == [s isEqual: eFrom])
    {
      NSRange   r;

      ASSIGNCOPY(eFrom, s);
      r = [s rangeOfString: @"@"];
      if (r.length > 0)
        {
          s = [s substringFromIndex: NSMaxRange(r)];
        }
      ASSIGNCOPY(eBase, s);
    }
}

- (void) smtpClient: (GSMimeSMTPClient*)client mimeFailed: (GSMimeDocument*)doc
{
  NSLog(@"Message failed: %@", doc);
}

- (void) smtpClient: (GSMimeSMTPClient*)client mimeSent: (GSMimeDocument*)doc
{
  if (YES == debug)
    {
      NSLog(@"Message sent: %@", doc);
    }
}

- (void) smtpClient: (GSMimeSMTPClient*)client mimeUnsent: (GSMimeDocument*)doc
{
  NSLog(@"Message dropped on SMTP client shutdown: %@", doc);
}

- (GSMimeSMTPClient*) _smtp
{
  if (nil == smtp)
    {
      smtp = [GSMimeSMTPClient new];
    }
  if (nil == eFrom)
    {
      [self _setEFrom: nil];
    }
  if (nil != eHost)
    {
      [smtp setHostname: eHost];
    }
  if (nil != ePort)
    {
      [smtp setPort: ePort];
    }
  [smtp setDelegate: self];
  return smtp;
}

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
  debug = [[c objectForKey: @"Debug"] boolValue];
  supersede = [[c objectForKey: @"Supersede"] boolValue];
  [self _setEFrom: [c objectForKey: @"EmailFrom"]];
  ASSIGNCOPY(eHost, [c objectForKey: @"EmailHost"]);
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

      str = [md objectForKey: @"SeverityText"];
      [md removeObjectForKey: @"SeverityTextRegex"];
      if (str != nil)
        {
	  val = [[Regex alloc] initWithString: str];
	  if (val == nil)
	    {
	      return NO;
	    }
	  [md setObject: val forKey: @"SeverityTextRegex"];
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
  NS_DURING
    {
      GSMimeDocument	*doc;

      doc = AUTORELEASE([GSMimeDocument new]);
      [doc setHeader: @"Subject" value: subject parameters: nil];
      [doc setHeader: @"To" value: address parameters: nil];
      [doc setHeader: @"From" value: eFrom parameters: nil];
      [doc setContent: text type: @"text/plain" name: nil];
      [[self _smtp] send: doc];
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
  return;
}

- (void) handleEvent: (NSString*)text
            withHost: (NSString*)hostName
           andServer: (NSString*)serverName
           timestamp: (NSDate*)timestamp
          identifier: (NSString*)identifier
            severity: (int)severity
            reminder: (int)reminder
{
  if (nil == identifier)
    {
      severity = EcAlarmSeverityIndeterminate;
    }
  NS_DURING
    {
      NSAutoreleasePool         *pool = nil;
      NSUInteger                i;
      NSString                  *type;
      NSString                  *severityText;
      NSMutableDictionary	*m;
      int                       duration;
      BOOL                      isClear;

      duration = (0.0 - [timestamp timeIntervalSinceNow]) / 60.0;
      isClear = (EcAlarmSeverityCleared == severity) ? YES : NO;
      if (EcAlarmSeverityIndeterminate == severity)
        {
          severityText = @"";   // Not an alarm
        }
      else
        {
          severityText = [EcAlarm stringFromSeverity: severity];
        }

      if (nil != identifier)
        {
          type = @"Alert";
        }
      else
        {
          type = @"Error";
        }

      m = [NSMutableDictionary dictionaryWithCapacity: 20];
      [m setObject: serverName forKey: @"Server"];
      [m setObject: hostName forKey: @"Host"];
      [m setObject: type forKey: @"Type"];
      [m setObject: [NSString stringWithFormat: @"%d", severity]
            forKey: @"SeverityCode"];
      [m setObject: severityText forKey: @"SeverityText"];
      [m setObject: [timestamp description] forKey: @"Timestamp"];
      if (reminder >= 0)
        {
          [m setObject: [NSString stringWithFormat: @"%d", reminder]
                forKey: @"Reminder"];
        }
      if ([identifier length] > 0)
        {
          [m setObject: identifier forKey: @"Identifier"];
        }
      [m setObject: [NSString stringWithFormat: @"%d", duration]
            forKey: @"Duration"];
      [m setObject: [NSString stringWithFormat: @"%d", duration / 60]
            forKey: @"Hours"];
      [m setObject: [NSString stringWithFormat: @"%02d", duration % 60]
            forKey: @"Minutes"];
      [m setObject: text forKey: @"Message"];
      [m setObject: text forKey: @"Original"];

      for (i = 0; i < [rules count]; i++)
        {
          NSDictionary	*d;
          NSString	*match = nil;
          Regex		*e;
          NSString	*s;
          id		o;

          RELEASE(pool);
          pool = [NSAutoreleasePool new];
          d = [rules objectAtIndex: i];
          s = [d objectForKey: @"Type"];
          if (s != nil && [s isEqualToString: type] == NO)
            {
              continue;		// Not a match.
            }

          /* These two can be used to decide whether an alert is
           * for an alarm or not.
           */
          e = [d objectForKey: @"SeverityTextRegex"];
          if (e != nil && [e match: severityText] == nil)
            {
              continue;		// Not a match.
            }
          s = [d objectForKey: @"SeverityCode"];
          if (s != nil && [s intValue] != severity)
            {
              continue;		// Not a match.
            }

          /* The next set are performed only for alarms,
           * since a non-alarm can never match them.
           */
          if (reminder >= 0)
            {
              s = [d objectForKey: @"DurationAbove"];
              if (s != nil && duration <= [s intValue])
                {
                  continue;		// Not a match.
                }
              s = [d objectForKey: @"DurationBelow"];
              if (s != nil && duration >= [s intValue])
                {
                  continue;		// Not a match.
                }
              s = [d objectForKey: @"ReminderAbove"];
              if (s != nil && reminder <= [s intValue])
                {
                  continue;		// Not a match.
                }
              s = [d objectForKey: @"ReminderBelow"];
              if (s != nil && reminder >= [s intValue])
                {
                  continue;		// Not a match.
                }
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

          [m removeObjectForKey: @"Match"];
          if (match != nil)
            {
              [m setObject: match forKey: @"Match"];
            }

          s = [d objectForKey: @"Rewrite"];
          if (nil != s)
            {
              s = replaceFields(m, s);
              [m setObject: s forKey: @"Message"];
            }

          /* Remove any old Replacement setting ... will set up specifically
           * for the output alert type later.
           */
          [m removeObjectForKey: @"Replacement"];

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
                  NSString *s = [d objectForKey: @"LogReplacement"];

                  if (nil == s)
                    {
                      s = [d objectForKey: @"Replacement"];
                      if (nil == s)
                        {
                          s = @"{Message}";
                        }
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

                  s = [d objectForKey: @"EmailReplacement"];
                  if (nil == s)
                    {
                      s = [d objectForKey: @"Replacement"];
                      if (nil == s)
                        {
                          /* Full details.  */
                          s = @"{Server}({Host}): {Timestamp} {Type}"
                            @" - {Message}";
                        }
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
              o = [d objectForKey: @"Threaded"];
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

                  if (reminder > 0)
                    {
                      NSString      *emailIdentifier;
                      NSString      *emailInReplyTo;

                      if (1 == reminder)
                        {
                          emailInReplyTo = identifier;
                          emailIdentifier
                            = [identifier stringByAppendingString: @"_1"];
                        }
                      else
                        {
                          emailInReplyTo
                            = [NSString stringWithFormat: @"%@_%d",
                            identifier, reminder - 1];
                          emailIdentifier
                            = [NSString stringWithFormat: @"%@_%d",
                            identifier, reminder];
                        }

                      [m setObject: emailIdentifier
                            forKey: @"EmailIdentifier"];
                      [m setObject: emailInReplyTo
                            forKey: @"EmailInReplyTo"];
                    }

                  if (s != nil)
                    {
                      [m setObject: s forKey: @"Subject"];
                    }

                  s = [d objectForKey: @"EmailReplacement"];
                  if (nil == s)
                    {
                      s = [d objectForKey: @"Replacement"];
                      if (nil == s)
                        {
                          /* Full details.  */
                          s = @"{Server}({Host}): {Timestamp} {Type}"
                            @" - {Message}";
                        }
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
          [m removeObjectForKey: @"EmailIdentifier"];
          [m removeObjectForKey: @"EmailInReplyTo"];

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
                  NSString *s = [d objectForKey: @"SmsReplacement"];

                  if (nil == s)
                    {
                      s = [d objectForKey: @"Replacement"];
                      if (nil == s)
                        {
                          /* Use few spaces so that more of the
                           * message fits into an Sms.  */
                          s = @"{Server}({Host}):{Timestamp} {Type}-{Message}";
                        }
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
      RELEASE(pool);
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
	  NSCalendarDate	*timestamp;
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
	  timestamp = [NSCalendarDate
            dateWithString: [str substringToIndex: r.location]
            calendarFormat: @"%Y-%m-%d %H:%M:%S %z"];

	  str = [str substringFromIndex: NSMaxRange(r)];

          [self handleEvent: str
                   withHost: hostName
                  andServer: serverName
                  timestamp: timestamp
                 identifier: (YES == immediate) ? (id)@"" : (id)nil
                   severity: EcAlarmSeverityIndeterminate
                   reminder: -1];
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
  s = replaceFields(m, [m objectForKey: @"Replacement"]);
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
  NSString	*text;
  NSString	*subject;

  /*
   * Perform {field-name} substitutions ...
   */
  text = replaceFields(m, [m objectForKey: @"Replacement"]);

  subject = [m objectForKey: @"Subject"];
  if (nil == subject)
    {
      if ([identifier length] > 0)
        {
          if (YES == isClear)
            {
              subject = [NSString stringWithFormat: @"Clear %@", identifier];
            }
          else
            {
              subject = [NSString stringWithFormat: @"Alarm %@", identifier];
            }
        }
      else
        {
          subject = @"system alert";
        }
    }
  else
    {
      subject = replaceFields(m, subject);
      [m removeObjectForKey: @"Subject"];
    }

  /* If we need to send immediately, don't buffer the message.
   */
  if (nil != identifier)
    {
      GSMimeDocument    *doc;

      [self _smtp];
      doc = AUTORELEASE([GSMimeDocument new]);
      [doc setHeader: @"Subject" value: subject parameters: nil];
      [doc setContent: text type: @"text/plain" name: nil];
      [doc setHeader: @"From" value: eFrom parameters: nil];

      if ([identifier length] > 0)
        {
          NSString      *mID;

          /* This may reference an earlier email (for threaded display)
           */
          mID = [m objectForKey: @"EmailInReplyTo"];
          if (nil != mID)
            {
              mID = [NSString stringWithFormat: @"<alrm%@@%@>", mID, eBase];
              [doc setHeader: @"In-Reply-To" value: mID parameters: nil];
            }

          /* We may have an identifier set in the dictionary to use
           */
          mID = [m objectForKey: @"EmailIdentifier"];
          if (nil != mID)
            {
              NSRange   r = [mID rangeOfString: @"_"];

              if (r.length > 0)
                {
#if 0
                  int   version;

                  /* Reference all earlier messages in thread.
                   */
                  version = [[mID substringFromIndex: NSMaxRange(r)] intValue];
                  if (version > 1)
                    {
                      NSMutableString   *ms = [NSMutableString string];
                      int               index;

                      for (index = 1; index < version; index++)
                        {
                          if (index > 1)
                            {
                              [ms appendString: @" "];
                            }
                          [ms appendFormat: @"<alrm%@_%d@%@>",
                            mID, index, eBase];
                        }
                      [doc setHeader: @"References" value: ms parameters: nil];
                    }
#else
                  NSString  *ref;

                  /* Reference the original message at start of thread.
                   */
                  ref = [NSString stringWithFormat: @"<alrm%@@%@>",
                    [mID substringToIndex: r.location], eBase];
                  [doc setHeader: @"References" value: ref parameters: nil];
#endif
                }
              mID = [NSString stringWithFormat: @"<alrm%@@%@>", mID, eBase];
            }
          else
            {
              mID = [NSString stringWithFormat: @"<alrm%@@%@>",
                identifier, eBase];
            }

          if (YES == isClear)
            {
              if (YES == supersede)
                {
                  /* Set all the headers likely to be used by clients to
                   * have this message supersede the original.
                   */
                  [doc setHeader: @"Obsoletes" value: mID parameters: nil];
                  [doc setHeader: @"Replaces" value: mID parameters: nil];
                  [doc setHeader: @"Supersedes" value: mID parameters: nil];
                }
              else
                {
                  /* Treat the clear as simply a repeat (new version) of the
                   * original message.
                   */
                  [doc setHeader: @"Message-ID" value: mID parameters: nil];
                }
            }
          else
            {
              [doc setHeader: @"Message-ID" value: mID parameters: nil];
            }
        }

      while ((d = [e nextObject]) != nil)
        {
          NS_DURING
            {
              GSMimeDocument    *msg;

              msg = AUTORELEASE([doc copy]);
              [msg setHeader: @"To" value: d parameters: nil];
              [smtp send: msg];
            }
          NS_HANDLER
            {
              NSLog(@"Problem flushing email for address: %@, subject: %@, %@",
                d, subject, localException);
            }
          NS_ENDHANDLER
        }
    }
  else
    {
      if (email == nil)
        {
          email = [NSMutableDictionary new];
        }
      while ((d = [e nextObject]) != nil)
        {
          NSMutableDictionary	*md = [email objectForKey: d];
          NSString		*msg;

          if (md == nil)
            {
              md = [NSMutableDictionary new];
              [email setObject: md forKey: d];
              RELEASE(md);
            }

          msg = [md objectForKey: subject];

          /* If adding the new text would take an existing message over the
           * size limit, send the existing stuff first.
           */
          if ([msg length] > 0 && [msg length] + [text length] + 2 > 20*1024)
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
              msg = text;
            }
          else
            {
              msg = [msg stringByAppendingFormat: @"\n\n%@", text];
            }
          [md setObject: msg forKey: subject];
        }
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
  s = replaceFields(m, [m objectForKey: @"Replacement"]);
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

