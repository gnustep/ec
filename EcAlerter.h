
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

#import <Foundation/NSObject.h>

@class	GSMimeSMTPClient;
@class	NSArray;
@class	NSMutableArray;
@class	NSMutableDictionary;
@class	NSString;
@class	NSTimer;


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
 * to be sent (if the alerter has been subclassed to implement SMS delivery).
 * </p>
 * <p>The <em>Email</em> array lists email addresses to which email alerts are
 * to be sent.<br />
 * An optional 'Subject' field may be present in the rule ... this is used
 * to specify that the is to be tagged with the given subject line.  This
 * <em>defeats</em> batching of messages in that only messages with the
 * same subject may be batched in the same email.
 * </p>
 *
 * <p>Configuration of the alerter is done by the 'Alerter' key in the user
 * defaults system.  The value for this key must be a dictionary configuring
 * the Email setup and the rules as follows:
 * </p>
 * <deflist>
 *   <term>Debug</term>
 *   <desc>A boolean saying whether extra debug data should be logged.
 *     If YES, all outgoing Email messages are logged.</desc>
 *   <term>EmailFrom</term>
 *   <desc>The sender address to use for outgoing alert Email messages.
 *     By default 'alerter@host' where 'host' is the value defined in
 *     the EmailHost config, or any name of the local host.</desc>
 *   <term>EmailHost</term>
 *   <desc>The name or address of the host to use as an Email gateway.
 *     By default the local host.</desc>
 *   <term>EmailPort</term>
 *   <desc>The port number of the MTA to connect to on the EmailHost.
 *     By default this is port 25.</desc>
 *   <term>Rules</term>
 *   <desc>An array of rule dictionaries as defined above.</desc>
 * </deflist>
 *
 * <p>When an ExAlerter instance is used by a Control server process,
 *  The 'Alerter' configuration dictionary may contain some extra
 *  configuration used to define the way the Control server uses the
 *  alerter.<br />
 *  The Control server integrates the alarm system (EcAlarm etc) with
 *  the alerting system (used by alert and error level logging from
 *  EcProcess) by generating alerter events when major and critical
 *  severity alarms are raised, and sending alerter 'clear' messages
 *  when the alarms are cleared.<br />
 *  The Control server may also be configured to generate reminder
 *  alerts when alarms have not been dealt with (cleared) in a timely
 *  manner.  
 * </p>
 * <deflist>
 *   <term>AlertBundle</term>
 *   <desc>An optional class/bundle name for a subclass of EcAlerter
 *     to be loaded into the Control server instead of the standard
 *     EcAlerter class.</desc>
 *   <term>AlertCritical</term>
 *   <desc>An integer number of minutes between generating alerts
 *     reminding about critical alarms.  If this is not set then
 *     the value for AlertMajor is used.</desc>
 *   <term>AlertMajor</term>
 *   <desc>An integer number of minutes between generating alerts
 *     reminding about major alarms.  If this is not set then it
 *     defaults to zero ... meaning that no reminders are sent.</desc>
 * </deflist>
 */
@interface	EcAlerter : NSObject
{
  NSArray		*rules; /** Rules for handling alerts */
  NSMutableDictionary	*email; /** Batching Email alerts */
  NSMutableDictionary	*sms;   /** Batching SMS alerts */
  NSTimer		*timer; /** Timer for batch flush */
  NSString		*eBase; /** Sender host name for message ID */
  NSString		*eDflt; /** Default sender address */
  NSString		*eFrom; /** Sender address in use */
  NSString		*eHost; /** Host with SMTP MTA */
  NSString		*ePort; /** Port of SMTP MTA */
  GSMimeSMTPClient	*smtp;  /** Client connection to MTA */
  int                   aCrit;  /** Interval between critical alarm reminders */
  int                   aMaj;   /** Interval between major alarm reminders */
  BOOL                  debug;  /** Debug enabled in config */
}

/** Called when user defaults are updated, this fetches the dictionary
 * 'Alerter' from the defaults system, and passes it to the
 * -configureWithDefaults: method.
 */
- (BOOL) configure: (NSNotification*)n;

/** Called to set up or modify the configuration of the alerter.<br />
 * The dictionary c must contain (keyed on <code>Rules</code> an
 * array of dictionaries, each of which provides a rule for
 * delivering some form of alert.<br />
 * Other values in the configuration are used for standard configuration
 * of message delivery to the queueing system etc.
 */
- (BOOL) configureWithDefaults: (NSDictionary*)c;

/** This method is called to flush any batched email messages.
 */
- (void) flushEmail;

/** This method is called to flush any batched SMS messages.
 */
- (void) flushSms;

/** <p>This method handles an error/alert event (an 'error' is one which may
 * be buffered, while an 'alert' must be sent immediately).<br />
 * If the identifier field is non-nil then the event is an alert which is
 * identified by the value of the field and may be 'cleared' by a later
 * event with the same identfier and with the isClear flag set.  The use
 * of an empty string as an identifier is permitted for events which should
 * not be buffered, but which will never be matched by a clear.
 * </p>
 * <p>Each event must consist of text associated with a host name,
 * server name (usually the process on the host) and timestamp.
 * </p>
 * <p>Each message is matched against each rule in the <em>Rules</em>
 * configuration in turn, and the first match found is used.  The
 * message is sent to the people listed in the <code>Email</code> and
 * <code>Sms</code> entries in the rule (which may be either single
 * names or arrays of names).
 * </p>
 */
- (void) handleEvent: (NSString*)text
            withHost: (NSString*)hostName
           andServer: (NSString*)serverName
           timestamp: (NSString*)timestamp
          identifier: (NSString*)identifier
             isClear: (BOOL)isClear;

/** <p>This method handles error/alert messages.  It is able to handle
 * multiple (newline separated messages.
 * </p>
 * <p>Each message must be a line of the format -<br />
 * serverName(hostName): YYYY-MM-DD hh:mm:ss.mmm szzzz type - text
 * </p>
 * <p>Each message is parsed an then the components are passed to
 * the -handleEvent:withHost:andServer:timestamp:identifier:isClear: method.
 * </p>
 */
- (void) handleInfo: (NSString*)str;

/** Called by -handleEvent:withHost:andServer:timestamp:identifier:isClear:
 * to log a message to an array of destinations.
 */
- (void) log: (NSMutableDictionary*)m
  identifier: (NSString*)identifier
     isClear: (BOOL)isClear
          to: (NSArray*)destinations;

/** Calls -log:identifier:isClear:to: with a nil identifier.
 */
- (void) log: (NSMutableDictionary*)m to: (NSArray*)destinations;

/** Called by -handleEvent:withHost:andServer:timestamp:identifier:isClear:
 * to pass a message to an array of destinations.
 * The message is actually appended to any cached messages for those
 * destinations ... and the cache is periodically flushed.
 */
- (void) mail: (NSMutableDictionary*)m
   identifier: (NSString*)identifier
      isClear: (BOOL)isClear
           to: (NSArray*)destinations;

/** Calls -mail:identifier:isClear:to: with a nil identifier.
 */
- (void) mail: (NSMutableDictionary*)m
           to: (NSArray*)destinations;

/** Cache a copy of the Rules with modifications to store information
 * so we don't need to regenerate it every time we check a message.
 */
- (BOOL) setRules: (NSArray*)ra;

/** Called by -handleEvent:withHost:andServer:timestamp:identifier:isClear:
 * to pass a message to an array of destinations.
 * The message replaces any cached messages for those
 * destinations (and has a count of the lost messages noted) ... and
 * the cache is periodically flushed.
 */
- (void) sms: (NSMutableDictionary*)m
  identifier: (NSString*)identifier
     isClear: (BOOL)isClear
          to: (NSArray*)destinations;

/** Calls -sms:identifier:isClear:to: with a nil identifier.
 */
- (void) sms: (NSMutableDictionary*)m to: (NSArray*)destinations;

/** Responsible for the periodic calling of -flushEmail and -flushSms
 */
- (void) timeout: (NSTimer*)t;
@end

