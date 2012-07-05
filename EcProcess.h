
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

#ifndef INCLUDED_ECPROCESS_H
#define INCLUDED_ECPROCESS_H

/**
    <chapter>
      <heading>The EcProcess class</heading>
      <p>
	The EcProcess class provides basic configuration, control, logging,
	and inter-process connection systems for servers processors.
      </p>
      <section>
	<heading>Configuration options</heading>
	<p>
	  This class understands two groups of configuration options ...
	  those that take effect at process startup, and must therefore
	  be supplied on the command-line or in the defaults system, and
	  those which can take effect at any time, in which case the
	  values supplied by the configuration system will take
	  precedence over command line and defaults database settings.
	</p>
	<subsect>
	  <heading>startup settings</heading>
	  <deflist>
	    <term>EcDebug-</term>
	    <desc>
	      Any key of the form EcDebug-xxx turns on the xxx debug level
	      on program startup.
	    </desc>
	    <term>EcMemory</term>
	    <desc>
	      This boolean value determines whether statistics on creation
	      and destruction of objects are maintained.<br />
	      This may be set on the command line or in Control.plist, but
	      may be overridden by using the 'release' command in the
	      Console program.
	    </desc>
	    <term>EcRelease</term>
	    <desc>
	      This boolean value determines whether checks for memory problems
	      caused by release an object too many times are done.  Turning
	      this on has a big impact on program performance and is not
	      recommended except for debugging crashes and other memory
	      issues.<br />
	      This may be set on the command line or in Control.plist, but
	      may be overridden by using the 'release' command in the
	      Console program.
	    </desc>
	    <term>EcTesting</term>
	    <desc>
	      This boolean value determines whether the server is running in
	      test mode (which may enable extra logging or prevent the server
	      from comm,unicating with live systems etc ... the actual
	      behavior is server dependent).<br />
	      This may be set on the command line or in Control.plist, but
	      may be overridden by using the 'testing' command in the
	      Console program.
	    </desc>
	    <term>EcTransient</term>
	    <desc>
	      This boolean option is used to specify that the program
	      should not be restarted automatically by the Command
	      server if/when it disconnects from that server.
	    </desc>
	  </deflist>
	</subsect>
      </section>
    </chapter>

 */

#import	<Foundation/Foundation.h>

#import	"EcAlarmDestination.h"

@class	NSFileHandle;

typedef enum    {
  LT_DEBUG,             /* Debug message - internal info.       */
  LT_WARNING,           /* Warning - possibly a real problem.   */
  LT_ERROR,             /* Error - needs dealing with.          */
  LT_AUDIT,             /* Not a problem but needs logging.     */
  LT_ALERT,             /* Severe - needs immediate attention.  */
} EcLogType;


/**
 * A 'ping' can be sent from or to any process to check that it is alive.
 * A 'gnip' should be sent in response to each 'ping'
 * Each 'ping' carries a sequence number which should be echoed in its 'gnip'.
 * Optionally, the 'ping' can also transport a serialized property-list
 * to provide additional data or instructions - the value of which is
 * dependent on the program being pinged - normally this value is nil.
 */
@protocol	CmdPing
- (oneway void) cmdGnip: (id <CmdPing>)from
	       sequence: (unsigned)num
		  extra: (in bycopy NSData*)data;
- (oneway void) cmdPing: (id <CmdPing>)from
	       sequence: (unsigned)num
		  extra: (in bycopy NSData*)data;
@end

/** The CmdConfig protocol is needed by objects that send and receive
 * configuarion information.
 */
@protocol	CmdConfig
- (oneway void) requestConfigFor: (id<CmdConfig>)c;
- (oneway void) updateConfig: (in bycopy NSData*)info;
@end

/** Messages that the Command server may send to clients.
 */
@protocol	CmdClient <CmdPing,CmdConfig>
- (oneway void) cmdMesgData: (in bycopy NSData*)dat from: (NSString*)name;
- (oneway void) cmdQuit: (int)status;
@end

/** Messages a Command logging process can be expected to handle.
 */
@protocol	CmdLogger <CmdClient>
- (void) flush;
- (oneway void) logMessage: (NSString*)msg
		      type: (EcLogType)t
                      name: (NSString*)c;
- (oneway void) logMessage: (NSString*)msg
		      type: (EcLogType)t
		       for: (id)o;
- (bycopy NSData*) registerClient: (id)c
			     name: (NSString*)n;
- (void) unregisterByObject: (id)obj;
- (void) unregisterByName: (NSString*)n;
@end

@protocol	Console <NSObject>
- (oneway void) information: (NSString*)txt;
@end

/**
 *	Messages that clients may send to the server.
 *	NB. The 'registerClient...' message must be sent first.
 */
@protocol	Command <CmdLogger,CmdConfig,EcAlarmDestination>
- (oneway void) alarm: (in bycopy EcAlarm*)alarm;
- (oneway void) command: (in bycopy NSData*)dat
		     to: (NSString*)t
		   from: (NSString*)f;
- (bycopy NSData*) registerClient: (id<CmdClient>)c
			     name: (NSString*)n
			transient: (BOOL)t;
- (oneway void) reply: (NSString*)msg
		   to: (NSString*)n
		 from: (NSString*)c;
/** Shut down the Command server and all its clients */
- (oneway void) terminate;
/** An exceptional method and can be used without registering first
 * (ie, can be used by anyone, not only clients of the Command server).
 * It's meant to be used remotely by java servlets, and all sort of
 * software running on the machine and which is *not* a full Command
 * client (ie, a subclass of EcProcess) but which still wants to retrieve
 * configuration from a central location (the Control/Command servers).
 * NB: The configuration might change later on, so you must not cache
 * the configuration after asking for it, but rather ask for it each
 * time your software needs it.
 */
- (bycopy NSData *) configurationFor: (NSString *)name;
@end

/*
 *	Messages that clients may send to the server.
 */
@protocol	Control <CmdPing,CmdConfig,EcAlarmDestination>
- (oneway void) alarm: (in bycopy EcAlarm*)alarm;
- (oneway void) command: (in bycopy NSData*)cmd
		   from: (NSString*)f;
- (oneway void) domanage: (NSString*)name;
- (oneway void) information: (NSString*)msg
		       type: (EcLogType)t
		         to: (NSString*)to
		       from: (NSString*)from;
- (bycopy NSData*) registerCommand: (id<Command>)c
			      name: (NSString*)n;
- (bycopy NSString*) registerConsole: (id<Console>)c
				name: (NSString*)n
				pass: (NSString*)p;
- (oneway void) reply: (NSString*)msg
		   to: (NSString*)n
		 from: (NSString*)c;
- (oneway void) servers: (in bycopy NSData*)a
		     on: (id<Command>)s;
- (oneway void) unmanage: (NSString*)name;
- (void) unregister: (id)o;
@end

/*
 *	Useful functions -
 */
extern void		cmdSetHome(NSString *home);
extern NSString*	cmdLogsDir(NSString *date);
extern NSString*	cmdLogKey(EcLogType t);
extern NSString*	cmdLogName();
extern NSString*	cmdLogFormat(EcLogType t, NSString *fmt);

/* Set/get version/compilation date.
 */
extern NSString*	cmdVersion(NSString *ver);

/**
 *	Command line arguments -
 *
 *
 * <p>On startup, these are taken from the command line, or from the
 * local user defaults database of the person running the program.<br />
 * If the EcEffectiveUser specifies an alternative user, or the
 * program is able to read the database for the 'ecuser' user, then
 * the other values are read from the defaults database of that user.
 * </p>
 * <p>After startup, the command line arguments still take precedence,
 * but values retrieved from the network configuration system will
 * then override any read from the local user defaults database.
 * </p>
 * <p>Settings in the network configuration system will have no effect on
 * the following defaults which are used BEFORE the network configuration
 * can be read.
 * </p>
 * <deflist>
 *   <term>EcDaemon</term>
 *   <desc>To specify whether the program should run in the background
 *     (boolean, YES if the program is to run as a daemon, NO otherwise).<br />
 *     The value in the network configuration has no effect.
 *   </desc>
 *   <term>EcEffectiveUser</term>
 *   <desc>To tell the server to change to being this user on startup.
 *     defaults to 'ecuser', but the default can be overridden by specifying
 *     '-DEC_EFFECTIVE_USER+@"username"' in the local.make make file.<br />
 *     Set a value of '' or '*' to remain whoever runs the program
 *     rather than changing.
 *   </desc>
 *   <term>EcInstance</term>
 *   <desc>To set the program instance ID (an arbitrary string).<br />
 *     If this is specified, the program name has a hyphen and the
 *     id appended to it by the '-initWithDefaults:' method.
 *   </desc>
 * </deflist>
 * <p>The following settings will be revised after startup to include the
 * values from the network configuration system.
 * </p>
 * <deflist>
 *   <term>EcAuditLocal</term>
 *   <desc>A boolean used to specify that audit information should
 *   be logged locally rather than sending it to be logged centrally.<br />
 *   Default value is NO.
 *   </desc>
 *   <term>EcAuditFlush</term>
 *   <desc>A flush interval in seconds (optionally followed by a colon
 *   and a buffer size in KiloBytes) to control flushing of audit logs.<br />
 *   Setting an interval of zero or less disables flushing by timer.<br />
 *   Setting a size of zero or less, disables buffering (so logs are
 *   flushed immediately).
 *   </desc>
 *   <term>EcDebug-XXX</term>
 *   <desc>A boolean used to ensure that the debug mode named 'XXX' is either
 *   turned on or turned off.  The value of 'XXX' must match
 *   the name of a debug mode used by the program!
 *   </desc>
 *   <term>EcDebugLocal</term>
 *   <desc>A boolean used to specify that debug information should
 *   be logged locally rather than sending it to be logged centrally.<br />
 *   Default value is YES.
 *   </desc>
 *   <term>EcDebugFlush</term>
 *   <desc>A flush interval in seconds (optionally followed by a colon
 *   and a buffer size in KiloBytes) to control flushing of debug logs.<br />
 *   Setting an interval of zero or less disables flushing by timer.<br />
 *   Setting a size of zero or less, disables buffering (so logs are
 *   flushed immediately).
 *   </desc>
 *   <term>EcMemory</term>
 *   <desc>A boolean used to ensure that monitoring of memory allocation is
 *   turned on or turned off.
 *   </desc>
 *   <term>EcRelease</term>
 *   <desc>A boolean used to specify whether the program should perform
 *   sanity checks for retain/release combinations.  Slows things down a lot!
 *   </desc>
 *   <term>EcTesting</term>
 *   <desc>A boolean used to specify whether the program is running
 *   in test mode or not.
 *   </desc>
 *   <term>EcWellKnownHostNames</term>
 *   <desc>A dictionary mapping host names/address values to well known
 *   names (the canonical values used by Command and Control).
 *   </desc>
 * </deflist>
 */
@interface EcProcess : NSObject <CmdClient,EcAlarmDestination>

/** Return a short copyright notice ... subclasses should override.
 */
- (NSString*) ecCopyright;

/** Obtain a lock on the shared EcProcess for thread-safe updates to
 * process-wide variables.
 */
- (void) ecDoLock;

/** Release a lock on the shared EcProcess after thread-safe updates to
 * process-wide variables.
 */
- (void) ecUnLock;

/* Call these methods during initialisation of your instance
 * to set up automatic management of connections to servers. 
 * You then access the servers by calling -(id)server: (NSString*)serverName.
 */

- (void) addServerToList: (NSString*)serverName;
- (void) addServerToList: (NSString*)serverName for: (id)anObject;
- (void) removeServerFromList: (NSString*)serverName;


/** Send a SEVERE error message to the server.
 */
- (void) cmdAlert: (NSString*)fmt arguments: (va_list)args;

/** Send a SEVERE error message to the server.
 */
- (void) cmdAlert: (NSString*)fmt, ...;

/** Archives debug log files into the specified subdirectory of the debug
 * logging directory.  If subdir is nil then a subdirectory name corresponding
 * to the current date is generated and that subdirectory is created if
 * necessary.
 */
- (NSString*) cmdArchive: (NSString*)subdir;

/** Send a log message to the server.
 */
- (void) cmdAudit: (NSString*)fmt arguments: (va_list)args;

/** Send a log message to the server.
 */
- (void) cmdAudit: (NSString*)fmt, ...;

/** Handles loss of connection to the server.
 */
- (id) cmdConnectionBecameInvalid: (NSNotification*)notification;

/** Returns the path to the data storage directory used by this process
 * to store files containing persistent information.
 */
- (NSString*) cmdDataDirectory;

/** Send a debug message - as long as the debug mode specified as 'type'
 * is currently set.
 */
- (void) cmdDbg: (NSString*)type msg: (NSString*)fmt arguments: (va_list)args;

/** Send a debug message - as long as the debug mode specified as 'type'
 * is currently set.
 */
- (void) cmdDbg: (NSString*)type msg: (NSString*)fmt, ...;

/** Send a debug message with debug mode 'defaultMode'.
 */
- (void) cmdDebug: (NSString*)fmt arguments: (va_list)args;

/** Send a debug message with debug mode 'defaultMode'.
 */
- (void) cmdDebug: (NSString*)fmt, ...;

/** Called whenever the user defaults are updated due to a central
 * configuration change (or another defaults system change).<br />
 * If you override this to handle configuration changes, don't forget
 * to call the superclass implementation.
 */
- (void) cmdDefaultsChanged: (NSNotification*)n;

/** Send an error message to the server.
 */
- (void) cmdError: (NSString*)fmt arguments: (va_list)args;

/** Send an error message to the server.
 */
- (void) cmdError: (NSString*)fmt, ...;

/** Flush logging information
 */
- (void) cmdFlushLogs;

/** This message returns YES if the receiver is intended to be a client
 * of a Command server, and NO if it is a standalone process which does
 * not need to contact the Command server.<br />
 * The default implementation returns YES, but subclasses may override
 * this method to return NO if they do not wish to contact the Command
 * server.
 */
- (BOOL) cmdIsClient;

/** Returns a fag indicating whether this process is currently connected
 * it its Command server.
 */
- (BOOL) cmdIsConnected;

/** Returns YES is the process is running in test mode, NO otherwise.
 */
- (BOOL) cmdIsTesting;

/** Closes a file handle previously obtained using the -cmdLogFile: method.
 * You should not close a logging handle directly, use this method.
 */
- (void) cmdLogEnd: (NSString*)name;

/** Obtain a file handle for logging purposes.  The file will have the
 * specified name and will be created (if necessary) in the processes
 * logging directory.<br />
 * If there is already a handle for the specified file, this method
 * returns the existing handle rather than creating a new one.<br />
 * Do not close this file handle other than by calling the -cmdLogEnd: method.
 */
- (NSFileHandle*) cmdLogFile: (NSString*)name;

/** Used by the Command server to send messages to your application.
 */
- (void) cmdMesgData: (NSData*)dat from: (NSString*)name;

/** This method is called whenever the Command server sends an instruction
 * for your Command client process to act upon.  Often the command has been
 * entered by an operator and you need to respond with a text string.<br />
 * To implement support for an operator command, you must write a method
 * whose name is of the form -cmdMesgXXX: where XXX is the command (a
 * lowercase string) that the operator will enter.  This method must accept
 * a single NSArray object as an argument and must return a readable string
 * as a result.<br />
 * The array argument will contain the words in the command line entered
 * by the operator (with the command itsself as the first item in the
 * array).<br />
 * There are two special cases ... when the operator types 'help XXX' your
 * method will be called with 'help'as the first element of the array and
 * you should respond with some useful hep text, and when the operator
 * simply wants a short description of what the command does, the array
 * argument will be nil (and your method should respond with a short 
 * description of the cmmand).
 */
- (NSString*) cmdMesg: (NSArray*)msg;

/** Attempt to establish connection to Command server etc.
 * Return a proxy to that server if it is available.
 */
- (id) cmdNewServer;

/** Return dictionary giving info about specified operator.  If the
 * password string matches the password of the operator (or the operator
 * has no password) then the dictionary field @"Password" will be set to
 * @"yes", otherwise it will be @"no".
 * If the named operator does not exist, the method will return nil.
 */
- (NSMutableDictionary*)cmdOperator: (NSString*)name password: (NSString*)pass;

/** Used to tell your application to quit.
 */
- (void) cmdQuit: (int)status;

/** Returns non-zero (a signal) if the process has received a unix signal.
 */
- (int) cmdSignalled;

/** Used to tell your application about configuration changes.
 */
- (void) cmdUpdate: (NSMutableDictionary*)info;




- (void) log: (NSString*)message type: (EcLogType)t;

/** Send a warning message to the server.
 */
- (void) cmdWarn: (NSString*)fmt arguments: (va_list)args;

/** Send a warning message to the server.
 */
- (void) cmdWarn: (NSString*)fmt, ...;

/* Return interval between timeouts.
 */
- (NSTimeInterval) cmdInterval;

- (void) cmdUnregister;
/*
 *	All this to unregister from the server.
 */

/** Register a debug mode 'mode'
 */
- (void) setCmdDebug: (NSString*)mode withDescription: (NSString*)desc;

/* Sets the interval between timeouts.
 */
- (void) setCmdInterval: (NSTimeInterval)interval;

/** Specify a handler method to be invoked after each timeout to let you
 * perform additional tasks.
 */
- (void) setCmdTimeout: (SEL)sel;

/** Specify an object 'obj' to be sent a message 'sel' when the
 * network configuration information for this process has been changed.
 * If 'sel' is a nul selector, then the specified object is removed
 * from the list of objects to be notified.  The EcProces class will
 * retain the object given.
 */
- (void) setCmdUpdate: (id)obj withMethod: (SEL)sel;

/*
 * Trigger a timeout to go off as soon as possible ... subsequent timeouts
 * go off at the normal interval after that one.
 */
- (void) triggerCmdTimeout;

/** Obtains the configuration value for the specified key from the
 * NSUserDefaults system (as modified by the Command server).<br />
 * If you need more than one value, or if you want a typed values,
 * you should call -cmdDefaults to get the defaults object, and then
 * call methods of that object directly.
 */
- (id) cmdConfig: (NSString*)key;

/** Check to see if a debug mode is active.
 */
- (BOOL) cmdDebugMode: (NSString*)mode;

/** Set a particular (named) debug mode to be active or inactive.
 */
- (void) cmdDebugMode: (NSString*)mode active: (BOOL)flag;

/** Returns the NSUserDefaults instance containing the configuration
 * information for this process.
 */
- (NSUserDefaults*) cmdDefaults;

/** Utility method to perform partial (case insensitive) matching of
 * an abbreviated command word (val) to a keyword (key)
 */
- (BOOL) cmdMatch: (NSString*)val toKey: (NSString*)key;

/** Handle with care - this method invokes the cmdMesg... methods.
 */
- (NSString*) cmdMesg: (NSArray*)msg;

/** Retrurns the name by which this process is known to the Command server.
 */
- (NSString*) cmdName;

/** May be used withing cmdMesg... methods to return formatted text to
 * the Console.
 */
- (void) cmdPrintf: (NSString*)fmt arguments: (va_list)args;

/** May be used withing cmdMesg... methods to return formatted text to
 * the Console.
 */
- (void) cmdPrintf: (NSString*)fmt, ...;

/** Should be over-ridden to perform extra tidy up on shutdown of the
 * process - should call [super cmdQuit:...] at the end of the method.
 */
- (void) cmdQuit: (int)status;

/** Used to tell your application about configuration changes (the
 * default implementation merges the configuration change into the
 * NSUserDefaults system and sends the defaults change notification).<br />
 * If you want to deal with configuration changes actively - override
 * this and call [super cmdUpdate:...] to install the changed
 * configuration before anything else.
 * NB.  This method WILL be called before your application is
 * initialised.  Make sure it is safe.
 */
- (void) cmdUpdate: (NSMutableDictionary*)info;

/** [-initWithDefaults:] is the Designated initialiser<br />
 * It adds the defaults specified to the defaults system.
 * It sets the process name to be that specified in the
 * 'EcProgramName' default with an '-id' affix if EcInstance is used
 * to provide an instance id.
 * Moves to the directory (relative to the current user's home directory)
 * given in 'EcHomeDirectory'.
 * If 'EcHomeDirectory' is not present in the defaults system (or is
 * an empty string) then no directory change is done.
 */
- (id) initWithDefaults: (NSDictionary*)defs;

/*
 *	How commands sent to the client via cmdMesg: are invoked -
 *
 *	If a method exists whose name is 'cmdMesgfoo:' where 'foo' is the
 *	command given, then that method is registered when the receiver
 *      is initialised (or -cmdMesgCache is called) and invoked.
 *
 *	The action methods should use the [-cmdPrintf:] method repeatedly to
 *	add text to be returned to the caller.
 *
 *	By default the method 'cmdMesghelp:' is defined to handle the 'help'
 *	command.  To extend the help facility - invoke [super cmdMesghelp:]
 *	at the start of your own implementation.
 *	NB. This method may call any other 'cmdMesg...:' method passing it
 *	an array with the first parameter set to be the string 'help'.
 *	In this case the method should use 'cmdLine:' to return it's help
 *	information.
 *
 *	We also have 'cmdMesgdebug:' to activate debug logging and
 *	'cmdMesgnodebug:' to deactivate it.  The known debug modes may
 *	be extended by using the 'setCmdDebug:withDescription:' method.
 *
 *	'cmdMesgmemory:' is for reporting process memory allocation stats -
 *	it should be overridden to give detailed info.
 *
 *	'cmdMesgstatus:' is for reporting process status information and
 *	should be overridden to give detailed info.
 *
 *	'cmdMesgarchive:' forces an archive of the debug log.
 */
- (void) cmdMesgCache;
- (void) cmdMesgarchive: (NSArray*)msg;
- (void) cmdMesgdebug: (NSArray*)msg;
- (void) cmdMesghelp: (NSArray*)msg;
- (void) cmdMesgmemory: (NSArray*)msg;
- (void) cmdMesgnodebug: (NSArray*)msg;
- (void) cmdMesgstatus: (NSArray*)msg;

/*
 * Returns a proxy object to a[n automatically managed] server
 */
- (id) server: (NSString *)serverName;

/*
 * Like server:, but if the configuration contains a multiple servers,
 * this tries to locate the specific server that is set up to deal with
 * users where the last two digits of the phone number are as specified.
 */
- (id) server: (NSString *)serverName forNumber: (NSString*)num;

/*
 * Standard servers return NO to the following.  But if we are using 
 * a multiple/broadcast server, this returns YES.
 */
- (BOOL) isServerMultiple: (NSString *)serverName;

/** Records the timestamp of the latest significant input for this process.
 * If when is nil the current timestmp is used.
 */
- (void) ecHadIP: (NSDate*)when;

/** Records the timestamp of the latest significant output for this process.
 * If when is nil the current timestmp is used.
 */
- (void) ecHadOP: (NSDate*)when;

/** Called on the first timeout of a new day.<br />
 * The argument 'when' is the timestamp of the timeout.
 */
- (void) ecNewDay: (NSCalendarDate*)when;

/** Called on the first timeout of a new hour.<br />
 * The argument 'when' is the timestamp of the timeout.
 */
- (void) ecNewHour: (NSCalendarDate*)when;

/** Called on the first timeout of a new minute.<br />
 * The argument 'when' is the timestamp of the timeout.
 */
- (void) ecNewMinute: (NSCalendarDate*)when;

/** Return heap memory known not to be leaked ... for use in internal
 * monitoring of memory usage.  You should override this ti add in any
 * heap store you have used and know is not leaked.
 */
- (NSUInteger) ecNotLeaked;

/** Establishes the receiver as a DO server and runs the runloop.<br />
 * Returns zero when the run loop completes.<br />
 * Returns one (immediately) if the receiver is transent.<br />
 * Returns two if unable to register as a DO server.
 */
- (int) ecRun;

@end

@interface NSObject (RemoteServerDelegate)
- (void) cmdMadeConnectionToServer: (NSString *)serverName;
- (void) cmdLostConnectionToServer: (NSString *)serverName;
@end

extern EcProcess	*EcProc;	/* Single instance or nil */

extern	NSString*	cmdConnectDbg;	/* Debug connection attempts.	*/
extern	NSString*	cmdDefaultDbg;	/* Debug normal stuff.		*/
extern	NSString*	cmdDetailDbg;	/* Debug stuff in more detail.	*/


#endif /* INCLUDED_ECPROCESS_H */
