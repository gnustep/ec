
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

@interface      EcAlerterEvent : NSObject
{
  @public
  NSMutableDictionary   *m;
  NSString              *hostName;
  NSString              *identifier;
  NSString              *serverName;
  NSString              *severityText;
  NSString              *text;
  NSDate                *timestamp;
  NSString              *type;
  int                   duration;
  int                   reminder;
  int                   severity;
  BOOL                  isClear;
}
@end
@implementation EcAlerterEvent
- (void) dealloc
{
  RELEASE(hostName);
  RELEASE(identifier);
  RELEASE(m);
  RELEASE(serverName);
  RELEASE(severityText);
  RELEASE(text);
  RELEASE(timestamp);
  RELEASE(type);
  [super dealloc];
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
    [super description], (unsigned)[rules count], eHost, ePort,
    eFrom, email, sms];
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

- (void) applyRules: (NSArray*)rulesArray
            toEvent: (EcAlerterEvent*)event
{
  CREATE_AUTORELEASE_POOL(pool);
  NSUInteger    i;

  for (i = 0; i < [rulesArray count]; i++)
    {
      NSDictionary	*d;
      NSString	        *match = nil;
      Regex		*e;
      NSString	        *s;
      id		o;

      RELEASE(pool);
      pool = [NSAutoreleasePool new];
      d = [rulesArray objectAtIndex: i];

      s = [d objectForKey: @"Tagged"];
      if (s != nil && NO == [s isEqual: [event->m objectForKey: @"Tag"]])
        {
          continue;         // Not a match.
        }

      s = [d objectForKey: @"Type"];
      if (s != nil && [s isEqualToString: event->type] == NO)
        {
          continue;		// Not a match.
        }

      /* The next set are performed only for alarms,
       * since a non-alarm can never match them.
       */
      if (event->reminder >= 0)
        {
          if (event->reminder > 0 && NO == event->isClear)
            {
              /* This is an alarm reminder (neither the initial alarm
               * nor the clear), so we check the ReminderInterval.
               * In order for a match to occur, the ReminderInterval
               * must be set and must match the number of the reminder
               * using division modulo the reminder interval value.
               * NB, unlike other patterns, the absence of this one
               * implies a match failure!
               */
              s = [d objectForKey: @"ReminderInterval"];
              if (nil == s || (event->reminder % [s intValue]))
                {
                  continue;		// Not a match.
                }
            }

          s = [d objectForKey: @"DurationAbove"];
          if (s != nil && event->duration <= [s intValue])
            {
              continue;		// Not a match.
            }
          s = [d objectForKey: @"DurationBelow"];
          if (s != nil && event->duration >= [s intValue])
            {
              continue;		// Not a match.
            }
          s = [d objectForKey: @"ReminderAbove"];
          if (s != nil && event->reminder <= [s intValue])
            {
              continue;		// Not a match.
            }
          s = [d objectForKey: @"ReminderBelow"];
          if (s != nil && event->reminder >= [s intValue])
            {
              continue;		// Not a match.
            }
          e = [d objectForKey: @"SeverityTextRegex"];
          if (e != nil && [e match: event->severityText] == nil)
            {
              continue;		// Not a match.
            }

          s = [d objectForKey: @"SeverityCode"];
          if (s != nil && [s intValue] != event->severity)
            {
              continue;		// Not a match.
            }
        }

      e = [d objectForKey: @"ServerRegex"];
      if (e != nil && [e match: event->serverName] == nil)
        {
          continue;		// Not a match.
        }
      e = [d objectForKey: @"HostRegex"];
      if (e != nil && [e match: event->hostName] == nil)
        {
          continue;		// Not a match.
        }

      e = [d objectForKey: @"PatternRegex"];
      if (nil != e)
        {
          [event->m removeObjectForKey: @"Match"];
          if (nil == (match = [e match: event->text]))
            {
              continue;		// Not a match.
            }
          [event->m setObject: match forKey: @"Match"];
        }

      /*
       * If the Extra1 or Extra2 patterns are matched,
       * The matching strings are made available for
       * substitution into the replacement message.
       */
      e = [d objectForKey: @"Extra1Regex"];
      if (nil != e)
        {
          [event->m removeObjectForKey: @"Extra1"];
          if (nil == (match = [e match: event->text]))
            {
              [event->m setObject: match forKey: @"Extra1"];
            }
        }

      e = [d objectForKey: @"Extra2Regex"];
      if (nil != e)
        {
          [event->m removeObjectForKey: @"Extra2"];
          if (nil != (match = [e match: event->text]))
            {
              [event->m setObject: match forKey: @"Extra2"];
            }
        }

      s = [d objectForKey: @"Rewrite"];
      if (nil != s)
        {
          s = replaceFields(event->m, s);
          [event->m setObject: s forKey: @"Message"];
        }

      s = [d objectForKey: @"Subject"];
      if (s != nil)
        {
          s = replaceFields(event->m, s);
          [event->m setObject: s forKey: @"Subject"];
        }

      /* Set the tag for this event if necessary ... done *after*
       * all matching, but before sending out the alerts.
       */
      if (nil != [d objectForKey: @"Tag"])
        {
          NSString  *s = replaceFields(event->m, [d objectForKey: @"Tag"]);

          [event->m setObject: s forKey: @"Tag"];
        }

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
              [event->m setObject: s forKey: @"Replacement"];
              [self log: event->m
             identifier: event->identifier
                isClear: event->isClear
                     to: o];
            }
        }
      NS_HANDLER
        {
          NSLog(@"Exception handling database log for rule: %@",
            localException);
        }
      NS_ENDHANDLER
      [event->m removeObjectForKey: @"Replacement"];

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
              NSString	*s;

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
              [event->m setObject: s forKey: @"Replacement"];
              [self mail: event->m
              identifier: event->identifier
                 isClear: event->isClear
                      to: o];
            }
        }
      NS_HANDLER
        {
          NSLog(@"Exception handling Email send for rule: %@",
            localException);
        }
      NS_ENDHANDLER
      [event->m removeObjectForKey: @"Replacement"];

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
              NSString	*s;

              if (event->reminder > 0)
                {
                  NSString      *s;

                  /* Pass the reminder value to the email code so it
                   * can generate In-Reply-To and References headers
                   * for threading.
                   */
                  s = [NSString stringWithFormat: @"%d", event->reminder];
                  [event->m setObject: s forKey: @"EmailThreading"];
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
              [event->m setObject: s forKey: @"Replacement"];
              [self mail: event->m
              identifier: event->identifier
                 isClear: event->isClear
                      to: o];
            }
        }
      NS_HANDLER
        {
          NSLog(@"Exception handling Email send for rule: %@",
            localException);
        }
      NS_ENDHANDLER
      [event->m removeObjectForKey: @"Replacement"];
      [event->m removeObjectForKey: @"ReminderInterval"];

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
              [event->m setObject: s forKey: @"Replacement"];
              [self sms: event->m
             identifier: event->identifier
                isClear: event->isClear
                     to: o];
            }
        }
      NS_HANDLER
        {
          NSLog(@"Exception handling Sms send for rule: %@",
            localException);
        }
      NS_ENDHANDLER
      [event->m removeObjectForKey: @"Replacement"];

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

- (void) handleEvent: (NSString*)text
            withHost: (NSString*)hostName
           andServer: (NSString*)serverName
           timestamp: (NSDate*)timestamp
          identifier: (NSString*)identifier
               alarm: (EcAlarm*)alarm
            reminder: (int)reminder
{
  NS_DURING
    {
      NSMutableDictionary	*m;
      NSString                  *str;
      EcAlerterEvent            *event;
      
      event = AUTORELEASE([EcAlerterEvent new]);
      ASSIGN(event->text, text);
      ASSIGN(event->hostName, hostName);
      ASSIGN(event->serverName, serverName);
      ASSIGN(event->timestamp, timestamp);
      ASSIGN(event->identifier, identifier);

      if (nil == alarm)
        {
          event->severity = EcAlarmSeverityIndeterminate;
          event->severityText = @"";
          event->isClear = NO;
          if (nil != identifier)
            {
              event->type = @"Alert";
            }
          else
            {
              event->type = @"Error";
            }
        }
      else
        {
          event->severity = [alarm perceivedSeverity];
          ASSIGN(event->severityText,
            [EcAlarm stringFromSeverity: event->severity]);
          if ([@"Clear" isEqual: [alarm extra]])
            {
              event->isClear = YES;
              event->type = @"Clear";
            }
          else
            {
              event->isClear = NO;
              event->type = @"Alarm";
            }
        }
      event->reminder = reminder;
      event->duration = (0.0 - [timestamp timeIntervalSinceNow]) / 60.0;

      m = event->m = [[NSMutableDictionary alloc] initWithCapacity: 20];
      [m setObject: event->serverName forKey: @"Server"];
      [m setObject: event->hostName forKey: @"Host"];
      [m setObject: event->type forKey: @"Type"];
      [m setObject: [NSString stringWithFormat: @"%d", event->severity]
            forKey: @"SeverityCode"];
      [m setObject: event->severityText forKey: @"SeverityText"];
      [m setObject: [event->timestamp description] forKey: @"Timestamp"];
      if (event->reminder >= 0)
        {
          [m setObject: [NSString stringWithFormat: @"%d", event->reminder]
                forKey: @"Reminder"];
        }
      /* If the alarm has a responsible person/entity email address set,
       * make it available.
       */
      str = [[alarm userInfo] objectForKey: @"ResponsibleEmail"];
      if (nil != str)
        {
          [m setObject: str forKey: @"ResponsibleEmail"];
        }
      if ([event->identifier length] > 0)
        {
          [m setObject: event->identifier forKey: @"Identifier"];
        }
      [m setObject: [NSString stringWithFormat: @"%d", event->duration]
            forKey: @"Duration"];
      [m setObject: [NSString stringWithFormat: @"%d", event->duration / 60]
            forKey: @"Hours"];
      [m setObject: [NSString stringWithFormat: @"%02d", event->duration % 60]
            forKey: @"Minutes"];
      [m setObject: event->text forKey: @"Message"];
      [m setObject: event->text forKey: @"Original"];

      [self applyRules: rules toEvent: event];
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
                      alarm: nil
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
          int           threadID;

          threadID = [[m objectForKey: @"EmailThreading"] intValue];
          if (threadID > 0)
            {
              NSString          *rep;
              NSMutableString   *ref;

              rep = [NSString stringWithFormat: @"<alrm%@@%@>",
                identifier, eBase];
              [doc setHeader: @"In-Reply-To" value: rep parameters: nil];
              ref = [rep mutableCopy];
#if 0
              if (threadID > 1)
                {
                  int   index;

                  for (index = 1; index < threadID; index++)
                    {
                      [ref appendFormat: @"<alrm%@_%d@%@>",
                        identifier, index, eBase];
                    }
                }
#endif
              [doc setHeader: @"References" value: ref parameters: nil];
              mID = [NSString stringWithFormat: @"<alrm%@_%d@%@>",
                identifier, threadID, eBase];
            }
          else
            {
              mID = [NSString stringWithFormat: @"<alrm%@@%@>",
                identifier, eBase];
            }

          if (YES == isClear && threadID <= 0)
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
          if (YES == [d hasPrefix: @"{ResponsibleEmail}"])
            {
              NSString  *s = [m objectForKey: @"ResponsibleEmail"];

              if ([s length] > 0)
                {
                  /* Use the ResponsibleEmail address from the alarm
                   */
                  d = s;
                }
              else
                {
                  /* Use the fallback (remaining text in the address)
                   */
                  d = [d substringFromIndex: 18];
                }
            }
          if (0 == [d length])
            {
              continue;
            }
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

