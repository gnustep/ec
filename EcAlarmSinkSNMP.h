
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

#import "EcAlarmDestination.h"

/** <p>The EcAlarmSinkSNMP class implements an alarm destination which
 * terminates a chain of destinations by delivering alarms to an SNMP
 * monitoring system rather than forwarding them to another EcAlarmDestination
 * object.
 * </p>
 * <p>The SNMP functionality of the EcAlarmSinkSNMP is essentially to maintain
 * a table of active alarms and to send out traps indicating changes of
 * state of that table as follows:
 * </p>
 * <p>Alarms in the table are each identified by a unique numeric identifier,
 * the 'notificationID' and traps concerning the alarms carry that ID.<br />
 * For each alarm trap sent out, there is a corresponding trap sent when
 * the alarm is cleared and removed from the table.  The clear trap carries
 * the same notification identifier as that of the alarm being cleared, and
 * the pair (alarm/clear) is known as a correlation.<br />
 * A clear trap is never sent without a corresponding alarm trap having first
 * been sent.<br />
 * Each trap carries a sequence number so that the SNMP manager is able to
 * detect lost traps.
 * </p>
 * <p>For purposes of establishing a correlation between any alarms coming
 * in to the system, the managed object, event type, specific problem,
 * and probable cause values must be the same.  When this occurs, any
 * matching alarms are given the same notification identifier as the first
 * alarm.<br />
 * When an alarm is added to the table, only one trap will to notify about it,
 * and no further traps will be sent for any correlated alarms arriving
 * unless those alarms have new perceived severity values.<br />
 * If an alarm changes its severity, a trap will be sent to clear the
 * alarm (removing it from the table) and the alarm with new severity will
 * be added to the table and its trap sent.
 * </p>
 * <p>To allow an SNMP manager to resynchronize with the agent, the manager
 * may examine the table of active alarms.  This may be needed where there
 * is an agent error, manager error, or loss of connectivity/traps (jumps
 * in the trap sequence number).<br />
 * The entries in the table contain all the same information as the alarm
 * traps, apart from the trap sequence number.
 * </p>
 * <p>After a crash/shutdown and subsequent start-up of the agent, the
 * active alarm table is updated with the current situation of the system
 * before the manager is able to respond to the coldstart (see RFC 1157).
 * When the manager receives the agent's coldstart it may being a
 * resynchronization process gathering alarms related to the current
 * situation of the system by examining the alarm table.<br />
 * There is a resync flag variable which indicates whether a resynchronization
 * process is being carried out or not (set to 1 if resync is in progress,
 * 0 otherwise). Before sending a trap, the variable is checked to know
 * whether the resynchronization process is active or not. The traps will
 * only be sent to the manager if there is no resync in progress, otherwise
 * they will be deferred until the resync has completed.<br />
 * The manager may therefore set the resync flag to 1, read the contents of
 * the active alarms table, and then set the resync flag to zero to resume
 * active operation.<br />
 * As a safety measure to protect against manager failure, the resync flag
 * is automatically reset to zero if it is left set to 1 for more than five
 * minutes.
 * </p> 
 * <p>In addition to the traps and the alarms table, a table of managed
 * objects is also maintained.  The system guarantees that any managed object
 * referred to in a trap is present in the table before the trap is sent.
 * </p>
 * <p>In order for the manager to know that the agent is running, a heartbeat
 * trap is sent periodically.  The heartbeat contains a notification
 * identifier of zero (never used other than for a heartbeat).<br />
 * A poll heartbeat interval variable is provided to allow the manager to
 * control the time between heartbeats (in minutes) and may be set to a
 * positive integer value, or queried.
 * </p>
 * <p>The class works by connecting to an SNMP agent using the Agent-X
 * protocol, and registering as the 'owner' of various OIDs in an SNMP MIB
 * so that SNMP requests made to the agent for those OIDs are forwarded to
 * the EcAlarmSinkSNMP, and so that the EcAlarmSinkSNMP can send SNMP 'traps'
 * via the agent.<br />
 * To do this, the agent must be configured to accept incoming Agent-X
 * connections from the host on which the EcAlarmSinkSNMP is running, and the
 * alarm sink object must be initialized using the -initWithHost:name: method
 * to specify the host and port on which the agent is listening.<br />
 * If the EcAlarmSinkSNMP object is initialized without a specific host and name
 * then it assumes that the agent is running on localhost and the standard
 * Agent-X tcp/ip port (705).
 * </p>
 * <p>To configure a net-snmp agent to work with this software you need to:
 * </p>
 * Edit /etc/snmp/snmpd.conf to get it to send traps to snmptrapd ...
 * <example>
 * rwcommunity     public
 * trap2sink       localhost public
 * </example>
 * and to accept agentx connections via tcp ...
 * <example>
 * agentxsocket    tcp:localhost:705
 * master          agentx
 * </example>
 * Then restart with '/etc/rc.d/init.d/snmpd restart'
 *
 * <p>All alarming is done a based on three OIDs which may be defined
 * within the user defaults system.  The EcAlarmSinkSNMP instance is
 * responsible for managing those OIDs (and anything below them in the
 * OID hierarchy).<br />
 * By default the OIDs used are those specified in the GNUstep MIB
 * (GNUSTEP-MIB.txt), but you may override them as specified below:
 * </p>
 * <deflist>
 *   <term>AlarmsOID</term>
 *   <desc>All SNMP alarm data is in a fixed structure relative to this
 *   OID in the MIB.<br />
 *   The table of current alarms is at the OID 1 relative to AlarmsOID,
 *   so you can interrogate the table using;
 *   <example>snmpwalk -v 1 -c public localhost {AlarmsOID}.1
 *   </example>
 *   The resync flag is at OID 2 relative to AlarmsOID and can be queried
 *   or set using:
 *   <example>snmpget -v 1 -c public localhost {AlarmsOID}.2.0
 *   </example>
 *   <example>snmpset -v 1 -c public localhost {AlarmsOID}.2.0 i 1
 *   </example>
 *   The current trap sequence number is at OID 3 relative to AlarmsOID
 *   and can be queried using:
 *   <example>snmpget -v 1 -c public localhost {AlarmsOID}.3.0
 *   </example>
 *   The heartbeat poll interval is at OID 4 relative to AlarmsOID
 *   and can be queried or set using:
 *   <example>snmpget -v 1 -c public localhost {AlarmsOID}.4.0
 *   </example>
 *   <example>snmpset -v 1 -c public localhost {AlarmsOID}.4.0 i 5
 *   </example>
 *   </desc>
 *   <term>ObjectsOID</term>
 *   <desc>All SNMP managed object values are in a table relative to this
 *   OID in the MIB.<br />
 *   SNMP tools are able to interrogate the table at this OID to see which
 *   managed objects are currently registered:
 *   <example>snmpwalk -v 1 -c public localhost {ObjectsOID}
 *   </example>
 *   </desc>
 *   <term>TrapOID</term>
 *   <desc>The definition of the trap which carries alarms to any monitoring
 *   system is at this OID.
 *   </desc>
 * </deflist>
 * <p>Each of these OID strings must be a representation of an OID in the
 * integer dotted format (eg. 1.3.6.1.4.1.37374.3.0.1).
 * </p>
 */
@interface	EcAlarmSinkSNMP : EcAlarmDestination

/** <p>Returns the singleton alarm sink instance.<br />
 * This instance is the link between the Objective-C world and the net-snmp
 * world which runs in a separate thread.  You should stop the SNMP system
 * by calling -shutdown before process termination.
 * </p>
 * <p>If the agent is on another host and/or is using a non-standard port,
 * you need to call -initWithHost:name: before and/or instead of calling
 * this method.
 * </p>
 */
+ (EcAlarmSinkSNMP*) alarmSinkSNMP;

/** <p>Overrides the default behavior to specify a host and name for the
 * SNMP agent this instance is to connect to.<br />
 * The host must be the machine the agent is running on and the name must
 * be the tcp/ip port on which that agent is listening for Agent-X connections.
 * </p>
 * <p>If an instance has already been created/initialized, this method returns
 * the existing instance and its arguments are ignored.
 * </p>
 */
- (id) initWithHost: (NSString*)host name: (NSString*)name;

@end

