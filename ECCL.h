
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
        <p>You may use -CommandHost and -CommandName to specify a Command
          server to contact, otherwise the default local Command server is
          contacted (or if there is no local server, any available Command
          server on the local network is contacted).
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
