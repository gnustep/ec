
/** Enterprise Control Configuration and Logging

   Copyright (C) 2013 Free Software Foundation, Inc.

   Written by: Richard Frith-Macdonald <rfm@gnu.org>
   Date: April 2013
   Originally developed from 1996 to 2013 by Brainstorm, and donated to
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



    <chapter>
      <p>The index below lists the major components of the ECCL 
         documentation.<br/></p>
      <index type="title" scope="project" target="mainFrame" />
      <section>
        <heading>Enterprise Control Configuration and Logging</heading>
        <p>
          Classes and tools for building and administering 24*7
          server processes for large scale software systems.
        </p>
      </section>

      <section>
        <heading>The Control command line tool</heading>
        <p>Based around the [EcControl] class, this server process provides
          a central command/control point and acts as the SNMP agent for
          integration of a cluster of Objective-C based processes.
        </p> 
      </section>

      <section>
        <heading>The Command command line tool</heading>
        <p>Based around the [EcCommand] class, this server process provides
          the configuration/logging/launch facilities for all processes on
          a single machine.  It obtains centralised configuration from the
          Control server and sends logging, alerts and alarms to that server.
        </p> 
      </section>

      <section>
        <heading>The Console command line tool</heading>
        <p>Based around the [EcConsole] class, this process provides an
          interactive command-line based interface for controlling the
          entire system via the Control server.<br />
          It may also be used in a non-interactive mode to send commands to
          any process and wait for responses.  In non-interactive mode the
          tool uses the following additional
          command-line-arguments/user-default-keys and/or
          environment variables:
        </p> 
        User (or the ConsoleUser environment variable) specifies the
        user for whom the tool is performing an action.<br />
        Pass (or the ConsolePass environment variable) specifies the
        password for the user login to the Control server.<br />
        Line (or the ConsoleLine environment variable) specifies the
        command line to be used (as if type in interactively).
        If the command line is sent, the process exit status is 0, but
        if a failure occurs the status is 1 (except as noted below).<br />
        Wait (or the ConsoleWait environment variable) specifies the
        number of seconds to wait for the result of the command.
        If this timeout occurs, the process exit status is 2.<br />
        Want (or the ConsoleWant environment variable) specifies the
        regular expression to match a single line success response to the
        command.<br />
        Fail (or the ConsoleFail environment variable) specifies the regular
        expression to match a single line failure response to the command.
        If this response is matched, the process exit status is 3.<br />
        Quiet (or the ConsoleQuiet environment variable) is a boolean
        which, if true, will suppress any output while waiting for a
        response.
      </section>

      <section>
        <heading>The AlarmTool command line tool</heading>
        <p>The AlarmTool command line tool provides a mechanism to raise and
          clear alarms (using the ECCL alarm system) from a process which is
          not itsself ECCL enabled (ie not built using the ECCL classes).<br />
          You may use this to generate logging from shell scripts
          or from Java servlets etc.
        </p>
        <p>The tool requires at least four (usually six) arguments:<br />
          '-Cause NN' the probable cause of the alarm (type of problem).<br />
          '-Component NN' the component which raised the alarm.<br />
          '-Problem NN' the specific problem which raised the alarm.<br />
          '-Process NN' the name of the process which raised the alarm.<br />
          '-Repair NN' a proposed repair action to fix the issue.<br />
          '-Severity NN' the severity of the problem (defaults to 'cleared',
          in which case the Repair action is not required).<br />
        </p>
      </section>

      <section>
        <heading>The LogTool command line tool</heading>
        <p>The LogTool command line tool provides a mechanism to log various
          types of messages (using the ECCL logging system) from a process
          which is not itsself ECCL enabled (ie not built using the ECCL
          classes).  You may use this to generate logging from shell scripts
          or from Java servlets etc.
        </p>
        <p>The tool requires at least two arguments:<br />
          '-Name XXX' specifies the name under which the message is to be logged
          and<br />
          '-Mesg XXX' specifies the content of the message to be logged.<br />
          The optional '-Mode XXX' argument specifies the type of log to be
          generated (one of Audit, Debug, Warn, Error or Alert) and defaults
          to generating a 'Warn' log.
        </p>
      </section>

      <section>
        <heading>The Terminate command line tool</heading>
        <p>The Terminate command line tool provides a mechanism to shut down
          an ECCL host.  This tool contacts a Command server and tells it to
          shut down all it's local client process and the shut itsself down.
        </p>
        <p>You may use '-CommandHost' and '-CommandName' to specify a Command
          server to contact, otherwise the default local Command server is
          contacted (or if there is no local server, any available Command
          server on the local network is contacted).
        </p>
        <p>If you wish to terminate everything in a cluster, you may use the
          '-CommandName' argument to specify the name of the 'Control'
          server of the cluster rather than the 'Command' server of an
          individual host.  In this case the tool will contact the Control
          server, and the Control server will in turn send a terminate
          message to each Command server in the cluster, before closing
          down itsself.
        </p>
      </section>

    </chapter>
 */

#ifndef INCLUDED_ECCL_H
#define INCLUDED_ECCL_H

#import	<ECCL/EcAlarm.h>
#import	<ECCL/EcAlarmDestination.h>
#import	<ECCL/EcAlarmSinkSNMP.h>
#import	<ECCL/EcAlerter.h>
#import	<ECCL/EcBroadcastProxy.h>
#import	<ECCL/EcHost.h>
#import	<ECCL/EcLogger.h>
#import	<ECCL/EcProcess.h>
#import	<ECCL/EcUserDefaults.h>

#endif
